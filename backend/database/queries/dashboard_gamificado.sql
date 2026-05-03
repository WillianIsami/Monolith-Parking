-- Gamificacao e app de usuario nao fazem parte do MVP obrigatorio da Sprint 2.
-- Consultas abaixo mostram dados que podem alimentar uma demonstracao simples.

-- Mapa atual.
SELECT
  spot_id,
  sector_id,
  current_state,
  last_change_ts
FROM v_current_map
ORDER BY sector_id, spot_id;

-- Vagas livres por setor.
SELECT 'A' AS sector_id, COUNT(*) AS free_count FROM get_free_spots('A', 30)
UNION ALL
SELECT 'B' AS sector_id, COUNT(*) AS free_count FROM get_free_spots('B', 30)
UNION ALL
SELECT 'C' AS sector_id, COUNT(*) AS free_count FROM get_free_spots('C', 30)
ORDER BY sector_id;

-- Historico recente de eventos.
SELECT
  ts,
  sector_id,
  spot_id,
  state
FROM spot_events
ORDER BY ts DESC
LIMIT 30;
