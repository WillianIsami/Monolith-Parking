DO $$
DECLARE
  v_has_advanced_sector_columns boolean;
  v_spot_sector_udt text;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'sectors'
      AND column_name = 'facility_id'
  )
  INTO v_has_advanced_sector_columns;

  IF v_has_advanced_sector_columns THEN
    UPDATE sectors
    SET
      capacity = 30,
      occupancy_alert_threshold = 0.9000
    WHERE sector_id::text IN ('A', 'B', 'C');
  ELSE
    INSERT INTO sectors(sector_id, capacity, occupancy_alert_threshold)
    VALUES
      ('A', 30, 0.9000),
      ('B', 30, 0.9000),
      ('C', 30, 0.9000)
    ON CONFLICT (sector_id) DO NOTHING;
  END IF;

  SELECT udt_name
  INTO v_spot_sector_udt
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'spots'
    AND column_name = 'sector_id';

  IF v_spot_sector_udt = 'sector_code' THEN
    EXECUTE '
      INSERT INTO spots(spot_id, sector_id, current_state, last_change_ts, last_event_id)
      SELECT
        sector_id || ''-'' || LPAD(spot_number::text, 2, ''0'') AS spot_id,
        sector_id::sector_code,
        ''FREE''::spot_state AS current_state,
        NULL::timestamptz AS last_change_ts,
        NULL::uuid AS last_event_id
      FROM unnest(ARRAY[''A'', ''B'', ''C'']) AS sector_id
      CROSS JOIN generate_series(1, 30) AS spot_number
      ON CONFLICT (spot_id) DO NOTHING';
  ELSE
    INSERT INTO spots(spot_id, sector_id, current_state, last_change_ts, last_event_id)
    SELECT
      sector_id || '-' || LPAD(spot_number::text, 2, '0') AS spot_id,
      sector_id,
      'FREE' AS current_state,
      NULL::timestamptz AS last_change_ts,
      NULL::uuid AS last_event_id
    FROM unnest(ARRAY['A', 'B', 'C']) AS sector_id
    CROSS JOIN generate_series(1, 30) AS spot_number
    ON CONFLICT (spot_id) DO NOTHING;
  END IF;
END;
$$;

SELECT upsert_sector_snapshot(date_trunc('minute', now()), sector_id::text)
FROM sectors
WHERE sector_id::text IN ('A', 'B', 'C');
