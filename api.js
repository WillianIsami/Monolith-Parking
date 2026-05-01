const express = require('express');
const db = require('./db');
const { getRecommendation } = require('./service');

const router = express.Router();

// GET /api/v1/map
router.get('/map', async (req, res) => {
  try {
    const { rows: spots } = await db.query('SELECT spot_id, sector_id, current_state, last_change_ts FROM spots');
    
    const map = spots.reduce((acc, spot) => {
      if (!acc[spot.sector_id]) acc[spot.sector_id] = [];
      acc[spot.sector_id].push({
        spotId: spot.spot_id, // Traduzindo para o JSON do cliente
        state: spot.current_state,
        lastChange: spot.last_change_ts
      });
      return acc;
    }, {});
    
    res.json({ data: map });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Erro ao buscar o mapa' });
  }
});

// GET /api/v1/sectors
router.get('/sectors', async (req, res) => {
  try {
    const { rows: spots } = await db.query('SELECT sector_id, current_state FROM spots');
    const sectorData = {};

    spots.forEach(spot => {
      if (!sectorData[spot.sector_id]) {
        sectorData[spot.sector_id] = { sectorId: spot.sector_id, total: 0, free: 0, occupied: 0 };
      }
      sectorData[spot.sector_id].total++;
      if (spot.current_state === 'FREE') sectorData[spot.sector_id].free++;
      if (spot.current_state === 'OCCUPIED') sectorData[spot.sector_id].occupied++;
    });

    const response = Object.values(sectorData).map(sector => ({
      sectorId: sector.sectorId,
      occupiedCount: sector.occupied,
      freeCount: sector.free,
      occupancyRate: sector.occupied / sector.total,
      lastUpdateTs: new Date().toISOString()
    }));

    res.json({ data: response });
  } catch (error) {
    res.status(500).json({ error: 'Erro ao buscar os setores' });
  }
});

// GET /api/v1/sectors/:sectorId/spots
router.get('/sectors/:sectorId/spots', async (req, res) => {
  try {
    const { rows: spots } = await db.query('SELECT * FROM spots WHERE sector_id = $1', [req.params.sectorId]);
    // Formatando a resposta para camelCase
    const formattedSpots = spots.map(s => ({
      spotId: s.spot_id,
      sectorId: s.sector_id,
      currentState: s.current_state,
      lastChangeTs: s.last_change_ts
    }));
    res.json({ data: formattedSpots });
  } catch (error) {
    res.status(500).json({ error: 'Erro ao buscar vagas do setor' });
  }
});

// GET /api/v1/sectors/:sectorId/free-spots?limit=10
router.get('/sectors/:sectorId/free-spots', async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 10;
    const { rows: spots } = await db.query(`
      SELECT * FROM spots 
      WHERE sector_id = $1 AND current_state = 'FREE' 
      LIMIT $2
    `, [req.params.sectorId, limit]);
    
    const formattedSpots = spots.map(s => ({
      spotId: s.spot_id,
      sectorId: s.sector_id,
      currentState: s.current_state,
      lastChangeTs: s.last_change_ts
    }));
    
    res.json({ data: formattedSpots });
  } catch (error) {
    res.status(500).json({ error: 'Erro ao buscar vagas livres' });
  }
});

// GET /api/v1/reports/turnover?sectorId=A&from=...&to=...
router.get('/reports/turnover', async (req, res) => {
  try {
    const { sectorId, from, to } = req.query;
    if (!sectorId || !from || !to) {
      return res.status(400).json({ error: 'sectorId, from e to são obrigatórios' });
    }

    const { rows } = await db.query(`
      SELECT COUNT(*) as turnover 
      FROM spot_events 
      WHERE sector_id = $1 AND state = 'OCCUPIED' AND ts BETWEEN $2 AND $3
    `, [sectorId, from, to]);

    res.json({ sectorId, from, to, turnover: parseInt(rows[0].turnover) });
  } catch (error) {
    res.status(500).json({ error: 'Erro ao gerar relatório' });
  }
});

// GET /api/v1/incidents?status=open
router.get('/incidents', async (req, res) => {
  try {
    const status = req.query.status || 'OPEN';
    const { rows: incidents } = await db.query('SELECT * FROM incidents WHERE status = UPPER($1)', [status]);
    
    const formattedIncidents = incidents.map(i => ({
      id: i.id,
      type: i.type,
      severity: i.severity,
      status: i.status,
      spotId: i.spot_id,
      sectorId: i.sector_id,
      tsOpen: i.ts_open,
      tsClose: i.ts_close,
      evidenceJson: i.evidence_json
    }));

    res.json({ data: formattedIncidents });
  } catch (error) {
    res.status(500).json({ error: 'Erro ao buscar incidentes' });
  }
});

// GET /api/v1/recommendation?fromSector=A
router.get('/recommendation', async (req, res) => {
  try {
    if (!req.query.fromSector) {
      return res.status(400).json({ error: 'fromSector é obrigatório' });
    }
    const result = await getRecommendation(req.query.fromSector);
    if (result.error) return res.status(400).json(result);
    
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: 'Erro ao gerar recomendação' });
  }
});

module.exports = router;