import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/hud_theme.dart';

/// Pantalla para Emparejamiento Rápido de Motociclistas mediante Código QR.
/// Permite escanear el QR del compañero o mostrar el QR de la propia sala.
class QrScannerScreen extends StatefulWidget {
  final String? myRoomId;

  const QrScannerScreen({
    super.key,
    this.myRoomId,
  });

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _cameraController = MobileScannerController();
  bool _isShowingMyQr = false;
  bool _hasDetected = false;

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasDetected) return;
    final barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final code = barcode.rawValue;
      if (code != null && code.isNotEmpty) {
        _hasDetected = true;
        Navigator.pop(context, code);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HudTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _isShowingMyQr ? 'MI CÓDIGO QR' : 'ESCANEAR COMPAÑERO',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (!_isShowingMyQr) ...[
            IconButton(
              icon: const Icon(Icons.flash_on_rounded, color: HudTheme.warningNeon),
              onPressed: () => _cameraController.toggleTorch(),
            ),
            IconButton(
              icon: const Icon(Icons.flip_camera_ios_rounded, color: HudTheme.cyanNeon),
              onPressed: () => _cameraController.switchCamera(),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Selector de pestaña (Escanear vs Mostrar)
            if (widget.myRoomId != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildTabButton(
                        title: 'ESCANEAR QR',
                        icon: Icons.qr_code_scanner_rounded,
                        isSelected: !_isShowingMyQr,
                        onTap: () => setState(() => _isShowingMyQr = false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTabButton(
                        title: 'MOSTRAR MI QR',
                        icon: Icons.qr_code_2_rounded,
                        isSelected: _isShowingMyQr,
                        onTap: () => setState(() => _isShowingMyQr = true),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: _isShowingMyQr
                  ? _buildMyQrView(widget.myRoomId!)
                  : _buildCameraScannerView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: isSelected ? HudTheme.surfaceElevated : HudTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? HudTheme.accentNeon : HudTheme.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? HudTheme.accentNeon : HudTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isSelected ? HudTheme.accentNeon : HudTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraScannerView() {
    return Stack(
      alignment: Alignment.center,
      children: [
        MobileScanner(
          controller: _cameraController,
          onDetect: _onDetect,
          errorBuilder: (context, error, child) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_rounded, size: 54, color: HudTheme.dangerNeon),
                    const SizedBox(height: 12),
                    Text(
                      'No se pudo abrir la cámara (${error.errorCode.name})',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: HudTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: HudTheme.accentNeon),
                      icon: const Icon(Icons.refresh_rounded, color: Colors.black),
                      label: const Text('REINTENTAR / PERMISOS', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        _cameraController.start();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // Marco de escaneo HUD
        Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            border: Border.all(color: HudTheme.accentNeon, width: 3),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        Positioned(
          bottom: 40,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Apunta al código QR del intercomunicador de tu compañero',
              style: TextStyle(
                color: HudTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMyQrView(String rawData) {
    String displayCode = rawData;
    if (rawData.startsWith('comunikte://join')) {
      final uri = Uri.tryParse(rawData);
      if (uri != null && uri.queryParameters.containsKey('room')) {
        displayCode = uri.queryParameters['room']!;
      }
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: HudTheme.accentNeon.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: rawData,
              version: QrVersions.auto,
              size: 240.0,
            ),
            const SizedBox(height: 16),
            Text(
              'SALA: $displayCode',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pídele a tu compañero que escanee este código',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
