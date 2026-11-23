import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../core/audio/audio_routing_service.dart';
import '../../../core/audio/gain_controller.dart';
import '../../../core/network/signaling_service.dart';

enum IntercomState {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,
  error,
}

enum MicMode {
  openMic,    // Micrófono abierto continuo (Hands-Free)
  pushToTalk, // Pulsar para hablar (PTT)
}

/// Orquestador WebRTC de MediaStream y PeerConnection para COMUNIKTE.
///
/// Implementa:
/// - Códec de voz Opus con supresión de eco acústico (AEC), filtro paso alto
///   y supresión de ruido de viento de motocicleta.
/// - Conexión P2P directa vía STUN (Google STUN) con latencia < 80ms.
/// - Enlace con [GainController] para amplificación independiente PCM.
/// - Enlace con [AudioRoutingService] para Bluetooth SCO y Audio Duck/Mix.
class WebRtcIntercomEngine extends ChangeNotifier {
  final SignalingService signalingService;
  final AudioRoutingService audioRoutingService;
  final GainController gainController;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  IntercomState _state = IntercomState.idle;
  MicMode _micMode = MicMode.openMic;
  bool _isMicMuted = false;
  bool _isPttPressed = false;
  String? _connectedPeerId;

  IntercomState get state => _state;
  MicMode get micMode => _micMode;
  bool get isMicMuted => _isMicMuted;
  bool get isPttPressed => _isPttPressed;
  String? get connectedPeerId => _connectedPeerId;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  // Configuración de Servidores STUN/TURN (Punto 2)
  static final Map<String, dynamic> _rtcConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  WebRtcIntercomEngine({
    required this.signalingService,
    required this.audioRoutingService,
    required this.gainController,
  }) {
    _bindSignalingEvents();
  }

  void _bindSignalingEvents() {
    signalingService.onPeerJoined = _handlePeerJoined;
    signalingService.onPeerLeft = _handlePeerLeft;
    signalingService.onRemoteOffer = _handleRemoteOffer;
    signalingService.onRemoteAnswer = _handleRemoteAnswer;
    signalingService.onRemoteCandidate = _handleRemoteCandidate;
  }

  /// Inicia el motor de intercomunicador: captura micrófono local y configura WebRTC.
  Future<void> startIntercom() async {
    _state = IntercomState.connecting;
    notifyListeners();

    try {
      // 1. Inicializar sesión de audio y canal SCO para casco
      await audioRoutingService.initializeAudioPipeline();

      // 2. Captura de audio optimizada para intercomunicador de moto (Opus + AEC + NS)
      final mediaConstraints = <String, dynamic>{
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'highpassFilter': true,
          'googEchoCancellation': true,
          'googAutoGainControl': true,
          'googNoiseSuppression': true,
          'googHighpassFilter': true,
        },
        'video': false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

      // Si el modo es PTT, mantener silenciado inicialmente
      if (_micMode == MicMode.pushToTalk) {
        _setMicTransmission(false);
      } else {
        _setMicTransmission(!_isMicMuted);
      }

      // 3. Crear RTCPeerConnection
      await _createPeerConnection();

      // Si ya hay señalización conectada, avisamos que estamos listos
      debugPrint('[WebRtcIntercomEngine] Motor de intercomunicador listo.');
    } catch (e) {
      debugPrint('[WebRtcIntercomEngine] Error iniciando intercom: $e');
      _state = IntercomState.error;
      notifyListeners();
    }
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_rtcConfiguration);

