# Roteiro de demonstração

1. Subir os serviços:

```bash
docker compose up --build
```

2. Conferir o backend:

```bash
curl http://localhost:3000/api/v1/health
```

3. Conferir o simulador:

```bash
curl http://localhost:4000/health
```

4. Ver mapa e setores:

```bash
curl http://localhost:3000/api/v1/map
curl http://localhost:3000/api/v1/sectors
```

5. Injetar falha de flapping:

```bash
curl -X POST http://localhost:4000/sim/faults \
  -H "Content-Type: application/json" \
  -d '{"sectorId":"A","spotId":"A-07","type":"flapping"}'
```

6. Conferir incidente:

```bash
curl "http://localhost:3000/api/v1/incidents?status=open"
```

7. Lotar setor A:

```bash
curl -X POST http://localhost:4000/sim/fill-sector/A \
  -H "Content-Type: application/json" \
  -d '{"occupiedCount":28}'
```

8. Conferir recomendação:

```bash
curl "http://localhost:3000/api/v1/recommendation?fromSector=A"
```
