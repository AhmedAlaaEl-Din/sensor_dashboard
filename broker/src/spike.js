'use strict';
// Trigger a spike on an already-running simulator.
// Usage: node src/spike.js <deviceId|all> [--url mqtt://127.0.0.1:1883] [--prefix sensors]

const mqtt = require('mqtt');
const { parseArgs } = require('./simulator');

const argv = process.argv.slice(2);
const target = argv[0] && !argv[0].startsWith('--') ? argv[0] : 'all';
const { url, prefix } = parseArgs(argv);

const client = mqtt.connect(url, { reconnectPeriod: 0, connectTimeout: 3000 });
client.on('connect', () => {
  client.publish(`${prefix}/_control/spike`, target, { qos: 1 }, () => {
    console.log(`[spike] requested spike on "${target}"`);
    client.end();
  });
});
client.on('error', (err) => {
  console.error(`[spike] could not connect: ${err.message}`);
  process.exit(1);
});
