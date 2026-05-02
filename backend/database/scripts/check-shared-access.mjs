import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import dotenv from 'dotenv';
import pg from 'pg';

const { Client } = pg;

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const databaseRoot = path.resolve(__dirname, '..');

dotenv.config({ path: path.join(databaseRoot, '.env') });

async function withClient(label, connectionString, callback) {
  if (!connectionString || connectionString.includes('change-me')) {
    throw new Error(`${label} nao configurado no .env.`);
  }

  const client = new Client({
    connectionString,
    ssl: process.env.PGSSLMODE === 'require' ? { rejectUnauthorized: false } : undefined
  });

  await client.connect();

  try {
    return await callback(client);
  } finally {
    await client.end();
  }
}

async function main() {
  await withClient('DATABASE_URL', process.env.DATABASE_URL, async (client) => {
    await client.query('BEGIN');
    try {
      await client.query(`
        SELECT log_recommendation(
          now(),
          'A'::sector_code,
          'B'::sector_code,
          'shared access smoke test',
          '{}'::jsonb
        )
      `);
      await client.query('ROLLBACK');
      console.log('[shared-check] writer consegue executar escrita transacional');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    }
  });

  await withClient('TEAM_READER_DATABASE_URL', process.env.TEAM_READER_DATABASE_URL, async (client) => {
    const { rows } = await client.query(`
      SELECT COUNT(*)::integer AS total_spots
      FROM spots
    `);

    console.log(`[shared-check] reader consegue consultar spots: ${rows[0].total_spots}`);

    await client.query('BEGIN');
    try {
      await client.query(`
        INSERT INTO recommendations_log (
          ts,
          from_sector,
          recommended_sector,
          reason,
          data_json
        )
        VALUES (
          now(),
          'A'::sector_code,
          'B'::sector_code,
          'reader write should fail',
          '{}'::jsonb
        )
      `);
      await client.query('ROLLBACK');
      throw new Error('TEAM_READER_DATABASE_URL conseguiu escrever; permissao deveria ser somente leitura.');
    } catch (error) {
      await client.query('ROLLBACK');

      if (!/permission denied|permiss/i.test(error.message)) {
        throw error;
      }

      console.log('[shared-check] reader nao possui permissao de escrita');
    }
  });

  console.log('[shared-check] acesso compartilhado validado');
}

main().catch((error) => {
  console.error('[shared-check] falha na validacao do acesso compartilhado');
  console.error(error.message);
  process.exitCode = 1;
});
