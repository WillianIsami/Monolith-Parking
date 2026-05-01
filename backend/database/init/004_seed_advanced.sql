INSERT INTO campuses (
  campus_code,
  campus_name,
  timezone_name,
  metadata_json
)
VALUES (
  'CAMPUS_MAIN',
  'Campus Inteligente Monolith',
  'America/Sao_Paulo',
  '{"city":"Rio de Janeiro","country":"BR","domain":"smart-mobility"}'::jsonb
)
ON CONFLICT (campus_code) DO UPDATE
SET
  campus_name = EXCLUDED.campus_name,
  timezone_name = EXCLUDED.timezone_name,
  metadata_json = EXCLUDED.metadata_json;

INSERT INTO parking_facilities (
  campus_id,
  facility_code,
  facility_name,
  facility_type,
  total_capacity,
  operating_hours_json,
  metadata_json
)
SELECT
  c.campus_id,
  'PARKING_MAIN',
  'Estacionamento Inteligente Principal',
  'surface',
  90,
  '{"opensAt":"06:00","closesAt":"23:00","timezone":"America/Sao_Paulo"}'::jsonb,
  '{"entryPoints":["north-gate","south-gate"],"surveillance":"camera+sensor"}'::jsonb
FROM campuses c
WHERE c.campus_code = 'CAMPUS_MAIN'
ON CONFLICT (facility_code) DO UPDATE
SET
  facility_name = EXCLUDED.facility_name,
  facility_type = EXCLUDED.facility_type,
  total_capacity = EXCLUDED.total_capacity,
  operating_hours_json = EXCLUDED.operating_hours_json,
  metadata_json = EXCLUDED.metadata_json;

INSERT INTO sectors (
  sector_id,
  facility_id,
  sector_name,
  display_order,
  capacity,
  occupancy_alert_threshold,
  congestion_threshold,
  recommendation_priority,
  geojson,
  metadata_json
)
SELECT
  sector_data.sector_id::sector_code,
  pf.facility_id,
  sector_data.sector_name,
  sector_data.display_order,
  30,
  sector_data.occupancy_alert_threshold,
  sector_data.congestion_threshold,
  sector_data.recommendation_priority,
  sector_data.geojson::jsonb,
  sector_data.metadata_json::jsonb
FROM parking_facilities pf
CROSS JOIN (
  VALUES
    ('A', 'Setor A - Entrada Norte', 1, 0.9200, 0.8000, 1.0000, '{"anchor":"north"}', '{"profile":"high-turnover"}'),
    ('B', 'Setor B - Nucleo Central', 2, 0.9000, 0.7600, 1.0500, '{"anchor":"center"}', '{"profile":"balanced"}'),
    ('C', 'Setor C - Area Academica', 3, 0.8800, 0.7200, 1.1500, '{"anchor":"south"}', '{"profile":"overflow-and-events"}')
) AS sector_data (
  sector_id,
  sector_name,
  display_order,
  occupancy_alert_threshold,
  congestion_threshold,
  recommendation_priority,
  geojson,
  metadata_json
)
WHERE pf.facility_code = 'PARKING_MAIN'
ON CONFLICT (sector_id) DO UPDATE
SET
  facility_id = EXCLUDED.facility_id,
  sector_name = EXCLUDED.sector_name,
  display_order = EXCLUDED.display_order,
  capacity = EXCLUDED.capacity,
  occupancy_alert_threshold = EXCLUDED.occupancy_alert_threshold,
  congestion_threshold = EXCLUDED.congestion_threshold,
  recommendation_priority = EXCLUDED.recommendation_priority,
  geojson = EXCLUDED.geojson,
  metadata_json = EXCLUDED.metadata_json;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_spots_sector'
  ) THEN
    ALTER TABLE spots
      ADD CONSTRAINT fk_spots_sector
      FOREIGN KEY (sector_id)
      REFERENCES sectors (sector_id)
      ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_spot_events_sector'
  ) THEN
    ALTER TABLE spot_events
      ADD CONSTRAINT fk_spot_events_sector
      FOREIGN KEY (sector_id)
      REFERENCES sectors (sector_id)
      ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_sector_snapshots_sector'
  ) THEN
    ALTER TABLE sector_snapshots
      ADD CONSTRAINT fk_sector_snapshots_sector
      FOREIGN KEY (sector_id)
      REFERENCES sectors (sector_id)
      ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_incidents_sector'
  ) THEN
    ALTER TABLE incidents
      ADD CONSTRAINT fk_incidents_sector
      FOREIGN KEY (sector_id)
      REFERENCES sectors (sector_id)
      ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_recommendations_log_from_sector'
  ) THEN
    ALTER TABLE recommendations_log
      ADD CONSTRAINT fk_recommendations_log_from_sector
      FOREIGN KEY (from_sector)
      REFERENCES sectors (sector_id)
      ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_recommendations_log_recommended_sector'
  ) THEN
    ALTER TABLE recommendations_log
      ADD CONSTRAINT fk_recommendations_log_recommended_sector
      FOREIGN KEY (recommended_sector)
      REFERENCES sectors (sector_id)
      ON DELETE RESTRICT;
  END IF;
