DO $$
BEGIN
  CREATE TYPE facility_type AS ENUM ('surface', 'garage', 'hybrid');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE asset_status AS ENUM ('online', 'offline', 'degraded', 'maintenance');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE spot_category AS ENUM (
    'standard',
    'accessible',
    'ev',
    'motorcycle',
    'visitor',
    'staff',
    'loading'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE parking_session_status AS ENUM ('open', 'closed');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE maintenance_status AS ENUM ('planned', 'active', 'completed', 'canceled');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE operator_action_type AS ENUM (
    'incident_acknowledged',
    'incident_closed',
    'manual_override',
    'maintenance_scheduled',
    'maintenance_completed',
    'recommendation_overridden',
    'gateway_recovered'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE campus_event_type AS ENUM (
    'academic',
    'sports',
    'concert',
    'weather',
    'construction',
    'emergency'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE policy_status AS ENUM ('active', 'inactive');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS campuses (
  campus_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campus_code text NOT NULL UNIQUE,
  campus_name text NOT NULL,
  timezone_name text NOT NULL DEFAULT 'America/Sao_Paulo',
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS parking_facilities (
  facility_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campus_id uuid NOT NULL REFERENCES campuses (campus_id) ON DELETE RESTRICT,
  facility_code text NOT NULL UNIQUE,
  facility_name text NOT NULL,
  facility_type facility_type NOT NULL DEFAULT 'surface',
  total_capacity integer NOT NULL CHECK (total_capacity >= 0),
  operating_hours_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS sectors (
  sector_id sector_code PRIMARY KEY,
  facility_id uuid NOT NULL REFERENCES parking_facilities (facility_id) ON DELETE RESTRICT,
  sector_name text NOT NULL,
  display_order integer NOT NULL DEFAULT 1,
  capacity integer NOT NULL CHECK (capacity > 0),
  occupancy_alert_threshold numeric(5,4) NOT NULL DEFAULT 0.9000 CHECK (
    occupancy_alert_threshold >= 0 AND occupancy_alert_threshold <= 1
  ),
  congestion_threshold numeric(5,4) NOT NULL DEFAULT 0.7500 CHECK (
    congestion_threshold >= 0 AND congestion_threshold <= 1
  ),
  recommendation_priority numeric(8,4) NOT NULL DEFAULT 1.0000,
  geojson jsonb NOT NULL DEFAULT '{}'::jsonb,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS gateways (
  gateway_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sector_id sector_code NOT NULL UNIQUE REFERENCES sectors (sector_id) ON DELETE RESTRICT,
  gateway_code text NOT NULL UNIQUE,
  gateway_name text NOT NULL,
  firmware_version text,
  connectivity_status asset_status NOT NULL DEFAULT 'online',
  installed_at timestamptz,
  last_heartbeat_ts timestamptz,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb
);

ALTER TABLE spots
  ADD COLUMN IF NOT EXISTS spot_category spot_category NOT NULL DEFAULT 'standard';

ALTER TABLE spots
  ADD COLUMN IF NOT EXISTS is_priority boolean NOT NULL DEFAULT false;

ALTER TABLE spots
  ADD COLUMN IF NOT EXISTS grid_row integer;

ALTER TABLE spots
  ADD COLUMN IF NOT EXISTS grid_col integer;

ALTER TABLE spots
  ADD COLUMN IF NOT EXISTS lane_code text;

ALTER TABLE spots
  ADD COLUMN IF NOT EXISTS metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE TABLE IF NOT EXISTS sensors (
  sensor_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  spot_id text NOT NULL UNIQUE REFERENCES spots (spot_id) ON DELETE RESTRICT,
  gateway_id uuid NOT NULL REFERENCES gateways (gateway_id) ON DELETE RESTRICT,
  sensor_code text NOT NULL UNIQUE,
  device_status asset_status NOT NULL DEFAULT 'online',
  battery_level numeric(5,2) CHECK (battery_level >= 0 AND battery_level <= 100),
  installed_at timestamptz,
  last_seen_ts timestamptz,
  calibration_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS gateway_status_events (
  gateway_status_event_id bigserial PRIMARY KEY,
  ts timestamptz NOT NULL,
  sector_id sector_code NOT NULL REFERENCES sectors (sector_id) ON DELETE RESTRICT,
  gateway_id uuid REFERENCES gateways (gateway_id) ON DELETE RESTRICT,
  status asset_status NOT NULL,
  latency_ms integer CHECK (latency_ms IS NULL OR latency_ms >= 0),
  source_topic text,
  raw_payload_json jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_gateway_status_events_sector_ts
  ON gateway_status_events (sector_id, ts DESC);

CREATE TABLE IF NOT EXISTS spot_sessions (
  session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  spot_id text NOT NULL REFERENCES spots (spot_id) ON DELETE RESTRICT,
  sector_id sector_code NOT NULL REFERENCES sectors (sector_id) ON DELETE RESTRICT,
  entry_event_id uuid NOT NULL REFERENCES spot_events (event_id) ON DELETE RESTRICT,
  exit_event_id uuid REFERENCES spot_events (event_id) ON DELETE RESTRICT,
  started_at timestamptz NOT NULL,
  ended_at timestamptz,
  duration_seconds integer,
  session_status parking_session_status NOT NULL DEFAULT 'open',
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (
    (session_status = 'open' AND ended_at IS NULL AND exit_event_id IS NULL AND duration_seconds IS NULL) OR
    (session_status = 'closed' AND ended_at IS NOT NULL AND exit_event_id IS NOT NULL AND duration_seconds IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_spot_sessions_sector_started
  ON spot_sessions (sector_id, started_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_spot_sessions_open_unique
  ON spot_sessions (spot_id)
  WHERE session_status = 'open';

CREATE UNIQUE INDEX IF NOT EXISTS idx_spot_sessions_entry_event_unique
  ON spot_sessions (entry_event_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_spot_sessions_exit_event_unique
  ON spot_sessions (exit_event_id)
  WHERE exit_event_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS recommendation_policies (
  policy_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  policy_code text NOT NULL UNIQUE,
  policy_name text NOT NULL,
  description text,
  min_source_occupancy_rate numeric(5,4) NOT NULL DEFAULT 0.9000 CHECK (
    min_source_occupancy_rate >= 0 AND min_source_occupancy_rate <= 1
  ),
  target_selection_strategy text NOT NULL,
  allow_cross_facility boolean NOT NULL DEFAULT false,
  priority_weight numeric(8,4) NOT NULL DEFAULT 1.0000,
  policy_status policy_status NOT NULL DEFAULT 'active',
  config_json jsonb NOT NULL DEFAULT '{}'::jsonb
);

ALTER TABLE recommendations_log
  ADD COLUMN IF NOT EXISTS policy_id uuid REFERENCES recommendation_policies (policy_id) ON DELETE SET NULL;

ALTER TABLE recommendations_log
  ADD COLUMN IF NOT EXISTS request_id uuid DEFAULT gen_random_uuid();

ALTER TABLE recommendations_log
  ADD COLUMN IF NOT EXISTS source_occupancy_rate numeric(5,4) CHECK (
    source_occupancy_rate IS NULL OR (source_occupancy_rate >= 0 AND source_occupancy_rate <= 1)
  );

ALTER TABLE recommendations_log
  ADD COLUMN IF NOT EXISTS target_free_count integer CHECK (
    target_free_count IS NULL OR target_free_count >= 0
  );

ALTER TABLE recommendations_log
  ADD COLUMN IF NOT EXISTS ranking_score numeric(8,4);

ALTER TABLE recommendations_log
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

ALTER TABLE recommendations_log
  ADD COLUMN IF NOT EXISTS created_by text NOT NULL DEFAULT 'system';

CREATE TABLE IF NOT EXISTS recommendation_candidates (
  candidate_id bigserial PRIMARY KEY,
  recommendation_log_id bigint NOT NULL REFERENCES recommendations_log (id) ON DELETE CASCADE,
  candidate_sector sector_code NOT NULL REFERENCES sectors (sector_id) ON DELETE RESTRICT,
  free_count integer NOT NULL CHECK (free_count >= 0),
  occupancy_rate numeric(5,4) NOT NULL CHECK (occupancy_rate >= 0 AND occupancy_rate <= 1),
  distance_score numeric(8,4),
  ranking_score numeric(8,4),
  candidate_reason text,
  candidate_data_json jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_recommendation_candidates_log_id
  ON recommendation_candidates (recommendation_log_id);

ALTER TABLE incidents
  ADD COLUMN IF NOT EXISTS rule_code text;

ALTER TABLE incidents
  ADD COLUMN IF NOT EXISTS acknowledged_at timestamptz;

ALTER TABLE incidents
  ADD COLUMN IF NOT EXISTS acknowledged_by text;

ALTER TABLE incidents
  ADD COLUMN IF NOT EXISTS resolution_notes text;

ALTER TABLE incidents
  ADD COLUMN IF NOT EXISTS resolution_data_json jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE TABLE IF NOT EXISTS maintenance_windows (
  maintenance_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_type text NOT NULL CHECK (target_type IN ('sector', 'spot', 'sensor', 'gateway')),
  target_id text NOT NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz,
  status maintenance_status NOT NULL DEFAULT 'planned',
  reason text NOT NULL,
  created_by text NOT NULL,
  notes text,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (ends_at IS NULL OR ends_at >= starts_at)
);

CREATE INDEX IF NOT EXISTS idx_maintenance_windows_target
  ON maintenance_windows (target_type, target_id, status);

CREATE TABLE IF NOT EXISTS operator_actions (
  action_id bigserial PRIMARY KEY,
  ts timestamptz NOT NULL DEFAULT now(),
  actor_name text NOT NULL,
  action_type operator_action_type NOT NULL,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  details_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  notes text
);

CREATE INDEX IF NOT EXISTS idx_operator_actions_ts
  ON operator_actions (ts DESC);

CREATE TABLE IF NOT EXISTS campus_events (
  campus_event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campus_id uuid NOT NULL REFERENCES campuses (campus_id) ON DELETE RESTRICT,
  event_type campus_event_type NOT NULL,
  event_name text NOT NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  expected_attendance integer CHECK (expected_attendance IS NULL OR expected_attendance >= 0),
  impact_multiplier numeric(6,3) NOT NULL DEFAULT 1.000 CHECK (impact_multiplier > 0),
  affected_sectors_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (ends_at >= starts_at)
);

CREATE TABLE IF NOT EXISTS sector_forecasts (
  forecast_id bigserial PRIMARY KEY,
  generated_at timestamptz NOT NULL,
  forecast_for_ts timestamptz NOT NULL,
  sector_id sector_code NOT NULL REFERENCES sectors (sector_id) ON DELETE RESTRICT,
  predicted_occupied_count integer NOT NULL CHECK (predicted_occupied_count >= 0),
  predicted_free_count integer NOT NULL CHECK (predicted_free_count >= 0),
  predicted_occupancy_rate numeric(5,4) NOT NULL CHECK (
    predicted_occupancy_rate >= 0 AND predicted_occupancy_rate <= 1
  ),
  model_name text NOT NULL,
  confidence_score numeric(5,4) CHECK (
    confidence_score IS NULL OR (confidence_score >= 0 AND confidence_score <= 1)
  ),
  drivers_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (forecast_for_ts, sector_id, model_name)
);

CREATE INDEX IF NOT EXISTS idx_sector_forecasts_sector_ts
  ON sector_forecasts (sector_id, forecast_for_ts DESC);

COMMENT ON TABLE campuses IS 'Entidade raiz para evoluir o projeto de estacionamento para uma plataforma de mobilidade de campus.';
COMMENT ON TABLE parking_facilities IS 'Instalacoes fisicas de estacionamento do campus.';
COMMENT ON TABLE sectors IS 'Metadados operacionais dos setores, com capacidade e thresholds.';
COMMENT ON TABLE gateways IS 'Gateways IoT responsaveis pela recepcao ou consolidacao dos sensores de cada setor.';
COMMENT ON TABLE sensors IS 'Sensores individuais associados a vagas e gateways.';
COMMENT ON TABLE gateway_status_events IS 'Historico de saude e conectividade dos gateways.';
COMMENT ON TABLE spot_sessions IS 'Sessoes de uso derivadas das transicoes OCCUPIED/FREE para medir permanencia.';
COMMENT ON TABLE recommendation_policies IS 'Politicas explicitas de recomendacao de setores.';
COMMENT ON TABLE recommendation_candidates IS 'Ranking de candidatos considerados a cada recomendacao.';
COMMENT ON TABLE maintenance_windows IS 'Janela planejada ou ativa de manutencao de ativos do sistema.';
COMMENT ON TABLE operator_actions IS 'Trilha de acoes humanas na operacao.';
COMMENT ON TABLE campus_events IS 'Eventos do campus que ajudam a explicar variacoes de demanda.';
COMMENT ON TABLE sector_forecasts IS 'Previsoes operacionais de ocupacao por setor.';

CREATE OR REPLACE VIEW v_gateway_health AS
SELECT
  g.gateway_id,
  g.gateway_code,
  g.gateway_name,
  g.sector_id,
  g.connectivity_status,
  g.last_heartbeat_ts,
  CASE
    WHEN g.last_heartbeat_ts IS NULL THEN NULL
    ELSE EXTRACT(EPOCH FROM (now() - g.last_heartbeat_ts))::integer
  END AS heartbeat_age_seconds,
  COUNT(s.sensor_id)::integer AS sensor_count,
  ROUND(AVG(s.battery_level), 2) AS avg_sensor_battery_level
FROM gateways g
LEFT JOIN sensors s
  ON s.gateway_id = g.gateway_id
GROUP BY
  g.gateway_id,
  g.gateway_code,
  g.gateway_name,
  g.sector_id,
  g.connectivity_status,
  g.last_heartbeat_ts;

CREATE OR REPLACE VIEW v_spot_session_metrics AS
SELECT
  sec.sector_id,
  COALESCE(counts.completed_sessions, 0) AS completed_sessions,
  COALESCE(counts.open_sessions, 0) AS open_sessions,
  duration_stats.avg_duration_seconds,
  duration_stats.median_duration_seconds
FROM sectors sec
LEFT JOIN LATERAL (
  SELECT
    COUNT(*) FILTER (WHERE ss.session_status = 'closed')::integer AS completed_sessions,
    COUNT(*) FILTER (WHERE ss.session_status = 'open')::integer AS open_sessions
  FROM spot_sessions ss
  WHERE ss.sector_id = sec.sector_id
) counts
  ON true
LEFT JOIN LATERAL (
  SELECT
    ROUND(AVG(ss.duration_seconds), 2) AS avg_duration_seconds,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ss.duration_seconds) AS median_duration_seconds
  FROM spot_sessions ss
  WHERE ss.sector_id = sec.sector_id
    AND ss.duration_seconds IS NOT NULL
) duration_stats
  ON true;

CREATE OR REPLACE VIEW v_sector_command_center AS
SELECT
  sec.sector_id,
  sec.sector_name,
  sec.capacity,
  sec.occupancy_alert_threshold,
  sec.congestion_threshold,
  sec.recommendation_priority,
  COALESCE(curr.occupied_count, 0) AS occupied_count,
  COALESCE(curr.free_count, sec.capacity) AS free_count,
  COALESCE(curr.occupancy_rate, 0)::numeric(5,4) AS occupancy_rate,
  gw.gateway_code,
  gw.connectivity_status,
  gw.last_heartbeat_ts,
  COALESCE(inc.open_incidents, 0) AS open_incidents,
  COALESCE(ssm.completed_sessions, 0) AS completed_sessions,
  COALESCE(ssm.open_sessions, 0) AS open_sessions,
  COALESCE(maint.active_maintenances, 0) AS active_maintenances,
  fc.forecast_for_ts AS next_forecast_at,
  fc.predicted_occupancy_rate AS next_predicted_occupancy_rate
FROM sectors sec
LEFT JOIN v_sector_summary_current curr
  ON curr.sector_id = sec.sector_id
LEFT JOIN gateways gw
  ON gw.sector_id = sec.sector_id
LEFT JOIN (
  SELECT sector_id, COUNT(*)::integer AS open_incidents
  FROM incidents
  WHERE status = 'open'
  GROUP BY sector_id
) inc
  ON inc.sector_id = sec.sector_id
LEFT JOIN v_spot_session_metrics ssm
  ON ssm.sector_id = sec.sector_id
LEFT JOIN LATERAL (
  SELECT COUNT(*)::integer AS active_maintenances
  FROM maintenance_windows mw
  WHERE mw.target_type = 'sector'
    AND mw.target_id = sec.sector_id::text
    AND mw.status IN ('planned', 'active')
    AND mw.starts_at <= now()
    AND (mw.ends_at IS NULL OR mw.ends_at >= now())
) maint
  ON true
LEFT JOIN LATERAL (
  SELECT
    sf.forecast_for_ts,
    sf.predicted_occupancy_rate
  FROM sector_forecasts sf
  WHERE sf.sector_id = sec.sector_id
    AND sf.forecast_for_ts >= now()
  ORDER BY sf.forecast_for_ts
  LIMIT 1
) fc
  ON true
ORDER BY sec.display_order, sec.sector_id;

CREATE OR REPLACE VIEW vw_saude_gateways AS
SELECT
  gateway_code AS codigo_gateway,
  gateway_name AS nome_gateway,
  sector_id AS id_setor,
  connectivity_status AS status_conectividade,
  last_heartbeat_ts AS ultimo_heartbeat_em,
  heartbeat_age_seconds AS idade_heartbeat_segundos,
  sensor_count AS quantidade_sensores,
  avg_sensor_battery_level AS bateria_media_sensores
FROM v_gateway_health;

CREATE OR REPLACE VIEW vw_metricas_sessoes_vagas AS
SELECT
  sector_id AS id_setor,
  completed_sessions AS sessoes_concluidas,
  open_sessions AS sessoes_abertas,
  avg_duration_seconds AS duracao_media_segundos,
  median_duration_seconds AS duracao_mediana_segundos
FROM v_spot_session_metrics;

CREATE OR REPLACE VIEW vw_centro_operacional_setores AS
SELECT
  sector_id AS id_setor,
  sector_name AS nome_setor,
  capacity AS capacidade,
  occupancy_alert_threshold AS limite_alerta_ocupacao,
  congestion_threshold AS limite_congestionamento,
  recommendation_priority AS prioridade_recomendacao,
  occupied_count AS vagas_ocupadas,
  free_count AS vagas_livres,
  occupancy_rate AS taxa_ocupacao,
  gateway_code AS codigo_gateway,
  connectivity_status AS status_gateway,
  last_heartbeat_ts AS ultimo_heartbeat_gateway_em,
  open_incidents AS incidentes_abertos,
  completed_sessions AS sessoes_concluidas,
  open_sessions AS sessoes_abertas,
  active_maintenances AS manutencoes_ativas,
  next_forecast_at AS proxima_previsao_em,
  next_predicted_occupancy_rate AS taxa_ocupacao_prevista
FROM v_sector_command_center;

CREATE OR REPLACE FUNCTION sync_spot_session_transition(
  p_sector_id sector_code,
  p_spot_id text,
  p_previous_state spot_state,
  p_new_state spot_state,
  p_ts timestamptz,
  p_event_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_open_session_id uuid;
BEGIN
  IF p_previous_state IS DISTINCT FROM p_new_state THEN
    IF COALESCE(p_previous_state, 'FREE'::spot_state) = 'FREE' AND p_new_state = 'OCCUPIED' THEN
      SELECT session_id
      INTO v_open_session_id
      FROM spot_sessions
      WHERE spot_id = p_spot_id
        AND session_status = 'open'
      ORDER BY started_at DESC
      LIMIT 1;

      IF v_open_session_id IS NULL THEN
        INSERT INTO spot_sessions (
          spot_id,
          sector_id,
          entry_event_id,
          started_at,
          session_status
        )
        VALUES (
          p_spot_id,
          p_sector_id,
          p_event_id,
          p_ts,
          'open'
        );
      END IF;
    ELSIF p_previous_state = 'OCCUPIED' AND p_new_state = 'FREE' THEN
      UPDATE spot_sessions
      SET
        exit_event_id = p_event_id,
        ended_at = p_ts,
        duration_seconds = GREATEST(EXTRACT(EPOCH FROM (p_ts - started_at))::integer, 0),
        session_status = 'closed'
      WHERE session_id = (
        SELECT session_id
        FROM spot_sessions
        WHERE spot_id = p_spot_id
          AND session_status = 'open'
        ORDER BY started_at DESC
        LIMIT 1
      );
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION register_gateway_status_event(
  p_ts timestamptz,
  p_sector_id sector_code,
  p_status asset_status,
  p_gateway_code text DEFAULT NULL,
  p_latency_ms integer DEFAULT NULL,
  p_source_topic text DEFAULT NULL,
  p_raw_payload_json jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_gateway_id uuid;
  v_status_event_id bigint;
BEGIN
  IF p_gateway_code IS NOT NULL THEN
    SELECT gateway_id
    INTO v_gateway_id
    FROM gateways
    WHERE gateway_code = p_gateway_code
    LIMIT 1;
  END IF;

  IF v_gateway_id IS NULL THEN
    SELECT gateway_id
    INTO v_gateway_id
    FROM gateways
    WHERE sector_id = p_sector_id
    LIMIT 1;
  END IF;

  INSERT INTO gateway_status_events (
    ts,
    sector_id,
    gateway_id,
    status,
    latency_ms,
    source_topic,
    raw_payload_json
  )
  VALUES (
    p_ts,
    p_sector_id,
    v_gateway_id,
    p_status,
    p_latency_ms,
    p_source_topic,
    COALESCE(p_raw_payload_json, '{}'::jsonb)
  )
  RETURNING gateway_status_event_id INTO v_status_event_id;

  IF v_gateway_id IS NOT NULL THEN
    UPDATE gateways
    SET
      connectivity_status = p_status,
      last_heartbeat_ts = p_ts
    WHERE gateway_id = v_gateway_id;
  END IF;

  RETURN v_status_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION record_operator_action(
  p_ts timestamptz,
  p_actor_name text,
  p_action_type operator_action_type,
  p_entity_type text,
  p_entity_id text,
  p_details_json jsonb DEFAULT '{}'::jsonb,
  p_notes text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_action_id bigint;
BEGIN
  INSERT INTO operator_actions (
    ts,
    actor_name,
    action_type,
    entity_type,
    entity_id,
    details_json,
    notes
  )
  VALUES (
    p_ts,
    p_actor_name,
    p_action_type,
    p_entity_type,
    p_entity_id,
    COALESCE(p_details_json, '{}'::jsonb),
    p_notes
  )
  RETURNING action_id INTO v_action_id;

  RETURN v_action_id;
END;
$$;

CREATE OR REPLACE FUNCTION schedule_maintenance_window(
  p_target_type text,
  p_target_id text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_reason text,
  p_created_by text,
  p_notes text DEFAULT NULL,
  p_metadata_json jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_maintenance_id uuid;
BEGIN
  INSERT INTO maintenance_windows (
    target_type,
    target_id,
    starts_at,
    ends_at,
    status,
    reason,
    created_by,
    notes,
    metadata_json
  )
  VALUES (
    p_target_type,
    p_target_id,
    p_starts_at,
    p_ends_at,
    CASE
      WHEN p_starts_at <= now() AND (p_ends_at IS NULL OR p_ends_at >= now()) THEN 'active'::maintenance_status
      ELSE 'planned'::maintenance_status
    END,
    p_reason,
    p_created_by,
    p_notes,
    COALESCE(p_metadata_json, '{}'::jsonb)
  )
  RETURNING maintenance_id INTO v_maintenance_id;

  RETURN v_maintenance_id;
END;
$$;

CREATE OR REPLACE FUNCTION generate_sector_forecasts(
  p_generated_at timestamptz DEFAULT now(),
  p_horizon_minutes integer DEFAULT 30,
  p_model_name text DEFAULT 'naive_baseline'
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_rows integer := 0;
BEGIN
  WITH recent AS (
    SELECT
      sec.sector_id,
      sec.capacity,
      COALESCE(curr.occupancy_rate, 0)::numeric(5,4) AS current_rate,
      COALESCE(AVG(ss.occupancy_rate), COALESCE(curr.occupancy_rate, 0), 0)::numeric(8,4) AS avg_recent_rate
    FROM sectors sec
    LEFT JOIN v_sector_summary_current curr
      ON curr.sector_id = sec.sector_id
    LEFT JOIN sector_snapshots ss
      ON ss.sector_id = sec.sector_id
      AND ss.ts >= p_generated_at - interval '60 minutes'
      AND ss.ts <= p_generated_at
    GROUP BY
      sec.sector_id,
      sec.capacity,
      curr.occupancy_rate
  ),
  predicted AS (
    SELECT
      sector_id,
      capacity,
      current_rate,
      avg_recent_rate,
      LEAST(
        1::numeric,
        GREATEST(
          0::numeric,
          ROUND(current_rate + ((current_rate - avg_recent_rate) * 0.50), 4)
        )
      )::numeric(5,4) AS predicted_rate
    FROM recent
  ),
  final_prediction AS (
    SELECT
      sector_id,
      current_rate,
      avg_recent_rate,
      predicted_rate,
      LEAST(capacity, GREATEST(0, ROUND(predicted_rate * capacity)::integer)) AS predicted_occupied_count,
      capacity
    FROM predicted
  )
  INSERT INTO sector_forecasts (
    generated_at,
    forecast_for_ts,
    sector_id,
    predicted_occupied_count,
    predicted_free_count,
    predicted_occupancy_rate,
    model_name,
    confidence_score,
    drivers_json
  )
  SELECT
    p_generated_at,
    p_generated_at + make_interval(mins => p_horizon_minutes),
    fp.sector_id,
    fp.predicted_occupied_count,
    GREATEST(fp.capacity - fp.predicted_occupied_count, 0),
    fp.predicted_rate,
    p_model_name,
    0.5500,
    jsonb_build_object(
      'currentRate', fp.current_rate,
      'avgRecentRate', fp.avg_recent_rate,
      'horizonMinutes', p_horizon_minutes
    )
  FROM final_prediction fp
  ON CONFLICT (forecast_for_ts, sector_id, model_name) DO UPDATE
  SET
    generated_at = EXCLUDED.generated_at,
    predicted_occupied_count = EXCLUDED.predicted_occupied_count,
    predicted_free_count = EXCLUDED.predicted_free_count,
    predicted_occupancy_rate = EXCLUDED.predicted_occupancy_rate,
    confidence_score = EXCLUDED.confidence_score,
    drivers_json = EXCLUDED.drivers_json;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

CREATE OR REPLACE FUNCTION acknowledge_incident(
  p_incident_id uuid,
  p_acknowledged_at timestamptz,
  p_acknowledged_by text,
  p_notes text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE incidents
  SET
    acknowledged_at = p_acknowledged_at,
    acknowledged_by = p_acknowledged_by,
    resolution_notes = COALESCE(p_notes, resolution_notes)
  WHERE id = p_incident_id;
END;
$$;

CREATE OR REPLACE FUNCTION close_incident(
  p_incident_id uuid,
  p_ts_close timestamptz,
  p_resolution_notes text,
  p_resolution_data_json jsonb
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE incidents
  SET
    ts_close = p_ts_close,
    status = 'closed',
    resolution_notes = COALESCE(p_resolution_notes, resolution_notes),
    resolution_data_json = COALESCE(p_resolution_data_json, resolution_data_json)
  WHERE id = p_incident_id
    AND status = 'open';
END;
$$;

CREATE OR REPLACE FUNCTION record_recommendation_decision(
  p_ts timestamptz,
  p_from_sector sector_code,
  p_recommended_sector sector_code,
  p_reason text,
  p_source_occupancy_rate numeric(5,4),
  p_policy_code text DEFAULT 'R-OP1',
  p_created_by text DEFAULT 'system',
  p_candidates_json jsonb DEFAULT '[]'::jsonb,
  p_data_json jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_policy_id uuid;
  v_log_id bigint;
  v_target_free_count integer;
  v_ranking_score numeric(8,4);
BEGIN
  SELECT policy_id
  INTO v_policy_id
  FROM recommendation_policies
  WHERE policy_code = p_policy_code
    AND policy_status = 'active'
  LIMIT 1;

  SELECT
    (candidate->>'freeCount')::integer,
    (candidate->>'rankingScore')::numeric(8,4)
  INTO
    v_target_free_count,
    v_ranking_score
  FROM jsonb_array_elements(COALESCE(p_candidates_json, '[]'::jsonb)) candidate
  WHERE candidate->>'sectorId' = p_recommended_sector::text
  LIMIT 1;

  INSERT INTO recommendations_log (
    ts,
    from_sector,
    recommended_sector,
    reason,
    data_json,
    policy_id,
    source_occupancy_rate,
    target_free_count,
    ranking_score,
    created_by
  )
  VALUES (
    p_ts,
    p_from_sector,
    p_recommended_sector,
    p_reason,
    COALESCE(p_data_json, '{}'::jsonb),
    v_policy_id,
    p_source_occupancy_rate,
    v_target_free_count,
    v_ranking_score,
    p_created_by
  )
  RETURNING id INTO v_log_id;

  INSERT INTO recommendation_candidates (
    recommendation_log_id,
    candidate_sector,
    free_count,
    occupancy_rate,
    distance_score,
    ranking_score,
    candidate_reason,
    candidate_data_json
  )
  SELECT
    v_log_id,
    (candidate->>'sectorId')::sector_code,
    COALESCE((candidate->>'freeCount')::integer, 0),
    COALESCE((candidate->>'occupancyRate')::numeric(5,4), 0),
    (candidate->>'distanceScore')::numeric(8,4),
    (candidate->>'rankingScore')::numeric(8,4),
    candidate->>'reason',
    candidate
  FROM jsonb_array_elements(COALESCE(p_candidates_json, '[]'::jsonb)) candidate;

  RETURN v_log_id;
END;
$$;

CREATE OR REPLACE FUNCTION registrar_status_gateway(
  p_data_hora timestamptz,
  p_id_setor sector_code,
  p_status asset_status,
  p_codigo_gateway text DEFAULT NULL,
  p_latencia_ms integer DEFAULT NULL,
  p_topico_origem text DEFAULT NULL,
  p_payload_bruto jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE sql
AS $$
  SELECT register_gateway_status_event(
    p_data_hora,
    p_id_setor,
    p_status,
    p_codigo_gateway,
    p_latencia_ms,
    p_topico_origem,
    p_payload_bruto
  );
$$;

CREATE OR REPLACE FUNCTION registrar_acao_operador(
  p_data_hora timestamptz,
  p_nome_ator text,
  p_tipo_acao operator_action_type,
  p_tipo_entidade text,
  p_id_entidade text,
  p_detalhes jsonb DEFAULT '{}'::jsonb,
  p_observacoes text DEFAULT NULL
)
RETURNS bigint
LANGUAGE sql
AS $$
  SELECT record_operator_action(
    p_data_hora,
    p_nome_ator,
    p_tipo_acao,
    p_tipo_entidade,
    p_id_entidade,
    p_detalhes,
    p_observacoes
  );
$$;

CREATE OR REPLACE FUNCTION agendar_janela_manutencao(
  p_tipo_alvo text,
  p_id_alvo text,
  p_inicio timestamptz,
  p_fim timestamptz,
  p_motivo text,
  p_criado_por text,
  p_observacoes text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE sql
AS $$
  SELECT schedule_maintenance_window(
    p_tipo_alvo,
    p_id_alvo,
    p_inicio,
    p_fim,
    p_motivo,
    p_criado_por,
    p_observacoes,
    p_metadata
  );
$$;

CREATE OR REPLACE FUNCTION gerar_previsoes_setores(
  p_gerado_em timestamptz DEFAULT now(),
  p_horizonte_minutos integer DEFAULT 30,
  p_modelo text DEFAULT 'naive_baseline'
)
RETURNS integer
LANGUAGE sql
AS $$
  SELECT generate_sector_forecasts(
    p_gerado_em,
    p_horizonte_minutos,
    p_modelo
  );
$$;

CREATE OR REPLACE FUNCTION registrar_decisao_recomendacao(
  p_data_hora timestamptz,
  p_setor_origem sector_code,
  p_setor_recomendado sector_code,
  p_motivo text,
  p_taxa_ocupacao_origem numeric(5,4),
  p_codigo_politica text DEFAULT 'R-OP1',
  p_criado_por text DEFAULT 'system',
  p_candidatos jsonb DEFAULT '[]'::jsonb,
  p_dados jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE sql
AS $$
  SELECT record_recommendation_decision(
    p_data_hora,
    p_setor_origem,
    p_setor_recomendado,
    p_motivo,
    p_taxa_ocupacao_origem,
    p_codigo_politica,
    p_criado_por,
    p_candidatos,
    p_dados
  );
$$;

CREATE OR REPLACE FUNCTION apply_spot_event(
  p_event_id uuid,
  p_ts timestamptz,
  p_sector_id sector_code,
  p_spot_id text,
  p_state spot_state,
  p_raw_payload_json jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  inserted_event boolean,
  applied_to_current_state boolean,
  sector_id sector_code,
  occupied_count integer,
  free_count integer,
  occupancy_rate numeric(5,4)
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_inserted_event_id uuid;
  v_spot_updated integer := 0;
  v_previous_state spot_state;
  v_last_change_ts timestamptz;
BEGIN
  IF split_part(p_spot_id, '-', 1) <> p_sector_id::text THEN
    RAISE EXCEPTION 'Spot % does not belong to sector %', p_spot_id, p_sector_id;
  END IF;

  SELECT
    s.current_state,
    s.last_change_ts
  INTO
    v_previous_state,
    v_last_change_ts
  FROM spots s
  WHERE s.spot_id = p_spot_id
    AND s.sector_id = p_sector_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Spot % is not registered in sector %', p_spot_id, p_sector_id;
  END IF;

  INSERT INTO spot_events (
    event_id,
    ts,
    sector_id,
    spot_id,
    state,
    raw_payload_json
  )
  VALUES (
    p_event_id,
    p_ts,
    p_sector_id,
    p_spot_id,
    p_state,
    COALESCE(p_raw_payload_json, '{}'::jsonb)
  )
  ON CONFLICT (event_id) DO NOTHING
  RETURNING event_id INTO v_inserted_event_id;

  IF v_inserted_event_id IS NULL THEN
    RETURN QUERY
    SELECT
      FALSE,
      FALSE,
      occ.sector_id,
      occ.occupied_count,
      occ.free_count,
      occ.occupancy_rate
    FROM get_sector_occupancy(p_sector_id) occ;
    RETURN;
  END IF;

  UPDATE spots
  SET
    current_state = p_state,
    last_change_ts = p_ts,
    last_event_id = p_event_id
  WHERE spot_id = p_spot_id
    AND sector_id = p_sector_id
    AND (v_last_change_ts IS NULL OR p_ts >= v_last_change_ts);

  GET DIAGNOSTICS v_spot_updated = ROW_COUNT;

  IF v_spot_updated > 0 THEN
    PERFORM sync_spot_session_transition(
      p_sector_id,
      p_spot_id,
      v_previous_state,
      p_state,
      p_ts,
      p_event_id
    );

    UPDATE sensors
    SET
      last_seen_ts = p_ts,
      device_status = 'online'
    WHERE spot_id = p_spot_id
      AND (last_seen_ts IS NULL OR p_ts >= last_seen_ts);

    PERFORM upsert_sector_snapshot(date_trunc('minute', p_ts), p_sector_id);
  END IF;

  RETURN QUERY
  SELECT
    TRUE,
    v_spot_updated > 0,
    occ.sector_id,
    occ.occupied_count,
    occ.free_count,
    occ.occupancy_rate
  FROM get_sector_occupancy(p_sector_id) occ;
END;
$$;

CREATE OR REPLACE FUNCTION close_incident(
  p_incident_id uuid,
  p_ts_close timestamptz DEFAULT now()
)
RETURNS void
LANGUAGE sql
AS $$
  SELECT close_incident(
    p_incident_id,
    p_ts_close,
    NULL,
    '{}'::jsonb
  );
$$;

COMMENT ON FUNCTION register_gateway_status_event(timestamptz, sector_code, asset_status, text, integer, text, jsonb)
IS 'Registra heartbeat ou falha de gateway e atualiza o estado corrente do ativo.';

COMMENT ON FUNCTION generate_sector_forecasts(timestamptz, integer, text)
IS 'Gera previsoes operacionais simples por setor usando tendencia recente de snapshots.';

COMMENT ON FUNCTION record_recommendation_decision(timestamptz, sector_code, sector_code, text, numeric, text, text, jsonb, jsonb)
IS 'Registra recomendacao com politica aplicada e ranking completo de candidatos.';

COMMENT ON FUNCTION sync_spot_session_transition(sector_code, text, spot_state, spot_state, timestamptz, uuid)
IS 'Mantem sessoes de uso derivadas das transicoes de estado das vagas.';
