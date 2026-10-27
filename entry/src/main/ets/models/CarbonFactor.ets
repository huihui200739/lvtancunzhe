import { BehaviorCategory, GasScope, FactorUsableAs, ReviewStatus } from '../common/Domain';

/**
 * 碳排放因子（carbon_factor 表）。
 * 第 5.2 / 5.5 节：因子必须保存气体口径、系统边界、地区、年份、方法学和单位；
 * 每条因子须登记来源、许可与核验状态，未核验不得进入生产核算。
 */
export interface CarbonFactor {
  /** 因子编码，如 EF_ELEC_HENAN_2023 */
  code: string;
  /** 因子版本，更新后旧凭证仍按快照重现 */
  version: string;
  category: BehaviorCategory;
  /** 子项标识，如 grid_elec / drive_gasoline / bus_electric */
  subItem: string;
  /** 情景文字，如「驾车」「公交」「全国电网用电」 */
  scenarioLabel: string;
  /** 因子数值，含义为「每 perUnit 的 unit 排放」 */
  value: number;
  /** 气体与质量单位：kgCO2 或 kgCO2e */
  gasScope: GasScope;
  /** 分母单位：km / kWh / m3 / kg / times */
  perUnit: string;
  /**
   * 距离口径：vkm=车辆公里，pkm=人公里，na=非距离类。
   * 第 5.1 / 测试 T03：车辆公里与人公里不得直接混算。
   */
  distanceBasis: string;
  /** 该因子可用于基准情景、实际情景或两者 */
  usableAs: FactorUsableAs;
  region: string;
  dataYear: number;
  /** 系统边界说明 */
  boundary: string;
  /** 方法学 */
  methodology: string;
  /** 来源文件标题 */
  sourceTitle: string;
  sourceUrl: string;
  /** 来源定位：表号 / 页码，便于复核 */
  sourceLocator: string;
  /** 发布或核对日期 */
  publishedAt: string;
  /** 数据许可说明 */
  licenseNote: string;
  reviewStatus: ReviewStatus;
  /** 查原文者 */
  reviewer: string;
  /** 复核者 */
  verifiedBy: string;
  note: string;
  evidenceRequirement?: string;
}

/** 因子单位展示：kgCO₂/kWh */
export function factorUnitText(factor: CarbonFactor): string {
  const gas = factor.gasScope === GasScope.CO2 ? 'kgCO₂' : 'kgCO₂e';
  return `${gas}/${factor.perUnit}`;
}
