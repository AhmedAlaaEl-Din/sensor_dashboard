'use strict';
// Local-only MQTT broker (aedes) for the sensor dashboard.
// SAFETY: binds to the loopback interface only. The phone reaches it via
// `adb reverse tcp:1883 tcp:1883`, never over the network.

const net = require('node:net');
const { Aedes } = require('aedes');

const LOOPBACK_HOSTS = new Set(['127.0.0.1', '::1', 'localhost']);

/**
 * Start the broker.
 * @param {{port?: number, host?: string, log?: (msg: string) => void}} [opts]
 * @returns {Promise<{port: number, host: string, close: () => Promise<void>}>}
 */
async function startBroker(opts = {}) {
  const host = opts.host ?? '127.0.0.1';
  const port = opts.port ?? 1883;
  const log = opts.log ?? (() => {});

  if (!LOOPBACK_HOSTS.has(host)) {
    throw new Error(`Refusing to bind to "${host}": the broker is local-only (use 127.0.0.1).`);
  }

  const aedes = await Aedes.createBroker();
  const server = net.createServer(aedes.handle);

  aedes.on('client', (c) => log(`client connected: ${c ? c.id : '?'}`));
  aedes.on('clientDisconnect', (c) => log(`client disconnected: ${c ? c.id : '?'}`));

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => {
      server.off('error', reject);
      resolve();
    });
  });

  const actualPort = server.address().port;
  log(`MQTT broker listening on ${host}:${actualPort} (local only)`);

  const sockets = new Set();
  server.on('connection', (s) => {
    sockets.add(s);
    s.on('close', () => sockets.delete(s));
  });

  return {
    port: actualPort,
    host,
    close: () =>
      new Promise((resolve) => {
        for (const s of sockets) s.destroy();
        server.close(() => aedes.close(() => resolve()));
      }),
  };
}

module.exports = { startBroker };

if (require.main === module) {
  const portArg = process.argv.indexOf('--port');
  const port = portArg > -1 ? Number(process.argv[portArg + 1]) : 1883;
  startBroker({ port, log: (m) => console.log(`[broker] ${m}`) })
    .then((b) => {
      const stop = async () => {
        console.log('[broker] shutting down');
        await b.close();
        process.exit(0);
      };
      process.on('SIGINT', stop);
      process.on('SIGTERM', stop);
    })
    .catch((err) => {
      console.error(`[broker] failed to start: ${err.message}`);
      process.exit(1);
    });
}
