const mqtt = require('mqtt');
const config = require('../config');
const logger = require('../utils/logger');
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
    logger.info(`[MQTT] Conectado em ${config.mqttBrokerUrl}`);
    client.subscribe([SPOT_EVENTS_TOPIC, GATEWAY_STATUS_TOPIC], { qos: 1 }, (error) => {
      if (error) {
        logger.error({ err: error }, '[MQTT] Erro ao assinar tópicos');
        return;
      }
      logger.info(`[MQTT] Assinando ${SPOT_EVENTS_TOPIC}`);
      logger.info(`[MQTT] Assinando ${GATEWAY_STATUS_TOPIC}`);
    });
  });

  client.on('message', async (topic, message) => {
    let payload;
    try {
      payload = JSON.parse(message.toString());
    } catch (error) {
      logger.warn({ err: error }, `[MQTT] JSON inválido em ${topic}`);
      return;
    }

    if (topic.includes('/gateway/status')) {
      try {
        await recordGatewayStatus(payload);
        logger.info(`[MQTT] Gateway status salvo: ${payload.sectorId}/${payload.gatewayId} -> ${payload.status}`);
      } catch (error) {
        logger.warn({ err: error }, `[MQTT] Gateway status rejeitado em ${topic}`);
      }
      return;
    }

    let result;
    try {
      result = await applySpotEvent(payload);
    } catch (error) {
      logger.warn({ err: error }, `[MQTT] Evento rejeitado em ${topic}`);
      return;
    }

    if (!result?.inserted_event) {
      logger.info(`[MQTT] Evento duplicado ignorado pelo banco: ${payload.eventId}`);
    } else if (result.applied_to_current_state) {
      logger.info(`[MQTT] Evento ${payload.eventId} salvo e aplicado: ${payload.spotId} -> ${payload.state}`);
    } else {
      logger.warn(`[MQTT] Evento ${payload.eventId} salvo no historico, mas ignorado no estado atual por timestamp antigo: ${payload.spotId} -> ${payload.state}`);
    }

    try {
      await checkIncidents();
    } catch (error) {
      logger.warn({ err: error }, `[INCIDENTS] Falha ao verificar incidentes apos evento ${payload.eventId}`);
    }
  });

  client.on('reconnect', () => logger.info('[MQTT] Tentando reconectar...'));
  client.on('error', (error) => logger.error({ err: error }, '[MQTT] Erro'));

  return client;
}

module.exports = {
  startMqttSubscriber,
  SPOT_EVENTS_TOPIC,
  GATEWAY_STATUS_TOPIC
};
