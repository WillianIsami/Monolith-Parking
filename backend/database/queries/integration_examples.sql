-- MQTT ingestion persistence example
SELECT *
FROM apply_spot_event(
  '00000000-0000-0000-0000-000000000001',
  '2026-04-29T10:15:30Z',
  'A',
  'A-07',
  'OCCUPIED',
  '{"eventId":"00000000-0000-0000-0000-000000000001","ts":"2026-04-29T10:15:30Z","sectorId":"A","spotId":"A-07","state":"OCCUPIED","source":"gateway"}'::jsonb
);

-- Current occupancy for all sectors
SELECT *
FROM get_sector_occupancy(NULL::sector_code);

-- Current occupancy for one sector
SELECT *
FROM get_sector_occupancy('A');

-- Open incident example
SELECT open_incident(
  '2026-04-29T11:00:00Z',
  'FLAPPING',
  'high',
  'A',
  'A-07',
  '{"changesInOneMinute":5,"window":"2026-04-29T10:59:00Z/2026-04-29T11:00:00Z"}'::jsonb
);

-- Close incident example
SELECT close_incident(
  '00000000-0000-0000-0000-000000000099',
  '2026-04-29T12:00:00Z'
);
