# Checklist tecnico do projeto

Checklist de aceite do MVP com base em `dist/prova_final_sprint_2.md`.

## Requisitos implementados

- [x] Setores fixos `A`, `B`, `C`.
- [x] 30 vagas por setor.
- [x] 90 vagas criadas no seed inicial.
- [x] Estados `FREE` e `OCCUPIED`.
- [x] Simulador Node.js com 90 sensores virtuais.
- [x] 3 gateways virtuais, um por setor.
- [x] Padroes realistas de chegada com picos por horario.
- [x] Permanencia variavel entre 30 minutos e 6 horas simuladas.
- [x] Publicacao MQTT de eventos de vaga.
- [x] Publicacao MQTT de status de gateway.
- [x] Persistencia do status de gateway em `gateway_status_events`.
- [x] Injecao de falhas `stuck_occupied`, `stuck_free` e `flapping`.
- [x] Backend assina topicos MQTT obrigatorios.
- [x] Payload MQTT validado antes da persistencia.
- [x] Idempotencia por `eventId`.
- [x] Historico persistido em `spot_events`.
- [x] Estado atual persistido em `spots`.
- [x] Snapshots persistidos em `sector_snapshots`.
- [x] Incidentes persistidos em `incidents`.
- [x] Recomendacoes persistidas em `recommendations_log`.
- [x] API HTTP REST com endpoints obrigatorios.
- [x] Relatorio de rotatividade por transicao `FREE -> OCCUPIED`.
- [x] Recomendacao quando `occupancyRate >= 0.90`.
- [x] Docker Compose com Mosquitto, PostgreSQL, backend e simulador.

## Contratos principais

### Topicos MQTT

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

### Endpoints obrigatorios

```txt
GET /api/v1/map
GET /api/v1/sectors
GET /api/v1/sectors/:sectorId/spots
GET /api/v1/sectors/:sectorId/free-spots?limit=10
GET /api/v1/reports/turnover?sectorId=A&from=...&to=...
GET /api/v1/incidents?status=open
GET /api/v1/recommendation?fromSector=A
```

### Endpoint adicional de saude dos gateways

```txt
GET /api/v1/gateways
```
