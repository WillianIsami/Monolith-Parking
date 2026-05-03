import crypto from 'node:crypto';
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

async function persistSpotEvent(pool) {
  const eventId = crypto.randomUUID();
  const ts = new Date().toISOString();
  const payload = {
    eventId,
    ts,
    sectorId: 'A',
    spotId: 'A-11',
    state: 'OCCUPIED',
    source: 'gateway'
  };

  const { rows } = await pool.query(
    `
      SELECT *
      FROM apply_spot_event(
        $1::uuid,
        $2::timestamptz,
        $3::text,
        $4::text,
        $5::text,
        $6::jsonb
      )
    `,
    [eventId, ts, 'A', 'A-11', 'OCCUPIED', JSON.stringify(payload)]
  );

  console.log('[demo] evento de vaga persistido');
  console.table(rows);
}

async function recordGatewayHeartbeat(pool) {
  const { rows } = await pool.query(
    `
      SELECT record_gateway_status(
        now(),
        $1::text,
        $2::text,
        $3::text,
        $4::text,
        $5::jsonb
      ) AS gateway_status_event_id
    `,
    [
      'A',
      'gateway-A',
      'ONLINE',
      'gateway',
      JSON.stringify({
        sectorId: 'A',
        gatewayId: 'gateway-A',
        status: 'ONLINE',
        source: 'gateway'
      })
    ]
  );

  console.log('[demo] status de gateway registrado');
  console.table(rows);
}

async function showMvpQueries(pool) {
  const queries = [
    {
      label: 'ocupacao por setor',
      sql: `
        SELECT sector_id, occupied_count, free_count, occupancy_rate, last_update_ts
        FROM get_sector_occupancy(NULL)
        ORDER BY sector_id
      `
    },
    {
      label: 'vagas livres setor A',
      sql: `
        SELECT spot_id, sector_id, current_state
        FROM get_free_spots('A', 10)
      `
    },
    {
      label: 'incidentes abertos',
      sql: `
        SELECT id, type, severity, sector_id, spot_id, status
        FROM get_incidents('open', NULL)
      `
    },
    {
      label: 'gateways atuais',
      sql: `
        SELECT sector_id, gateway_id, status, last_status_ts
        FROM v_gateway_current_status
        ORDER BY sector_id
      `
    }
  ];

  for (const query of queries) {
    const { rows } = await pool.query(query.sql);
    console.log(`[demo] ${query.label}`);
    console.table(rows);
  }
}

async function main() {
  if (!process.env.DATABASE_URL) {
    throw new Error('DATABASE_URL nao definido. Configure no .env ou no ambiente.');
  }

  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.PGSSLMODE === 'require' ? { rejectUnauthorized: false } : undefined
  });

  try {
    await persistSpotEvent(pool);
    await recordGatewayHeartbeat(pool);
    await showMvpQueries(pool);
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error('[demo] falha no exemplo Node.js');
  console.error(error.message);
  process.exitCode = 1;
});
