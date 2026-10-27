import { LedgerOperations } from './LedgerOperations';
import { LedgerDb } from './LedgerDb';
import { StatsService } from './StatsService';
import { Result, ErrorCode } from '../common/AppError';
import { NumUtil } from '../common/Format';
import { CalculationSnapshot, VoucherFactorSource } from '../models/RecordModels';
import { ScenarioResult } from '../models/CalcModels';
import { PointEvent } from '../models/PointModels';
import { BaselineType, GasScope, ScenarioRole, TimeDimension, categoryName, gasUnitLabel } from '../common/Domain';

/**
 * CSV 导出服务（第 9.4 节、第 4.1 节 B5）。
 *
 *  - 提供明细、分类汇总与期间汇总三类；
 *  - 输出 UTF-8 BOM，中文在表格软件中可读；
 *  - 正确处理逗号、引号与换行；
 *  - 对可能被表格软件当作公式执行的前缀（= + - @ 以及制表符 / 回车）加单引号前缀。
 */
export class CsvService {

  /** UTF-8 BOM，保证 Excel 等软件按 UTF-8 解析中文 */
  static readonly BOM = '\uFEFF';

  /** 明细 CSV */
  static async detailCsv(db: LedgerDb): Promise<Result<string>> {
    return LedgerOperations.run(() => CsvService.detailCsvUnlocked(db));
  }

  private static async detailCsvUnlocked(db: LedgerDb): Promise<Result<string>> {
    try {
      const records = await db.listLatestRecords(-1);
      const points = await CsvService.pointsByRecord(db);
      const lines: string[] = [];
      lines.push(CsvService.row([
        '记录编号', '类别', '数量', '单位', '发生日期', '录入方式', '基准类型',
        '基准情景', '实际情景', '减排量kg', '气体口径', '公式版本',
        '依据标签', '因子与来源版本', '积分', '状态'
      ]));
      for (const rec of records) {
        const snap = await db.getSnapshot(rec.recordId, rec.revision);
        if (snap === null) {
          continue;
        }
        const scenarios: ScenarioResult[] = JSON.parse(snap.scenariosJson) as ScenarioResult[];
        lines.push(CsvService.row([
          rec.recordId,
          categoryName(rec.category),
          NumUtil.fixed(rec.quantity, 4),
          rec.unit,
          rec.occurredAt,
          rec.entryNote,
          snap.baselineType === BaselineType.USER_DECLARED ? '用户声明的替代情景' : '方法学统计基线',
          CsvService.describeRole(scenarios, ScenarioRole.BASELINE),
          CsvService.describeRole(scenarios, ScenarioRole.ACTUAL),
          NumUtil.fixed(snap.reductionKg, 4),
          CsvService.scopeLabel(snap.gasScope),
          snap.formulaVersion,
          snap.evidenceLabel,
          CsvService.factorSummary(snap),
          `${CsvService.pointOf(points, rec.recordId, rec.revision)}`,
          `${rec.status}`
        ]));
      }
      return Result.success(CsvService.BOM + lines.join('\r\n') + '\r\n');
    } catch (e) {
      return Result.failure(ErrorCode.E_STORAGE, `导出明细失败：${CsvService.errText(e)}`);
    }
  }

  /** 分类汇总 CSV */
  static async categorySummaryCsv(db: LedgerDb): Promise<Result<string>> {
    return LedgerOperations.run(() => CsvService.categorySummaryCsvUnlocked(db));
  }

  private static async categorySummaryCsvUnlocked(db: LedgerDb): Promise<Result<string>> {
    try {
      const initial = await StatsService.summary(db, TimeDimension.YEAR, '0001-01-01', '9999-12-31');
      const lines: string[] = [];
      lines.push(CsvService.row(['类别', '气体口径', '正向贡献kg', '增加排放kg', '净变化kg', '记录数']));
      for (const scope of initial.gasScopes) {
        const summary = await StatsService.summary(db, TimeDimension.YEAR, '0001-01-01', '9999-12-31', null, scope);
        for (const c of summary.categories) {
          lines.push(CsvService.row([c.label, scope, NumUtil.fixed(c.positiveKg, 4), NumUtil.fixed(c.negativeKg, 4), NumUtil.fixed(c.netKg, 4), `${c.count}`]));
        }
        lines.push(CsvService.row(['口径小计', scope, NumUtil.fixed(summary.totalPositiveKg, 4), NumUtil.fixed(summary.totalNegativeKg, 4), NumUtil.fixed(summary.totalNetKg, 4), `${summary.recordCount}`]));
      }
      return Result.success(CsvService.BOM + lines.join('\r\n') + '\r\n');
    } catch (e) {
      return Result.failure(ErrorCode.E_STORAGE, `导出分类汇总失败：${CsvService.errText(e)}`);
    }
  }

