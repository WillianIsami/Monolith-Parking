# Requisitos do banco

Mapeamento entre os requisitos da atividade e a implementacao em PostgreSQL.

## Tabelas obrigatorias

| Requisito | Implementacao |
| --- | --- |
| `spots(spotId, sectorId, currentState, lastChangeTs, lastEventId)` | `spots(spot_id, sector_id, current_state, last_change_ts, last_event_id)` |
| `spot_events(eventId, ts, sectorId, spotId, state, rawPayloadJson)` | `spot_events(event_id, ts, sector_id, spot_id, state, raw_payload_json)` |
| `sector_snapshots(ts, sectorId, occupiedCount, freeCount, occupancyRate)` | `sector_snapshots(ts, sector_id, occupied_count, free_count, occupancy_rate)` |
| `incidents(id, tsOpen, tsClose, type, severity, sectorId, spotId, evidenceJson, status)` | `incidents(id, ts_open, ts_close, type, severity, sector_id, spot_id, evidence_json, status)` |
| `recommendations_log(ts, fromSector, recommendedSector, reason, dataJson)` | `recommendations_log(ts, from_sector, recommended_sector, reason, data_json)` |

Os nomes fisicos usam `snake_case`; a API pode expor os campos em `camelCase`.

## Entregas implementadas

| Item | Implementacao |
| --- | --- |
| Banco PostgreSQL | `docker-compose.yml` e `.env.example` |
| Migrations | `init/001_schema.sql` a `init/006_seed_dashboard_gamification.sql` |
| Seed das 90 vagas | `init/002_seed_spots.sql` |
| Persistencia de evento | `apply_spot_event(...)` |
| Estado atual da vaga | tabela `spots` |
| Historico de eventos | tabela `spot_events` |
| Ocupacao por setor | `get_sector_occupancy(...)` |
| Snapshots por minuto | `sector_snapshots` |
| Vagas livres | `get_free_spots(...)` |
| Turnover | `get_turnover_report(...)` |
| Incidentes | `incidents`, `open_incident(...)`, `close_incident(...)` |
| Recomendacoes | `recommendations_log`, `log_recommendation(...)`, `record_recommendation_decision(...)` |

## Validacao

Com o banco em execucao:

```powershell
npm run check:requirements
```

O script valida existencia de tabelas, colunas obrigatorias, seed de vagas, funcoes principais, chaves estrangeiras e recursos de navegacao/gamificacao.

## Acesso compartilhado

O banco remoto deve usar dois perfis:

| Perfil | Uso |
| --- | --- |
| `parking_writer` | Backend, API e scripts que precisam gravar |
| `parking_reader` | Consultas, dashboard e acesso de leitura para o time |

Configuracao:

```powershell
npm run setup:shared-access
npm run check:shared-access
```
