CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  CREATE TYPE sector_code AS ENUM ('A', 'B', 'C');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE spot_state AS ENUM ('FREE', 'OCCUPIED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE incident_type AS ENUM ('STUCK_OCCUPIED', 'STUCK_FREE', 'FLAPPING');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE incident_severity AS ENUM ('low', 'medium', 'high', 'critical');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE incident_status AS ENUM ('open', 'closed');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS spots (
  spot_id text PRIMARY KEY,
  sector_id sector_code NOT NULL,
  current_state spot_state NOT NULL DEFAULT 'FREE',
  last_change_ts timestamptz,
  last_event_id uuid,
  CHECK (spot_id ~ '^[ABC]-[0-9]{2}$'),
  CHECK (split_part(spot_id, '-', 1) = sector_id::text)
);

CREATE INDEX IF NOT EXISTS idx_spots_sector_state
  ON spots (sector_id, current_state);

CREATE TABLE IF NOT EXISTS spot_events (
  event_id uuid PRIMARY KEY,
  ts timestamptz NOT NULL,
  sector_id sector_code NOT NULL,
  spot_id text NOT NULL REFERENCES spots (spot_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  state spot_state NOT NULL,
  raw_payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (split_part(spot_id, '-', 1) = sector_id::text)
);

CREATE INDEX IF NOT EXISTS idx_spot_events_sector_ts
  ON spot_events (sector_id, ts DESC);

CREATE INDEX IF NOT EXISTS idx_spot_events_spot_ts
  ON spot_events (spot_id, ts DESC);

CREATE TABLE IF NOT EXISTS sector_snapshots (
  ts timestamptz NOT NULL,
  sector_id sector_code NOT NULL,
  occupied_count integer NOT NULL CHECK (occupied_count >= 0),
  free_count integer NOT NULL CHECK (free_count >= 0),
  occupancy_rate numeric(5,4) NOT NULL CHECK (occupancy_rate >= 0 AND occupancy_rate <= 1),
  PRIMARY KEY (ts, sector_id)
);

CREATE INDEX IF NOT EXISTS idx_sector_snapshots_sector_ts
  ON sector_snapshots (sector_id, ts DESC);

CREATE TABLE IF NOT EXISTS incidents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ts_open timestamptz NOT NULL,
  ts_close timestamptz,
  type incident_type NOT NULL,
  severity incident_severity NOT NULL,
  sector_id sector_code NOT NULL,
  spot_id text REFERENCES spots (spot_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  evidence_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  status incident_status NOT NULL DEFAULT 'open',
  CHECK (
    (status = 'open' AND ts_close IS NULL) OR
    (status = 'closed' AND ts_close IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_incidents_status_ts
  ON incidents (status, ts_open DESC);

CREATE INDEX IF NOT EXISTS idx_incidents_sector_status
  ON incidents (sector_id, status);

CREATE UNIQUE INDEX IF NOT EXISTS idx_incidents_open_unique
  ON incidents (type, sector_id, COALESCE(spot_id, ''))
  WHERE status = 'open';

CREATE TABLE IF NOT EXISTS recommendations_log (
  id bigserial PRIMARY KEY,
  ts timestamptz NOT NULL,
  from_sector sector_code NOT NULL,
  recommended_sector sector_code NOT NULL,
  reason text NOT NULL,
  data_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (from_sector <> recommended_sector)
);

CREATE INDEX IF NOT EXISTS idx_recommendations_log_ts
  ON recommendations_log (ts DESC);

CREATE INDEX IF NOT EXISTS idx_recommendations_log_from_sector
  ON recommendations_log (from_sector, ts DESC);

COMMENT ON TABLE spots IS 'Estado atual consolidado de cada vaga do estacionamento.';
COMMENT ON TABLE spot_events IS 'Historico completo dos eventos recebidos para cada vaga.';
COMMENT ON TABLE sector_snapshots IS 'Resumo temporal da ocupacao por setor, agregado por minuto.';
COMMENT ON TABLE incidents IS 'Incidentes detectados pelas regras de negocio e monitoramento.';
COMMENT ON TABLE recommendations_log IS 'Registro historico das recomendacoes emitidas pela API.';

COMMENT ON COLUMN spots.spot_id IS 'Identificador da vaga, por exemplo A-07.';
COMMENT ON COLUMN spots.sector_id IS 'Setor ao qual a vaga pertence.';
COMMENT ON COLUMN spots.current_state IS 'Estado atual consolidado da vaga.';
COMMENT ON COLUMN spots.last_change_ts IS 'Momento do ultimo evento aplicado na vaga.';
COMMENT ON COLUMN spots.last_event_id IS 'Ultimo event_id que atualizou o estado atual da vaga.';

COMMENT ON COLUMN spot_events.event_id IS 'Identificador unico do evento para idempotencia.';
COMMENT ON COLUMN spot_events.ts IS 'Timestamp original do evento.';
COMMENT ON COLUMN spot_events.sector_id IS 'Setor informado pelo evento.';
COMMENT ON COLUMN spot_events.spot_id IS 'Vaga informada pelo evento.';
COMMENT ON COLUMN spot_events.state IS 'Estado informado pelo evento.';
COMMENT ON COLUMN spot_events.raw_payload_json IS 'Payload bruto recebido via MQTT, preservado para auditoria.';

COMMENT ON COLUMN sector_snapshots.ts IS 'Minuto de referencia do snapshot.';
COMMENT ON COLUMN sector_snapshots.sector_id IS 'Setor resumido no snapshot.';
COMMENT ON COLUMN sector_snapshots.occupied_count IS 'Quantidade de vagas ocupadas no setor.';
COMMENT ON COLUMN sector_snapshots.free_count IS 'Quantidade de vagas livres no setor.';
COMMENT ON COLUMN sector_snapshots.occupancy_rate IS 'Taxa de ocupacao entre 0 e 1.';

COMMENT ON COLUMN incidents.ts_open IS 'Momento de abertura do incidente.';
COMMENT ON COLUMN incidents.ts_close IS 'Momento de fechamento do incidente.';
COMMENT ON COLUMN incidents.type IS 'Tipo do incidente detectado.';
COMMENT ON COLUMN incidents.severity IS 'Severidade do incidente.';
COMMENT ON COLUMN incidents.sector_id IS 'Setor relacionado ao incidente.';
COMMENT ON COLUMN incidents.spot_id IS 'Vaga relacionada ao incidente, quando aplicavel.';
COMMENT ON COLUMN incidents.evidence_json IS 'Evidencias usadas para justificar o incidente.';
COMMENT ON COLUMN incidents.status IS 'Situacao do incidente: aberto ou fechado.';

COMMENT ON COLUMN recommendations_log.ts IS 'Momento em que a recomendacao foi gerada.';
COMMENT ON COLUMN recommendations_log.from_sector IS 'Setor de origem da recomendacao.';
COMMENT ON COLUMN recommendations_log.recommended_sector IS 'Setor recomendado como destino.';
COMMENT ON COLUMN recommendations_log.reason IS 'Justificativa textual da recomendacao.';
COMMENT ON COLUMN recommendations_log.data_json IS 'Contexto numerico e dados auxiliares da recomendacao.';

CREATE OR REPLACE VIEW v_current_map AS
SELECT
  spot_id,
  sector_id,
  current_state,
  last_change_ts,
  last_event_id
FROM spots
ORDER BY sector_id, spot_id;

CREATE OR REPLACE VIEW v_sector_summary_current AS
SELECT
  sector_id,
  COUNT(*) FILTER (WHERE current_state = 'OCCUPIED')::integer AS occupied_count,
  COUNT(*) FILTER (WHERE current_state = 'FREE')::integer AS free_count,
  COALESCE(
    ROUND(
      (
        COUNT(*) FILTER (WHERE current_state = 'OCCUPIED')::numeric /
        NULLIF(COUNT(*), 0)
      ),
      4
    ),
    0
  ) AS occupancy_rate
FROM spots
GROUP BY sector_id
ORDER BY sector_id;

CREATE OR REPLACE VIEW vw_mapa_atual_vagas AS
SELECT
  spot_id AS id_vaga,
  sector_id AS id_setor,
  current_state AS estado_atual,
  last_change_ts AS ultima_mudanca_em,
  last_event_id AS ultimo_id_evento
FROM v_current_map;

CREATE OR REPLACE VIEW vw_resumo_atual_setores AS
SELECT
  sector_id AS id_setor,
  occupied_count AS vagas_ocupadas,
  free_count AS vagas_livres,
  occupancy_rate AS taxa_ocupacao
FROM v_sector_summary_current;

CREATE OR REPLACE FUNCTION get_sector_occupancy(p_sector_id sector_code DEFAULT NULL)
RETURNS TABLE (
  sector_id sector_code,
  occupied_count integer,
  free_count integer,
  occupancy_rate numeric(5,4)
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    s.sector_id,
    COUNT(*) FILTER (WHERE s.current_state = 'OCCUPIED')::integer AS occupied_count,
    COUNT(*) FILTER (WHERE s.current_state = 'FREE')::integer AS free_count,
    COALESCE(
      ROUND(
        (
          COUNT(*) FILTER (WHERE s.current_state = 'OCCUPIED')::numeric /
          NULLIF(COUNT(*), 0)
        ),
        4
      ),
      0
    )::numeric(5,4) AS occupancy_rate
  FROM spots s
  WHERE p_sector_id IS NULL OR s.sector_id = p_sector_id
  GROUP BY s.sector_id
  ORDER BY s.sector_id;
$$;

CREATE OR REPLACE FUNCTION upsert_sector_snapshot(
  p_snapshot_ts timestamptz,
  p_sector_id sector_code
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO sector_snapshots (
    ts,
    sector_id,
    occupied_count,
    free_count,
    occupancy_rate
  )
  SELECT
    p_snapshot_ts,
    occ.sector_id,
    occ.occupied_count,
    occ.free_count,
    occ.occupancy_rate
  FROM get_sector_occupancy(p_sector_id) occ
  ON CONFLICT (ts, sector_id) DO UPDATE
  SET
    occupied_count = EXCLUDED.occupied_count,
    free_count = EXCLUDED.free_count,
    occupancy_rate = EXCLUDED.occupancy_rate;
END;
$$;

CREATE OR REPLACE FUNCTION apply_spot_event(
  p_event_id uuid,
  p_ts timestamptz,
  p_sector_id sector_code,
  p_spot_id text,
  p_state spot_state,
  p_raw_payload_json jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  inserted_event boolean,
  applied_to_current_state boolean,
  sector_id sector_code,
  occupied_count integer,
  free_count integer,
  occupancy_rate numeric(5,4)
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_inserted_event_id uuid;
  v_spot_updated integer := 0;
BEGIN
  IF split_part(p_spot_id, '-', 1) <> p_sector_id::text THEN
    RAISE EXCEPTION 'Spot % does not belong to sector %', p_spot_id, p_sector_id;
  END IF;

  INSERT INTO spot_events (
    event_id,
    ts,
    sector_id,
    spot_id,
    state,
    raw_payload_json
  )
  VALUES (
    p_event_id,
    p_ts,
    p_sector_id,
    p_spot_id,
    p_state,
    COALESCE(p_raw_payload_json, '{}'::jsonb)
  )
  ON CONFLICT (event_id) DO NOTHING
  RETURNING event_id INTO v_inserted_event_id;

  IF v_inserted_event_id IS NULL THEN
    RETURN QUERY
    SELECT
      FALSE,
      FALSE,
      occ.sector_id,
      occ.occupied_count,
      occ.free_count,
      occ.occupancy_rate
    FROM get_sector_occupancy(p_sector_id) occ;
    RETURN;
  END IF;

  UPDATE spots
  SET
    current_state = p_state,
    last_change_ts = p_ts,
    last_event_id = p_event_id
  WHERE spot_id = p_spot_id
    AND sector_id = p_sector_id
    AND (last_change_ts IS NULL OR p_ts >= last_change_ts);

  GET DIAGNOSTICS v_spot_updated = ROW_COUNT;

  IF v_spot_updated > 0 THEN
    PERFORM upsert_sector_snapshot(date_trunc('minute', p_ts), p_sector_id);
  END IF;

  RETURN QUERY
  SELECT
    TRUE,
    v_spot_updated > 0,
    occ.sector_id,
    occ.occupied_count,
    occ.free_count,
    occ.occupancy_rate
  FROM get_sector_occupancy(p_sector_id) occ;
END;
$$;

CREATE OR REPLACE FUNCTION get_free_spots(
  p_sector_id sector_code,
  p_limit integer DEFAULT 10
)
RETURNS TABLE (
  spot_id text,
  sector_id sector_code,
  last_change_ts timestamptz
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    s.spot_id,
    s.sector_id,
    s.last_change_ts
  FROM spots s
  WHERE s.sector_id = p_sector_id
    AND s.current_state = 'FREE'
  ORDER BY s.spot_id
  LIMIT GREATEST(COALESCE(p_limit, 10), 1);
$$;

CREATE OR REPLACE FUNCTION get_turnover_report(
  p_sector_id sector_code,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS TABLE (
  spot_id text,
  turnover_count bigint
)
LANGUAGE sql
STABLE
AS $$
  WITH ordered_events AS (
    SELECT
      se.spot_id,
      se.ts,
      se.state,
      LAG(se.state) OVER (PARTITION BY se.spot_id ORDER BY se.ts) AS previous_state
    FROM spot_events se
    WHERE se.sector_id = p_sector_id
      AND se.ts <= p_to
  )
  SELECT
    oe.spot_id,
    COUNT(*)::bigint AS turnover_count
  FROM ordered_events oe
  WHERE oe.ts >= p_from
    AND oe.ts <= p_to
    AND oe.state = 'OCCUPIED'
    AND COALESCE(oe.previous_state, 'FREE'::spot_state) = 'FREE'
  GROUP BY oe.spot_id
  ORDER BY turnover_count DESC, oe.spot_id;
$$;

CREATE OR REPLACE FUNCTION get_incidents(
  p_status incident_status DEFAULT NULL,
  p_sector_id sector_code DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  ts_open timestamptz,
  ts_close timestamptz,
  type incident_type,
  severity incident_severity,
  sector_id sector_code,
  spot_id text,
  evidence_json jsonb,
  status incident_status
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    i.id,
    i.ts_open,
    i.ts_close,
    i.type,
    i.severity,
    i.sector_id,
    i.spot_id,
    i.evidence_json,
    i.status
  FROM incidents i
  WHERE (p_status IS NULL OR i.status = p_status)
    AND (p_sector_id IS NULL OR i.sector_id = p_sector_id)
  ORDER BY i.ts_open DESC;
$$;

CREATE OR REPLACE FUNCTION open_incident(
  p_ts_open timestamptz,
  p_type incident_type,
  p_severity incident_severity,
  p_sector_id sector_code,
  p_spot_id text,
  p_evidence_json jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_incident_id uuid;
BEGIN
  SELECT i.id
  INTO v_incident_id
  FROM incidents i
  WHERE i.status = 'open'
    AND i.type = p_type
    AND i.sector_id = p_sector_id
    AND COALESCE(i.spot_id, '') = COALESCE(p_spot_id, '')
  LIMIT 1;

  IF v_incident_id IS NOT NULL THEN
    RETURN v_incident_id;
  END IF;

  INSERT INTO incidents (
    ts_open,
    type,
    severity,
    sector_id,
    spot_id,
    evidence_json,
    status
  )
  VALUES (
    p_ts_open,
    p_type,
    p_severity,
    p_sector_id,
    p_spot_id,
    COALESCE(p_evidence_json, '{}'::jsonb),
    'open'
  )
  RETURNING id INTO v_incident_id;

  RETURN v_incident_id;
END;
$$;

CREATE OR REPLACE FUNCTION close_incident(
  p_incident_id uuid,
  p_ts_close timestamptz DEFAULT now()
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE incidents
  SET
    ts_close = p_ts_close,
    status = 'closed'
  WHERE id = p_incident_id
    AND status = 'open';
END;
$$;

CREATE OR REPLACE FUNCTION log_recommendation(
  p_ts timestamptz,
  p_from_sector sector_code,
  p_recommended_sector sector_code,
  p_reason text,
  p_data_json jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_log_id bigint;
BEGIN
  INSERT INTO recommendations_log (
    ts,
    from_sector,
    recommended_sector,
    reason,
    data_json
  )
  VALUES (
    p_ts,
    p_from_sector,
    p_recommended_sector,
    p_reason,
    COALESCE(p_data_json, '{}'::jsonb)
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$$;

COMMENT ON FUNCTION apply_spot_event(uuid, timestamptz, sector_code, text, spot_state, jsonb)
IS 'Persiste um evento, aplica idempotencia, atualiza a vaga atual e registra snapshot do setor.';

COMMENT ON FUNCTION get_turnover_report(sector_code, timestamptz, timestamptz)
IS 'Conta transicoes FREE para OCCUPIED por vaga em um intervalo.';

COMMENT ON FUNCTION open_incident(timestamptz, incident_type, incident_severity, sector_code, text, jsonb)
IS 'Abre incidente se ainda nao existir um equivalente em status open.';

COMMENT ON FUNCTION log_recommendation(timestamptz, sector_code, sector_code, text, jsonb)
IS 'Registra uma recomendacao emitida pela camada de negocio.';

CREATE OR REPLACE FUNCTION aplicar_evento_vaga(
  p_id_evento uuid,
  p_data_hora timestamptz,
  p_id_setor sector_code,
  p_id_vaga text,
  p_estado spot_state,
  p_payload_bruto jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  evento_inserido boolean,
  estado_atualizado boolean,
  id_setor sector_code,
  vagas_ocupadas integer,
  vagas_livres integer,
  taxa_ocupacao numeric(5,4)
)
LANGUAGE sql
AS $$
  SELECT
    inserted_event AS evento_inserido,
    applied_to_current_state AS estado_atualizado,
    sector_id AS id_setor,
    occupied_count AS vagas_ocupadas,
    free_count AS vagas_livres,
    occupancy_rate AS taxa_ocupacao
  FROM apply_spot_event(
    p_id_evento,
    p_data_hora,
    p_id_setor,
    p_id_vaga,
    p_estado,
    p_payload_bruto
  );
$$;

CREATE OR REPLACE FUNCTION obter_ocupacao_setor(
  p_id_setor sector_code DEFAULT NULL
)
RETURNS TABLE (
  id_setor sector_code,
  vagas_ocupadas integer,
  vagas_livres integer,
  taxa_ocupacao numeric(5,4)
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    sector_id AS id_setor,
    occupied_count AS vagas_ocupadas,
    free_count AS vagas_livres,
    occupancy_rate AS taxa_ocupacao
  FROM get_sector_occupancy(p_id_setor);
$$;

CREATE OR REPLACE FUNCTION obter_vagas_livres(
  p_id_setor sector_code,
  p_limite integer DEFAULT 10
)
RETURNS TABLE (
  id_vaga text,
  id_setor sector_code,
  ultima_mudanca_em timestamptz
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    spot_id AS id_vaga,
    sector_id AS id_setor,
    last_change_ts AS ultima_mudanca_em
  FROM get_free_spots(p_id_setor, p_limite);
$$;

CREATE OR REPLACE FUNCTION obter_relatorio_rotatividade(
  p_id_setor sector_code,
  p_de timestamptz,
  p_ate timestamptz
)
RETURNS TABLE (
  id_vaga text,
  quantidade_rotatividade bigint
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    spot_id AS id_vaga,
    turnover_count AS quantidade_rotatividade
  FROM get_turnover_report(p_id_setor, p_de, p_ate);
$$;

CREATE OR REPLACE FUNCTION obter_incidentes(
  p_status incident_status DEFAULT NULL,
  p_id_setor sector_code DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  aberto_em timestamptz,
  fechado_em timestamptz,
  tipo incident_type,
  severidade incident_severity,
  id_setor sector_code,
  id_vaga text,
  evidencias jsonb,
  status incident_status
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    id,
    ts_open AS aberto_em,
    ts_close AS fechado_em,
    type AS tipo,
    severity AS severidade,
    sector_id AS id_setor,
    spot_id AS id_vaga,
    evidence_json AS evidencias,
    status
  FROM get_incidents(p_status, p_id_setor);
$$;

CREATE OR REPLACE FUNCTION abrir_incidente(
  p_aberto_em timestamptz,
  p_tipo incident_type,
  p_severidade incident_severity,
  p_id_setor sector_code,
  p_id_vaga text,
  p_evidencias jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE sql
AS $$
  SELECT open_incident(
    p_aberto_em,
    p_tipo,
    p_severidade,
    p_id_setor,
    p_id_vaga,
    p_evidencias
  );
$$;

CREATE OR REPLACE FUNCTION fechar_incidente(
  p_id_incidente uuid,
  p_fechado_em timestamptz DEFAULT now()
)
RETURNS void
LANGUAGE sql
AS $$
  SELECT close_incident(p_id_incidente, p_fechado_em);
$$;

CREATE OR REPLACE FUNCTION registrar_recomendacao(
  p_data_hora timestamptz,
  p_setor_origem sector_code,
  p_setor_recomendado sector_code,
  p_motivo text,
  p_dados jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE sql
AS $$
  SELECT log_recommendation(
    p_data_hora,
    p_setor_origem,
    p_setor_recomendado,
    p_motivo,
    p_dados
  );
$$;
