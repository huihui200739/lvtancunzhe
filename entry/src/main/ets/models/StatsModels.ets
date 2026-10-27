import { BehaviorCategory, GasScope } from '../common/Domain';

/**
 * 统计模型（第 4.1 节 B2、第 5.1 节）：
 * 看板同时展示正向贡献、增加排放和净变化，图表口径一致。
 */

/** 单条参与统计的记录行 */
export interface StatRow {
  recordId: string;
  revision: number;
  dayKey: string;
  category: BehaviorCategory;
  reductionKg: number;
  gasScope: GasScope;
}

/** 折线 / 柱状图的数据点 */
export interface StatBucket {
  /** 维度键：日 'YYYY-MM-DD' / 周 'YYYY-Www' / 月 'YYYY-MM' / 年 'YYYY' */
  key: string;
  label: string;
  /** 正向贡献合计（kg） */
  positiveKg: number;
  /** 增加排放合计（kg，取绝对值便于图表展示） */
  negativeKg: number;
  /** 净变化 = 正向 − 增加排放（可为负） */
  netKg: number;
  count: number;
}

/** 分类占比（饼图用） */
export interface CategoryStat {
  category: BehaviorCategory;
  label: string;
  positiveKg: number;
  negativeKg: number;
  netKg: number;
  count: number;
}

/** 看板汇总 */
export interface StatsSummary {
  buckets: StatBucket[];
  categories: CategoryStat[];
  totalPositiveKg: number;
  totalNegativeKg: number;
  totalNetKg: number;
  recordCount: number;
  /** 是否所有数值都为 0（用于空状态展示，避免除零） */
  allZero: boolean;
  /** 参与统计的气体口径（跨口径时分别汇总） */
  gasScopes: string[];
}
