-- GET /api/v1/map
SELECT spot_id, sector_id, current_state, last_change_ts, last_event_id
FROM v_current_map;

-- GET /api/v1/sectors
SELECT sector_id, occupied_count, free_count, occupancy_rate, last_update_ts
FROM get_sector_occupancy(NULL);

-- GET /api/v1/sectors/:sectorId/spots
SELECT spot_id, sector_id, current_state, last_change_ts, last_event_id
FROM spots
WHERE sector_id = 'A'
ORDER BY spot_id;

-- GET /api/v1/sectors/:sectorId/free-spots?limit=10
SELECT *
FROM get_free_spots('A', 10);

-- GET /api/v1/reports/turnover?sectorId=A&from=...&to=...
SELECT *
FROM get_turnover_report(
  'A',
  '2026-04-29T00:00:00Z',
  '2026-04-30T00:00:00Z'
);

-- GET /api/v1/incidents?status=open
SELECT *
FROM get_incidents('open', NULL);

-- GET /api/v1/recommendation?fromSector=A
-- A API escolhe o melhor setor candidato e registra o resultado.
SELECT log_recommendation(
  now(),
  'A',
  'B',
  'Sector A at 93% occupancy; Sector B has 12 free spots',
  '{"origin":{"sectorId":"A","occupancyRate":0.93},"candidates":[{"sectorId":"B","freeCount":12},{"sectorId":"C","freeCount":5}]}'::jsonb
);

-- GET /api/v1/gateways
SELECT sector_id, gateway_id, status, source, last_status_ts
FROM v_gateway_current_status
ORDER BY sector_id;
