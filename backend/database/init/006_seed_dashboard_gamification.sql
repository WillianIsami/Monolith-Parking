INSERT INTO app_users (
  external_ref,
  display_name,
  role,
  accessibility_mode,
  preferred_spot_category,
  total_points,
  level,
  metadata_json
)
VALUES
  (
    'driver-demo-01',
    'Lia Freitas',
    'driver',
    false,
    'ev',
    180,
    2,
    '{"favoriteEntry":"ENTRY_NORTH","persona":"commuter"}'::jsonb
  ),
  (
    'driver-demo-02',
    'Caio Nunes',
    'driver',
    true,
    'accessible',
    260,
    3,
    '{"favoriteEntry":"ENTRY_CENTER","persona":"accessible-first"}'::jsonb
  ),
  (
    'operator-demo-01',
    'Torre Operacional',
    'operator',
    false,
    NULL,
    90,
    1,
    '{"team":"ops"}'::jsonb
  )
ON CONFLICT (external_ref) DO UPDATE
SET
  display_name = EXCLUDED.display_name,
  role = EXCLUDED.role,
  accessibility_mode = EXCLUDED.accessibility_mode,
  preferred_spot_category = EXCLUDED.preferred_spot_category,
  total_points = EXCLUDED.total_points,
  level = EXCLUDED.level,
  metadata_json = EXCLUDED.metadata_json;

INSERT INTO achievement_catalog (
  achievement_code,
  achievement_name,
  achievement_tier,
  description,
  points_reward,
  criteria_json,
  active
)
VALUES
  (
    'FIRST_ROUTE',
    'Primeira Rota',
    'bronze',
    'Concluiu a primeira navegação até uma vaga sugerida.',
    20,
    '{"requiredEvents":["navigation_completed"],"targetCount":1}'::jsonb,
    true
  ),
  (
    'FLOW_KEEPER',
    'Guardião do Fluxo',
    'silver',
    'Aceitou recomendações que ajudaram a aliviar setores congestionados.',
    45,
    '{"requiredEvents":["low_congestion_choice"],"targetCount":5}'::jsonb,
    true
  ),
  (
    'ECO_NAVIGATOR',
    'Eco Navigator',
    'gold',
    'Escolheu rotas mais eficientes de caminhada e menor impacto operacional.',
    80,
    '{"requiredEvents":["eco_route_choice"],"targetCount":8}'::jsonb,
    true
  ),
  (
    'CAMPUS_SCOUT',
    'Campus Scout',
    'platinum',
    'Manteve alta frequência de uso e navegação eficiente durante eventos de campus.',
    120,
    '{"requiredEvents":["daily_check_in","navigation_completed"],"targetDays":10}'::jsonb,
    true
  )
ON CONFLICT (achievement_code) DO UPDATE
SET
  achievement_name = EXCLUDED.achievement_name,
  achievement_tier = EXCLUDED.achievement_tier,
  description = EXCLUDED.description,
  points_reward = EXCLUDED.points_reward,
  criteria_json = EXCLUDED.criteria_json,
  active = EXCLUDED.active;

INSERT INTO user_achievements (
  user_id,
  achievement_id,
  unlocked_at,
  progress_numeric,
  evidence_json
)
SELECT
  u.user_id,
  a.achievement_id,
  now() - interval '2 days',
  1,
  '{"source":"seed"}'::jsonb
FROM app_users u
JOIN achievement_catalog a
  ON a.achievement_code = 'FIRST_ROUTE'
WHERE u.external_ref = 'driver-demo-01'
  AND NOT EXISTS (
    SELECT 1
    FROM user_achievements ua
    WHERE ua.user_id = u.user_id
      AND ua.achievement_id = a.achievement_id
  );

INSERT INTO user_achievements (
  user_id,
  achievement_id,
  unlocked_at,
  progress_numeric,
  evidence_json
)
SELECT
  u.user_id,
  a.achievement_id,
  now() - interval '1 day',
  5,
  '{"source":"seed"}'::jsonb
FROM app_users u
JOIN achievement_catalog a
  ON a.achievement_code = 'FLOW_KEEPER'
WHERE u.external_ref = 'driver-demo-02'
  AND NOT EXISTS (
    SELECT 1
    FROM user_achievements ua
    WHERE ua.user_id = u.user_id
      AND ua.achievement_id = a.achievement_id
  );

INSERT INTO map_nodes (
  facility_id,
  node_code,
  node_name,
  node_type,
  sector_id,
  spot_id,
  pos_x,
  pos_y,
  z_level,
  metadata_json
)
SELECT
  pf.facility_id,
  data.node_code,
  data.node_name,
  data.node_type::map_node_type,
  data.sector_id::sector_code,
  NULL,
  data.pos_x,
  data.pos_y,
  0,
  data.metadata_json::jsonb
