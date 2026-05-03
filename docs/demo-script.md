# Roteiro de demonstracao

1. Subir os servicos:

```bash
docker compose up --build
```

2. Conferir backend e simulador:

```bash
curl http://localhost:3000/api/v1/health
curl http://localhost:4000/health
```

3. Mostrar mapa, setores e gateways:

```bash
curl http://localhost:3000/api/v1/map
curl http://localhost:3000/api/v1/sectors
curl http://localhost:3000/api/v1/gateways
```

4. Injetar falha de flapping:

```bash
curl -X POST http://localhost:4000/sim/faults \
  -H "Content-Type: application/json" \
  -d '{"sectorId":"A","spotId":"A-07","type":"flapping"}'
```

5. Conferir incidente:

```bash
curl "http://localhost:3000/api/v1/incidents?status=open"
```

6. Injetar sensor travado ocupado para demo rapida:

```bash
curl -X POST http://localhost:4000/sim/faults \
  -H "Content-Type: application/json" \
  -d '{"sectorId":"A","spotId":"A-08","type":"stuck_occupied","ageMinutes":400}'
```

7. Conferir incidente novamente:

```bash
curl "http://localhost:3000/api/v1/incidents?status=open"
```

8. Lotar setor A:

```bash
curl -X POST http://localhost:4000/sim/fill-sector/A \
  -H "Content-Type: application/json" \
  -d '{"occupiedCount":28}'
```

9. Conferir recomendacao:

```bash
curl "http://localhost:3000/api/v1/recommendation?fromSector=A"
```

10. Conferir banco, se desejar:

```bash
cd backend/database
npm run check:db
```
