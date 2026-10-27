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
}

/** 录入页路由参数 */
export interface EntryParams {
  /** 预选类别，空串表示不限 */
  category: string;
  /** 若从计划任务进入，完成后回写关联并发放参与奖励 */
  planTaskId: string;
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
