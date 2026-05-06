# Requisitos do Banco

Mapeamento entre o enunciado da Sprint 2 e a implementação em PostgreSQL.

## Tabelas Obrigatórias

| Requisito | Implementação |
| --- | --- |
| `spots(spotId, sectorId, currentState, lastChangeTs, lastEventId)` | `spots(spot_id, sector_id, current_state, last_change_ts, last_event_id)` |
| `spot_events(eventId, ts, sectorId, spotId, state, rawPayloadJson)` | `spot_events(event_id, ts, sector_id, spot_id, state, raw_payload_json)` |
| `sector_snapshots(ts, sectorId, occupiedCount, freeCount, occupancyRate)` | `sector_snapshots(ts, sector_id, occupied_count, free_count, occupancy_rate)` |
| `incidents(id, tsOpen, tsClose, type, severity, sectorId, spotId, evidenceJson, status)` | `incidents(id, ts_open, ts_close, type, severity, sector_id, spot_id, evidence_json, status)` |
| `recommendations_log(ts, fromSector, recommendedSector, reason, dataJson)` | `recommendations_log(ts, from_sector, recommended_sector, reason, data_json)` |

## Tabelas de Apoio

| Tabela | Justificativa |
| --- | --- |
| `sectors` | Mantém os setores fixos `A`, `B` e `C` com capacidade 30 |
| `gateway_status_events` | Persiste status dos gateways publicados no tópico MQTT de saúde |

## Entregas Implementadas

| Item | Implementação |
| --- | --- |
| Banco PostgreSQL | `docker-compose.yml` e `.env.example` |
| Schema | `init/001_schema.sql` |
| Seed das 90 vagas | `init/002_seed_spots.sql` |
| Persistência de evento | `apply_spot_event(...)` |
| Idempotência por `eventId` | `spot_events.event_id` como chave primária e `ON CONFLICT DO NOTHING` |
| Estado atual da vaga | tabela `spots` |
| Histórico de eventos | tabela `spot_events` |
| Ocupação por setor | `get_sector_occupancy(...)` |
| Snapshots por minuto | `sector_snapshots`, atualizado em `apply_spot_event(...)` |
| Vagas livres | `get_free_spots(...)` |
| Turnover | `get_turnover_report(...)` |
| Incidentes | `incidents`, `open_incident(...)`, `get_incidents(...)` |
| Recomendações | `recommendations_log`, `log_recommendation(...)` |
| Saúde dos gateways | `gateway_status_events`, `record_gateway_status(...)`, `v_gateway_current_status` |

## Validação

Com o banco em execução:

```powershell
npm run check:requirements
npm run check:db
```

Os checks validam tabelas, colunas, funções, views, seed das 90 vagas e consultas principais do MVP.
