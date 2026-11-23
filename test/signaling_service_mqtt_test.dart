import 'package:flutter_test/flutter_test.dart';
import 'package:comunikte/core/network/signaling_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SignalingService Unit Tests', () {
    test('Initializes in disconnected state', () {
      final service = SignalingService();
      expect(service.status, equals(SignalingStatus.disconnected));
      expect(service.currentRoomId, isNull);
      expect(service.clientId, isNull);
      expect(service.latencyMs, equals(0));
    });

    test('Disconnect resets room and status cleanly', () async {
      final service = SignalingService();
      await service.disconnect();
      expect(service.status, equals(SignalingStatus.disconnected));
      expect(service.currentRoomId, isNull);
      expect(service.latencyMs, equals(0));
    });
  });
}
