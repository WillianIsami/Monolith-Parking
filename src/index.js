const config = require('./config');
const createApp = require('./app');
const logger = require('./utils/logger');
const { waitForDatabase } = require('./database/client');
const { startMqttSubscriber } = require('./mqtt/subscriber');
const { checkIncidents } = require('./services/incidentService');

async function main() {
  await waitForDatabase();

  const app = createApp();
  const server = app.listen(config.port, () => {
    logger.info(`[HTTP] API do Estacionamento Inteligente rodando na porta ${config.port}`);
  });

  const mqttClient = startMqttSubscriber();

  const interval = setInterval(() => {
    checkIncidents().catch((error) => logger.error({ err: error }, '[INCIDENTS] Erro na checagem'));
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
  logger.fatal({ err: error }, '[BOOT] Falha ao iniciar aplicação');
  process.exit(1);
});
