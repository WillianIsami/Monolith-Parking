# Plano de trabalho

Este documento define a divisão de responsabilidades e os contratos de integração do projeto Monolith Parking.

## Objetivo

Construir um sistema de estacionamento inteligente para campus com simulação de sensores, mensageria MQTT, persistência em banco, API HTTP, regras de recomendação, incidentes e visualização operacional.

## Responsabilidades

| Responsável | Área | Entrega |
| --- | --- | --- |
| Roger | Simulador IoT/MQTT | Sensores virtuais, gateways, eventos e falhas simuladas |
| Nicolas | Backend MQTT | Subscriber, validação de payload, idempotência e ingestão |
| Morgado | Banco de dados | Schema, seed, persistência, consultas e relatórios |
| Seisdedo | API e regras | Endpoints HTTP, recomendações e incidentes |
| Will | Integração | Docker, documentação final, testes e demo |

## Contratos de dados

### Setores e vagas

```txt
Setores: A, B, C
Vagas: A-01..A-30, B-01..B-30, C-01..C-30
Estados: FREE, OCCUPIED
```

### Evento MQTT de vaga

Tópico:

```txt
campus/parking/sectors/<sectorId>/spots/<spotId>/events
```

Payload:

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

### Status de gateway

Tópico:

```txt
campus/parking/sectors/<sectorId>/gateway/status
```

Campos mínimos:

```txt
ts, sectorId, status, gatewayId/source
```

## Banco de dados

Banco escolhido: PostgreSQL.

Tabelas obrigatórias:

```txt
spots
spot_events
sector_snapshots
incidents
recommendations_log
```

Contrato técnico completo: [backend/database/README.md](backend/database/README.md).

## API HTTP prevista

```txt
GET /api/v1/map
GET /api/v1/sectors
GET /api/v1/sectors/:sectorId/spots
GET /api/v1/sectors/:sectorId/free-spots?limit=10
GET /api/v1/reports/turnover?sectorId=A&from=...&to=...
GET /api/v1/incidents?status=open
GET /api/v1/recommendation?fromSector=A
```

## Regras obrigatórias

### Recomendação

Regra `R-OP1`: se `occupancyRate >= 0.90`, recomendar outro setor com melhor disponibilidade.

### Incidentes

Tipos mínimos:

```txt
STUCK_OCCUPIED
STUCK_FREE
FLAPPING
```

Status:

```txt
open
closed
```

## Fluxo esperado

```txt
simulador -> MQTT -> backend subscriber -> banco -> API -> dashboard/demo
```

1. Sensores simulados publicam eventos.
2. Backend MQTT valida payload e ignora duplicados por `eventId`.
3. Banco grava histórico em `spot_events` e atualiza `spots`.
4. Banco calcula snapshots e fornece consultas para API.
5. API retorna mapa, setores, vagas livres, turnover, incidentes e recomendações.
6. Demo mostra fluxo completo e registros persistidos.

## Critérios de aceite

- 90 vagas criadas no seed inicial.
- Eventos duplicados não alteram o estado duas vezes.
- Estado atual da vaga fica em `spots`.
- Histórico completo fica em `spot_events`.
- Ocupação por setor fica disponível em consulta e snapshot.
- Turnover considera transições `FREE -> OCCUPIED`.
- Recomendações ficam registradas em `recommendations_log`.
- Incidentes ficam registrados em `incidents`.
- Todos os serviços usam os mesmos contratos de tópico, payload, setor e vaga.
