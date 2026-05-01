# Plano de trabalho

Este documento define a divisao de responsabilidades e os contratos de integracao do projeto Monolith Parking.

## Objetivo

Construir um sistema de estacionamento inteligente para campus com simulacao de sensores, mensageria MQTT, persistencia em banco, API HTTP, regras de recomendacao, incidentes e visualizacao operacional.

## Responsabilidades

| Responsavel | Area | Entrega |
| --- | --- | --- |
| Roger | Simulador IoT/MQTT | Sensores virtuais, gateways, eventos e falhas simuladas |
| Nicol | Backend MQTT | Subscriber, validacao de payload, idempotencia e ingestao |
| Morgado | Banco de dados | Schema, seed, persistencia, consultas e relatorios |
| Seisdedo | API e regras | Endpoints HTTP, recomendacoes e incidentes |
| Will | Integracao | Docker, documentacao final, testes e demo |

## Contratos de dados

### Setores e vagas

```txt
Setores: A, B, C
Vagas: A-01..A-30, B-01..B-30, C-01..C-30
Estados: FREE, OCCUPIED
```

### Evento MQTT de vaga

Topico:

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

Topico:

```txt
campus/parking/sectors/<sectorId>/gateway/status
```

Campos minimos:

```txt
ts, sectorId, status, gatewayId/source
```

## Banco de dados

Banco escolhido: PostgreSQL.

Tabelas obrigatorias:

```txt
spots
spot_events
sector_snapshots
incidents
recommendations_log
```

Contrato tecnico completo: [backend/database/README.md](backend/database/README.md).

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

## Regras obrigatorias

### Recomendacao

Regra `R-OP1`: se `occupancyRate >= 0.90`, recomendar outro setor com melhor disponibilidade.

### Incidentes

Tipos minimos:

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
3. Banco grava historico em `spot_events` e atualiza `spots`.
4. Banco calcula snapshots e fornece consultas para API.
5. API retorna mapa, setores, vagas livres, turnover, incidentes e recomendacoes.
6. Demo mostra fluxo completo e registros persistidos.

## Criterios de aceite

- 90 vagas criadas no seed inicial.
- Eventos duplicados nao alteram o estado duas vezes.
- Estado atual da vaga fica em `spots`.
- Historico completo fica em `spot_events`.
- Ocupacao por setor fica disponivel em consulta e snapshot.
- Turnover considera transicoes `FREE -> OCCUPIED`.
- Recomendacoes ficam registradas em `recommendations_log`.
- Incidentes ficam registrados em `incidents`.
- Todos os servicos usam os mesmos contratos de topico, payload, setor e vaga.
