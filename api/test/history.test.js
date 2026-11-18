import request from 'supertest';
import { describe, expect, it } from 'vitest';
import { CSV_HEADER, runRetention } from '../src/history.js';
import { insertReading } from '../src/db.js';
import { parseMessage } from '../src/ingest.js';
import { NOW, VIEWER, makeApp, seed } from './helpers.js';

async function auth(app) {
  const res = await request(app).post('/auth/login').send(VIEWER);
  return { Authorization: `Bearer ${res.body.token}` };
}

const HOUR = 3600_000;
const iso = (ms) => new Date(ms).toISOString();

describe('history bucketing', () => {
  it('1 minute buckets: 60 points over an hour, each the average of 60 readings', async () => {
    const { app, db } = makeApp();
    seed(db, { seconds: 3600 }); // temp cycles 20..29 → average 24.5
    const res = await request(app)
      .get('/devices/greenhouse/history')
      .query({ from: iso(NOW - HOUR), to: iso(NOW), bucket: '1m' })
      .set(await auth(app));
    expect(res.status).toBe(200);
    expect(res.body.bucket).toBe('1m');
    expect(res.body.points).toHaveLength(60);
    const p = res.body.points[0];
    expect(p.t).toBe(iso(NOW - HOUR));
    expect(p.count).toBe(60);
    expect(p.temperature).toBe(24.5);
    expect(p.humidity).toBe(50);
    // Stats come from raw readings, not bucket averages.
    expect(res.body.stats.temperature).toEqual({ min: 20, max: 29, avg: 24.5, count: 3600 });
  });

  it('15 minute and 1 hour buckets', async () => {
    const { app, db } = makeApp();
    seed(db, { seconds: 2 * 3600 });
    const h = await auth(app);
    const q = (bucket) =>
      request(app).get('/devices/greenhouse/history').query({ from: NOW - 2 * HOUR, to: NOW, bucket }).set(h);
    const fifteen = await q('15m');
    expect(fifteen.body.points).toHaveLength(8);
    expect(fifteen.body.points.every((p) => p.count === 900)).toBe(true);
    const hour = await q('1h');
    expect(hour.body.points).toHaveLength(2);
    expect(hour.body.points[1].t).toBe(iso(NOW - HOUR));
  });

  it('raw returns every reading in order and is limited to 6 hours', async () => {
    const { app, db } = makeApp();
    seed(db, { seconds: 120 });
    const h = await auth(app);
    const raw = await request(app)
      .get('/devices/greenhouse/history')
      .query({ from: NOW - 120_000, to: NOW, bucket: 'raw' })
      .set(h);
    expect(raw.body.points).toHaveLength(120);
    expect(raw.body.points[0].t < raw.body.points[1].t).toBe(true);

    const tooLong = await request(app)
      .get('/devices/greenhouse/history')
      .query({ from: NOW - 7 * HOUR, to: NOW, bucket: 'raw' })
      .set(h);
    expect(tooLong.status).toBe(400);
  });

  it('only returns the requested device and range; empty range gives empty points and null stats', async () => {
    const { app, db } = makeApp();
    seed(db, { deviceId: 'warehouse', seconds: 600 });
    const h = await auth(app);
    const res = await request(app)
      .get('/devices/greenhouse/history')
      .query({ from: NOW - HOUR, to: NOW })
      .set(h);
    expect(res.status).toBe(200);
    expect(res.body.points).toEqual([]);
    expect(res.body.stats.temperature).toBeNull();
  });

  it('defaults to the last hour in 1 minute buckets', async () => {
    const { app, db } = makeApp();
    seed(db, { seconds: 2 * 3600 });
    const res = await request(app).get('/devices/greenhouse/history').set(await auth(app));
    expect(res.body.from).toBe(iso(NOW - HOUR));
    expect(res.body.to).toBe(iso(NOW));
    expect(res.body.points).toHaveLength(60);
  });

  it('validates the range', async () => {
    const { app } = makeApp();
    const h = await auth(app);
    const bad = [
      { from: 'yesterday' },
      { from: NOW, to: NOW - 1 },
      { bucket: '5m' },
      { from: NOW - 40 * 24 * HOUR, to: NOW, bucket: '1h' },
    ];
    for (const query of bad) {
      const res = await request(app).get('/devices/greenhouse/history').query(query).set(h);
      expect(res.status, JSON.stringify(query)).toBe(400);
      expect(res.body.error).toMatch(/^Invalid request/);
    }
  });

  it('lists devices with their latest reading', async () => {
    const { app, db } = makeApp();
    seed(db, { deviceId: 'warehouse', seconds: 3 });
    const res = await request(app).get('/devices').set(await auth(app));
    expect(res.body.devices).toHaveLength(1);
    expect(res.body.devices[0]).toMatchObject({ id: 'warehouse', online: true, lastSeen: iso(NOW - 1000) });
    expect(res.body.devices[0].latest.temperature).toBe(22);
  });
});

