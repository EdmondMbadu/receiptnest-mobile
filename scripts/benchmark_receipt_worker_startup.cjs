#!/usr/bin/env node
// Offline: loads worker exports in fresh Node processes; never invokes a worker.
const {spawnSync} = require('node:child_process');
const {resolve} = require('node:path');

const paths = process.argv.slice(2);
if (paths.length !== 2) {
  console.error('Usage: node scripts/benchmark_receipt_worker_startup.cjs BASELINE_BOOTSTRAP.js OPTIMIZED_BOOTSTRAP.js');
  process.exit(64);
}
const script = `
  const {performance} = require('node:perf_hooks');
  const start = performance.now();
  const cpu = process.cpuUsage();
  const exports = require(process.argv[1]);
  const elapsed = performance.now() - start;
  const used = process.cpuUsage(cpu);
  const modules = Object.keys(require.cache);
  process.stdout.write(JSON.stringify({
    loadMs: elapsed, cpuMs: (used.user + used.system) / 1000,
    rssMiB: process.memoryUsage().rss / 1048576, modules: modules.length,
    emailParserModules: modules.filter(p => /node_modules\\/(cheerio|sanitize-html)\\//.test(p)).length,
    exports: Object.keys(exports)
  }));
`;
const results = [];
for (let iteration = 0; iteration < 14; iteration++) {
  for (const index of iteration % 2 === 0 ? [0, 1] : [1, 0]) {
    const result = spawnSync(process.execPath, ['-e', script, resolve(paths[index])], {
      env: {...process.env, FUNCTION_TARGET: 'processReceipt', GCLOUD_PROJECT: 'demo-receipt-benchmark'},
      encoding: 'utf8', timeout: 20000,
    });
    if (result.status !== 0) throw new Error(result.stderr || String(result.error));
    const sample = JSON.parse(result.stdout);
    if (sample.exports.length !== 1 || sample.exports[0] !== 'processReceipt') {
      throw new Error('Expected only the processReceipt worker export');
    }
    results.push({variant: index === 0 ? 'baseline' : 'optimized', iteration, ...sample});
  }
}
function median(samples, field) {
  const sorted = samples.map(s => s[field]).sort((a, b) => a - b);
  return (sorted[5] + sorted[6]) / 2;
}
const summary = ['baseline', 'optimized'].map(variant => {
  const samples = results.filter(s => s.variant === variant && s.iteration >= 2);
  return {variant, samples: samples.length,
    p50LoadMs: median(samples, 'loadMs'), p50CpuMs: median(samples, 'cpuMs'),
    p50RssMiB: median(samples, 'rssMiB'), modules: median(samples, 'modules'),
    emailParserModules: median(samples, 'emailParserModules')};
});
console.log(JSON.stringify({node: process.version, platform: process.platform,
  architecture: process.arch, warmupsPerVariant: 2, summary, samples: results}, null, 2));
