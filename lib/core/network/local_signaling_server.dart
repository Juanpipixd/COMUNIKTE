import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Servidor Embebido de Señalización WebSocket para Redes Locales / Hotspot Wi-Fi.
///
/// Cumple con la especificación 2 de COMUNIKTE:
/// "Fallback / Redes Inestables: Preparado para conmutación a TURN o redes locales
/// (Wi-Fi Direct / Hotspot) en zonas sin cobertura celular."
///
/// Permite que un teléfono actúe como anfitrión (Host) de señalización sin requerir
/// conexión a Internet ni datos móviles.
class LocalSignalingServer extends ChangeNotifier {
  HttpServer? _server;
  final Map<String, Set<WebSocket>> _roomClients = {};
  int _port = 8080;
  String _hostIp = '127.0.0.1';
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  int get port => _port;
  String get hostIp => _hostIp;
  String get serverUrl => 'ws://$_hostIp:$_port';

  /// Inicia el servidor WebSocket en la interfaz de red local.
  Future<bool> startServer({int port = 8080}) async {
    if (_isRunning) return true;
    _port = port;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _isRunning = true;

      // Obtener IP local (normalmente 192.168.43.1 en Hotspot Android)
      await _detectLocalIp();

      _server!.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          _handleWebSocket(socket);
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.text
            ..write('COMUNIKTE Local Hotspot Signaling Server OK')
            ..close();
        }
      });

      debugPrint('[LocalSignalingServer] Servidor iniciado en $serverUrl');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[LocalSignalingServer] Error iniciando servidor local: $e');
      _isRunning = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            _hostIp = addr.address;
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('[LocalSignalingServer] No se pudo resolver IP local: $e');
      _hostIp = '192.168.43.1'; // IP estándar de Hotspot
    }
  }

  void _handleWebSocket(WebSocket socket) {
    String? currentRoom;

    socket.listen(
      (message) {
        try {
          final data = jsonDecode(message.toString()) as Map<String, dynamic>;
          final type = data['type'] as String?;
          final roomId = data['roomId'] as String?;

          if (roomId == null) return;
          currentRoom = roomId;

          if (type == 'join') {
            _roomClients.putIfAbsent(roomId, () => <WebSocket>{}).add(socket);
            debugPrint('[LocalSignalingServer] Cliente unido a sala $roomId (Total: ${_roomClients[roomId]!.length})');

            // Notificar a otros pares en la sala
            _broadcastToRoom(roomId, jsonEncode({
              'type': 'peer_joined',
              'roomId': roomId,
              'peerId': data['clientId'] ?? 'companion',
            }), exclude: socket);
          } else if (type == 'ping') {
            // Responder pong para medición de latencia
            socket.add(jsonEncode({
              'type': 'pong',
              'timestamp': data['timestamp'],
            }));
          } else {
            // Reenviar mensajes SDP (offer, answer, candidate, leave) a los demás
            _broadcastToRoom(roomId, message.toString(), exclude: socket);
          }
        } catch (e) {
          debugPrint('[LocalSignalingServer] Error procesando mensaje WS: $e');
        }
      },
      onDone: () {
        if (currentRoom != null && _roomClients.containsKey(currentRoom)) {
          _roomClients[currentRoom]!.remove(socket);
          _broadcastToRoom(currentRoom!, jsonEncode({
            'type': 'peer_left',
            'roomId': currentRoom,
          }));
          if (_roomClients[currentRoom]!.isEmpty) {
            _roomClients.remove(currentRoom);
          }
        }
      },
      onError: (err) {
        debugPrint('[LocalSignalingServer] Error en socket: $err');
      },
    );
  }

  void _broadcastToRoom(String roomId, String message, {WebSocket? exclude}) {
    final clients = _roomClients[roomId];
    if (clients == null) return;

    for (final client in clients) {
      if (client != exclude && client.readyState == WebSocket.open) {
        try {
          client.add(message);
        } catch (_) {}
      }
    }
  }

  /// Detiene el servidor y cierra todas las conexiones activas.
  Future<void> stopServer() async {
    for (final clients in _roomClients.values) {
      for (final socket in clients) {
        await socket.close();
      }
    }
    _roomClients.clear();

    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    notifyListeners();
    debugPrint('[LocalSignalingServer] Servidor detenido.');
  }

  @override
  void dispose() {
    stopServer();
    super.dispose();
  }
}
