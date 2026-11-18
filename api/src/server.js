// Entry point: local-only API on 127.0.0.1:3000 + MQTT ingest + retention job.

import { DEMO_USERS, loadConfig } from './config.js';
import { createApp } from './app.js';
import { openDb, seedUsers } from './db.js';
import { runRetention } from './history.js';
import { startIngest } from './ingest.js';

const log = (m) => console.log(`[api] ${m}`);

const config = loadConfig({ log });
const db = openDb(config.dbPath);
if (
  seedUsers(db, {
    adminEmail: DEMO_USERS.admin,
    adminPassword: config.demoAdminPassword,
    viewerEmail: DEMO_USERS.viewer,
    viewerPassword: config.demoViewerPassword,
  })
) {
  log(`seeded demo users ${DEMO_USERS.admin} (admin) and ${DEMO_USERS.viewer} (viewer)`);
}

const cleanup = () => {
  const removed = runRetention(db, { retentionDays: config.retentionDays });
  if (removed > 0) log(`retention: removed ${removed} readings older than ${config.retentionDays} days`);
};
cleanup();
const cleanupTimer = setInterval(cleanup, config.cleanupIntervalMs);

const ingest = startIngest({ db, url: config.mqttUrl, prefix: config.topicPrefix, log });
const app = createApp({ db, config });
const server = app.listen(config.port, config.host, () => {
  log(`listening on http://${config.host}:${config.port} (local only)`);
});
server.on('error', (e) => {
  console.error(`[api] failed to start: ${e.message}`);
  process.exit(1);
});

const stop = async () => {
  log('shutting down');
  clearInterval(cleanupTimer);
  server.close();
  await ingest.stop();
  db.close();
  process.exit(0);
};
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
