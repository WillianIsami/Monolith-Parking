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

async function persistExampleEvent(pool) {
  const query = `
    SELECT *
    FROM aplicar_evento_vaga(
      $1::uuid,
      $2::timestamptz,
      $3::sector_code,
      $4::text,
      $5::spot_state,
      $6::jsonb
    )
  `;

  const values = [
    '00000000-0000-0000-0000-000000000011',
    new Date().toISOString(),
    'A',
    'A-11',
    'OCCUPIED',
    JSON.stringify({
      eventId: '00000000-0000-0000-0000-000000000011',
      ts: new Date().toISOString(),
      sectorId: 'A',
      spotId: 'A-11',
      state: 'OCCUPIED',
      source: 'gateway',
      sensorCode: 'SNS-A11'
    })
  ];

  const { rows } = await pool.query(query, values);
  console.log('[demo] evento persistido');
  console.table(rows);
}

async function showOperationalCenter(pool) {
  const { rows } = await pool.query(`
    SELECT
      id_setor,
      nome_setor,
      vagas_ocupadas,
      vagas_livres,
      taxa_ocupacao,
      status_gateway,
      incidentes_abertos,
      taxa_ocupacao_prevista
    FROM vw_centro_operacional_setores
    ORDER BY id_setor
  `);

  console.log('[demo] centro operacional');
  console.table(rows);
}

async function recordRecommendation(pool) {
  const { rows } = await pool.query(
    `
      SELECT registrar_decisao_recomendacao(
        now(),
        $1::sector_code,
        $2::sector_code,
        $3::text,
        $4::numeric(5,4),
        $5::text,
        $6::text,
        $7::jsonb,
        $8::jsonb
      ) AS recommendation_log_id
    `,
    [
      'A',
      'B',
      'Setor A em sobrecarga operacional; Setor B oferece melhor equilibrio.',
      0.9300,
      'R-OP1',
      'node-demo',
      JSON.stringify([
        {
          sectorId: 'B',
          freeCount: 14,
          occupancyRate: 0.53,
          distanceScore: 0.86,
          rankingScore: 0.93,
          reason: 'highest_free_count_then_priority'
        },
        {
          sectorId: 'C',
          freeCount: 9,
          occupancyRate: 0.70,
          distanceScore: 0.77,
          rankingScore: 0.78,
          reason: 'secondary_candidate'
        }
      ]),
      JSON.stringify({
        apiRoute: '/api/v1/recommendation',
        strategy: 'highest_free_count_then_priority'
      })
    ]
  );

  console.log('[demo] recomendacao registrada');
  console.table(rows);
}

async function showNavigationOptions(pool) {
  const { rows } = await pool.query(`
    SELECT
      id_vaga,
      id_setor,
      distancia_metros,
      tempo_estimado_segundos,
      pontuacao_navegacao
    FROM obter_opcoes_navegacao(
      'ENTRY_CENTER',
      5,
      NULL,
      false
    )
  `);

  console.log('[demo] opcoes de navegacao');
  console.table(rows);
}

async function registerNavigationAndPoints(pool) {
  const navigation = await pool.query(
    `
      SELECT registrar_solicitacao_navegacao(
        $1::text,
        $2::text,
        $3::text,
        $4::text,
        NULL,
        $5::jsonb
      ) AS navigation_request_id
    `,
    [
      'driver-demo-04',
      'Nina Costa',
      'ENTRY_CENTER',
      'B-03',
      JSON.stringify({
        channel: 'mobile-app',
        mode: 'smart-gps'
      })
    ]
  );

  const navigationRequestId = navigation.rows[0]?.navigation_request_id;

  const points = await pool.query(
    `
      SELECT registrar_pontos_engajamento(
        $1::text,
        $2::text,
        $3::engagement_event_type,
        $4::integer,
        $5::uuid,
        $6::jsonb
      ) AS engagement_event_id
    `,
    [
      'driver-demo-04',
      'Nina Costa',
      'navigation_completed',
      35,
      navigationRequestId,
      JSON.stringify({
        reason: 'completed-smart-gps-route'
      })
    ]
  );

  console.log('[demo] navegacao registrada');
  console.table(navigation.rows);
  console.log('[demo] pontos registrados');
  console.table(points.rows);
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
    await persistExampleEvent(pool);
    await showOperationalCenter(pool);
    await recordRecommendation(pool);
    await showNavigationOptions(pool);
    await registerNavigationAndPoints(pool);
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error('[demo] falha no exemplo Node.js');
  console.error(error.message);
  process.exitCode = 1;
});
