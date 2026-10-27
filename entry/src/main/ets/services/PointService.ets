import { LedgerDb } from './LedgerDb';
import { PointsEngine } from './PointsEngine';
import { DateUtil } from '../common/Format';
import { Ids } from '../common/Ids';
import { BehaviorCategory, PointReason } from '../common/Domain';
import { PointAccountView, BadgeUnlock } from '../models/PointModels';
import { BadgeDef } from '../models/ContentModels';
import { PARTICIPATION_POINTS } from '../data/TaskTemplates';

/**
 * 积分与徽章服务（第 9.1 节）。
 *
 * 关键约束：
 *  - 发分不重复：积分事件带 uniqueKey，重复写入被唯一索引与预检查拦下；
 *  - 修订与撤销按差额冲正；
 *  - 每日奖励上限只影响奖励资格，不改写原始核算结果；
 *  - 余额由事件派生，不保存独立总余额。
 *
 * 事务约定（重要）：OpenHarmony RDB 在同一事务内读不到未提交的写入，
 * 因此积分的「读—算—写」拆成两步：planSettlement 在写事务之前基于已提交
 * 状态与变更后的推算量算出待写事件；applySettlement 在写事务内落库，
 * 与行为记录、计算快照同事务提交。
 */

/** 待写入的积分事件（事务前算好，事务内落库） */
export interface PendingPoint {
  reason: PointReason;
  uniqueKey: string;
  delta: number;
  detail: string;
}

/** 一次行为变更的积分结算计划 */
export interface SettlementPlan {
  points: PendingPoint[];
  /** 变更后的连续有效记录天数（提交后用于徽章解锁） */
  streak: number;
}

export class PointService {

  /**
   * 事务前结算计划：基于已提交状态与「变更后累计量」计算应写入的积分事件。
   * @param totalsAfter 本次变更提交后的各气体口径累计合格减排量（分别计算）
   * @param activeDaysAfter 本次变更提交后的有效记录日期集合
   */
  static async planSettlement(db: LedgerDb, recordId: string, revision: number, dayKey: string,
    totalsAfter: Map<string, number>, activeDaysAfter: string[]): Promise<SettlementPlan> {
    const points: PendingPoint[] = [];

    // 1) 减排积分：按累计口径换算，与已发放额的差额入账（可为负，用于冲正）
    const issuedReduction = await db.sumPointsByReason(PointReason.REDUCTION);
    let entitled = 0;
    const scopeDetails: string[] = [];
    totalsAfter.forEach((kg: number, scope: string) => {
      entitled += Math.floor(Math.round(kg * 10000) / 10000 * PointsEngine.POINTS_PER_KG);
      scopeDetails.push(`${scope} ${kg.toFixed(4)}kg`);
    });
    const delta = entitled - issuedReduction;
    // 键中带上「写入前的已发放数」，使同一状态下重复调用幂等，
    // 而撤销 / 修订导致应得额变化时能再写一条差额（可为负）以冲正。
    const reductionKey = `${PointsEngine.keyReduction(recordId, revision)}:${issuedReduction}`;
    if (delta !== 0 && !(await db.hasPointEvent(reductionKey))) {
      const scopeText = scopeDetails.length > 0 ? `；${scopeDetails.join('；')}` : '';
      points.push({
        reason: PointReason.REDUCTION,
        uniqueKey: reductionKey,
        delta: delta,
        detail: `各气体口径分别累计并取整为积分，再汇总${scopeText}。本次调整 ${delta} 分。`
      });
    }

    // 2) 每日首次有效记录奖励（上限内）
    let bonusToday = await db.sumBonusPointsOnDay(dayKey);
    const dailyKey = PointsEngine.keyDailyFirst(dayKey);
    if (!(await db.hasPointEvent(dailyKey))) {
      const capped = PointsEngine.applyDailyBonusCap(bonusToday, PointsEngine.DAILY_FIRST_BONUS);
      if (capped > 0) {
        points.push({
          reason: PointReason.DAILY_FIRST,
          uniqueKey: dailyKey,
          delta: capped,
          detail: '当日首次有效记录奖励。'
        });
        bonusToday = bonusToday + capped;
      }
    }

    // 3) 连续七天奖励（每个连续区间只发一次，受每日上限约束）
    const streak = PointsEngine.streakDays(activeDaysAfter);
    if (streak >= PointsEngine.STREAK_DAYS && activeDaysAfter.length > 0) {
      let streakEnd = activeDaysAfter[0];
      for (const d of activeDaysAfter) {
        if (d > streakEnd) {
          streakEnd = d;
        }
      }
      const streakKey = PointsEngine.keyStreak(streakEnd);
      if (!(await db.hasPointEvent(streakKey))) {
        const capped = PointsEngine.applyDailyBonusCap(bonusToday, PointsEngine.STREAK7_BONUS);
        if (capped > 0) {
          points.push({
            reason: PointReason.STREAK7,
            uniqueKey: streakKey,
            delta: capped,
            detail: `连续 ${streak} 个自然日有效记录奖励（每个连续区间只发一次）。`
          });
        }
      }
    }

    return { points: points, streak: streak };
  }