FROM parking_facilities pf
CROSS JOIN (
  VALUES
    ('ENTRY_NORTH', 'Portão Norte', 'entry', NULL, 10.00, 18.00, '{"kind":"main-entry","uiIcon":"entry"}'),
    ('ENTRY_CENTER', 'Acesso Central', 'entry', NULL, 180.00, 18.00, '{"kind":"central-entry","uiIcon":"entry"}'),
    ('ENTRY_SOUTH', 'Portão Sul', 'entry', NULL, 350.00, 18.00, '{"kind":"secondary-entry","uiIcon":"entry"}'),
    ('SECTOR_A_ANCHOR', 'Âncora Setor A', 'sector_anchor', 'A', 55.00, 65.00, '{"kind":"sector-anchor"}'),
    ('SECTOR_B_ANCHOR', 'Âncora Setor B', 'sector_anchor', 'B', 180.00, 65.00, '{"kind":"sector-anchor"}'),
    ('SECTOR_C_ANCHOR', 'Âncora Setor C', 'sector_anchor', 'C', 305.00, 65.00, '{"kind":"sector-anchor"}')
) AS data (
  node_code,
  node_name,
  node_type,
  sector_id,
  pos_x,
  pos_y,
  metadata_json
)
WHERE pf.facility_code = 'PARKING_MAIN'
ON CONFLICT (node_code) DO UPDATE
SET
  node_name = EXCLUDED.node_name,
  node_type = EXCLUDED.node_type,
  sector_id = EXCLUDED.sector_id,
  pos_x = EXCLUDED.pos_x,
  pos_y = EXCLUDED.pos_y,
  z_level = EXCLUDED.z_level,
  metadata_json = EXCLUDED.metadata_json;

INSERT INTO map_nodes (
  facility_id,
  node_code,
  node_name,
  node_type,
  sector_id,
  spot_id,
  pos_x,
  pos_y,
  z_level,
  metadata_json
)
SELECT
  sec.facility_id,
  'SPOT_' || replace(s.spot_id, '-', '_'),
  'Âncora ' || s.spot_id,
  'spot_anchor',
  s.sector_id,
  s.spot_id,
  CASE s.sector_id
    WHEN 'A' THEN 35 + (s.grid_col * 4.50)
    WHEN 'B' THEN 160 + (s.grid_col * 4.50)
    ELSE 285 + (s.grid_col * 4.50)
  END,
  85 + (s.grid_row * 22.00) + ((s.grid_col - 1) * 0.20),
  0,
  jsonb_build_object(
    'gridRow', s.grid_row,
    'gridCol', s.grid_col,
    'laneCode', s.lane_code,
    'sectorId', s.sector_id
  )
FROM spots s
JOIN sectors sec
  ON sec.sector_id = s.sector_id
ON CONFLICT (node_code) DO UPDATE
SET
  facility_id = EXCLUDED.facility_id,
  node_name = EXCLUDED.node_name,
  node_type = EXCLUDED.node_type,
  sector_id = EXCLUDED.sector_id,
  spot_id = EXCLUDED.spot_id,
  pos_x = EXCLUDED.pos_x,
  pos_y = EXCLUDED.pos_y,
  z_level = EXCLUDED.z_level,
  metadata_json = EXCLUDED.metadata_json;

INSERT INTO map_edges (
  from_node_id,
  to_node_id,
  distance_meters,
  estimated_seconds,
  accessible,
  covered,
  metadata_json
)
SELECT
  origin.node_id,
  target.node_id,
  route_data.distance_meters,
  route_data.estimated_seconds,
  true,
  route_data.covered,
  route_data.metadata_json
FROM (
  VALUES
    ('ENTRY_NORTH', 'SECTOR_A_ANCHOR', 60.00, 45, true, '{"kind":"entry-to-sector"}'::jsonb),
    ('ENTRY_NORTH', 'SECTOR_B_ANCHOR', 110.00, 80, true, '{"kind":"entry-to-sector"}'::jsonb),
    ('ENTRY_NORTH', 'SECTOR_C_ANCHOR', 165.00, 120, false, '{"kind":"entry-to-sector"}'::jsonb),
    ('ENTRY_CENTER', 'SECTOR_A_ANCHOR', 95.00, 70, true, '{"kind":"entry-to-sector"}'::jsonb),
    ('ENTRY_CENTER', 'SECTOR_B_ANCHOR', 55.00, 42, true, '{"kind":"entry-to-sector"}'::jsonb),
    ('ENTRY_CENTER', 'SECTOR_C_ANCHOR', 92.00, 68, true, '{"kind":"entry-to-sector"}'::jsonb),
    ('ENTRY_SOUTH', 'SECTOR_A_ANCHOR', 170.00, 124, false, '{"kind":"entry-to-sector"}'::jsonb),
    ('ENTRY_SOUTH', 'SECTOR_B_ANCHOR', 108.00, 78, true, '{"kind":"entry-to-sector"}'::jsonb),
    ('ENTRY_SOUTH', 'SECTOR_C_ANCHOR', 62.00, 46, true, '{"kind":"entry-to-sector"}'::jsonb)
) AS route_data (
  from_code,
  to_code,
  distance_meters,
  estimated_seconds,
  covered,
  metadata_json
)
JOIN map_nodes origin
  ON origin.node_code = route_data.from_code
