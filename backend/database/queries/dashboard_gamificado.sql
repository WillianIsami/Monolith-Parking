-- Mapa pronto para renderização do dashboard ou app
SELECT *
FROM vw_mapa_dashboard_vagas
ORDER BY id_setor, id_vaga;

-- Ranking de engajamento do app
SELECT *
FROM vw_ranking_engajamento;

-- Opções de navegação a partir do portão norte
SELECT *
FROM obter_opcoes_navegacao(
  'ENTRY_NORTH',
  5,
  NULL,
  false
);

-- Opções de navegação com acessibilidade priorizada
SELECT *
FROM obter_opcoes_navegacao(
  'ENTRY_CENTER',
  5,
  'accessible',
  true
);

-- Registrar uma solicitação de navegação no app
SELECT registrar_solicitacao_navegacao(
  'driver-demo-03',
  'Marina Lopes',
  'ENTRY_CENTER',
  'B-04',
  NULL,
  '{"channel":"mobile-app","mode":"quick-route"}'::jsonb
);

-- Registrar pontos por concluir uma rota
SELECT registrar_pontos_engajamento(
  'driver-demo-03',
  'Marina Lopes',
  'navigation_completed',
  30,
  NULL,
  '{"reason":"completed-recommended-route"}'::jsonb
);

-- Inspecionar rotas pré-calculadas para vagas livres
SELECT
  origin.node_code AS origem,
  rt.target_spot_id AS id_vaga,
  rt.target_sector_id AS id_setor,
  rt.distance_meters AS distancia_metros,
  rt.estimated_seconds AS tempo_estimado_segundos,
  rt.route_score AS pontuacao_rota,
  rt.path_node_codes AS caminho_nos
FROM route_templates rt
JOIN map_nodes origin
  ON origin.node_id = rt.origin_node_id
JOIN spots s
  ON s.spot_id = rt.target_spot_id
WHERE rt.target_type = 'spot'
  AND origin.node_code = 'ENTRY_NORTH'
  AND s.current_state = 'FREE'
ORDER BY rt.route_score DESC, rt.estimated_seconds ASC
LIMIT 10;
