const config = require('./config');
const createApp = require('./app');
const { waitForDatabase } = require('./database/client');
const { startMqttSubscriber } = require('./mqtt/subscriber');
const { checkIncidents } = require('./services/incidentService');

async function main() {
  await waitForDatabase();

  const app = createApp();
  const server = app.listen(config.port, () => {
    console.log(`[HTTP] API do Estacionamento Inteligente rodando na porta ${config.port}`);
  });

  const mqttClient = startMqttSubscriber();

  const interval = setInterval(() => {
    checkIncidents().catch((error) => console.error('[INCIDENTS] Erro:', error.message));
  }, config.incidentCheckIntervalMs);

  function shutdown() {
    clearInterval(interval);
    mqttClient.end(true);
    server.close(() => process.exit(0));
  }

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((error) => {
  console.error('[BOOT] Falha ao iniciar aplicação:', error);
  process.exit(1);
});