JOIN map_nodes target
  ON target.node_code = route_data.to_code
WHERE NOT EXISTS (
  SELECT 1
  FROM map_edges me
  WHERE me.from_node_id = origin.node_id
    AND me.to_node_id = target.node_id
);

INSERT INTO map_edges (
  from_node_id,
  to_node_id,
  distance_meters,
  estimated_seconds,
  accessible,
  covered,
  metadata_json
)
SELECT
  sector_anchor.node_id,
  spot_anchor.node_id,
  (
    8.00 +
    (s.grid_row * 11.50) +
    (s.grid_col * 3.20)
  )::numeric(8,2),
  GREATEST(
    ROUND(
      (
        8.00 +
        (s.grid_row * 11.50) +
        (s.grid_col * 3.20)
      ) / 1.25
    )::integer,
    12
  ),
  CASE
    WHEN s.spot_category = 'accessible'::spot_category THEN true
    WHEN s.lane_code = 'CENTER' THEN true
    ELSE false
  END,
  s.spot_category = 'ev'::spot_category,
  jsonb_build_object(
    'kind', 'sector-to-spot',
    'spotCategory', s.spot_category,
    'laneCode', s.lane_code
  )
FROM spots s
JOIN map_nodes sector_anchor
  ON sector_anchor.sector_id = s.sector_id
 AND sector_anchor.node_type = 'sector_anchor'
JOIN map_nodes spot_anchor
  ON spot_anchor.spot_id = s.spot_id
 AND spot_anchor.node_type = 'spot_anchor'
WHERE NOT EXISTS (
  SELECT 1
  FROM map_edges me
  WHERE me.from_node_id = sector_anchor.node_id
    AND me.to_node_id = spot_anchor.node_id
);

INSERT INTO route_templates (
  origin_node_id,
  target_type,
  target_sector_id,
  target_spot_id,
  path_node_codes,
  distance_meters,
  estimated_seconds,
  difficulty_score,
  scenic_score,
  accessibility_score,
  route_score,
  metadata_json
)
SELECT
  origin.node_id,
  'sector',
  sec.sector_id,
  NULL,
  jsonb_build_array(origin.node_code, anchor.node_code),
  edge.distance_meters,
  edge.estimated_seconds,
  CASE
    WHEN edge.distance_meters <= 70 THEN 1.20
    WHEN edge.distance_meters <= 110 THEN 2.00
    ELSE 3.10
  END,
  CASE
    WHEN sec.sector_id = 'B' THEN 0.85
    ELSE 0.65
  END,
  CASE
    WHEN edge.accessible THEN 0.95
    ELSE 0.55
  END,
  (
    (1 / edge.distance_meters) * 100 +
    sec.recommendation_priority * 0.25 +
    CASE WHEN edge.accessible THEN 0.15 ELSE 0 END
  )::numeric(8,4),
  jsonb_build_object(
    'kind', 'entry-to-sector',
    'covered', edge.covered
  )
FROM map_nodes origin
JOIN map_nodes anchor
  ON anchor.node_type = 'sector_anchor'
JOIN sectors sec
  ON sec.sector_id = anchor.sector_id
JOIN map_edges edge
  ON edge.from_node_id = origin.node_id
 AND edge.to_node_id = anchor.node_id
WHERE origin.node_type = 'entry'
  AND NOT EXISTS (
    SELECT 1
    FROM route_templates rt
    WHERE rt.origin_node_id = origin.node_id
      AND rt.target_type = 'sector'
      AND rt.target_sector_id = sec.sector_id
  );

