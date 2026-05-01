require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.PGSSLMODE === 'require' ? { rejectUnauthorized: false } : false
});

async function initDB() {
  const client = await pool.connect();
  try {
    // Inicia uma transação (se der erro no meio, ele cancela tudo)
    await client.query('BEGIN');

    // 1. Hierarquia de Localização (Imagem 1)
    await client.query(`
      CREATE TABLE IF NOT EXISTS campuses (
        campus_id UUID PRIMARY KEY,
        campus_code TEXT UNIQUE NOT NULL,
        campus_name TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS parking_facilities (
        facility_id UUID PRIMARY KEY,
        campus_id UUID REFERENCES campuses(campus_id),
        facility_code TEXT UNIQUE NOT NULL,
        initial_capacity INTEGER
      );

      CREATE TABLE IF NOT EXISTS sectors (
        sector_id TEXT PRIMARY KEY,
        facility_id UUID REFERENCES parking_facilities(facility_id),
        capacity INTEGER,
        occupancy_alert_threshold NUMERIC
      );
    `);

    // 2. Vagas, Eventos e Snapshots (Imagem 1)
    await client.query(`
      CREATE TABLE IF NOT EXISTS spots (
        spot_id TEXT PRIMARY KEY,
        sector_id TEXT REFERENCES sectors(sector_id),
        current_state TEXT,
        last_change_ts TIMESTAMP,
        last_event_id UUID
      );

      CREATE TABLE IF NOT EXISTS sector_snapshots (
        ts TIMESTAMP,
        sector_id TEXT REFERENCES sectors(sector_id),
        occupied_count INTEGER,
        free_count INTEGER,
        occupancy_rate NUMERIC,
        PRIMARY KEY (ts, sector_id)
      );

      CREATE TABLE IF NOT EXISTS spot_events (
        event_id UUID PRIMARY KEY,
        ts TIMESTAMP,
        sector_id TEXT REFERENCES sectors(sector_id),
        spot_id TEXT REFERENCES spots(spot_id),
        state TEXT
      );
    `);

    // 3. Incidentes (Imagem 1)
    // Nota: O diagrama exibe apenas 4 campos, mas adicionei as chaves estrangeiras 
    // e timestamps necessários para as regras do seu MVP funcionarem.
    await client.query(`
      CREATE TABLE IF NOT EXISTS incidents (
        id UUID PRIMARY KEY,
        type TEXT,
        severity TEXT,
        status TEXT,
        spot_id TEXT REFERENCES spots(spot_id),
        sector_id TEXT REFERENCES sectors(sector_id),
        ts_open TIMESTAMP,
        ts_close TIMESTAMP,
        evidence_json TEXT
      );
    `);

    // 4. Recomendações (Imagem 2)
    await client.query(`
      CREATE TABLE IF NOT EXISTS recommendations_log (
        id BIGSERIAL PRIMARY KEY,
        from_sector TEXT REFERENCES sectors(sector_id),
        recommended_sector TEXT REFERENCES sectors(sector_id),
        reason TEXT,
        ts TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS recommendation_candidates (
        candidate_id BIGSERIAL PRIMARY KEY,
        recommendation_log_id BIGINT REFERENCES recommendations_log(id),
        candidate_sector TEXT REFERENCES sectors(sector_id),
        ranking_score NUMERIC
      );
    `);

    // 5. Navegação e Mapas (Imagem 2)
    await client.query(`
      CREATE TABLE IF NOT EXISTS map_nodes (
        node_id UUID PRIMARY KEY,
        node_code TEXT UNIQUE,
        pos_x NUMERIC,
        pos_y NUMERIC
      );

      CREATE TABLE IF NOT EXISTS route_templates (
        route_id UUID PRIMARY KEY,
        origin_node_id UUID REFERENCES map_nodes(node_id),
        target_spot_id TEXT REFERENCES spots(spot_id),
        route_score NUMERIC
      );

      CREATE TABLE IF NOT EXISTS navigation_requests (
        navigation_request_id UUID PRIMARY KEY,
        user_id UUID,
        route_id UUID REFERENCES route_templates(route_id),
        recommended_spot_id TEXT REFERENCES spots(spot_id)
      );
    `);

    // Aplica todas as criações
    await client.query('COMMIT');
    console.log('✅ Novas tabelas (Arquitetura ERD Completa) verificadas/criadas!');

  } catch (error) {
    // Se der erro, desfaz a transação
    await client.query('ROLLBACK');
    console.error('❌ Erro ao criar tabelas da nova arquitetura:', error);
  } finally {
    client.release();
  }
}

initDB();

module.exports = {
  query: (text, params) => pool.query(text, params),
};