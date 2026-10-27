import { LedgerOperations } from './LedgerOperations';
import { LedgerDb } from './LedgerDb';
import { CalcEngine } from './CalcEngine';
import { FactorRepository } from './FactorRepository';
import { PointService } from './PointService';
import { RecordPlanSync } from './RecordPlanSync';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Result, ErrorCode } from '../common/AppError';
import { DateUtil } from '../common/Format';
import { Ids } from '../common/Ids';
import {
  BehaviorRecord, CalculationSnapshot, RecordDraft, VoucherFactorSource, VoucherView
} from '../models/RecordModels';
import { CalcOutcome, ScenarioResult } from '../models/CalcModels';
import { CarbonFactor, factorUnitText } from '../models/CarbonFactor';
import { BehaviorCategory, EntrySource, RecordStatus, SCOPE_STATEMENT, gasUnitLabel } from '../common/Domain';

const DOMAIN = 0x0000;

/**
 * 行为记录服务（主链路：记录行为 → 核算 → 入账 → 生成凭证）。
 *
 * 第 8.4 节：提交记录时，把行为、计算快照与积分事件放入一个事务；
 * 修订保留旧版本并写积分差额；撤销写状态与冲正事件。任何失败均回滚。
 */
export class RecordService {

  /** 新建记录并入账 */
  static async createRecord(db: LedgerDb, repo: FactorRepository, draft: RecordDraft): Promise<Result<VoucherView>> {
    return LedgerOperations.run(() => RecordService.createRecordUnlocked(db, repo, draft));
  }

  private static async createRecordUnlocked(db: LedgerDb, repo: FactorRepository, draft: RecordDraft): Promise<Result<VoucherView>> {
    if (!DateUtil.isValidDay(draft.occurredAt)) { return Result.failure(ErrorCode.E_INPUT_EMPTY, '请输入有效日期，格式为 YYYY-MM-DD。'); }
    if (DateUtil.isFuture(draft.occurredAt)) {
      return Result.failure(ErrorCode.E_FUTURE_DATE, '未来日期不能作为已完成的行为记录，请改选发生日期。');
    }
    for (const scenario of draft.scenarios) {
      const factor = repo.find(scenario.factorCode);
      if (factor !== undefined && factor.evidenceRequirement && (draft.applicabilityAccepted !== true || draft.remark.trim().length === 0)) {
        return Result.failure(ErrorCode.E_INPUT_EMPTY, '请确认此场景的适用条件，并在备注中填写数量、基准和处理路径等依据。');
      }
    }
    const outcome = CalcEngine.calculate({
      category: draft.category,
      baselineType: draft.baselineType,
      scenarios: draft.scenarios
    }, repo, draft.passengers);
    if (!outcome.ok) {
      return Result.failure(outcome.errorCode, outcome.message);
    }

    const now = DateUtil.toDateTime(new Date());
    const recordId = Ids.withPrefix('rec');
    const revision = 1;
    const record = RecordService.buildRecord(recordId, revision, draft, now, '');

    // 事务前结算：RDB 事务内读不到未提交写入，故先按已提交状态 + 本次变更推算
    const totalsAfter = await db.eligibleReductionTotalsExcluding(recordId);
    if (outcome.reductionKg > 0) { totalsAfter.set(`${outcome.gasScope}`, (totalsAfter.get(`${outcome.gasScope}`) || 0) + outcome.reductionKg); }
    const activeDaysAfter = RecordService.unionDays(await db.listActiveDaysExcluding(recordId), draft.occurredAt);
    const plan = await PointService.planSettlement(db, recordId, revision, draft.occurredAt,
      totalsAfter, activeDaysAfter);

    try {
      await db.begin();
      await db.insertRecord(record);
      await db.insertSnapshot(RecordService.buildSnapshot(recordId, revision, draft, outcome, now, repo));
      await PointService.applySettlement(db, plan, recordId, revision, draft.occurredAt);
      await db.commit();
    } catch (e) {
      await db.rollBack();
      return Result.failure(ErrorCode.E_STORAGE, `入账失败，已回滚：${RecordService.errText(e)}`);
    }
    // 徽章在提交后判定（读取已提交状态，幂等；跨记录自愈）
    try {
      await PointService.evaluateBadges(db, plan.streak);
    } catch (e) {
      hilog.warn(DOMAIN, 'RecordService', 'badge evaluation failed: %{public}s', RecordService.errText(e));
    }
    return RecordService.getVoucherUnlocked(db, recordId, revision);
  }

