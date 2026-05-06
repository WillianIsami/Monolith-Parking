require('dotenv').config();

const express = require('express');
const mqtt = require('mqtt');
const crypto = require('crypto');

const PORT = Number(process.env.SIMULATOR_PORT || 4000);
const MQTT_BROKER_URL = process.env.MQTT_BROKER_URL || 'mqtt://localhost:1883';
const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:3000';
const SIMULATED_MINUTE_MS = Number(process.env.SIMULATED_MINUTE_MS || 1000);
const SIMULATOR_TICK_MS = Number(process.env.SIMULATOR_TICK_MS || SIMULATED_MINUTE_MS);
const GATEWAY_STATUS_INTERVAL_MS = Number(process.env.GATEWAY_STATUS_INTERVAL_MS || 15000);
const STARTUP_SYNC_RETRIES = Number(process.env.SIMULATOR_STARTUP_SYNC_RETRIES || 30);
const STARTUP_SYNC_DELAY_MS = Number(process.env.SIMULATOR_STARTUP_SYNC_DELAY_MS || 1000);
const MANUAL_SYNC_RETRIES = Number(process.env.SIMULATOR_MANUAL_SYNC_RETRIES || 3);
const MANUAL_SYNC_DELAY_MS = Number(process.env.SIMULATOR_MANUAL_SYNC_DELAY_MS || 300);

const SECTORS = ['A', 'B', 'C'];
const STATES = ['FREE', 'OCCUPIED'];
const FAULT_TYPES = new Set(['stuck_occupied', 'stuck_free', 'flapping']);

const app = express();
app.use(express.json());

const mqttClient = mqtt.connect(MQTT_BROKER_URL, {
  reconnectPeriod: 2000,
  clean: true,
  clientId: `parking-simulator-${Math.random().toString(16).slice(2)}`
});

let simulatedClock = new Date();
let lastBackendSyncTs = null;
const spots = new Map();
const faults = new Map();

function formatSpotId(sectorId, spotNumber) {
  return `${sectorId}-${String(spotNumber).padStart(2, '0')}`;
}

function createInitialSpots() {
  for (const sectorId of SECTORS) {
    for (let number = 1; number <= 30; number += 1) {
      const spotId = formatSpotId(sectorId, number);
      spots.set(spotId, {
        sectorId,
        spotId,
        state: 'FREE',
        occupiedUntil: null,
        lastChangeTs: null
      });
    }
  }
}

function eventTopic(sectorId, spotId) {
  return `campus/parking/sectors/${sectorId}/spots/${spotId}/events`;
}

function gatewayStatusTopic(sectorId) {
  return `campus/parking/sectors/${sectorId}/gateway/status`;
}

function publishJson(topic, payload, options = {}) {
  mqttClient.publish(topic, JSON.stringify(payload), { qos: 1, ...options }, (error) => {
    if (error) console.error(`[SIM] Falha ao publicar em ${topic}:`, error.message);
  });
}

function publishGatewayStatus(status = 'ONLINE') {
  for (const sectorId of SECTORS) {
    publishJson(gatewayStatusTopic(sectorId), {
      ts: simulatedClock.toISOString(),
      sectorId,
      gatewayId: `gateway-${sectorId}`,
      status,
      source: 'gateway'
    }, { retain: true });
  }
}

function publishSpotEvent(spot, state, ts = simulatedClock) {
  const normalizedState = String(state).toUpperCase();
  if (!STATES.includes(normalizedState)) return;

  spot.state = normalizedState;
  spot.lastChangeTs = ts.toISOString();

  const payload = {
    eventId: crypto.randomUUID(),
    ts: ts.toISOString(),
    sectorId: spot.sectorId,
    spotId: spot.spotId,
    state: normalizedState,
    source: 'gateway'
  };

  publishJson(eventTopic(spot.sectorId, spot.spotId), payload);
  console.log(`[SIM] ${spot.spotId} -> ${normalizedState} (${payload.ts})`);
}

function getArrivalProbability(hour) {
  if (hour >= 7 && hour <= 9) return 0.055;
  if (hour >= 10 && hour <= 15) return 0.020;
  if (hour >= 16 && hour <= 18) return 0.035;
  return 0.008;
}

