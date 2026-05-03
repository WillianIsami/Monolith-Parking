CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS sectors (
  sector_id text PRIMARY KEY CHECK (sector_id IN ('A', 'B', 'C')),
  capacity integer NOT NULL DEFAULT 30 CHECK (capacity = 30),
  occupancy_alert_threshold numeric(5,4) NOT NULL DEFAULT 0.9000
);

CREATE TABLE IF NOT EXISTS spots (
  spot_id text PRIMARY KEY,
  sector_id text NOT NULL REFERENCES sectors(sector_id),
  current_state text NOT NULL DEFAULT 'FREE' CHECK (current_state IN ('FREE', 'OCCUPIED')),
  last_change_ts timestamptz,
  last_event_id uuid,
  CHECK (spot_id ~ '^[ABC]-(0[1-9]|[12][0-9]|30)$'),
  CHECK (split_part(spot_id, '-', 1) = sector_id)
);

CREATE INDEX IF NOT EXISTS idx_spots_sector_state ON spots(sector_id, current_state);

CREATE TABLE IF NOT EXISTS spot_events (
  event_id uuid PRIMARY KEY,
  ts timestamptz NOT NULL,
  sector_id text NOT NULL REFERENCES sectors(sector_id),
  spot_id text NOT NULL REFERENCES spots(spot_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  state text NOT NULL CHECK (state IN ('FREE', 'OCCUPIED')),
  raw_payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (split_part(spot_id, '-', 1) = sector_id)
);

CREATE INDEX IF NOT EXISTS idx_spot_events_sector_ts ON spot_events(sector_id, ts DESC);
CREATE INDEX IF NOT EXISTS idx_spot_events_spot_ts ON spot_events(spot_id, ts DESC);

CREATE TABLE IF NOT EXISTS gateway_status_events (
  id bigserial PRIMARY KEY,
  ts timestamptz NOT NULL,
  sector_id text NOT NULL REFERENCES sectors(sector_id),
  gateway_id text NOT NULL,
  status text NOT NULL CHECK (status IN ('ONLINE', 'OFFLINE', 'DEGRADED')),
  source text NOT NULL DEFAULT 'gateway' CHECK (source IN ('gateway', 'sensor')),
  raw_payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (gateway_id <> '')
);

CREATE INDEX IF NOT EXISTS idx_gateway_status_events_sector_ts
  ON gateway_status_events(sector_id, ts DESC);

CREATE TABLE IF NOT EXISTS sector_snapshots (
  ts timestamptz NOT NULL,
  sector_id text NOT NULL REFERENCES sectors(sector_id),
  occupied_count integer NOT NULL CHECK (occupied_count >= 0),
  free_count integer NOT NULL CHECK (free_count >= 0),
  occupancy_rate numeric(5,4) NOT NULL CHECK (occupancy_rate >= 0 AND occupancy_rate <= 1),
  PRIMARY KEY (ts, sector_id)
);

CREATE INDEX IF NOT EXISTS idx_sector_snapshots_sector_ts ON sector_snapshots(sector_id, ts DESC);

CREATE TABLE IF NOT EXISTS incidents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ts_open timestamptz NOT NULL,
  ts_close timestamptz,
  type text NOT NULL CHECK (type IN ('STUCK_OCCUPIED', 'STUCK_FREE', 'FLAPPING')),
  severity text NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  sector_id text NOT NULL REFERENCES sectors(sector_id),
  spot_id text REFERENCES spots(spot_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  evidence_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
  CHECK ((status = 'open' AND ts_close IS NULL) OR (status = 'closed' AND ts_close IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS idx_incidents_status_ts ON incidents(status, ts_open DESC);
CREATE INDEX IF NOT EXISTS idx_incidents_sector_status ON incidents(sector_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_incidents_open_unique
  ON incidents(type, sector_id, COALESCE(spot_id, ''))
  WHERE status = 'open';

CREATE TABLE IF NOT EXISTS recommendations_log (
  id bigserial PRIMARY KEY,
  ts timestamptz NOT NULL,
  from_sector text NOT NULL REFERENCES sectors(sector_id),
  recommended_sector text REFERENCES sectors(sector_id),
  reason text NOT NULL,
  data_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (recommended_sector IS NULL OR from_sector <> recommended_sector)
);

CREATE INDEX IF NOT EXISTS idx_recommendations_log_ts ON recommendations_log(ts DESC);
CREATE INDEX IF NOT EXISTS idx_recommendations_log_from_sector ON recommendations_log(from_sector, ts DESC);

CREATE OR REPLACE VIEW v_current_map AS
SELECT spot_id, sector_id, current_state, last_change_ts, last_event_id
FROM spots
ORDER BY sector_id, spot_id;

CREATE OR REPLACE VIEW v_sector_summary_current AS
SELECT
  s.sector_id,
  COUNT(*) FILTER (WHERE s.current_state = 'OCCUPIED')::integer AS occupied_count,
  COUNT(*) FILTER (WHERE s.current_state = 'FREE')::integer AS free_count,
  COALESCE(ROUND(COUNT(*) FILTER (WHERE s.current_state = 'OCCUPIED')::numeric / NULLIF(COUNT(*), 0), 4), 0)::numeric(5,4) AS occupancy_rate,
  MAX(s.last_change_ts) AS last_update_ts
FROM spots s
GROUP BY s.sector_id
ORDER BY s.sector_id;

CREATE OR REPLACE VIEW v_gateway_current_status AS
SELECT DISTINCT ON (gse.sector_id)
  gse.sector_id,
  gse.gateway_id,
  gse.status,
  gse.source,
  gse.ts AS last_status_ts,
  gse.raw_payload_json
FROM gateway_status_events gse
ORDER BY gse.sector_id, gse.ts DESC, gse.id DESC;

CREATE OR REPLACE FUNCTION get_sector_occupancy(p_sector_id text DEFAULT NULL)
RETURNS TABLE (
  sector_id text,
  occupied_count integer,
  free_count integer,
  occupancy_rate numeric(5,4),
  last_update_ts timestamptz
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    v.sector_id,
    v.occupied_count,
    v.free_count,
    v.occupancy_rate,
    v.last_update_ts
  FROM v_sector_summary_current v
  WHERE p_sector_id IS NULL OR v.sector_id = p_sector_id
  ORDER BY v.sector_id;
$$;

CREATE OR REPLACE FUNCTION upsert_sector_snapshot(
  p_snapshot_ts timestamptz,
  p_sector_id text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO sector_snapshots(ts, sector_id, occupied_count, free_count, occupancy_rate)
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
  p_sector_id text,
  p_spot_id text,
  p_state text,
  p_raw_payload_json jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  inserted_event boolean,
  applied_to_current_state boolean,
  sector_id text,
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
  IF p_sector_id NOT IN ('A', 'B', 'C') THEN
    RAISE EXCEPTION 'Invalid sector_id: %', p_sector_id;
  END IF;

  IF p_state NOT IN ('FREE', 'OCCUPIED') THEN
    RAISE EXCEPTION 'Invalid spot state: %', p_state;
  END IF;

  IF split_part(p_spot_id, '-', 1) <> p_sector_id THEN
    RAISE EXCEPTION 'Spot % does not belong to sector %', p_spot_id, p_sector_id;
  END IF;

  INSERT INTO spot_events(event_id, ts, sector_id, spot_id, state, raw_payload_json)
  VALUES (p_event_id, p_ts, p_sector_id, p_spot_id, p_state, COALESCE(p_raw_payload_json, '{}'::jsonb))
  ON CONFLICT (event_id) DO NOTHING
  RETURNING event_id INTO v_inserted_event_id;

  IF v_inserted_event_id IS NULL THEN
    RETURN QUERY
    SELECT FALSE, FALSE, occ.sector_id, occ.occupied_count, occ.free_count, occ.occupancy_rate
    FROM get_sector_occupancy(p_sector_id) occ;
    RETURN;
  END IF;

  UPDATE spots s
  SET current_state = p_state,
      last_change_ts = p_ts,
      last_event_id = p_event_id
  WHERE s.spot_id = p_spot_id
    AND s.sector_id = p_sector_id
    AND (s.last_change_ts IS NULL OR p_ts >= s.last_change_ts);

  GET DIAGNOSTICS v_spot_updated = ROW_COUNT;

  IF v_spot_updated > 0 THEN
    PERFORM upsert_sector_snapshot(date_trunc('minute', p_ts), p_sector_id);
  END IF;

  RETURN QUERY
  SELECT TRUE, v_spot_updated > 0, occ.sector_id, occ.occupied_count, occ.free_count, occ.occupancy_rate
  FROM get_sector_occupancy(p_sector_id) occ;
END;
$$;

CREATE OR REPLACE FUNCTION get_free_spots(p_sector_id text, p_limit integer DEFAULT 10)
RETURNS TABLE (
  spot_id text,
  sector_id text,
  current_state text,
  last_change_ts timestamptz,
  last_event_id uuid
)
LANGUAGE sql
STABLE
AS $$
  SELECT s.spot_id, s.sector_id, s.current_state, s.last_change_ts, s.last_event_id
  FROM spots s
  WHERE s.sector_id = p_sector_id
    AND s.current_state = 'FREE'
  ORDER BY s.spot_id
  LIMIT GREATEST(COALESCE(p_limit, 10), 1);
$$;

CREATE OR REPLACE FUNCTION get_incidents(
  p_status text DEFAULT NULL,
  p_sector_id text DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  ts_open timestamptz,
  ts_close timestamptz,
  type text,
  severity text,
  sector_id text,
  spot_id text,
  evidence_json jsonb,
  status text
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

CREATE OR REPLACE FUNCTION get_turnover_report(
  p_sector_id text,
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
      LAG(se.state) OVER (PARTITION BY se.spot_id ORDER BY se.ts, se.event_id) AS previous_state
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
    AND COALESCE(oe.previous_state, 'FREE') = 'FREE'
  GROUP BY oe.spot_id
  ORDER BY turnover_count DESC, oe.spot_id;
$$;

CREATE OR REPLACE FUNCTION open_incident(
  p_ts_open timestamptz,
  p_type text,
  p_severity text,
  p_sector_id text,
  p_spot_id text,
  p_evidence_json jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_incident_id uuid;
BEGIN
  SELECT i.id INTO v_incident_id
  FROM incidents i
  WHERE i.status = 'open'
    AND i.type = p_type
    AND i.sector_id = p_sector_id
    AND COALESCE(i.spot_id, '') = COALESCE(p_spot_id, '')
  LIMIT 1;

  IF v_incident_id IS NOT NULL THEN
    UPDATE incidents
    SET evidence_json = COALESCE(p_evidence_json, '{}'::jsonb),
        ts_open = LEAST(ts_open, p_ts_open)
    WHERE id = v_incident_id;
    RETURN v_incident_id;
  END IF;

  INSERT INTO incidents(ts_open, type, severity, sector_id, spot_id, evidence_json, status)
  VALUES (p_ts_open, p_type, p_severity, p_sector_id, p_spot_id, COALESCE(p_evidence_json, '{}'::jsonb), 'open')
  RETURNING id INTO v_incident_id;

  RETURN v_incident_id;
END;
$$;

CREATE OR REPLACE FUNCTION close_incident(p_incident_id uuid, p_ts_close timestamptz DEFAULT now())
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE incidents
  SET ts_close = p_ts_close,
      status = 'closed'
  WHERE id = p_incident_id
    AND status = 'open';
END;
$$;

CREATE OR REPLACE FUNCTION log_recommendation(
  p_ts timestamptz,
  p_from_sector text,
  p_recommended_sector text,
  p_reason text,
  p_data_json jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_log_id bigint;
BEGIN
  INSERT INTO recommendations_log(ts, from_sector, recommended_sector, reason, data_json)
  VALUES (p_ts, p_from_sector, p_recommended_sector, p_reason, COALESCE(p_data_json, '{}'::jsonb))
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$$;

CREATE OR REPLACE FUNCTION record_gateway_status(
  p_ts timestamptz,
  p_sector_id text,
  p_gateway_id text,
  p_status text,
  p_source text DEFAULT 'gateway',
  p_raw_payload_json jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_status_id bigint;
BEGIN
  IF p_sector_id NOT IN ('A', 'B', 'C') THEN
    RAISE EXCEPTION 'Invalid sector_id: %', p_sector_id;
  END IF;

  IF p_status NOT IN ('ONLINE', 'OFFLINE', 'DEGRADED') THEN
    RAISE EXCEPTION 'Invalid gateway status: %', p_status;
  END IF;

  INSERT INTO gateway_status_events(ts, sector_id, gateway_id, status, source, raw_payload_json)
  VALUES (
    p_ts,
    p_sector_id,
    p_gateway_id,
    p_status,
    COALESCE(p_source, 'gateway'),
    COALESCE(p_raw_payload_json, '{}'::jsonb)
  )
  RETURNING id INTO v_status_id;

  RETURN v_status_id;
END;
$$;
