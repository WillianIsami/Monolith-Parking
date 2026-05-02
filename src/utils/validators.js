const VALID_SECTORS = new Set(['A', 'B', 'C']);
const VALID_STATES = new Set(['FREE', 'OCCUPIED']);
const VALID_SOURCES = new Set(['sensor', 'gateway']);
const VALID_INCIDENT_STATUS = new Set(['open', 'closed']);

function normalizeSector(sectorId) {
  return typeof sectorId === 'string' ? sectorId.trim().toUpperCase() : '';
}

function normalizeState(state) {
  return typeof state === 'string' ? state.trim().toUpperCase() : '';
}

function normalizeSource(source) {
  return typeof source === 'string' ? source.trim().toLowerCase() : '';
}

function normalizeSpotId(spotId) {
  return typeof spotId === 'string' ? spotId.trim().toUpperCase() : '';
}

function isValidSector(sectorId) {
  return VALID_SECTORS.has(normalizeSector(sectorId));
}

function isValidState(state) {
  return VALID_STATES.has(normalizeState(state));
}

function isValidSource(source) {
  return VALID_SOURCES.has(normalizeSource(source));
}

function isValidSpotId(spotId, sectorId) {
  const normalizedSpot = normalizeSpotId(spotId);
  const normalizedSector = normalizeSector(sectorId);
  const match = normalizedSpot.match(/^([A-C])-(0[1-9]|[12][0-9]|30)$/);
  return Boolean(match && match[1] === normalizedSector);
}

function isValidUuid(value) {
  return typeof value === 'string'
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function normalizeTimestamp(value) {
  if (typeof value === 'number') {
    const millis = value < 1e12 ? value * 1000 : value;
    const date = new Date(millis);
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
  }

  if (typeof value === 'string') {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
  }

  return null;
}

function parsePositiveInteger(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function parseIsoDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

module.exports = {
  VALID_SECTORS,
  VALID_STATES,
  VALID_SOURCES,
  VALID_INCIDENT_STATUS,
  normalizeSector,
  normalizeState,
  normalizeSource,
  normalizeSpotId,
  isValidSector,
  isValidState,
  isValidSource,
  isValidSpotId,
  isValidUuid,
  normalizeTimestamp,
  parsePositiveInteger,
  parseIsoDate
};
