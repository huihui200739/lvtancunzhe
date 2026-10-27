import { BehaviorCategory, PlanTaskStatus, QuantityUnit } from '../common/Domain';

/**
 * 任务模板（task_template 表）与七日计划（weekly_plan / plan_task 表）。
 * 第 6.1 / 6.2 / 8.3 节。
 */

/** 任务模板。预计效果由核验后的因子实时计算，不在模板中硬编码减排数字。 */
export interface TaskTemplate {
  /** 模板编号 P01..P08 */
  templateId: string;
  name: string;
  category: BehaviorCategory;
  /** 适用条件说明 */
  applicableWhen: string;
  /** 完成依据说明 */
  evidenceRule: string;
  /** 计量方式 */
  measureUnit: QuantityUnit;
  /** 该任务引用的因子子项（如 bus / grid_elec_henan）；无匹配因子的任务为空串，仅作参与任务 */
  factorSubItem: string;
  /** 替代情景说明（用于推荐解释） */
  substituteScenario: string;
  /** 每次预计效果所需的默认数量（有依据时可改） */
  defaultQuantity: number;
  /** 额外时间（分钟 / 次） */
  extraMinutes: number;
  /** 额外费用（元 / 次） */
  extraCost: number;
  /** 允许的星期（1..7），空数组表示不限 */
  allowedWeekdays: number[];
  /** 互斥组标识，同组同日只能选一个 */
  mutexGroup: string;
  /** 单个计划周期内的频次上限 */
  maxTimesPerWeek: number;
  /** 是否有可比较的数量依据；false 时只给参与积分 */
  hasComparableQuantity: boolean;
  /** 推荐解释模板，含 {weekday} {minutes} {cost} 等占位符 */
  explainTemplate: string;
}

/** 计划约束（用户输入） */
export interface PlanConstraints {
  /** 生成日起七个本地自然日的第一天 'YYYY-MM-DD' */
  startDay: string;
  /** 目标减排量（kg），气体口径见 gasScope */
  targetKg: number;
  gasScope: string;
  /** 可接受的额外总时间（分钟） */
  budgetMinutes: number;
  /** 可接受的额外总费用（元） */
  budgetCost: number;
  /** 可用日期（'YYYY-MM-DD' 列表），空表示七天都可用 */
  availableDays: string[];
  /** 愿意尝试的类别 */
  acceptedCategories: BehaviorCategory[];
  /**
   * 用户通常出行的因子子项（如 drive_gasoline / bus / bike）。
   * 用于排除「本来就步行或骑行，却推荐步行替代驾车并虚计贡献」。
   */
  usualTravelSubItem: string;
  /** 常用出行距离（km） */
  usualTravelKm: number;
  /** 用户排除的模板 ID */
  excludedTemplateIds: string[];
}

/**
 * 计划引擎输出的候选安排（纯业务结果，不含数据库主键，保证相同输入产生相同方案）。
 * 由 PlanService 分配 planTaskId 后写入 plan_task 表。
 */
export interface PlanProposal {
  templateId: string;
  name: string;
  category: BehaviorCategory;
  /** 安排日期 'YYYY-MM-DD' */
  day: string;
  /** 预计减排量（kg）；参与任务为 0 */
  expectedKg: number;
  quantity: number;
  unit: string;
  extraMinutes: number;
  extraCost: number;
  /** 推荐原因（解释模板渲染结果） */
  reason: string;
  /** 参与任务：无可用因子或气体口径与本次目标不同，只计参与积分 */
  participationOnly: boolean;
}

/** 计划求解结果 */
export interface PlanSolution {
  ok: boolean;
  code: string;
  message: string;
  proposals: PlanProposal[];
  /** 预计达成总量（kg），仅统计可核算任务 */
  plannedKg: number;
  /** 剩余差额（kg），0 表示达成 */
  gapKg: number;
  participationCount: number;
  targetMet: boolean;
  /** 本次目标采用的单一气体口径（'CO2' / 'CO2e'），无候选时为空串 */
  gasScope: string;
  /** 排序、筛选与选取过程说明，用于调试与推荐解释 */
  trace: string[];
}

/** 计划任务（plan_task 表） */
export interface PlanTask {
  planTaskId: string;
  planId: string;
  templateId: string;
  name: string;
  category: BehaviorCategory;
  /** 安排日期 'YYYY-MM-DD' */
  day: string;
  status: PlanTaskStatus;
  /** 预计减排量（kg）；参与任务为 0 且计入参与区 */
  expectedKg: number;
  /** 预计所用数量与单位 */
  quantity: number;
  unit: string;
  /** 额外时间 / 费用 */
  extraMinutes: number;
  extraCost: number;
  /** 推荐原因（可读模板渲染结果） */
  reason: string;
  /** 参与任务标记：没有匹配因子，只给参与积分，不计入目标可达性 */
  participationOnly: boolean;
  /** 关联的真实行为记录 ID */
  linkedRecordId: string;
  /** 实际减排量（kg，完成任务核算后写入） */
  actualKg: number;
  /** 是否已发放参与奖励 */
  rewarded: boolean;
}

/** 周计划（weekly_plan 表）：保存约束快照与版本，便于解释推荐变化 */
export interface WeeklyPlan {
  planId: string;
  planVersion: number;
  /** 约束快照 JSON */
  constraintsJson: string;
  createdAt: string;
  /** 生成时的因子版本快照标识 */
  factorSetVersion: string;
}

/** 计划生成结果 */
export interface PlanOutcome {
  ok: boolean;
  code: string;
  message: string;
  plan: WeeklyPlan | null;
  tasks: PlanTask[];
  /** 预计达成总量（kg），仅统计可核算任务 */
  plannedKg: number;
  /** 剩余差额（kg） */
  gapKg: number;
  /** 参与任务数量 */
  participationCount: number;
  /** 是否达成目标 */
  targetMet: boolean;
  /** 排序与筛选过程说明，用于调试与推荐解释 */
  trace: string[];
}
