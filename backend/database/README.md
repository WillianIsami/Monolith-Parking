# Banco de Dados

Módulo responsável pela persistência do MVP de estacionamento inteligente.

## Decisão Técnica

Banco escolhido: PostgreSQL.

Motivos:

- suporte nativo a `jsonb` para payloads MQTT, evidências de incidentes e contexto de recomendação;
- boa compatibilidade com Docker Compose, Supabase e outros provedores gerenciados;
- constraints e funções SQL para manter idempotência e integridade perto dos dados;
- integração simples com Node.js via `pg`, sem depender de ORM para a demonstração.

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
| `sectors` | Setores fixos `A`, `B` e `C`, capacidade e threshold operacional |
| `spots` | Estado atual de cada vaga |
| `spot_events` | Histórico bruto dos eventos de vaga recebidos via MQTT |
| `gateway_status_events` | Histórico de saúde dos gateways recebido via MQTT |
| `sector_snapshots` | Ocupação agregada por setor e minuto |
| `incidents` | Incidentes operacionais e evidências |
| `recommendations_log` | Histórico de recomendações emitidas |

## Funções e Views

| Objeto | Uso |
| --- | --- |
| `apply_spot_event(...)` | Persiste evento MQTT, garante idempotência por `event_id` e atualiza `spots` |
| `record_gateway_status(...)` | Persiste heartbeat/status dos gateways |
| `get_sector_occupancy(...)` | Retorna ocupação atual por setor |
| `get_free_spots(...)` | Lista vagas livres por setor |
| `get_turnover_report(...)` | Calcula transições `FREE -> OCCUPIED` |
| `get_incidents(...)` | Lista incidentes filtrando por status e setor |
| `open_incident(...)` | Abre incidente sem duplicar incidente aberto equivalente |
| `close_incident(...)` | Fecha incidente |
| `log_recommendation(...)` | Registra recomendação operacional |
| `v_current_map` | Mapa atual das vagas |
| `v_sector_summary_current` | Resumo atual de ocupação |
| `v_gateway_current_status` | Último status conhecido de cada gateway |

## Execução Local

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

## Banco Compartilhado

1. Criar ou reutilizar um PostgreSQL remoto.
2. Copiar `.env.shared.example` ou `.env.supabase.example` para `.env`.
3. Ajustar `DATABASE_URL`, `DATABASE_ADMIN_URL` e `PGSSLMODE`.
4. Aplicar schema, seed e permissões.

```powershell
npm run bootstrap:shared
npm run setup:shared-access
npm run check:requirements
npm run check:db
npm run check:shared-access
```

O bootstrap é idempotente para o MVP atual: ele cria objetos ausentes e também atualiza bancos compartilhados criados antes da tabela de status dos gateways.

## Papéis de Acesso

| Papel | Uso |
| --- | --- |
| `parking_writer` | Backend, subscriber MQTT e scripts que precisam escrever |
| `parking_reader` | Consultas, dashboards, BI e validações somente leitura |

Senhas e URLs reais não devem ser commitadas. Compartilhe credenciais reais apenas em canal privado do grupo.
