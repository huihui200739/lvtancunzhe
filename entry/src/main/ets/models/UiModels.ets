import { BehaviorRecord } from './RecordModels';

/**
 * UI 层视图模型与路由参数（第 8.2 节表现层）。
 * 页面只依赖这些结构与各领域服务，不自行拼 SQL 或复制公式。
 */

/** 存折列表行 */
export interface RecordListItem {
  record: BehaviorRecord;
  reductionKg: number;
  isNetIncrease: boolean;
  gasScope: string;
  categoryLabel: string;
  /** 账页摘要，如「步行 · 替代汽油驾车」，取自冻结快照里的情景名 */
  summary: string;
  /** 快照内全部因子来源已核对（只说明计算依据可查，不代表行为本身经过认证） */
  verified: boolean;
}

/** 录入页路由参数 */
export interface EntryParams {
  /** 预选类别，空串表示不限 */
  category: string;
  /** 若从计划任务进入，完成后回写关联并发放参与奖励 */
  planTaskId: string;
  /** 从“拍照记一笔”进入：记录标为图片辅助填写，数量仍须用户填写 */
  imageAssisted?: boolean;
  /** 识别结果与需补齐事项，仅作提示展示，不写入数量 */
  imageHint?: string;
}

/** 凭证页路由参数 */
export interface VoucherParams {
  recordId: string;
  revision: number;
}

/** 计划详情页路由参数 */
export interface PlanDetailParams {
  planId: string;
}

/** 证书页路由参数 */
export interface CertParams {
  redemptionId: string;
}
