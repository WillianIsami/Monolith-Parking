import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import dotenv from 'dotenv';
import pg from 'pg';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const databaseRoot = path.resolve(__dirname, '..');

dotenv.config({ path: path.join(databaseRoot, '.env') });

const { Pool } = pg;

async function main() {
  if (!process.env.DATABASE_URL) {
    throw new Error('DATABASE_URL nao definido. Configure no .env ou no ambiente.');
  }

  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.PGSSLMODE === 'require' ? { rejectUnauthorized: false } : undefined
  });

  try {
    const [
      { rows: spotRows },
      { rows: sectorRows },
      { rows: gatewayRows },
      { rows: incidentRows },
      { rows: recommendationRows },
      { rows: eventRows }
    ] = await Promise.all([
      pool.query(`
        SELECT
          COUNT(*)::integer AS total_spots,
          COUNT(*) FILTER (WHERE current_state = 'FREE')::integer AS free_spots,
          COUNT(*) FILTER (WHERE current_state = 'OCCUPIED')::integer AS occupied_spots
        FROM spots
      `),
      pool.query(`
        SELECT sector_id, occupied_count, free_count, occupancy_rate, last_update_ts
        FROM get_sector_occupancy(NULL)
        ORDER BY sector_id
      `),
      pool.query(`
        SELECT sector_id, gateway_id, status, last_status_ts
        FROM v_gateway_current_status
        ORDER BY sector_id
      `),
      pool.query(`
        SELECT status, type, COUNT(*)::integer AS total
        FROM incidents
        GROUP BY status, type
        ORDER BY status, type
      `),
      pool.query(`
        SELECT COUNT(*)::integer AS total_recommendations
        FROM recommendations_log
      `),
      pool.query(`
        SELECT event_id, ts, sector_id, spot_id, state
        FROM spot_events
        ORDER BY ts DESC
        LIMIT 5
      `)
    ]);

    console.log('[check] resumo geral das vagas');
    console.table(spotRows);
    console.log('[check] ocupacao atual por setor');
    console.table(sectorRows);
    console.log('[check] status atual dos gateways');
    console.table(gatewayRows);
    console.log('[check] incidentes por status/tipo');
    console.table(incidentRows);
    console.log('[check] recomendacoes registradas');
    console.table(recommendationRows);
    console.log('[check] ultimos eventos MQTT persistidos');
    console.table(eventRows);
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error('[check] falha na verificacao do banco');
  console.error(error.message);
  process.exitCode = 1;
});
