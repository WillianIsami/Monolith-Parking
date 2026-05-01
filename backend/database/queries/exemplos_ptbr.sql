-- Mapa atual das vagas
SELECT *
FROM vw_mapa_atual_vagas;

-- Resumo atual por setor
SELECT *
FROM vw_resumo_atual_setores;

-- Persistencia de um evento MQTT
SELECT *
FROM aplicar_evento_vaga(
  '00000000-0000-0000-0000-000000000001',
  '2026-04-29T10:15:30Z',
  'A',
  'A-07',
  'OCCUPIED',
  '{"eventId":"00000000-0000-0000-0000-000000000001","ts":"2026-04-29T10:15:30Z","sectorId":"A","spotId":"A-07","state":"OCCUPIED","source":"gateway"}'::jsonb
);

-- Ocupacao atual de todos os setores
SELECT *
FROM obter_ocupacao_setor(NULL::sector_code);

-- Vagas livres de um setor
SELECT *
FROM obter_vagas_livres('A', 10);

-- Relatorio de rotatividade
SELECT *
FROM obter_relatorio_rotatividade(
  'A',
  '2026-04-29T00:00:00Z',
  '2026-04-30T00:00:00Z'
);

-- Abrir incidente
SELECT abrir_incidente(
  '2026-04-29T11:00:00Z',
  'FLAPPING',
  'high',
  'A',
  'A-07',
  '{"trocasEmUmMinuto":5,"janela":"2026-04-29T10:59:00Z/2026-04-29T11:00:00Z"}'::jsonb
);

-- Listar incidentes abertos
SELECT *
FROM obter_incidentes('open', NULL::sector_code);

-- Registrar recomendacao
SELECT registrar_recomendacao(
  '2026-04-29T10:20:00Z',
  'A',
  'B',
  'Setor A com 93% de ocupacao; Setor B possui 12 vagas livres',
  '{"taxaOcupacao":0.93,"setoresCandidatos":[{"setor":"B","vagasLivres":12},{"setor":"C","vagasLivres":5}]}'::jsonb
);
