const fs = require('fs');
const path = require('path');

const requiredFiles = [
  'docker-compose.yml',
  'backend/database/init/001_schema.sql',
  'backend/database/init/002_seed_spots.sql',
  'src/index.js',
  'src/mqtt/subscriber.js',
  'src/services/gatewayService.js',
  'simulator/index.js',
  'mosquitto/mosquitto.conf',
  'README.md'
];

let ok = true;

function fail(message) {
  console.error(`ERR ${message}`);
  ok = false;
}

function pass(message) {
  console.log(`OK  ${message}`);
}

function read(file) {
  return fs.readFileSync(path.join(process.cwd(), file), 'utf8');
}

function assertIncludes(file, expected, label = expected) {
  const content = read(file);
  if (content.includes(expected)) {
    pass(`${file} contem ${label}`);
    return;
  }

  fail(`${file} nao contem ${label}`);
}

for (const file of requiredFiles) {
  const exists = fs.existsSync(path.join(process.cwd(), file));
  console.log(`${exists ? 'OK ' : 'ERR'} ${file}`);
  if (!exists) ok = false;
}

const requiredTables = [
  'spots',
  'spot_events',
  'sector_snapshots',
  'incidents',
  'recommendations_log'
];

for (const table of requiredTables) {
  assertIncludes('backend/database/init/001_schema.sql', `CREATE TABLE IF NOT EXISTS ${table}`, `tabela ${table}`);
}

assertIncludes('backend/database/init/001_schema.sql', 'CREATE OR REPLACE FUNCTION apply_spot_event', 'funcao apply_spot_event');
assertIncludes('backend/database/init/001_schema.sql', 'ON CONFLICT (event_id) DO NOTHING', 'idempotencia por event_id');
assertIncludes('backend/database/init/001_schema.sql', 'CREATE OR REPLACE FUNCTION log_recommendation', 'log de recomendacao');

assertIncludes('backend/database/init/002_seed_spots.sql', "unnest(ARRAY['A', 'B', 'C'])", 'seed setores A/B/C');
assertIncludes('backend/database/init/002_seed_spots.sql', 'generate_series(1, 30)', 'seed 30 vagas por setor');

const requiredRoutes = [
  "router.get('/map'",
  "router.get('/sectors'",
  "router.get('/sectors/:sectorId/spots'",
  "router.get('/sectors/:sectorId/free-spots'",
  "router.get('/reports/turnover'",
  "router.get('/incidents'",
  "router.get('/recommendation'"
];

for (const route of requiredRoutes) {
  assertIncludes('src/http/routes.js', route, `rota ${route}`);
}

assertIncludes('src/mqtt/subscriber.js', 'campus/parking/sectors/+/spots/+/events', 'topico MQTT eventos');
assertIncludes('src/mqtt/subscriber.js', 'campus/parking/sectors/+/gateway/status', 'topico MQTT gateway');

for (const faultType of ['stuck_occupied', 'stuck_free', 'flapping']) {
  assertIncludes('simulator/index.js', faultType, `falha ${faultType}`);
}

assertIncludes('simulator/index.js', "app.post('/sim/faults'", 'endpoint injecao de falhas');
assertIncludes('simulator/index.js', "app.post('/sim/fill-sector/:sectorId'", 'endpoint lotar setor');

process.exit(ok ? 0 : 1);
