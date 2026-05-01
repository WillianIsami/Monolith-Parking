const express = require('express');
const cors = require('cors');
const apiRoutes = require('./api');
const { checkIncidents } = require('./service');

const app = express();
const PORT = process.env.PORT || 3000;

// Middlewares
app.use(cors());
app.use(express.json());

// Rota base para o grupo de APIs
app.use('/api/v1', apiRoutes);

// Loop de background para incidentes
setInterval(() => {
  checkIncidents().catch(err => console.error("Erro no background check:", err));
}, 30 * 1000);

app.listen(PORT, () => {
  console.log(`🚀 API do Estacionamento Inteligente rodando na porta ${PORT}`);
  console.log(`🔍 Verificação de incidentes ativada (a cada 30s)`);
});