import { BaselineType, BehaviorCategory, GasScope, ScenarioRole } from '../common/Domain';

/**
 * 核算引擎的输入输出模型（第 5.1 / 8.2 节）。
 * 公式：R = E基准 − E实际；
 * 同距离同口径时 R = d × (EF基准 − EF实际)。
 */

/** 单个情景的输入 */
export interface ScenarioInput {
  role: ScenarioRole;
  /** 因子编码，指向 FactorRepository */
  factorCode: string;
  /** 用户填写的数量（距离 km / 用电 kWh / 用水 m3 / 重量 kg / 次数） */
  quantity: number;
  /** 数量单位，须与因子分母单位一致 */
  unit: string;
  /** 情景自定义说明，如「校门口→图书馆」 */
  label: string;
}

/** 一次核算的输入 */
export interface CalcInput {
  category: BehaviorCategory;
  /** 基准类型：用户声明 或 统计基线 */
  baselineType: BaselineType;
  /** 单情景（节电/回收/光盘）传 1 个；出行对照传 2 个 */
  scenarios: ScenarioInput[];
}

/** 单个情景的核算结果 */
export interface ScenarioResult {
  role: ScenarioRole;
  factorCode: string;
  factorVersion: string;
  scenarioLabel: string;
  label: string;
  /** 用户填写数量 */
  quantity: number;
  unit: string;
  /** 因子值 */
  factorValue: number;
  /** 因子单位文本，如 kgCO₂/km */
  factorUnit: string;
  /** 该情景排放量（kg），保留原始符号 */
  emissionKg: number;
  effectiveQuantity?: number;
  passengers?: number;
  conversionNote?: string;
}

/** 核算结果 */
export interface CalcOutcome {
  ok: boolean;
  errorCode: string;
  message: string;
  /** 减排量 R = ΣE基准 − ΣE实际，可为负 */
  reductionKg: number;
  /** 是否相对所选情景增加排放（R < 0） */
  isNetIncrease: boolean;
  gasScope: GasScope;
  baselineType: BaselineType;
  scenarioResults: ScenarioResult[];
  /** 公式版本快照 */
  formulaVersion: string;
  /** 可读公式文本，用于凭证展示 */
  formulaText: string;
  /** 舍入规则说明 */
  roundingNote: string;
  /** 参与计算的气体口径集合（用于判断是否跨口径） */
  gasScopes: GasScope[];
  /** 主统计口径是否可与其他结果合并汇总 */
  comparable: boolean;
}
