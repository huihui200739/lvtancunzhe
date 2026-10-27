import { LedgerOperations } from './LedgerOperations';
import { PlanLinkPolicy } from './PlanLinkPolicy';
import { LedgerDb } from './LedgerDb';
import { PlanEngine } from './PlanEngine';
import { RecordService } from './RecordService';
import { PointService } from './PointService';
import { FactorRepository } from './FactorRepository';
import { Tables } from './LedgerSchema';
import { Result, ErrorCode } from '../common/AppError';
import { DateUtil } from '../common/Format';
import { Ids } from '../common/Ids';
import { PlanConstraints, PlanOutcome, PlanProposal, PlanSolution, PlanTask, TaskTemplate, WeeklyPlan } from '../models/PlanModels';
import { BehaviorRecord, RecordDraft } from '../models/RecordModels';
import { PlanTaskStatus } from '../common/Domain';

/**
 * 七日减排计划服务（第 6.3 / 6.4 节、第 8.2 节接口）。
 *
 *  - generatePlan(constraints)：调用纯引擎求解并持久化，写入约束快照与因子版本；
 *  - completeTask(taskId, recordId)：先关联真实记录，再更新状态与参与奖励；仅勾选不产生减排量；
 *  - replan：保留已完成任务，只重排未完成任务；
 *  - 记录撤销后回算任务状态与参与积分。
 *
 * 计划预计贡献、实际记录贡献与任务激励积分分别保存，任何失败均回滚。
 */
export class PlanService {
  private static completing: boolean = false;

  /** 生成并保存七日计划 */
  static async generatePlan(db: LedgerDb, repo: FactorRepository,
    constraints: PlanConstraints): Promise<Result<PlanOutcome>> {
    return LedgerOperations.run(() => PlanService.generatePlanUnlocked(db, repo, constraints));
  }

  private static async generatePlanUnlocked(db: LedgerDb, repo: FactorRepository,
    constraints: PlanConstraints): Promise<Result<PlanOutcome>> {
    let templates: TaskTemplate[] = [];
    try {
      templates = await db.listTemplates();
    } catch (e) {
      return Result.failure(ErrorCode.E_STORAGE, `读取任务模板失败：${PlanService.errText(e)}`);
    }
    if (templates.length === 0) {
      return Result.failure(ErrorCode.E_PLAN_NO_CANDIDATE, '任务模板池为空，无法生成计划。');
    }
    const solution = PlanEngine.generate(constraints, templates, repo);
    if (!solution.ok) {
      return Result.success(PlanService.toOutcome(null, [], constraints, solution));
    }
    return PlanService.persist(db, repo, constraints, solution);
  }

  /** 重新规划：保留已完成 / 已关联记录的任务，只重排未完成任务 */
  static async replan(db: LedgerDb, repo: FactorRepository,
    constraints: PlanConstraints): Promise<Result<PlanOutcome>> {
    return LedgerOperations.run(() => PlanService.replanUnlocked(db, repo, constraints));
  }

