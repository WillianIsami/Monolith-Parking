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

const requiredColumns = {
  spots: ['spot_id', 'sector_id', 'current_state', 'last_change_ts', 'last_event_id'],
  spot_events: ['event_id', 'ts', 'sector_id', 'spot_id', 'state', 'raw_payload_json'],
  sector_snapshots: ['ts', 'sector_id', 'occupied_count', 'free_count', 'occupancy_rate'],
  incidents: ['id', 'ts_open', 'ts_close', 'type', 'severity', 'sector_id', 'spot_id', 'evidence_json', 'status'],
  recommendations_log: ['ts', 'from_sector', 'recommended_sector', 'reason', 'data_json']
};

const advancedTables = [
  'campuses',
  'parking_facilities',
  'sectors',
  'gateways',
  'sensors',
  'gateway_status_events',
  'spot_sessions',
  'recommendation_policies',
  'recommendation_candidates',
  'maintenance_windows',
  'operator_actions',
  'campus_events',
  'sector_forecasts',
  'app_users',
  'map_nodes',
  'map_edges',
  'route_templates',
  'navigation_requests',
  'achievement_catalog',
  'user_achievements',
  'engagement_events'
];

const requiredFunctions = [
  'apply_spot_event',
  'get_sector_occupancy',
  'get_free_spots',
  'get_turnover_report',
  'get_incidents',
  'open_incident',
  'close_incident',
  'log_recommendation',
  'registrar_decisao_recomendacao',
  'obter_opcoes_navegacao',
  'registrar_solicitacao_navegacao',
  'registrar_pontos_engajamento'
];

const requiredConstraints = [
  'fk_spots_sector',
  'fk_spot_events_sector',
  'fk_sector_snapshots_sector',
  'fk_incidents_sector',
  'fk_recommendations_log_from_sector',
  'fk_recommendations_log_recommended_sector'
];

function addResult(results, area, check, ok, details) {
  results.push({
    area,
    check,
    status: ok ? 'OK' : 'FAIL',
    details
  });
}

async function main() {
  if (!process.env.DATABASE_URL) {
    throw new Error('DATABASE_URL nao definido. Configure no .env ou no ambiente.');
  }

  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.PGSSLMODE === 'require' ? { rejectUnauthorized: false } : undefined
  });

  const results = [];

  try {
    const requiredTables = Object.keys(requiredColumns);
    const allTables = [...new Set([...requiredTables, ...advancedTables])];

    const { rows: tableRows } = await pool.query(
      `
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = ANY($1)
      `,
      [allTables]
    );

    const existingTables = new Set(tableRows.map((row) => row.table_name));

    for (const tableName of requiredTables) {
      addResult(
        results,
        'required-schema',
        `table:${tableName}`,
        existingTables.has(tableName),
        existingTables.has(tableName) ? 'tabela existe' : 'tabela ausente'
      );
    }

    const { rows: columnRows } = await pool.query(
      `
        SELECT table_name, column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = ANY($1)
      `,
      [requiredTables]
    );

    const columnsByTable = new Map();
    for (const row of columnRows) {
      if (!columnsByTable.has(row.table_name)) {
        columnsByTable.set(row.table_name, new Set());
      }
      columnsByTable.get(row.table_name).add(row.column_name);
    }

    for (const [tableName, columns] of Object.entries(requiredColumns)) {
      const existingColumns = columnsByTable.get(tableName) ?? new Set();
      const missingColumns = columns.filter((column) => !existingColumns.has(column));

      addResult(
        results,
        'required-schema',
        `columns:${tableName}`,
        missingColumns.length === 0,
        missingColumns.length === 0 ? 'colunas obrigatorias presentes' : `faltando: ${missingColumns.join(', ')}`
      );
    }

    const { rows: spotRows } = await pool.query(`
      SELECT
        COUNT(*)::integer AS total_spots,
        COUNT(*) FILTER (WHERE sector_id = 'A')::integer AS sector_a,
        COUNT(*) FILTER (WHERE sector_id = 'B')::integer AS sector_b,
        COUNT(*) FILTER (WHERE sector_id = 'C')::integer AS sector_c
      FROM spots
    `);

    const spotStats = spotRows[0];
    addResult(
      results,
      'seed',
      '90-spots',
      spotStats.total_spots === 90 && spotStats.sector_a === 30 && spotStats.sector_b === 30 && spotStats.sector_c === 30,
      `total=${spotStats.total_spots}; A=${spotStats.sector_a}; B=${spotStats.sector_b}; C=${spotStats.sector_c}`
    );

    const { rows: snapshotRows } = await pool.query(`
      SELECT COUNT(*)::integer AS total_snapshots
      FROM sector_snapshots
    `);

    addResult(
      results,
      'seed',
      'initial-sector-snapshots',
      snapshotRows[0].total_snapshots >= 3,
      `snapshots=${snapshotRows[0].total_snapshots}`
    );

    const { rows: functionRows } = await pool.query(
      `
        SELECT DISTINCT p.proname AS function_name
        FROM pg_proc p
        JOIN pg_namespace n
          ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = ANY($1)
      `,
      [requiredFunctions]
    );

    const existingFunctions = new Set(functionRows.map((row) => row.function_name));
    for (const functionName of requiredFunctions) {
      addResult(
        results,
        'functions',
        functionName,
        existingFunctions.has(functionName),
        existingFunctions.has(functionName) ? 'funcao disponivel' : 'funcao ausente'
      );
    }

    for (const tableName of advancedTables) {
      addResult(
        results,
        'advanced-platform',
        `table:${tableName}`,
        existingTables.has(tableName),
        existingTables.has(tableName) ? 'tabela avancada existe' : 'tabela avancada ausente'
      );
    }

    const { rows: constraintRows } = await pool.query(
      `
        SELECT conname
        FROM pg_constraint
        WHERE conname = ANY($1)
      `,
      [requiredConstraints]
    );

    const existingConstraints = new Set(constraintRows.map((row) => row.conname));
    for (const constraintName of requiredConstraints) {
      addResult(
        results,
        'integrity',
        constraintName,
        existingConstraints.has(constraintName),
        existingConstraints.has(constraintName) ? 'fk presente' : 'fk ausente'
      );
    }

    const { rows: navigationRows } = await pool.query(`
      SELECT COUNT(*)::integer AS option_count
      FROM obter_opcoes_navegacao('ENTRY_NORTH', 5, NULL, false)
    `);

    addResult(
      results,
      'gamification',
      'navigation-options',
      navigationRows[0].option_count > 0,
      `opcoes=${navigationRows[0].option_count}`
    );

    const { rows: leaderboardRows } = await pool.query(`
      SELECT COUNT(*)::integer AS user_count
      FROM vw_ranking_engajamento
    `);

    addResult(
      results,
      'gamification',
      'leaderboard',
      leaderboardRows[0].user_count > 0,
      `usuarios=${leaderboardRows[0].user_count}`
    );

    console.table(results);

    const failed = results.filter((result) => result.status !== 'OK');
    if (failed.length > 0) {
      console.error(`[requirements] ${failed.length} verificacao(oes) falharam.`);
      process.exitCode = 1;
      return;
    }

    console.log('[requirements] banco atende aos requisitos obrigatorios e a camada avancada/gamificada.');
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error('[requirements] falha na verificacao');
  console.error(error.message);
  process.exitCode = 1;
});
