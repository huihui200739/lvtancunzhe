import { PlanTask } from '../models/PlanModels';
import { PlanTaskStatus } from '../common/Domain';
import { DateUtil } from '../common/Format';

/** 一条来自已保存七日计划的可执行建议；不生成新任务或新的减排数值。 */
export interface ActionRecommendation {
  planTaskId: string;
  title: string;
  day: string;
  category: string;
  expectedKg: number;
  unit: string;
  extraMinutes: number;
  extraCost: number;
  reason: string;
  participationOnly: boolean;
  isToday: boolean;
}

/**
 * 行动教练：只把用户已保存计划中的未来/今日任务整理成短列表。
 * 排序依据是日期、进行状态、额外时间/费用及原有预计值，不使用模型推理，
 * 不改计划、不写数据库，也不替用户完成任务。
 */
export class ActionCoachService {
  static recommend(tasks: PlanTask[], today: string = DateUtil.today(), limit: number = 3): ActionRecommendation[] {
    if (!DateUtil.isValidDay(today) || !Number.isFinite(limit) || limit <= 0) {
      return [];
    }
    const endDay = DateUtil.addDays(today, 6);
    const candidates: PlanTask[] = [];
    for (const task of tasks) {
      if ((task.status === PlanTaskStatus.PLANNED || task.status === PlanTaskStatus.IN_PROGRESS) &&
        DateUtil.isValidDay(task.day) && task.day >= today && task.day <= endDay) {
        candidates.push(task);
      }
    }
    candidates.sort((a: PlanTask, b: PlanTask) => {
      if (a.day !== b.day) { return a.day < b.day ? -1 : 1; }
      const aStarted = a.status === PlanTaskStatus.IN_PROGRESS;
      const bStarted = b.status === PlanTaskStatus.IN_PROGRESS;
      if (aStarted !== bStarted) { return aStarted ? -1 : 1; }
      if (a.extraMinutes !== b.extraMinutes) { return a.extraMinutes - b.extraMinutes; }
      if (a.extraCost !== b.extraCost) { return a.extraCost - b.extraCost; }
      if (a.expectedKg !== b.expectedKg) { return b.expectedKg - a.expectedKg; }
      return a.planTaskId < b.planTaskId ? -1 : (a.planTaskId > b.planTaskId ? 1 : 0);
    });
    const out: ActionRecommendation[] = [];
    const count = Math.min(Math.floor(limit), candidates.length);
    for (let i = 0; i < count; i++) {
      const task = candidates[i];
      out.push({
        planTaskId: task.planTaskId,
        title: task.name,
        day: task.day,
        category: `${task.category}`,
        expectedKg: task.participationOnly ? 0 : task.expectedKg,
        unit: task.unit,
        extraMinutes: task.extraMinutes,
        extraCost: task.extraCost,
        reason: task.reason,
        participationOnly: task.participationOnly,
        isToday: task.day === today
      });
    }
    return out;
  }
}
