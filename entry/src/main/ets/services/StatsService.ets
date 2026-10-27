import { LedgerDb } from './LedgerDb';
import { DateUtil, NumUtil } from '../common/Format';
import { BehaviorCategory, GasScope, TimeDimension, categoryName } from '../common/Domain';
import { CategoryStat, StatBucket, StatRow, StatsSummary } from '../models/StatsModels';
import { Tables } from './LedgerSchema';

/**
 * 统计服务（第 4.1 节 B2、第 5.1 节）。
 * 全部统计由有效记录派生，缓存可重建，不保存无法对账的独立总余额。
 * 饼图展示正向贡献占比，负值单列；全零时正常显示。
 */
export class StatsService {

  /** 取参与统计的有效记录行（最新版本） */
  static async rows(db: LedgerDb): Promise<StatRow[]> {
    const rs = await db.queryStatRows();
    return rs;
  }

  /** 按时间维度聚合；category 非空时仅统计该类别（第 4.1 节 B2 分类查询） */
  static async summary(db: LedgerDb, dim: TimeDimension, from: string, to: string,
    category: BehaviorCategory | null = null, gasScope: string = ''): Promise<StatsSummary> {
    const all = await db.queryStatRows();
    const candidates: StatRow[] = [];
    const scopes: string[] = [];
    for (const r of all) {
      if (r.dayKey >= from && r.dayKey <= to && (category === null || r.category === category)) {
        candidates.push(r);
        if (scopes.indexOf(`${r.gasScope}`) < 0) { scopes.push(`${r.gasScope}`); }
      }
    }

    const selectedScope = scopes.indexOf(gasScope) >= 0 ? gasScope : (scopes.length > 0 ? scopes[0] : gasScope);
    const rows = candidates.filter((r: StatRow) => `${r.gasScope}` === selectedScope);

    const bucketMap: Map<string, StatBucket> = new Map<string, StatBucket>();
    const catMap: Map<string, CategoryStat> = new Map<string, CategoryStat>();
    let totalPositive = 0;
    let totalNegative = 0;

    for (const r of rows) {
      const isPositive = r.reductionKg > 0;
      const pos = isPositive ? r.reductionKg : 0;
      const neg = isPositive ? 0 : Math.abs(r.reductionKg);
      totalPositive = totalPositive + pos;
      totalNegative = totalNegative + neg;
      if (scopes.indexOf(`${r.gasScope}`) < 0) {
        scopes.push(`${r.gasScope}`);
      }

      const bkey = StatsService.bucketKey(r.dayKey, dim);
      const existing = bucketMap.get(bkey);
      if (existing === undefined) {
        bucketMap.set(bkey, {
          key: bkey,
          label: StatsService.bucketLabel(r.dayKey, dim),
          positiveKg: pos,
          negativeKg: neg,
          netKg: pos - neg,
          count: 1
        });
      } else {
        existing.positiveKg = existing.positiveKg + pos;
        existing.negativeKg = existing.negativeKg + neg;
        existing.netKg = existing.positiveKg - existing.negativeKg;
        existing.count = existing.count + 1;
        bucketMap.set(bkey, existing);
      }

      const ckey = `${r.category}`;
      const cexisting = catMap.get(ckey);
      if (cexisting === undefined) {
        catMap.set(ckey, {
          category: r.category,
          label: categoryName(r.category),
          positiveKg: pos,
          negativeKg: neg,
          netKg: pos - neg,
          count: 1
        });
      } else {
        cexisting.positiveKg = cexisting.positiveKg + pos;
        cexisting.negativeKg = cexisting.negativeKg + neg;
        cexisting.netKg = cexisting.positiveKg - cexisting.negativeKg;
        cexisting.count = cexisting.count + 1;
        catMap.set(ckey, cexisting);
      }
    }

    const buckets: StatBucket[] = [];
    bucketMap.forEach((b: StatBucket) => {
      buckets.push(b);
    });
    buckets.sort((a: StatBucket, b: StatBucket) => a.key < b.key ? -1 : (a.key > b.key ? 1 : 0));

    const categories: CategoryStat[] = [];
    catMap.forEach((c: CategoryStat) => {
      categories.push(c);
    });
    categories.sort((a: CategoryStat, b: CategoryStat) => b.positiveKg - a.positiveKg);

    const summary: StatsSummary = {
      buckets: buckets,
      categories: categories,
      totalPositiveKg: NumUtil.roundCalc(totalPositive),
      totalNegativeKg: NumUtil.roundCalc(totalNegative),
      totalNetKg: NumUtil.roundCalc(totalPositive - totalNegative),
      recordCount: rows.length,
      allZero: rows.length === 0 || (totalPositive === 0 && totalNegative === 0),
      gasScopes: scopes
    };
    return summary;
  }

  /** 维度键 */
  private static bucketKey(day: string, dim: TimeDimension): string {
    if (dim === TimeDimension.DAY) {
      return day;
    } else if (dim === TimeDimension.WEEK) {
      return DateUtil.weekStart(day);
    } else if (dim === TimeDimension.MONTH) {
      return DateUtil.monthKey(day);
    }
    return DateUtil.yearKey(day);
  }

  /** 维度标签（周视图显示为该周周一） */
  private static bucketLabel(day: string, dim: TimeDimension): string {
    if (dim === TimeDimension.DAY) {
      return day.substring(5);
    } else if (dim === TimeDimension.WEEK) {
      return `${DateUtil.weekStart(day).substring(5)} 起`;
    } else if (dim === TimeDimension.MONTH) {
      return DateUtil.monthKey(day);
    }
    return `${DateUtil.yearKey(day)}年`;
  }

  /** 默认时间范围：按维度给出合理的起点 */
  static defaultFrom(dim: TimeDimension): string {
    const today = DateUtil.today();
    if (dim === TimeDimension.DAY) {
      return DateUtil.addDays(today, -6);
    } else if (dim === TimeDimension.WEEK) {
      return DateUtil.addDays(today, -27);
    } else if (dim === TimeDimension.MONTH) {
      return DateUtil.addDays(today, -180);
    }
    return `${DateUtil.yearKey(today)}-01-01`;
  }
}
