import { createApp } from '../src/app.js';
import { insertReading, openDb, seedUsers } from '../src/db.js';

export const ADMIN = { email: 'admin@example.com', password: 'admin-test-pass' };
export const VIEWER = { email: 'viewer@example.com', password: 'viewer-test-pass' };
export const SECRET = 'test-secret-that-is-long-enough-for-hs256-0123456789';

/** Fixed "now" so bucketing and expiry are deterministic. */
export const NOW = Date.parse('2026-11-18T12:00:00.000Z');

export function makeApp({ now = () => NOW, ttl = 1800 } = {}) {
  const db = openDb(':memory:');
  seedUsers(db, {
    adminEmail: ADMIN.email,
    adminPassword: ADMIN.password,
    viewerEmail: VIEWER.email,
    viewerPassword: VIEWER.password,
    cost: 4,
  });
  const app = createApp({
    db,
    config: { jwtSecret: SECRET, tokenTtlSeconds: ttl },
    now,
    log: () => {},
  });
  return { app, db };
}

/** One reading per second for `seconds`, ending just before `end`. */
export function seed(db, { deviceId = 'greenhouse', end = NOW, seconds = 3600, temp = (i) => 20 + (i % 10) } = {}) {
  db.exec('BEGIN');
  for (let i = 0; i < seconds; i++) {
    const ts = end - (seconds - i) * 1000;
    insertReading(db, { deviceId, ts, temperature: temp(i), humidity: 50, pressure: 1013, battery: 90 });
  }
  db.exec('COMMIT');
}
