import { RewardDef } from '../models/PointModels';

/**
 * 虚拟兑换奖励（第 9.1 节）：首版至少 2 项。
 * 价格是应用内激励规则，可在试用后调整；
 * 价格版本固化在兑换记录中，调整不追溯改变历史扣分。
 */
export const REWARD_DEFS: RewardDef[] = [
  {
    rewardId: 'REWARD_GREEN_BADGE',
    name: '绿色收藏章',
    price: 30,
    kind: 'badge',
    description: '可重复申请的收藏印章，相同请求只扣一次。',
    repeatable: true,
    priceVersion: 'v1'
  },
  {
    rewardId: 'REWARD_TREE_CERT',
    name: '虚拟植树成就证书',
    price: 50,
    kind: 'certificate',
    description: '显示编号、日期与用户记录范围；明确不代表真实植树。',
    repeatable: true,
    priceVersion: 'v1'
  }
];
