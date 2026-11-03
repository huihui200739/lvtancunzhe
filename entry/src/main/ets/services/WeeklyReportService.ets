import { LedgerOperations } from './LedgerOperations';
import { StatsService } from './StatsService';
import { LedgerDb } from './LedgerDb';
import { Result, ErrorCode } from '../common/AppError';
import { DateUtil, NumUtil } from '../common/Format';
import { TimeDimension } from '../common/Domain';
import { StatsSummary } from '../models/StatsModels';

/** 生成不含记录编号、备注或用户身份信息的七日分享文本。 */
export class WeeklyReportService {
  static async buildWeeklyReport(db: LedgerDb, endDay: string = DateUtil.today()): Promise<Result<string>> {
    return LedgerOperations.run(() => WeeklyReportService.buildUnlocked(db, endDay));
  }

  private static async buildUnlocked(db: LedgerDb, endDay: string): Promise<Result<string>> {
    if (!DateUtil.isValidDay(endDay)) {
      return Result.failure(ErrorCode.E_QUANTITY_INVALID, '统计结束日期无效，未生成周报。');
    }
    const fromDay = DateUtil.addDays(endDay, -6);
    try {
      const overview: StatsSummary = await StatsService.summary(db, TimeDimension.DAY, fromDay, endDay);
      const scopes: string[] = [];
      for (const scope of overview.gasScopes) {
        if ((scope === 'CO2' || scope === 'CO2e') && scopes.indexOf(scope) < 0) { scopes.push(scope); }
      }
      scopes.sort();
      const summaries: StatsSummary[] = [];
      let recordCount = 0;
      for (const scope of scopes) {
        const summary = await StatsService.summary(db, TimeDimension.DAY, fromDay, endDay, null, scope);
        summaries.push(summary);
        recordCount += summary.recordCount;
      }
      const lines: string[] = [
        '绿碳存折 · 七日行动回顾',
        `统计周期：${fromDay} 至 ${endDay}`,
        `有效记录：${recordCount} 条`,
        ''
      ];
      if (scopes.length === 0) {
        lines.push('本周期还没有可汇总的有效记录。');
      } else {
        lines.push('按气体口径分别统计（不跨口径合并）：');
        for (let i = 0; i < scopes.length; i++) {
          const scope = scopes[i];
          const summary = summaries[i];
          const gasLabel = scope === 'CO2' ? 'CO₂ / kgCO₂' : 'CO₂e / kgCO₂e';
          lines.push('');
          lines.push(`${gasLabel} · ${summary.recordCount} 条`);
          lines.push(`正向贡献 ${NumUtil.show(summary.totalPositiveKg)} kg · 排放增加 ${NumUtil.show(summary.totalNegativeKg)} kg · 净变化 ${NumUtil.show(summary.totalNetKg)} kg`);
          for (const category of summary.categories) {
            lines.push(`  ${category.label}：${category.count} 条，净变化 ${NumUtil.show(category.netKg)} kg`);
          }
        }
      }
      lines.push('');
      lines.push('说明：仅汇总本地已记录行为的用户申报估算，不是完整个人碳足迹，也不是经核证碳资产。分享前请自行检查内容。');
      return Result.success(lines.join('\n'));
    } catch (e) {
      return Result.failure(ErrorCode.E_STORAGE, `生成周报失败：${WeeklyReportService.errText(e)}`);
    }
  }

  private static errText(e: object): string {
    const msg = (e as Error).message;
    return msg !== undefined ? msg : JSON.stringify(e);
  }
}
