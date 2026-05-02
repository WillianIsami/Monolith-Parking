const db = require('../database/client');
const config = require('../config');

function toIncident(row) {
  return {
    id: row.id,
    tsOpen: row.ts_open,
    tsClose: row.ts_close,
    type: row.type,
    severity: row.severity,
    sectorId: row.sector_id,
    spotId: row.spot_id,
    evidenceJson: row.evidence_json,
    status: row.status
  };
}

async function openIncident({ tsOpen, type, severity, sectorId, spotId, evidence }) {
  const { rows } = await db.query(
    `SELECT open_incident($1::timestamptz, $2::text, $3::text, $4::text, $5::text, $6::jsonb) AS id`,
    [tsOpen, type, severity, sectorId, spotId, JSON.stringify(evidence || {})]
  );

  return rows[0]?.id;
}

async function getIncidents({ status, sectorId } = {}) {
  const values = [];
  const where = [];

  if (status) {
    values.push(status);
    where.push(`status = $${values.length}`);
  }

  if (sectorId) {
    values.push(sectorId);
    where.push(`sector_id = $${values.length}`);
  }

  const sql = `
    SELECT id, ts_open, ts_close, type, severity, sector_id, spot_id, evidence_json, status
    FROM incidents
    ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
    ORDER BY ts_open DESC
  `;

  const { rows } = await db.query(sql, values);
  return rows.map(toIncident);
}

async function getReferenceTimestamp() {
  const { rows } = await db.query(`
    SELECT COALESCE(MAX(last_change_ts), now()) AS reference_ts
    FROM spots
  `);

  return rows[0].reference_ts;
}

async function checkStuckOccupied(referenceTs) {
  const { rows } = await db.query(
    `SELECT spot_id, sector_id, current_state, last_change_ts
     FROM spots
     WHERE current_state = 'OCCUPIED'
       AND last_change_ts IS NOT NULL
       AND last_change_ts <= ($1::timestamptz - ($2::text || ' minutes')::interval)`,
    [referenceTs, config.stuckOccupiedMinutes]
  );

  for (const row of rows) {
    await openIncident({
      tsOpen: referenceTs,
      type: 'STUCK_OCCUPIED',
      severity: 'high',
      sectorId: row.sector_id,
      spotId: row.spot_id,
      evidence: {
        rule: 'Vaga ocupada por tempo suspeito',
        thresholdMinutes: config.stuckOccupiedMinutes,
        currentState: row.current_state,
        lastChangeTs: row.last_change_ts,
        referenceTs
      }
    });
  }

  return rows.length;
}

async function checkStuckFree(referenceTs) {
  const { rows } = await db.query(
    `SELECT spot_id, sector_id, current_state, last_change_ts
     FROM spots
     WHERE current_state = 'FREE'
       AND last_change_ts IS NOT NULL
       AND last_change_ts <= ($1::timestamptz - ($2::text || ' minutes')::interval)`,
    [referenceTs, config.stuckFreeMinutes]
  );

  for (const row of rows) {
    await openIncident({
      tsOpen: referenceTs,
      type: 'STUCK_FREE',
      severity: 'medium',
      sectorId: row.sector_id,
      spotId: row.spot_id,
      evidence: {
        rule: 'Vaga livre por tempo suspeito',
        thresholdMinutes: config.stuckFreeMinutes,
        currentState: row.current_state,
        lastChangeTs: row.last_change_ts,
        referenceTs
      }
    });
  }

  return rows.length;
}

async function checkFlapping(referenceTs) {
  const { rows } = await db.query(
    `WITH recent AS (
       SELECT spot_id, sector_id, state, ts,
              LAG(state) OVER (PARTITION BY spot_id ORDER BY ts, event_id) AS previous_state
       FROM spot_events
       WHERE ts >= ($1::timestamptz - ($2::text || ' minutes')::interval)
         AND ts <= $1::timestamptz
     )
     SELECT spot_id,
            sector_id,
            COUNT(*) FILTER (WHERE previous_state IS NULL OR state <> previous_state)::integer AS transitions,
            MIN(ts) AS first_event_ts,
            MAX(ts) AS last_event_ts
     FROM recent
     GROUP BY spot_id, sector_id
     HAVING COUNT(*) FILTER (WHERE previous_state IS NULL OR state <> previous_state) >= $3`,
    [referenceTs, config.flappingWindowMinutes, config.flappingThreshold]
  );

  for (const row of rows) {
    await openIncident({
      tsOpen: referenceTs,
      type: 'FLAPPING',
      severity: 'high',
      sectorId: row.sector_id,
      spotId: row.spot_id,
      evidence: {
        rule: 'Trocas rápidas demais entre FREE e OCCUPIED',
        thresholdTransitions: config.flappingThreshold,
        windowMinutes: config.flappingWindowMinutes,
        transitions: Number(row.transitions),
        firstEventTs: row.first_event_ts,
        lastEventTs: row.last_event_ts,
        referenceTs
      }
    });
  }

  return rows.length;
}

async function checkIncidents() {
  const referenceTs = await getReferenceTimestamp();
  const [stuckOccupied, stuckFree, flapping] = await Promise.all([
    checkStuckOccupied(referenceTs),
    checkStuckFree(referenceTs),
    checkFlapping(referenceTs)
  ]);

  const total = stuckOccupied + stuckFree + flapping;
  if (total > 0) {
    console.log(`[INCIDENTS] Verificação concluída: ${total} ocorrência(s) detectada(s).`);
  }

  return { stuckOccupied, stuckFree, flapping, total };
}

module.exports = {
  checkIncidents,
  getIncidents,
  openIncident,
  toIncident
};
