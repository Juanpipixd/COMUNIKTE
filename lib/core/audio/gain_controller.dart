import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Controlador de Ganancia por Software (Software Gain) para COMUNIKTE.
///
/// Cumple con la especificación 1.3:
/// - NO modifica el volumen general del hardware del dispositivo ni del sistema.
/// - Ajusta la amplitud digital PCM directamente sobre el [MediaStreamTrack] de la voz remota
///   en un rango continuo de 0.0 (silencio) a 2.0 (200% boost).
/// - Permite que la música de fondo (Spotify, Apple Music) y el GPS se mantengan
///   a su volumen deseado sin interferencias de la voz del compañero.
class GainController extends ChangeNotifier {
  double _softwareGain = 1.0;
  MediaStreamTrack? _remoteAudioTrack;
  bool _isMuted = false;
  double _gainBeforeMute = 1.0;

  /// Callback para sincronizar cambios de ganancia con el motor WebRTC,
  /// el reproductor de audio y el procesador de Web Audio API (Safari/Web).
  void Function(double gain, bool isMuted)? onGainChanged;

  double get softwareGain => _softwareGain;
  bool get isMuted => _isMuted;
  int get gainPercentage => (_softwareGain * 100).round();

  /// Asigna o actualiza la pista de audio remota entrante.
  void attachRemoteAudioTrack(MediaStreamTrack? track) {
    _remoteAudioTrack = track;
    _applyGainToTrack();
  }

  /// Establece la ganancia de software (0.0 a 2.0).
  /// 0.0 = Silencio total de la voz entrante
  /// 1.0 = Ganancia unitaria / normal
  /// 1.5 = Modo Carretera / Viento
  /// 2.0 = Máxima amplificación digital
  void setGain(double gain) {
    final clampedGain = gain.clamp(0.0, 2.0);
    _softwareGain = clampedGain;
    _isMuted = clampedGain == 0.0;
    _applyGainToTrack();
    notifyListeners();
  }

  /// Silencia o restaura la voz del compañero instantáneamente.
  void toggleMute() {
    if (_isMuted) {
      _softwareGain = _gainBeforeMute > 0.0 ? _gainBeforeMute : 1.0;
      _isMuted = false;
    } else {
      _gainBeforeMute = _softwareGain;
      _softwareGain = 0.0;
      _isMuted = true;
    }
    _applyGainToTrack();
    notifyListeners();
  }

  /// Aplica la ganancia directamente sobre el MediaStreamTrack mediante WebRTC Helper
  /// y activa los callbacks hacia Web Audio API y el renderer.
  void _applyGainToTrack() {
    final track = _remoteAudioTrack;
    if (track != null) {
      // Si está silenciado o en 0%, deshabilitar el track garantiza silencio total
      track.enabled = !_isMuted && _softwareGain > 0.0;
      try {
        // Helper.setVolume aplica la ganancia PCM sobre el track de audio remoto en Android/iOS (acotado a 1.0)
        final trackVol = _isMuted ? 0.0 : _softwareGain.clamp(0.0, 1.0);
        Helper.setVolume(trackVol, track);
      } catch (e) {
        debugPrint('[GainController] Error aplicando ganancia al track: $e');
      }
    }

    // Notificar al motor para actualizar renderer, Web Audio API y Android LoudnessEnhancer
    onGainChanged?.call(_softwareGain, _isMuted);
  }

  /// Presets rápidos pensados para motociclistas con guantes.
  void setPresetQuiet() => setGain(0.0);
  void setPresetCity() => setGain(1.0);
  void setPresetHighway() => setGain(1.5);
  void setPresetMaxBoost() => setGain(2.0);
}
