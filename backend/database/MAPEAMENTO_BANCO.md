# Mapeamento do banco

Resumo do modelo fisico entregue em `backend/database/init`.

## Camadas

| Camada | Objetivo | Tabelas |
| --- | --- | --- |
| Obrigatoria | Persistir estado, historico, snapshots, incidentes e recomendacoes | `spots`, `spot_events`, `sector_snapshots`, `incidents`, `recommendations_log` |
| Organizacao | Representar campus, estacionamento e setores | `campuses`, `parking_facilities`, `sectors` |
| IoT | Controlar gateways, sensores e status de conectividade | `gateways`, `sensors`, `gateway_status_events` |
| Operacao | Medir permanencia e registrar manutencao/acoes humanas | `spot_sessions`, `maintenance_windows`, `operator_actions` |
| Decisao | Registrar politicas, recomendacoes e candidatos avaliados | `recommendation_policies`, `recommendation_candidates` |
| Analitica | Guardar eventos de campus e previsoes de ocupacao | `campus_events`, `sector_forecasts` |
| Experiencia | Suportar mapa, rotas, navegacao e gamificacao | `map_nodes`, `map_edges`, `route_templates`, `navigation_requests`, `app_users`, `achievement_catalog`, `user_achievements`, `engagement_events` |

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

- `event_id` garante idempotencia.
- `spot_id` deve pertencer ao `sector_id`.
- eventos atrasados entram no historico, mas nao sobrescrevem o estado atual.
- snapshots sao consolidados por minuto.

## Tabelas centrais

| Tabela | Papel |
| --- | --- |
| `spots` | Leitura rapida do estado atual das vagas |
| `spot_events` | Auditoria completa dos eventos recebidos |
| `sector_snapshots` | Base temporal para relatorios e previsoes |
| `incidents` | Registro de anomalias e evidencias |
| `recommendations_log` | Registro de recomendacoes emitidas pela API |
| `spot_sessions` | Permanencia calculada a partir de `OCCUPIED` e `FREE` |
| `sectors` | Capacidade, thresholds e prioridade operacional |
| `sensors` | Vinculo entre vaga fisica e dispositivo |

## Funcoes principais

| Funcao | Responsabilidade |
| --- | --- |
| `apply_spot_event(...)` | Persistir evento e atualizar estado atual |
| `upsert_sector_snapshot(...)` | Atualizar snapshot de ocupacao |
| `sync_spot_session_transition(...)` | Abrir/fechar sessoes de permanencia |
| `register_gateway_status_event(...)` | Registrar status de gateway |
| `record_recommendation_decision(...)` | Registrar recomendacao explicavel |
| `generate_sector_forecasts(...)` | Gerar previsao operacional simples |
| `get_navigation_options(...)` | Listar vagas livres com rota e score |
| `grant_engagement_points(...)` | Registrar pontos de gamificacao |

## Views de consumo

| View | Consumidor previsto |
| --- | --- |
| `v_current_map` | API `GET /api/v1/map` |
| `v_sector_summary_current` | API `GET /api/v1/sectors` |
| `v_sector_command_center` | Dashboard operacional |
| `vw_mapa_dashboard_vagas` | Frontend de mapa |
| `vw_ranking_engajamento` | Experiencia gamificada |
