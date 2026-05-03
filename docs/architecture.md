# Arquitetura

```txt
Sensores virtuais
  -> Gateways virtuais
  -> MQTT Mosquitto
  -> Backend Node.js/Express
  -> PostgreSQL
  -> API HTTP REST
```

## Simulador

O simulador Node.js cria 90 sensores virtuais e 3 gateways. Ele publica eventos de vaga e status dos gateways em topicos MQTT e tambem oferece endpoints HTTP para demo e injecao de falhas.

## MQTT

Topicos usados:

```txt
campus/parking/sectors/<sectorId>/spots/<spotId>/events
campus/parking/sectors/<sectorId>/gateway/status
```

## Backend

O backend:

- assina os topicos MQTT;
- valida o payload;
- aplica idempotencia por `eventId`;
- atualiza o estado atual da vaga;
- persiste historico;
- registra status de gateways;
- detecta incidentes;
- gera recomendacoes por regra;
- expoe a API HTTP REST.

## Banco

O PostgreSQL armazena:

- setores e vagas;
- historico de eventos;
- status dos gateways;
- snapshots de ocupacao;
- incidentes;
- recomendacoes.

## API

A API HTTP permite consultar mapa atual, disponibilidade por setor, vagas livres, turnover, incidentes, gateways e recomendacao operacional.

## Fora do MVP atual

Dashboard web, app mobile, Swagger e modelos preditivos nao fazem parte desta entrega.