INSERT INTO route_templates (
  origin_node_id,
  target_type,
  target_sector_id,
  target_spot_id,
  path_node_codes,
  distance_meters,
  estimated_seconds,
  difficulty_score,
  scenic_score,
  accessibility_score,
  route_score,
  metadata_json
)
SELECT
  origin.node_id,
  'spot',
  s.sector_id,
  s.spot_id,
  jsonb_build_array(origin.node_code, sector_anchor.node_code, spot_anchor.node_code),
  (entry_edge.distance_meters + spot_edge.distance_meters)::numeric(8,2),
  entry_edge.estimated_seconds + spot_edge.estimated_seconds,
  CASE
    WHEN s.grid_row = 1 THEN 1.10
    WHEN s.grid_row = 2 THEN 1.80
    ELSE 2.60
  END,
  CASE
    WHEN s.sector_id = 'B' THEN 0.90
    ELSE 0.70
  END,
  CASE
    WHEN s.spot_category = 'accessible'::spot_category THEN 1.00
    WHEN s.lane_code = 'CENTER' THEN 0.85
    ELSE 0.60
  END,
  (
    (1000 / (entry_edge.distance_meters + spot_edge.distance_meters)) * 0.12 +
    CASE WHEN s.is_priority THEN 0.18 ELSE 0 END +
    CASE WHEN s.spot_category = 'accessible'::spot_category THEN 0.22 ELSE 0 END +
    CASE WHEN s.spot_category = 'ev'::spot_category THEN 0.12 ELSE 0 END +
    CASE WHEN s.grid_row = 1 THEN 0.14 WHEN s.grid_row = 2 THEN 0.08 ELSE 0.02 END
  )::numeric(8,4),
  jsonb_build_object(
    'kind', 'entry-to-spot',
    'spotCategory', s.spot_category,
    'laneCode', s.lane_code,
    'priority', s.is_priority
  )
FROM spots s
JOIN map_nodes sector_anchor
  ON sector_anchor.sector_id = s.sector_id
 AND sector_anchor.node_type = 'sector_anchor'
JOIN map_nodes spot_anchor
  ON spot_anchor.spot_id = s.spot_id
 AND spot_anchor.node_type = 'spot_anchor'
JOIN map_nodes origin
  ON origin.node_type = 'entry'
JOIN map_edges entry_edge
  ON entry_edge.from_node_id = origin.node_id
 AND entry_edge.to_node_id = sector_anchor.node_id
JOIN map_edges spot_edge
  ON spot_edge.from_node_id = sector_anchor.node_id
 AND spot_edge.to_node_id = spot_anchor.node_id
WHERE NOT EXISTS (
  SELECT 1
  FROM route_templates rt
  WHERE rt.origin_node_id = origin.node_id
    AND rt.target_type = 'spot'
    AND rt.target_spot_id = s.spot_id
);

INSERT INTO navigation_requests (
  ts_requested,
  user_id,
  origin_node_id,
  requested_sector_id,
  recommended_sector_id,
  recommended_spot_id,
  route_id,
  request_status,
  eta_seconds,
  score,
  request_context_json,
  response_payload_json
)
SELECT
  now() - interval '4 hours',
  u.user_id,
  origin.node_id,
  'A',
  s.sector_id,
  s.spot_id,
  rt.route_id,
  'arrived',
  rt.estimated_seconds,
  rt.route_score,
  '{"source":"seed-demo","channel":"mobile-app"}'::jsonb,
  jsonb_build_object(
    'pathNodeCodes', rt.path_node_codes,
    'spotId', s.spot_id
  )
FROM app_users u
JOIN map_nodes origin
  ON origin.node_code = 'ENTRY_NORTH'
JOIN route_templates rt
  ON rt.origin_node_id = origin.node_id
 AND rt.target_type = 'spot'
JOIN spots s
  ON s.spot_id = rt.target_spot_id
WHERE u.external_ref = 'driver-demo-01'
  AND s.spot_id = 'A-03'
  AND NOT EXISTS (
    SELECT 1
    FROM navigation_requests nr
    WHERE nr.user_id = u.user_id
      AND nr.recommended_spot_id = s.spot_id
  );

SELECT grant_engagement_points(
  'driver-demo-01',
  'Lia Freitas',
  'navigation_completed',
  25,
  (
    SELECT nr.navigation_request_id
    FROM navigation_requests nr
    JOIN app_users u
      ON u.user_id = nr.user_id
    WHERE u.external_ref = 'driver-demo-01'
    ORDER BY nr.ts_requested DESC
    LIMIT 1
  ),
  '{"source":"seed-demo","routeOutcome":"arrived"}'::jsonb
)
WHERE EXISTS (
  SELECT 1
  FROM navigation_requests nr
  JOIN app_users u
    ON u.user_id = nr.user_id
  WHERE u.external_ref = 'driver-demo-01'
)
AND NOT EXISTS (
  SELECT 1
  FROM engagement_events ee
  JOIN app_users u
    ON u.user_id = ee.user_id
  WHERE u.external_ref = 'driver-demo-01'
    AND ee.event_type = 'navigation_completed'
);