  private static async replanUnlocked(db: LedgerDb, repo: FactorRepository,
    constraints: PlanConstraints): Promise<Result<PlanOutcome>> {
    const latestId = await db.getLatestPlanId();
    const keep: PlanTask[] = [];
    if (latestId.length > 0) {
      const tasks = await db.listPlanTasks(latestId);
      for (const t of tasks) {
        if ((t.status === PlanTaskStatus.COMPLETED || t.status === PlanTaskStatus.LINKED) && t.day >= constraints.startDay && t.day <= DateUtil.addDays(constraints.startDay, 6)) {
          keep.push(t);
        }
      }
    }
    if (keep.some((t: PlanTask) => !t.participationOnly)) {
      const previous = await db.getPlan(latestId);
      const previousConstraints = previous !== null ? PlanService.parseConstraints(previous.constraintsJson) : null;
      if (previousConstraints !== null) {
        if (constraints.gasScope.length > 0 && constraints.gasScope !== previousConstraints.gasScope) { return Result.failure(ErrorCode.E_GAS_SCOPE_MIXED, '已完成任务的气体口径需要保留，本次重排请沿用原口径。'); }
        constraints.gasScope = previousConstraints.gasScope;
      }
    }
    const reserved: PlanProposal[] = keep.map((t: PlanTask): PlanProposal => ({ templateId: t.templateId, name: t.name,
      category: t.category, day: t.day, expectedKg: t.expectedKg, quantity: t.quantity, unit: t.unit,
      extraMinutes: t.extraMinutes, extraCost: t.extraCost, participationOnly: t.participationOnly, reason: t.reason }));
    let templates: TaskTemplate[] = [];
    try {
      templates = await db.listTemplates();
    } catch (e) {
      return Result.failure(ErrorCode.E_STORAGE, `读取任务模板失败：${PlanService.errText(e)}`);
    }
    const solution = PlanEngine.generate(constraints, templates, repo, reserved);
    if (!solution.ok) { return Result.failure(solution.code, solution.message); }
    // 已完成的 (模板, 日期) 不再重复安排
    const keptKeys: string[] = [];
    for (const k of keep) {
      keptKeys.push(`${k.templateId}#${k.day}`);
    }
    const filtered: PlanSolution = {
      ok: solution.ok,
      code: solution.code,
      message: solution.message,
      proposals: [],
      plannedKg: solution.plannedKg,
      gapKg: solution.gapKg,
      participationCount: solution.participationCount,
      targetMet: solution.targetMet,
      gasScope: solution.gasScope,
      trace: solution.trace
    };
    for (const p of solution.proposals) {
      if (keptKeys.indexOf(`${p.templateId}#${p.day}`) < 0) {
        filtered.proposals.push(p);
      }
    }
    return PlanService.persist(db, repo, constraints, filtered, keep);
  }

  /** 最近一份计划 */
  static async latestPlan(db: LedgerDb): Promise<PlanOutcome | null> {
    return LedgerOperations.run(() => PlanService.latestPlanUnlocked(db));
  }

  private static async latestPlanUnlocked(db: LedgerDb): Promise<PlanOutcome | null> {
    const planId = await db.getLatestPlanId();
    if (planId.length === 0) {
      return null;
    }
    const plan = await db.getPlan(planId);
    if (plan === null) {
      return null;
    }
    const tasks = await db.listPlanTasks(planId);
    const constraints = PlanService.parseConstraints(plan.constraintsJson);
    let planned = 0;
    let participation = 0;
    for (const t of tasks) {
      if (t.status === PlanTaskStatus.SKIPPED) { continue; }
      if (t.participationOnly) {
        participation = participation + 1;
      } else {
        planned = planned + t.expectedKg;
      }
    }
    const target = constraints !== null ? constraints.targetKg : 0;
    const gap = target > planned ? target - planned : 0;
    const outcome: PlanOutcome = {
      ok: true,
      code: ErrorCode.OK,
      message: '',
      plan: plan,
      tasks: tasks,
      plannedKg: planned,
      gapKg: gap,
      participationCount: participation,
      targetMet: gap <= 0,
      trace: []
    };
    return outcome;
  }

  /** 计划下的任务列表 */
  static async listTasks(db: LedgerDb, planId: string): Promise<PlanTask[]> {
    return db.listPlanTasks(planId);
  }

  /**
   * 完成任务：关联一条已存在的真实行为记录后更新状态。
   * 仅点击勾选不会调用本方法，因此不产生减排量（第 6.4 节、T16）。
   */
  static async completeTask(db: LedgerDb, planTaskId: string, recordId: string): Promise<Result<PlanTask>> {
    return LedgerOperations.run(() => PlanService.completeTaskUnlocked(db, planTaskId, recordId));
  }