END $$;

UPDATE spots
SET
  grid_row = ((split_part(spot_id, '-', 2)::integer - 1) / 10) + 1,
  grid_col = ((split_part(spot_id, '-', 2)::integer - 1) % 10) + 1,
  lane_code = CASE
    WHEN split_part(spot_id, '-', 2)::integer BETWEEN 1 AND 10 THEN 'NORTH'
    WHEN split_part(spot_id, '-', 2)::integer BETWEEN 11 AND 20 THEN 'CENTER'
    ELSE 'SOUTH'
  END,
  is_priority = split_part(spot_id, '-', 2)::integer IN (1, 2, 3, 4),
  spot_category = CASE
    WHEN split_part(spot_id, '-', 2)::integer IN (1, 2) THEN 'accessible'::spot_category
    WHEN split_part(spot_id, '-', 2)::integer IN (3, 4) THEN 'ev'::spot_category
    WHEN split_part(spot_id, '-', 2)::integer IN (5, 6) THEN 'motorcycle'::spot_category
    WHEN split_part(spot_id, '-', 2)::integer IN (7, 8) THEN 'visitor'::spot_category
    WHEN split_part(spot_id, '-', 2)::integer IN (9, 10) THEN 'staff'::spot_category
    ELSE 'standard'::spot_category
  END,
  metadata_json = jsonb_build_object(
    'displayLabel', spot_id,
    'lane', CASE
      WHEN split_part(spot_id, '-', 2)::integer BETWEEN 1 AND 10 THEN 'North Lane'
      WHEN split_part(spot_id, '-', 2)::integer BETWEEN 11 AND 20 THEN 'Central Lane'
      ELSE 'South Lane'
    END,
    'supportsFastEvCharge', split_part(spot_id, '-', 2)::integer IN (3, 4)
  );

INSERT INTO gateways (
  sector_id,
  gateway_code,
  gateway_name,
  firmware_version,
  connectivity_status,
  installed_at,
  last_heartbeat_ts,
  metadata_json
)
VALUES
  ('A', 'GW-A', 'Gateway A - Entrada Norte', '1.4.2', 'online', now() - interval '20 days', now(), '{"vendor":"Monolith IoT","protocol":"MQTT"}'::jsonb),
  ('B', 'GW-B', 'Gateway B - Nucleo Central', '1.4.2', 'online', now() - interval '20 days', now(), '{"vendor":"Monolith IoT","protocol":"MQTT"}'::jsonb),
  ('C', 'GW-C', 'Gateway C - Area Academica', '1.4.2', 'online', now() - interval '20 days', now(), '{"vendor":"Monolith IoT","protocol":"MQTT"}'::jsonb)
ON CONFLICT (gateway_code) DO UPDATE
SET
  gateway_name = EXCLUDED.gateway_name,
  firmware_version = EXCLUDED.firmware_version,
  connectivity_status = EXCLUDED.connectivity_status,
  installed_at = EXCLUDED.installed_at,
  last_heartbeat_ts = EXCLUDED.last_heartbeat_ts,
  metadata_json = EXCLUDED.metadata_json;

