import BuildProfile from 'BuildProfile';

/**
 * 构建期开关（由 entry/build-profile.json5 的 arkOptions.buildProfileFields 注入）。
 *
 * DEV_FACTOR_MODE：
 *   true  —— 允许加载「测试因子库」（data/TestFactors.ets），
 *            并在界面顶部显示「当前使用测试因子，数值未核验」横幅。
 *            仅用于开发与联调，禁止用于参赛材料截图、演示视频与正式设计方案。
 *   false —— 仅使用已核验的生产因子库（data/ProdFactors.ets）。
 *
 * 构建方式：
 *   ./build.sh                      → debug/开发联调构建，DEV_FACTOR_MODE = true
 *   ./build.sh prod                 → release/生产构建，DEV_FACTOR_MODE = false
 *
 * 计划书 5.5：软件测试用数值与生产因子分库管理。
 * 计划书 1.2：11 月 1 日功能冻结，届时交付包必须为生产构建（false）。
 */
function readDevFactorMode(): boolean {
  // buildProfileFields 的值以字符串注入，这里统一按字符串判定
  return `${BuildProfile.DEV_FACTOR_MODE}`.toLowerCase() === 'true';
}

export const DEV_FACTOR_MODE: boolean = readDevFactorMode();

/** 应用版本，写入备份文件与冻结安装包 */
export const APP_VERSION = '1.1.3';

/** 数据库 schema 版本，写入备份文件用于恢复校验 */
export const SCHEMA_VERSION = 2;
