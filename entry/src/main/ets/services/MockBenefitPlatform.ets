import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { RecordStatus, GasScope, gasUnitLabel } from '../common/Domain';
import { Result, ErrorCode } from '../common/AppError';
import { DateUtil, NumUtil } from '../common/Format';
import { VoucherView } from '../models/RecordModels';

/** 模拟平台上的一笔“转存”回执：记录版本与当时的估算量一并冻结 */
export interface MockTransfer {
  requestId: string;
  recordId: string;
  revision: number;
  amountKg: number;
  gasScope: string;
  credits: number;
  createdAt: string;
}

/** 模拟平台权益：价格以“模拟碳普惠积分”计，不是现金、真实权益或碳资产 */
export interface MockPerk {
  perkId: string;
  name: string;
  partner: string;
  price: number;
  description: string;
}

export interface MockRedemption {
  requestId: string;
  perkId: string;
  perkName: string;
  price: number;
  code: string;
  createdAt: string;
}

/** 模拟平台账户：只存在应用偏好文件，不写账本 RDB，不进备份/CSV */
export interface MockBenefitAccount {
  transfers: MockTransfer[];
  redemptions: MockRedemption[];
}

export interface MockBenefitSummary {
  earned: number;
  spent: number;
  balance: number;
  transferCount: number;
}

/**
 * 模拟城市碳普惠平台（赛题创新拓展 3：“模拟城市碳普惠接口，实现积分互通与权益兑换”）。
 *
 * 边界：
 * - 不联网，也没有任何真实平台或合作方；名称、权益、兑换码全部为演示虚构，界面逐处标注“模拟”。
 * - 只接收“最新有效、正向、来源已核验”的凭证；同一记录版本只能转存一次（requestId 幂等）。
 * - 转存不扣减、不改写存折账本与应用积分；撤销/修订后，旧版本的转存保留为历史，新版本可再次转存。
 * - 兑换率是演示假设（每 0.1 kg 记 1 模拟积分，CO₂ 与 CO₂e 分别换算后再相加只用于模拟积分，不合并 kg）。
 */
export class MockBenefitPlatform {
  static readonly PLATFORM_NAME: string = '郑州市碳普惠平台（模拟）';
  static readonly NOTICE: string = '模拟平台：不联网、无真实合作方，积分与兑换码均为演示数据，不代表真实权益或经核证碳资产。';
  static readonly CREDITS_PER_KG: number = 10;
  private static readonly FILE: string = 'mock_benefit_platform';
  private static readonly KEY: string = 'account';

  static readonly PERKS: MockPerk[] = [
    { perkId: 'MP01', name: '公交乘车优惠（模拟）', partner: '城市公交（虚构）', price: 30, description: '演示“积分互通后换取出行权益”的流程，不能实际乘车。' },
    { perkId: 'MP02', name: '共享单车骑行券（模拟）', partner: '共享出行（虚构）', price: 20, description: '演示兑换后生成兑换码，兑换码不可在任何平台使用。' },
    { perkId: 'MP03', name: '校园绿植认领（模拟）', partner: '校园后勤（虚构）', price: 50, description: '演示与线下活动对接的形态，不代表真实认领。' }
  ];

  /** 与旧版接口演练一致的稳定请求号：同一记录版本始终得到同一个号 */
  static requestId(recordId: string, revision: number): string {
    const input = `${recordId}#${revision}`;
    let hash = 2166136261;
    for (let i = 0; i < input.length; i++) {
      hash = Math.imul(hash ^ input.charCodeAt(i), 16777619) >>> 0;
    }
    return `SIM-${hash.toString(16).toUpperCase().padStart(8, '0')}`;
  }

  /** 不可转存时返回原因，可转存时返回空串 */
  static ineligibleReason(voucher: VoucherView): string {
    if (voucher.record.recordId.length === 0 || !Number.isInteger(voucher.record.revision) || voucher.record.revision < 1) {
      return '记录版本信息不完整。';
    }
    if (voucher.record.status !== RecordStatus.ACTIVE || !voucher.isLatest) {
      return '只有当前有效的最新版本可以转存。';
    }
    if (!Number.isFinite(voucher.snapshot.reductionKg) || voucher.snapshot.reductionKg <= 0 || voucher.snapshot.isNetIncrease) {
      return '只接收正向估算结果；净增排或零值不转存。';
    }
    if (voucher.snapshot.gasScope !== GasScope.CO2 && voucher.snapshot.gasScope !== GasScope.CO2E) {
      return '记录的气体口径无效。';
    }
    if (voucher.sources.length === 0 || voucher.sources.some((s) => s.reviewStatus !== 'verified')) {
      return '缺少已核验的因子来源。';
    }
    return '';
  }

  static creditsFor(amountKg: number): number {
    return Number.isFinite(amountKg) && amountKg > 0 ? Math.floor(NumUtil.roundCalc(amountKg) * MockBenefitPlatform.CREDITS_PER_KG) : 0;
  }

  static summary(account: MockBenefitAccount): MockBenefitSummary {
    let earned = 0;
    for (const t of account.transfers) { earned += t.credits; }
    let spent = 0;
    for (const r of account.redemptions) { spent += r.price; }
    return { earned: earned, spent: spent, balance: earned - spent, transferCount: account.transfers.length };
  }

  static findTransfer(account: MockBenefitAccount, recordId: string, revision: number): MockTransfer | null {
    const id = MockBenefitPlatform.requestId(recordId, revision);
    const found = account.transfers.find((t: MockTransfer) => t.requestId === id);
    return found !== undefined ? found : null;
  }

