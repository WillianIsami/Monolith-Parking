# Mapeamento do banco

Resumo do modelo físico entregue em `backend/database/init`.

## Camadas

| Camada | Objetivo | Tabelas |
| --- | --- | --- |
| Obrigatória | Persistir estado, histórico, snapshots, incidentes e recomendações | `spots`, `spot_events`, `sector_snapshots`, `incidents`, `recommendations_log` |
| Organização | Representar campus, estacionamento e setores | `campuses`, `parking_facilities`, `sectors` |
| IoT | Controlar gateways, sensores e status de conectividade | `gateways`, `sensors`, `gateway_status_events` |
| Operação | Medir permanência e registrar manutenção/ações humanas | `spot_sessions`, `maintenance_windows`, `operator_actions` |
| Decisão | Registrar políticas, recomendações e candidatos avaliados | `recommendation_policies`, `recommendation_candidates` |
| Analítica | Guardar eventos de campus e previsões de ocupação | `campus_events`, `sector_forecasts` |
| Experiência | Suportar mapa, rotas, navegação e gamificação | `map_nodes`, `map_edges`, `route_templates`, `navigation_requests`, `app_users`, `achievement_catalog`, `user_achievements`, `engagement_events` |

## Fluxo de evento de vaga

```txt
MQTT payload
  -> apply_spot_event(...)
    -> spot_events
    -> spots
    -> spot_sessions
    -> sector_snapshots
    -> sensors.last_seen_ts
```

Regras aplicadas:

- `event_id` garante idempotência.
- `spot_id` deve pertencer ao `sector_id`.
- eventos atrasados entram no histórico, mas não sobrescrevem o estado atual.
- snapshots são consolidados por minuto.

## Tabelas centrais

| Tabela | Papel |
| --- | --- |
| `spots` | Leitura rápida do estado atual das vagas |
| `spot_events` | Auditoria completa dos eventos recebidos |
| `sector_snapshots` | Base temporal para relatórios e previsões |
| `incidents` | Registro de anomalias e evidências |
| `recommendations_log` | Registro de recomendações emitidas pela API |
| `spot_sessions` | Permanência calculada a partir de `OCCUPIED` e `FREE` |
| `sectors` | Capacidade, thresholds e prioridade operacional |
| `sensors` | Vínculo entre vaga física e dispositivo |

## Funções principais

| Função | Responsabilidade |
| --- | --- |
| `apply_spot_event(...)` | Persistir evento e atualizar estado atual |
| `upsert_sector_snapshot(...)` | Atualizar snapshot de ocupação |
| `sync_spot_session_transition(...)` | Abrir/fechar sessões de permanência |
| `register_gateway_status_event(...)` | Registrar status de gateway |
| `record_recommendation_decision(...)` | Registrar recomendação explicável |
| `generate_sector_forecasts(...)` | Gerar previsão operacional simples |
| `get_navigation_options(...)` | Listar vagas livres com rota e score |
| `grant_engagement_points(...)` | Registrar pontos de gamificação |

## Views de consumo

| View | Consumidor previsto |
| --- | --- |
| `v_current_map` | API `GET /api/v1/map` |
| `v_sector_summary_current` | API `GET /api/v1/sectors` |
| `v_sector_command_center` | Dashboard operacional |
| `vw_mapa_dashboard_vagas` | Frontend de mapa |
| `vw_ranking_engajamento` | Experiência gamificada |
