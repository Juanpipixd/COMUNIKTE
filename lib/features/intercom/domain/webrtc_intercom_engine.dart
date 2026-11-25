import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/audio/audio_routing_service.dart';
import '../../../core/audio/gain_controller.dart';
import '../../../core/audio/platform_gain/platform_gain.dart';
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

  final RTCVideoRenderer remoteAudioRenderer = RTCVideoRenderer();

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

  // Configuración de Servidores STUN/TURN con respaldo público de alta disponibilidad
  static final Map<String, dynamic> _rtcConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:443?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  WebRtcIntercomEngine({
    required this.signalingService,
    required this.audioRoutingService,
    required this.gainController,
  }) {
    _bindSignalingEvents();
    _bindGainController();
  }

  void _bindGainController() {
    gainController.onGainChanged = (double gain, bool isMuted) {
      final shouldMute = isMuted || gain == 0.0;
      try {
        remoteAudioRenderer.muted = shouldMute;
      } catch (_) {}
      applyPlatformGain(gain, isMuted);
    };
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
      // Activar WakeLock para mantener pantalla encendida en marcha
      try {
        await WakelockPlus.enable();
      } catch (e) {
        debugPrint('[WebRtcIntercomEngine] Error activando WakelockPlus: $e');
      }
      requestScreenWakeLockPlatform();
      await audioRoutingService.setKeepScreenOn(true);

      // 0. Inicializar renderer de audio para navegadores web (Safari / PWA)
      try {
        await remoteAudioRenderer.initialize();
        remoteAudioRenderer.muted = false;
      } catch (e) {
        debugPrint('[WebRtcIntercomEngine] Renderer audio init: $e');
      }

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

    // Agregar tracks locales (asigna automáticamente el transceptor m=audio único)
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }

    // Escuchar tracks entrantes de la voz remota
    _peerConnection!.onTrack = (RTCTrackEvent event) async {
      if (event.track.kind == 'audio') {
        debugPrint('[WebRtcIntercomEngine] Track de audio remoto recibido: ${event.track.id}');
        final shouldEnable = !gainController.isMuted && gainController.softwareGain > 0.0;
        event.track.enabled = shouldEnable;

        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
        } else {
          try {
            final stream = await createLocalMediaStream('remote_stream_${event.track.id}');
            await stream.addTrack(event.track);
            _remoteStream = stream;
          } catch (e) {
            debugPrint('[WebRtcIntercomEngine] Error envolviendo track remoto: $e');
          }
        }

        if (_remoteStream != null) {
          remoteAudioRenderer.srcObject = _remoteStream;
          remoteAudioRenderer.muted = !shouldEnable;
          setupWebAudioStream();
        }

        // VINCULAR AL CONTROLADOR DE GANANCIA POR SOFTWARE (Punto 1.3)
        gainController.attachRemoteAudioTrack(event.track);
        applyPlatformGain(gainController.softwareGain, gainController.isMuted);

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

  final List<RTCIceCandidate> _pendingIceCandidates = [];
  Timer? _politeOfferTimer;

  /// Cuando un nuevo compañero se une a la sala, creamos la Oferta SDP evitando colisiones (Glare).
  Future<void> _handlePeerJoined(String peerId) async {
    _connectedPeerId = peerId;
    if (_peerConnection == null) await _createPeerConnection();

    // Notificar presencia al otro dispositivo
    signalingService.sendPeerJoined();

    // Si nuestro ID es menor, enviamos la oferta de inmediato
    final myId = signalingService.clientId ?? '';
    final shouldCreateOffer = myId.isEmpty || peerId.isEmpty || myId.compareTo(peerId) < 0;

    if (shouldCreateOffer) {
      _politeOfferTimer?.cancel();
      await _createAndSendOffer(peerId);
    } else {
      debugPrint('[WebRtcIntercomEngine] Peer polite: esperando oferta SDP de $peerId (con fallback a 1.2s)');
      // Si el otro peer no envía la oferta dentro de 1.2s (por ejemplo versión anterior instalada),
      // tomamos la iniciativa automáticamente para evitar que queden esperando.
      _politeOfferTimer?.cancel();
      _politeOfferTimer = Timer(const Duration(milliseconds: 1200), () async {
        if (_state != IntercomState.connected) {
          debugPrint('[WebRtcIntercomEngine] Fallback activado: enviando oferta SDP proactivamente a $peerId');
          await _createAndSendOffer(peerId);
        }
      });
    }
  }

  Future<void> _createAndSendOffer(String peerId) async {
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
      debugPrint('[WebRtcIntercomEngine] Oferta SDP enviada al compañero ($peerId).');
    } catch (e) {
      debugPrint('[WebRtcIntercomEngine] Error creando oferta SDP: $e');
    }
  }

  /// Cuando recibimos una oferta del compañero, respondemos con SDP Answer.
  Future<void> _handleRemoteOffer(RTCSessionDescription offer) async {
    _politeOfferTimer?.cancel();
    if (_peerConnection == null) await _createPeerConnection();

    try {
      await _peerConnection!.setRemoteDescription(offer);
      await _drainPendingIceCandidates();
      final answerConstraints = <String, dynamic>{
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      };
      final answer = await _peerConnection!.createAnswer(answerConstraints);
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
      await _drainPendingIceCandidates();
      debugPrint('[WebRtcIntercomEngine] Descripción remota establecida exitosamente.');
    } catch (e) {
      debugPrint('[WebRtcIntercomEngine] Error configurando respuesta remota: $e');
    }
  }

  /// Manejo de candidatos ICE entrantes con buffer preventivo.
  Future<void> _handleRemoteCandidate(RTCIceCandidate candidate) async {
    try {
      if (_peerConnection == null) {
        _pendingIceCandidates.add(candidate);
        return;
      }
      final remoteDesc = await _peerConnection!.getRemoteDescription();
      if (remoteDesc == null) {
        _pendingIceCandidates.add(candidate);
        return;
      }
      await _peerConnection!.addCandidate(candidate);
    } catch (e) {
      debugPrint('[WebRtcIntercomEngine] Error añadiendo candidato ICE: $e');
    }
  }

  Future<void> _drainPendingIceCandidates() async {
    while (_pendingIceCandidates.isNotEmpty) {
      final cand = _pendingIceCandidates.removeAt(0);
      try {
        await _peerConnection?.addCandidate(cand);
      } catch (e) {
        debugPrint('[WebRtcIntercomEngine] Error drenando candidato ICE: $e');
      }
    }
  }

  void _handlePeerLeft(String peerId) {
    if (_connectedPeerId == peerId) {
      _connectedPeerId = null;
      _state = IntercomState.disconnected;
      notifyListeners();
    }
  }

  /// Fuerza la activación de la salida de audio para navegadores (Safari / iOS)
  void unmuteAudioRenderer() {
    final shouldMute = gainController.isMuted || gainController.softwareGain == 0.0;
    remoteAudioRenderer.muted = shouldMute;
    if (_remoteStream != null && remoteAudioRenderer.srcObject == null) {
      remoteAudioRenderer.srcObject = _remoteStream;
    }
    setupWebAudioStream();
    applyPlatformGain(gainController.softwareGain, gainController.isMuted);
    notifyListeners();
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
    // Desactivar WakeLock
    try {
      await WakelockPlus.disable();
    } catch (e) {
      debugPrint('[WebRtcIntercomEngine] Error desactivando WakelockPlus: $e');
    }
    releaseScreenWakeLockPlatform();
    await audioRoutingService.setKeepScreenOn(false);

    _politeOfferTimer?.cancel();
    _politeOfferTimer = null;
    remoteAudioRenderer.srcObject = null;
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
