# Exemplos de API

## Health

```bash
curl http://localhost:3000/api/v1/health
```

## Mapa atual

```bash
curl http://localhost:3000/api/v1/map
```

## Setores

```bash
curl http://localhost:3000/api/v1/sectors
```

## Vagas de um setor

```bash
curl http://localhost:3000/api/v1/sectors/A/spots
```

## Vagas livres

```bash
curl "http://localhost:3000/api/v1/sectors/A/free-spots?limit=10"
```

## Turnover

```bash
curl "http://localhost:3000/api/v1/reports/turnover?sectorId=A&from=2026-04-29T00:00:00.000Z&to=2026-04-30T00:00:00.000Z"
```

## Incidentes

```bash
curl "http://localhost:3000/api/v1/incidents?status=open"
```

## Recomendação

```bash
curl "http://localhost:3000/api/v1/recommendation?fromSector=A"
```

## Injetar flapping no simulador

```bash
curl -X POST http://localhost:4000/sim/faults \
  -H "Content-Type: application/json" \
  -d '{"sectorId":"A","spotId":"A-07","type":"flapping"}'
```

## Lotar setor A

```bash
curl -X POST http://localhost:4000/sim/fill-sector/A \
  -H "Content-Type: application/json" \
  -d '{"occupiedCount":28}'
```
