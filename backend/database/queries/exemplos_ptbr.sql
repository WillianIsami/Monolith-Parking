-- Mapa atual das vagas.
SELECT *
FROM v_current_map;

-- Resumo atual por setor.
SELECT *
FROM get_sector_occupancy(NULL);

-- Persistencia de um evento MQTT.
SELECT *
FROM apply_spot_event(
  '00000000-0000-4000-8000-000000000002',
  '2026-04-29T10:15:30Z',
  'A',
  'A-07',
  'OCCUPIED',
  '{"eventId":"00000000-0000-4000-8000-000000000002","ts":"2026-04-29T10:15:30Z","sectorId":"A","spotId":"A-07","state":"OCCUPIED","source":"gateway"}'::jsonb
);

-- Vagas livres de um setor.
SELECT *
FROM get_free_spots('A', 10);

-- Relatorio de rotatividade.
SELECT *
FROM get_turnover_report(
  'A',
  '2026-04-29T00:00:00Z',
  '2026-04-30T00:00:00Z'
);

-- Abrir incidente.
SELECT open_incident(
  now(),
  'FLAPPING',
  'high',
  'A',
  'A-07',
  '{"trocasEmUmMinuto":5}'::jsonb
);

-- Listar incidentes abertos.
SELECT *
FROM get_incidents('open', NULL);

-- Registrar recomendacao.
SELECT log_recommendation(
  now(),
  'A',
  'B',
  'Setor A com 93% de ocupacao; Setor B possui 12 vagas livres',
  '{"taxaOcupacao":0.93,"setoresCandidatos":[{"setor":"B","vagasLivres":12},{"setor":"C","vagasLivres":5}]}'::jsonb
);
