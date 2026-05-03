# Monolith Parking

MVP de Estacionamento Inteligente para Campus com MQTT, HTTP REST, PostgreSQL e simulador Node.js.

O projeto implementa 3 setores fixos (`A`, `B`, `C`), cada um com 30 vagas, totalizando 90 vagas (`A-01..A-30`, `B-01..B-30`, `C-01..C-30`). O simulador publica eventos MQTT, o backend processa os eventos de forma idempotente, persiste historico no banco, atualiza o estado atual, detecta incidentes e expoe uma API HTTP para consultas, relatorios e recomendacoes.

![Arquitetura do Monolith Parking](arquitetura.png)

## O que esta implementado

- Simulador Node.js com 90 sensores virtuais e 3 gateways.
- Setores fixos `A`, `B`, `C` e vagas `A-01..C-30`.
- Publicacao MQTT de eventos de vaga.
- Publicacao MQTT de status dos gateways.
- Falhas injetaveis: `stuck_occupied`, `stuck_free` e `flapping`.
- Backend HTTP REST com Express.
- Subscriber MQTT com validacao de payload.
- Idempotencia por `eventId` no PostgreSQL.
- Estado atual em `spots` e historico em `spot_events`.
- Status de gateways em `gateway_status_events`.
- Snapshots de ocupacao por setor em `sector_snapshots`.
- Incidentes persistidos em `incidents`.
- Recomendacoes persistidas em `recommendations_log`.
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
        | MQTT subscriber
        v
Backend Node.js / Express
        |
        | SQL
        v
PostgreSQL

Consumidores HTTP:
curl, Postman, Insomnia ou navegador
        |
        | HTTP REST
        v
Backend / Simulador
```

## Tecnologias

- Node.js
- Express
- MQTT.js
- Eclipse Mosquitto
- PostgreSQL
- Docker Compose
- Adminer opcional

## Como rodar com Docker

Pre-requisitos:

- Docker Desktop no Windows com integracao WSL 2 habilitada para a distro usada, ou Docker Engine no Linux.
- Node.js 18+ se quiser rodar os checks locais fora dos containers.

No Windows/PowerShell:

```powershell
Copy-Item .env.example .env
docker compose up --build
```

No Linux/WSL/bash:

```bash
cp .env.example .env
docker compose up --build
```

Se o WSL mostrar `The command 'docker' could not be found`, abra o Docker Desktop no Windows e habilite `Settings > Resources > WSL Integration` para a sua distro. Depois feche e reabra o terminal WSL.

Se ja existia um volume Postgres antigo deste projeto, recrie o banco para aplicar o schema atualizado:

```bash
docker compose down -v
docker compose up --build
```

Servicos principais:

| Servico | URL |
| --- | --- |
| Backend HTTP | `http://localhost:3000` |
| Simulador HTTP | `http://localhost:4000` |
| Mosquitto MQTT | `mqtt://localhost:1883` |
| Adminer opcional | `http://localhost:8080` |

Para subir com Adminer:

```bash
docker compose --profile admin up --build
```

## Como rodar com Podman

Em Linux com Podman funcional:

```bash
cp .env.example .env
podman compose up --build
```

Se estiver em WSL e aparecer erro parecido com `aardvark-dns failed to start: Failed to connect to bus`, o problema e do Podman rootless sem `systemd --user`/D-Bus na distro. Nesse caso, habilite systemd no WSL ou use Docker Desktop com integracao WSL para a demo. O projeto em si usa imagens e Compose compativeis com Podman; o simulador precisa ser iniciado pelo Compose porque ele sobrescreve o comando padrao do Dockerfile com `npm run start:simulator`.

## Como rodar manualmente

O modo manual roda backend e simulador pelo Node.js local. O PostgreSQL e o Mosquitto ainda precisam estar disponiveis. Backend e simulador leem o arquivo `.env` da raiz do projeto via `dotenv`.

1. Instale as dependencias:

```bash
npm install
```