  /** 在写事务内落库结算计划，返回本次实际发放的积分合计 */
  static async applySettlement(db: LedgerDb, plan: SettlementPlan, recordId: string,
    revision: number, dayKey: string): Promise<number> {
    let issued = 0;
    for (const p of plan.points) {
      await db.insertPointEvent({
        eventId: Ids.withPrefix('pts'),
        recordId: recordId,
        revision: revision,
        reason: p.reason,
        uniqueKey: p.uniqueKey,
        delta: p.delta,
        detail: p.detail,
        createdAt: DateUtil.toDateTime(new Date())
      }, dayKey);
      issued = issued + p.delta;
    }
    return issued;
  }

  /**
   * 任务参与奖励（唯一事件，受每日奖励上限约束）。
   * 与减排积分分开标记；上限不足时不写入事件、返回 0，不改写原始核算结果。
   */
  static async awardParticipation(db: LedgerDb, planTaskId: string, dayKey: string,
    recordId: string, revision: number): Promise<number> {
    const key = PointsEngine.keyParticipation(planTaskId);
    if (await db.hasPointEvent(key)) {
      return 0;
    }
    const bonusToday = await db.sumBonusPointsOnDay(dayKey);
    const capped = PointsEngine.applyDailyBonusCap(bonusToday, PARTICIPATION_POINTS);
    if (capped <= 0) {
      return 0;
    }
    await db.insertPointEvent({
      eventId: Ids.withPrefix('pts'),
      recordId: recordId,
      revision: revision,
      reason: PointReason.PARTICIPATION,
      uniqueKey: key,
      delta: capped,
      detail: `任务参与奖励 ${capped} 分（每日奖励上限内）。`,
      createdAt: DateUtil.toDateTime(new Date())
    }, dayKey);
    return capped;
  }

  /** 撤销任务参与奖励：写冲正事件，不删除原事件 */
  static async revokeParticipation(db: LedgerDb, planTaskId: string, dayKey: string): Promise<number> {
    const key = PointsEngine.keyParticipation(planTaskId);
    const ev = await db.findPointEventByKey(key);
    if (ev === null || ev.delta === 0) {
      return 0;
    }
    const revKey = PointsEngine.keyReversal(ev.eventId);
    if (await db.hasPointEvent(revKey)) {
      return 0;
    }
    await db.insertPointEvent({
      eventId: Ids.withPrefix('pts'),
      recordId: ev.recordId,
      revision: ev.revision,
      reason: PointReason.REVERSAL,
      uniqueKey: revKey,
      delta: -ev.delta,
      detail: '关联记录撤销，冲正任务参与奖励。',
      createdAt: DateUtil.toDateTime(new Date())
    }, dayKey);
    return -ev.delta;
  }

  /** 评估并解锁徽章 */
  static async evaluateBadges(db: LedgerDb, streak: number): Promise<void> {
    const defs: BadgeDef[] = await db.listBadgeDefs();
    const unlocked: BadgeUnlock[] = await db.listBadgeUnlocks();
    const unlockedIds: string[] = [];
    for (const u of unlocked) {
      unlockedIds.push(u.badgeId);
    }
    const totalRecords = await db.countLatestActiveRecords();

    for (const def of defs) {
      if (unlockedIds.indexOf(def.badgeId) >= 0) {
        continue;
      }
      let hit = false;
      let reason = '';
      if (def.ruleKind === 'first_record') {
        hit = totalRecords >= def.ruleThreshold;
        reason = `已完成 ${totalRecords} 条有效记录。`;
      } else if (def.ruleKind === 'category_count') {
        const cat = def.ruleCategory as BehaviorCategory;
        const n = await db.countActiveByCategory(cat);
        hit = n >= def.ruleThreshold;
        reason = `${categoryLabel(def.ruleCategory)}类累计 ${n} 条有效记录。`;
      } else if (def.ruleKind === 'streak_days') {
        hit = streak >= def.ruleThreshold;
        reason = `连续 ${streak} 个自然日有效记录。`;
      }
      if (hit) {
        await db.unlockBadge(def.badgeId, reason);
      }
    }
  }

  /** 积分账户视图（由事件派生） */
  static async account(db: LedgerDb): Promise<PointAccountView> {
    const events = await db.listPointEvents(-1);
    let earned = 0;
    let spent = 0;
    for (const e of events) {
      if (e.delta > 0) {
        earned = earned + e.delta;
      } else {
        spent = spent + (-e.delta);
      }
    }
    const balance = earned - spent;
    const shortfall = balance < 0 ? -balance : 0;
    return {
      balance: balance,
      earned: earned,
      spent: spent,
      shortfall: shortfall,
      redeemSuspended: balance < 0
    };
  }
}

function categoryLabel(category: string): string {
  if (category === BehaviorCategory.TRAVEL) {
    return '出行';
  } else if (category === BehaviorCategory.WATER_ENERGY) {
    return '节水节电';
  } else if (category === BehaviorCategory.RECYCLING) {
    return '旧物回收';
  }
  return '光盘行动';
}