function randomStayMinutes() {
  return 30 + Math.floor(Math.random() * (360 - 30 + 1));
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function asyncHandler(handler) {
  return (req, res, next) => {
    Promise.resolve(handler(req, res, next)).catch(next);
  };
}

async function requestBackendMap() {
  const response = await fetch(`${BACKEND_URL}/api/v1/map`);
  if (!response.ok) {
    throw new Error(`backend respondeu ${response.status}`);
  }

  return response.json();
}

function readBackendSnapshot(map) {
  const backendSpots = [];
  let maxLastChangeTs = null;

  for (const sector of map?.sectors || []) {
    for (const spot of sector.spots || []) {
      const spotId = String(spot.spotId || '').trim().toUpperCase();
      const sectorId = String(spot.sectorId || '').trim().toUpperCase();
      const state = String(spot.state || '').trim().toUpperCase();

      if (!spots.has(spotId) || !SECTORS.includes(sectorId) || !STATES.includes(state)) continue;

      const parsedTs = spot.lastChangeTs ? new Date(spot.lastChangeTs) : null;
      const lastChangeTs = parsedTs && !Number.isNaN(parsedTs.getTime()) ? parsedTs : null;

      if (lastChangeTs && (!maxLastChangeTs || lastChangeTs > maxLastChangeTs)) {
        maxLastChangeTs = lastChangeTs;
      }

      backendSpots.push({ spotId, sectorId, state, lastChangeTs });
    }
  }

  return { backendSpots, maxLastChangeTs };
}

function advanceClockAfter(maxLastChangeTs) {
  if (!maxLastChangeTs) return false;

  const nextClock = new Date(maxLastChangeTs.getTime() + 60_000);
  if (nextClock > simulatedClock) {
    simulatedClock = nextClock;
    return true;
  }

  return false;
}

function hydrateSpotsFromBackend(backendSpots) {
  for (const backendSpot of backendSpots) {
    const spot = spots.get(backendSpot.spotId);
    if (!spot) continue;

    spot.sectorId = backendSpot.sectorId;
    spot.state = backendSpot.state;
    spot.lastChangeTs = backendSpot.lastChangeTs ? backendSpot.lastChangeTs.toISOString() : null;
    spot.occupiedUntil = backendSpot.state === 'OCCUPIED'
      ? new Date(simulatedClock.getTime() + randomStayMinutes() * 60_000)
      : null;
  }
}

async function syncWithBackend({ attempts, delayMs, hydrateSpots = false, reason = 'sincronizacao' }) {
  let lastError;

  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      const map = await requestBackendMap();
      const { backendSpots, maxLastChangeTs } = readBackendSnapshot(map);
      const clockAdvanced = advanceClockAfter(maxLastChangeTs);

      if (hydrateSpots) {
        hydrateSpotsFromBackend(backendSpots);
      }

      lastBackendSyncTs = new Date().toISOString();

      const maxTsLabel = maxLastChangeTs ? maxLastChangeTs.toISOString() : 'sem eventos';
      const clockLabel = clockAdvanced ? 'relogio avancado' : 'relogio mantido';
      console.log(`[SIM] Backend sincronizado (${reason}): ${backendSpots.length} vagas, max=${maxTsLabel}, ${clockLabel} para ${simulatedClock.toISOString()}`);
      return true;
    } catch (error) {
      lastError = error;
      if (attempt < attempts) await sleep(delayMs);
    }
  }

  console.warn(`[SIM] Nao foi possivel sincronizar com ${BACKEND_URL} (${reason}): ${lastError?.message || 'erro desconhecido'}`);
  return false;
}

function tickNormalSpot(spot) {
  const fault = faults.get(spot.spotId);
  if (fault?.type === 'stuck_occupied') {
    if (spot.state !== 'OCCUPIED') publishSpotEvent(spot, 'OCCUPIED');
    return;
  }

  if (fault?.type === 'stuck_free') {
    if (spot.state !== 'FREE') publishSpotEvent(spot, 'FREE');
    return;
  }

  if (fault?.type === 'flapping') {
    return;
  }

  const hour = simulatedClock.getHours();

  if (spot.state === 'OCCUPIED') {
    const shouldLeaveByStay = spot.occupiedUntil && simulatedClock >= spot.occupiedUntil;
    if (shouldLeaveByStay) {
      spot.occupiedUntil = null;
      publishSpotEvent(spot, 'FREE');
    }
    return;
  }

  if (Math.random() < getArrivalProbability(hour)) {
    const stay = randomStayMinutes();
    spot.occupiedUntil = new Date(simulatedClock.getTime() + stay * 60_000);
    publishSpotEvent(spot, 'OCCUPIED');
  }
}