2. Configure o `.env` da raiz, se ainda nao existir.

Windows/PowerShell:

```powershell
Copy-Item .env.example .env
```

Linux/WSL/bash:

```bash
cp .env.example .env
```

Os valores do `.env.example` ja apontam para PostgreSQL e Mosquitto locais em `localhost`. Edite o `.env` apenas se precisar trocar porta, credenciais ou URL de conexao.

3. Suba somente a infraestrutura com Docker:

```bash
docker compose up -d postgres mosquitto
```

Esse comando inicializa o banco automaticamente com os arquivos em `backend/database/init`.

4. Inicie o backend:

```bash
npm run start:backend
```

5. Em outro terminal, inicie o simulador:

```bash
npm run start:simulator
```

6. Se preferir usar PostgreSQL e Mosquitto instalados diretamente na maquina, aplique o schema antes de iniciar o backend:

```bash
psql "$DATABASE_URL" -f backend/database/init/001_schema.sql
psql "$DATABASE_URL" -f backend/database/init/002_seed_spots.sql
```

### Sobrescrever variaveis pelo terminal

O fluxo principal usa `.env`. Os comandos abaixo sao uma alternativa avancada para explicitar as variaveis usadas e sobrescrever valores sem editar arquivo local.

Backend:

| Variavel | Uso |
| --- | --- |
| `PORT` | Porta HTTP do backend |
| `DATABASE_URL` | String de conexao PostgreSQL |
| `PGSSLMODE` | Modo SSL do PostgreSQL |
| `MQTT_BROKER_URL` | URL do broker MQTT |

Linux/WSL/bash:

```bash
export PORT=3000
export DATABASE_URL="postgresql://parking:parking123@localhost:5432/monolith_parking"
export PGSSLMODE=disable
export MQTT_BROKER_URL="mqtt://localhost:1883"
npm run start:backend
```

Windows/PowerShell:

```powershell
$env:PORT="3000"
$env:DATABASE_URL="postgresql://parking:parking123@localhost:5432/monolith_parking"
$env:PGSSLMODE="disable"
$env:MQTT_BROKER_URL="mqtt://localhost:1883"
npm run start:backend
```

Simulador:

| Variavel | Uso |
| --- | --- |
| `SIMULATOR_PORT` | Porta HTTP do simulador |
| `MQTT_BROKER_URL` | URL do broker MQTT |
| `SIMULATED_MINUTE_MS` | Duracao de 1 minuto simulado |
| `SIMULATOR_TICK_MS` | Intervalo de tick da simulacao |
| `GATEWAY_STATUS_INTERVAL_MS` | Intervalo de heartbeat dos gateways |

Linux/WSL/bash:

```bash
export SIMULATOR_PORT=4000
export MQTT_BROKER_URL="mqtt://localhost:1883"
export SIMULATED_MINUTE_MS=1000
export SIMULATOR_TICK_MS=1000
export GATEWAY_STATUS_INTERVAL_MS=15000
npm run start:simulator
```

Windows/PowerShell:

```powershell
$env:SIMULATOR_PORT="4000"
$env:MQTT_BROKER_URL="mqtt://localhost:1883"
$env:SIMULATED_MINUTE_MS="1000"
$env:SIMULATOR_TICK_MS="1000"
$env:GATEWAY_STATUS_INTERVAL_MS="15000"
npm run start:simulator
```

## Contratos MQTT

### Evento de vaga

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

Payload:

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

Tabelas principais:

- `sectors`
- `spots`
- `spot_events`
- `gateway_status_events`
- `sector_snapshots`
- `incidents`
- `recommendations_log`

O seed inicial cria automaticamente os setores `A`, `B`, `C`, as 90 vagas e snapshots iniciais.

## Endpoints HTTP do backend

