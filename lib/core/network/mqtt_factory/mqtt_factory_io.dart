import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient createPlatformMqttClient(String broker, String clientId) {
  final client = MqttServerClient(broker, clientId);
  client.port = 1883;
  client.logging(on: false);
  client.keepAlivePeriod = 30;
  client.autoReconnect = true;
  return client;
}
