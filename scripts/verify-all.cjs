const {spawnSync} = require('child_process');
const path = require('path');
for (const name of ['core', 'hardening', 'plan-ui', 'concurrency', 'full-audit']) {
  const result = spawnSync(process.execPath, [path.join(__dirname, `verify-${name}.cjs`)], {stdio: 'inherit'});
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status || 1);
}
console.log('PASS all 59 service regression checks (isolated fixtures; no native UI acceptance implied)');
