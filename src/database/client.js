const { Pool } = require('pg');
require('dotenv').config();

// Configuração do pool de conexão com o Postgres do Supabase
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: {
    rejectUnauthorized: false // Necessário para conexões seguras com Supabase
  }
});

module.exports = {
  // Função para executar as queries
  query: (text, params) => pool.query(text, params),
};