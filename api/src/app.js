// Express app (no listening here, so tests can drive it with supertest).

import bcrypt from 'bcryptjs';
import express from 'express';
import rateLimit, { ipKeyGenerator } from 'express-rate-limit';
import helmet from 'helmet';
import jwt from 'jsonwebtoken';
import { z } from 'zod';

import { SENSORS, getThresholds, setThresholds } from './db.js';
import {
  BUCKETS,
  MAX_EXPORT_RANGE_MS,
  MAX_RANGE_MS,
  MAX_RAW_RANGE_MS,
  csvLines,
  deleteHistory,
  listDevices,
  queryHistory,
} from './history.js';

/** An error whose message is safe to show to the client. */
export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
    this.expose = true;
  }
}

const DEVICE_ID = /^[A-Za-z0-9_-]{1,64}$/;
// Constant dummy hash so unknown emails take as long as wrong passwords.
const DUMMY_HASH = bcrypt.hashSync('not-a-real-password', 10);

const loginSchema = z.object({
  email: z.string().trim().max(254).pipe(z.email()),
  password: z.string().min(1).max(200),
});

const timeParam = z
  .string()
  .max(40)
  .transform((v, ctx) => {
    const ms = /^\d{1,15}$/.test(v) ? Number(v) : Date.parse(v);
    if (!Number.isFinite(ms)) {
      ctx.addIssue({ code: 'custom', message: 'must be an ISO 8601 date or epoch milliseconds' });
      return z.NEVER;
    }
    return ms;
  });

const rangeSchema = z.object({
  from: timeParam.optional(),
  to: timeParam.optional(),
  bucket: z.enum(Object.keys(BUCKETS)).optional(),
});

const limitSchema = z
  .object({ min: z.number().finite().nullable(), max: z.number().finite().nullable() })
  .refine((t) => t.min == null || t.max == null || t.min < t.max, {
    message: 'min must be below max',
  });
const thresholdsSchema = z.object(Object.fromEntries(SENSORS.map((s) => [s, limitSchema]))).partial().strict();

function parse(schema, value) {
  const r = schema.safeParse(value);
  if (!r.success) {
    const issue = r.error.issues[0];
    const where = issue.path.length ? `${issue.path.join('.')}: ` : '';
    throw new HttpError(400, `Invalid request. ${where}${issue.message}`);
  }
  return r.data;
}

function resolveRange(query, { defaultBucket, maxRange, now }) {
  const q = parse(rangeSchema, query);
  const to = q.to ?? now();
  const from = q.from ?? to - 60 * 60_000;
  const bucket = q.bucket ?? defaultBucket;
  if (from >= to) throw new HttpError(400, 'Invalid request. "from" must be before "to".');
  if (to - from > maxRange) throw new HttpError(400, 'Invalid request. The time range is too long.');
  if (bucket === 'raw' && to - from > MAX_RAW_RANGE_MS) {
    throw new HttpError(400, 'Invalid request. Raw data is limited to 6 hours; use a bucket.');
  }
  return { from, to, bucket };
}

/**
 * @param {object} deps
 * @param {import('node:sqlite').DatabaseSync} deps.db
 * @param {{jwtSecret: string, tokenTtlSeconds: number}} deps.config
 * @param {() => number} [deps.now]
 * @param {(msg: string) => void} [deps.log]
 */