```http
GET /api/v1/health
GET /api/v1/map
GET /api/v1/sectors
GET /api/v1/sectors/:sectorId/spots
GET /api/v1/sectors/:sectorId/free-spots?limit=10
GET /api/v1/reports/turnover?sectorId=A&from=2026-04-29T00:00:00.000Z&to=2026-04-30T00:00:00.000Z
GET /api/v1/incidents?status=open
GET /api/v1/recommendation?fromSector=A
GET /api/v1/gateways
```

A recomendacao e registrada quando o setor de origem esta com `occupancyRate >= 0.90`.

Exemplo:

```json
{
  "fromSector": "A",
  "recommendedSector": "B",
  "reason": "Sector A at 93% occupancy; Sector B has 12 free spots",
  "ts": "2026-04-29T10:20:00.000Z"
}
```

## Endpoints HTTP do simulador

```http
GET /health
GET /sim/state
POST /sim/faults
DELETE /sim/faults/:spotId
POST /sim/fill-sector/:sectorId
POST /sim/reset
```

### Injetar `flapping`

```bash
curl -X POST http://localhost:4000/sim/faults \
  -H "Content-Type: application/json" \
  -d '{"sectorId":"A","spotId":"A-07","type":"flapping"}'
```

### Injetar `stuck_occupied` com tempo antigo para demo rapida

```bash
curl -X POST http://localhost:4000/sim/faults \
  -H "Content-Type: application/json" \
  -d '{"sectorId":"A","spotId":"A-08","type":"stuck_occupied","ageMinutes":400}'
```

### Injetar `stuck_free` com tempo antigo para demo rapida

```bash
curl -X POST http://localhost:4000/sim/faults \
  -H "Content-Type: application/json" \
  -d '{"sectorId":"B","spotId":"B-10","type":"stuck_free","ageMinutes":800}'
```

### Lotar setor A para testar recomendacao

```bash
curl -X POST http://localhost:4000/sim/fill-sector/A \
  -H "Content-Type: application/json" \
  -d '{"occupiedCount":28}'
```

Depois:

```bash
curl "http://localhost:3000/api/v1/recommendation?fromSector=A"
```

## Checks

Validacao estatica dos contratos principais da atividade:

```bash
npm run check
```

Smoke test e2e com a stack ja rodando em `localhost:3000` e `localhost:4000`:

```bash
npm run smoke:e2e
```

Com o banco rodando, os checks do modulo `backend/database` tambem podem usar `.env`.

Linux/WSL/bash:

```bash
cd backend/database
cp .env.example .env
npm install
npm run check:requirements
npm run check:db
```

Windows/PowerShell:

```powershell
cd backend/database
Copy-Item .env.example .env
npm install
npm run check:requirements
npm run check:db
```

Alternativa avancada, sem editar `backend/database/.env`:

Linux/WSL/bash:

```bash
DATABASE_URL="postgresql://parking:parking123@localhost:5432/monolith_parking" PGSSLMODE=disable npm run check:db
```

Windows/PowerShell:

```powershell
$env:DATABASE_URL="postgresql://parking:parking123@localhost:5432/monolith_parking"
$env:PGSSLMODE="disable"
npm run check:db
```

## Roteiro de demonstracao

1. Rodar `docker compose up --build`.
2. Rodar `npm run smoke:e2e` para validar o fluxo completo.
3. Mostrar logs do simulador publicando eventos MQTT.
4. Mostrar logs do backend consumindo eventos MQTT.
5. Acessar `GET /api/v1/map`.
6. Acessar `GET /api/v1/sectors`.
7. Acessar `GET /api/v1/gateways`.
8. Injetar `flapping` ou `stuck_occupied` em uma vaga.
9. Acessar `GET /api/v1/incidents?status=open`.
10. Lotar o setor `A` com `POST /sim/fill-sector/A`.
11. Acessar `GET /api/v1/recommendation?fromSector=A`.
12. Conferir registros no banco em `spot_events`, `gateway_status_events`, `incidents` e `recommendations_log`.

## Escopo atual

Este projeto entrega o MVP operacional: MQTT, HTTP, banco, incidentes e recomendacao por regra.
