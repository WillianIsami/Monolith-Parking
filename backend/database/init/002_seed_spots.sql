INSERT INTO spots (
  spot_id,
  sector_id,
  current_state,
  last_change_ts,
  last_event_id
)
SELECT
  sector_name || '-' || LPAD(spot_number::text, 2, '0') AS spot_id,
  sector_name::sector_code AS sector_id,
  'FREE'::spot_state AS current_state,
  NULL::timestamptz AS last_change_ts,
  NULL::uuid AS last_event_id
FROM unnest(ARRAY['A', 'B', 'C']) AS sector_name
CROSS JOIN generate_series(1, 30) AS spot_number
ON CONFLICT (spot_id) DO NOTHING;

SELECT upsert_sector_snapshot(date_trunc('minute', now()), sector_id)
FROM get_sector_occupancy(NULL::sector_code);
