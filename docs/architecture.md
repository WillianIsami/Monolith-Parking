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

O simulador Node.js cria 90 sensores virtuais e 3 gateways. Ele publica eventos de vaga e status dos gateways em tópicos MQTT e também oferece endpoints HTTP para demonstração e injeção de falhas.

## MQTT

Tópicos usados:

```txt
campus/parking/sectors/<sectorId>/spots/<spotId>/events
campus/parking/sectors/<sectorId>/gateway/status
```

## Backend

O backend:

- assina os tópicos MQTT;
- valida o payload;
- aplica idempotência por `eventId`;
- atualiza o estado atual da vaga;
- persiste histórico;
- registra status de gateways;
- detecta incidentes;
- gera recomendações por regra;
- expõe a API HTTP REST.

## Banco

O PostgreSQL armazena:

- setores e vagas;
- histórico de eventos;
- status dos gateways;
- snapshots de ocupação;
- incidentes;
- recomendações.

## API

A API HTTP permite consultar mapa atual, disponibilidade por setor, vagas livres, turnover, incidentes, gateways e recomendação operacional.

## Fora do MVP Atual

Dashboard web, app mobile, Swagger e modelos preditivos não fazem parte desta entrega.
