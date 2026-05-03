-- O MVP da Sprint 2 nao implementa dashboard avancado.
-- Este arquivo fica como apoio para consultas operacionais simples no banco atual.

-- Centro operacional simples por setor.
SELECT
  sector_id,
  occupied_count,
  free_count,
  occupancy_rate,
  last_update_ts
FROM get_sector_occupancy(NULL)
ORDER BY sector_id;

-- Saude atual dos gateways recebida via MQTT.
SELECT
  sector_id,
  gateway_id,
  status,
  last_status_ts
FROM v_gateway_current_status
ORDER BY sector_id;

-- Incidentes abertos.
SELECT
  id,
  type,
  severity,
  sector_id,
  spot_id,
  ts_open,
  status
FROM get_incidents('open', NULL);

-- Recomendacoes ja registradas.
SELECT
  id,
  ts,
  from_sector,
  recommended_sector,
  reason
FROM recommendations_log
ORDER BY ts DESC
LIMIT 20;
