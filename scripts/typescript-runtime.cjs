/* SDK ArkTS TypeScript is preferred locally; the pinned npm compiler supports service-only CI. */
const fs = require('fs');
const path = require('path');
module.exports = function typescriptRuntime() {
  const explicit = process.env.ARKTS_TYPESCRIPT_PATH;
  if (explicit) return require(path.resolve(explicit));
  const candidates = [];
  const suffix = ['ets', 'build-tools', 'ets-loader', 'node_modules', 'typescript'];
  for (const root of [process.env.ARKTS_SDK_HOME, process.env.OHOS_BASE_SDK_HOME, process.env.DEVECO_SDK_HOME]) {
    if (root) {
      candidates.push(path.join(root, ...suffix));
      candidates.push(path.join(root, '24', ...suffix));
      candidates.push(path.join(root, 'default', 'openharmony', ...suffix));
    }
  }
  for (const home of [process.env.DEVECO_HOME, '/Applications/DevEco-Studio.app/Contents']) {
    if (home) candidates.push(path.join(home, 'sdk', 'default', 'openharmony', ...suffix));
  }
  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, 'package.json'))) return require(candidate);
  }
  try { return require('typescript'); }
  catch {
    throw Error('未找到 TypeScript：执行 npm ci，或设置 ARKTS_TYPESCRIPT_PATH 为 SDK 的 typescript 目录。');
  }
};