function tickSimulation() {
  simulatedClock = new Date(simulatedClock.getTime() + 60_000);
  for (const spot of spots.values()) tickNormalSpot(spot);
}

function validateSpot(sectorId, spotId) {
  const normalizedSector = String(sectorId || '').trim().toUpperCase();
  const normalizedSpot = String(spotId || '').trim().toUpperCase();
  const spot = spots.get(normalizedSpot);

  if (!SECTORS.includes(normalizedSector) || !spot || spot.sectorId !== normalizedSector) {
    const error = new Error('sectorId/spotId inválidos. Use exemplos como A e A-07.');
    error.statusCode = 400;
    throw error;
  }

  return spot;
}

function startFlapping(spot) {
  const fault = faults.get(spot.spotId);
  if (fault?.interval) clearInterval(fault.interval);

  let toggles = 0;
  const maxToggles = 8;
  const baseTs = new Date(simulatedClock.getTime());
  const interval = setInterval(() => {
    const nextState = spot.state === 'FREE' ? 'OCCUPIED' : 'FREE';
    const eventTs = new Date(baseTs.getTime() + toggles * 5000);
    publishSpotEvent(spot, nextState, eventTs);
    toggles += 1;

    if (toggles >= maxToggles) {
      clearInterval(interval);
      const currentFault = faults.get(spot.spotId);
      if (currentFault?.interval === interval) {
        faults.set(spot.spotId, { type: 'flapping' });
      }
    }
  }, 300);

  faults.set(spot.spotId, { type: 'flapping', interval });
}

function injectFault({ sectorId, spotId, type, ageMinutes }) {
  if (!FAULT_TYPES.has(type)) {
    const error = new Error('type inválido. Use stuck_occupied, stuck_free ou flapping.');
    error.statusCode = 400;
    throw error;
  }

  const spot = validateSpot(sectorId, spotId);
  const previous = faults.get(spot.spotId);
  if (previous?.interval) clearInterval(previous.interval);

  const requestedAgeMinutes = Number(ageMinutes);
  if (Number.isFinite(requestedAgeMinutes) && requestedAgeMinutes > 0 && spot.lastChangeTs) {
    const minClockForAge = new Date(new Date(spot.lastChangeTs).getTime() + requestedAgeMinutes * 60_000 + 1000);
    if (simulatedClock < minClockForAge) simulatedClock = minClockForAge;
  }

  const backdatedTs = Number.isFinite(requestedAgeMinutes) && requestedAgeMinutes > 0
    ? new Date(simulatedClock.getTime() - requestedAgeMinutes * 60_000)
    : simulatedClock;

  if (type === 'stuck_occupied') {
    faults.set(spot.spotId, { type });
    publishSpotEvent(spot, 'OCCUPIED', backdatedTs);
  }

  if (type === 'stuck_free') {
    faults.set(spot.spotId, { type });
    publishSpotEvent(spot, 'FREE', backdatedTs);
  }

  if (type === 'flapping') {
    startFlapping(spot);
  }

  publishGatewayStatus('ONLINE');

  return {
    sectorId: spot.sectorId,
    spotId: spot.spotId,
    type,
    ageMinutes: requestedAgeMinutes > 0 ? requestedAgeMinutes : 0,
    ts: simulatedClock.toISOString()
  };
}

function clearFault(spotId) {
  const normalizedSpot = String(spotId || '').trim().toUpperCase();
  const fault = faults.get(normalizedSpot);
  if (fault?.interval) clearInterval(fault.interval);
  faults.delete(normalizedSpot);
  return normalizedSpot;
}

function fillSector(sectorId, occupiedCount = 27) {
  const normalizedSector = String(sectorId || '').trim().toUpperCase();
  if (!SECTORS.includes(normalizedSector)) {
    const error = new Error('sectorId inválido. Use A, B ou C.');
    error.statusCode = 400;
    throw error;
  }

  const target = Math.max(0, Math.min(30, Number(occupiedCount) || 27));
  const sectorSpots = Array.from(spots.values()).filter((spot) => spot.sectorId === normalizedSector);

  sectorSpots.forEach((spot, index) => {
    const nextState = index < target ? 'OCCUPIED' : 'FREE';
    if (spot.state !== nextState) publishSpotEvent(spot, nextState);
  });

  return {
    sectorId: normalizedSector,
    occupiedCount: target,
    occupancyRate: target / 30,
    ts: simulatedClock.toISOString()
  };
}

