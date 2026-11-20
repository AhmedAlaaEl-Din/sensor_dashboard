#!/usr/bin/env node
// Fills data/history.db with simulated history (default: 7 days, 1 reading per minute,
// 3 devices) so the History screen has full charts in a demo.
//
//   npm run seed                 # refuses if the DB has readings the API recorded
//   npm run seed -- --force      # replace them anyway
//   npm run seed -- --days 3 --seed 7
//
// Only the `readings` table is replaced (plus a marker in `meta`); users and thresholds stay.
// Best run while the API is stopped (dev-up -Seed does that for you).

import path from 'node:path';
import { parseArgs } from 'node:util';
import { REPO_ROOT } from '../src/config.js';
import { openDb } from '../src/db.js';
import { seedHistory } from '../src/seed.js';

const { values: args } = parseArgs({
  options: {
    force: { type: 'boolean', default: false },
    days: { type: 'string', default: '7' },
    seed: { type: 'string', default: '42' },
    db: { type: 'string' },
    help: { type: 'boolean', short: 'h', default: false },
  },
});

if (args.help) {
  console.log('Usage: npm run seed -- [--force] [--days 7] [--seed 42] [--db path/to/history.db]');
  process.exit(0);
}

const days = Number(args.days);
const seed = Number(args.seed);
if (!Number.isFinite(days) || days <= 0 || days > 31) {
  console.error('--days must be between 1 and 31.');
  process.exit(2);
}
if (!Number.isInteger(seed)) {
  console.error('--seed must be an integer.');
  process.exit(2);
}

const dbPath = path.resolve(args.db ?? process.env.DB_PATH ?? path.join(REPO_ROOT, 'data', 'history.db'));
const db = openDb(dbPath);
db.exec('PRAGMA busy_timeout = 5000;');

try {
  const result = seedHistory(db, { days, seed, force: args.force });
  if (!result.ok) {
    console.error(
      `Not seeding: ${dbPath} has ${result.real.toLocaleString('en')} readings recorded by the API.\n` +
        'Run again with --force to replace them (npm run seed -- --force).',
    );
    process.exitCode = 1;
  } else {
    const fmt = (ts) => new Date(ts).toLocaleString('en-GB', { dateStyle: 'medium', timeStyle: 'short' });
    console.log(
      `Seeded ${result.inserted.toLocaleString('en')} simulated readings (${days} days, 1 per minute, 3 devices)\n` +
        `  ${fmt(result.from)} -> ${fmt(result.until)}\n` +
        `  removed ${result.removed.toLocaleString('en')} old readings` +
        (result.real ? ` (${result.real.toLocaleString('en')} recorded by the API, --force)` : '') +
        `\n  into ${dbPath}`,
    );
  }
} finally {
  db.close();
}
