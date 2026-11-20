import jwt from 'jsonwebtoken';
import request from 'supertest';
import { describe, expect, it } from 'vitest';
import { ADMIN, NOW, SECRET, VIEWER, makeApp } from './helpers.js';

async function login(app, user) {
  const res = await request(app).post('/auth/login').send(user);
  expect(res.status).toBe(200);
  return res.body.token;
}

describe('auth', () => {
  it('logs in with the right password and returns a short-lived token', async () => {
    const { app } = makeApp();
    const res = await request(app).post('/auth/login').send(ADMIN);
    expect(res.status).toBe(200);
    expect(res.body.user).toEqual({ email: ADMIN.email, role: 'admin' });
    expect(res.body.expiresAt).toBe(new Date(NOW + 1800_000).toISOString());
    const payload = jwt.verify(res.body.token, SECRET, { clockTimestamp: NOW / 1000 });
    expect(payload.role).toBe('admin');
    expect(payload.exp - payload.iat).toBe(1800);
    expect(JSON.stringify(payload)).not.toContain('password');
  });

  it('email is case-insensitive', async () => {
    const { app } = makeApp();
    const res = await request(app).post('/auth/login').send({ ...VIEWER, email: 'Viewer@Example.com' });
    expect(res.status).toBe(200);
  });

  it('rejects a wrong password and an unknown user with the same message', async () => {
    const { app } = makeApp();
    const wrong = await request(app).post('/auth/login').send({ ...ADMIN, password: 'nope' });
    const unknown = await request(app).post('/auth/login').send({ email: 'x@example.com', password: 'nope' });
    expect(wrong.status).toBe(401);
    expect(unknown.status).toBe(401);
    expect(wrong.body).toEqual({ error: 'Wrong email or password.' });
    expect(unknown.body).toEqual(wrong.body);
    expect(wrong.body.token).toBeUndefined();
  });

  it('validates the login body', async () => {
    const { app } = makeApp();
    for (const body of [{}, { email: 'not-an-email', password: 'x' }, { email: ADMIN.email }, { email: ADMIN.email, password: 'x'.repeat(201) }]) {
      const res = await request(app).post('/auth/login').send(body);
      expect(res.status).toBe(400);
      expect(res.body.error).toMatch(/^Invalid request/);
    }
  });

  it('rate-limits repeated failed logins for the same account', async () => {
    const { app } = makeApp();
    for (let i = 0; i < 5; i++) {
      const r = await request(app).post('/auth/login').send({ ...ADMIN, password: `bad${i}` });
      expect(r.status).toBe(401);
    }
    const blocked = await request(app).post('/auth/login').send(ADMIN);
    expect(blocked.status).toBe(429);
    expect(blocked.body.error).toMatch(/Too many failed login attempts/);
    // Another account is not affected.
    const other = await request(app).post('/auth/login').send(VIEWER);
    expect(other.status).toBe(200);
  });

  it('requires a token on protected routes', async () => {
    const { app } = makeApp();
    for (const path of ['/me', '/devices', '/devices/greenhouse/history', '/devices/greenhouse/export.csv', '/thresholds']) {
      const res = await request(app).get(path);
      expect(res.status, path).toBe(401);
      expect(res.body).toEqual({ error: 'Sign in required.' });
    }
    const bad = await request(app).get('/devices').set('Authorization', 'Bearer not.a.token');
    expect(bad.status).toBe(401);
  });

  it('rejects an expired token with a clear message', async () => {
    let now = NOW;
    const { app } = makeApp({ now: () => now, ttl: 60 });
    const token = await login(app, VIEWER);
    expect((await request(app).get('/me').set('Authorization', `Bearer ${token}`)).status).toBe(200);
    now += 61_000;
    const res = await request(app).get('/me').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: 'Session expired. Please sign in again.' });
  });

  it('rejects tokens signed with another key or with alg none', async () => {
    const { app } = makeApp();
    const forged = jwt.sign({ sub: '1', role: 'admin' }, 'another-secret-another-secret-123456', { expiresIn: 60 });
    const none = jwt.sign({ sub: '1', role: 'admin', exp: NOW / 1000 + 60 }, null, { algorithm: 'none' });
    for (const t of [forged, none]) {
      const res = await request(app).get('/me').set('Authorization', `Bearer ${t}`);
      expect(res.status).toBe(401);
    }
  });
});

describe('permissions', () => {
  it('viewer can read but cannot change thresholds or delete history', async () => {
    const { app } = makeApp();
    const token = await login(app, VIEWER);
    const auth = { Authorization: `Bearer ${token}` };

    expect((await request(app).get('/thresholds').set(auth)).status).toBe(200);
    const put = await request(app).put('/thresholds').set(auth).send({ temperature: { min: 0, max: 30 } });
    expect(put.status).toBe(403);
    expect(put.body).toEqual({ error: 'Only an admin can do this.' });
    const del = await request(app).delete('/devices/greenhouse/history').set(auth);
    expect(del.status).toBe(403);
  });

  it('admin can change thresholds (validated) and delete history', async () => {
    const { app } = makeApp();
    const token = await login(app, ADMIN);
    const auth = { Authorization: `Bearer ${token}` };

    const put = await request(app).put('/thresholds').set(auth).send({ temperature: { min: 0, max: 30 } });
    expect(put.status).toBe(200);
    expect(put.body.thresholds.temperature).toEqual({ min: 0, max: 30 });
    expect(put.body.thresholds.humidity).toEqual({ min: 20, max: 85 }); // untouched

    const inverted = await request(app).put('/thresholds').set(auth).send({ temperature: { min: 40, max: 30 } });
    expect(inverted.status).toBe(400);
    const unknown = await request(app).put('/thresholds').set(auth).send({ wind: { min: 0, max: 1 } });
    expect(unknown.status).toBe(400);

    const del = await request(app).delete('/devices/greenhouse/history').set(auth);
    expect(del.status).toBe(200);
    expect(del.body).toEqual({ deleted: 0 });
  });
});

describe('hardening', () => {
  it('sets security headers and never leaks stack traces', async () => {
    const { app } = makeApp();
    const res = await request(app).post('/auth/login').set('Content-Type', 'application/json').send('{"email":');
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'Invalid JSON body.' });
    expect(JSON.stringify(res.body)).not.toMatch(/at .*\.js/);
    expect(res.headers['x-powered-by']).toBeUndefined();
    expect(res.headers['x-content-type-options']).toBe('nosniff');
    expect(res.headers['content-security-policy']).toBeDefined();
    expect(res.headers['cache-control']).toBe('no-store');
  });

  it('unknown routes return a JSON 404', async () => {
    const { app } = makeApp();
    const token = await login(app, VIEWER);
    const res = await request(app).get('/nope').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: 'Not found.' });
  });

  it('rejects bad device ids', async () => {
    const { app } = makeApp();
    const token = await login(app, VIEWER);
    const res = await request(app).get('/devices/bad%20id;drop/history').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});
