import { util } from '@kit.ArkTS';

/**
 * 稳定标识生成（第 8.3 节）：
 * 记录、积分事件、兑换请求使用稳定 UUID，不用设备自增整数作为跨设备唯一标识。
 */
export class Ids {
  /** 随机 UUID */
  static uuid(): string {
    return util.generateRandomUUID(true);
  }

  /** 带前缀的标识，便于日志与调试识别 */
  static withPrefix(prefix: string): string {
    return `${prefix}_${util.generateRandomUUID(true)}`;
  }
}
