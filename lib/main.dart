import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/audio/audio_routing_service.dart';
import 'core/audio/gain_controller.dart';
import 'core/network/local_signaling_server.dart';
import 'core/network/signaling_service.dart';
import 'core/theme/hud_theme.dart';
import 'features/connection/presentation/room_entry_screen.dart';
import 'features/intercom/domain/webrtc_intercom_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configurar barra de estado inmersiva para pantalla de moto (HUD)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: HudTheme.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ComunikteApp());
}

class ComunikteApp extends StatelessWidget {
  const ComunikteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioRoutingService()),
        ChangeNotifierProvider(create: (_) => GainController()),
        ChangeNotifierProvider(create: (_) => SignalingService()),
        ChangeNotifierProvider(create: (_) => LocalSignalingServer()),
        ChangeNotifierProxyProvider3<SignalingService, AudioRoutingService, GainController, WebRtcIntercomEngine>(
          create: (ctx) => WebRtcIntercomEngine(
            signalingService: ctx.read<SignalingService>(),
            audioRoutingService: ctx.read<AudioRoutingService>(),
            gainController: ctx.read<GainController>(),
          ),
          update: (ctx, signaling, audio, gain, previousEngine) =>
              previousEngine ??
              WebRtcIntercomEngine(
                signalingService: signaling,
                audioRoutingService: audio,
                gainController: gain,
              ),
        ),
      ],
      child: MaterialApp(
        title: 'COMUNIKTE',
        debugShowCheckedModeBanner: false,
        theme: HudTheme.themeData,
        home: const RoomEntryScreen(),
      ),
    );
  }
}
