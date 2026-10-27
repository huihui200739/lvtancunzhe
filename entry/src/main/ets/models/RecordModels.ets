import { BehaviorCategory, EntrySource, GasScope, BaselineType, RecordStatus } from '../common/Domain';
import { ScenarioResult, ScenarioInput } from './CalcModels';

/** 新建 / 修订记录的输入草案 */
export interface RecordDraft {
  category: BehaviorCategory;
  baselineType: BaselineType;
  scenarios: ScenarioInput[];
  /** 发生日期 'YYYY-MM-DD' */
  occurredAt: string;
  entrySource: EntrySource;
  remark: string;
  /** 载客数，仅出行且基准为车辆公里时需要 */
  passengers: number;
  applicabilityAccepted?: boolean;
}

/**
 * 行为记录（behavior_record 表）与计算快照（calculation_snapshot 表）。
 * 第 5.4 / 8.3 节：提交时冻结输入、因子值、因子来源、公式版本与结果；
 * 原始版本保留，修订产生新的 revision；撤销写状态与冲正积分。
 */

/** 行为记录 */
export interface BehaviorRecord {
  /** 稳定 UUID，跨设备唯一，不用自增整数 */
  recordId: string;
  /** 版本号，首次为 1，每次修订 +1 */
  revision: number;
  category: BehaviorCategory;
  /** 用户填写数量 */
  quantity: number;
  unit: string;
  /** 发生日期 'YYYY-MM-DD' */
  occurredAt: string;
  status: RecordStatus;
  entrySource: EntrySource;
  /** 录入方式标签：用户填写 / 图片辅助填写 */
  entryNote: string;
  /** 备注（不写入日志，避免泄漏私人信息） */
  remark: string;
  createdAt: string;
  updatedAt: string;
  /** 由哪条记录修订而来（首个版本为空） */
  parentRecordId: string;
}

/**
 * 计算快照。完整保存到库内，不只引用会变化的 factor_code，
 * 保证因子库更新后旧凭证仍可重现（第 5.4 节）。
 */
export interface CalculationSnapshot {
  snapshotId: string;
  recordId: string;
  revision: number;
  category: BehaviorCategory;
  baselineType: BaselineType;
  gasScope: GasScope;
  /** 结果：减排量（kg） */
  reductionKg: number;
  isNetIncrease: boolean;
  formulaVersion: string;
  formulaText: string;
  roundingNote: string;
  /** 情景结果序列化 JSON（含因子值、标签、数量、单位） */
  scenariosJson: string;
  /** 因子来源 JSON 快照：来源标题、网址、年份、地区、版本、许可 */
  factorSourcesJson: string;
  /** 依据标签 */
  evidenceLabel: string;
  /** 范围说明 */
  scopeNote: string;
  createdAt: string;
}

/** 凭证视图模型：把记录 + 快照 + 因子来源组装为可展示结构 */
export interface VoucherFactorSource {
  factorCode: string;
  factorVersion: string;
  factorName: string;
  value: number;
  gasScope: string;
  region: string;
  dataYear: number;
  boundary: string;
  methodology: string;
  sourceTitle: string;
  sourceUrl: string;
  sourceLocator: string;
  licenseNote: string;
  reviewStatus: string;
  applicabilityNote?: string;
  applicabilityConfirmed?: boolean;
}

/** 凭证 */
export interface VoucherView {
  record: BehaviorRecord;
  snapshot: CalculationSnapshot;
  scenarios: ScenarioResult[];
  sources: VoucherFactorSource[];
  /** 当前是否为最新版本 */
  isLatest: boolean;
  /** 关联积分事件摘要 */
  pointDelta: number;
}