  /** 期间汇总 CSV（按指定时间维度） */
  static async periodSummaryCsv(db: LedgerDb, dim: TimeDimension,
    from: string, to: string): Promise<Result<string>> {
    return LedgerOperations.run(() => CsvService.periodSummaryCsvUnlocked(db, dim, from, to));
  }

  private static async periodSummaryCsvUnlocked(db: LedgerDb, dim: TimeDimension,
    from: string, to: string): Promise<Result<string>> {
    try {
      const initial = await StatsService.summary(db, dim, from, to);
      const lines: string[] = [];
      lines.push(CsvService.row(['期间', '起点', '气体口径', '正向贡献kg', '增加排放kg', '净变化kg', '记录数']));
      for (const scope of initial.gasScopes) {
        const summary = await StatsService.summary(db, dim, from, to, null, scope);
        for (const b of summary.buckets) {
          lines.push(CsvService.row([b.label, b.key, scope, NumUtil.fixed(b.positiveKg, 4), NumUtil.fixed(b.negativeKg, 4), NumUtil.fixed(b.netKg, 4), `${b.count}`]));
        }
      }
      return Result.success(CsvService.BOM + lines.join('\r\n') + '\r\n');
    } catch (e) {
      return Result.failure(ErrorCode.E_STORAGE, `导出期间汇总失败：${CsvService.errText(e)}`);
    }
  }

  // —— 内部 ——

  private static async pointsByRecord(db: LedgerDb): Promise<Map<string, number>> {
    const events: PointEvent[] = await db.listPointEvents(-1);
    const map: Map<string, number> = new Map<string, number>();
    for (const e of events) {
      if (e.recordId.length === 0) {
        continue;
      }
      const key = `${e.recordId}#${e.revision}`;
      const cur = map.get(key);
      map.set(key, (cur !== undefined ? cur : 0) + e.delta);
    }
    return map;
  }

  private static pointOf(map: Map<string, number>, recordId: string, revision: number): number {
    const v = map.get(`${recordId}#${revision}`);
    return v !== undefined ? v : 0;
  }

  private static describeRole(scenarios: ScenarioResult[], role: ScenarioRole): string {
    const parts: string[] = [];
    for (const s of scenarios) {
      if (s.role === role) {
        parts.push(`${s.scenarioLabel} ${NumUtil.fixed(s.quantity, 2)} ${s.unit} × ${s.factorValue} ${s.factorUnit} = ${NumUtil.fixed(s.emissionKg, 4)} kg`);
      }
    }
    return parts.join('；');
  }

  private static factorSummary(snap: CalculationSnapshot): string {
    const list = JSON.parse(snap.factorSourcesJson) as VoucherFactorSource[];
    const parts: string[] = [];
    for (const f of list) {
      parts.push(`${f.factorCode}@${f.factorVersion}（${f.sourceTitle}）`);
    }
    return parts.join('；');
  }

  private static scopeLabel(scope: GasScope): string {
    return gasUnitLabel(scope);
  }

  /** 单元格转义：公式前缀中和 + 引号 / 逗号 / 换行转义 */
  static cell(value: string): string {
    let s = value !== undefined && value !== null ? value : '';
    // 防公式注入：表格软件可能把 = + - @ 及制表符 / 回车开头的单元格当作公式
    if (s.length > 0) {
      const first = s.charAt(0);
      if (first === '=' || first === '+' || first === '-' || first === '@' || first === '\t' || first === '\r') {
        s = `'${s}`;
      }
    }
    const needQuote = s.indexOf(',') >= 0 || s.indexOf('"') >= 0 || s.indexOf('\n') >= 0 || s.indexOf('\r') >= 0;
    if (needQuote) {
      s = `"${s.split('"').join('""')}"`;
    }
    return s;
  }

  private static row(cells: string[]): string {
    const out: string[] = [];
    for (const c of cells) {
      out.push(CsvService.cell(c));
    }
    return out.join(',');
  }

  private static errText(e: object): string {
    const msg = (e as Error).message;
    return msg !== undefined ? msg : JSON.stringify(e);
  }
}