  /** 纯函数：在给定账户上转存一张凭证，返回新账户；重复转存返回原回执且账户不变 */
  static applyTransfer(account: MockBenefitAccount, voucher: VoucherView, now: string): Result<MockBenefitAccount> {
    const reason = MockBenefitPlatform.ineligibleReason(voucher);
    if (reason.length > 0) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, reason);
    }
    if (MockBenefitPlatform.findTransfer(account, voucher.record.recordId, voucher.record.revision) !== null) {
      return Result.success(account);
    }
    const credits = MockBenefitPlatform.creditsFor(voucher.snapshot.reductionKg);
    if (credits <= 0) {
      return Result.failure(ErrorCode.E_QUANTITY_INVALID, '估算量不足 0.1 kg，不够换算 1 个模拟积分。');
    }
    const transfer: MockTransfer = {
      requestId: MockBenefitPlatform.requestId(voucher.record.recordId, voucher.record.revision),
      recordId: voucher.record.recordId,
      revision: voucher.record.revision,
      amountKg: voucher.snapshot.reductionKg,
      gasScope: `${voucher.snapshot.gasScope}`,
      credits: credits,
      createdAt: now
    };
    const next: MockBenefitAccount = { transfers: account.transfers.concat([transfer]), redemptions: account.redemptions };
    return Result.success(next);
  }

  /** 纯函数：用模拟积分兑换权益；同一 requestId 只扣一次 */
  static applyRedeem(account: MockBenefitAccount, perkId: string, requestId: string, now: string): Result<MockBenefitAccount> {
    if (account.redemptions.some((r: MockRedemption) => r.requestId === requestId)) {
      return Result.success(account);
    }
    const perk = MockBenefitPlatform.PERKS.find((p: MockPerk) => p.perkId === perkId);
    if (perk === undefined) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '没有这项模拟权益。');
    }
    if (MockBenefitPlatform.summary(account).balance < perk.price) {
      return Result.failure(ErrorCode.E_BALANCE_INSUFFICIENT, '模拟积分不足。');
    }
    let hash = 0;
    for (let i = 0; i < requestId.length; i++) { hash = (hash * 31 + requestId.charCodeAt(i)) >>> 0; }
    const redemption: MockRedemption = {
      requestId: requestId, perkId: perk.perkId, perkName: perk.name, price: perk.price,
      code: `DEMO-${perk.perkId}-${(hash % 1000000).toString().padStart(6, '0')}`, createdAt: now
    };
    const next: MockBenefitAccount = { transfers: account.transfers, redemptions: account.redemptions.concat([redemption]) };
    return Result.success(next);
  }

  static empty(): MockBenefitAccount {
    return { transfers: [], redemptions: [] };
  }

  static async load(context: common.Context): Promise<MockBenefitAccount> {
    try {
      const store = await preferences.getPreferences(context, MockBenefitPlatform.FILE);
      const raw = `${await store.get(MockBenefitPlatform.KEY, '')}`;
      if (raw.length === 0) {
        return MockBenefitPlatform.empty();
      }
      const parsed = JSON.parse(raw) as MockBenefitAccount;
      return {
        transfers: Array.isArray(parsed.transfers) ? parsed.transfers : [],
        redemptions: Array.isArray(parsed.redemptions) ? parsed.redemptions : []
      };
    } catch (e) {
      return MockBenefitPlatform.empty();
    }
  }

  private static async save(context: common.Context, account: MockBenefitAccount): Promise<void> {
    const store = await preferences.getPreferences(context, MockBenefitPlatform.FILE);
    await store.put(MockBenefitPlatform.KEY, JSON.stringify(account));
    await store.flush();
  }

  static async transfer(context: common.Context, voucher: VoucherView): Promise<Result<MockTransfer>> {
    try {
      const account = await MockBenefitPlatform.load(context);
      const next = MockBenefitPlatform.applyTransfer(account, voucher, DateUtil.toDateTime(new Date()));
      if (!next.ok || next.data === null) {
        return Result.failure(next.code, next.message);
      }
      if (next.data !== account) {
        await MockBenefitPlatform.save(context, next.data);
      }
      const t = MockBenefitPlatform.findTransfer(next.data, voucher.record.recordId, voucher.record.revision);
      return t !== null ? Result.success(t) : Result.failure(ErrorCode.E_IO, '转存回执丢失。');
    } catch (e) {
      return Result.failure(ErrorCode.E_IO, `模拟转存失败：${(e as Error).message}`);
    }
  }

  static async redeem(context: common.Context, perkId: string, requestId: string): Promise<Result<MockRedemption>> {
    try {
      const account = await MockBenefitPlatform.load(context);
      const next = MockBenefitPlatform.applyRedeem(account, perkId, requestId, DateUtil.toDateTime(new Date()));
      if (!next.ok || next.data === null) {
        return Result.failure(next.code, next.message);
      }
      if (next.data !== account) {
        await MockBenefitPlatform.save(context, next.data);
      }
      const r = next.data.redemptions.find((x: MockRedemption) => x.requestId === requestId);
      return r !== undefined ? Result.success(r) : Result.failure(ErrorCode.E_IO, '兑换记录丢失。');
    } catch (e) {
      return Result.failure(ErrorCode.E_IO, `模拟兑换失败：${(e as Error).message}`);
    }
  }

  static unitText(t: MockTransfer): string {
    return gasUnitLabel(t.gasScope as GasScope);
  }
}
