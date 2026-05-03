const db = require('../database/client');
const {
  normalizeSector,
  normalizeSource,
  isValidSector,
  isValidSource,
  normalizeTimestamp
} = require('../utils/validators');

const VALID_GATEWAY_STATUS = new Set(['ONLINE', 'OFFLINE', 'DEGRADED']);

function normalizeGatewayStatus(status) {
  return typeof status === 'string' ? status.trim().toUpperCase() : '';
}

function toGatewayStatus(row) {
  return {
    sectorId: row.sector_id,
    gatewayId: row.gateway_id,
    status: row.status,
    source: row.source,
    lastStatusTs: row.last_status_ts,
    rawPayloadJson: row.raw_payload_json
  };
}

async function recordGatewayStatus(payload) {
  const ts = normalizeTimestamp(payload?.ts);
  const sectorId = normalizeSector(payload?.sectorId);
  const gatewayId = typeof payload?.gatewayId === 'string' ? payload.gatewayId.trim() : '';
  const status = normalizeGatewayStatus(payload?.status);
  const source = normalizeSource(payload?.source || 'gateway');

  if (!ts) {
    throw new Error(`ts de gateway invalido: ${payload?.ts}`);
  }

  if (!isValidSector(sectorId)) {
    throw new Error(`sectorId de gateway invalido: ${payload?.sectorId}`);
  }

  if (!gatewayId) {
    throw new Error('gatewayId e obrigatorio no status do gateway.');
  }

  if (!VALID_GATEWAY_STATUS.has(status)) {
    throw new Error(`status de gateway invalido: ${payload?.status}`);
  }

  if (!isValidSource(source)) {
    throw new Error(`source de gateway invalido: ${payload?.source}`);
  }

  const rawPayload = {
    ...payload,
    ts,
    sectorId,
    gatewayId,
    status,
    source
  };

  const { rows } = await db.query(
    `SELECT record_gateway_status($1::timestamptz, $2::text, $3::text, $4::text, $5::text, $6::jsonb) AS id`,
    [ts, sectorId, gatewayId, status, source, JSON.stringify(rawPayload)]
  );

  return rows[0]?.id;
}

async function getGatewayStatuses() {
  const { rows } = await db.query(`
    SELECT sector_id, gateway_id, status, source, last_status_ts, raw_payload_json
    FROM v_gateway_current_status
    ORDER BY sector_id
  `);

  return rows.map(toGatewayStatus);
}

module.exports = {
  recordGatewayStatus,
  getGatewayStatuses,
  toGatewayStatus
};
