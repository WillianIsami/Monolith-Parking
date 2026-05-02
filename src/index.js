const handleMqttEvents = require('./mqtt/subscriber');

console.log('🚀 Iniciando Backend de Ingestão MQTT...');

// Inicia o "escutador" de eventos
handleMqttEvents();