import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum AudioRouteType {
  bluetoothSco, // Intercomunicador del casco (HFP/SCO)
  loudspeaker,  // Altavoz del teléfono
  earpiece,     // Auricular telefónico interno
}

/// Servicio de Enrutamiento de Audio y Gestión de Bluetooth SCO / Focus Nativo.
///
/// Cumple con la especificación 1.2 de COMUNIKTE:
/// - Audio Focus en modo comunicación (USAG_VOICE_COMMUNICATION / AVAudioSessionCategoryPlayAndRecord).
/// - Opciones `.mixWithOthers` y `.allowBluetooth` para modo Duck/Mix: la voz remota
///   se mezcla sobre la música (Spotify/YouTube/GPS) sin pausarla.
/// - Conexión forzada y selectiva hacia el perfil Bluetooth SCO/HFP del intercomunicador de casco.
class AudioRoutingService extends ChangeNotifier {
  static const MethodChannel _nativeChannel = MethodChannel('com.comunikte/audio_bridge');

  AudioSession? _session;
  StreamSubscription<Set<AudioDevice>>? _devicesSubscription;

  bool _isBluetoothScoActive = false;
  AudioRouteType _currentRoute = AudioRouteType.bluetoothSco;
  List<MediaDeviceInfo> _availableAudioDevices = [];

  bool get isBluetoothScoActive => _isBluetoothScoActive;
  AudioRouteType get currentRoute => _currentRoute;
  List<MediaDeviceInfo> get availableAudioDevices => _availableAudioDevices;

  /// Inicializa la sesión de audio nativa con políticas de comunicación y Duck/Mix.
  Future<void> initializeAudioPipeline() async {
    try {
      _session = await AudioSession.instance;

      // Configuración de AudioSession cumpliendo Punto 1.2
      await _session!.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers |
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ));

      // Activar la sesión
      await _session!.setActive(true);

      // Monitorear dispositivos de audio conectados
      _devicesSubscription = _session!.devicesStream.listen((devices) {
        _handleDeviceChanges(devices);
      });

      // Forzar Bluetooth SCO / Auricular de Casco por defecto
      await activateBluetoothSco();
      await refreshAudioDevices();
    } catch (e) {
      debugPrint('[AudioRoutingService] Error inicializando pipeline de audio: $e');
    }
  }

  /// Conmuta la bandera de mantener pantalla activa (Keep Screen On) a nivel nativo.
  Future<void> setKeepScreenOn(bool keepOn) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _nativeChannel.invokeMethod('setKeepScreenOn', {'enable': keepOn});
      } catch (e) {
        debugPrint('[AudioRoutingService] Error configurando KeepScreenOn nativo: $e');
      }
    }
  }

  /// Activa explícitamente el canal Bluetooth SCO (Hands-Free Profile) para casco.
  Future<void> activateBluetoothSco() async {
    if (kIsWeb) {
      _currentRoute = AudioRouteType.loudspeaker;
      notifyListeners();
      return;
    }

    try {
      // 1. Invocar puente nativo en Android si está disponible
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _nativeChannel.invokeMethod('startBluetoothSco');
          await _nativeChannel.invokeMethod('requestDuckFocus');
        } catch (e) {
          debugPrint('[AudioRoutingService] Canal nativo SCO no disponible o simulado: $e');
        }
      }

      // 2. En WebRTC móvil, deshabilitar altavoz prioriza el dispositivo Bluetooth SCO
      await Helper.setSpeakerphoneOn(false);
      await Helper.selectAudioOutput('bluetooth');

      _isBluetoothScoActive = true;
      _currentRoute = AudioRouteType.bluetoothSco;
      notifyListeners();
      debugPrint('[AudioRoutingService] Bluetooth SCO activado correctamente.');
    } catch (e) {
      debugPrint('[AudioRoutingService] Error activando Bluetooth SCO: $e');
      // Fallback a earpiece o altavoz según disponibilidad
      _isBluetoothScoActive = false;
      notifyListeners();
    }
  }

  /// Alterna entre el intercomunicador del casco y el altavoz externo.
  Future<void> toggleLoudspeaker() async {
    try {
      if (_currentRoute == AudioRouteType.loudspeaker) {
        await activateBluetoothSco();
      } else {
        if (defaultTargetPlatform == TargetPlatform.android) {
          try {
            await _nativeChannel.invokeMethod('stopBluetoothSco');
            await _nativeChannel.invokeMethod('setSpeakerphone', {'enable': true});
          } catch (_) {}
        }
        await Helper.setSpeakerphoneOn(true);
        await Helper.selectAudioOutput('speaker');
        _isBluetoothScoActive = false;
        _currentRoute = AudioRouteType.loudspeaker;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[AudioRoutingService] Error conmutando altavoz: $e');
    }
  }

  /// Refresca los dispositivos de entrada/salida disponibles reconocidos por WebRTC.
  Future<void> refreshAudioDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      _availableAudioDevices = devices.where((d) => d.kind == 'audioinput' || d.kind == 'audiooutput').toList();
      notifyListeners();
    } catch (e) {
      debugPrint('[AudioRoutingService] Error listando dispositivos: $e');
    }
  }

  void _handleDeviceChanges(Set<AudioDevice> devices) {
    // ignore: experimental_member_use
    final hasBluetooth = devices.any((d) =>
        // ignore: experimental_member_use
        d.type == AudioDeviceType.bluetoothSco ||
        // ignore: experimental_member_use
        d.type == AudioDeviceType.bluetoothA2dp ||
        // ignore: experimental_member_use
        d.type == AudioDeviceType.bluetoothLe);

    if (hasBluetooth && !_isBluetoothScoActive) {
      activateBluetoothSco();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _devicesSubscription?.cancel();
    _session?.setActive(false);
    super.dispose();
  }
}
