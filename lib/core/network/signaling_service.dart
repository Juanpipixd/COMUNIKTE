import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum SignalingStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Servicio de Señalización Híbrido para Intercomunicador P2P WebRTC (COMUNIKTE).
///
/// Soporta dos modos automáticos:
/// 1. NUBE GLOBAL (MQTT Pub/Sub): Permite enlace por datos móviles (4G/5G) o Wi-Fi
///    mediante brokers MQTT de alta disponibilidad sin requerir servidor propio.
/// 2. MODO RURAL / HOTSPOT (WebSocket Local): Permite enlace en carretera sin cobertura
///    mediante el microservidor local integrado (ws://192.168.43.1:8080).
class SignalingService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;
  MqttServerClient? _mqttClient;
  StreamSubscription? _mqttSubscription;
  Timer? _pingTimer;

  SignalingStatus _status = SignalingStatus.disconnected;
  String? _currentRoomId;
  String? _clientId;
  int _latencyMs = 0;

  SignalingStatus get status => _status;
  String? get currentRoomId => _currentRoomId;
  String? get clientId => _clientId;
  int get latencyMs => _latencyMs;

  // Callbacks de señalización WebRTC
  Function(RTCSessionDescription)? onRemoteOffer;
  Function(RTCSessionDescription)? onRemoteAnswer;
  Function(RTCIceCandidate)? onRemoteCandidate;
  Function(String peerId)? onPeerJoined;
  Function(String peerId)? onPeerLeft;

  /// Conecta al canal de señalización e ingresa a la sala.
  /// Si [serverUrl] comienza con ws:// o wss:// usa WebSocket (modo Hotspot).
  /// En caso contrario, usa la red Cloud MQTT.
  Future<void> connectAndJoinRoom({
    required String serverUrl,
    required String roomId,
    required String clientId,
  }) async {
    _pingTimer?.cancel();
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _channel?.sink.close();
    _channel = null;
    _mqttSubscription?.cancel();
    _mqttSubscription = null;
    _mqttClient?.disconnect();
    _mqttClient = null;

    _currentRoomId = roomId;
    _clientId = clientId;
    _status = SignalingStatus.connecting;
    notifyListeners();

    final isWs = serverUrl.startsWith('ws://') || serverUrl.startsWith('wss://');

    if (isWs) {
      await _connectWebSocket(serverUrl, roomId, clientId);
    } else {
      await _connectMqttCloud(roomId, clientId);
    }
  }

  Future<void> _connectWebSocket(String serverUrl, String roomId, String clientId) async {
    try {
      final uri = Uri.parse(serverUrl);
      _channel = WebSocketChannel.connect(uri);

      _wsSubscription = _channel!.stream.listen(
        _onMessageReceived,
        onError: (error) {
          debugPrint('[SignalingService WS] Error: $error');
          _status = SignalingStatus.error;
          notifyListeners();
        },
        onDone: () {
          debugPrint('[SignalingService WS] Desconectado.');
          _status = SignalingStatus.disconnected;
          notifyListeners();
        },
      );

      _status = SignalingStatus.connected;
      notifyListeners();

      _send({
        'type': 'peer_joined',
        'roomId': roomId,
        'senderId': clientId,
        'peerId': clientId,
      });

      _startLatencyPing();
    } catch (e) {
      debugPrint('[SignalingService WS] Excepción conectando: $e');
      _status = SignalingStatus.error;
      notifyListeners();
    }
  }

  Future<void> _connectMqttCloud(String roomId, String clientId) async {
    try {
      final broker = 'broker.emqx.io';
      final uniqueId = 'rider_${DateTime.now().millisecondsSinceEpoch}_$clientId';
      final client = MqttServerClient(broker, uniqueId);

      client.port = 1883;
      client.logging(on: false);
      client.keepAlivePeriod = 30;
      client.autoReconnect = true;

      final conn = await client.connect();
      if (conn?.state == MqttConnectionState.connected) {
        _mqttClient = client;
        final topic = 'comunikte/rooms/$roomId';
        client.subscribe(topic, MqttQos.atLeastOnce);

        _mqttSubscription = client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> c) {
          final recMess = c[0].payload as MqttPublishMessage;
          final pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
          _onMessageReceived(pt);
        });

        _status = SignalingStatus.connected;
        notifyListeners();

        // Notificar a otros miembros en la sala que entramos
        _send({
          'type': 'peer_joined',
          'roomId': roomId,
          'senderId': clientId,
          'peerId': clientId,
        });

        _startLatencyPing();
        debugPrint('[SignalingService MQTT] Conectado exitosamente a sala $roomId');
      } else {
        debugPrint('[SignalingService MQTT] Falló conexión: ${conn?.state}');
        _status = SignalingStatus.error;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[SignalingService MQTT] Error conectando: $e');
      _status = SignalingStatus.error;
      notifyListeners();
    }
  }

  /// Envía la oferta SDP (Offer) al compañero remoto.
  void sendOffer(RTCSessionDescription offer) {
    _send({
      'type': 'offer',
      'roomId': _currentRoomId,
      'senderId': _clientId,
      'sdp': offer.sdp,
      'sdpType': offer.type,
    });
  }

  /// Envía la respuesta SDP (Answer) al compañero remoto.
  void sendAnswer(RTCSessionDescription answer) {
    _send({
      'type': 'answer',
      'roomId': _currentRoomId,
      'senderId': _clientId,
      'sdp': answer.sdp,
      'sdpType': answer.type,
    });
  }

  /// Envía un candidato ICE para la conectividad STUN/P2P.
  void sendCandidate(RTCIceCandidate candidate) {
    _send({
      'type': 'candidate',
      'roomId': _currentRoomId,
      'senderId': _clientId,
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    });
  }

  /// Procesa los mensajes JSON entrantes de la señalización.
  void _onMessageReceived(dynamic message) {
    try {
      final Map<String, dynamic> data = jsonDecode(message.toString());
      final type = data['type'] as String?;
      final senderId = data['senderId'] as String?;

      // Ignorar mensajes enviados por nosotros mismos
      if (senderId != null && senderId == _clientId) return;

      switch (type) {
        case 'peer_joined':
          final peerId = data['peerId'] as String? ?? 'companion';
          debugPrint('[SignalingService] Compañero conectado: $peerId');
          onPeerJoined?.call(peerId);
          break;

        case 'peer_left':
          final peerId = data['peerId'] as String? ?? 'companion';
          debugPrint('[SignalingService] Compañero desconectado: $peerId');
          onPeerLeft?.call(peerId);
          break;

        case 'offer':
          final sdp = data['sdp'] as String;
          final sdpType = data['sdpType'] as String;
          onRemoteOffer?.call(RTCSessionDescription(sdp, sdpType));
          break;

        case 'answer':
          final sdp = data['sdp'] as String;
          final sdpType = data['sdpType'] as String;
          onRemoteAnswer?.call(RTCSessionDescription(sdp, sdpType));
          break;

        case 'candidate':
          final candMap = data['candidate'] as Map<String, dynamic>;
          final candidate = RTCIceCandidate(
            candMap['candidate'] as String?,
            candMap['sdpMid'] as String?,
            candMap['sdpMLineIndex'] as int?,
          );
          onRemoteCandidate?.call(candidate);
          break;

        case 'ping':
          _send({
            'type': 'pong',
            'roomId': _currentRoomId,
            'senderId': _clientId,
            'timestamp': data['timestamp'],
          });
          break;

        case 'pong':
          final timestamp = data['timestamp'] as int?;
          if (timestamp != null) {
            final now = DateTime.now().millisecondsSinceEpoch;
            _latencyMs = (now - timestamp).clamp(10, 999);
            notifyListeners();
          }
          break;
      }
    } catch (e) {
      debugPrint('[SignalingService] Error procesando payload de señalización: $e');
    }
  }

  void _send(Map<String, dynamic> payload) {
    if (_status != SignalingStatus.connected) return;

    try {
      final jsonStr = jsonEncode(payload);

      if (_mqttClient != null && _mqttClient!.connectionStatus?.state == MqttConnectionState.connected) {
        final builder = MqttClientPayloadBuilder();
        builder.addString(jsonStr);
        final topic = 'comunikte/rooms/$_currentRoomId';
        _mqttClient!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      } else if (_channel != null) {
        _channel!.sink.add(jsonStr);
      }
    } catch (e) {
      debugPrint('[SignalingService] Error enviando mensaje: $e');
    }
  }

  void _startLatencyPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_status == SignalingStatus.connected) {
        _send({
          'type': 'ping',
          'roomId': _currentRoomId,
          'senderId': _clientId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  /// Desconecta y limpia recursos de la sala.
  Future<void> disconnect() async {
    _pingTimer?.cancel();
    _pingTimer = null;

    if (_currentRoomId != null && _clientId != null) {
      _send({
        'type': 'peer_left',
        'roomId': _currentRoomId,
        'senderId': _clientId,
        'peerId': _clientId,
      });
    }

    await _wsSubscription?.cancel();
    _wsSubscription = null;
    await _channel?.sink.close();
    _channel = null;

    await _mqttSubscription?.cancel();
    _mqttSubscription = null;
    _mqttClient?.disconnect();
    _mqttClient = null;

    _status = SignalingStatus.disconnected;
    _currentRoomId = null;
    _latencyMs = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