function resetSimulation() {
  for (const spotId of Array.from(faults.keys())) clearFault(spotId);

  const wallClock = new Date();
  simulatedClock = wallClock > simulatedClock
    ? wallClock
    : new Date(simulatedClock.getTime() + 60_000);

  for (const spot of spots.values()) {
    spot.occupiedUntil = null;
    publishSpotEvent(spot, 'FREE');
  }
  publishGatewayStatus('ONLINE');
}

app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'parking-simulator',
    ts: simulatedClock.toISOString(),
    backendSyncTs: lastBackendSyncTs
  });
});

app.get('/sim/state', (_req, res) => {
  const summary = SECTORS.map((sectorId) => {
    const sectorSpots = Array.from(spots.values()).filter((spot) => spot.sectorId === sectorId);
    const occupiedCount = sectorSpots.filter((spot) => spot.state === 'OCCUPIED').length;
    return {
      sectorId,
      occupiedCount,
      freeCount: 30 - occupiedCount,
      occupancyRate: occupiedCount / 30
    };
  });

  res.json({
    simulatedClock: simulatedClock.toISOString(),
    simulatedMinuteMs: SIMULATED_MINUTE_MS,
    faults: Array.from(faults.entries()).map(([spotId, fault]) => ({ spotId, type: fault.type })),
    sectors: summary
  });
});

app.post('/sim/faults', asyncHandler(async (req, res) => {
  await syncWithBackend({
    attempts: MANUAL_SYNC_RETRIES,
    delayMs: MANUAL_SYNC_DELAY_MS,
    hydrateSpots: true,
    reason: 'fault'
  });

  res.status(201).json(injectFault(req.body || {}));
}));

app.delete('/sim/faults/:spotId', (req, res) => {
  const spotId = clearFault(req.params.spotId);
  res.json({ spotId, removed: true });
});

app.post('/sim/fill-sector/:sectorId', asyncHandler(async (req, res) => {
  await syncWithBackend({
    attempts: MANUAL_SYNC_RETRIES,
    delayMs: MANUAL_SYNC_DELAY_MS,
    hydrateSpots: true,
    reason: 'fill-sector'
  });

  res.json(fillSector(req.params.sectorId, req.body?.occupiedCount));
}));

app.post('/sim/reset', asyncHandler(async (_req, res) => {
  await syncWithBackend({
    attempts: MANUAL_SYNC_RETRIES,
    delayMs: MANUAL_SYNC_DELAY_MS,
    hydrateSpots: true,
    reason: 'reset'
  });

  resetSimulation();
  res.json({ reset: true, ts: simulatedClock.toISOString() });
}));

app.use((error, _req, res, _next) => {
  res.status(error.statusCode || 500).json({ error: error.message || 'Erro interno do simulador' });
});

mqttClient.on('connect', () => {
  console.log(`[SIM] Conectado ao broker MQTT em ${MQTT_BROKER_URL}`);
  publishGatewayStatus('ONLINE');
});

mqttClient.on('reconnect', () => console.log('[SIM] Reconectando ao broker MQTT...'));
mqttClient.on('error', (error) => console.error('[SIM] MQTT erro:', error.message));

async function startSimulator() {
  createInitialSpots();

  await syncWithBackend({
    attempts: STARTUP_SYNC_RETRIES,
    delayMs: STARTUP_SYNC_DELAY_MS,
    hydrateSpots: true,
    reason: 'startup'
  });

  publishGatewayStatus('ONLINE');

  setInterval(tickSimulation, SIMULATOR_TICK_MS);
  setInterval(() => publishGatewayStatus('ONLINE'), GATEWAY_STATUS_INTERVAL_MS);

  app.listen(PORT, () => {
    console.log(`[SIM] Simulador rodando na porta ${PORT}`);
    console.log(`[SIM] Tempo simulado: ${SIMULATED_MINUTE_MS}ms = 1 minuto simulado`);
  });
}

startSimulator().catch((error) => {
  console.error('[SIM] Falha ao iniciar simulador:', error.message);
  process.exit(1);
});
