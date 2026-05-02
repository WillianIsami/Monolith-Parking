const mqtt = require('mqtt');
require('dotenv').config();
const db = require('../database/client');

const client = mqtt.connect(process.env.MQTT_BROKER_URL || 'mqtt://localhost:1883');

// In-memory idempotency cache (simple): armazena eventId por 5 minutos
const seenEvents = new Map();
const IDEMPOTENCY_TTL_MS = 5 * 60 * 1000;

function markSeen(eventId) {
  seenEvents.set(eventId, Date.now());
  setTimeout(() => seenEvents.delete(eventId), IDEMPOTENCY_TTL_MS);
}

function isSeen(eventId) {
  return seenEvents.has(eventId);
}

function isValidUUID(v) {
  return typeof v === 'string' && /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(v);
}

function normalizeTimestamp(ts) {
  // Accept numbers (seconds or ms) or ISO strings
  if (typeof ts === 'number') {
    // Heuristic: if ts looks like seconds (10 digits) -> multiply
    if (ts < 1e12) ts = ts * 1000;
    const d = new Date(ts);
    return isNaN(d.getTime()) ? null : d.toISOString();
  }
  if (typeof ts === 'string') {
    const d = new Date(ts);
    return isNaN(d.getTime()) ? null : d.toISOString();
  }
  return null;
}

function isValidSpotId(spotId, sectorId) {
  if (typeof spotId !== 'string' || typeof sectorId !== 'string') return false;
  const m = spotId.match(/^([A-C])-(0[1-9]|[12][0-9]|30)$/);
  return m && m[1] === sectorId;
}

const VALID_STATES = new Set(['FREE', 'OCCUPIED']);
const VALID_SECTORS = new Set(['A', 'B', 'C']);

const handleMqttEvents = () => {
  client.on('connect', () => {
    console.log('✅ [MQTT] Conectado ao broker com sucesso!');

    // Assinando os tópicos de eventos e status conforme o contrato
    client.subscribe('campus/parking/sectors/+/spots/+/events');
    client.subscribe('campus/parking/sectors/+/gateway/status');
  });

  client.on('message', async (topic, message) => {
    try {
      const payload = JSON.parse(message.toString());
      console.log(`📩 [MQTT] Mensagem recebida no tópico: ${topic}`);

      // Checagem mínima de campos
      const { eventId, ts, sectorId, spotId, state, source } = payload || {};
      if (!eventId || !ts || !sectorId || !spotId || !state || !source) {
        console.warn('⚠️ [MQTT] Payload inválido (faltando campos obrigatórios)');
        return;
      }

      // Idempotência simples
      if (isSeen(eventId)) {
        console.info(`ℹ️ [MQTT] Evento duplicado ignorado: eventId=${eventId}`);
        return;
      }

      // Normalizar e validar state
      const stateNorm = String(state).toUpperCase();
      if (!VALID_STATES.has(stateNorm)) {
        console.warn(`⚠️ [MQTT] Estado inválido: ${state}`);
        return;
      }

      // Validar sector
      const sectorNorm = String(sectorId).toUpperCase();
      if (!VALID_SECTORS.has(sectorNorm)) {
        console.warn(`⚠️ [MQTT] Sector inválido: ${sectorId}`);
        return;
      }

      // Validar spotId pertence ao sector
      if (!isValidSpotId(String(spotId), sectorNorm)) {
        console.warn(`⚠️ [MQTT] spotId inválido ou não pertence ao sector: ${spotId}`);
        return;
      }

      // Normalizar timestamp
      const tsIso = normalizeTimestamp(ts);
      if (!tsIso) {
        console.warn(`⚠️ [MQTT] Timestamp inválido: ${ts}`);
        return;
      }

      // Marcar como visto para idempotência
      markSeen(eventId);

      const query = `SELECT apply_spot_event($1, $2, $3, $4, $5, $6)`;
      const values = [eventId, tsIso, sectorNorm, spotId, stateNorm, JSON.stringify(payload)];

      await db.query(query, values);
      console.log(`💾 [DB] Evento ${eventId} processado.`);
    } catch (error) {
      console.error('❌ [MQTT] Erro ao processar mensagem:', error.message);
    }
  });
};

module.exports = handleMqttEvents;