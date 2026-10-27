import { DEV_FACTOR_MODE } from './BuildConfig';

export class EnvironmentPolicy {
  static environmentName(development: boolean): string { return development ? 'development' : 'production'; }
  static databaseName(development: boolean): string {
    // Keep the legacy file exclusively for development; production never opens it.
    return development ? 'lvtancunzhe.db' : 'lvtancunzhe-production.db';
  }
  static importError(origin: string | undefined, development: boolean): string {
    if (development) {
      return origin === undefined || origin === 'development' ? '' : '这是正式数据备份，请在正式版本中恢复，避免混入测试环境。';
    }
    return origin === 'production' ? '' : '正式版本仅接受明确标记为正式环境的备份。开发或旧版未标记的备份请在开发版本中打开。';
  }
}
export const DATA_ENVIRONMENT: string = EnvironmentPolicy.environmentName(DEV_FACTOR_MODE);
export const DATABASE_NAME: string = EnvironmentPolicy.databaseName(DEV_FACTOR_MODE);