  /** 修订记录：保留旧版本，写入新版本与积分差额 */
  static async reviseRecord(db: LedgerDb, repo: FactorRepository, recordId: string, baseRevision: number,
    draft: RecordDraft): Promise<Result<VoucherView>> {
    return LedgerOperations.run(() => RecordService.reviseRecordUnlocked(db, repo, recordId, baseRevision, draft));
  }

  private static async reviseRecordUnlocked(db: LedgerDb, repo: FactorRepository, recordId: string, baseRevision: number,
    draft: RecordDraft): Promise<Result<VoucherView>> {
    if (!DateUtil.isValidDay(draft.occurredAt)) { return Result.failure(ErrorCode.E_INPUT_EMPTY, '请输入有效日期，格式为 YYYY-MM-DD。'); }
    if (DateUtil.isFuture(draft.occurredAt)) {
      return Result.failure(ErrorCode.E_FUTURE_DATE, '未来日期不能作为已完成的行为记录。');
    }
    for (const scenario of draft.scenarios) {
      const factor = repo.find(scenario.factorCode);
      if (factor !== undefined && factor.evidenceRequirement && (draft.applicabilityAccepted !== true || draft.remark.trim().length === 0)) {
        return Result.failure(ErrorCode.E_INPUT_EMPTY, '请确认此场景的适用条件，并在备注中填写数量、基准和处理路径等依据。');
      }
    }
    const outcome = CalcEngine.calculate({
      category: draft.category,
      baselineType: draft.baselineType,
      scenarios: draft.scenarios
    }, repo, draft.passengers);
    if (!outcome.ok) {
      return Result.failure(outcome.errorCode, outcome.message);
    }
    const versions = await db.listRecordVersions(recordId);
    if (versions.length === 0) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '找不到要修订的记录。');
    }
    const currentRecord = await db.getRecord(recordId, baseRevision);
    let maxRev = 0;
    for (const v of versions) {
      if (v.revision > maxRev) {
        maxRev = v.revision;
      }
    }
    if (currentRecord === null || currentRecord.status !== RecordStatus.ACTIVE || baseRevision !== maxRev) { return Result.failure(ErrorCode.E_INPUT_EMPTY, '仅可修订最新的有效记录，旧版本凭证保持原样。'); }
    const newRevision = maxRev + 1;
    const now = DateUtil.toDateTime(new Date());
    const record = RecordService.buildRecord(recordId, newRevision, draft, now, `${recordId}#${baseRevision}`);

    // 事务前结算：排除该记录的全部版本后，加上本次新版本的合格减排量
    const totalsAfter = await db.eligibleReductionTotalsExcluding(recordId);
    if (outcome.reductionKg > 0) { totalsAfter.set(`${outcome.gasScope}`, (totalsAfter.get(`${outcome.gasScope}`) || 0) + outcome.reductionKg); }
    const activeDaysAfter = RecordService.unionDays(await db.listActiveDaysExcluding(recordId), draft.occurredAt);
    const plan = await PointService.planSettlement(db, recordId, newRevision, draft.occurredAt,
      totalsAfter, activeDaysAfter);

    try {
      await db.begin();
      await db.insertRecord(record);
      await db.insertSnapshot(RecordService.buildSnapshot(recordId, newRevision, draft, outcome, now, repo));
      await PointService.applySettlement(db, plan, recordId, newRevision, draft.occurredAt);
      await RecordPlanSync.apply(db, record, RecordService.buildSnapshot(recordId, newRevision, draft, outcome, now, repo), repo);
      await db.commit();
    } catch (e) {
      await db.rollBack();
      return Result.failure(ErrorCode.E_STORAGE, `修订失败，已回滚：${RecordService.errText(e)}`);
    }
    try {
      await PointService.evaluateBadges(db, plan.streak);
    } catch (e) {
      hilog.warn(DOMAIN, 'RecordService', 'badge evaluation failed: %{public}s', RecordService.errText(e));
    }
    return RecordService.getVoucherUnlocked(db, recordId, newRevision);
  }

  /** 撤销记录：写状态 + 冲正积分，不物理删除 */
  static async voidRecord(db: LedgerDb, recordId: string, revision: number): Promise<Result<boolean>> {
    return LedgerOperations.run(() => RecordService.voidRecordUnlocked(db, recordId, revision));
  }

  private static async voidRecordUnlocked(db: LedgerDb, recordId: string, revision: number): Promise<Result<boolean>> {
    const rec = await db.getRecord(recordId, revision);
    if (rec === null) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '找不到要撤销的记录。');
    }
    if (rec.status === RecordStatus.VOIDED) { return Result.success(true); }
    const versions = await db.listRecordVersions(recordId);
    if (versions.some((v: BehaviorRecord) => v.revision > revision)) { return Result.failure(ErrorCode.E_INPUT_EMPTY, '旧版本只能查看，请在最新凭证中撤销。'); }
    // 事务前结算：撤销后该记录不再计入，排除其全部版本
    const totalsAfter = await db.eligibleReductionTotalsExcluding(recordId);
    const activeDaysAfter = await db.listActiveDaysExcluding(recordId);
    const plan = await PointService.planSettlement(db, recordId, revision, rec.occurredAt,
      totalsAfter, activeDaysAfter);

    try {
      await db.begin();
      await db.updateRecordStatus(recordId, revision, RecordStatus.VOIDED);
      await PointService.applySettlement(db, plan, recordId, revision, rec.occurredAt);
      rec.status = RecordStatus.VOIDED;
      await RecordPlanSync.apply(db, rec, null, FactorRepository.createDefault());
      await db.commit();
    } catch (e) {
      await db.rollBack();
      return Result.failure(ErrorCode.E_STORAGE, `撤销失败，已回滚：${RecordService.errText(e)}`);
    }
    try {
      await PointService.evaluateBadges(db, plan.streak);
    } catch (e) {
      hilog.warn(DOMAIN, 'RecordService', 'badge evaluation failed: %{public}s', RecordService.errText(e));
    }
    return Result.success(true);
  }

  /** 合并日期集合（去重），用于推算变更后的有效记录日期 */
  private static unionDays(days: string[], extra: string): string[] {
    const out: string[] = [];
    for (const d of days) {
      out.push(d);
    }
    if (extra.length > 0 && days.indexOf(extra) < 0) {
      out.push(extra);
    }
    return out;
  }

  /** 列出记录（最新版本） */
  static async listRecords(db: LedgerDb): Promise<BehaviorRecord[]> {
    return db.listLatestRecords(-1);
  }

  /** 组装凭证视图（第 5.3 节字段顺序：行为 → 对照 → 计算 → 来源 → 范围 → 变更） */
  static async getVoucher(db: LedgerDb, recordId: string, revision: number): Promise<Result<VoucherView>> {
    return LedgerOperations.run(() => RecordService.getVoucherUnlocked(db, recordId, revision));
  }

  private static async getVoucherUnlocked(db: LedgerDb, recordId: string, revision: number): Promise<Result<VoucherView>> {
    const record = await db.getRecord(recordId, revision);
    if (record === null) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '找不到该记录。');
    }
    const snapshot = await db.getSnapshot(recordId, revision);
    if (snapshot === null) {
      return Result.failure(ErrorCode.E_STORAGE, '该记录缺少计算快照。');
    }
    const versions = await db.listRecordVersions(recordId);
    let maxRev = 0;
    for (const v of versions) {
      if (v.revision > maxRev) {
        maxRev = v.revision;
      }
    }

    const scenarios: ScenarioResult[] = JSON.parse(snapshot.scenariosJson) as ScenarioResult[];
    const sources: VoucherFactorSource[] = JSON.parse(snapshot.factorSourcesJson) as VoucherFactorSource[];

    const events = await db.listPointEvents(-1);
    let pointDelta = 0;
    for (const e of events) {
      if (e.recordId === recordId && e.revision === revision) {
        pointDelta = pointDelta + e.delta;
      }
    }

    const view: VoucherView = {
      record: record,
      snapshot: snapshot,
      scenarios: scenarios,
      sources: sources,
      isLatest: record.revision === maxRev && record.status === RecordStatus.ACTIVE,
      pointDelta: pointDelta
    };
    return Result.success(view);
  }

  /**
   * 相似记录提示（第 9.2 节）：对同类、相近时间和数量的记录给出提示，
   * 用户确认后保留，不使用模糊匹配静默删除合法记录。
   */
  static async findSimilarCount(db: LedgerDb, recordId: string, category: string,
    dayKey: string, quantity: number): Promise<number> {
    const all = await db.listLatestRecords(-1);
    let count = 0;
    for (const r of all) {
      if (r.recordId === recordId || r.status !== RecordStatus.ACTIVE) {
        continue;
      }
      if (`${r.category}` === category && r.occurredAt === dayKey) {
        const diff = Math.abs(r.quantity - quantity);
        if (diff <= quantity * 0.2 + 0.0001) {
          count = count + 1;
        }
      }
    }
    return count;
  }

  // —— 内部 ——

  /** 依据标签（第 5.4 节）。标签不代表行为真实性认证。 */
  private static evidenceLabel(source: EntrySource): string {
    if (source === EntrySource.IMAGE_ASSISTED) {
      return '图片辅助填写，用户已确认';
    }
    return '用户填写，数量未独立核实';
  }

  private static buildRecord(recordId: string, revision: number, draft: RecordDraft,
    now: string, parentRecordId: string): BehaviorRecord {
    const first = draft.category === BehaviorCategory.TRAVEL ? draft.scenarios.find((s) => `${s.role}` === 'actual') : (draft.scenarios.length > 0 ? draft.scenarios[0] : null);
    return {
      recordId: recordId,
      revision: revision,
      category: draft.category,
      quantity: first !== null && first !== undefined ? first.quantity : 0,
      unit: first !== null && first !== undefined ? first.unit : '',
      occurredAt: draft.occurredAt,
      status: RecordStatus.ACTIVE,
      entrySource: draft.entrySource,
      entryNote: RecordService.evidenceLabel(draft.entrySource),
      remark: draft.remark,
      createdAt: now,
      updatedAt: now,
      parentRecordId: parentRecordId
    };
  }

  /** 计算快照：冻结输入、因子值、来源与结果，保证历史可重现（第 5.4 节） */
  private static buildSnapshot(recordId: string, revision: number, draft: RecordDraft,
    outcome: CalcOutcome, now: string, repo: FactorRepository): CalculationSnapshot {
    const sources: VoucherFactorSource[] = [];
    for (const r of outcome.scenarioResults) {
      const f: CarbonFactor | undefined = repo.find(r.factorCode);
      if (f === undefined) {
        continue;
      }
      sources.push({
        factorCode: f.code,
        factorVersion: f.version,
        factorName: f.scenarioLabel,
        value: f.value,
        gasScope: `${gasUnitLabel(f.gasScope)}/${f.perUnit}`,
        region: f.region,
        dataYear: f.dataYear,
        boundary: f.boundary,
        methodology: f.methodology,
        sourceTitle: f.sourceTitle,
        sourceUrl: f.sourceUrl,
        sourceLocator: f.sourceLocator,
        licenseNote: f.licenseNote,
        applicabilityNote: f.evidenceRequirement || '',
        applicabilityConfirmed: draft.applicabilityAccepted === true,
        reviewStatus: `${f.reviewStatus}`
      });
    }
    return {
      snapshotId: Ids.withPrefix('snp'),
      recordId: recordId,
      revision: revision,
      category: draft.category,
      baselineType: draft.baselineType,
      gasScope: outcome.gasScope,
      reductionKg: outcome.reductionKg,
      isNetIncrease: outcome.isNetIncrease,
      formulaVersion: outcome.formulaVersion,
      formulaText: outcome.formulaText,
      roundingNote: outcome.roundingNote,
      scenariosJson: JSON.stringify(outcome.scenarioResults),
      factorSourcesJson: JSON.stringify(sources),
      evidenceLabel: RecordService.evidenceLabel(draft.entrySource),
      scopeNote: `${gasUnitLabel(outcome.gasScope)}；${SCOPE_STATEMENT}`,
      createdAt: now
    };
  }

  private static errText(e: object): string {
    const msg = (e as Error).message;
    return msg !== undefined ? msg : JSON.stringify(e);
  }
}
