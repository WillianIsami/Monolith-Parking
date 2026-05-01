# Banco de dados

Modulo responsavel pela persistencia do Monolith Parking.

## Decisao tecnica

Banco escolhido: PostgreSQL.

Motivos praticos:

- suporte nativo a `jsonb` para payloads MQTT, evidencias e contexto de recomendacao;
- boa concorrencia para ingestao MQTT, API e consultas;
- execucao local via Docker e compatibilidade com banco remoto compartilhado;
- schema SQL independente de ORM.

## Estrutura

```txt
backend/database/
  docker-compose.yml
  package.json
  .env.example
  .env.docker.example
  .env.shared.example
  .env.supabase.example
  init/
    001_schema.sql
    002_seed_spots.sql
    003_advanced_platform.sql
    004_seed_advanced.sql
    005_dashboard_navigation_gamification.sql
    006_seed_dashboard_gamification.sql
  queries/
    api_queries.sql
    integration_examples.sql
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

## Schema obrigatorio

| Tabela | Finalidade |
| --- | --- |
| `spots` | Estado atual de cada vaga |
| `spot_events` | Historico bruto dos eventos recebidos |
| `sector_snapshots` | Ocupacao agregada por setor e minuto |
| `incidents` | Incidentes operacionais e evidencias |
| `recommendations_log` | Historico de recomendacoes emitidas |

## Extensoes do modelo

| Area | Tabelas principais |
| --- | --- |
| Organizacao | `campuses`, `parking_facilities`, `sectors` |
| IoT | `gateways`, `sensors`, `gateway_status_events` |
| Operacao | `spot_sessions`, `maintenance_windows`, `operator_actions` |
| Recomendacao | `recommendation_policies`, `recommendation_candidates` |
| Previsao | `campus_events`, `sector_forecasts` |
| Mapa e navegacao | `map_nodes`, `map_edges`, `route_templates`, `navigation_requests` |
| Gamificacao | `app_users`, `achievement_catalog`, `user_achievements`, `engagement_events` |

## Funcoes de integracao

| Funcao | Uso |
| --- | --- |
| `apply_spot_event(...)` | Persiste evento MQTT, garante idempotencia e atualiza estado atual |
| `get_sector_occupancy(...)` | Retorna ocupacao atual por setor |
| `get_free_spots(...)` | Lista vagas livres por setor |
| `get_turnover_report(...)` | Calcula transicoes `FREE -> OCCUPIED` |
| `get_incidents(...)` | Lista incidentes filtrando por status e setor |
| `open_incident(...)` | Abre incidente sem duplicar incidente aberto equivalente |
| `close_incident(...)` | Fecha incidente |
| `log_recommendation(...)` | Registra recomendacao simples |
| `record_recommendation_decision(...)` | Registra recomendacao com politica e candidatos |
| `register_gateway_status_event(...)` | Registra status de gateway |
| `get_navigation_options(...)` | Retorna vagas livres com rota e pontuacao |

Wrappers em portugues existem para facilitar apresentacao e consultas manuais.

## Ambiente

| Contexto | Host | Arquivo base |
| --- | --- | --- |
| Scripts locais | `localhost:5432` | `.env.example` |
| Servicos no Docker Compose | `postgres:5432` | `.env.docker.example` |
| Banco remoto compartilhado | definido em `DATABASE_URL` | `.env.shared.example` |

Contrato completo: [CONTRATO_AMBIENTE.md](CONTRATO_AMBIENTE.md).

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
3. Ajustar `DATABASE_URL` e `PGSSLMODE`.
4. Aplicar schema e seeds.

```powershell
npm run bootstrap:shared
npm run setup:shared-access
npm run check:requirements
npm run check:db
npm run check:shared-access
```

Senhas e URLs reais nao devem ser commitadas.

## Consultas de apoio

- [queries/api_queries.sql](queries/api_queries.sql)
- [queries/integration_examples.sql](queries/integration_examples.sql)
- [queries/advanced_dashboard_queries.sql](queries/advanced_dashboard_queries.sql)
- [queries/dashboard_gamificado.sql](queries/dashboard_gamificado.sql)

## Documentos relacionados

- [REQUISITOS_BANCO.md](REQUISITOS_BANCO.md)
- [MAPEAMENTO_BANCO.md](MAPEAMENTO_BANCO.md)
- [ERD_BANCO.md](ERD_BANCO.md)
- [GUIA_OPERACIONAL.md](GUIA_OPERACIONAL.md)
- [CONTRATO_AMBIENTE.md](CONTRATO_AMBIENTE.md)
