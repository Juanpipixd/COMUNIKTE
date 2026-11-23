import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:comunikte/core/network/local_signaling_server.dart';

void main() {
  group('LocalSignalingServer Unit Tests (P2P Hotspot Mode)', () {
    late LocalSignalingServer server;
    const testPort = 8999;

    setUp(() async {
      server = LocalSignalingServer();
    });

    tearDown(() async {
      await server.stopServer();
    });

    test('Starts and stops local embedded signaling server', () async {
      expect(server.isRunning, isFalse);

      final started = await server.startServer(port: testPort);
      expect(started, isTrue);
      expect(server.isRunning, isTrue);
      expect(server.port, testPort);

      await server.stopServer();
      expect(server.isRunning, isFalse);
    });

    test('Relays join and signaling messages between two peers', () async {
      await server.startServer(port: testPort);

      final clientA = await WebSocket.connect('ws://127.0.0.1:$testPort');
      final clientB = await WebSocket.connect('ws://127.0.0.1:$testPort');

      final completerJoin = Completer<Map<String, dynamic>>();
      final completerOffer = Completer<Map<String, dynamic>>();

      clientA.listen((message) {
        final data = jsonDecode(message.toString()) as Map<String, dynamic>;
        if (data['type'] == 'peer_joined') {
          completerJoin.complete(data);
        }
      });

      clientB.listen((message) {
        final data = jsonDecode(message.toString()) as Map<String, dynamic>;
        if (data['type'] == 'offer') {
          completerOffer.complete(data);
        }
      });

      // Rider A joins room 777
      clientA.add(jsonEncode({
        'type': 'join',
        'roomId': '777',
        'clientId': 'riderA',
      }));

      // Small delay to ensure Rider A is registered
      await Future.delayed(const Duration(milliseconds: 50));

      // Rider B joins room 777 -> Rider A should receive peer_joined
      clientB.add(jsonEncode({
        'type': 'join',
        'roomId': '777',
        'clientId': 'riderB',
      }));

      final joinEvent = await completerJoin.future.timeout(const Duration(seconds: 3));
      expect(joinEvent['type'], 'peer_joined');
      expect(joinEvent['peerId'], 'riderB');

      // Rider A sends offer -> Rider B should receive it
      clientA.add(jsonEncode({
        'type': 'offer',
        'roomId': '777',
        'sdp': 'v=0\r\no=riderA...',
      }));

      final offerEvent = await completerOffer.future.timeout(const Duration(seconds: 3));
      expect(offerEvent['type'], 'offer');
      expect(offerEvent['sdp'], 'v=0\r\no=riderA...');

      await clientA.close();
      await clientB.close();
    });
  });
}
