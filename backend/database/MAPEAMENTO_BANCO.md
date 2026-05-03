# Mapeamento do banco

Resumo do modelo fisico entregue em `backend/database/init`.

## Camadas do MVP

| Camada | Objetivo | Objetos |
| --- | --- | --- |
| Cadastro fixo | Representar setores A, B e C e as 90 vagas | `sectors`, `spots` |
| Ingestao MQTT | Guardar eventos de vaga e status dos gateways | `spot_events`, `gateway_status_events` |
| Estado atual | Permitir leitura rapida do mapa e ocupacao | `spots`, `v_current_map`, `v_sector_summary_current` |
| Relatorios | Guardar snapshots e calcular turnover | `sector_snapshots`, `get_turnover_report(...)` |
| Operacao | Registrar incidentes e recomendacoes | `incidents`, `recommendations_log` |

## Fluxo de evento de vaga

```txt
Payload MQTT
  -> backend valida JSON
  -> apply_spot_event(...)
  -> spot_events
  -> spots
  -> sector_snapshots
```

Regras aplicadas:

- `event_id` garante idempotencia.
- `spot_id` deve pertencer ao `sector_id`.
- eventos atrasados entram no historico, mas nao sobrescrevem o estado atual se forem mais antigos que `last_change_ts`.
- snapshots sao consolidados por minuto.

## Fluxo de status de gateway

```txt
Payload MQTT gateway/status
  -> backend valida JSON
  -> record_gateway_status(...)
  -> gateway_status_events
  -> v_gateway_current_status
```

## Tabelas centrais

| Tabela | Papel |
| --- | --- |
| `sectors` | Setores fixos e capacidade |
| `spots` | Estado atual das vagas |
| `spot_events` | Auditoria dos eventos recebidos |
| `gateway_status_events` | Historico de saude dos gateways |
| `sector_snapshots` | Base temporal para relatorios |
| `incidents` | Registro de anomalias e evidencias |
| `recommendations_log` | Registro de recomendacoes emitidas pela API |

## Funcoes principais

| Funcao | Responsabilidade |
| --- | --- |
| `apply_spot_event(...)` | Persistir evento, garantir idempotencia e atualizar estado atual |
| `record_gateway_status(...)` | Persistir status de gateway |
| `upsert_sector_snapshot(...)` | Atualizar snapshot de ocupacao |
| `get_sector_occupancy(...)` | Retornar disponibilidade por setor |
| `get_free_spots(...)` | Retornar vagas livres por setor |
| `get_turnover_report(...)` | Calcular transicoes `FREE -> OCCUPIED` |
| `get_incidents(...)` | Consultar incidentes |
| `open_incident(...)` | Abrir incidente sem duplicidade aberta |
| `log_recommendation(...)` | Registrar recomendacao |
