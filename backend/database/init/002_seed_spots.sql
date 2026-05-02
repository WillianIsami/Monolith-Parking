INSERT INTO sectors(sector_id, capacity, occupancy_alert_threshold)
VALUES
  ('A', 30, 0.9000),
  ('B', 30, 0.9000),
  ('C', 30, 0.9000)
ON CONFLICT (sector_id) DO NOTHING;

INSERT INTO spots(spot_id, sector_id, current_state, last_change_ts, last_event_id)
SELECT
  sector_id || '-' || LPAD(spot_number::text, 2, '0') AS spot_id,
  sector_id,
  'FREE' AS current_state,
  NULL::timestamptz AS last_change_ts,
  NULL::uuid AS last_event_id
FROM unnest(ARRAY['A', 'B', 'C']) AS sector_id
CROSS JOIN generate_series(1, 30) AS spot_number
ON CONFLICT (spot_id) DO NOTHING;

SELECT upsert_sector_snapshot(date_trunc('minute', now()), sector_id)
FROM sectors;