  private static async completeTaskUnlocked(db: LedgerDb, planTaskId: string, recordId: string): Promise<Result<PlanTask>> {
    if (PlanService.completing) { return Result.failure(ErrorCode.E_STORAGE, '正在更新任务，请稍后重试。'); }
    PlanService.completing = true;
    try {
      await db.begin();
      const task = await db.getPlanTask(planTaskId);
      if (task === null) { await db.rollBack(); return Result.failure(ErrorCode.E_INPUT_EMPTY, '找不到该计划任务。'); }
      if (task.status === PlanTaskStatus.COMPLETED || task.status === PlanTaskStatus.LINKED) {
        await db.rollBack();
        return task.linkedRecordId === recordId ? Result.success(task) : Result.failure(ErrorCode.E_DUPLICATE_REWARD, '这项任务已关联其他记录。');
      }
      const revision = await PlanService.latestRevision(db, recordId);
      const rec = revision > 0 ? await db.getRecord(recordId, revision) : null;
      const snapshot = revision > 0 ? await db.getSnapshot(recordId, revision) : null;
      if (rec === null || snapshot === null) { await db.rollBack(); return Result.failure(ErrorCode.E_INPUT_EMPTY, '找不到完整的有效行为记录。'); }
      const template = (await db.listTemplates()).find((t: TaskTemplate) => t.templateId === task.templateId);
      const error = PlanLinkPolicy.recordError(task, rec, snapshot, template, await db.listPlanTasksByRecord(recordId), FactorRepository.createDefault());
      if (error.length > 0) { await db.rollBack(); return Result.failure(ErrorCode.E_INPUT_EMPTY, error); }
      task.status = PlanTaskStatus.COMPLETED;
      task.linkedRecordId = recordId;
      task.actualKg = task.participationOnly ? 0 : snapshot.reductionKg;
      task.rewarded = (await PointService.awardParticipation(db, planTaskId, rec.occurredAt, recordId, revision)) > 0 || task.rewarded;
      await db.updatePlanTask(task);
      await db.commit();
      return Result.success(task);
    } catch (e) { await db.rollBack(); return Result.failure(ErrorCode.E_STORAGE, `完成任务失败，原状态已保留：${PlanService.errText(e)}`); }
    finally { PlanService.completing = false; }
  }

  /** Self-reported participation creates no carbon record or calculation snapshot. */
  static async completeParticipation(db: LedgerDb, planTaskId: string, day: string, evidence: string): Promise<Result<PlanTask>> {
    return LedgerOperations.run(() => PlanService.completeParticipationUnlocked(db, planTaskId, day, evidence));
  }

  private static async completeParticipationUnlocked(db: LedgerDb, planTaskId: string, day: string, evidence: string): Promise<Result<PlanTask>> {
    if (PlanService.completing) { return Result.failure(ErrorCode.E_STORAGE, '正在更新任务，请稍后重试。'); }
    PlanService.completing = true;
    try {
      await db.begin();
      const task = await db.getPlanTask(planTaskId);
      if (task === null || !task.participationOnly) { await db.rollBack(); return Result.failure(ErrorCode.E_INPUT_EMPTY, '这项任务需要正式核算记录，不能仅标记参与。'); }
      if (task.status === PlanTaskStatus.COMPLETED) { await db.rollBack(); return Result.success(task); }
      const error = PlanLinkPolicy.taskError(task);
      if (error.length > 0 || day !== task.day || !DateUtil.isValidDay(day) || evidence.trim().length === 0 || evidence.length > 500) {
        await db.rollBack(); return Result.failure(ErrorCode.E_INPUT_EMPTY, error.length > 0 ? error : '请填写安排日期当天的真实参与说明（1—500字）。');
      }
      task.status = PlanTaskStatus.COMPLETED;
      task.actualKg = 0;
      task.linkedRecordId = '';
      task.reason += `\n参与记录（用户声明，未独立核实）：${evidence.trim()}`;
      task.rewarded = (await PointService.awardParticipation(db, planTaskId, day, '', 0)) > 0;
      await db.updatePlanTask(task); await db.commit();
      return Result.success(task);
    } catch (e) { await db.rollBack(); return Result.failure(ErrorCode.E_STORAGE, `记录参与失败，已回滚：${PlanService.errText(e)}`); }
    finally { PlanService.completing = false; }
  }

  static async cancelParticipation(db: LedgerDb, planTaskId: string): Promise<Result<boolean>> {
    return LedgerOperations.run(() => PlanService.cancelParticipationUnlocked(db, planTaskId));
  }

