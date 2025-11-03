#!/usr/bin/env node
/**
 * MIRROR STAGE development seeder.
 * Sends synthetic metric batches to the EGO backend so the 2.5D 네트워크 뷰 can render immediately.
 */

const endpoint = process.env.MIRROR_STAGE_METRICS_URL ?? 'http://localhost:3000/api/metrics/batch';
const intervalMs = Number(process.env.MIRROR_STAGE_SEED_INTERVAL_MS ?? 5000);
const once = process.argv.includes('--once');

const hosts = [
  {
    hostname: 'atlas-01',
    rack: 'CoreRack',
    position: { x: -6.5, y: 1.2, z: 2.8 },
    baseCpu: 24,
    cpuVariance: 18,
    baseMem: 48,
    memVariance: 10,
    baseThroughput: 1.8,
  },
  {
    hostname: 'atlas-02',
    rack: 'CoreRack',
    position: { x: -3.8, y: 0.8, z: -4.2 },
    baseCpu: 36,
    cpuVariance: 22,
    baseMem: 57,
    memVariance: 8,
    baseThroughput: 3.2,
  },
  {
    hostname: 'hephaestus-01',
    rack: 'EdgeRack-A',
    position: { x: 5.6, y: 0.4, z: -6.1 },
    baseCpu: 62,
    cpuVariance: 25,
    baseMem: 71,
    memVariance: 12,
    baseThroughput: 5.8,
  },
  {
    hostname: 'hephaestus-02',
    rack: 'EdgeRack-A',
    position: { x: 6.9, y: 0.9, z: -1.9 },
    baseCpu: 54,
    cpuVariance: 18,
    baseMem: 66,
    memVariance: 10,
    baseThroughput: 4.6,
  },
  {
    hostname: 'luna-gpu-01',
    rack: 'AI-Pod-1',
    position: { x: 2.4, y: 1.4, z: 5.8 },
    baseCpu: 48,
    cpuVariance: 20,
    baseMem: 72,
    memVariance: 9,
    baseThroughput: 7.5,
  },
  {
    hostname: 'luna-gpu-02',
    rack: 'AI-Pod-1',
    position: { x: 0.8, y: 1.1, z: 7.2 },
    baseCpu: 52,
    cpuVariance: 21,
    baseMem: 75,
    memVariance: 8,
    baseThroughput: 8.1,
  },
  {
    hostname: 'aegis-firewall',
    rack: 'Security',
    position: { x: -1.1, y: 0.6, z: -8.4 },
    baseCpu: 29,
    cpuVariance: 12,
    baseMem: 41,
    memVariance: 6,
    baseThroughput: 2.4,
  },
  {
    hostname: 'celer-storage-01',
    rack: 'Storage-Pod',
    position: { x: -8.3, y: 1.5, z: -0.4 },
    baseCpu: 18,
    cpuVariance: 9,
    baseMem: 63,
    memVariance: 7,
    baseThroughput: 1.1,
  },
];

let tick = 0;

async function sendBatch() {
  const timestamp = new Date().toISOString();
  const samples = hosts.map((host, index) => {
    const phase = tick * 0.5 + index;
    const cpuLoad = clamp(host.baseCpu + Math.sin(phase) * host.cpuVariance, 0, 98);
    const memoryUsedPercent = clamp(host.baseMem + Math.cos(phase * 0.7) * host.memVariance, 5, 96);
    const netBase = Math.max(host.baseThroughput + Math.sin(phase * 0.9) * 1.5, 0.2);
    const netBytesPerSec = netBase * 1_000_000_000 / 8;
    const uptimeSeconds = 3600 * 24 + tick * intervalMs / 1000;

    return {
      hostname: host.hostname,
      timestamp,
      cpu_load: Number(cpuLoad.toFixed(2)),
      memory_used_percent: Number(memoryUsedPercent.toFixed(2)),
      load_average: Number((cpuLoad / 20).toFixed(2)),
      uptime_seconds: Math.floor(uptimeSeconds),
      agent_version: 'dev-seeder',
      platform: 'Synthetic-Linux-x86_64',
      net_bytes_tx: Math.floor(netBytesPerSec),
      net_bytes_rx: Math.floor(netBytesPerSec * 0.92),
      rack: host.rack,
      position: host.position,
      tags: {
        profile: 'seed',
        generator: 'dev_seed_metrics',
      },
    };
  });

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ samples }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`HTTP ${response.status}: ${text}`);
  }

  const body = await response.json();
  console.log(
    `[seed] ${timestamp} sent ${samples.length} samples -> ${endpoint} (accepted=${body.accepted ?? '?'})`,
  );
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

async function loop() {
  try {
    await sendBatch();
    tick += 1;
  } catch (error) {
    console.error('[seed] error', error);
  }

  if (!once) {
    setTimeout(loop, intervalMs);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  console.log(`[seed] running against ${endpoint}${once ? ' (single batch)' : ''}`);
  loop();
}
