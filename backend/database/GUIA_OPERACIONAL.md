# Guia Operacional do Banco

Este guia resume como manter o PostgreSQL local, Docker e compartilhado alinhados.

## Fluxo Local

```powershell
cd backend/database
Copy-Item .env.example .env
npm install
docker compose up -d
npm run check:requirements
npm run check:db
```

## Fluxo Compartilhado

```powershell
cd backend/database
Copy-Item .env.supabase.example .env
npm install
npm run bootstrap:shared
npm run setup:shared-access
npm run check:requirements
npm run check:db
npm run check:shared-access
```

## Hosts por Ambiente

| Ambiente | Host esperado |
| --- | --- |
| Ferramentas locais | `localhost` |
| Serviços no mesmo Docker Compose | `postgres` |
| Supabase ou provedor remoto | host/pooler informado pelo provedor |

## Rotina de Validação

- Rode `npm run check:requirements` após qualquer alteração de schema.
- Rode `npm run check:db` para ver estado de vagas, setores, gateways, incidentes e recomendações.
- Rode `npm run check:shared-access` quando alterar credenciais ou permissões de `parking_writer` e `parking_reader`.

## Integração com o Backend

- Ingestão MQTT de vagas chama `apply_spot_event(...)`.
- Ingestão MQTT de gateways chama `record_gateway_status(...)`.
- API de mapa e setores usa `get_sector_occupancy(...)` e `v_current_map`.
- API de incidentes usa `incidents` e `get_incidents(...)`.
- API de recomendação registra decisões em `recommendations_log`.

## Segurança

- Não committe `.env`.
- Não publique senhas em Markdown.
- Use `parking_writer` para serviços que escrevem.
- Use `parking_reader` para consultas, dashboards e validações somente leitura.
