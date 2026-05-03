# Requisitos do banco

Mapeamento entre o enunciado da Sprint 2 e a implementacao em PostgreSQL.

## Tabelas obrigatorias

| Requisito | Implementacao |
| --- | --- |
| `spots(spotId, sectorId, currentState, lastChangeTs, lastEventId)` | `spots(spot_id, sector_id, current_state, last_change_ts, last_event_id)` |
| `spot_events(eventId, ts, sectorId, spotId, state, rawPayloadJson)` | `spot_events(event_id, ts, sector_id, spot_id, state, raw_payload_json)` |
| `sector_snapshots(ts, sectorId, occupiedCount, freeCount, occupancyRate)` | `sector_snapshots(ts, sector_id, occupied_count, free_count, occupancy_rate)` |
| `incidents(id, tsOpen, tsClose, type, severity, sectorId, spotId, evidenceJson, status)` | `incidents(id, ts_open, ts_close, type, severity, sector_id, spot_id, evidence_json, status)` |
| `recommendations_log(ts, fromSector, recommendedSector, reason, dataJson)` | `recommendations_log(ts, from_sector, recommended_sector, reason, data_json)` |

## Tabelas de apoio

| Tabela | Justificativa |
| --- | --- |
| `sectors` | Mantem os setores fixos A, B e C com capacidade 30 |
| `gateway_status_events` | Persiste status dos gateways publicados no topico MQTT de saude |

## Entregas implementadas

| Item | Implementacao |
| --- | --- |
| Banco PostgreSQL | `docker-compose.yml` e `.env.example` |
| Schema | `init/001_schema.sql` |
| Seed das 90 vagas | `init/002_seed_spots.sql` |
| Persistencia de evento | `apply_spot_event(...)` |
| Idempotencia por `eventId` | `spot_events.event_id` como chave primaria e `ON CONFLICT DO NOTHING` |
| Estado atual da vaga | tabela `spots` |
| Historico de eventos | tabela `spot_events` |
| Ocupacao por setor | `get_sector_occupancy(...)` |
| Snapshots por minuto | `sector_snapshots` atualizado em `apply_spot_event(...)` |
| Vagas livres | `get_free_spots(...)` |
| Turnover | `get_turnover_report(...)` |
| Incidentes | `incidents`, `open_incident(...)`, `get_incidents(...)` |
| Recomendacoes | `recommendations_log`, `log_recommendation(...)` |
| Saude dos gateways | `gateway_status_events`, `record_gateway_status(...)`, `v_gateway_current_status` |

## Validacao

Com o banco em execucao:

```powershell
npm run check:requirements
npm run check:db
```

Os checks validam tabelas, colunas, funcoes, views, seed das 90 vagas e consultas principais do MVP.
