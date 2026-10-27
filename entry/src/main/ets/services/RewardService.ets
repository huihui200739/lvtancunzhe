import { LedgerOperations } from './LedgerOperations';
import { StatsService } from './StatsService';
import { LedgerDb } from './LedgerDb';
import { Result, ErrorCode } from '../common/AppError';
import { DateUtil, NumUtil } from '../common/Format';
import { Ids } from '../common/Ids';
import { PointReason, SCOPE_STATEMENT } from '../common/Domain';
import { PointsEngine } from './PointsEngine';
import { PointService } from './PointService';
import { CertificateView, PointEvent, Redemption, RedemptionView, RewardDef } from '../models/PointModels';

/**
 * 兑换与证书服务（第 9.1 节、第 4.1 节 B3）。
 *
 * 约束：
 *  - 兑换按 requestId 幂等，重复提交只扣一次（T06）；
 *  - 余额校验、扣分事件与兑换记录在单个事务内完成，任何失败回滚（8.4）；
 *  - 余额不足或已进入待补足状态时拒绝兑换，并给出可读原因；
 *  - 价格版本固化在兑换记录中，后续调价不追溯改变历史扣分；
 *  - 证书由兑换记录派生，不单独存表，撤销兑换不删除历史（9.1）。
 */
export class RewardService {

  /** 奖励目录 */
  static async listRewards(db: LedgerDb): Promise<RewardDef[]> {
    return db.listRewards();
  }

  /**
   * 兑换奖励。
   * @param rewardId 奖励 ID
   * @param requestId 幂等请求 ID（同一次点击复用同一个值）
   */
  static async redeem(db: LedgerDb, rewardId: string, requestId: string): Promise<Result<Redemption>> {
    return LedgerOperations.run(() => RewardService.redeemUnlocked(db, rewardId, requestId));
  }

