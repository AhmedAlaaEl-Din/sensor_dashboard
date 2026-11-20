// Simulated history for demos: N days of one-per-minute readings for the three demo devices,
// with smooth daily cycles, slow weather drift, small noise and a few short spikes.
// All values are made up. Used by scripts/seed-history.js.

const MINUTE = 60_000;
const DAY = 24 * 60 * MINUTE;

/** Matches the live simulator (broker/src/simulator.js) so seeded and live data join up. */
export const SEED_DEVICES = [
  // amp = daily swing (half peak-to-peak); humidity moves opposite to temperature.
  { id: 'greenhouse', temperature: 26, tempAmp: 3.5, humidity: 70, humAmp: 8, pressure: 1012, battery: 96 },
  { id: 'warehouse', temperature: 18, tempAmp: 2.5, humidity: 45, humAmp: 6, pressure: 1015, battery: 81 },
  { id: 'server-room', temperature: 22, tempAmp: 0.8, humidity: 35, humAmp: 3, pressure: 1013, battery: 64 },
];

/**
 * Spikes as [daysBeforeEnd, durationMinutes, sensor, delta]. They cross the default thresholds
 * (temperature max 35, humidity max 85, pressure min 985) so history shows real alert moments.
 * None are in the last 6 hours, so the end of the seed joins the live data smoothly.
 */
const SPIKES = {
  greenhouse: [
    [5.4, 9, 'temperature', 12],
    [1.7, 6, 'humidity', 22],
  ],
  warehouse: [[3.3, 12, 'pressure', -32]],
  'server-room': [
    [4.6, 7, 'temperature', 16],
    [0.9, 5, 'temperature', 14],
  ],
};

const BATTERY_DRAIN_PER_MIN = 0.006; // about 8.6 % per day
const BATTERY_LOW = 25; // "recharged" to 100 when it would drop below this

/** Small deterministic PRNG (mulberry32) so a given --seed always gives the same data. */
function prng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const round = (v, d) => Math.round(v * 10 ** d) / 10 ** d;
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

/** Local hour of day as a fraction (0–24), so the warmest point is mid-afternoon on the user's clock. */
function localHour(ts) {
  const d = new Date(ts);
  return d.getHours() + d.getMinutes() / 60;
}

/**
 * Generates readings ending one minute before `end` (inclusive range of `days`).
 * Returns rows like { deviceId, ts, temperature, humidity, pressure, battery }.
 */
