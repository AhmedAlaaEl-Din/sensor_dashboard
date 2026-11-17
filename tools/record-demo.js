'use strict';
// Scripted ~70 s demo recording for Phase 1. Simulated data only.
//
// Owns the local broker + simulator (so it can stop/restart them for the
// offline demo), records with scrcpy, drives the app with `adb shell input`,
// and takes adb screencaps at key moments.
//
// Tap coordinates are for a 720x1520 portrait screen (Huawei DUB-LX1).
// The video crops off the status bar (top 56 px) and nav bar so no
// notification icons are recorded. Never touches the notification shade.
//
// Usage (from repo root, phone connected, app installed, adb reverse active):
//   node tools/record-demo.js

const { spawn, execFile } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const BROKER_DIR = path.join(ROOT, 'broker');
const mqtt = require(path.join(BROKER_DIR, 'node_modules', 'mqtt'));
const VIDEO = path.join(ROOT, 'demo_videos', 'phase1-demo.mp4');
const SHOTS = path.join(ROOT, 'evidence', 'screenshots');
const PKG = 'com.ahmed.sensor_dashboard';

const P = {
  greenhouseCard: [360, 500],
  chipHumidity: [369, 310],
  chipTemperature: [147, 310],
  gear: [672, 110],
  bell: [576, 110],
  tempMaxField: [590, 853],
  save: [600, 1352],
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const t0 = Date.now();
const log = (m) => console.log(`[${((Date.now() - t0) / 1000).toFixed(1).padStart(5)} s] ${m}`);

function adb(...args) {
  return new Promise((resolve) => {
    execFile('adb', args, { timeout: 30000 }, (err, stdout) => {
      if (err) log(`adb ${args.join(' ')} failed: ${err.message}`);
      resolve(stdout);
    });
  });
}
const tap = ([x, y]) => adb('shell', 'input', 'tap', String(x), String(y));
const key = (k) => adb('shell', 'input', 'keyevent', k);

function screencap(name) {
  const out = fs.createWriteStream(path.join(SHOTS, name));
  const p = spawn('adb', ['exec-out', 'screencap', '-p']);
  p.stdout.pipe(out);
  log(`screenshot ${name}`);
}

let dev = null;
function startStack() {
  dev = spawn(process.execPath, ['src/dev.js', '--no-random-spikes'], { cwd: BROKER_DIR });
  dev.stdout.on('data', (d) => {
    const s = d.toString();
    if (s.includes('listening')) log('broker + simulator up');
  });
  dev.stderr.on('data', (d) => log(`dev stderr: ${d.toString().trim()}`));
}
function stopStack() {
  if (dev) dev.kill();
  dev = null;
  log('broker + simulator STOPPED');
}

function spike(device) {
  const c = mqtt.connect('mqtt://127.0.0.1:1883', { reconnectPeriod: 0 });
  c.on('connect', () => c.publish('sensors/_control/spike', device, { qos: 1 }, () => c.end()));
  c.on('error', (e) => log(`spike failed: ${e.message}`));
  log(`spike requested on ${device}`);
}

(async () => {
  fs.mkdirSync(path.dirname(VIDEO), { recursive: true });
  fs.mkdirSync(SHOTS, { recursive: true });

  startStack();
  await sleep(1500);
  await adb('shell', 'am', 'force-stop', PKG);
  await adb('shell', 'am', 'start', '-n', `${PKG}/.MainActivity`);
  log('app launched; filling the chart history for 55 s');
  await sleep(55000);

  const scrcpy = spawn(
    'scrcpy',
    [
      '--no-audio',
      '--show-touches',
      '--max-size=1280',
      '--crop=720:1384:0:56',
      '--no-window',
      `--record=${VIDEO}`,
      '--time-limit=72',
    ],
    { stdio: ['ignore', 'pipe', 'pipe'] },
  );
  scrcpy.stderr.on('data', (d) => process.stdout.write(`[scrcpy] ${d}`));
  scrcpy.stdout.on('data', (d) => process.stdout.write(`[scrcpy] ${d}`));
  const scrcpyDone = new Promise((r) => scrcpy.on('exit', r));
  await sleep(2500);
  const s = Date.now();
  const at = async (sec) => {
    const wait = s + sec * 1000 - Date.now();
    if (wait > 0) await sleep(wait);
  };

  log('REC: dashboard live');
  screencap('01-dashboard.png');
  await at(8);  await tap(P.greenhouseCard); log('open Greenhouse');
  await at(14); await tap(P.chipHumidity); log('humidity chart');
  await at(18); await tap(P.chipTemperature); log('temperature chart');
  await at(20); screencap('02-detail.png');
  await at(22); spike('greenhouse');
  await at(27); screencap('03-alert.png');
  await at(31); await key('KEYCODE_BACK'); log('back to dashboard (banner)');
  await at(34); await tap(P.gear); log('open Settings');
  await at(36); screencap('05-settings.png');
  await at(37); await tap(P.tempMaxField);
  await at(38.5);
  await key('KEYCODE_MOVE_END');
  for (let i = 0; i < 4; i++) await key('KEYCODE_DEL');
  await adb('shell', 'input', 'text', '24');
  log('temperature max -> 24');
  await at(41.5); await key('KEYCODE_BACK'); log('hide keyboard');
  await at(43); await tap(P.save); log('save');
  await at(47); stopStack();
  await at(51); screencap('06-offline.png');
  await at(54); startStack();
  await at(61); await tap(P.bell); log('open alerts list');
  await at(63.5); screencap('04-alerts-list.png');
  await at(67); await key('KEYCODE_BACK'); log('back to dashboard');

  await scrcpyDone;
  log(`recording finished: ${VIDEO}`);
  stopStack();
  process.exit(0);
})().catch((e) => {
  console.error(e);
  stopStack();
  process.exit(1);
});