  private static async redeemUnlocked(db: LedgerDb, rewardId: string, requestId: string): Promise<Result<Redemption>> {
    if (rewardId.length === 0 || requestId.length === 0) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '缺少奖励或请求标识，无法兑换。');
    }

    // 幂等：同一请求 ID 直接返回既有结果，不重复扣分
    const existing = await db.getRedemptionByRequest(requestId);
    if (existing !== null) {
      return Result.success(existing);
    }

    const rewards = await db.listRewards();
    let reward: RewardDef | null = null;
    for (const r of rewards) {
      if (r.rewardId === rewardId) {
        reward = r;
      }
    }
    if (reward === null) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '找不到该奖励。');
    }
    if (reward.price <= 0) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '成就类徽章通过行为解锁获得，不使用积分兑换。');
    }

    const account = await PointService.account(db);
    if (account.redeemSuspended) {
      return Result.failure(ErrorCode.E_BALANCE_INSUFFICIENT,
        `当前待补足 ${account.shortfall} 分，已暂停兑换。请先补足积分（例如补录有效行为）后再试。`);
    }
    if (account.balance < reward.price) {
      return Result.failure(ErrorCode.E_BALANCE_INSUFFICIENT,
        `积分不足：本次需要 ${reward.price} 分，当前余额 ${account.balance} 分。`);
    }

    // 不可重复的奖励：已兑换过则拒绝
    if (!reward.repeatable) {
      const history: Redemption[] = await db.listRedemptions();
      for (const h of history) {
        if (h.rewardId === rewardId) {
          return Result.failure(ErrorCode.E_DUPLICATE_REWARD, `「${reward.name}」每位用户只能兑换一次。`);
        }
      }
    }

    const now = DateUtil.toDateTime(new Date());
    const dayKey = DateUtil.today();
    const pointEventId = Ids.withPrefix('pts');
    const redemption: Redemption = {
      redemptionId: Ids.withPrefix('rdm'),
      requestId: requestId,
      rewardId: rewardId,
      price: reward.price,
      priceVersion: reward.priceVersion,
      pointEventId: pointEventId,
      status: 'granted',
      createdAt: now
    };

    try {
      await db.begin();
      const ev: PointEvent = {
        eventId: pointEventId,
        recordId: '',
        revision: 0,
        reason: PointReason.REDEMPTION,
        uniqueKey: PointsEngine.keyRedemption(requestId),
        delta: -reward.price,
        detail: `兑换「${reward.name}」扣 ${reward.price} 分（价格版本 ${reward.priceVersion}）。`,
        createdAt: now
      };
      await db.insertPointEvent(ev, dayKey);
      await db.insertRedemption(redemption);
      await db.commit();
    } catch (e) {
      await db.rollBack();
      const msg = (e as Error).message;
      return Result.failure(ErrorCode.E_STORAGE,
        `兑换失败，已回滚：${msg !== undefined ? msg : JSON.stringify(e)}`);
    }
    return Result.success(redemption);
  }

  /** 兑换记录（含奖励名称） */
  static async listRedemptions(db: LedgerDb): Promise<RedemptionView[]> {
    const rewards = await db.listRewards();
    const nameOf: Map<string, string> = new Map<string, string>();
    for (const r of rewards) {
      nameOf.set(r.rewardId, r.name);
    }
    const redemptions = await db.listRedemptions();
    const out: RedemptionView[] = [];
    for (const r of redemptions) {
      const name = nameOf.get(r.rewardId);
      out.push({
        redemption: r,
        rewardName: name !== undefined ? name : r.rewardId
      });
    }
    return out;
  }

  /**
   * 证书视图：由兑换记录派生。
   * 明确不含真实植树或正式碳权益含义（第 9.1 节、B3 验收）。
   */
  static async certificate(db: LedgerDb, redemptionId: string): Promise<Result<CertificateView>> {
    return LedgerOperations.run(() => RewardService.certificateUnlocked(db, redemptionId));
  }

  private static async certificateUnlocked(db: LedgerDb, redemptionId: string): Promise<Result<CertificateView>> {
    const redemptions = await db.listRedemptions();
    let target: Redemption | null = null;
    for (const r of redemptions) {
      if (r.redemptionId === redemptionId) {
        target = r;
      }
    }
    if (target === null) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '找不到该兑换记录。');
    }
    const rewards = await db.listRewards();
    let name = '虚拟成就证书';
    for (const rw of rewards) {
      if (rw.rewardId === target.rewardId) {
        name = rw.name;
      }
    }
    const statRows = await StatsService.rows(db);
    const totals: Map<string, number> = new Map<string, number>();
    for (const row of statRows) {
      if (row.reductionKg > 0) { totals.set(`${row.gasScope}`, (totals.get(`${row.gasScope}`) || 0) + row.reductionKg); }
    }
    const parts: string[] = [];
    let totalKg = 0;
    totals.forEach((value: number, scope: string) => {
      parts.push(`${NumUtil.fixed(value, 2)} ${scope === 'CO2' ? 'kgCO₂' : 'kgCO₂e'}`);
      if (totals.size === 1) { totalKg = value; }
    });
    const count = await db.countLatestActiveRecords();
    const view: CertificateView = {
      redemptionId: redemptionId,
      serial: RewardService.serialOf(target),
      rewardName: name,
      issuedAt: target.createdAt,
      totalReductionKg: NumUtil.roundCalc(totalKg),
      reductionSummary: parts.length > 0 ? parts.join(' / ') : '暂无正向贡献',
      recordCount: count,
      scopeNote: `统计范围：当前账本中已记录行为的正向贡献，按气体口径分别列示（${count} 条有效记录）。${SCOPE_STATEMENT}`,
      disclaimer: '本证书为应用内虚拟成就，不代表真实植树，也不代表任何正式碳信用或碳交易权益。'
    };
    return Result.success(view);
  }

  /** 证书编号：由兑换时间与兑换 ID 尾部派生，稳定可复核 */
  private static serialOf(r: Redemption): string {
    const compact = r.createdAt.replace(/[^0-9]/g, '');
    const short = r.redemptionId.length >= 8 ? r.redemptionId.substring(r.redemptionId.length - 8) : r.redemptionId;
    return `GCTC-${compact}-${short}`.toUpperCase();
  }
}
