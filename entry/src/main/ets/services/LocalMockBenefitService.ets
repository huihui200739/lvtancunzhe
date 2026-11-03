import { RecordStatus, GasScope, gasUnitLabel } from '../common/Domain';
import { VoucherView } from '../models/RecordModels';
import { Result } from '../common/AppError';

export interface MockBenefitDecision {
  eligible: boolean;
  reason: string;
  requestId: string;
  recordId: string;
  revision: number;
  amountKg: number;
  gasScope: string;
}

export interface MockBenefitReceipt {
  requestId: string;
  status: string;
  platformName: string;
  amountKg: number;
  unit: string;
  createdAt: string;
  notice: string;
}

/**
 * 离线碳普惠接口演练器。仅在内存生成可重复的模拟回执，不联网、不写数据库、
 * 不发放积分/权益，也不构成真实平台接入或碳资产登记。
 */
export class LocalMockBenefitService {
  private static receipts: Map<string, MockBenefitReceipt> = new Map<string, MockBenefitReceipt>();
  private static readonly PLATFORM_NAME = '校园碳普惠接口演练（本地模拟）';
  private static readonly NOTICE = '模拟回执，不是平台交易、真实积分或经核证碳资产。';

  static simulationNotice(): string {
    return LocalMockBenefitService.NOTICE;
  }

  static evaluate(voucher: VoucherView): MockBenefitDecision {
    const requestId = LocalMockBenefitService.requestId(voucher.record.recordId, voucher.record.revision);
    let reason = '';
    if (voucher.record.recordId.length === 0 || !Number.isInteger(voucher.record.revision) || voucher.record.revision < 1) {
      reason = '记录版本信息不完整。';
    } else if (voucher.record.status !== RecordStatus.ACTIVE || !voucher.isLatest) {
      reason = '仅可演练当前有效的最新记录。';
    } else if (!Number.isFinite(voucher.snapshot.reductionKg) || voucher.snapshot.reductionKg <= 0 || voucher.snapshot.isNetIncrease) {
      reason = '仅接收正向估算结果；净增排或无正向结果不进入演练。';
    } else if (voucher.snapshot.gasScope !== GasScope.CO2 && voucher.snapshot.gasScope !== GasScope.CO2E) {
      reason = '记录的气体口径无效。';
    } else if (voucher.sources.length === 0 || voucher.sources.some((source) => source.reviewStatus !== 'verified')) {
      reason = '缺少可用的已核验来源快照。';
    }
    return {
      eligible: reason.length === 0,
      reason: reason,
      requestId: requestId,
      recordId: voucher.record.recordId,
      revision: voucher.record.revision,
      amountKg: reason.length === 0 ? voucher.snapshot.reductionKg : 0,
      gasScope: reason.length === 0 ? `${voucher.snapshot.gasScope}` : ''
    };
  }

  static submit(voucher: VoucherView, now: string): Result<MockBenefitReceipt> {
    const decision = LocalMockBenefitService.evaluate(voucher);
    if (!decision.eligible) {
      return Result.failure('E_MOCK_BENEFIT_INELIGIBLE', decision.reason);
    }
    const previous = LocalMockBenefitService.receipts.get(decision.requestId);
    if (previous !== undefined) {
      return Result.success(previous);
    }
    const receipt: MockBenefitReceipt = {
      requestId: decision.requestId,
      status: 'SIMULATED_ACCEPTED',
      platformName: LocalMockBenefitService.PLATFORM_NAME,
      amountKg: decision.amountKg,
      unit: gasUnitLabel(decision.gasScope as GasScope),
      createdAt: now,
      notice: LocalMockBenefitService.NOTICE
    };
    LocalMockBenefitService.receipts.set(receipt.requestId, receipt);
    return Result.success(receipt);
  }

  static query(requestId: string): Result<MockBenefitReceipt> {
    const receipt = LocalMockBenefitService.receipts.get(requestId);
    if (receipt === undefined) {
      return Result.failure('E_MOCK_BENEFIT_NOT_FOUND', '本次运行中没有找到该模拟回执。');
    }
    return Result.success(receipt);
  }

  private static requestId(recordId: string, revision: number): string {
    const input = `${recordId}#${revision}`;
    let hash = 2166136261;
    for (let i = 0; i < input.length; i++) {
      hash = Math.imul(hash ^ input.charCodeAt(i), 16777619) >>> 0;
    }
    return `SIM-${hash.toString(16).toUpperCase().padStart(8, '0')}`;
  }
}
