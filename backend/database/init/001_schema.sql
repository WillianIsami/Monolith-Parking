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

-- Compatibilidade para bancos compartilhados criados antes do status dos gateways.
ALTER TABLE gateway_status_events
  ADD COLUMN IF NOT EXISTS id bigserial;

ALTER TABLE gateway_status_events
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'gateway';

ALTER TABLE gateway_status_events
  ADD COLUMN IF NOT EXISTS raw_payload_json jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE gateway_status_events
  ADD COLUMN IF NOT EXISTS source_topic text;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'gateway_status_events'
      AND column_name = 'id'
      AND is_nullable = 'YES'
  ) THEN
    UPDATE gateway_status_events
    SET id = nextval(pg_get_serial_sequence('gateway_status_events', 'id'))
    WHERE id IS NULL;

    ALTER TABLE gateway_status_events
      ALTER COLUMN id SET NOT NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'gateway_status_events'::regclass
      AND contype = 'p'
  ) THEN
    ALTER TABLE gateway_status_events
      ADD PRIMARY KEY (id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'gateway_status_events'::regclass
      AND conname = 'gateway_status_events_source_check'
  ) THEN
    ALTER TABLE gateway_status_events
      ADD CONSTRAINT gateway_status_events_source_check
      CHECK (source IN ('gateway', 'sensor'));
  END IF;
END;
$$;

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

DROP VIEW IF EXISTS v_gateway_current_status CASCADE;
DROP VIEW IF EXISTS v_sector_summary_current CASCADE;
DROP VIEW IF EXISTS v_current_map CASCADE;

CREATE OR REPLACE VIEW v_current_map AS
SELECT
  spot_id,
  sector_id::text AS sector_id,
  current_state::text AS current_state,
  last_change_ts,
  last_event_id
FROM spots
ORDER BY sector_id, spot_id;

CREATE OR REPLACE VIEW v_sector_summary_current AS
SELECT
  s.sector_id::text AS sector_id,
  COUNT(*) FILTER (WHERE s.current_state::text = 'OCCUPIED')::integer AS occupied_count,
  COUNT(*) FILTER (WHERE s.current_state::text = 'FREE')::integer AS free_count,
  COALESCE(ROUND(COUNT(*) FILTER (WHERE s.current_state::text = 'OCCUPIED')::numeric / NULLIF(COUNT(*), 0), 4), 0)::numeric(5,4) AS occupancy_rate,
  MAX(s.last_change_ts) AS last_update_ts
FROM spots s
GROUP BY s.sector_id::text
ORDER BY s.sector_id::text;

CREATE OR REPLACE VIEW v_gateway_current_status AS
SELECT DISTINCT ON (gse.sector_id::text)
  gse.sector_id::text AS sector_id,
  COALESCE(gse.raw_payload_json->>'gatewayId', gse.gateway_id::text) AS gateway_id,
  UPPER(gse.status::text) AS status,
  COALESCE(gse.source, gse.raw_payload_json->>'source', 'gateway') AS source,
  gse.ts AS last_status_ts,
  gse.raw_payload_json
FROM gateway_status_events gse
ORDER BY gse.sector_id::text, gse.ts DESC, gse.id DESC;

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
DECLARE
  v_sector_udt text;
