'use strict';
// Simulated sensor telemetry publisher. All data is generated; no real sensors.
//
// Topics (prefix defaults to "sensors"):
//   <prefix>/<deviceId>/telemetry  JSON every interval (default 1 s)
//   <prefix>/<deviceId>/status     retained "online" / "offline" (offline is also the MQTT last will)
//   <prefix>/_control/spike        send a device id (or "all") to trigger a spike
//
// Usage:
//   node src/simulator.js [--url mqtt://127.0.0.1:1883] [--prefix sensors]
//                         [--interval 1000] [--spike <deviceId|all>] [--no-random-spikes]

const mqtt = require('mqtt');

const DEVICES = [
  { id: 'greenhouse', temperature: 26, humidity: 70, pressure: 1012, battery: 96 },
  { id: 'warehouse', temperature: 18, humidity: 45, pressure: 1015, battery: 81 },
  { id: 'server-room', temperature: 22, humidity: 35, pressure: 1013, battery: 64 },
];

// Per-sensor random-walk tuning: step size, clamp range and spike offset.
const SENSORS = {
  temperature: { step: 0.15, min: -20, max: 80, spike: 18, decimals: 1 },
  humidity: { step: 0.6, min: 0, max: 100, spike: 25, decimals: 1 },
  pressure: { step: 0.4, min: 900, max: 1100, spike: -30, decimals: 1 },
};

const SPIKE_TICKS = 6;
const RANDOM_SPIKE_PROBABILITY = 0.004; // per device per tick: roughly one every ~4 min per device

function round(v, d) {
  const f = 10 ** d;
  return Math.round(v * f) / f;
}

function gaussian(rand) {
  // Box–Muller transform.
  const u = 1 - rand();
  const v = rand();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

/** Pure state machine for one device, so it can be tested without MQTT. */
class DeviceModel {
  constructor(def, rand = Math.random) {
    this.id = def.id;
    this.base = { temperature: def.temperature, humidity: def.humidity, pressure: def.pressure };
    this.values = { ...this.base };
    this.battery = def.battery;
    this.spikeTicksLeft = 0;
    this.rand = rand;
  }

  triggerSpike() {
    this.spikeTicksLeft = SPIKE_TICKS;
  }

  /** Advance one tick and return the telemetry payload object. */
  tick(now = new Date()) {
    for (const [name, cfg] of Object.entries(SENSORS)) {
      const meanReversion = (this.base[name] - this.values[name]) * 0.05;
      let v = this.values[name] + meanReversion + gaussian(this.rand) * cfg.step;
      v = Math.min(cfg.max, Math.max(cfg.min, v));
      this.values[name] = v;
    }

    // Battery drains slowly and "recharges" when low, so the demo never runs flat.
    this.battery -= 0.01 + this.rand() * 0.01;
    if (this.battery < 12) this.battery = 100;

    const out = {};
    for (const [name, cfg] of Object.entries(SENSORS)) {
      let v = this.values[name];
      if (this.spikeTicksLeft > 0) v += cfg.spike;
      out[name] = round(Math.min(cfg.max, Math.max(cfg.min, v)), cfg.decimals);
    }
    if (this.spikeTicksLeft > 0) this.spikeTicksLeft -= 1;

    return {
      deviceId: this.id,
      temperature: out.temperature,
      humidity: out.humidity,
      pressure: out.pressure,
      battery: round(this.battery, 1),
      timestamp: now.toISOString(),
    };
  }
}

/**
 * Start the simulator. One MQTT client per device so each one has its own
 * retained last-will "offline" status.
 */
async function startSimulator(opts = {}) {
  const url = opts.url ?? 'mqtt://127.0.0.1:1883';
  const prefix = opts.prefix ?? 'sensors';
  const interval = opts.interval ?? 1000;
  const randomSpikes = opts.randomSpikes ?? true;
  const log = opts.log ?? (() => {});

  const models = DEVICES.map((d) => new DeviceModel(d));
  const clients = await Promise.all(
    models.map(
      (m) =>
        new Promise((resolve, reject) => {
          const statusTopic = `${prefix}/${m.id}/status`;
          const client = mqtt.connect(url, {
            clientId: `sim-${m.id}-${process.pid}-${Math.random().toString(16).slice(2, 8)}`,
            will: { topic: statusTopic, payload: 'offline', qos: 1, retain: true },
            reconnectPeriod: 1000,
          });
          client.once('connect', () => {
            client.publish(statusTopic, 'online', { qos: 1, retain: true });
            resolve(client);
          });
          client.on('reconnect', () => log(`${m.id}: reconnecting`));
          client.on('connect', () => client.publish(statusTopic, 'online', { qos: 1, retain: true }));
          client.once('error', reject);
        }),
    ),
  );

  // The first client also listens for spike commands.
  const control = clients[0];
  control.subscribe(`${prefix}/_control/spike`);
  control.on('message', (_topic, payload) => {
    const target = payload.toString().trim();
    for (const m of models) {
      if (target === 'all' || target === m.id) {
        m.triggerSpike();
        log(`spike triggered on ${m.id}`);
      }
    }
  });

  const timer = setInterval(() => {
    models.forEach((m, i) => {
      if (randomSpikes && Math.random() < RANDOM_SPIKE_PROBABILITY) {
        m.triggerSpike();
        log(`random spike on ${m.id}`);
      }
      const payload = m.tick();
      clients[i].publish(`${prefix}/${m.id}/telemetry`, JSON.stringify(payload), { qos: 0 });
    });
  }, interval);

  log(`publishing ${models.length} devices to ${url} under "${prefix}/" every ${interval} ms`);

  return {
    models,
    spike(target) {
      for (const m of models) if (target === 'all' || target === m.id) m.triggerSpike();
    },
    async stop() {
      clearInterval(timer);
      await Promise.all(
        clients.map(
          (c, i) =>
            new Promise((resolve) => {
              c.publish(`${prefix}/${models[i].id}/status`, 'offline', { qos: 1, retain: true }, () =>
                c.end(false, {}, resolve),
              );
            }),
        ),
      );
    },
  };
}

function parseArgs(argv) {
  const get = (name, fallback) => {
    const i = argv.indexOf(name);
    return i > -1 && argv[i + 1] !== undefined ? argv[i + 1] : fallback;
  };
  return {
    url: get('--url', 'mqtt://127.0.0.1:1883'),
    prefix: get('--prefix', 'sensors'),
    interval: Number(get('--interval', 1000)),
    spike: get('--spike', null),
    randomSpikes: !argv.includes('--no-random-spikes'),
  };
}

module.exports = { DeviceModel, DEVICES, startSimulator, parseArgs };

if (require.main === module) {
  const args = parseArgs(process.argv.slice(2));
  startSimulator({ ...args, log: (m) => console.log(`[sim] ${m}`) })
    .then((sim) => {
      if (args.spike) {
        setTimeout(() => {
          sim.spike(args.spike);
          console.log(`[sim] --spike: spike triggered on ${args.spike}`);
        }, 3000);
      }
      const stop = async () => {
        console.log('[sim] stopping, publishing offline status');
        await sim.stop();
        process.exit(0);
      };
      process.on('SIGINT', stop);
      process.on('SIGTERM', stop);
    })
    .catch((err) => {
      console.error(`[sim] could not connect: ${err.message}. Is the broker running (npm run broker)?`);
      process.exit(1);
    });
}
