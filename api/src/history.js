// History queries: downsampling (bucketing), statistics, CSV export, retention.

import { SENSORS } from './db.js';

/** Bucket name -> width in milliseconds. 'raw' means no downsampling. */
export const BUCKETS = {
  raw: 0,
  '1m': 60_000,
  '15m': 15 * 60_000,
  '1h': 60 * 60_000,
};

/** Raw data is limited to short ranges so a response never holds 100k+ points. */
export const MAX_RAW_RANGE_MS = 6 * 60 * 60_000;
export const MAX_RANGE_MS = 31 * 24 * 60 * 60_000;
export const MAX_EXPORT_RANGE_MS = 8 * 24 * 60 * 60_000;

const round = (v) => (v == null ? null : Math.round(v * 100) / 100);

/**
 * Downsampled points: each bucket holds the average of the readings inside it,
 * stamped with the bucket start time.
 */
export function queryHistory(db, { deviceId, from, to, bucket }) {
  const width = BUCKETS[bucket];
  let rows;
  if (width === 0) {
    rows = db
      .prepare(
        `SELECT ts AS t, temperature, humidity, pressure, battery, 1 AS count
         FROM readings WHERE device_id = ? AND ts >= ? AND ts < ? ORDER BY ts`,
      )
      .all(deviceId, from, to);
  } else {
    // `width` comes from the BUCKETS whitelist, so inlining it is safe. It must be
    // an integer literal: a bound JS number arrives as REAL and turns `/` into
    // float division, which would disable the grouping.
    rows = db
      .prepare(
        `SELECT (ts / ${width}) * ${width} AS t,
                AVG(temperature) AS temperature, AVG(humidity) AS humidity,
                AVG(pressure) AS pressure, AVG(battery) AS battery,
                COUNT(*) AS count
         FROM readings WHERE device_id = ? AND ts >= ? AND ts < ?
         GROUP BY ts / ${width} ORDER BY t`,
      )
      .all(deviceId, from, to);
  }

  const points = rows.map((r) => ({
    t: new Date(Number(r.t)).toISOString(),
    temperature: round(r.temperature),
    humidity: round(r.humidity),
    pressure: round(r.pressure),
    battery: round(r.battery),
    count: Number(r.count),
  }));

  return { points, stats: queryStats(db, { deviceId, from, to }) };
}

/** Min / max / average over the raw readings in the range (not the buckets). */
export function queryStats(db, { deviceId, from, to }) {
  const cols = SENSORS.map(
    (s) => `MIN(${s}) AS ${s}_min, MAX(${s}) AS ${s}_max, AVG(${s}) AS ${s}_avg, COUNT(${s}) AS ${s}_n`,
  ).join(', ');
  const row = db
    .prepare(`SELECT ${cols} FROM readings WHERE device_id = ? AND ts >= ? AND ts < ?`)
    .get(deviceId, from, to);
  const stats = {};
  for (const s of SENSORS) {
    const n = Number(row[`${s}_n`]);
    stats[s] = n === 0 ? null : { min: round(row[`${s}_min`]), max: round(row[`${s}_max`]), avg: round(row[`${s}_avg`]), count: n };
  }
  return stats;
}

export const CSV_HEADER = 'timestamp,device_id,temperature,humidity,pressure,battery';

const csvNum = (v) => (v == null ? '' : String(round(v)));

/**
 * Yields CSV lines (header first). Values are numbers and a validated device id,
 * so no quoting or spreadsheet-formula escaping is needed.
 */
export function* csvLines(db, { deviceId, from, to, bucket = 'raw' }) {
  yield CSV_HEADER;
  const width = BUCKETS[bucket];
  const stmt =
    width === 0
      ? db.prepare(
          `SELECT ts AS t, temperature, humidity, pressure, battery
           FROM readings WHERE device_id = ? AND ts >= ? AND ts < ? ORDER BY ts`,
        )
      : db.prepare(
          `SELECT (ts / ${width}) * ${width} AS t, AVG(temperature) AS temperature,
                  AVG(humidity) AS humidity, AVG(pressure) AS pressure, AVG(battery) AS battery
           FROM readings WHERE device_id = ? AND ts >= ? AND ts < ?
           GROUP BY ts / ${width} ORDER BY t`,
        );
  for (const r of stmt.iterate(deviceId, from, to)) {
    yield [
      new Date(Number(r.t)).toISOString(),
      deviceId,
      csvNum(r.temperature),
      csvNum(r.humidity),
      csvNum(r.pressure),
      csvNum(r.battery),
    ].join(',');
  }
}

/** Deletes readings older than the retention window. Returns rows removed. */
export function runRetention(db, { retentionDays, now = Date.now() }) {
  const cutoff = now - retentionDays * 24 * 60 * 60_000;
  const result = db.prepare('DELETE FROM readings WHERE ts < ?').run(cutoff);
  return Number(result.changes);
}

export function deleteHistory(db, deviceId) {
  return Number(db.prepare('DELETE FROM readings WHERE device_id = ?').run(deviceId).changes);
}

export function listDevices(db) {
  const devices = db.prepare('SELECT id, online, last_seen FROM devices ORDER BY id').all();
  const latest = db.prepare(
    `SELECT ts, temperature, humidity, pressure, battery FROM readings
     WHERE device_id = ? ORDER BY ts DESC LIMIT 1`,
  );
  return devices.map((d) => {
    const r = latest.get(d.id);
    return {
      id: d.id,
      online: d.online == null ? null : d.online === 1,
      lastSeen: d.last_seen == null ? null : new Date(Number(d.last_seen)).toISOString(),
      latest: r
        ? {
            timestamp: new Date(Number(r.ts)).toISOString(),
            temperature: r.temperature,
            humidity: r.humidity,
            pressure: r.pressure,
            battery: r.battery,
          }
        : null,
    };
  });
}
