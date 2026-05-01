# Guia operacional do banco

## Fluxo local

```powershell
cd backend/database
Copy-Item .env.example .env
npm install
docker compose up -d
npm run check:requirements
npm run check:db
```

Adminer:

```powershell
docker compose --profile admin up -d
```

## Fluxo com banco compartilhado

```powershell
cd backend/database
Copy-Item .env.shared.example .env
npm install
npm run bootstrap:shared
npm run setup:shared-access
npm run check:requirements
npm run check:db
npm run check:shared-access
```

O arquivo `.env` real deve ficar fora do Git.

Para Supabase, use `.env.supabase.example` como base e mantenha o database como `postgres`, salvo se o projeto tiver configuracao diferente.

## Hosts padrao

| Uso | Host |
| --- | --- |
| Scripts locais e ferramentas desktop | `localhost` |
| Servicos no mesmo Docker Compose | `postgres` |
| Ambiente compartilhado | valor definido em `DATABASE_URL` |

## Comandos NPM

| Comando | Descricao |
| --- | --- |
| `npm run bootstrap:shared` | Aplica schema e seeds em um banco existente |
| `npm run setup:shared-access` | Cria/atualiza usuarios `parking_writer` e `parking_reader` |
| `npm run check:shared-access` | Valida escrita do writer e leitura do reader |
| `npm run check:requirements` | Verifica requisitos obrigatorios e recursos avancados |
| `npm run check:db` | Mostra resumo operacional do banco |
| `npm run demo:db` | Executa um fluxo demonstrativo via Node.js |

## Integracao esperada

- Ingestao MQTT chama `apply_spot_event(...)`.
- API de setores usa `get_sector_occupancy(...)`.
- API de vagas livres usa `get_free_spots(...)`.
- API de turnover usa `get_turnover_report(...)`.
- API de incidentes usa `get_incidents(...)`, `open_incident(...)` e `close_incident(...)`.
- API de recomendacao registra decisoes em `recommendations_log`.

## Checks antes da demo

- `docker compose ps` mostra o Postgres saudavel.
- `npm run check:requirements` finaliza sem falhas.
- `npm run check:db` retorna 90 vagas.
- Consultas em `queries/api_queries.sql` executam sem erro.