BEGIN
  SELECT udt_name
  INTO v_sector_udt
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'sector_snapshots'
    AND column_name = 'sector_id';

  IF v_sector_udt = 'sector_code' THEN
    EXECUTE '
      INSERT INTO sector_snapshots(ts, sector_id, occupied_count, free_count, occupancy_rate)
      SELECT
        $1,
        occ.sector_id::sector_code,
        occ.occupied_count,
        occ.free_count,
        occ.occupancy_rate
      FROM get_sector_occupancy($2) occ
      ON CONFLICT (ts, sector_id) DO UPDATE
      SET
        occupied_count = EXCLUDED.occupied_count,
        free_count = EXCLUDED.free_count,
        occupancy_rate = EXCLUDED.occupancy_rate'
    USING p_snapshot_ts, p_sector_id;
  ELSE
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
  END IF;
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
  v_event_sector_udt text;
  v_event_state_udt text;
  v_spot_state_udt text;
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

  SELECT udt_name
  INTO v_event_sector_udt
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'spot_events'
    AND column_name = 'sector_id';

  SELECT udt_name
  INTO v_event_state_udt
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'spot_events'
    AND column_name = 'state';

  IF v_event_sector_udt = 'sector_code' OR v_event_state_udt = 'spot_state' THEN
    EXECUTE '
      INSERT INTO spot_events(event_id, ts, sector_id, spot_id, state, raw_payload_json)
      VALUES ($1, $2, $3::sector_code, $4, $5::spot_state, $6)
      ON CONFLICT (event_id) DO NOTHING
      RETURNING event_id'
    INTO v_inserted_event_id
    USING p_event_id, p_ts, p_sector_id, p_spot_id, p_state, COALESCE(p_raw_payload_json, '{}'::jsonb);
  ELSE
    INSERT INTO spot_events(event_id, ts, sector_id, spot_id, state, raw_payload_json)
    VALUES (p_event_id, p_ts, p_sector_id, p_spot_id, p_state, COALESCE(p_raw_payload_json, '{}'::jsonb))
    ON CONFLICT (event_id) DO NOTHING
    RETURNING event_id INTO v_inserted_event_id;
  END IF;

  IF v_inserted_event_id IS NULL THEN
    RETURN QUERY
    SELECT FALSE, FALSE, occ.sector_id, occ.occupied_count, occ.free_count, occ.occupancy_rate
    FROM get_sector_occupancy(p_sector_id) occ;
    RETURN;
  END IF;

  SELECT udt_name
  INTO v_spot_state_udt
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'spots'
    AND column_name = 'current_state';

  IF v_spot_state_udt = 'spot_state' THEN
    EXECUTE '
      UPDATE spots s
      SET current_state = $1::spot_state,
          last_change_ts = $2,
          last_event_id = $3
      WHERE s.spot_id = $4
        AND s.sector_id::text = $5
        AND (s.last_change_ts IS NULL OR $2 >= s.last_change_ts)'
    USING p_state, p_ts, p_event_id, p_spot_id, p_sector_id;
  ELSE
    UPDATE spots s
    SET current_state = p_state,
        last_change_ts = p_ts,
        last_event_id = p_event_id
    WHERE s.spot_id = p_spot_id
      AND s.sector_id = p_sector_id
      AND (s.last_change_ts IS NULL OR p_ts >= s.last_change_ts);
  END IF;

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
  SELECT s.spot_id, s.sector_id::text, s.current_state::text, s.last_change_ts, s.last_event_id
  FROM spots s
  WHERE s.sector_id::text = p_sector_id
    AND s.current_state::text = 'FREE'
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
    i.type::text,
    i.severity::text,
    i.sector_id::text,
    i.spot_id,
    i.evidence_json,
    i.status::text
  FROM incidents i
  WHERE (p_status IS NULL OR i.status::text = p_status)
    AND (p_sector_id IS NULL OR i.sector_id::text = p_sector_id)
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
      se.state::text AS state,
      LAG(se.state::text) OVER (PARTITION BY se.spot_id ORDER BY se.ts, se.event_id) AS previous_state
    FROM spot_events se
    WHERE se.sector_id::text = p_sector_id
      AND se.ts <= p_to
  )
  SELECT
    oe.spot_id,
    COUNT(*)::bigint AS turnover_count
  FROM ordered_events oe
  WHERE oe.ts >= p_from
    AND oe.ts <= p_to
    AND oe.state::text = 'OCCUPIED'
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
  v_type_udt text;
