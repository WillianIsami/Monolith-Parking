# Monolith Parking

MVP de estacionamento inteligente para campus com simulador Node.js, MQTT, backend HTTP REST, PostgreSQL e detecção de incidentes.

O projeto trabalha com 3 setores fixos (`A`, `B`, `C`), 30 vagas por setor e 90 vagas no total (`A-01..A-30`, `B-01..B-30`, `C-01..C-30`). O simulador publica eventos de sensores e gateways via MQTT; o backend valida, persiste e expõe consultas HTTP para mapa, disponibilidade, incidentes, rotatividade e recomendação de setor.

![Arquitetura do Monolith Parking](arquitetura.png)

## Estado Atual

- Simulador com 90 sensores virtuais e 3 gateways.
- Publicação MQTT de eventos de vaga e status de gateway.
- Falhas injetáveis: `stuck_occupied`, `stuck_free` e `flapping`.
- Backend Express com subscriber MQTT e API REST.
- Persistência PostgreSQL com idempotência por `eventId`.
- Tabelas obrigatórias da atividade implementadas.
- Snapshots de ocupação por setor.
- Incidentes e recomendações persistidos.
- Docker Compose com PostgreSQL, Mosquitto, backend, simulador e Adminer opcional.

## Arquitetura

```txt
Simulador Node.js
90 sensores virtuais + 3 gateways
        |
        | MQTT
        v
Eclipse Mosquitto
        |
        | Subscriber MQTT
        v
Backend Node.js / Express
        |
        | SQL
        v
PostgreSQL
        |
        | HTTP REST
        v
Clientes de teste, dashboard ou integrações
```

## Tecnologias

- Node.js 20
- Express
- MQTT.js
- Eclipse Mosquitto
- PostgreSQL 16
- Docker Compose
- Adminer opcional

## Como Rodar com Docker

Pré-requisitos:

- Docker Desktop no Windows com integração WSL 2 habilitada, ou Docker Engine no Linux.
- Node.js 18+ apenas se for rodar os checks fora dos containers.

PowerShell:

```powershell
Copy-Item .env.example .env
docker compose up --build
```

Bash/WSL/Linux:

```bash
cp .env.example .env
docker compose up --build
```

Se já existia um volume antigo do PostgreSQL, recrie o banco para aplicar o schema atualizado:

```bash
docker compose down -v
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

## Como Rodar Manualmente

O modo manual usa Node.js local para backend e simulador. PostgreSQL e Mosquitto ainda precisam estar disponíveis.

1. Instale as dependências:

```bash
npm install
```

2. Configure o `.env` da raiz:

```bash
cp .env.example .env
```

No PowerShell:

```powershell
Copy-Item .env.example .env
```

3. Suba somente a infraestrutura:

```bash
docker compose up -d postgres mosquitto
```

4. Inicie o backend:

```bash
npm run start:backend
```

5. Em outro terminal, inicie o simulador:

```bash
npm run start:simulator
```

## Variáveis Principais

| Variável | Uso |
| --- | --- |
| `PORT` | Porta HTTP do backend |
| `DATABASE_URL` | URL de conexão PostgreSQL usada pelo backend |
| `PGSSLMODE` | Modo SSL do PostgreSQL |
| `MQTT_BROKER_URL` | URL do broker MQTT |
| `SIMULATOR_PORT` | Porta HTTP do simulador |
| `SIMULATED_MINUTE_MS` | Duração de um minuto simulado |
| `SIMULATOR_TICK_MS` | Intervalo de atualização do simulador |
| `GATEWAY_STATUS_INTERVAL_MS` | Intervalo de heartbeat dos gateways |

Os valores reais devem ficar em `.env`. O repositório versiona apenas arquivos `.env.example`.

## Contratos MQTT

Evento de vaga:

```txt
campus/parking/sectors/<sectorId>/spots/<spotId>/events
```

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

Status de gateway:

```txt
campus/parking/sectors/<sectorId>/gateway/status
```

```json
{
  "ts": "2026-04-29T10:15:30.000Z",
  "sectorId": "A",
  "gatewayId": "gateway-A",
  "status": "ONLINE",
  "source": "gateway"
}
```

## Banco de Dados

O banco oficial é PostgreSQL. A documentação exclusiva do módulo está em `backend/database/README.md`.

Tabelas centrais:

| Tabela | Responsabilidade |
| --- | --- |
| `sectors` | Cadastro dos setores `A`, `B` e `C` |
| `spots` | Estado atual de cada vaga |
| `spot_events` | Histórico bruto dos eventos MQTT |
| `gateway_status_events` | Histórico de saúde dos gateways |
| `sector_snapshots` | Ocupação agregada por setor e minuto |
| `incidents` | Incidentes operacionais e evidências |
| `recommendations_log` | Recomendações emitidas pela API |

Funções de integração:

| Função | Uso |
| --- | --- |
| `apply_spot_event(...)` | Persiste evento de vaga, garante idempotência e atualiza `spots` |
| `record_gateway_status(...)` | Persiste heartbeat/status dos gateways |
| `get_sector_occupancy(...)` | Retorna ocupação atual |
| `get_free_spots(...)` | Lista vagas livres |
| `get_turnover_report(...)` | Calcula rotatividade |
| `open_incident(...)` | Abre incidente sem duplicar incidente aberto equivalente |
| `log_recommendation(...)` | Registra recomendação |

## Endpoints do Backend

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
POST /api/v1/admin/check-incidents
```

## Endpoints do Simulador

```http
GET /health
GET /sim/state
POST /sim/faults
DELETE /sim/faults/:spotId
POST /sim/fill-sector/:sectorId
POST /sim/reset
```

Exemplo para lotar o setor `A` e testar recomendação:

```bash
curl -X POST http://localhost:4000/sim/fill-sector/A \
  -H "Content-Type: application/json" \
  -d '{"occupiedCount":28}'

curl "http://localhost:3000/api/v1/recommendation?fromSector=A"
```

## Checks

Validação estática dos contratos principais:

```bash
npm run check
```

Smoke test com a stack rodando:

```bash
npm run smoke:e2e
```

Checks específicos do banco:

```bash
cd backend/database
npm install
npm run check:requirements
npm run check:db
```

## Demonstração Sugerida

1. Rodar `docker compose up --build`.
2. Executar `npm run smoke:e2e`.
3. Mostrar logs do simulador publicando MQTT.
4. Mostrar logs do backend consumindo MQTT.
5. Consultar `GET /api/v1/map`, `GET /api/v1/sectors` e `GET /api/v1/gateways`.
6. Injetar `flapping` ou `stuck_occupied` pelo simulador.
7. Consultar `GET /api/v1/incidents?status=open`.
8. Lotar o setor `A` e consultar `GET /api/v1/recommendation?fromSector=A`.
9. Conferir registros no PostgreSQL.

## Escopo do MVP

Esta entrega cobre o fluxo operacional completo de sensores virtuais, MQTT, backend, banco, incidentes e recomendação por regra. Dashboard web, app mobile, Swagger e modelos preditivos ficam fora do escopo atual.
