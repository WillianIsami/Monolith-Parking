# Banco de dados

Modulo responsavel pela persistencia do MVP de Estacionamento Inteligente Campus.

## Decisao tecnica

Banco escolhido: PostgreSQL.

Motivos:

- `jsonb` para payloads MQTT, evidencias de incidentes e contexto de recomendacao;
- boa compatibilidade com Docker Compose e banco compartilhado;
- constraints e funcoes SQL simples para garantir idempotencia e integridade;
- sem ORM, mantendo o contrato SQL facil de demonstrar.

## Estrutura

```txt
backend/database/
  docker-compose.yml
  package.json
  init/
    001_schema.sql
    002_seed_spots.sql
  queries/
    api_queries.sql
    integration_examples.sql
    exemplos_ptbr.sql
    advanced_dashboard_queries.sql
    dashboard_gamificado.sql
  scripts/
    bootstrap-shared-db.mjs
    setup-shared-access.mjs
    check-db-health.mjs
    check-db-requirements.mjs
    check-shared-access.mjs
  examples/
    node-pg-client.mjs
```

## Tabelas

| Tabela | Finalidade |
| --- | --- |
| `sectors` | Setores fixos A, B e C, capacidade e threshold operacional |
| `spots` | Estado atual de cada vaga |
| `spot_events` | Historico bruto dos eventos de vaga recebidos via MQTT |
| `gateway_status_events` | Historico de saude dos gateways recebido via MQTT |
| `sector_snapshots` | Ocupacao agregada por setor e minuto |
| `incidents` | Incidentes operacionais e evidencias |
| `recommendations_log` | Historico de recomendacoes emitidas |

## Funcoes e views

| Objeto | Uso |
| --- | --- |
| `apply_spot_event(...)` | Persiste evento MQTT, garante idempotencia por `event_id` e atualiza `spots` |
| `record_gateway_status(...)` | Persiste heartbeat/status dos gateways |
| `get_sector_occupancy(...)` | Retorna ocupacao atual por setor |
| `get_free_spots(...)` | Lista vagas livres por setor |
| `get_turnover_report(...)` | Calcula transicoes `FREE -> OCCUPIED` |
| `get_incidents(...)` | Lista incidentes filtrando por status e setor |
| `open_incident(...)` | Abre incidente sem duplicar incidente aberto equivalente |
| `close_incident(...)` | Fecha incidente |
| `log_recommendation(...)` | Registra recomendacao operacional |
| `v_current_map` | Mapa atual das vagas |
| `v_sector_summary_current` | Resumo atual de ocupacao |
| `v_gateway_current_status` | Ultimo status conhecido de cada gateway |

## Execucao local

```powershell
cd backend/database
Copy-Item .env.example .env
npm install
docker compose up -d
npm run check:requirements
npm run check:db
```

Adminer local:

```powershell
docker compose --profile admin up -d
```

## Banco compartilhado

1. Criar um PostgreSQL remoto.
2. Copiar `.env.shared.example` ou `.env.supabase.example` para `.env`.
3. Ajustar `DATABASE_URL`, `DATABASE_ADMIN_URL` e `PGSSLMODE`.
4. Aplicar schema e seed.

```powershell
npm run bootstrap:shared
npm run setup:shared-access
npm run check:requirements
npm run check:db
npm run check:shared-access
```

Senhas e URLs reais nao devem ser commitadas.
