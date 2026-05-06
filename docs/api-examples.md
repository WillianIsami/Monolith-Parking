# Exemplos de API

## Backend

```bash
curl http://localhost:3000/api/v1/health
curl http://localhost:3000/api/v1/map
curl http://localhost:3000/api/v1/sectors
curl http://localhost:3000/api/v1/sectors/A/spots
curl "http://localhost:3000/api/v1/sectors/A/free-spots?limit=10"
curl "http://localhost:3000/api/v1/reports/turnover?sectorId=A&from=2026-04-29T00:00:00.000Z&to=2026-04-30T00:00:00.000Z"
curl "http://localhost:3000/api/v1/incidents?status=open"
curl "http://localhost:3000/api/v1/recommendation?fromSector=A"
curl http://localhost:3000/api/v1/gateways
```

## Simulador

```bash
curl http://localhost:4000/health
curl http://localhost:4000/sim/state
```

## Injetar flapping

```bash
curl -X POST http://localhost:4000/sim/faults \
  -H "Content-Type: application/json" \
  -d '{"sectorId":"A","spotId":"A-07","type":"flapping"}'
```

## Injetar stuck_occupied para demo rápida

```bash
curl -X POST http://localhost:4000/sim/faults \
  -H "Content-Type: application/json" \
  -d '{"sectorId":"A","spotId":"A-08","type":"stuck_occupied","ageMinutes":400}'
```

## Injetar stuck_free para demo rápida

```bash
curl -X POST http://localhost:4000/sim/faults \
  -H "Content-Type: application/json" \
  -d '{"sectorId":"B","spotId":"B-10","type":"stuck_free","ageMinutes":800}'
```

## Lotar setor A

```bash
curl -X POST http://localhost:4000/sim/fill-sector/A \
  -H "Content-Type: application/json" \
  -d '{"occupiedCount":28}'
```

## Resetar simulador

```bash
curl -X POST http://localhost:4000/sim/reset
```
