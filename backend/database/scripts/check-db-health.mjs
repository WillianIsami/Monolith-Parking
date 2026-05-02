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
      { rows: sessionRows },
      { rows: healthRows },
      { rows: navigationRows },
      { rows: leaderboardRows }
    ] = await Promise.all([
      pool.query(`
        SELECT
          COUNT(*)::integer AS total_spots,
          COUNT(*) FILTER (WHERE current_state = 'FREE')::integer AS free_spots,
          COUNT(*) FILTER (WHERE current_state = 'OCCUPIED')::integer AS occupied_spots
        FROM spots
      `),
      pool.query(`
        SELECT
          COUNT(*)::integer AS total_sessions,
          COUNT(*) FILTER (WHERE session_status = 'open')::integer AS open_sessions
        FROM spot_sessions
      `),
      pool.query(`
        SELECT
          sector_id,
          occupied_count,
          free_count,
          occupancy_rate,
          open_incidents,
          gateway_code,
          connectivity_status
        FROM v_sector_command_center
        ORDER BY sector_id
      `),
      pool.query(`
        SELECT
          id_vaga,
          id_setor,
          tempo_estimado_segundos,
          pontuacao_navegacao
        FROM obter_opcoes_navegacao(
          'ENTRY_NORTH',
          3,
          NULL,
          false
        )
      `),
      pool.query(`
        SELECT
          nome_usuario,
          pontos_totais,
          nivel,
          quantidade_conquistas
        FROM vw_ranking_engajamento
        LIMIT 5
      `)
    ]);

    console.log('[check] resumo geral');
    console.table(spotRows);
    console.log('[check] sessoes');
    console.table(sessionRows);
    console.log('[check] centro operacional');
    console.table(healthRows);
    console.log('[check] navegacao sugerida');
    console.table(navigationRows);
    console.log('[check] ranking gamificado');
    console.table(leaderboardRows);
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error('[check] falha na verificacao do banco');
  console.error(error.message);
  process.exitCode = 1;
});
