import { CarbonFactor } from '../models/CarbonFactor';
import { BehaviorCategory, ReviewStatus } from '../common/Domain';
import { PROD_FACTORS } from '../data/ProdFactors';
import { TEST_FACTORS } from '../data/TestFactors';
import { DEV_FACTOR_MODE } from '../common/BuildConfig';

/**
 * 因子仓库（业务层）。
 * 页面不直接持有因子数值，统一经此查询，避免 UI 复制公式（第 8.1 节）。
 */
export class FactorRepository {
  private factors: Map<string, CarbonFactor> = new Map<string, CarbonFactor>();
  private usingTestData: boolean = false;

  constructor(list: CarbonFactor[], usingTestData: boolean) {
    this.usingTestData = usingTestData;
    for (const f of list) {
      this.factors.set(f.code, f);
    }
  }

  /** 默认仓库：生产因子 + （开发期）测试因子 */
  static createDefault(): FactorRepository {
    const merged: CarbonFactor[] = [];
    for (const f of PROD_FACTORS) {
      merged.push(f);
    }
    if (DEV_FACTOR_MODE) {
      for (const f of TEST_FACTORS) {
        merged.push(f);
      }
    }
    return new FactorRepository(merged, DEV_FACTOR_MODE);
  }

  /** 是否处于测试因子模式（界面据此显示未核验提示） */
  isUsingTestData(): boolean {
    return this.usingTestData;
  }

  /** 按编码查询 */
  find(code: string): CarbonFactor | undefined {
    return this.factors.get(code);
  }

  /** 是否可用于生产核算 */
  isUsable(factor: CarbonFactor): boolean {
    if (factor.reviewStatus === ReviewStatus.VERIFIED) {
      return true;
    }
    // 测试因子仅在开发模式下可用，且界面会持续提示
    if (DEV_FACTOR_MODE && this.usingTestData) {
      return true;
    }
    return false;
  }

  /** 按类别列出可用因子 */
  listByCategory(category: BehaviorCategory): CarbonFactor[] {
    const out: CarbonFactor[] = [];
    this.factors.forEach((f: CarbonFactor) => {
      if (f.category === category) {
        out.push(f);
      }
    });
    return out;
  }

  /**
   * 按子项解析因子。任务模板引用的是子项（如 bus），而不是会变化的因子编码，
   * 这样因子版本更新后模板无需改动（第 5.4 节：不只引用会变化的 factor_code）。
   */
  findBySubItem(subItem: string): CarbonFactor | undefined {
    if (subItem.length === 0) {
      return undefined;
    }
    let found: CarbonFactor | undefined = undefined;
    this.factors.forEach((f: CarbonFactor) => {
      if (f.subItem === subItem && this.isUsable(f)) {
        // 已核验因子优先
        if (found === undefined || f.reviewStatus === ReviewStatus.VERIFIED) {
          found = f;
        }
      }
    });
    return found;
  }

  /** 全部可用因子 */
  listUsable(): CarbonFactor[] {
    const out: CarbonFactor[] = [];
    this.factors.forEach((f: CarbonFactor) => {
      if (this.isUsable(f)) {
        out.push(f);
      }
    });
    return out;
  }

  /** 因子集合版本标识，写入计划与快照，便于解释推荐变化 */
  setVersion(): string {
    if (this.usingTestData) {
      return 'test-set';
    }
    return 'prod-2026-10-16-conditional';
  }
}