export function createApp({ db, config, now = Date.now, log = console.error }) {
  if (!config.jwtSecret || config.jwtSecret.length < 32) throw new Error('JWT secret missing or too short');

  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', false);
  app.use(helmet());
  app.use((_req, res, next) => {
    res.set('Cache-Control', 'no-store');
    next();
  });
  app.use(express.json({ limit: '10kb' }));

  const loginLimiter = rateLimit({
    windowMs: 5 * 60_000,
    limit: 5,
    skipSuccessfulRequests: true,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    keyGenerator: (req) => {
      const email = typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : '';
      return `${ipKeyGenerator(req.ip ?? '')}|${email}`;
    },
    handler: (_req, res) =>
      res.status(429).json({ error: 'Too many failed login attempts. Try again in a few minutes.' }),
  });

  // ---- auth ----

  const findUser = db.prepare('SELECT id, email, password_hash, role FROM users WHERE email = ?');

  app.post('/auth/login', loginLimiter, (req, res) => {
    const { email, password } = parse(loginSchema, req.body ?? {});
    const user = findUser.get(email);
    const ok = bcrypt.compareSync(password, user?.password_hash ?? DUMMY_HASH);
    if (!user || !ok) throw new HttpError(401, 'Wrong email or password.');

    const iat = Math.floor(now() / 1000);
    const exp = iat + config.tokenTtlSeconds;
    const token = jwt.sign({ sub: String(user.id), email: user.email, role: user.role, iat, exp }, config.jwtSecret, {
      algorithm: 'HS256',
    });
    res.json({
      token,
      expiresAt: new Date(exp * 1000).toISOString(),
      user: { email: user.email, role: user.role },
    });
  });

  function requireAuth(req, _res, next) {
    const header = req.get('authorization') ?? '';
    const m = header.match(/^Bearer ([A-Za-z0-9._-]+)$/);
    if (!m) return next(new HttpError(401, 'Sign in required.'));
    try {
      const payload = jwt.verify(m[1], config.jwtSecret, {
        algorithms: ['HS256'],
        clockTimestamp: Math.floor(now() / 1000),
      });
      req.user = { id: Number(payload.sub), email: payload.email, role: payload.role };
      next();
    } catch (e) {
      next(new HttpError(401, e.name === 'TokenExpiredError' ? 'Session expired. Please sign in again.' : 'Sign in required.'));
    }
  }

  const requireRole = (role) => (req, _res, next) =>
    req.user?.role === role ? next() : next(new HttpError(403, 'Only an admin can do this.'));

  function deviceParam(req) {
    const id = req.params.id;
    if (!DEVICE_ID.test(id)) throw new HttpError(400, 'Invalid request. Unknown device id format.');
    return id;
  }

  app.get('/health', (_req, res) => res.json({ ok: true }));

  app.use(requireAuth);

  app.get('/me', (req, res) => res.json({ user: { email: req.user.email, role: req.user.role } }));

  // ---- devices and history ----

  app.get('/devices', (_req, res) => res.json({ devices: listDevices(db) }));

  app.get('/devices/:id/history', (req, res) => {
    const deviceId = deviceParam(req);
    const { from, to, bucket } = resolveRange(req.query, { defaultBucket: '1m', maxRange: MAX_RANGE_MS, now });
    const { points, stats } = queryHistory(db, { deviceId, from, to, bucket });
    res.json({
      deviceId,
      bucket,
      from: new Date(from).toISOString(),
      to: new Date(to).toISOString(),
      points,
      stats,
    });
  });

  app.get('/devices/:id/export.csv', (req, res) => {
    const deviceId = deviceParam(req);
    const { from, to, bucket } = resolveRange(req.query, {
      defaultBucket: 'raw',
      maxRange: MAX_EXPORT_RANGE_MS,
      now,
    });
    const stamp = (ms) => new Date(ms).toISOString().slice(0, 16).replace(/[-:T]/g, '');
    res.set('Content-Type', 'text/csv; charset=utf-8');
    res.set('Content-Disposition', `attachment; filename="${deviceId}_${stamp(from)}-${stamp(to)}.csv"`);
    let chunk = [];
    for (const line of csvLines(db, { deviceId, from, to, bucket })) {
      chunk.push(line);
      if (chunk.length >= 2000) {
        res.write(chunk.join('\n') + '\n');
        chunk = [];
      }
    }
    res.end(chunk.length ? chunk.join('\n') + '\n' : '');
  });

  app.delete('/devices/:id/history', requireRole('admin'), (req, res) => {
    const deviceId = deviceParam(req);
    res.json({ deleted: deleteHistory(db, deviceId) });
  });

  // ---- thresholds ----

  app.get('/thresholds', (_req, res) => res.json({ thresholds: getThresholds(db) }));

  app.put('/thresholds', requireRole('admin'), (req, res) => {
    const body = parse(thresholdsSchema, req.body ?? {});
    setThresholds(db, body);
    res.json({ thresholds: getThresholds(db) });
  });

  // ---- errors: JSON only, never a stack trace ----

  app.use((_req, _res, next) => next(new HttpError(404, 'Not found.')));

  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    if (err?.type === 'entity.parse.failed') return res.status(400).json({ error: 'Invalid JSON body.' });
    if (err?.type === 'entity.too.large') return res.status(413).json({ error: 'Request body too large.' });
    if (err instanceof HttpError) return res.status(err.status).json({ error: err.message });
    log(`[api] unexpected error: ${err?.stack ?? err}`);
    if (res.headersSent) return res.end();
    res.status(500).json({ error: 'Something went wrong on the server.' });
  });

  return app;
}
