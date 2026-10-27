import { PlanTask, TaskTemplate } from '../models/PlanModels';
import { BehaviorRecord, CalculationSnapshot, RecordDraft } from '../models/RecordModels';
import { ScenarioResult } from '../models/CalcModels';
import { RecordStatus, PlanTaskStatus, BehaviorCategory, ScenarioRole } from '../common/Domain';
import { DateUtil } from '../common/Format';
import { FactorRepository } from './FactorRepository';

export class PlanLinkPolicy {
  static taskError(task: PlanTask): string {
    if (task.status === PlanTaskStatus.SKIPPED) { return '这项任务已跳过，请重排计划后再记录。'; }
    if (!DateUtil.isValidDay(task.day) || DateUtil.isFuture(task.day)) { return '任务安排日期尚未到来，完成当天再记录。'; }
    return '';
  }
  /** 在入账前检查关联条件，避免日期或行动填错后先产生一笔孤立记录。 */
  static draftError(task: PlanTask, draft: RecordDraft, template: TaskTemplate | undefined, repo: FactorRepository): string {
    const taskError = PlanLinkPolicy.taskError(task);
    if (taskError.length > 0) { return taskError; }
    if (task.participationOnly) { return '这项任务只记录参与，请从参与入口完成。'; }
    if (task.status === PlanTaskStatus.COMPLETED || task.linkedRecordId.length > 0) { return '这项任务已有完成记录，请返回计划查看。'; }
    if (draft.category !== task.category) { return '记录类别与任务不匹配。'; }
    if (draft.occurredAt !== task.day) { return '记录日期必须与这项任务的安排日期一致。'; }
    if (template === undefined || template.factorSubItem.length === 0) { return '缺少任务行动定义，请返回计划。'; }
    const requiredRole = task.category === BehaviorCategory.TRAVEL ? ScenarioRole.ACTUAL : ScenarioRole.BASELINE;
    for (const sc of draft.scenarios) {
      const f = repo.find(sc.factorCode);
      if (f !== undefined && repo.isUsable(f) && sc.role === requiredRole && sc.unit === task.unit &&
        Number.isFinite(sc.quantity) && sc.quantity > 0 &&
        (f.subItem === template.factorSubItem || (template.templateId === 'P02' && f.subItem === 'walk'))) { return ''; }
    }
    return '记录的实际行动与任务不匹配，请按任务要求选择情景。';
  }

  static recordError(task: PlanTask, record: BehaviorRecord, snapshot: CalculationSnapshot,
    template: TaskTemplate | undefined, linked: PlanTask[], repo: FactorRepository): string {
    const taskError = PlanLinkPolicy.taskError(task);
    if (taskError.length > 0) { return taskError; }
    if (record.status !== RecordStatus.ACTIVE) { return '已撤销的记录不能完成任务。'; }
    if (record.category !== task.category || snapshot.category !== task.category) { return '记录类别与任务不匹配。'; }
    if (record.occurredAt !== task.day) { return '记录日期必须与这项任务的安排日期一致。'; }
    if (record.unit !== task.unit || !Number.isFinite(record.quantity) || record.quantity <= 0) { return '记录单位或数量与任务不匹配。'; }
    for (const other of linked) {
      if (other.planTaskId !== task.planTaskId) { return '这笔记录已用于其他任务，不能重复关联或重复领取参与奖励。'; }
    }
    if (template === undefined || template.factorSubItem.length === 0) { return '缺少任务行动定义，请改用仅记录参与入口。'; }
    let scenarios: ScenarioResult[];
    try { scenarios = JSON.parse(snapshot.scenariosJson) as ScenarioResult[]; }
    catch (e) { return '记录的计算快照已损坏。'; }
    if (!Array.isArray(scenarios)) { return '记录的计算快照已损坏。'; }
    let matched = false;
    for (const sc of scenarios) {
      const f = repo.find(sc.factorCode);
      const requiredRole = task.category === BehaviorCategory.TRAVEL ? ScenarioRole.ACTUAL : ScenarioRole.BASELINE;
      if (f !== undefined && repo.isUsable(f) && sc.role === requiredRole &&
        sc.factorVersion === f.version && sc.factorValue === f.value && snapshot.gasScope === f.gasScope &&
        (f.subItem === template.factorSubItem || (template.templateId === 'P02' && f.subItem === 'walk'))) { matched = true; }
    }
    return matched ? '' : '记录的实际行动与任务不匹配，请按任务要求选择情景。';
  }
}
