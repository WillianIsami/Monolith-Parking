-- Persistencia de evento MQTT com idempotencia por event_id.
SELECT *
FROM apply_spot_event(
  '00000000-0000-4000-8000-000000000001',
  '2026-04-29T10:15:30Z',
  'A',
  'A-07',
  'OCCUPIED',
  '{"eventId":"00000000-0000-4000-8000-000000000001","ts":"2026-04-29T10:15:30Z","sectorId":"A","spotId":"A-07","state":"OCCUPIED","source":"gateway"}'::jsonb
);

-- Repetir o mesmo event_id nao duplica spot_events.
SELECT *
FROM apply_spot_event(
  '00000000-0000-4000-8000-000000000001',
  '2026-04-29T10:15:30Z',
  'A',
  'A-07',
  'OCCUPIED',
  '{"eventId":"00000000-0000-4000-8000-000000000001","ts":"2026-04-29T10:15:30Z","sectorId":"A","spotId":"A-07","state":"OCCUPIED","source":"gateway"}'::jsonb
);

-- Status de gateway.
SELECT record_gateway_status(
  now(),
  'A',
  'gateway-A',
  'ONLINE',
  'gateway',
  '{"sectorId":"A","gatewayId":"gateway-A","status":"ONLINE","source":"gateway"}'::jsonb
);

-- Ocupacao atual para todos os setores.
SELECT *
FROM get_sector_occupancy(NULL);

-- Abrir incidente para demonstracao.
SELECT open_incident(
  now(),
  'FLAPPING',
  'high',
  'A',
  'A-07',
  '{"changesInOneMinute":5}'::jsonb
);

-- Fechar incidente, se necessario.
-- SELECT close_incident('<incident-id-aqui>'::uuid, now());
