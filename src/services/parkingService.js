const db = require('../database/client');
const {
  normalizeSector,
  normalizeState,
  normalizeSource,
  normalizeSpotId,
  isValidSector,
  isValidSpotId,
  isValidState,
  isValidSource,
  isValidUuid,
  normalizeTimestamp
} = require('../utils/validators');

function toSpot(row) {
  return {
    spotId: row.spot_id,
    sectorId: row.sector_id,
    state: row.current_state,
    lastChangeTs: row.last_change_ts,
    lastEventId: row.last_event_id
  };
}

function toSector(row) {
  return {
    sectorId: row.sector_id,
    occupiedCount: Number(row.occupied_count),
    freeCount: Number(row.free_count),
    occupancyRate: Number(row.occupancy_rate),
    lastUpdateTs: row.last_update_ts
  };
}

async function getMap() {
  const [{ rows: spots }, { rows: sectors }] = await Promise.all([
    db.query('SELECT spot_id, sector_id, current_state, last_change_ts, last_event_id FROM v_current_map ORDER BY sector_id, spot_id'),
    db.query('SELECT sector_id, occupied_count, free_count, occupancy_rate, last_update_ts FROM get_sector_occupancy(NULL)')
  ]);

  const bySector = new Map(sectors.map((sector) => [sector.sector_id, { ...toSector(sector), spots: [] }]));

  for (const spot of spots) {
    const sector = bySector.get(spot.sector_id);
    if (sector) sector.spots.push(toSpot(spot));
  }

  return {
    sectors: Array.from(bySector.values()),
    lastUpdateTs: new Date().toISOString()
  };
}

async function getSectors() {
  const { rows } = await db.query('SELECT sector_id, occupied_count, free_count, occupancy_rate, last_update_ts FROM get_sector_occupancy(NULL)');
  return rows.map(toSector);
}

async function getSectorSpots(sectorId) {
  const normalizedSector = normalizeSector(sectorId);
  const { rows } = await db.query(
    `SELECT spot_id, sector_id, current_state, last_change_ts, last_event_id
     FROM spots
     WHERE sector_id = $1
     ORDER BY spot_id`,
    [normalizedSector]
  );

  return rows.map(toSpot);
}

async function getFreeSpots(sectorId, limit) {
  const normalizedSector = normalizeSector(sectorId);
  const { rows } = await db.query('SELECT * FROM get_free_spots($1, $2)', [normalizedSector, limit]);
  return rows.map(toSpot);
}

async function getTurnoverReport(sectorId, from, to) {
  const normalizedSector = normalizeSector(sectorId);
  const { rows } = await db.query('SELECT * FROM get_turnover_report($1, $2, $3)', [normalizedSector, from, to]);
  const bySpot = rows.map((row) => ({ spotId: row.spot_id, turnover: Number(row.turnover_count) }));
  const turnover = bySpot.reduce((sum, spot) => sum + spot.turnover, 0);

  return {
    sectorId: normalizedSector,
    from,
    to,
    turnover,
    bySpot
  };
}

async function applySpotEvent(payload) {
  const eventId = payload?.eventId;
  const sectorId = normalizeSector(payload?.sectorId);
  const spotId = normalizeSpotId(payload?.spotId);
  const state = normalizeState(payload?.state);
  const source = normalizeSource(payload?.source);
  const ts = normalizeTimestamp(payload?.ts);

  if (!isValidUuid(eventId)) {
    throw new Error(`eventId inválido: ${eventId}`);
  }

  if (!ts) {
    throw new Error(`ts inválido: ${payload?.ts}`);
  }

  if (!isValidSector(sectorId)) {
    throw new Error(`sectorId inválido: ${payload?.sectorId}`);
  }

  if (!isValidSpotId(spotId, sectorId)) {
    throw new Error(`spotId inválido ou incompatível com o setor: ${payload?.spotId}`);
  }

  if (!isValidState(state)) {
    throw new Error(`state inválido: ${payload?.state}`);
  }

  if (!isValidSource(source)) {
    throw new Error(`source inválido: ${payload?.source}`);
  }

  const rawPayload = {
    ...payload,
    ts,
    sectorId,
    spotId,
    state,
    source
  };

  const { rows } = await db.query(
    `SELECT * FROM apply_spot_event($1::uuid, $2::timestamptz, $3::text, $4::text, $5::text, $6::jsonb)`,
    [eventId, ts, sectorId, spotId, state, JSON.stringify(rawPayload)]
  );

  return rows[0] || null;
}

module.exports = {
  getMap,
  getSectors,
  getSectorSpots,
  getFreeSpots,
  getTurnoverReport,
  applySpotEvent,
  toSpot,
  toSector
};
