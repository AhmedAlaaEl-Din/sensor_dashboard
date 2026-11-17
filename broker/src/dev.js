'use strict';
// One command for local demos: starts the broker and the simulator in one process.
// Usage: npm run dev [-- --no-random-spikes] [-- --spike greenhouse]

const { startBroker } = require('./broker');
const { startSimulator, parseArgs } = require('./simulator');

(async () => {
  const args = parseArgs(process.argv.slice(2));
  const broker = await startBroker({ port: 1883, log: (m) => console.log(`[broker] ${m}`) });
  const sim = await startSimulator({
    ...args,
    url: `mqtt://127.0.0.1:${broker.port}`,
    log: (m) => console.log(`[sim] ${m}`),
  });
  if (args.spike) setTimeout(() => sim.spike(args.spike), 3000);
  console.log('Ready. Spike a device with: npm run spike -- greenhouse   (Ctrl+C to stop)');

  const stop = async () => {
    await sim.stop().catch(() => {});
    await broker.close();
    process.exit(0);
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
})().catch((err) => {
  console.error(`[dev] failed: ${err.message}`);
  process.exit(1);
});