    // Agregar tracks locales
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }

    // Escuchar tracks entrantes de la voz remota
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'audio') {
        debugPrint('[WebRtcIntercomEngine] Track de audio remoto recibido.');
        _remoteStream = event.streams.isNotEmpty ? event.streams[0] : null;

        // VINCULAR AL CONTROLADOR DE GANANCIA POR SOFTWARE (Punto 1.3)
        gainController.attachRemoteAudioTrack(event.track);

        _state = IntercomState.connected;
        notifyListeners();
      }
    };

    // Candidatos ICE generados localmente
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        signalingService.sendCandidate(candidate);
      }
    };

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[WebRtcIntercomEngine] PeerConnection State: $state');
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _state = IntercomState.connected;
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          _state = IntercomState.connecting;
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _state = IntercomState.reconnecting;
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _state = IntercomState.error;
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _state = IntercomState.disconnected;
          break;
        default:
          break;
      }
      notifyListeners();
    };
  }

  /// Cuando un nuevo compañero se une a la sala, creamos la Oferta SDP.
  Future<void> _handlePeerJoined(String peerId) async {
    _connectedPeerId = peerId;
    if (_peerConnection == null) await _createPeerConnection();

    try {
      final offerConstraints = <String, dynamic>{
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      };

      final offer = await _peerConnection!.createOffer(offerConstraints);
      // Forzar Opus en el SDP
      await _peerConnection!.setLocalDescription(offer);
      signalingService.sendOffer(offer);
      debugPrint('[WebRtcIntercomEngine] Oferta SDP enviada al compañero.');
    } catch (e) {
      debugPrint('[WebRtcIntercomEngine] Error creando oferta SDP: $e');
    }
  }

  /// Cuando recibimos una oferta del compañero, respondemos con SDP Answer.
  Future<void> _handleRemoteOffer(RTCSessionDescription offer) async {
    if (_peerConnection == null) await _createPeerConnection();

    try {
      await _peerConnection!.setRemoteDescription(offer);
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      signalingService.sendAnswer(answer);
      debugPrint('[WebRtcIntercomEngine] Respuesta SDP enviada.');
    } catch (e) {
      debugPrint('[WebRtcIntercomEngine] Error manejando oferta remota: $e');
    }
  }

  /// Cuando recibimos la respuesta a nuestra oferta.
  Future<void> _handleRemoteAnswer(RTCSessionDescription answer) async {
    try {
      await _peerConnection?.setRemoteDescription(answer);
      debugPrint('[WebRtcIntercomEngine] Descripción remota establecida exitosamente.');
    } catch (e) {
      debugPrint('[WebRtcIntercomEngine] Error configurando respuesta remota: $e');
    }
  }

  /// Manejo de candidatos ICE entrantes.
  Future<void> _handleRemoteCandidate(RTCIceCandidate candidate) async {
    try {
      await _peerConnection?.addCandidate(candidate);
    } catch (e) {
      debugPrint('[WebRtcIntercomEngine] Error añadiendo candidato ICE: $e');
    }
  }

  void _handlePeerLeft(String peerId) {
    if (_connectedPeerId == peerId) {
      _connectedPeerId = null;
      _state = IntercomState.disconnected;
      notifyListeners();
    }
  }

  /// Conmuta entre micrófono Abierto (Hands-free) y Pulsar para Hablar (PTT).
  void setMicMode(MicMode mode) {
    _micMode = mode;
    if (_micMode == MicMode.pushToTalk) {
      _setMicTransmission(_isPttPressed);
    } else {
      _setMicTransmission(!_isMicMuted);
    }
    notifyListeners();
  }

  /// Presionar o soltar botón PTT (para botones en manillar o pantalla).
  void setPttPressed(bool pressed) {
    _isPttPressed = pressed;
    if (_micMode == MicMode.pushToTalk) {
      _setMicTransmission(pressed);
    }
    notifyListeners();
  }

  /// Silenciar / Reactivar micrófono local.
  void toggleMicMute() {
    _isMicMuted = !_isMicMuted;
    _setMicTransmission(!_isMicMuted);
    notifyListeners();
  }

  void _setMicTransmission(bool enabled) {
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = enabled;
      }
    }
  }

  /// Detener intercomunicador y liberar recursos de hardware.
  Future<void> stopIntercom() async {
    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;

    await _peerConnection?.close();
    await _peerConnection?.dispose();
    _peerConnection = null;

    _remoteStream = null;
    _connectedPeerId = null;
    _state = IntercomState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    stopIntercom();
    super.dispose();
  }
}
