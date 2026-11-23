import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum SignalingStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Servicio de Señalización para Intercomunicador P2P WebRTC (COMUNIKTE).
/// Maneja la negociación SDP (Offer / Answer) y candidatos ICE mediante WebSocket
/// con soporte para servidores remotos o Hotspot Local sin cobertura celular.
class SignalingService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
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

  /// Conecta al servidor de señalización (WebSocket) e ingresa a la sala.
  /// En modo rural/montaña puede especificarse la IP local del Hotspot Wi-Fi (ej. ws://192.168.43.1:8080).
  Future<void> connectAndJoinRoom({
    required String serverUrl,
    required String roomId,
    required String clientId,
  }) async {
    _currentRoomId = roomId;
    _clientId = clientId;
    _status = SignalingStatus.connecting;
    notifyListeners();

    try {
      final uri = Uri.parse(serverUrl);
      _channel = WebSocketChannel.connect(uri);

      _subscription = _channel!.stream.listen(
        _onMessageReceived,
        onError: (error) {
          debugPrint('[SignalingService] Error en WebSocket: $error');
          _status = SignalingStatus.error;
          notifyListeners();
        },
        onDone: () {
          debugPrint('[SignalingService] WebSocket desconectado.');
          _status = SignalingStatus.disconnected;
          notifyListeners();
        },
      );

      _status = SignalingStatus.connected;
      notifyListeners();

      // Enviar solicitud de unirse a la sala
      _send({
        'type': 'join',
        'roomId': roomId,
        'clientId': clientId,
      });

      _startLatencyPing();
    } catch (e) {
      debugPrint('[SignalingService] Excepción conectando: $e');
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
    if (_channel != null && _status == SignalingStatus.connected) {
      try {
        _channel!.sink.add(jsonEncode(payload));
      } catch (e) {
        debugPrint('[SignalingService] Error enviando mensaje: $e');
      }
    }
  }

  void _startLatencyPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_status == SignalingStatus.connected) {
        _send({
          'type': 'ping',
          'roomId': _currentRoomId,
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
        'type': 'leave',
        'roomId': _currentRoomId,
        'clientId': _clientId,
      });
    }

    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;

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
