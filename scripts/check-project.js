const fs = require('fs');
const path = require('path');

const requiredFiles = [
  'docker-compose.yml',
  'backend/database/init/001_schema.sql',
  'backend/database/init/002_seed_spots.sql',
  'src/index.js',
  'src/mqtt/subscriber.js',
  'simulator/index.js',
  'mosquitto/mosquitto.conf',
  'README.md'
];

let ok = true;
for (const file of requiredFiles) {
  const exists = fs.existsSync(path.join(process.cwd(), file));
  console.log(`${exists ? 'OK ' : 'ERR'} ${file}`);
  if (!exists) ok = false;
}

process.exit(ok ? 0 : 1);
