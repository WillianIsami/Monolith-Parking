const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:3000';
const SIMULATOR_URL = process.env.SIMULATOR_URL || 'http://localhost:4000';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function requestJson(url, options) {
  const response = await fetch(url, {
    headers: { 'Content-Type': 'application/json', ...(options?.headers || {}) },
    ...options
  });
  const text = await response.text();
  const data = text ? JSON.parse(text) : null;

  if (!response.ok) {
    throw new Error(`${response.status} ${url}: ${text}`);
  }

  return data;
}

async function postJson(url, body) {
  return requestJson(url, {
    method: 'POST',
    body: JSON.stringify(body || {})
  });
}

async function forceIncidentCheck() {
  return postJson(`${BACKEND_URL}/api/v1/admin/check-incidents`);
}

async function waitForGateways(attempts = 12) {
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    const gateways = await requestJson(`${BACKEND_URL}/api/v1/gateways`);
    if (Array.isArray(gateways) && gateways.length === 3) return gateways;
    await sleep(1000);
  }

  throw new Error('/gateways nao retornou os 3 gateways');
}

async function waitForIncident(type, spotId, attempts = 12) {
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    await forceIncidentCheck();
    const incidents = await requestJson(`${BACKEND_URL}/api/v1/incidents?status=open`);
    const found = incidents.find((incident) => incident.type === type && incident.spotId === spotId);
    if (found) return found;
    await sleep(1000);
  }

  throw new Error(`Incidente ${type} para ${spotId} nao apareceu em /incidents`);
}

async function main() {
  console.log('[smoke] checando health do backend e simulador');
  const backendHealth = await requestJson(`${BACKEND_URL}/api/v1/health`);
  const simulatorHealth = await requestJson(`${SIMULATOR_URL}/health`);
  assert(backendHealth.status === 'ok', 'backend health nao retornou ok');
  assert(simulatorHealth.status === 'ok', 'simulador health nao retornou ok');

  console.log('[smoke] checando mapa e setores');
  const map = await requestJson(`${BACKEND_URL}/api/v1/map`);
  assert(Array.isArray(map.sectors) && map.sectors.length === 3, '/map deve retornar 3 setores');
  const totalSpots = map.sectors.reduce((sum, sector) => sum + sector.spots.length, 0);
  assert(totalSpots === 90, `/map deve retornar 90 vagas, retornou ${totalSpots}`);

  const sectors = await requestJson(`${BACKEND_URL}/api/v1/sectors`);
  assert(Array.isArray(sectors) && sectors.length === 3, '/sectors deve retornar 3 setores');
  for (const sector of sectors) {
    assert(
      sector.occupiedCount + sector.freeCount === 30,
      `setor ${sector.sectorId} deve somar 30 vagas`
    );
  }

  const sectorSpots = await requestJson(`${BACKEND_URL}/api/v1/sectors/A/spots`);
  assert(sectorSpots.sectorId === 'A', '/sectors/A/spots deve responder setor A');
  assert(Array.isArray(sectorSpots.spots) && sectorSpots.spots.length === 30, 'setor A deve ter 30 vagas');

  const freeSpots = await requestJson(`${BACKEND_URL}/api/v1/sectors/A/free-spots?limit=10`);
  assert(freeSpots.sectorId === 'A', '/sectors/A/free-spots deve responder setor A');
  assert(Array.isArray(freeSpots.freeSpots), '/free-spots deve retornar lista de vagas');

  const gateways = await waitForGateways();
  for (const gateway of gateways) {
    assert(gateway.status === 'ONLINE', `gateway ${gateway.sectorId} deve estar ONLINE`);
  }

  const turnover = await requestJson(
    `${BACKEND_URL}/api/v1/reports/turnover?sectorId=A&from=2020-01-01T00:00:00.000Z&to=2100-01-01T00:00:00.000Z`
  );
  assert(turnover.sectorId === 'A', 'relatorio de turnover deve responder setor A');
  assert(Number.isFinite(turnover.turnover), 'relatorio de turnover deve retornar total numerico');

  console.log('[smoke] validando injecao de flapping');
  await postJson(`${SIMULATOR_URL}/sim/faults`, {
    sectorId: 'A',
    spotId: 'A-07',
    type: 'flapping'
  });
  await waitForIncident('FLAPPING', 'A-07');

  console.log('[smoke] validando sensor travado ocupado');
  await postJson(`${SIMULATOR_URL}/sim/faults`, {
    sectorId: 'A',
    spotId: 'A-08',
    type: 'stuck_occupied',
    ageMinutes: 400
  });
  await waitForIncident('STUCK_OCCUPIED', 'A-08');

  console.log('[smoke] validando recomendacao por setor >= 90%');
  await postJson(`${SIMULATOR_URL}/sim/fill-sector/A`, { occupiedCount: 28 });
  await sleep(3000);
  const recommendation = await requestJson(`${BACKEND_URL}/api/v1/recommendation?fromSector=A`);
  assert(recommendation.fromSector === 'A', 'recomendacao deve responder fromSector A');
  assert(recommendation.recommendedSector, 'recomendacao deve indicar um setor alternativo');

  console.log('[smoke] OK e2e: MQTT, HTTP, banco, incidentes e recomendacao funcionaram');
}

main().catch((error) => {
  console.error('[smoke] falha e2e');
  console.error(error.message);
  process.exitCode = 1;
});
