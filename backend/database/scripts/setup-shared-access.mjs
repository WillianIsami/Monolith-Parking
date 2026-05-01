import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import dotenv from 'dotenv';
import pg from 'pg';

const { Client } = pg;

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const databaseRoot = path.resolve(__dirname, '..');

dotenv.config({ path: path.join(databaseRoot, '.env') });

function quoteIdentifier(value) {
  if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(value)) {
    throw new Error(`Identificador invalido para role: ${value}`);
  }

  return `"${value.replaceAll('"', '""')}"`;
}

function quoteLiteral(value) {
  return `'${value.replaceAll("'", "''")}'`;
}

function readRequiredEnv(name) {
  const value = process.env[name];

  if (!value || value.includes('change-me')) {
    throw new Error(`${name} nao definido. Configure no .env local antes de rodar este script.`);
  }

  return value;
}

async function ensureLoginRole(client, roleName, password) {
  const { rowCount } = await client.query(
    'SELECT 1 FROM pg_roles WHERE rolname = $1',
    [roleName]
  );

  if (rowCount === 0) {
    await client.query(
      `CREATE ROLE ${quoteIdentifier(roleName)} LOGIN PASSWORD ${quoteLiteral(password)}`
    );
    console.log(`[access] role criada: ${roleName}`);
    return;
  }

  await client.query(
    `ALTER ROLE ${quoteIdentifier(roleName)} WITH LOGIN PASSWORD ${quoteLiteral(password)}`
  );
  console.log(`[access] senha atualizada: ${roleName}`);
}

async function grantAccess(client, databaseName, writerRole, readerRole) {
  const writer = quoteIdentifier(writerRole);
  const reader = quoteIdentifier(readerRole);
  const database = quoteIdentifier(databaseName);

  await client.query(`GRANT CONNECT ON DATABASE ${database} TO ${writer}, ${reader}`);
  await client.query(`GRANT USAGE ON SCHEMA public TO ${writer}, ${reader}`);

  await client.query(`GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${writer}`);
  await client.query(`GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO ${writer}`);
  await client.query(`GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO ${writer}`);

  await client.query(`GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${reader}`);
  await client.query(`GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${reader}`);
  await client.query(`GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO ${reader}`);

  await client.query(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${writer}`);
  await client.query(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO ${writer}`);
  await client.query(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO ${writer}`);

  await client.query(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ${reader}`);
  await client.query(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO ${reader}`);
  await client.query(`ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO ${reader}`);
}

async function main() {
  const connectionString = readRequiredEnv('DATABASE_ADMIN_URL');
  const writerRole = process.env.DATABASE_WRITER_USER || 'parking_writer';
  const readerRole = process.env.DATABASE_READER_USER || 'parking_reader';
  const writerPassword = readRequiredEnv('DATABASE_WRITER_PASSWORD');
  const readerPassword = readRequiredEnv('DATABASE_READER_PASSWORD');
  const sslMode = process.env.PGSSLMODE;

  const client = new Client({
    connectionString,
    ssl: sslMode === 'require' ? { rejectUnauthorized: false } : undefined
  });

  await client.connect();

  try {
    const { rows } = await client.query('SELECT current_database() AS database_name');
    const databaseName = rows[0].database_name;

    await ensureLoginRole(client, writerRole, writerPassword);
    await ensureLoginRole(client, readerRole, readerPassword);
    await grantAccess(client, databaseName, writerRole, readerRole);

    console.log('[access] permissoes compartilhadas configuradas');
    console.log(`[access] writer: ${writerRole}`);
    console.log(`[access] reader: ${readerRole}`);
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  console.error('[access] falha ao configurar acesso compartilhado');
  console.error(error.message);
  process.exitCode = 1;
});
