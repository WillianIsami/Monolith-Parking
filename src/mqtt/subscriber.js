const mqtt = require('mqtt');
const config = require('../config');
const { applySpotEvent } = require('../services/parkingService');
const { checkIncidents } = require('../services/incidentService');
const { recordGatewayStatus } = require('../services/gatewayService');

const SPOT_EVENTS_TOPIC = 'campus/parking/sectors/+/spots/+/events';
const GATEWAY_STATUS_TOPIC = 'campus/parking/sectors/+/gateway/status';

function startMqttSubscriber() {
  const client = mqtt.connect(config.mqttBrokerUrl, {
    reconnectPeriod: 2000,
    clean: true,
    clientId: `parking-backend-${Math.random().toString(16).slice(2)}`
  });

  client.on('connect', () => {
    console.log(`[MQTT] Conectado em ${config.mqttBrokerUrl}`);
    client.subscribe([SPOT_EVENTS_TOPIC, GATEWAY_STATUS_TOPIC], { qos: 1 }, (error) => {
      if (error) {
        console.error('[MQTT] Erro ao assinar tópicos:', error.message);
        return;
      }
      console.log(`[MQTT] Assinando ${SPOT_EVENTS_TOPIC}`);
      console.log(`[MQTT] Assinando ${GATEWAY_STATUS_TOPIC}`);
    });
  });

  client.on('message', async (topic, message) => {
    let payload;
    try {
      payload = JSON.parse(message.toString());
    } catch (error) {
      console.warn(`[MQTT] JSON inválido em ${topic}: ${error.message}`);
      return;
    }

    if (topic.includes('/gateway/status')) {
      try {
        await recordGatewayStatus(payload);
        console.log(`[MQTT] Gateway status salvo: ${payload.sectorId}/${payload.gatewayId} -> ${payload.status}`);
      } catch (error) {
        console.warn(`[MQTT] Gateway status rejeitado em ${topic}: ${error.message}`);
      }
      return;
    }

    try {
      const result = await applySpotEvent(payload);
      if (result?.inserted_event) {
        console.log(`[MQTT] Evento ${payload.eventId} salvo: ${payload.spotId} -> ${payload.state}`);
      } else {
        console.log(`[MQTT] Evento duplicado ignorado pelo banco: ${payload.eventId}`);
      }
      await checkIncidents();
    } catch (error) {
      console.warn(`[MQTT] Evento rejeitado em ${topic}: ${error.message}`);
    }
  });

  client.on('reconnect', () => console.log('[MQTT] Tentando reconectar...'));
  client.on('error', (error) => console.error('[MQTT] Erro:', error.message));

  return client;
}

module.exports = {
  startMqttSubscriber,
  SPOT_EVENTS_TOPIC,
  GATEWAY_STATUS_TOPIC
};
