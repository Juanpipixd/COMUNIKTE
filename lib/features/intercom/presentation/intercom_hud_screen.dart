import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../../../core/audio/audio_routing_service.dart';
import '../../../core/theme/hud_theme.dart';
import '../domain/webrtc_intercom_engine.dart';
import 'widgets/connection_badge.dart';
import 'widgets/volume_slider.dart';

/// Pantalla Principal HUD de Intercomunicador para Motociclistas (COMUNIKTE).
/// Diseñada con botones gigantes y colores de alto contraste para máxima
/// seguridad y operabilidad con guantes de moto en marcha.
class IntercomHudScreen extends StatefulWidget {
  final String roomId;

  const IntercomHudScreen({
    super.key,
    required this.roomId,
  });

  @override
  State<IntercomHudScreen> createState() => _IntercomHudScreenState();
}

class _IntercomHudScreenState extends State<IntercomHudScreen> {
  @override
  Widget build(BuildContext context) {
    final engine = context.watch<WebRtcIntercomEngine>();
    final audioRouting = context.watch<AudioRoutingService>();

    final isMuted = engine.isMicMuted;
    final isPtt = engine.micMode == MicMode.pushToTalk;
    final isPttPressed = engine.isPttPressed;

    return Scaffold(
      backgroundColor: HudTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'COMUNIKTE HUD',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
            fontSize: 20,
          ),
        ),
        actions: [
          // Botón desconectar llamada
          IconButton(
            icon: const Icon(Icons.call_end_rounded, color: HudTheme.dangerNeon, size: 32),
            onPressed: () => _confirmExit(context, engine),
            tooltip: 'Finalizar Intercom',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Badge Superior de Conexión, Latencia STUN y Bluetooth SCO
              ConnectionBadge(roomId: widget.roomId),

              const SizedBox(height: 16),

              // 2. Control de Modo de Micrófono (MANOS LIBRES / PTT)
              Container(
                decoration: BoxDecoration(
                  color: HudTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: HudTheme.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildModeTab(
                        label: 'MANOS LIBRES',
                        icon: Icons.record_voice_over_rounded,
                        isSelected: !isPtt,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          engine.setMicMode(MicMode.openMic);
                        },
                      ),
                    ),
                    Expanded(
                      child: _buildModeTab(
                        label: 'PTT (PULSAR)',
                        icon: Icons.touch_app_rounded,
                        isSelected: isPtt,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          engine.setMicMode(MicMode.pushToTalk);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 3. BOTÓN GIGANTE CENTRAL (Acción rápida con guantes)
              Expanded(
                child: Center(
                  child: isPtt
                      ? _buildPttGiantButton(engine, isPttPressed)
                      : _buildMuteGiantButton(engine, isMuted),
                ),
              ),

              const SizedBox(height: 16),

              // 4. Slider de Ganancia Independiente por Software (Software Gain PCM)
              const VolumeSlider(),

              const SizedBox(height: 12),

              // 5. Botón de Conmutación Rápida de Bluetooth SCO / Altavoz
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: audioRouting.isBluetoothScoActive
                      ? HudTheme.surfaceElevated
                      : HudTheme.warningNeon.withValues(alpha: 0.2),
                  side: BorderSide(
                    color: audioRouting.isBluetoothScoActive
                        ? HudTheme.cyanNeon
                        : HudTheme.warningNeon,
                    width: 2,
                  ),
                ),
                icon: Icon(
                  audioRouting.isBluetoothScoActive
                      ? Icons.bluetooth_audio_rounded
                      : Icons.volume_up_rounded,
                  color: audioRouting.isBluetoothScoActive
                      ? HudTheme.cyanNeon
                      : HudTheme.warningNeon,
                  size: 28,
                ),
                label: Text(
                  audioRouting.isBluetoothScoActive
                      ? 'AUDIO EN CASCO BLUETOOTH (SCO ACTIVO)'
                      : 'AUDIO EN ALTAVOZ (CONMUTAR A CASCO)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: audioRouting.isBluetoothScoActive
                        ? HudTheme.cyanNeon
                        : HudTheme.warningNeon,
                  ),
                ),
                onPressed: () {
                  HapticFeedback.heavyImpact();
                  audioRouting.toggleLoudspeaker();
                },
              ),

              // Receptor de audio WebRTC para navegadores web (Safari / Chrome PWA)
              SizedBox(
                width: 1,
                height: 1,
                child: Opacity(
                  opacity: 0.01,
                  child: RTCVideoView(
                    engine.remoteAudioRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeTab({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? HudTheme.surfaceElevated : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: HudTheme.accentNeon, width: 2)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? HudTheme.accentNeon : HudTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: isSelected ? HudTheme.accentNeon : HudTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMuteGiantButton(WebRtcIntercomEngine engine, bool isMuted) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.heavyImpact();
        engine.toggleMicMute();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          color: isMuted ? HudTheme.dangerNeon : HudTheme.accentNeon,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (isMuted ? HudTheme.dangerNeon : HudTheme.accentNeon)
                  .withValues(alpha: 0.4),
              blurRadius: 30,
              spreadRadius: 6,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              size: 72,
              color: Colors.black,
            ),
            const SizedBox(height: 8),
            Text(
              isMuted ? 'MIC MUTEADO' : 'TRANSMITIENDO',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isMuted ? 'Toca para hablar' : 'Toca para mutear',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPttGiantButton(WebRtcIntercomEngine engine, bool isPressed) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.heavyImpact();
        engine.setPttPressed(true);
      },
      onTapUp: (_) {
        HapticFeedback.mediumImpact();
        engine.setPttPressed(false);
      },
      onTapCancel: () {
        engine.setPttPressed(false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: isPressed ? 210 : 200,
        height: isPressed ? 210 : 200,
        decoration: BoxDecoration(
          color: isPressed ? HudTheme.accentNeon : HudTheme.surfaceElevated,
          shape: BoxShape.circle,
          border: Border.all(
            color: isPressed ? HudTheme.accentNeon : HudTheme.cyanNeon,
            width: 4,
          ),
          boxShadow: [
            BoxShadow(
              color: (isPressed ? HudTheme.accentNeon : HudTheme.cyanNeon)
                  .withValues(alpha: isPressed ? 0.6 : 0.2),
              blurRadius: isPressed ? 35 : 15,
              spreadRadius: isPressed ? 8 : 2,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.radio_button_checked_rounded,
              size: 72,
              color: isPressed ? Colors.black : HudTheme.cyanNeon,
            ),
            const SizedBox(height: 8),
            Text(
              isPressed ? 'HABLANDO...' : 'MANTÉN PRESIONADO',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: isPressed ? Colors.black : HudTheme.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isPressed ? 'Transmitiendo voz' : 'PTT activo',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isPressed ? Colors.black87 : HudTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmExit(BuildContext context, WebRtcIntercomEngine engine) async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HudTheme.surfaceElevated,
        title: const Text('¿Finalizar Intercomunicador?'),
        content: const Text(
          'Se cerrará la conexión P2P con tu compañero y se liberará el canal de audio del casco.',
        ),
        actions: [
          TextButton(
            child: const Text('CANCELAR', style: TextStyle(color: HudTheme.textSecondary)),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: HudTheme.dangerNeon),
            child: const Text('DESCONECTAR', style: TextStyle(color: Colors.black)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (shouldExit == true && context.mounted) {
      await engine.stopIntercom();
      if (!context.mounted) return;
      Navigator.pop(context);
    }
  }
}
