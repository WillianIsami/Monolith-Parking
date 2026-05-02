const db = require('./db');
const crypto = require('crypto'); // Módulo nativo do Node para gerar UUIDs

async function getRecommendation(fromSectorId) {
  // 1. Calcular a taxa de ocupação do setor
  const { rows: spots } = await db.query('SELECT current_state FROM spots WHERE sector_id = $1', [fromSectorId]);
  
  if (spots.length === 0) return { error: 'Setor não encontrado ou vazio' };

  const occupiedCount = spots.filter(s => s.current_state === 'OCCUPIED').length;
  const occupancyRate = occupiedCount / spots.length;

  if (occupancyRate < 0.90) {
    return { message: `Setor ${fromSectorId} ainda tem vagas. Ocupação: ${(occupancyRate * 100).toFixed(1)}%` };
  }

  // 2. Procurar o melhor setor alternativo
  const { rows: allSpots } = await db.query('SELECT sector_id, current_state FROM spots WHERE sector_id != $1', [fromSectorId]);
  const sectorStats = {};

  allSpots.forEach(spot => {
    if (!sectorStats[spot.sector_id]) {
      sectorStats[spot.sector_id] = { total: 0, free: 0 };
    }
    sectorStats[spot.sector_id].total++;
    if (spot.current_state === 'FREE') sectorStats[spot.sector_id].free++;
  });

  let bestSector = null;
  let maxFree = -1;

  for (const [sectorId, stats] of Object.entries(sectorStats)) {
    if (stats.free > maxFree) {
      maxFree = stats.free;
      bestSector = sectorId;
    }
  }

  if (!bestSector || maxFree === 0) {
    return { error: 'Todos os outros setores também estão lotados.' };
  }

  const reason = `Sector ${fromSectorId} at ${(occupancyRate * 100).toFixed(1)}% occupancy; Sector ${bestSector} has ${maxFree} free spots`;
  const ts = new Date().toISOString();

  // 3. Registrar no banco (recommendations_log)
  await db.query(`
    INSERT INTO recommendations_log (ts, from_sector, recommended_sector, reason) 
    VALUES ($1, $2, $3, $4)
  `, [ts, fromSectorId, bestSector, reason]);

  // Retorna no formato exigido pela sua tarefa
  return {
    fromSector: fromSectorId,
    recommendedSector: bestSector,
    reason: reason,
    ts: ts
  };
}

async function checkIncidents() {
  const now = new Date();
  const nowStr = now.toISOString();
  
  const MS_PER_MINUTE = 60000;
  const TIME_STUCK_OCCUPIED = 6 * 60 * MS_PER_MINUTE; // 6 horas
  const TIME_STUCK_FREE = 12 * 60 * MS_PER_MINUTE;    // 12 horas
  const FLAPPING_WINDOW = 1 * MS_PER_MINUTE;          // 1 minuto
  const FLAPPING_THRESHOLD = 5;                       // 5 trocas

  try {
    // 1. STUCK_OCCUPIED
    const stuckOccupiedLimit = new Date(now.getTime() - TIME_STUCK_OCCUPIED).toISOString();
    const { rows: stuckOccupiedSpots } = await db.query(`
      SELECT spot_id, sector_id, last_change_ts FROM spots 
      WHERE current_state = 'OCCUPIED' AND last_change_ts < $1
    `, [stuckOccupiedLimit]);

    for (const spot of stuckOccupiedSpots) {
      await registrarIncidente(spot, 'STUCK_OCCUPIED', 'HIGH', nowStr, { timeStuck: spot.last_change_ts });
    }

    // 2. STUCK_FREE
    const stuckFreeLimit = new Date(now.getTime() - TIME_STUCK_FREE).toISOString();
    const { rows: stuckFreeSpots } = await db.query(`
      SELECT spot_id, sector_id, last_change_ts FROM spots 
      WHERE current_state = 'FREE' AND last_change_ts < $1
    `, [stuckFreeLimit]);

    for (const spot of stuckFreeSpots) {
      await registrarIncidente(spot, 'STUCK_FREE', 'MEDIUM', nowStr, { timeStuck: spot.last_change_ts });
    }

    // 3. FLAPPING
    const flappingTimeLimit = new Date(now.getTime() - FLAPPING_WINDOW).toISOString();
    const { rows: recentEvents } = await db.query(`
      SELECT spot_id, sector_id, COUNT(*) as changes 
      FROM spot_events 
      WHERE ts >= $1 
      GROUP BY spot_id, sector_id
      HAVING COUNT(*) >= $2
    `, [flappingTimeLimit, FLAPPING_THRESHOLD]);

    for (const spot of recentEvents) {
      await registrarIncidente(spot, 'FLAPPING', 'HIGH', nowStr, { changes: spot.changes });
    }
  } catch (error) {
    console.error('Erro na verificação de incidentes:', error);
  }
}

async function registrarIncidente(spot, type, severity, ts, evidence) {
  // Verifica se já existe um incidente aberto deste tipo para esta vaga
  const { rows: existing } = await db.query(`
    SELECT id FROM incidents 
    WHERE spot_id = $1 AND type = $2 AND status = 'OPEN'
  `, [spot.spot_id, type]);

  if (existing.length === 0) {
    const incidenteId = crypto.randomUUID(); // Gera um UUID válido para a tabela
    await db.query(`
      INSERT INTO incidents (id, ts_open, type, severity, sector_id, spot_id, evidence_json, status)
      VALUES ($1, $2, $3, $4, $5, $6, $7, 'OPEN')
    `, [incidenteId, ts, type, severity, spot.sector_id, spot.spot_id, JSON.stringify(evidence)]);
    console.log(`⚠️ Incidente detectado: ${type} na vaga ${spot.spot_id}`);
  }
}

module.exports = {
  getRecommendation,
  checkIncidents
};