INSERT INTO sensors (
  spot_id,
  gateway_id,
  sensor_code,
  device_status,
  battery_level,
  installed_at,
  last_seen_ts,
  calibration_json,
  metadata_json
)
SELECT
  s.spot_id,
  g.gateway_id,
  'SNS-' || replace(s.spot_id, '-', '') AS sensor_code,
  'online',
  CASE
    WHEN s.spot_category = 'ev'::spot_category THEN 94.50
    WHEN s.spot_category = 'accessible'::spot_category THEN 92.00
    ELSE 88.00
  END,
  now() - interval '15 days',
  now(),
  jsonb_build_object(
    'sensitivity', CASE
      WHEN s.spot_category = 'motorcycle'::spot_category THEN 'high'
      ELSE 'normal'
    END,
    'calibratedAt', to_char(now() - interval '15 days', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  ),
  jsonb_build_object(
    'spotCategory', s.spot_category,
    'priority', s.is_priority
  )
FROM spots s
JOIN gateways g
  ON g.sector_id = s.sector_id
ON CONFLICT (sensor_code) DO UPDATE
SET
  gateway_id = EXCLUDED.gateway_id,
  device_status = EXCLUDED.device_status,
  battery_level = EXCLUDED.battery_level,
  installed_at = EXCLUDED.installed_at,
  last_seen_ts = EXCLUDED.last_seen_ts,
  calibration_json = EXCLUDED.calibration_json,
  metadata_json = EXCLUDED.metadata_json;

INSERT INTO recommendation_policies (
  policy_code,
  policy_name,
  description,
  min_source_occupancy_rate,
  target_selection_strategy,
  allow_cross_facility,
  priority_weight,
  policy_status,
  config_json
)
VALUES
  (
    'R-OP1',
    'Balanceamento de lotacao',
    'Quando o setor de origem ultrapassa o threshold, recomenda o melhor setor por vagas livres e prioridade.',
    0.9000,
    'highest_free_count_then_priority',
    false,
    1.0000,
    'active',
    '{"weights":{"freeCount":0.6,"priority":0.2,"distance":0.2}}'::jsonb
  ),
  (
    'R-EV-FIRST',
    'Prioridade para vagas com infraestrutura EV',
    'Quando o motorista precisa carregar, prioriza setores com vagas EV livres.',
    0.7500,
    'ev_capable_first',
    false,
    1.1500,
    'active',
    '{"requiredCategory":"ev","weights":{"categoryFit":0.5,"freeCount":0.3,"distance":0.2}}'::jsonb
  ),
  (
    'R-ACCESS',
    'Prioridade para acessibilidade',
    'Garante recomendacao de setor com vagas acessiveis e menor atrito de deslocamento.',
    0.7000,
    'accessible_first',
    false,
    1.2500,
    'active',
    '{"requiredCategory":"accessible","weights":{"categoryFit":0.55,"distance":0.25,"freeCount":0.20}}'::jsonb
  )
ON CONFLICT (policy_code) DO UPDATE
SET
  policy_name = EXCLUDED.policy_name,
  description = EXCLUDED.description,
  min_source_occupancy_rate = EXCLUDED.min_source_occupancy_rate,
  target_selection_strategy = EXCLUDED.target_selection_strategy,
  allow_cross_facility = EXCLUDED.allow_cross_facility,
  priority_weight = EXCLUDED.priority_weight,
  policy_status = EXCLUDED.policy_status,
  config_json = EXCLUDED.config_json;

INSERT INTO campus_events (
  campus_id,
  event_type,
  event_name,
  starts_at,
  ends_at,
  expected_attendance,
  impact_multiplier,
  affected_sectors_json,
  metadata_json
)
SELECT
  c.campus_id,
  'academic',
  'Pico de aulas do periodo noturno',
  now() + interval '1 day',
  now() + interval '1 day 3 hours',
  480,
  1.180,
  '["B","C"]'::jsonb,
  '{"reason":"class-shift","note":"expected pressure on central and academic sectors"}'::jsonb
FROM campuses c
WHERE c.campus_code = 'CAMPUS_MAIN'
AND NOT EXISTS (
  SELECT 1
  FROM campus_events ce
  WHERE ce.event_name = 'Pico de aulas do periodo noturno'
);

INSERT INTO gateway_status_events (
  ts,
  sector_id,
  gateway_id,
  status,
  latency_ms,
  source_topic,
  raw_payload_json
)
SELECT
  now(),
  g.sector_id,
  g.gateway_id,
  'online',
  CASE g.gateway_code
    WHEN 'GW-A' THEN 120
    WHEN 'GW-B' THEN 108
    ELSE 125
  END,
  'campus/parking/sectors/' || g.sector_id || '/gateway/status',
  jsonb_build_object('status', 'online', 'gatewayId', g.gateway_code)
FROM gateways g
WHERE NOT EXISTS (
  SELECT 1
  FROM gateway_status_events gse
  WHERE gse.gateway_id = g.gateway_id
);

SELECT generate_sector_forecasts(
  date_trunc('hour', now()),
  30,
  'naive_baseline'
)
WHERE NOT EXISTS (
  SELECT 1
  FROM sector_forecasts sf
  WHERE sf.model_name = 'naive_baseline'
);
