const { Pool } = require('pg');
const config = require('../config');

const pool = new Pool({
  connectionString: config.databaseUrl,
  ssl: config.pgSslMode === 'require' ? { rejectUnauthorized: false } : false
});

pool.on('error', (error) => {
  console.error('[DB] Pool error:', error.message);
});

async function query(text, params) {
  return pool.query(text, params);
}

async function waitForDatabase(maxAttempts = 30) {
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      await query('SELECT 1');
      console.log('[DB] Conexão com PostgreSQL OK.');
      return;
    } catch (error) {
      console.warn(`[DB] Aguardando PostgreSQL (${attempt}/${maxAttempts}): ${error.message}`);
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
