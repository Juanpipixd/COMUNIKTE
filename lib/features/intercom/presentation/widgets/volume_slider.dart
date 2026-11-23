import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/audio/gain_controller.dart';
import '../../../../core/theme/hud_theme.dart';

/// Slider táctil sobredimensionado para guantes de motocicleta.
/// Controla la ganancia digital independiente (Software Gain) de la voz entrante.
class VolumeSlider extends StatelessWidget {
  const VolumeSlider({super.key});

  @override
  Widget build(BuildContext context) {
    final gainController = context.watch<GainController>();
    final currentGain = gainController.softwareGain;
    final percentage = gainController.gainPercentage;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HudTheme.surface,
        borderRadius: BorderRadius.circular(HudTheme.borderRadius),
        border: Border.all(
          color: currentGain > 1.2 ? HudTheme.warningNeon : HudTheme.border,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera con indicador de ganancia
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    currentGain == 0.0
                        ? Icons.volume_off_rounded
                        : currentGain > 1.2
                            ? Icons.volume_up_rounded
                            : Icons.volume_down_rounded,
                    color: currentGain == 0.0
                        ? HudTheme.dangerNeon
                        : currentGain > 1.2
                            ? HudTheme.warningNeon
                            : HudTheme.accentNeon,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'VOZ COMPAÑERO (PCM GAIN)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: HudTheme.textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: currentGain > 1.2
                      ? HudTheme.warningNeon.withValues(alpha: 0.2)
                      : HudTheme.accentNeon.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: currentGain > 1.2
                        ? HudTheme.warningNeon
                        : HudTheme.accentNeon,
                  ),
                ),
                child: Text(
                  '$percentage%',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: currentGain > 1.2
                        ? HudTheme.warningNeon
                        : HudTheme.accentNeon,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Slider Grueso para Guantes
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 18,
              activeTrackColor: currentGain > 1.2
                  ? HudTheme.warningNeon
                  : HudTheme.accentNeon,
              inactiveTrackColor: HudTheme.surfaceElevated,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 18),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 28),
            ),
            child: Slider(
              value: currentGain,
              min: 0.0,
              max: 2.0,
              divisions: 20,
              onChanged: (val) {
                gainController.setGain(val);
              },
            ),
          ),

          const SizedBox(height: 16),

          // Presets Rápidos Accesibles con Guantes
          Row(
            children: [
              _buildPresetBtn(
                title: 'MUTE',
                isSelected: currentGain == 0.0,
                color: HudTheme.dangerNeon,
                onTap: gainController.setPresetQuiet,
              ),
              const SizedBox(width: 8),
              _buildPresetBtn(
                title: '100% CIUDAD',
                isSelected: (currentGain - 1.0).abs() < 0.05,
                color: HudTheme.cyanNeon,
                onTap: gainController.setPresetCity,
              ),
              const SizedBox(width: 8),
              _buildPresetBtn(
                title: '150% RUTA',
                isSelected: (currentGain - 1.5).abs() < 0.05,
                color: HudTheme.warningNeon,
                onTap: gainController.setPresetHighway,
              ),
              const SizedBox(width: 8),
              _buildPresetBtn(
                title: '200% MAX',
                isSelected: (currentGain - 2.0).abs() < 0.05,
                color: HudTheme.accentNeon,
                onTap: gainController.setPresetMaxBoost,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetBtn({
    required String title,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.25) : HudTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : HudTheme.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isSelected ? color : HudTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
