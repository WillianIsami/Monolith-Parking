# Checklist Técnico do Projeto

Checklist de aceite do MVP de estacionamento inteligente.

## Requisitos Implementados

- [x] Setores fixos `A`, `B`, `C`.
- [x] 30 vagas por setor.
- [x] 90 vagas criadas no seed inicial.
- [x] Estados `FREE` e `OCCUPIED`.
- [x] Simulador Node.js com 90 sensores virtuais.
- [x] 3 gateways virtuais, um por setor.
- [x] Padrões realistas de chegada com picos por horário.
- [x] Permanência variável entre 30 minutos e 6 horas simuladas.
- [x] Publicação MQTT de eventos de vaga.
- [x] Publicação MQTT de status de gateway.
- [x] Persistência do status de gateway em `gateway_status_events`.
- [x] Injeção de falhas `stuck_occupied`, `stuck_free` e `flapping`.
- [x] Backend assina tópicos MQTT obrigatórios.
- [x] Payload MQTT validado antes da persistência.
- [x] Idempotência por `eventId`.
- [x] Histórico persistido em `spot_events`.
- [x] Estado atual persistido em `spots`.
- [x] Snapshots persistidos em `sector_snapshots`.
- [x] Incidentes persistidos em `incidents`.
- [x] Recomendações persistidas em `recommendations_log`.
- [x] API HTTP REST com endpoints obrigatórios.
- [x] Relatório de rotatividade por transição `FREE -> OCCUPIED`.
- [x] Recomendação quando `occupancyRate >= 0.90`.
- [x] Docker Compose com Mosquitto, PostgreSQL, backend e simulador.

## Contratos Principais

### Tópicos MQTT

```txt
campus/parking/sectors/<sectorId>/spots/<spotId>/events
campus/parking/sectors/<sectorId>/gateway/status
```

### Payload de Evento

```json
{
  "eventId": "uuid",
  "ts": "2026-04-29T10:15:30.000Z",
  "sectorId": "A",
  "spotId": "A-07",
  "state": "OCCUPIED",
  "source": "gateway"
}
```

### Endpoints Obrigatórios

```txt
GET /api/v1/map
GET /api/v1/sectors
GET /api/v1/sectors/:sectorId/spots
GET /api/v1/sectors/:sectorId/free-spots?limit=10
GET /api/v1/reports/turnover?sectorId=A&from=...&to=...
GET /api/v1/incidents?status=open
GET /api/v1/recommendation?fromSector=A
```

### Endpoint Adicional de Saúde dos Gateways

```txt
GET /api/v1/gateways
```

## Responsabilidades por Área

| Área | Entrega |
| --- | --- |
| Simulador | Sensores virtuais, gateways, padrões de ocupação e falhas injetáveis |
| MQTT | Contratos de tópicos, publicação de eventos e heartbeat dos gateways |
| Backend | Subscriber MQTT, validação, API REST e regras operacionais |
| Banco | Schema PostgreSQL, persistência, idempotência, snapshots e logs |
| Integração | Docker Compose, checks e smoke test do fluxo completo |

## Critério de Pronto

O MVP é considerado pronto quando `npm run check` passa, a stack sobe com `docker compose up --build` e o smoke test `npm run smoke:e2e` valida MQTT, HTTP, banco, incidentes e recomendação.
