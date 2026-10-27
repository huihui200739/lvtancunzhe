import { PointReason } from '../common/Domain';

/**
 * 积分事件（point_event 表）与奖励（reward_def / redemption 表）。
 * 第 9.1 节：唯一事件防重复发分；撤销后重算并冲正；
 * 兑换的余额校验、扣分与奖励发放在单个事务内完成，并检查 request_id 唯一性。
 */

/** 积分事件。delta 为带符号整数：发分为正，扣分/冲正为负。 */
export interface PointEvent {
  eventId: string;
  /** 关联行为记录（连续奖励/兑换可为空） */
  recordId: string;
  revision: number;
  reason: PointReason;
  /** 事件唯一键，用于防重复发分，如 reduction:<recordId>:<revision> */
  uniqueKey: string;
  delta: number;
  /** 说明，如「1.24 kg × 10 分/kg」 */
  detail: string;
  createdAt: string;
}

/** 奖励定义 */
export interface RewardDef {
  rewardId: string;
  name: string;
  /** 兑换价格（积分）。为 0 表示成就类，不可用积分购买。 */
  price: number;
  kind: string;          // 'badge' | 'certificate'
  description: string;
  /** 是否可重复申请 */
  repeatable: boolean;
  /** 价格版本，固化在兑换记录中，调整不追溯历史扣分 */
  priceVersion: string;
}

/** 兑换记录 */
export interface Redemption {
  redemptionId: string;
  /** 幂等请求 ID，重复提交只扣一次 */
  requestId: string;
  rewardId: string;
  /** 兑换时的价格与价格版本快照 */
  price: number;
  priceVersion: string;
  /** 扣分事件 ID */
  pointEventId: string;
  status: string;        // 'granted' | 'pending_topup'
  createdAt: string;
}

/** 徽章解锁记录 */
export interface BadgeUnlock {
  badgeId: string;
  unlockedAt: string;
  /** 解锁依据说明 */
  reason: string;
}

/** 兑换结果视图：附带奖励名称，便于列表展示 */
export interface RedemptionView {
  redemption: Redemption;
  rewardName: string;
}

/**
 * 虚拟植树成就证书视图（由兑换记录派生，不单独存表）。
 * 明确声明不代表真实植树，也不代表正式碳权益。
 */
export interface CertificateView {
  redemptionId: string;
  /** 证书编号，由兑换时间与短 ID 派生，稳定可复核 */
  serial: string;
  rewardName: string;
  issuedAt: string;
  /** 出具时的累计合格减排量（kg） */
  totalReductionKg: number;
  reductionSummary: string;
  /** 出具时的有效记录条数 */
  recordCount: number;
  scopeNote: string;
  disclaimer: string;
}

/** 积分账户视图（由事件派生，不保存独立总余额） */
export interface PointAccountView {
  /** 当前可用余额 */
  balance: number;
  /** 累计获得 */
  earned: number;
  /** 累计消耗 */
  spent: number;
  /** 待补足积分（撤销兑换后余额不足形成的差额） */
  shortfall: number;
  /** 兑换是否暂停 */
  redeemSuspended: boolean;
}
