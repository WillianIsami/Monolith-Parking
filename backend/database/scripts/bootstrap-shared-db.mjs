import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import dotenv from 'dotenv';
import pg from 'pg';

const { Client } = pg;

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const databaseRoot = path.resolve(__dirname, '..');
const initDir = path.join(databaseRoot, 'init');

dotenv.config({ path: path.join(databaseRoot, '.env') });

async function main() {
  const connectionString = process.env.DATABASE_ADMIN_URL || process.env.DATABASE_URL;

  if (!connectionString) {
    throw new Error('DATABASE_ADMIN_URL ou DATABASE_URL nao definido. Configure no .env ou no ambiente.');
  }

  const sslMode = process.env.PGSSLMODE;
  const client = new Client({
    connectionString,
    ssl: sslMode === 'require' ? { rejectUnauthorized: false } : undefined
  });

  await client.connect();
  console.log('[bootstrap] conectado ao banco');

  try {
    const sqlFiles = (await fs.readdir(initDir))
      .filter((fileName) => fileName.endsWith('.sql'))
      .sort();

    if (sqlFiles.length === 0) {
      throw new Error(`Nenhum arquivo .sql encontrado em ${initDir}`);
    }

    for (const fileName of sqlFiles) {
      const filePath = path.join(initDir, fileName);
      const sql = await fs.readFile(filePath, 'utf8');
      console.log(`[bootstrap] aplicando ${fileName}`);
      await client.query(sql);
    }
    console.log('[bootstrap] schema e seeds aplicados com sucesso');
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  console.error('[bootstrap] falha ao inicializar o banco');
  console.error(error.message);
  process.exitCode = 1;
});
