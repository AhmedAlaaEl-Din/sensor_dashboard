// Subscribes to the local broker and stores every telemetry reading.

import mqtt from 'mqtt';
import { SENSORS, insertReading, setDeviceOnline } from './db.js';

const DEVICE_ID = /^[A-Za-z0-9_-]{1,64}$/;

/** Parses one message. Returns null for anything unusable (never throws). */
export function parseMessage(prefix, topic, payload, now = Date.now()) {
  const parts = topic.split('/');
  const pre = prefix.split('/').filter(Boolean);
  if (parts.length !== pre.length + 2 || pre.some((p, i) => parts[i] !== p)) return null;
  const deviceId = parts[pre.length];
  const kind = parts[pre.length + 1];
  if (!DEVICE_ID.test(deviceId) || deviceId.startsWith('_')) return null;

  const text = payload.toString();
  if (kind === 'status') {
    const s = text.trim().toLowerCase();
    return s === 'online' || s === 'offline' ? { kind: 'status', deviceId, online: s === 'online' } : null;
  }
  if (kind !== 'telemetry') return null;

  let json;
  try {
    json = JSON.parse(text);
  } catch {
    return null;
  }
  if (!json || typeof json !== 'object' || Array.isArray(json)) return null;

  const reading = { kind: 'telemetry', deviceId };
  let any = false;
  for (const s of SENSORS) {
    const v = typeof json[s] === 'string' ? Number(json[s]) : json[s];
    if (typeof v === 'number' && Number.isFinite(v)) {
      reading[s] = v;
      any = true;
    }
  }
  if (!any) return null;
  const ts = typeof json.timestamp === 'string' ? Date.parse(json.timestamp) : json.timestamp;
  // Trust the device clock only if it is within a day of ours.
  reading.ts = Number.isFinite(ts) && Math.abs(ts - now) < 24 * 3600_000 ? ts : now;
  return reading;
}

export function startIngest({ db, url, prefix, log = () => {} }) {
  const clean = prefix.replace(/^\/+|\/+$/g, '') || 'sensors';
  const client = mqtt.connect(url, {
    clientId: `api-${process.pid}-${Math.random().toString(16).slice(2, 8)}`,
    reconnectPeriod: 2000,
  });
  let stored = 0;
  client.on('connect', () => {
    log(`connected to ${url}, subscribing to ${clean}/+/telemetry and ${clean}/+/status`);
    client.subscribe([`${clean}/+/telemetry`, `${clean}/+/status`], { qos: 0 });
  });
  client.on('reconnect', () => log('broker not reachable, retrying'));
  client.on('error', (e) => log(`mqtt error: ${e.message}`));
  client.on('message', (topic, payload) => {
    const m = parseMessage(clean, topic, payload);
    if (!m) return;
    try {
      if (m.kind === 'status') setDeviceOnline(db, m.deviceId, m.online);
      else {
        insertReading(db, m);
        stored++;
      }
    } catch (e) {
      log(`store failed: ${e.message}`);
    }
  });
  return {
    client,
    get stored() {
      return stored;
    },
    stop: () => new Promise((r) => client.end(false, {}, r)),
  };
}
