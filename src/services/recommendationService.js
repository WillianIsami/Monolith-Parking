const db = require('../database/client');
const { normalizeSector } = require('../utils/validators');

function formatPercent(value) {
  return `${Math.round(Number(value) * 100)}%`;
}

async function getRecommendation(fromSector) {
  const normalizedFromSector = normalizeSector(fromSector);
  const { rows: sectors } = await db.query(
    `SELECT sector_id, occupied_count, free_count, occupancy_rate, last_update_ts
     FROM get_sector_occupancy(NULL)`
  );

  const origin = sectors.find((sector) => sector.sector_id === normalizedFromSector);
  if (!origin) {
    const error = new Error('Setor inválido ou inexistente. Use A, B ou C.');
    error.statusCode = 400;
    throw error;
  }

  const ts = new Date().toISOString();
  const occupancyRate = Number(origin.occupancy_rate);

  if (occupancyRate < 0.9) {
    return {
      fromSector: normalizedFromSector,
      recommendedSector: null,
      reason: `Sector ${normalizedFromSector} is below 90% occupancy (${formatPercent(occupancyRate)}); recommendation is not required`,
      ts
    };
  }

  const candidates = sectors
    .filter((sector) => sector.sector_id !== normalizedFromSector)
    .map((sector) => ({
      sectorId: sector.sector_id,
      occupiedCount: Number(sector.occupied_count),
      freeCount: Number(sector.free_count),
      occupancyRate: Number(sector.occupancy_rate)
    }))
    .sort((a, b) => b.freeCount - a.freeCount || a.occupancyRate - b.occupancyRate || a.sectorId.localeCompare(b.sectorId));

  const best = candidates[0];
  const reason = best && best.freeCount > 0
    ? `Sector ${normalizedFromSector} at ${formatPercent(occupancyRate)} occupancy; Sector ${best.sectorId} has ${best.freeCount} free spots`
    : `Sector ${normalizedFromSector} at ${formatPercent(occupancyRate)} occupancy; all alternative sectors are full`;

  const recommendedSector = best && best.freeCount > 0 ? best.sectorId : null;

  await db.query(
    `SELECT log_recommendation($1::timestamptz, $2::text, $3::text, $4::text, $5::jsonb)`,
    [
      ts,
      normalizedFromSector,
      recommendedSector,
      reason,
      JSON.stringify({
        origin: {
          sectorId: origin.sector_id,
          occupiedCount: Number(origin.occupied_count),
          freeCount: Number(origin.free_count),
          occupancyRate
        },
        candidates
      })
    ]
  );

  return {
    fromSector: normalizedFromSector,
    recommendedSector,
    reason,
    ts
  };
}

module.exports = {
  getRecommendation
};