describe('CSV export', () => {
  it('has a header, one row per reading, ISO timestamps and an attachment filename', async () => {
    const { app, db } = makeApp();
    seed(db, { seconds: 3 });
    insertReading(db, { deviceId: 'greenhouse', ts: NOW - 500, temperature: 21.456 }); // missing fields
    const res = await request(app)
      .get('/devices/greenhouse/export.csv')
      .query({ from: NOW - 60_000, to: NOW })
      .set(await auth(app));
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toBe('text/csv; charset=utf-8');
    expect(res.headers['content-disposition']).toBe(
      'attachment; filename="greenhouse_202611181159-202611181200.csv"',
    );
    const lines = res.text.trimEnd().split('\n');
    expect(lines[0]).toBe(CSV_HEADER);
    expect(lines).toHaveLength(5);
    expect(lines[1]).toBe(`${iso(NOW - 3000)},greenhouse,20,50,1013,90`);
    expect(lines[4]).toBe(`${iso(NOW - 500)},greenhouse,21.46,,,`);
  });

  it('supports bucketed export and returns only the header when empty', async () => {
    const { app, db } = makeApp();
    seed(db, { seconds: 600 });
    const h = await auth(app);
    const bucketed = await request(app)
      .get('/devices/greenhouse/export.csv')
      .query({ from: NOW - 600_000, to: NOW, bucket: '1m' })
      .set(h);
    expect(bucketed.text.trimEnd().split('\n')).toHaveLength(11);
    const empty = await request(app).get('/devices/warehouse/export.csv').set(h);
    expect(empty.text).toBe(`${CSV_HEADER}\n`);
  });
});

describe('retention', () => {
  it('deletes readings older than the retention window and keeps newer ones', () => {
    const { db } = makeApp();
    const day = 24 * HOUR;
    for (const age of [8 * day, 7 * day + 1, 7 * day - 1000, day, 0]) {
      insertReading(db, { deviceId: 'greenhouse', ts: NOW - age, temperature: 20 });
    }
    expect(runRetention(db, { retentionDays: 7, now: NOW })).toBe(2);
    expect(db.prepare('SELECT COUNT(*) AS n FROM readings').get().n).toBe(3);
    expect(runRetention(db, { retentionDays: 7, now: NOW })).toBe(0);
  });
});

describe('ingest parser', () => {
  const payload = (o) => Buffer.from(JSON.stringify(o));
  it('parses simulator telemetry and status', () => {
    const t = parseMessage('sensors', 'sensors/greenhouse/telemetry', payload({ temperature: 21, battery: '90', timestamp: iso(NOW) }), NOW);
    expect(t).toEqual({ kind: 'telemetry', deviceId: 'greenhouse', temperature: 21, battery: 90, ts: NOW });
    expect(parseMessage('sensors', 'sensors/a/status', Buffer.from('offline'))).toEqual({ kind: 'status', deviceId: 'a', online: false });
  });
  it('ignores junk, control topics and far-off timestamps', () => {
    expect(parseMessage('sensors', 'sensors/a/telemetry', Buffer.from('nope'))).toBeNull();
    expect(parseMessage('sensors', 'sensors/_control/spike', Buffer.from('all'))).toBeNull();
    expect(parseMessage('sensors', 'other/a/telemetry', payload({ temperature: 1 }))).toBeNull();
    expect(parseMessage('sensors', 'sensors/a/telemetry', payload({}))).toBeNull();
    const old = parseMessage('sensors', 'sensors/a/telemetry', payload({ temperature: 1, timestamp: '2001-01-01T00:00:00Z' }), NOW);
    expect(old.ts).toBe(NOW);
  });
});
