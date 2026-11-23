import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../../core/audio/audio_routing_service.dart';
import '../../../core/network/local_signaling_server.dart';
import '../../../core/network/signaling_service.dart';
import '../../../core/theme/hud_theme.dart';
import '../../intercom/domain/webrtc_intercom_engine.dart';
import '../../intercom/presentation/intercom_hud_screen.dart';
import 'qr_scanner_screen.dart';

/// Pantalla de Ingreso y Creación de Salas para Motociclistas (COMUNIKTE).
class RoomEntryScreen extends StatefulWidget {
  const RoomEntryScreen({super.key});

  @override
  State<RoomEntryScreen> createState() => _RoomEntryScreenState();
}

class _RoomEntryScreenState extends State<RoomEntryScreen> {
  static const String _defaultPublicServer = 'Servidor Nube Comunikte (MQTT P2P)';

  final TextEditingController _roomController = TextEditingController();
  final TextEditingController _serverController = TextEditingController(
    text: _defaultPublicServer,
  );

  bool _isConnecting = false;
  bool _isHotspotMode = false;

  @override
  void initState() {
    super.initState();
    _generateRandomRoom();
    _requestRequiredPermissions();
  }

  void _generateRandomRoom() {
    final rand = Random();
    final code = (rand.nextInt(900000) + 100000).toString();
    _roomController.text = code;
  }

  Future<void> _requestRequiredPermissions() async {
    await [
      Permission.microphone,
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.camera,
    ].request();

    if (mounted) {
      final audioService = context.read<AudioRoutingService>();
      await audioService.initializeAudioPipeline();
    }
  }

  @override
  void dispose() {
    _roomController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _openQrScanner() async {
    HapticFeedback.mediumImpact();
    final currentRoom = _roomController.text.trim();
    final currentServer = _serverController.text.trim();
    final qrPayload = 'comunikte://join?room=$currentRoom&server=$currentServer';

    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(myRoomId: qrPayload),
      ),
    );

