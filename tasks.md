# Checklist técnico do projeto

Este arquivo contém apenas o checklist técnico de aceite do MVP.

## Requisitos implementados

- [x] Setores fixos `A`, `B`, `C`.
- [x] 30 vagas por setor.
- [x] 90 vagas criadas no seed inicial.
- [x] Estados `FREE` e `OCCUPIED`.
- [x] Simulador Node.js com sensores virtuais.
- [x] 3 gateways virtuais, um por setor.
- [x] Publicação MQTT de eventos de vaga.
- [x] Publicação MQTT de status de gateway.
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

## Contratos principais

### Tópicos MQTT

```txt
campus/parking/sectors/<sectorId>/spots/<spotId>/events
campus/parking/sectors/<sectorId>/gateway/status
```

### Payload de evento

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

### Endpoints obrigatórios

```txt
GET /api/v1/map
GET /api/v1/sectors
GET /api/v1/sectors/:sectorId/spots
GET /api/v1/sectors/:sectorId/free-spots?limit=10
GET /api/v1/reports/turnover?sectorId=A&from=...&to=...
GET /api/v1/incidents?status=open
GET /api/v1/recommendation?fromSector=A
```
