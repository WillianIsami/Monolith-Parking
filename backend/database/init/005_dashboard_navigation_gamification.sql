DO $$
BEGIN
  CREATE TYPE map_node_type AS ENUM ('entry', 'intersection', 'sector_anchor', 'spot_anchor', 'poi');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE route_target_type AS ENUM ('sector', 'spot', 'poi');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE navigation_request_status AS ENUM ('resolved', 'arrived', 'abandoned', 'expired');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE app_user_role AS ENUM ('driver', 'operator', 'admin', 'guest');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE engagement_event_type AS ENUM (
    'navigation_completed',
    'low_congestion_choice',
    'eco_route_choice',
    'daily_check_in',
    'incident_reported',
    'route_shared'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE achievement_tier AS ENUM ('bronze', 'silver', 'gold', 'platinum');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS app_users (
  user_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  external_ref text NOT NULL UNIQUE,
  display_name text NOT NULL,
  role app_user_role NOT NULL DEFAULT 'driver',
  avatar_url text,
  accessibility_mode boolean NOT NULL DEFAULT false,
  preferred_spot_category spot_category,
  total_points integer NOT NULL DEFAULT 0 CHECK (total_points >= 0),
  level integer NOT NULL DEFAULT 1 CHECK (level >= 1),
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS map_nodes (
  node_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id uuid NOT NULL REFERENCES parking_facilities (facility_id) ON DELETE RESTRICT,
  node_code text NOT NULL UNIQUE,
  node_name text NOT NULL,
  node_type map_node_type NOT NULL,
  sector_id sector_code REFERENCES sectors (sector_id) ON DELETE RESTRICT,
  spot_id text REFERENCES spots (spot_id) ON DELETE RESTRICT,
  pos_x numeric(8,2) NOT NULL,
  pos_y numeric(8,2) NOT NULL,
  z_level integer NOT NULL DEFAULT 0,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (
    (node_type = 'spot_anchor' AND spot_id IS NOT NULL) OR
    (node_type <> 'spot_anchor')
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_map_nodes_spot_unique
  ON map_nodes (spot_id)
  WHERE spot_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_map_nodes_sector_anchor_unique
  ON map_nodes (sector_id)
  WHERE node_type = 'sector_anchor';

CREATE INDEX IF NOT EXISTS idx_map_nodes_type_sector
  ON map_nodes (node_type, sector_id);

CREATE TABLE IF NOT EXISTS map_edges (
  edge_id bigserial PRIMARY KEY,
  from_node_id uuid NOT NULL REFERENCES map_nodes (node_id) ON DELETE CASCADE,
  to_node_id uuid NOT NULL REFERENCES map_nodes (node_id) ON DELETE CASCADE,
  distance_meters numeric(8,2) NOT NULL CHECK (distance_meters > 0),
  estimated_seconds integer NOT NULL CHECK (estimated_seconds > 0),
  accessible boolean NOT NULL DEFAULT true,
  covered boolean NOT NULL DEFAULT false,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (from_node_id <> to_node_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_map_edges_unique
  ON map_edges (from_node_id, to_node_id);

CREATE INDEX IF NOT EXISTS idx_map_edges_from
  ON map_edges (from_node_id);

CREATE TABLE IF NOT EXISTS route_templates (
  route_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  origin_node_id uuid NOT NULL REFERENCES map_nodes (node_id) ON DELETE CASCADE,
  target_type route_target_type NOT NULL,
  target_sector_id sector_code REFERENCES sectors (sector_id) ON DELETE RESTRICT,
  target_spot_id text REFERENCES spots (spot_id) ON DELETE RESTRICT,
  path_node_codes jsonb NOT NULL DEFAULT '[]'::jsonb,
  distance_meters numeric(8,2) NOT NULL CHECK (distance_meters > 0),
  estimated_seconds integer NOT NULL CHECK (estimated_seconds > 0),
  difficulty_score numeric(5,2) NOT NULL DEFAULT 0 CHECK (difficulty_score >= 0),
  scenic_score numeric(5,2) NOT NULL DEFAULT 0 CHECK (scenic_score >= 0),
  accessibility_score numeric(5,2) NOT NULL DEFAULT 0 CHECK (accessibility_score >= 0),
  route_score numeric(8,4) NOT NULL DEFAULT 0,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (
    (target_type = 'sector' AND target_sector_id IS NOT NULL AND target_spot_id IS NULL) OR
    (target_type = 'spot' AND target_sector_id IS NOT NULL AND target_spot_id IS NOT NULL) OR
    (target_type = 'poi' AND target_sector_id IS NULL AND target_spot_id IS NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_route_templates_sector_unique
  ON route_templates (origin_node_id, target_sector_id)
  WHERE target_type = 'sector';

CREATE UNIQUE INDEX IF NOT EXISTS idx_route_templates_spot_unique
  ON route_templates (origin_node_id, target_spot_id)
  WHERE target_type = 'spot';

CREATE INDEX IF NOT EXISTS idx_route_templates_origin_target
  ON route_templates (origin_node_id, target_type, target_sector_id);

CREATE TABLE IF NOT EXISTS navigation_requests (
  navigation_request_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ts_requested timestamptz NOT NULL DEFAULT now(),
  user_id uuid REFERENCES app_users (user_id) ON DELETE SET NULL,
  origin_node_id uuid NOT NULL REFERENCES map_nodes (node_id) ON DELETE RESTRICT,
  requested_sector_id sector_code REFERENCES sectors (sector_id) ON DELETE SET NULL,
  recommended_sector_id sector_code REFERENCES sectors (sector_id) ON DELETE SET NULL,
  recommended_spot_id text REFERENCES spots (spot_id) ON DELETE SET NULL,
  recommendation_log_id bigint REFERENCES recommendations_log (id) ON DELETE SET NULL,
  route_id uuid REFERENCES route_templates (route_id) ON DELETE SET NULL,
  request_status navigation_request_status NOT NULL DEFAULT 'resolved',
  eta_seconds integer CHECK (eta_seconds IS NULL OR eta_seconds >= 0),
  score numeric(8,4),
  request_context_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  response_payload_json jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_navigation_requests_ts
  ON navigation_requests (ts_requested DESC);

CREATE INDEX IF NOT EXISTS idx_navigation_requests_user
  ON navigation_requests (user_id, ts_requested DESC);

CREATE TABLE IF NOT EXISTS achievement_catalog (
  achievement_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  achievement_code text NOT NULL UNIQUE,
  achievement_name text NOT NULL,
  achievement_tier achievement_tier NOT NULL,
  description text NOT NULL,
  points_reward integer NOT NULL DEFAULT 0 CHECK (points_reward >= 0),
  criteria_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS user_achievements (
  user_achievement_id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES app_users (user_id) ON DELETE CASCADE,
  achievement_id uuid NOT NULL REFERENCES achievement_catalog (achievement_id) ON DELETE CASCADE,
  unlocked_at timestamptz NOT NULL DEFAULT now(),
  progress_numeric numeric(8,2),
  evidence_json jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_achievements_unique
  ON user_achievements (user_id, achievement_id);

CREATE TABLE IF NOT EXISTS engagement_events (
  engagement_event_id bigserial PRIMARY KEY,
  ts timestamptz NOT NULL DEFAULT now(),
  user_id uuid NOT NULL REFERENCES app_users (user_id) ON DELETE CASCADE,
  navigation_request_id uuid REFERENCES navigation_requests (navigation_request_id) ON DELETE SET NULL,
  event_type engagement_event_type NOT NULL,
  points_delta integer NOT NULL,
  badge_code text,
  event_data_json jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_engagement_events_user_ts
  ON engagement_events (user_id, ts DESC);

COMMENT ON TABLE app_users IS 'Perfis do aplicativo para motoristas, operadores e futuras mecanicas gamificadas.';
COMMENT ON TABLE map_nodes IS 'Nós do mapa interno usados por dashboard, wayfinding e trajetos estilo GPS.';
COMMENT ON TABLE map_edges IS 'Conexões navegáveis entre nós do mapa com distância e tempo estimado.';
COMMENT ON TABLE route_templates IS 'Rotas pré-calculadas para setores e vagas, prontas para consumo por app ou dashboard.';
COMMENT ON TABLE navigation_requests IS 'Solicitações de navegação emitidas pelo app ou pelo painel operacional.';
COMMENT ON TABLE achievement_catalog IS 'Catálogo de badges, conquistas e recompensas do app.';
COMMENT ON TABLE user_achievements IS 'Conquistas desbloqueadas por cada usuário.';
COMMENT ON TABLE engagement_events IS 'Eventos de pontuação e engajamento gerados pela experiência gamificada.';

CREATE OR REPLACE VIEW v_dashboard_map_spots AS
SELECT
  s.spot_id,
  s.sector_id,
  sec.sector_name,
  s.current_state,
  s.spot_category,
  s.is_priority,
  s.grid_row,
  s.grid_col,
  s.lane_code,
  mn.node_code AS map_node_code,
  mn.pos_x,
  mn.pos_y,
  mn.z_level,
  CASE
    WHEN s.current_state = 'FREE' THEN '#2e8b57'
    ELSE '#cf3d3d'
  END AS map_color,
  CASE
    WHEN s.spot_category = 'accessible'::spot_category THEN 'accessible'
    WHEN s.spot_category = 'ev'::spot_category THEN 'ev'
    WHEN s.spot_category = 'visitor'::spot_category THEN 'visitor'
    WHEN s.spot_category = 'staff'::spot_category THEN 'staff'
    ELSE 'standard'
  END AS ui_badge
FROM spots s
JOIN sectors sec
  ON sec.sector_id = s.sector_id
LEFT JOIN map_nodes mn
  ON mn.spot_id = s.spot_id
 AND mn.node_type = 'spot_anchor';

CREATE OR REPLACE VIEW v_gamification_leaderboard AS
SELECT
  u.user_id,
  u.external_ref,
  u.display_name,
  u.role,
  u.total_points,
  u.level,
  COUNT(ua.user_achievement_id)::integer AS achievement_count,
  MAX(nr.ts_requested) AS last_navigation_request_at
FROM app_users u
LEFT JOIN user_achievements ua
  ON ua.user_id = u.user_id
LEFT JOIN navigation_requests nr
  ON nr.user_id = u.user_id
GROUP BY
  u.user_id,
  u.external_ref,
  u.display_name,
  u.role,
  u.total_points,
  u.level;

CREATE OR REPLACE VIEW vw_mapa_dashboard_vagas AS
SELECT
  spot_id AS id_vaga,
  sector_id AS id_setor,
  sector_name AS nome_setor,
  current_state AS estado_atual,
  spot_category AS categoria_vaga,
  is_priority AS eh_prioritaria,
  grid_row AS linha_grade,
  grid_col AS coluna_grade,
  lane_code AS codigo_corredor,
  map_node_code AS codigo_no_mapa,
  pos_x AS posicao_x,
  pos_y AS posicao_y,
  z_level AS nivel_z,
  map_color AS cor_mapa,
  ui_badge AS selo_ui
FROM v_dashboard_map_spots;

CREATE OR REPLACE VIEW vw_ranking_engajamento AS
SELECT
  display_name AS nome_usuario,
  role AS papel_usuario,
  total_points AS pontos_totais,
  level AS nivel,
  achievement_count AS quantidade_conquistas,
  last_navigation_request_at AS ultima_navegacao_em
FROM v_gamification_leaderboard
ORDER BY total_points DESC, achievement_count DESC, display_name;

CREATE OR REPLACE FUNCTION grant_engagement_points(
  p_external_ref text,
  p_display_name text,
  p_event_type engagement_event_type,
  p_points_delta integer,
  p_navigation_request_id uuid DEFAULT NULL,
  p_event_data_json jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_user_id uuid;
  v_event_id bigint;
  v_new_total_points integer;
BEGIN
  INSERT INTO app_users (
    external_ref,
    display_name
  )
  VALUES (
    p_external_ref,
    COALESCE(NULLIF(p_display_name, ''), p_external_ref)
  )
  ON CONFLICT (external_ref) DO UPDATE
  SET
    display_name = COALESCE(NULLIF(EXCLUDED.display_name, ''), app_users.display_name)
  RETURNING user_id INTO v_user_id;

  INSERT INTO engagement_events (
    user_id,
    navigation_request_id,
    event_type,
    points_delta,
    event_data_json
  )
  VALUES (
    v_user_id,
    p_navigation_request_id,
    p_event_type,
    p_points_delta,
    COALESCE(p_event_data_json, '{}'::jsonb)
  )
  RETURNING engagement_event_id INTO v_event_id;

  UPDATE app_users
  SET
    total_points = GREATEST(total_points + p_points_delta, 0),
    level = GREATEST(((GREATEST(total_points + p_points_delta, 0)) / 100) + 1, 1)
  WHERE user_id = v_user_id
  RETURNING total_points INTO v_new_total_points;

  RETURN v_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION register_navigation_request(
  p_external_ref text,
  p_display_name text,
  p_origin_node_code text,
  p_recommended_spot_id text,
  p_recommendation_log_id bigint DEFAULT NULL,
  p_request_context_json jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_user_id uuid;
  v_origin_node_id uuid;
  v_recommended_sector_id sector_code;
  v_route_id uuid;
  v_eta_seconds integer;
  v_route_score numeric(8,4);
  v_navigation_request_id uuid;
BEGIN
  INSERT INTO app_users (
    external_ref,
    display_name
  )
  VALUES (
    p_external_ref,
    COALESCE(NULLIF(p_display_name, ''), p_external_ref)
  )
  ON CONFLICT (external_ref) DO UPDATE
  SET
    display_name = COALESCE(NULLIF(EXCLUDED.display_name, ''), app_users.display_name)
  RETURNING user_id INTO v_user_id;

  SELECT node_id
  INTO v_origin_node_id
  FROM map_nodes
  WHERE node_code = p_origin_node_code
  LIMIT 1;

  IF v_origin_node_id IS NULL THEN
    RAISE EXCEPTION 'Map node % not found', p_origin_node_code;
  END IF;

  SELECT
    s.sector_id,
    rt.route_id,
    rt.estimated_seconds,
    rt.route_score
  INTO
    v_recommended_sector_id,
    v_route_id,
    v_eta_seconds,
    v_route_score
  FROM spots s
  LEFT JOIN route_templates rt
    ON rt.target_spot_id = s.spot_id
   AND rt.origin_node_id = v_origin_node_id
   AND rt.target_type = 'spot'
  WHERE s.spot_id = p_recommended_spot_id
  LIMIT 1;

  INSERT INTO navigation_requests (
    user_id,
    origin_node_id,
    requested_sector_id,
    recommended_sector_id,
    recommended_spot_id,
    recommendation_log_id,
    route_id,
    request_status,
    eta_seconds,
    score,
    request_context_json,
    response_payload_json
  )
  VALUES (
    v_user_id,
    v_origin_node_id,
    v_recommended_sector_id,
    v_recommended_sector_id,
    p_recommended_spot_id,
    p_recommendation_log_id,
    v_route_id,
    'resolved',
    v_eta_seconds,
    v_route_score,
    COALESCE(p_request_context_json, '{}'::jsonb),
    jsonb_build_object(
      'originNodeCode', p_origin_node_code,
      'recommendedSpotId', p_recommended_spot_id,
      'routeId', v_route_id
    )
  )
  RETURNING navigation_request_id INTO v_navigation_request_id;

  RETURN v_navigation_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION get_navigation_options(
  p_origin_node_code text,
  p_limit integer DEFAULT 5,
  p_required_category spot_category DEFAULT NULL,
  p_accessibility_mode boolean DEFAULT false
)
RETURNS TABLE (
  origin_node_code text,
  spot_id text,
  sector_id sector_code,
  spot_category spot_category,
  current_state spot_state,
  distance_meters numeric(8,2),
  estimated_seconds integer,
  route_score numeric(8,4),
  navigation_score numeric(8,4),
  path_node_codes jsonb,
  pos_x numeric(8,2),
  pos_y numeric(8,2)
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    origin.node_code AS origin_node_code,
    s.spot_id,
    s.sector_id,
    s.spot_category,
    s.current_state,
    rt.distance_meters,
    rt.estimated_seconds,
    rt.route_score,
    (
      rt.route_score +
      (CASE WHEN s.is_priority THEN 0.0300 ELSE 0 END) +
      (CASE WHEN p_accessibility_mode AND s.spot_category = 'accessible'::spot_category THEN 0.1200 ELSE 0 END) +
      (CASE WHEN p_required_category IS NOT NULL AND s.spot_category = p_required_category THEN 0.1000 ELSE 0 END) +
      ((1 - COALESCE(curr.occupancy_rate, 0)) * 0.1500)
    )::numeric(8,4) AS navigation_score,
    rt.path_node_codes,
    mn.pos_x,
    mn.pos_y
  FROM map_nodes origin
  JOIN route_templates rt
    ON rt.origin_node_id = origin.node_id
   AND rt.target_type = 'spot'
  JOIN spots s
    ON s.spot_id = rt.target_spot_id
  LEFT JOIN v_sector_summary_current curr
    ON curr.sector_id = s.sector_id
  LEFT JOIN map_nodes mn
    ON mn.spot_id = s.spot_id
   AND mn.node_type = 'spot_anchor'
  WHERE origin.node_code = p_origin_node_code
    AND s.current_state = 'FREE'
    AND (p_required_category IS NULL OR s.spot_category = p_required_category)
    AND (
      p_accessibility_mode = false OR
      s.spot_category IN ('accessible'::spot_category, 'standard'::spot_category)
    )
  ORDER BY navigation_score DESC, rt.estimated_seconds ASC, s.spot_id
  LIMIT GREATEST(COALESCE(p_limit, 5), 1);
$$;

CREATE OR REPLACE FUNCTION registrar_pontos_engajamento(
  p_referencia_externa text,
  p_nome_exibicao text,
  p_tipo_evento engagement_event_type,
  p_delta_pontos integer,
  p_id_navegacao uuid DEFAULT NULL,
  p_dados_evento jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE sql
AS $$
  SELECT grant_engagement_points(
    p_referencia_externa,
    p_nome_exibicao,
    p_tipo_evento,
    p_delta_pontos,
    p_id_navegacao,
    p_dados_evento
  );
$$;

CREATE OR REPLACE FUNCTION registrar_solicitacao_navegacao(
  p_referencia_externa text,
  p_nome_exibicao text,
  p_codigo_no_origem text,
  p_id_vaga_recomendada text,
  p_id_log_recomendacao bigint DEFAULT NULL,
  p_contexto_solicitacao jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE sql
AS $$
  SELECT register_navigation_request(
    p_referencia_externa,
    p_nome_exibicao,
    p_codigo_no_origem,
    p_id_vaga_recomendada,
    p_id_log_recomendacao,
    p_contexto_solicitacao
  );
$$;

CREATE OR REPLACE FUNCTION obter_opcoes_navegacao(
  p_codigo_no_origem text,
  p_limite integer DEFAULT 5,
  p_categoria_obrigatoria spot_category DEFAULT NULL,
  p_modo_acessibilidade boolean DEFAULT false
)
RETURNS TABLE (
  codigo_no_origem text,
  id_vaga text,
  id_setor sector_code,
  categoria_vaga spot_category,
  estado_atual spot_state,
  distancia_metros numeric(8,2),
  tempo_estimado_segundos integer,
  pontuacao_rota numeric(8,4),
  pontuacao_navegacao numeric(8,4),
  caminho_nos jsonb,
  posicao_x numeric(8,2),
  posicao_y numeric(8,2)
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    origin_node_code AS codigo_no_origem,
    spot_id AS id_vaga,
    sector_id AS id_setor,
    spot_category AS categoria_vaga,
    current_state AS estado_atual,
    distance_meters AS distancia_metros,
    estimated_seconds AS tempo_estimado_segundos,
    route_score AS pontuacao_rota,
    navigation_score AS pontuacao_navegacao,
    path_node_codes AS caminho_nos,
    pos_x AS posicao_x,
    pos_y AS posicao_y
  FROM get_navigation_options(
    p_codigo_no_origem,
    p_limite,
    p_categoria_obrigatoria,
    p_modo_acessibilidade
  );
$$;
