require('dotenv').config();

function numberFromEnv(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

module.exports = {
  port: numberFromEnv('PORT', 3000),
  databaseUrl: process.env.DATABASE_URL || 'postgresql://parking:parking123@localhost:5432/monolith_parking',
  pgSslMode: process.env.PGSSLMODE || 'disable',
  mqttBrokerUrl: process.env.MQTT_BROKER_URL || 'mqtt://localhost:1883',
  incidentCheckIntervalMs: numberFromEnv('INCIDENT_CHECK_INTERVAL_MS', 10000),
  stuckOccupiedMinutes: numberFromEnv('STUCK_OCCUPIED_MINUTES', 390),
  stuckFreeMinutes: numberFromEnv('STUCK_FREE_MINUTES', 720),
  flappingWindowMinutes: numberFromEnv('FLAPPING_WINDOW_MINUTES', 1),
  flappingThreshold: numberFromEnv('FLAPPING_THRESHOLD', 5)
};