  private static async cancelParticipationUnlocked(db: LedgerDb, planTaskId: string): Promise<Result<boolean>> {
    if (PlanService.completing) { return Result.failure(ErrorCode.E_STORAGE, '正在更新任务，请稍后重试。'); }
    PlanService.completing = true;
    try {
      await db.begin();
      const task = await db.getPlanTask(planTaskId);
      if (task === null || !task.participationOnly || task.linkedRecordId.length > 0) { await db.rollBack(); return Result.failure(ErrorCode.E_INPUT_EMPTY, '请在关联行为凭证中撤销这项任务。'); }
      if (task.status === PlanTaskStatus.SKIPPED) { await db.rollBack(); return Result.success(true); }
      if (task.status !== PlanTaskStatus.COMPLETED) { await db.rollBack(); return Result.failure(ErrorCode.E_INPUT_EMPTY, '这项任务尚未完成。'); }
      await PointService.revokeParticipation(db, planTaskId, DateUtil.today());
      task.status = PlanTaskStatus.SKIPPED; task.rewarded = false; task.actualKg = 0;
      task.reason += '\n参与标记已撤销，奖励已冲正。';
      await db.updatePlanTask(task); await db.commit(); return Result.success(true);
    } catch (e) { await db.rollBack(); return Result.failure(ErrorCode.E_STORAGE, `撤销参与失败：${PlanService.errText(e)}`); }
    finally { PlanService.completing = false; }
  }

  /**
   * 完成任务并同时新建真实记录（“先创建记录，核算成功后关联”）。
   */
  static async completeTaskWithNewRecord(db: LedgerDb, repo: FactorRepository, planTaskId: string,
    draft: RecordDraft): Promise<Result<PlanTask>> {
    const task = await db.getPlanTask(planTaskId);
    if (task === null) { return Result.failure(ErrorCode.E_INPUT_EMPTY, '找不到该计划任务。'); }
    const templates = await db.listTemplates();
    const error = PlanLinkPolicy.draftError(task, draft, templates.find((t: TaskTemplate) => t.templateId === task.templateId), repo);
    if (error.length > 0) { return Result.failure(ErrorCode.E_INPUT_EMPTY, error); }
    const created = await RecordService.createRecord(db, repo, draft);
    if (!created.ok || created.data === null) {
      return Result.failure(created.code, created.message);
    }
    return PlanService.completeTask(db, planTaskId, created.data.record.recordId);
  }

  /** 跳过任务 */
  static async skipTask(db: LedgerDb, planTaskId: string): Promise<Result<boolean>> {
    return LedgerOperations.run(() => PlanService.skipTaskUnlocked(db, planTaskId));
  }

