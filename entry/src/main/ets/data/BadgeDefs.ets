import { BadgeDef } from '../models/ContentModels';
import { BehaviorCategory } from '../common/Domain';

/**
 * 徽章定义（第 9.1 节）。
 * 成就解锁与积分购买是不同记录，不重复收费。
 */
export const BADGE_DEFS: BadgeDef[] = [
  {
    badgeId: 'BADGE_START',
    name: '启程之章',
    condition: '第一次有效记录解锁',
    ruleKind: 'first_record',
    ruleCategory: '',
    ruleThreshold: 1,
    achievement: true
  },
  {
    badgeId: 'BADGE_TRAVELER',
    name: '绿色行者',
    condition: '出行类累计 5 次有效记录解锁',
    ruleKind: 'category_count',
    ruleCategory: BehaviorCategory.TRAVEL,
    ruleThreshold: 5,
    achievement: true
  },
  {
    badgeId: 'BADGE_SAVER',
    name: '节约先锋',
    condition: '节水节电类累计 3 次有效记录解锁',
    ruleKind: 'category_count',
    ruleCategory: BehaviorCategory.WATER_ENERGY,
    ruleThreshold: 3,
    achievement: true
  },
  {
    badgeId: 'BADGE_RECYCLER',
    name: '回收能手',
    condition: '回收类累计 3 次有效记录解锁',
    ruleKind: 'category_count',
    ruleCategory: BehaviorCategory.RECYCLING,
    ruleThreshold: 3,
    achievement: true
  },
  {
    badgeId: 'BADGE_CLEAN_PLATE',
    name: '光盘同行',
    condition: '光盘类累计 5 次有效记录解锁',
    ruleKind: 'category_count',
    ruleCategory: BehaviorCategory.FOOD,
    ruleThreshold: 5,
    achievement: true
  },
  {
    badgeId: 'BADGE_SEVEN_DAYS',
    name: '七日之约',
    condition: '连续七个自然日有效记录解锁',
    ruleKind: 'streak_days',
    ruleCategory: '',
    ruleThreshold: 7,
    achievement: true
  }
];
