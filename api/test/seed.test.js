import { describe, expect, it } from 'vitest';
import { DEFAULT_THRESHOLDS, insertReading, openDb } from '../src/db.js';
import { queryHistory } from '../src/history.js';
import { countRealReadings, generateReadings, seedHistory, SEED_DEVICES } from '../src/seed.js';
import { NOW } from './helpers.js';

const MINUTE = 60_000;

describe('generateReadings', () => {
  const rows = generateReadings({ end: NOW, days: 7 });

  it('makes 7 days of one-per-minute readings for each of the 3 devices', () => {
    expect(rows.length).toBe(7 * 1440 * 3);
    const gh = rows.filter((r) => r.deviceId === 'greenhouse');
    expect(gh.length).toBe(7 * 1440);
    for (let i = 1; i < gh.length; i++) expect(gh[i].ts - gh[i - 1].ts).toBe(MINUTE);
    expect(gh.at(-1).ts).toBeLessThan(NOW);
    expect(NOW - gh.at(-1).ts).toBeLessThanOrEqual(2 * MINUTE);
  });

  it('is deterministic for a given seed', () => {
    expect(generateReadings({ end: NOW, days: 1, seed: 7 })).toEqual(generateReadings({ end: NOW, days: 1, seed: 7 }));
    expect(generateReadings({ end: NOW, days: 1, seed: 7 })).not.toEqual(generateReadings({ end: NOW, days: 1, seed: 8 }));
  });

  it('has a visible daily cycle and stays in range apart from a few short spikes', () => {
    const t = DEFAULT_THRESHOLDS;
    const outside = rows.filter(
      (r) =>
        r.temperature > t.temperature.max ||
        r.temperature < t.temperature.min ||
        r.humidity > t.humidity.max ||
        r.humidity < t.humidity.min ||
        r.pressure < t.pressure.min ||
        r.pressure > t.pressure.max ||
        r.battery < t.battery.min,
    );
    // A few spikes of a few minutes each: some, but well under 1 %.
    expect(outside.length).toBeGreaterThan(5);
    expect(outside.length).toBeLessThan(rows.length * 0.01);
    expect(new Set(outside.map((r) => r.deviceId)).size).toBe(3);

    const gh = rows.filter((r) => r.deviceId === 'greenhouse').map((r) => r.temperature);
    const sorted = [...gh].sort((a, b) => a - b);
    const p05 = sorted[Math.floor(gh.length * 0.05)];
    const p95 = sorted[Math.floor(gh.length * 0.95)];
    expect(p95 - p05).toBeGreaterThan(4); // daily swing, not a flat line
    for (const r of rows) {
      expect(r.battery).toBeGreaterThanOrEqual(25);
      expect(r.battery).toBeLessThanOrEqual(100);
    }
  });

  it('ends close to the live simulator values so seeded and live data join up', () => {
    for (const d of SEED_DEVICES) {
      const last = rows.filter((r) => r.deviceId === d.id).at(-1);
      expect(Math.abs(last.temperature - d.temperature)).toBeLessThan(0.3);
      expect(Math.abs(last.humidity - d.humidity)).toBeLessThan(0.5);
      expect(Math.abs(last.battery - d.battery)).toBeLessThan(0.1);
    }
  });
});

describe('seedHistory', () => {
  it('fills an empty DB and the 7 d chart gets ~168 hourly points', () => {
    const db = openDb(':memory:');
    const res = seedHistory(db, { end: NOW });
    expect(res).toMatchObject({ ok: true, inserted: 30240, removed: 0, real: 0 });
    const h = queryHistory(db, { deviceId: 'greenhouse', from: NOW - 7 * 24 * 3600_000, to: NOW, bucket: '1h' });
    expect(h.points.length).toBeGreaterThanOrEqual(168);
    expect(h.points.length).toBeLessThanOrEqual(169);
    expect(countRealReadings(db)).toBe(0);
  });

  it('refuses to replace readings recorded by the API unless forced', () => {
    const db = openDb(':memory:');
    insertReading(db, { deviceId: 'greenhouse', ts: NOW - 1000, temperature: 21 });
    expect(seedHistory(db, { end: NOW })).toEqual({ ok: false, real: 1 });
    expect(db.prepare('SELECT COUNT(*) AS n FROM readings').get().n).toBe(1);

    const forced = seedHistory(db, { end: NOW, force: true });
    expect(forced).toMatchObject({ ok: true, removed: 1, real: 1 });
  });

  it('re-seeding over its own data is allowed; live readings after a seed count as real', () => {
    const db = openDb(':memory:');
    seedHistory(db, { end: NOW - 3600_000, days: 1 });
    expect(seedHistory(db, { end: NOW, days: 1 }).ok).toBe(true);

    insertReading(db, { deviceId: 'greenhouse', ts: NOW + 5000, temperature: 26 });
    expect(countRealReadings(db)).toBe(1);
    expect(seedHistory(db, { end: NOW + 60_000, days: 1 }).ok).toBe(false);
  });

  it('leaves users and thresholds alone', () => {
    const db = openDb(':memory:');
    db.prepare("UPDATE thresholds SET max = 24 WHERE sensor = 'temperature'").run();
    seedHistory(db, { end: NOW, days: 1 });
    expect(db.prepare("SELECT max FROM thresholds WHERE sensor = 'temperature'").get().max).toBe(24);
  });
});
