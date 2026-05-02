-- Centro operacional consolidado
SELECT *
FROM vw_centro_operacional_setores;

-- Saude dos gateways e baterias medias
SELECT *
FROM vw_saude_gateways;

-- Metricas de sessoes de permanencia por setor
SELECT *
FROM vw_metricas_sessoes_vagas;

-- Gerar previsoes para os proximos 30 minutos
SELECT gerar_previsoes_setores(now(), 30, 'naive_baseline');

-- Consultar previsoes recentes
SELECT
  sector_id,
  forecast_for_ts,
  predicted_occupied_count,
  predicted_free_count,
  predicted_occupancy_rate,
  model_name,
  confidence_score
FROM sector_forecasts
ORDER BY forecast_for_ts DESC, sector_id;

-- Registrar heartbeat de gateway
SELECT registrar_status_gateway(
  now(),
  'A',
  'online',
  'GW-A',
  115,
  'campus/parking/sectors/A/gateway/status',
  '{"status":"online","latencyMs":115}'::jsonb
);

-- Abrir uma janela de manutencao planejada
SELECT agendar_janela_manutencao(
  'sensor',
  'SNS-A01',
  now() + interval '1 day',
  now() + interval '1 day 2 hours',
  'Troca preventiva de bateria',
  'torre-operacao',
  'Priorizar antes do pico noturno',
  '{"priority":"high"}'::jsonb
);

-- Registrar decisao de recomendacao com ranking explicavel
SELECT registrar_decisao_recomendacao(
  now(),
  'A',
  'B',
  'Setor A acima do threshold; Setor B oferece melhor equilibrio entre vagas livres e prioridade operacional.',
  0.9300,
  'R-OP1',
  'api-http',
  '[
    {"sectorId":"B","freeCount":12,"occupancyRate":0.60,"distanceScore":0.83,"rankingScore":0.91,"reason":"best_balance"},
    {"sectorId":"C","freeCount":8,"occupancyRate":0.72,"distanceScore":0.78,"rankingScore":0.79,"reason":"secondary_candidate"}
  ]'::jsonb,
  '{"requestSource":"GET /api/v1/recommendation","sourceSector":"A"}'::jsonb
);

-- Auditoria da recomendacao e seus candidatos
SELECT
  rl.id,
  rl.ts,
  rl.from_sector,
  rl.recommended_sector,
  rl.reason,
  rl.source_occupancy_rate,
  rc.candidate_sector,
  rc.free_count,
  rc.occupancy_rate,
  rc.ranking_score
FROM recommendations_log rl
LEFT JOIN recommendation_candidates rc
  ON rc.recommendation_log_id = rl.id
ORDER BY rl.id DESC, rc.ranking_score DESC NULLS LAST;
