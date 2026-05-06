const { Pool } = require('pg');
const config = require('../config');
const logger = require('../utils/logger');

const pool = new Pool({
  connectionString: config.databaseUrl,
  ssl: config.pgSslMode === 'require' ? { rejectUnauthorized: false } : false
});

pool.on('error', (error) => {
  logger.error({ err: error }, '[DB] Pool error');
});

async function query(text, params) {
  return pool.query(text, params);
}

async function waitForDatabase(maxAttempts = 30) {
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      await query('SELECT 1');
      logger.info('[DB] Conexão com PostgreSQL OK.');
      return;
    } catch (error) {
      logger.warn({ err: error }, `[DB] Aguardando PostgreSQL (${attempt}/${maxAttempts})`);
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }

  throw new Error('PostgreSQL não ficou disponível dentro do limite de tentativas.');
}

async function closePool() {
  await pool.end();
}

module.exports = {
  pool,
  query,
  waitForDatabase,
  closePool
};