BEGIN
  SELECT udt_name
  INTO v_type_udt
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'incidents'
    AND column_name = 'type';

  IF v_type_udt = 'incident_type' THEN
    EXECUTE '
      INSERT INTO incidents(ts_open, type, severity, sector_id, spot_id, evidence_json, status)
      VALUES ($1, $2::incident_type, $3::incident_severity, $4::sector_code, $5, $6, ''open''::incident_status)
      ON CONFLICT (type, sector_id, (COALESCE(spot_id, ''''))) WHERE status = ''open''::incident_status
      DO UPDATE
      SET evidence_json = EXCLUDED.evidence_json,
          ts_open = LEAST(incidents.ts_open, EXCLUDED.ts_open),
          severity = EXCLUDED.severity
      RETURNING id'
    INTO v_incident_id
    USING p_ts_open, p_type, p_severity, p_sector_id, p_spot_id, COALESCE(p_evidence_json, '{}'::jsonb);
  ELSE
    INSERT INTO incidents(ts_open, type, severity, sector_id, spot_id, evidence_json, status)
    VALUES (p_ts_open, p_type, p_severity, p_sector_id, p_spot_id, COALESCE(p_evidence_json, '{}'::jsonb), 'open')
    ON CONFLICT (type, sector_id, (COALESCE(spot_id, ''))) WHERE status = 'open'
    DO UPDATE
    SET evidence_json = EXCLUDED.evidence_json,
        ts_open = LEAST(incidents.ts_open, EXCLUDED.ts_open),
        severity = EXCLUDED.severity
    RETURNING id INTO v_incident_id;
  END IF;

  RETURN v_incident_id;
END;
$$;

CREATE OR REPLACE FUNCTION close_incident(p_incident_id uuid, p_ts_close timestamptz DEFAULT now())
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_status_udt text;
BEGIN
  SELECT udt_name
  INTO v_status_udt
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'incidents'
    AND column_name = 'status';

  IF v_status_udt = 'incident_status' THEN
    EXECUTE '
      UPDATE incidents
      SET ts_close = $1,
          status = ''closed''::incident_status
      WHERE id = $2
        AND status = ''open''::incident_status'
    USING p_ts_close, p_incident_id;
  ELSE
    UPDATE incidents
    SET ts_close = p_ts_close,
        status = 'closed'
    WHERE id = p_incident_id
      AND status = 'open';
  END IF;
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
  v_sector_udt text;
BEGIN
  SELECT udt_name
  INTO v_sector_udt
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'recommendations_log'
    AND column_name = 'from_sector';

  IF v_sector_udt = 'sector_code' THEN
    EXECUTE '
      INSERT INTO recommendations_log(ts, from_sector, recommended_sector, reason, data_json)
      VALUES ($1, $2::sector_code, $3::sector_code, $4, $5)
      RETURNING id'
    INTO v_log_id
    USING p_ts, p_from_sector, p_recommended_sector, p_reason, COALESCE(p_data_json, '{}'::jsonb);
  ELSE
    INSERT INTO recommendations_log(ts, from_sector, recommended_sector, reason, data_json)
    VALUES (p_ts, p_from_sector, p_recommended_sector, p_reason, COALESCE(p_data_json, '{}'::jsonb))
    RETURNING id INTO v_log_id;
  END IF;

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
  v_gateway_udt text;
  v_status_udt text;
  v_gateway_uuid uuid;
BEGIN
  IF p_sector_id NOT IN ('A', 'B', 'C') THEN
    RAISE EXCEPTION 'Invalid sector_id: %', p_sector_id;
  END IF;

  IF p_status NOT IN ('ONLINE', 'OFFLINE', 'DEGRADED') THEN
    RAISE EXCEPTION 'Invalid gateway status: %', p_status;
  END IF;

  SELECT udt_name
  INTO v_gateway_udt
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'gateway_status_events'
    AND column_name = 'gateway_id';

  SELECT udt_name
  INTO v_status_udt
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'gateway_status_events'
    AND column_name = 'status';

  IF v_gateway_udt = 'uuid' THEN
    EXECUTE '
      SELECT gateway_id
      FROM gateways
      WHERE sector_id::text = $1
      ORDER BY
        CASE WHEN gateway_code = $2 THEN 0 ELSE 1 END,
        gateway_code
      LIMIT 1'
    INTO v_gateway_uuid
    USING p_sector_id, p_gateway_id;

    IF v_gateway_uuid IS NULL THEN
      v_gateway_uuid := gen_random_uuid();

      EXECUTE '
        INSERT INTO gateways(gateway_id, sector_id, gateway_code, gateway_name, connectivity_status, last_heartbeat_ts, metadata_json)
        VALUES ($1, $2::sector_code, $3, $4, LOWER($5)::asset_status, $6, $7)
        ON CONFLICT DO NOTHING'
      USING
        v_gateway_uuid,
        p_sector_id,
        p_gateway_id,
        'Gateway ' || p_sector_id,
        p_status,
        p_ts,
        jsonb_build_object('source', 'mvp-compat');
    ELSE
      EXECUTE '
        UPDATE gateways
        SET connectivity_status = LOWER($1)::asset_status,
            last_heartbeat_ts = $2
        WHERE gateway_id = $3'
      USING p_status, p_ts, v_gateway_uuid;
    END IF;

    EXECUTE '
      INSERT INTO gateway_status_events(ts, sector_id, gateway_id, status, source, source_topic, raw_payload_json)
      VALUES ($1, $2::sector_code, $3, LOWER($4)::asset_status, $5, $6, $7)
      RETURNING id'
    INTO v_status_id
    USING
      p_ts,
      p_sector_id,
      v_gateway_uuid,
      p_status,
      COALESCE(p_source, 'gateway'),
      'campus/parking/sectors/' || p_sector_id || '/gateway/status',
      COALESCE(p_raw_payload_json, '{}'::jsonb);
  ELSIF v_status_udt = 'asset_status' THEN
    EXECUTE '
      INSERT INTO gateway_status_events(ts, sector_id, gateway_id, status, source, raw_payload_json)
      VALUES ($1, $2::sector_code, $3, LOWER($4)::asset_status, $5, $6)
      RETURNING id'
    INTO v_status_id
    USING p_ts, p_sector_id, p_gateway_id, p_status, COALESCE(p_source, 'gateway'), COALESCE(p_raw_payload_json, '{}'::jsonb);
  ELSE
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
  END IF;

  RETURN v_status_id;
END;
$$;
