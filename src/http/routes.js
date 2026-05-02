const express = require('express');
const parkingService = require('../services/parkingService');
const incidentService = require('../services/incidentService');
const recommendationService = require('../services/recommendationService');
const {
  normalizeSector,
  isValidSector,
  VALID_INCIDENT_STATUS,
  parsePositiveInteger,
  parseIsoDate
} = require('../utils/validators');

const router = express.Router();

function asyncHandler(handler) {
  return async (req, res, next) => {
    try {
      await handler(req, res, next);
    } catch (error) {
      next(error);
    }
  };
}

function validateSectorParam(req, res, next) {
  const sectorId = normalizeSector(req.params.sectorId || req.query.fromSector || req.query.sectorId);
  if (!isValidSector(sectorId)) {
    return res.status(400).json({ error: 'sectorId inválido. Use A, B ou C.' });
  }
  req.normalizedSectorId = sectorId;
  return next();
}

router.get('/health', asyncHandler(async (_req, res) => {
  res.json({ status: 'ok', service: 'parking-backend', ts: new Date().toISOString() });
}));

router.get('/map', asyncHandler(async (_req, res) => {
  res.json(await parkingService.getMap());
}));

router.get('/sectors', asyncHandler(async (_req, res) => {
  res.json(await parkingService.getSectors());
}));

router.get('/sectors/:sectorId/spots', validateSectorParam, asyncHandler(async (req, res) => {
  res.json({
    sectorId: req.normalizedSectorId,
    spots: await parkingService.getSectorSpots(req.normalizedSectorId)
  });
}));

router.get('/sectors/:sectorId/free-spots', validateSectorParam, asyncHandler(async (req, res) => {
  const limit = parsePositiveInteger(req.query.limit, 10);
  const freeSpots = await parkingService.getFreeSpots(req.normalizedSectorId, limit);
  res.json({
    sectorId: req.normalizedSectorId,
    limit,
    freeCount: freeSpots.length,
    freeSpots
  });
}));

router.get('/reports/turnover', validateSectorParam, asyncHandler(async (req, res) => {
  const from = parseIsoDate(req.query.from);
  const to = parseIsoDate(req.query.to);

  if (!from || !to) {
    return res.status(400).json({ error: 'Parâmetros from e to são obrigatórios e precisam ser datas ISO válidas.' });
  }

  if (new Date(from).getTime() > new Date(to).getTime()) {
    return res.status(400).json({ error: 'from não pode ser maior que to.' });
  }

  res.json(await parkingService.getTurnoverReport(req.normalizedSectorId, from, to));
}));

router.get('/incidents', asyncHandler(async (req, res) => {
  const status = req.query.status ? String(req.query.status).toLowerCase() : undefined;
  const sectorId = req.query.sectorId ? normalizeSector(req.query.sectorId) : undefined;

  if (status && !VALID_INCIDENT_STATUS.has(status)) {
    return res.status(400).json({ error: 'status inválido. Use open ou closed.' });
  }

  if (sectorId && !isValidSector(sectorId)) {
    return res.status(400).json({ error: 'sectorId inválido. Use A, B ou C.' });
  }

  res.json(await incidentService.getIncidents({ status, sectorId }));
}));

router.get('/recommendation', asyncHandler(async (req, res) => {
  const fromSector = normalizeSector(req.query.fromSector);
  if (!isValidSector(fromSector)) {
    return res.status(400).json({ error: 'fromSector é obrigatório e precisa ser A, B ou C.' });
  }

  res.json(await recommendationService.getRecommendation(fromSector));
}));

router.post('/admin/check-incidents', asyncHandler(async (_req, res) => {
  res.json(await incidentService.checkIncidents());
}));

module.exports = router;
