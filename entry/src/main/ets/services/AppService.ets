import { BackupPolicy } from './BackupPolicy';
import { Tables } from './LedgerSchema';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LedgerDb } from './LedgerDb';
import { FactorRepository } from './FactorRepository';
import { Result, ErrorCode } from '../common/AppError';
import { PROD_FACTORS } from '../data/ProdFactors';
import { TEST_FACTORS } from '../data/TestFactors';
import { REWARD_DEFS } from '../data/RewardDefs';
import { BADGE_DEFS } from '../data/BadgeDefs';
import { TASK_TEMPLATES } from '../data/TaskTemplates';
import { ARTICLES } from '../data/Articles';
import { DEV_FACTOR_MODE } from '../common/BuildConfig';

const DOMAIN = 0x0000;
const TAG = 'AppService';

/**
 * 应用级服务入口：初始化数据库、装载因子库、写入种子数据。
 * 页面只依赖本类与各领域服务，不自行打开数据库。
 */
export class AppService {
  private static repository: FactorRepository | null = null;
  private static bootstrapped: boolean = false;

  /** 因子仓库单例 */
  static repo(): FactorRepository {
    if (AppService.repository === null) {
      AppService.repository = FactorRepository.createDefault();
    }
    return AppService.repository;
  }

  static isReady(): boolean {
    return AppService.bootstrapped && LedgerDb.get().isReady();
  }

  /** 启动引导：打开数据库 → 建表 → 装载因子与内容种子数据 */
  static async bootstrap(context: common.Context): Promise<Result<boolean>> {
    const db = LedgerDb.get();
    const initRes = await db.init(context);
    if (!initRes.ok) {
      return initRes;
    }
    try {
      const repo = AppService.repo();
      if (!DEV_FACTOR_MODE) {
        const auditError = BackupPolicy.productionRowsError(await db.dumpTable(Tables.CARBON_FACTOR), await db.dumpTable(Tables.CALCULATION_SNAPSHOT), await db.dumpTable(Tables.BEHAVIOR_RECORD));
        if (auditError.length > 0) { return Result.failure(ErrorCode.E_RESTORE_INVALID, `正式数据检查未通过：${auditError}原数据已保留。`); }
      }

      // 因子：生产因子始终同步；开发模式下追加测试因子
      await db.seedFactors(PROD_FACTORS);
      if (DEV_FACTOR_MODE) {
        await db.seedFactors(TEST_FACTORS);
      }

      // Task definitions follow the reviewed factor set; persisted task instances keep their frozen reasons.
      await db.seedTemplates(TASK_TEMPLATES);

      // 内容与规则种子：仅首次写入，避免覆盖用户可见内容
      const seeded = await db.getMeta('seeded');
      if (seeded !== '1') {
        await db.seedRewards(REWARD_DEFS);
        await db.seedBadges(BADGE_DEFS);
        await db.seedTemplates(TASK_TEMPLATES);
        await db.seedArticles(ARTICLES);
        await db.setMeta('seeded', '1');
      }

      await db.setMeta('factor_set_version', repo.setVersion());
      AppService.bootstrapped = true;
      hilog.info(DOMAIN, TAG, 'bootstrap done; testFactorMode=%{public}s', `${repo.isUsingTestData()}`);
      return Result.success(true);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'bootstrap failed: %{public}s', JSON.stringify(err));
      return Result.failure(ErrorCode.E_STORAGE, `启动初始化失败：${err.message}`);
    }
  }
}
