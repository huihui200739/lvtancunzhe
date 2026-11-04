import { LedgerOperations } from './LedgerOperations';
import { StatsService } from './StatsService';
import { LedgerDb } from './LedgerDb';
import { Result, ErrorCode } from '../common/AppError';
import { DateUtil, NumUtil } from '../common/Format';
import { TimeDimension, BehaviorCategory } from '../common/Domain';
import { StatsSummary } from '../models/StatsModels';

/** 分享卡上的一行：某口径下某类行为的合计 */
export interface ShareCardLine {
  category: BehaviorCategory;
  label: string;
  count: number;
  netKg: number;
}

/** 分享卡上的一个气体口径分区；CO₂ 与 CO₂e 各自成区，不相加 */
export interface ShareCardScope {
  unit: string;
  netKg: number;
  count: number;
  lines: ShareCardLine[];
}

/** 七日分享卡数据：只含周期、分口径合计与分类合计，不含记录编号、备注或身份信息 */
export interface ShareCardData {
  fromDay: string;
  toDay: string;
  recordCount: number;
  scopes: ShareCardScope[];
  disclaimer: string;
}

/**
 * 减排成果分享卡（赛题创新拓展 4：社交分享）。
 * 数据与隐私七日周报同源，渲染成一张存折样式的图片，由用户通过系统保存控件存入相册后自行分享；应用不直接发到任何平台。
 */
export class ShareCardService {
  static readonly DISCLAIMER: string = '按公开因子对本人申报行为的估算，未经独立核实；不是完整个人碳足迹，也不是经核证碳资产。';

  static async build(db: LedgerDb, endDay: string = DateUtil.today()): Promise<Result<ShareCardData>> {
    return LedgerOperations.run(() => ShareCardService.buildUnlocked(db, endDay));
  }

  private static async buildUnlocked(db: LedgerDb, endDay: string): Promise<Result<ShareCardData>> {
    if (!DateUtil.isValidDay(endDay)) {
      return Result.failure(ErrorCode.E_QUANTITY_INVALID, '统计结束日期无效。');
    }
    const fromDay = DateUtil.addDays(endDay, -6);
    try {
      const overview: StatsSummary = await StatsService.summary(db, TimeDimension.DAY, fromDay, endDay);
      const scopes: string[] = overview.gasScopes.filter((s: string) => s === 'CO2' || s === 'CO2e').sort();
      const out: ShareCardScope[] = [];
      let total = 0;
      for (const scope of scopes) {
        const summary = await StatsService.summary(db, TimeDimension.DAY, fromDay, endDay, null, scope);
        const lines: ShareCardLine[] = summary.categories.filter((c) => c.count > 0).map((c) => ({
          category: c.category, label: c.label, count: c.count, netKg: NumUtil.roundCalc(c.netKg)
        }) as ShareCardLine);
        out.push({ unit: scope === 'CO2' ? 'kgCO₂' : 'kgCO₂e', netKg: NumUtil.roundCalc(summary.totalNetKg),
          count: summary.recordCount, lines: lines });
        total += summary.recordCount;
      }
      const card: ShareCardData = { fromDay: fromDay, toDay: endDay, recordCount: total, scopes: out,
        disclaimer: ShareCardService.DISCLAIMER };
      return Result.success(card);
    } catch (e) {
      return Result.failure(ErrorCode.E_STORAGE, `生成分享卡失败：${(e as Error).message}`);
    }
  }
}