    if (scannedCode != null && scannedCode.isNotEmpty) {
      if (scannedCode.startsWith('comunikte://join')) {
        final uri = Uri.tryParse(scannedCode);
        if (uri != null) {
          final room = uri.queryParameters['room'];
          final server = uri.queryParameters['server'];
          if (room != null && room.isNotEmpty) _roomController.text = room;
          if (server != null && server.isNotEmpty) _serverController.text = server;
        }
      } else {
        _roomController.text = scannedCode;
      }
      _startRide();
    }
  }

  Future<void> _toggleHotspotMode(bool enabled) async {
    final localServer = context.read<LocalSignalingServer>();
    setState(() => _isHotspotMode = enabled);

    if (enabled) {
      final started = await localServer.startServer();
      if (started) {
        _serverController.text = localServer.serverUrl;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Servidor Hotspot iniciado en ${localServer.serverUrl}'),
              backgroundColor: HudTheme.accentNeon,
            ),
          );
        }
      }
    } else {
      await localServer.stopServer();
      _serverController.text = _defaultPublicServer;
    }
  }

  Future<void> _startRide() async {
    final roomId = _roomController.text.trim();
    if (roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor introduce un código de sala'),
          backgroundColor: HudTheme.dangerNeon,
        ),
      );
      return;
    }

    setState(() => _isConnecting = true);

    try {
      final signaling = context.read<SignalingService>();
      final engine = context.read<WebRtcIntercomEngine>();

      final clientId = 'rider_${Random().nextInt(10000)}';
      final currentServer = _serverController.text.trim();
      final effectiveServer = currentServer == _defaultPublicServer ? 'cloud' : currentServer;

      // 1. Conectar señalización (MQTT Cloud o WebSocket Local)
      await signaling.connectAndJoinRoom(
        serverUrl: effectiveServer,
        roomId: roomId,
        clientId: clientId,
      );

      // 2. Iniciar motor WebRTC de voz y SCO
      await engine.startIntercom();

      if (mounted) {
        setState(() => _isConnecting = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IntercomHudScreen(roomId: roomId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error iniciando intercomunicador: $e'),
            backgroundColor: HudTheme.dangerNeon,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioRouting = context.watch<AudioRoutingService>();

    return Scaffold(
      backgroundColor: HudTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.two_wheeler_rounded, color: HudTheme.accentNeon, size: 30),
            const SizedBox(width: 12),
            const Text(
              'COMUNIKTE',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                fontSize: 22,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Estado de Hardware de Casco
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: HudTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: audioRouting.isBluetoothScoActive
                        ? HudTheme.cyanNeon
                        : HudTheme.warningNeon,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      audioRouting.isBluetoothScoActive
                          ? Icons.bluetooth_connected_rounded
                          : Icons.bluetooth_searching_rounded,
                      color: audioRouting.isBluetoothScoActive
                          ? HudTheme.cyanNeon
                          : HudTheme.warningNeon,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            audioRouting.isBluetoothScoActive
                                ? 'CASCO VINCULADO (CANAL SCO LISTO)'
                                : 'BUSCANDO CASCO BLUETOOTH...',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: audioRouting.isBluetoothScoActive
                                  ? HudTheme.cyanNeon
                                  : HudTheme.warningNeon,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Audio Focus activo: la música no se detendrá.',
                            style: TextStyle(
                              fontSize: 11,
                              color: HudTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Código de Sala (Numérico Grande para Guantes)
              const Text(
                'CÓDIGO DE SALA / RUTA',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: HudTheme.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: HudTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: HudTheme.border, width: 2),
                      ),
                      child: TextField(
                        controller: _roomController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6.0,
                          color: HudTheme.accentNeon,
                        ),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          hintText: '000000',
                          hintStyle: TextStyle(color: Colors.white24),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Botón Generar Nueva Sala
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: HudTheme.surfaceElevated,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(16),
                    ),
                    icon: const Icon(Icons.refresh_rounded, color: HudTheme.textPrimary, size: 28),
                    onPressed: _generateRandomRoom,
                    tooltip: 'Generar otra sala',
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Botón Escanear / Mostrar QR
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: HudTheme.surfaceElevated,
                  side: const BorderSide(color: HudTheme.cyanNeon, width: 2),
                ),
                icon: const Icon(Icons.qr_code_scanner_rounded, color: HudTheme.cyanNeon, size: 28),
                label: const Text(
                  'ESCANEAR O MOSTRAR CÓDIGO QR',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: HudTheme.cyanNeon,
                  ),
                ),
                onPressed: _openQrScanner,
              ),

              const SizedBox(height: 20),

              // BOTÓN GIGANTE INICIAR INTERCOM
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: HudTheme.accentNeon,
                  minimumSize: const Size.fromHeight(80),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 8,
                ),
                onPressed: _isConnecting ? null : _startRide,
                child: _isConnecting
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.headset_mic_rounded, color: Colors.black, size: 36),
                          SizedBox(width: 14),
                          Text(
                            'CONECTAR Y RODAR',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 28),

              // Configuración de Servidor de Señalización (Modo Hotspot / Local)
              ExpansionTile(
                iconColor: HudTheme.textSecondary,
                collapsedIconColor: HudTheme.textSecondary,
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'Opciones Avanzadas de Red y Servidor',
                  style: TextStyle(
                    color: HudTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: HudTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: HudTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Switch Modo Hotspot Local Sin Cobertura (Punto 2 COMUNIKTE)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Modo Hotspot Local (Sin Cobertura)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: HudTheme.textPrimary,
                            ),
                          ),
                          subtitle: const Text(
                            'Convierte tu teléfono en anfitrión de señalización para carreteras y montañas.',
                            style: TextStyle(fontSize: 11, color: HudTheme.textSecondary),
                          ),
                          value: _isHotspotMode,
                          activeThumbColor: HudTheme.accentNeon,
                          onChanged: _toggleHotspotMode,
                        ),
                        const Divider(color: HudTheme.border),
                        const SizedBox(height: 8),
                        const Text(
                          'Servidor WebSocket de Señalización:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: HudTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _serverController,
                          style: const TextStyle(fontSize: 13, color: HudTheme.textPrimary),
                          decoration: InputDecoration(
                            isDense: true,
                            fillColor: HudTheme.surfaceElevated,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Para zonas rurales sin cobertura celular, conéctense al mismo Hotspot Wi-Fi e ingresen la IP del host (ej: ws://192.168.43.1:8080).',
                          style: TextStyle(
                            fontSize: 11,
                            color: HudTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
