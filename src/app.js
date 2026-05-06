const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const pinoHttp = require('pino-http');
const logger = require('./utils/logger');
const routes = require('./http/routes');

function createApp() {
  const app = express();

  app.use(helmet());
  app.use(compression());

  app.get('/favicon.ico', (_req, res) => {
    res.status(204).end();
  });

  app.use(pinoHttp({
    logger,
    serializers: {
      req(req) {
        return {
          id: req.id,
          method: req.method,
          url: req.url,
          remoteAddress: req.remoteAddress
        };
      },
      res(res) {
        return {
          statusCode: res.statusCode
        };
      }
    }
  }));
  app.use(cors());
  app.use(express.json({ limit: '1mb' }));

  app.get('/', (_req, res) => {
    res.json({
      name: 'Monolith Parking',
      description: 'Estacionamento Inteligente Campus - MQTT + HTTP + PostgreSQL',
      health: '/api/v1/health',
      api: '/api/v1'
    });
  });

  app.use('/api/v1', routes);

  app.use((req, res) => {
    res.status(404).json({ error: 'Rota não encontrada', path: req.originalUrl });
  });

  app.use((error, _req, res, _next) => {
    logger.error({ err: error }, '[HTTP] Erro: ' + (error.message || 'Erro interno'));
    res.status(error.statusCode || 500).json({ error: error.message || 'Erro interno do servidor' });
  });

  return app;
}

module.exports = createApp;
