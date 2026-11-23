import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/audio/audio_routing_service.dart';
import '../../../../core/network/signaling_service.dart';
import '../../../../core/theme/hud_theme.dart';
import '../../domain/webrtc_intercom_engine.dart';

/// Badge HUD de Estado de Conexión, Latencia STUN y Enrutamiento Bluetooth SCO.
class ConnectionBadge extends StatelessWidget {
  final String roomId;

  const ConnectionBadge({
    super.key,
    required this.roomId,
  });

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<WebRtcIntercomEngine>();
    final audioRouting = context.watch<AudioRoutingService>();
    final signaling = context.watch<SignalingService>();

    final state = engine.state;
    final isSco = audioRouting.isBluetoothScoActive;
    final latency = signaling.latencyMs;

    Color statusColor;
    String statusText;

    switch (state) {
      case IntercomState.connected:
        statusColor = HudTheme.accentNeon;
        statusText = 'INTERCOM EN VIVO';
        break;
      case IntercomState.connecting:
      case IntercomState.reconnecting:
        statusColor = HudTheme.warningNeon;
        statusText = 'ENLAZANDO...';
        break;
      case IntercomState.error:
        statusColor = HudTheme.dangerNeon;
        statusText = 'ERROR DE ENLACE';
        break;
      case IntercomState.disconnected:
      case IntercomState.idle:
        statusColor = HudTheme.textSecondary;
        statusText = 'DESCONECTADO';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: HudTheme.surface,
        borderRadius: BorderRadius.circular(HudTheme.borderRadius),
        border: Border.all(color: statusColor, width: 2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Estado WebRTC
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.6),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),

              // Código de Sala
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: HudTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'SALA #$roomId',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: HudTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: HudTheme.border, height: 1),
          const SizedBox(height: 12),

          // Métricas Secundarias: Latencia STUN y Canal SCO
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Latencia
              Row(
                children: [
                  const Icon(Icons.speed_rounded, size: 20, color: HudTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    state == IntercomState.connected && latency > 0
                        ? '$latency ms (P2P Opus)'
                        : '< 50 ms (Google STUN)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: HudTheme.textSecondary,
                    ),
                  ),
                ],
              ),

              // Estado Bluetooth SCO de Casco
              GestureDetector(
                onTap: () => audioRouting.toggleLoudspeaker(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSco ? HudTheme.cyanNeon.withValues(alpha: 0.15) : HudTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSco ? HudTheme.cyanNeon : HudTheme.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSco ? Icons.headset_mic_rounded : Icons.volume_up_rounded,
                        size: 16,
                        color: isSco ? HudTheme.cyanNeon : HudTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isSco ? 'CASCO (SCO)' : 'ALTAVOZ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isSco ? HudTheme.cyanNeon : HudTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
