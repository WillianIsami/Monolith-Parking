# Roteiro de demonstracao

1. Subir os servicos:

Se ainda nao existir `.env`, copie o exemplo antes de subir a stack:

```bash
cp .env.example .env
```

No PowerShell, use:

```powershell
Copy-Item .env.example .env
```

```bash
docker compose up --build
```

No Windows com WSL, se `docker` nao existir dentro do terminal WSL, habilite a integracao da distro em `Docker Desktop > Settings > Resources > WSL Integration`.

2. Rodar o smoke e2e automatizado:

```bash
npm run smoke:e2e
```

3. Conferir backend e simulador manualmente:

```bash
curl http://localhost:3000/api/v1/health
curl http://localhost:4000/health
```

4. Mostrar mapa, setores e gateways:

```bash
curl http://localhost:3000/api/v1/map
curl http://localhost:3000/api/v1/sectors
curl http://localhost:3000/api/v1/gateways
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

7. Injetar sensor travado ocupado para demo rapida:

```bash
curl -X POST http://localhost:4000/sim/faults \
  -H "Content-Type: application/json" \
  -d '{"sectorId":"A","spotId":"A-08","type":"stuck_occupied","ageMinutes":400}'
```

8. Conferir incidente novamente:

```bash
curl "http://localhost:3000/api/v1/incidents?status=open"
```

9. Lotar setor A:

```bash
curl -X POST http://localhost:4000/sim/fill-sector/A \
  -H "Content-Type: application/json" \
  -d '{"occupiedCount":28}'
```

10. Conferir recomendacao:

```bash
curl "http://localhost:3000/api/v1/recommendation?fromSector=A"
```

11. Conferir banco, se desejar:

```bash
cd backend/database
cp .env.example .env
npm run check:db
```