  private static async skipTaskUnlocked(db: LedgerDb, planTaskId: string): Promise<Result<boolean>> {
    const task = await db.getPlanTask(planTaskId);
    if (task === null) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '找不到该计划任务。');
    }
    if (task.status === PlanTaskStatus.COMPLETED || task.status === PlanTaskStatus.LINKED) { return Result.failure(ErrorCode.E_INPUT_EMPTY, '已完成任务不能直接跳过，请撤销其参与记录或关联行为。'); }
    const updated: PlanTask = {
      planTaskId: task.planTaskId,
      planId: task.planId,
      templateId: task.templateId,
      name: task.name,
      category: task.category,
      day: task.day,
      status: PlanTaskStatus.SKIPPED,
      expectedKg: task.expectedKg,
      quantity: task.quantity,
      unit: task.unit,
      extraMinutes: task.extraMinutes,
      extraCost: task.extraCost,
      reason: task.reason,
      participationOnly: task.participationOnly,
      linkedRecordId: task.linkedRecordId,
      actualKg: task.actualKg,
      rewarded: task.rewarded
    };
    await db.updatePlanTask(updated);
    return Result.success(true);
  }

  /**
   * 记录撤销后回算：把关联任务退回「计划中」，并冲正参与奖励（第 6.4 节、T05）。
   */
  static async onRecordVoided(db: LedgerDb, recordId: string): Promise<void> {
    return LedgerOperations.run(() => PlanService.onRecordVoidedUnlocked(db, recordId));
  }

  private static async onRecordVoidedUnlocked(db: LedgerDb, recordId: string): Promise<void> {
    const tasks = await db.listPlanTasksByRecord(recordId);
    for (const t of tasks) {
      try {
        await db.begin();
        await PointService.revokeParticipation(db, t.planTaskId, DateUtil.today());
        const updated: PlanTask = {
          planTaskId: t.planTaskId,
          planId: t.planId,
          templateId: t.templateId,
          name: t.name,
          category: t.category,
          day: t.day,
          status: PlanTaskStatus.PLANNED,
          expectedKg: t.expectedKg,
          quantity: t.quantity,
          unit: t.unit,
          extraMinutes: t.extraMinutes,
          extraCost: t.extraCost,
          reason: t.reason,
          participationOnly: t.participationOnly,
          linkedRecordId: '',
          actualKg: 0,
          rewarded: false
        };
        await db.updatePlanTask(updated);
        await db.commit();
      } catch (e) {
        await db.rollBack();
      }
    }
  }

  // —— 内部 ——

  private static async persist(db: LedgerDb, repo: FactorRepository, constraints: PlanConstraints,
    solution: PlanSolution, keep: PlanTask[] = []): Promise<Result<PlanOutcome>> {
    const planId = Ids.withPrefix('plan');
    const version = (await db.countRows(Tables.WEEKLY_PLAN)) + 1;
    const now = DateUtil.toDateTime(new Date());
    constraints.gasScope = solution.gasScope;
    const plan: WeeklyPlan = {
      planId: planId,
      planVersion: version,
      constraintsJson: JSON.stringify(constraints),
      createdAt: now,
      factorSetVersion: repo.setVersion()
    };

    const tasks: PlanTask[] = [];
    try {
      await db.begin();
      await db.insertPlan(plan);
      for (const t of keep) {
        const kept: PlanTask = {
          planTaskId: t.planTaskId,
          planId: planId,
          templateId: t.templateId,
          name: t.name,
          category: t.category,
          day: t.day,
          status: t.status,
          expectedKg: t.expectedKg,
          quantity: t.quantity,
          unit: t.unit,
          extraMinutes: t.extraMinutes,
          extraCost: t.extraCost,
          reason: t.reason,
          participationOnly: t.participationOnly,
          linkedRecordId: t.linkedRecordId,
          actualKg: t.actualKg,
          rewarded: t.rewarded
        };
        await db.updatePlanTask(kept);
        tasks.push(kept);
      }
      for (const p of solution.proposals) {
        const task: PlanTask = {
          planTaskId: Ids.withPrefix('ptask'),
          planId: planId,
          templateId: p.templateId,
          name: p.name,
          category: p.category,
          day: p.day,
          status: PlanTaskStatus.PLANNED,
          expectedKg: p.expectedKg,
          quantity: p.quantity,
          unit: p.unit,
          extraMinutes: p.extraMinutes,
          extraCost: p.extraCost,
          reason: p.reason,
          participationOnly: p.participationOnly,
          linkedRecordId: '',
          actualKg: 0,
          rewarded: false
        };
        await db.insertPlanTask(task);
        tasks.push(task);
      }
      await db.setMeta('latest_plan_id', planId);
      await db.commit();
    } catch (e) {
      await db.rollBack();
      return Result.failure(ErrorCode.E_STORAGE, `保存计划失败，已回滚：${PlanService.errText(e)}`);
    }
    return Result.success(PlanService.toOutcome(plan, tasks, constraints, solution));
  }

  private static toOutcome(plan: WeeklyPlan | null, tasks: PlanTask[], constraints: PlanConstraints,
    solution: PlanSolution): PlanOutcome {
    const outcome: PlanOutcome = {
      ok: solution.ok,
      code: solution.code,
      message: solution.message,
      plan: plan,
      tasks: tasks,
      plannedKg: solution.plannedKg,
      gapKg: solution.gapKg,
      participationCount: solution.participationCount,
      targetMet: solution.targetMet,
      trace: solution.trace
    };
    return outcome;
  }

  private static parseConstraints(json: string): PlanConstraints | null {
    try {
      return JSON.parse(json) as PlanConstraints;
    } catch (e) {
      return null;
    }
  }

  private static async latestRevision(db: LedgerDb, recordId: string): Promise<number> {
    const versions: BehaviorRecord[] = await db.listRecordVersions(recordId);
    let max = 0;
    for (const v of versions) {
      if (v.revision > max) {
        max = v.revision;
      }
    }
    return max;
  }

  private static errText(e: object): string {
    const msg = (e as Error).message;
    return msg !== undefined ? msg : JSON.stringify(e);
  }
}
