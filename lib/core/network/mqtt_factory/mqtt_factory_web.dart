import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

MqttClient createPlatformMqttClient(String broker, String clientId) {
  // En navegadores web (Safari / Chrome) MQTT se conecta por WebSocket seguro (WSS)
  final client = MqttBrowserClient('wss://$broker', clientId);
  client.port = 8084;
  client.logging(on: false);
  client.keepAlivePeriod = 30;
  client.autoReconnect = true;
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  return client;
}
