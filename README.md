# Monolith Parking

MVP de **Estacionamento Inteligente para Campus** com **MQTT + HTTP REST + PostgreSQL**.

O projeto implementa 3 setores fixos (`A`, `B`, `C`), cada um com 30 vagas, totalizando 90 vagas (`A-01..A-30`, `B-01..B-30`, `C-01..C-30`). O simulador publica eventos MQTT, o backend processa os eventos de forma idempotente, persiste histórico no banco, atualiza o estado atual, detecta incidentes e expõe uma API HTTP para consultas, relatórios e recomendações.

![Arquitetura](arquitetura.png)

## O que está implementado

- Simulador Node.js com 90 sensores virtuais e 3 gateways.
- Publicação MQTT de eventos de vaga.
- Publicação MQTT de status dos gateways.
- Falhas injetáveis: `stuck_occupied`, `stuck_free` e `flapping`.
- Backend HTTP REST com Express.
- Subscriber MQTT com validação de payload.
- Idempotência real por `eventId` no PostgreSQL.
- Estado atual em `spots` e histórico em `spot_events`.
- Snapshots de ocupação por setor em `sector_snapshots`.
- Incidentes persistidos em `incidents`.
- Recomendações persistidas em `recommendations_log`.
- Docker Compose com Mosquitto, PostgreSQL, backend, simulador e Adminer opcional.

## Arquitetura

```txt
Simulador Node.js
90 sensores virtuais + 3 gateways
        |
        | MQTT
        v
Eclipse Mosquitto
        |
        | subscriber
        v
Backend Node.js / Express
        |
        | SQL
        v
PostgreSQL
        |
        v
HTTP REST API
/map, /sectors, /incidents, /reports, /recommendation
```

## Tecnologias

- Node.js
- Express
- MQTT.js
- Eclipse Mosquitto
- PostgreSQL
- Docker Compose
- Adminer opcional para visualização do banco

## Como rodar

Crie o arquivo `.env` a partir do exemplo:

```bash
cp .env.example .env
```

Suba todos os serviços:

```bash
docker compose up --build
```

Serviços principais:

| Serviço | URL |
| --- | --- |
| Backend HTTP | `http://localhost:3000` |
| Simulador HTTP | `http://localhost:4000` |
| Mosquitto MQTT | `mqtt://localhost:1883` |
| Adminer opcional | `http://localhost:8080` |

Para subir com Adminer:

```bash
docker compose --profile admin up --build
```

## Contratos MQTT

### Evento de vaga

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

Payload exemplo:

```json
{
  "ts": "2026-04-29T10:15:30.000Z",
  "sectorId": "A",
  "gatewayId": "gateway-A",
  "status": "ONLINE",
  "source": "gateway"
}
```

## Banco de dados

Tabelas obrigatórias implementadas:

- `spots`
- `spot_events`
- `sector_snapshots`
- `incidents`
- `recommendations_log`

O seed inicial cria automaticamente:

- setores `A`, `B`, `C`;
- vagas `A-01..A-30`, `B-01..B-30`, `C-01..C-30`;
- estado inicial `FREE`.

## Endpoints HTTP obrigatórios

### Mapa atual

```http
GET /api/v1/map
```

### Disponibilidade por setor

```http
GET /api/v1/sectors
```

### Vagas de um setor

```http
GET /api/v1/sectors/A/spots
```

### Vagas livres por setor

```http
GET /api/v1/sectors/A/free-spots?limit=10
```

### Relatório de rotatividade

```http
GET /api/v1/reports/turnover?sectorId=A&from=2026-04-29T00:00:00.000Z&to=2026-04-30T00:00:00.000Z
```

A rotatividade considera transições `FREE -> OCCUPIED` no período.

### Incidentes

```http
GET /api/v1/incidents?status=open
```

### Recomendação

```http
GET /api/v1/recommendation?fromSector=A
```

Quando o setor de origem está com `occupancyRate >= 0.90`, o backend recomenda o setor alternativo com mais vagas livres e registra o resultado em `recommendations_log`.

Resposta exemplo:

```json
{
  "fromSector": "A",
  "recommendedSector": "B",
  "reason": "Sector A at 93% occupancy; Sector B has 12 free spots",
  "ts": "2026-04-29T10:20:00.000Z"
}
```

## Endpoints do simulador para demonstração

### Ver estado do simulador

```http
GET http://localhost:4000/sim/state
```

### Injetar falha `flapping`

```http
POST http://localhost:4000/sim/faults
Content-Type: application/json

{
  "sectorId": "A",
  "spotId": "A-07",
  "type": "flapping"
}
```

Depois consulte:

```http
GET http://localhost:3000/api/v1/incidents?status=open
```

### Injetar `stuck_occupied` com tempo antigo para demo rápida

```http
POST http://localhost:4000/sim/faults
Content-Type: application/json

{
  "sectorId": "A",
  "spotId": "A-08",
  "type": "stuck_occupied",
  "ageMinutes": 400
}
```

### Injetar `stuck_free` com tempo antigo para demo rápida

```http
POST http://localhost:4000/sim/faults
Content-Type: application/json

{
  "sectorId": "B",
  "spotId": "B-10",
  "type": "stuck_free",
  "ageMinutes": 800
}
```

### Lotar um setor para testar recomendação

```http
POST http://localhost:4000/sim/fill-sector/A
Content-Type: application/json

{
  "occupiedCount": 28
}
```

Depois consulte:

```http
GET http://localhost:3000/api/v1/recommendation?fromSector=A
```

### Resetar simulação

```http
POST http://localhost:4000/sim/reset
```

## Roteiro de demonstração

1. Rodar `docker compose up --build`.
2. Mostrar logs do simulador publicando eventos MQTT.
3. Mostrar logs do backend consumindo eventos MQTT.
4. Acessar `GET /api/v1/map`.
5. Acessar `GET /api/v1/sectors`.
6. Injetar `flapping` em uma vaga pelo simulador.
7. Acessar `GET /api/v1/incidents?status=open`.
8. Lotar o setor `A` com `POST /sim/fill-sector/A`.
9. Acessar `GET /api/v1/recommendation?fromSector=A`.
10. Conferir registros no banco em `spot_events`, `incidents` e `recommendations_log`.

## Observação sobre IA

A base de dados já guarda histórico suficiente para uso futuro de IA, principalmente em `spot_events`, `sector_snapshots`, `incidents` e `recommendations_log`. A implementação atual mantém foco no MVP obrigatório: MQTT, HTTP, banco, incidentes e recomendação por regra.