export function generateReadings({ end = Date.now(), days = 7, seed = 42, devices = SEED_DEVICES } = {}) {
  const lastTs = Math.floor(end / MINUTE) * MINUTE - MINUTE;
  const count = Math.round((days * DAY) / MINUTE);
  const firstTs = lastTs - (count - 1) * MINUTE;
  const rows = [];

  devices.forEach((dev, di) => {
    const rand = prng(seed + di * 1000);
    const spikes = (SPIKES[dev.id] ?? []).map(([before, dur, sensor, delta]) => {
      const start = Math.floor((lastTs - before * DAY) / MINUTE) * MINUTE;
      return { start, end: start + dur * MINUTE, sensor, delta };
    });
    // Slow random walks (mean-reverting) on top of the daily cycle.
    const walk = { temperature: 0, humidity: 0, pressure: 0 };
    const weatherPhase = rand() * 2 * Math.PI;

    for (let i = 0; i < count; i++) {
      const ts = firstTs + i * MINUTE;
      // Daily cycle: coolest around 05:00, warmest around 15:00 local time.
      const cycle = Math.sin(((localHour(ts) - 9) / 24) * 2 * Math.PI);
      walk.temperature += (rand() - 0.5) * 0.08 - walk.temperature * 0.01;
      walk.humidity += (rand() - 0.5) * 0.3 - walk.humidity * 0.01;
      walk.pressure += (rand() - 0.5) * 0.1 - walk.pressure * 0.005;
      const weather = Math.sin((ts / (3.3 * DAY)) * 2 * Math.PI + weatherPhase) * 5;

      let temperature = dev.temperature + dev.tempAmp * cycle + walk.temperature;
      let humidity = dev.humidity - dev.humAmp * cycle + walk.humidity;
      let pressure = dev.pressure + weather + walk.pressure;

      // Ease the last 3 hours toward the live simulator's starting values (no jump at "now").
      const toEnd = lastTs - ts;
      if (toEnd < 3 * 60 * MINUTE) {
        const w = 1 - toEnd / (3 * 60 * MINUTE);
        temperature += (dev.temperature - temperature) * w;
        humidity += (dev.humidity - humidity) * w;
        pressure += (dev.pressure - pressure) * w;
      }

      // Per-reading sensor noise, added after the easing so the last hours aren't a flat staircase.
      temperature += (rand() - 0.5) * 0.25;
      humidity += (rand() - 0.5) * 0.8;
      pressure += (rand() - 0.5) * 0.3;

      // Short spikes: ramp up for a third, hold, ramp down for a third.
      const values = { temperature, humidity, pressure };
      for (const s of spikes) {
        if (ts < s.start || ts >= s.end) continue;
        const p = (ts - s.start) / (s.end - s.start);
        const shape = Math.min(1, p * 3, (1 - p) * 3);
        values[s.sensor] += s.delta * shape;
      }

      // Battery: count backwards from the device's current level, "recharged" when low.
      const range = 100 - BATTERY_LOW;
      const used = ((lastTs - ts) / MINUTE) * BATTERY_DRAIN_PER_MIN;
      let battery = dev.battery + used;
      if (battery > 100) battery = BATTERY_LOW + ((battery - 100) % range);

      rows.push({
        deviceId: dev.id,
        ts,
        temperature: round(clamp(values.temperature, -20, 80), 1),
        humidity: round(clamp(values.humidity, 0, 100), 1),
        pressure: round(clamp(values.pressure, 900, 1100), 1),
        battery: round(battery, 1),
      });
    }
  });
  return rows;
}

/** Number of readings in the DB that the seed did not write (i.e. recorded by the API). */
export function countRealReadings(db) {
  const marker = db.prepare("SELECT value FROM meta WHERE key = 'seed_until'").get();
  if (!marker) return db.prepare('SELECT COUNT(*) AS n FROM readings').get().n;
  return db.prepare('SELECT COUNT(*) AS n FROM readings WHERE ts > ?').get(Number(marker.value)).n;
}

/**
 * Replaces all readings with seeded ones. Refuses (returns { ok: false }) when the DB holds
 * readings the API recorded, unless `force` is set. Users and thresholds are not touched.
 */
export function seedHistory(db, { end = Date.now(), days = 7, seed = 42, force = false } = {}) {
  const real = countRealReadings(db);
  if (real > 0 && !force) return { ok: false, real };

  const rows = generateReadings({ end, days, seed });
  const ins = db.prepare(
    `INSERT INTO readings (device_id, ts, temperature, humidity, pressure, battery)
     VALUES (?, ?, ?, ?, ?, ?)`,
  );
  const dev = db.prepare(
    `INSERT INTO devices (id, online, last_seen) VALUES (?, 0, ?)
     ON CONFLICT(id) DO UPDATE SET last_seen = excluded.last_seen`,
  );
  const meta = db.prepare(
    'INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
  );
  const until = rows.reduce((m, r) => Math.max(m, r.ts), 0);

  db.exec('BEGIN');
  try {
    const removed = Number(db.prepare('DELETE FROM readings').run().changes);
    for (const r of rows) ins.run(r.deviceId, r.ts, r.temperature, r.humidity, r.pressure, r.battery);
    for (const d of SEED_DEVICES) dev.run(d.id, until);
    meta.run('seed_until', String(until));
    meta.run('seeded_at', new Date(end).toISOString());
    db.exec('COMMIT');
    return { ok: true, inserted: rows.length, removed, real, from: rows[0]?.ts, until };
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}
