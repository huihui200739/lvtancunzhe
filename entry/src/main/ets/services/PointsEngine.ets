import { PointReason } from '../common/Domain';
import { NumUtil } from '../common/Format';

/**
 * 积分引擎（纯业务模块）。
 *
 * 规则（第 9.1 节，首版）：
 *  - 合格减排行为按「累计每 1 kg 对应 10 分」换算，余数累计；
 *  - 不同口径分别计算，不跨口径合并；
 *  - 每日首次有效记录奖励 5 分；
 *  - 连续七天有效记录奖励 20 分，每个连续区间只发一次；
 *  - 参与与连续奖励合计每日上限 30 分；
 *  - 上限只影响奖励资格，不改写原始核算结果。
 */

/** 单条积分事件草案 */
export interface PointDraft {
  reason: PointReason;
  uniqueKey: string;
  delta: number;
  detail: string;
}

export class PointsEngine {
  /** 每 1 kg 减排对应积分 */
  static readonly POINTS_PER_KG = 10;
  /** 每日首次有效记录奖励 */
  static readonly DAILY_FIRST_BONUS = 5;
  /** 连续七天奖励 */
  static readonly STREAK7_BONUS = 20;
  /** 参与与连续奖励的每日合计上限 */
  static readonly DAILY_BONUS_CAP = 30;
  /** 连续达标所需天数 */
  static readonly STREAK_DAYS = 7;

  /**
   * 减排积分增量：按累计口径换算，实现「余数累计」。
   * @param totalKgAfter 本笔入账后的累计合格减排量（kg）
   * @param reductionPointsIssued 已发放的减排积分合计
   */
  static reductionDelta(totalKgAfter: number, reductionPointsIssued: number): number {
    if (totalKgAfter <= 0) {
      return 0;
    }
    const entitled = NumUtil.floorPoints(totalKgAfter * PointsEngine.POINTS_PER_KG);
    const delta = entitled - reductionPointsIssued;
    return delta > 0 ? delta : 0;
  }

  /** 减排积分事件的详情文案 */
  static reductionDetail(cumulativeKg: number, delta: number): string {
    return `累计 ${NumUtil.fixed(cumulativeKg, 2)} kg × ${PointsEngine.POINTS_PER_KG} 分/kg，本次发 ${delta} 分（余数累计）。`;
  }

  /**
   * 每日首次有效记录奖励。
   * @param todayHasValidRecord 今天是否已有其他有效记录
   */
  static dailyFirstDelta(todayHasValidRecord: boolean): number {
    return todayHasValidRecord ? 0 : PointsEngine.DAILY_FIRST_BONUS;
  }

  /**
   * 连续七天奖励。每个连续区间只发一次。
   * @param streakDays 当前连续有效记录天数
   * @param streakRewarded 本次连续区间是否已发放
   */
  static streakDelta(streakDays: number, streakRewarded: boolean): number {
    if (streakDays < PointsEngine.STREAK_DAYS || streakRewarded) {
      return 0;
    }
    return PointsEngine.STREAK7_BONUS;
  }

  /**
   * 应用每日奖励上限：只影响参与与连续奖励，不影响减排积分。
   * @param bonusToday 今日已发放的参与与连续奖励合计
   * @param proposed 本次拟发放的奖励类积分
   */
  static applyDailyBonusCap(bonusToday: number, proposed: number): number {
    const remaining = PointsEngine.DAILY_BONUS_CAP - bonusToday;
    if (remaining <= 0) {
      return 0;
    }
    return proposed > remaining ? remaining : proposed;
  }

  /** 唯一事件键：保证同一记录同一版本只发一次 */
  static keyReduction(recordId: string, revision: number): string {
    return `reduction:${recordId}:${revision}`;
  }

  static keyDailyFirst(day: string): string {
    return `daily_first:${day}`;
  }

  static keyStreak(streakEndDay: string): string {
    return `streak7:${streakEndDay}`;
  }

  static keyParticipation(planTaskId: string): string {
    return `participation:${planTaskId}`;
  }

  static keyRedemption(requestId: string): string {
    return `redemption:${requestId}`;
  }

  static keyReversal(eventId: string): string {
    return `reversal:${eventId}`;
  }

  /**
   * 连续有效记录天数：从最近一天向前回溯。
   * @param days 已有有效记录的日期集合（'YYYY-MM-DD'）
   */
  static streakDays(days: string[]): number {
    if (days.length === 0) {
      return 0;
    }
    const set: Set<string> = new Set<string>();
    for (const d of days) {
      set.add(d);
    }
    // 以最大日期为起点向前数
    let latest = days[0];
    for (const d of days) {
      if (d > latest) {
        latest = d;
      }
    }
    let count = 0;
    let cursor = latest;
    while (set.has(cursor)) {
      count = count + 1;
      const parts: string[] = cursor.split('-');
      const dt = new Date(Number.parseInt(parts[0], 10), Number.parseInt(parts[1], 10) - 1, Number.parseInt(parts[2], 10));
      dt.setDate(dt.getDate() - 1);
      const m = dt.getMonth() + 1;
      const dd = dt.getDate();
      cursor = `${dt.getFullYear()}-${m < 10 ? '0' : ''}${m}-${dd < 10 ? '0' : ''}${dd}`;
    }
    return count;
  }
}
