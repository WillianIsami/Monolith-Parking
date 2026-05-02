# Arquitetura

```txt
Sensores virtuais -> Gateways virtuais -> MQTT Mosquitto -> Backend -> PostgreSQL -> API HTTP
```

## MQTT

O simulador publica eventos de vaga e status dos gateways. O backend assina os tópicos obrigatórios e processa os eventos recebidos.

## Backend

O backend valida o payload, aplica idempotência via banco, atualiza o estado atual da vaga, persiste histórico, calcula snapshots, detecta incidentes e expõe a API HTTP.

## Banco

O PostgreSQL armazena estado atual, histórico, snapshots, incidentes e recomendações.

## API

A API HTTP permite consultar mapa atual, disponibilidade por setor, vagas livres, turnover, incidentes e recomendação operacional.
