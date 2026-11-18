// SQLite storage using Node's built-in node:sqlite (no native build step).

import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import bcrypt from 'bcryptjs';

export const SENSORS = ['temperature', 'humidity', 'pressure', 'battery'];

/** Same defaults as the app (spikes cross them, normal values do not). */
export const DEFAULT_THRESHOLDS = {
  temperature: { min: 5, max: 35 },
  humidity: { min: 20, max: 85 },
  pressure: { min: 985, max: 1040 },
  battery: { min: 20, max: null },
};

const SCHEMA = `
CREATE TABLE IF NOT EXISTS readings (
  device_id   TEXT    NOT NULL,
  ts          INTEGER NOT NULL,          -- epoch milliseconds (UTC)
  temperature REAL,
  humidity    REAL,
  pressure    REAL,
  battery     REAL
);
CREATE INDEX IF NOT EXISTS idx_readings_device_ts ON readings (device_id, ts);
CREATE INDEX IF NOT EXISTS idx_readings_ts ON readings (ts);

CREATE TABLE IF NOT EXISTS devices (
  id        TEXT PRIMARY KEY,
  online    INTEGER,
  last_seen INTEGER
);

CREATE TABLE IF NOT EXISTS users (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  email         TEXT NOT NULL UNIQUE COLLATE NOCASE,
  password_hash TEXT NOT NULL,
  role          TEXT NOT NULL CHECK (role IN ('admin', 'viewer'))
);

CREATE TABLE IF NOT EXISTS thresholds (
  sensor TEXT PRIMARY KEY,
  min    REAL,
  max    REAL
);
`;

/** Opens (or creates) the database. Use ':memory:' in tests. */
export function openDb(dbPath) {
  if (dbPath !== ':memory:') fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  const db = new DatabaseSync(dbPath);
  db.exec('PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;');
  db.exec(SCHEMA);
  const count = db.prepare('SELECT COUNT(*) AS n FROM thresholds').get().n;
  if (count === 0) {
    const ins = db.prepare('INSERT INTO thresholds (sensor, min, max) VALUES (?, ?, ?)');
    for (const [s, t] of Object.entries(DEFAULT_THRESHOLDS)) ins.run(s, t.min, t.max);
  }
  return db;
}

/** Seeds the two demo users if the table is empty. */
export function seedUsers(db, { adminEmail, adminPassword, viewerEmail, viewerPassword, cost = 10 }) {
  const n = db.prepare('SELECT COUNT(*) AS n FROM users').get().n;
  if (n > 0) return false;
  const ins = db.prepare('INSERT INTO users (email, password_hash, role) VALUES (?, ?, ?)');
  ins.run(adminEmail, bcrypt.hashSync(adminPassword, cost), 'admin');
  ins.run(viewerEmail, bcrypt.hashSync(viewerPassword, cost), 'viewer');
  return true;
}

export function insertReading(db, r) {
  db.prepare(
    `INSERT INTO readings (device_id, ts, temperature, humidity, pressure, battery)
     VALUES (?, ?, ?, ?, ?, ?)`,
  ).run(r.deviceId, r.ts, r.temperature ?? null, r.humidity ?? null, r.pressure ?? null, r.battery ?? null);
  db.prepare(
    `INSERT INTO devices (id, online, last_seen) VALUES (?, 1, ?)
     ON CONFLICT(id) DO UPDATE SET last_seen = MAX(COALESCE(last_seen, 0), excluded.last_seen), online = 1`,
  ).run(r.deviceId, r.ts);
}

export function setDeviceOnline(db, deviceId, online) {
  db.prepare(
    `INSERT INTO devices (id, online, last_seen) VALUES (?, ?, NULL)
     ON CONFLICT(id) DO UPDATE SET online = excluded.online`,
  ).run(deviceId, online ? 1 : 0);
}

export function getThresholds(db) {
  const out = {};
  for (const row of db.prepare('SELECT sensor, min, max FROM thresholds').all()) {
    out[row.sensor] = { min: row.min, max: row.max };
  }
  return out;
}

export function setThresholds(db, thresholds) {
  const up = db.prepare(
    `INSERT INTO thresholds (sensor, min, max) VALUES (?, ?, ?)
     ON CONFLICT(sensor) DO UPDATE SET min = excluded.min, max = excluded.max`,
  );
  db.exec('BEGIN');
  try {
    for (const [s, t] of Object.entries(thresholds)) up.run(s, t.min, t.max);
    db.exec('COMMIT');
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}
