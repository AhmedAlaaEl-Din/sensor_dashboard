'use strict';
// Smoke test: start the broker on a random loopback port, start the simulator,
// and check that telemetry, retained status and the spike command all work.

const test = require('node:test');
const assert = require('node:assert/strict');
const mqtt = require('mqtt');
const { startBroker } = require('../src/broker');
const { startSimulator, DeviceModel, DEVICES } = require('../src/simulator');

function waitFor(predicate, timeoutMs, label) {
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const t = setInterval(() => {
      if (predicate()) {
        clearInterval(t);
        resolve();
      } else if (Date.now() - started > timeoutMs) {
        clearInterval(t);
        reject(new Error(`timed out waiting for ${label}`));
      }
    }, 20);
  });
}

test('broker refuses to bind to a non-loopback address', async () => {
  await assert.rejects(startBroker({ host: '0.0.0.0', port: 0 }), /local-only/);
});

test('DeviceModel produces valid telemetry and spikes raise temperature', () => {
  let seed = 1;
  const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const m = new DeviceModel(DEVICES[0], rand);
  const normal = m.tick(new Date('2026-01-01T00:00:00Z'));
  assert.equal(normal.deviceId, 'greenhouse');
  for (const k of ['temperature', 'humidity', 'pressure', 'battery']) {
    assert.equal(typeof normal[k], 'number', k);
  }
  assert.equal(normal.timestamp, '2026-01-01T00:00:00.000Z');
  assert.ok(normal.humidity >= 0 && normal.humidity <= 100);
  m.triggerSpike();
  const spiked = m.tick();
  assert.ok(spiked.temperature > normal.temperature + 10, 'spike should add ~18 °C');
});

test('broker + simulator end-to-end', async (t) => {
  const broker = await startBroker({ port: 0 });
  const url = `mqtt://127.0.0.1:${broker.port}`;
  const sim = await startSimulator({ url, interval: 100, randomSpikes: false });

  const telemetry = new Map();
  const status = new Map();
  const sub = mqtt.connect(url);
  t.after(async () => {
    await new Promise((r) => sub.end(false, {}, r));
    await sim.stop().catch(() => {});
    await broker.close();
  });

  await new Promise((r) => sub.once('connect', r));
  sub.on('message', (topic, payload) => {
    const [, id, kind] = topic.split('/');
    if (kind === 'telemetry') {
      const list = telemetry.get(id) ?? [];
      list.push(JSON.parse(payload.toString()));
      telemetry.set(id, list);
    } else if (kind === 'status') {
      status.set(id, payload.toString());
    }
  });
  await new Promise((r) => sub.subscribe('sensors/+/+', r));

  await waitFor(() => DEVICES.every((d) => (telemetry.get(d.id) ?? []).length >= 3), 5000, 'telemetry');
  await waitFor(() => DEVICES.every((d) => status.get(d.id) === 'online'), 2000, 'retained online status');

  const sample = telemetry.get('warehouse').at(-1);
  assert.deepEqual(Object.keys(sample).sort(), [
    'battery', 'deviceId', 'humidity', 'pressure', 'temperature', 'timestamp',
  ]);

  // Spike via the control topic (the same path `npm run spike` uses).
  const before = telemetry.get('server-room').at(-1).temperature;
  sub.publish('sensors/_control/spike', 'server-room');
  await waitFor(
    () => telemetry.get('server-room').some((p) => p.temperature > before + 10),
    3000,
    'spiked temperature',
  );

  await sim.stop();
  await waitFor(() => DEVICES.every((d) => status.get(d.id) === 'offline'), 2000, 'offline status');
});
