# Mapeamento do Banco

Resumo do modelo físico entregue em `backend/database/init`.

## Camadas do MVP

| Camada | Objetivo | Objetos |
| --- | --- | --- |
| Cadastro fixo | Representar setores `A`, `B`, `C` e as 90 vagas | `sectors`, `spots` |
| Ingestão MQTT | Guardar eventos de vaga e status dos gateways | `spot_events`, `gateway_status_events` |
| Estado atual | Permitir leitura rápida do mapa e ocupação | `spots`, `v_current_map`, `v_sector_summary_current` |
| Relatórios | Guardar snapshots e calcular turnover | `sector_snapshots`, `get_turnover_report(...)` |
| Operação | Registrar incidentes e recomendações | `incidents`, `recommendations_log` |

## Fluxo de Evento de Vaga

```txt
Payload MQTT
  -> backend valida JSON
  -> apply_spot_event(...)
  -> spot_events
  -> spots
  -> sector_snapshots
```

Regras aplicadas:

- `event_id` garante idempotência.
- `spot_id` deve pertencer ao `sector_id`.
- eventos atrasados entram no histórico, mas não sobrescrevem o estado atual se forem mais antigos que `last_change_ts`.
- snapshots são consolidados por minuto.

## Fluxo de Status de Gateway

```txt
Payload MQTT gateway/status
  -> backend valida JSON
  -> record_gateway_status(...)
  -> gateway_status_events
  -> v_gateway_current_status
```

## Tabelas Centrais

| Tabela | Papel |
| --- | --- |
| `sectors` | Setores fixos e capacidade |
| `spots` | Estado atual das vagas |
| `spot_events` | Auditoria dos eventos recebidos |
| `gateway_status_events` | Histórico de saúde dos gateways |
| `sector_snapshots` | Base temporal para relatórios |
| `incidents` | Registro de anomalias e evidências |
| `recommendations_log` | Registro de recomendações emitidas pela API |

## Funções Principais

| Função | Responsabilidade |
| --- | --- |
| `apply_spot_event(...)` | Persistir evento, garantir idempotência e atualizar estado atual |
| `record_gateway_status(...)` | Persistir status de gateway |
| `upsert_sector_snapshot(...)` | Atualizar snapshot de ocupação |
| `get_sector_occupancy(...)` | Retornar disponibilidade por setor |
| `get_free_spots(...)` | Retornar vagas livres por setor |
| `get_turnover_report(...)` | Calcular transições `FREE -> OCCUPIED` |
| `get_incidents(...)` | Consultar incidentes |
| `open_incident(...)` | Abrir incidente sem duplicidade aberta |
| `log_recommendation(...)` | Registrar recomendação |
