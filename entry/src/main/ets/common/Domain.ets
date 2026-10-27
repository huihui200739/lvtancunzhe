/**
 * 全局领域枚举与类型。
 * 对应《绿碳存折项目计划方案》第 8.3 节业务表与第 4 章功能范围。
 */

/** 四类行为核算（B1） */
export enum BehaviorCategory {
  TRAVEL = 'travel',                 // 出行
  WATER_ENERGY = 'water_energy',     // 节水节电
  RECYCLING = 'recycling',           // 旧物回收
  FOOD = 'food'                      // 光盘行动 / 减少浪费
}

/** 气体口径。仅 CO2 的因子结果标为 kgCO2；覆盖相应温室气体的因子标为 kgCO2e。 */
export enum GasScope {
  CO2 = 'CO2',
  CO2E = 'CO2e'
}

/** 基准类型：用户明确声明的替代情景，或已选方法学规定的统计基线。界面必须标注且不混用。 */
export enum BaselineType {
  USER_DECLARED = 'user_declared',
  STATISTICAL = 'statistical'
}

/** 情景角色 */
export enum ScenarioRole {
  BASELINE = 'baseline',
  ACTUAL = 'actual'
}

/** 因子可作为哪类情景使用 */
export enum FactorUsableAs {
  BASELINE = 'baseline',
  ACTUAL = 'actual',
  BOTH = 'both',
  SINGLE = 'single'
}

/** 因子核验状态。非 VERIFIED 的因子不得进入生产核算。 */
export enum ReviewStatus {
  VERIFIED = 'verified',
  PENDING = 'pending',
  REJECTED = 'rejected'
}

/** 行为记录状态。撤销写状态 + 冲正积分，不物理删除。 */
export enum RecordStatus {
  ACTIVE = 'active',
  VOIDED = 'voided'
}

/** 录入方式。标签不代表行为真实性认证。 */
export enum EntrySource {
  USER_INPUT = 'user_input',
  IMAGE_ASSISTED = 'image_assisted'
}

/** 积分事件原因。唯一事件防重复发分。 */
export enum PointReason {
  REDUCTION = 'reduction',               // 合格减排积分
  DAILY_FIRST = 'daily_first',           // 每日首次有效记录 +5
  STREAK7 = 'streak7',                   // 连续七天 +20
  PARTICIPATION = 'participation',       // 任务参与奖励
  REDEMPTION = 'redemption',             // 兑换扣分
  REVERSAL = 'reversal',                 // 撤销 / 修订冲正
  BADGE = 'badge'                        // 成就相关
}

/** 计划任务状态（第 6.4 节） */
export enum PlanTaskStatus {
  PLANNED = 'planned',
  IN_PROGRESS = 'in_progress',
  LINKED = 'linked',
  COMPLETED = 'completed',
  SKIPPED = 'skipped'
}

/** 计量单位 */
export enum QuantityUnit {
  KM = 'km',
  KWH = 'kWh',
  CUBIC_METER = 'm3',
  KG = 'kg',
  TIMES = 'times'
}

/** 图表时间维度 */
export enum TimeDimension {
  DAY = 'day',
  WEEK = 'week',
  MONTH = 'month',
  YEAR = 'year'
}

/** 数值格式化统一使用的保留位数：核算内部保留 4 位，展示 2 位（第 8.3 节：计算精度与显示舍入分开）。 */
export const CALC_PRECISION = 10000;
export const DISPLAY_PRECISION = 100;

/** 公式版本。凭证快照冻结该值，历史凭证据此重现。 */
export const FORMULA_VERSION = 'v1.0.1';

/** 统计口径：本项目仅统计校园场景下的局部行为估算，不构成完整个人碳足迹。 */
export const SCOPE_STATEMENT = '本数值仅为已记录行为的估算减排量，非完整个人碳足迹，非经核证碳资产。';

/** 行为类别中文名 */
export function categoryName(category: BehaviorCategory): string {
  if (category === BehaviorCategory.TRAVEL) {
    return '出行';
  } else if (category === BehaviorCategory.WATER_ENERGY) {
    return '节水节电';
  } else if (category === BehaviorCategory.RECYCLING) {
    return '旧物回收';
  }
  return '光盘行动';
}

/** 气体口径展示标签：kgCO2 / kgCO2e */
export function gasUnitLabel(scope: GasScope): string {
  return scope === GasScope.CO2 ? 'kgCO₂' : 'kgCO₂e';
}
