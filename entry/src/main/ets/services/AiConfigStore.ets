import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AiConfig, emptyAiConfig } from '../models/AiModels';
import { Result, ErrorCode } from '../common/AppError';

/**
 * AI 配置存储。
 * 只使用应用沙箱内的 preferences，不写 RDB、不进备份/CSV 导出，也不写日志。
 */
export class AiConfigStore {
  private static readonly FILE_NAME = 'ai_assistant_settings';
  private static readonly KEY_ENDPOINT = 'endpoint';
  private static readonly KEY_MODEL = 'model';
  private static readonly KEY_API_KEY = 'api_key';
  private static readonly KEY_ENABLED = 'enabled';

  static async load(context: common.Context): Promise<AiConfig> {
    const config = emptyAiConfig();
    try {
      const store = await preferences.getPreferences(context, AiConfigStore.FILE_NAME);
      const endpoint = await store.get(AiConfigStore.KEY_ENDPOINT, config.endpoint);
      const model = await store.get(AiConfigStore.KEY_MODEL, config.model);
      const apiKey = await store.get(AiConfigStore.KEY_API_KEY, '');
      const enabled = await store.get(AiConfigStore.KEY_ENABLED, false);
      config.endpoint = `${endpoint}`;
      config.model = `${model}`;
      config.apiKey = `${apiKey}`;
      config.enabled = enabled === true;
    } catch (e) {
      // 读取失败时按未配置处理，不影响本地功能
    }
    return config;
  }

  static async save(context: common.Context, config: AiConfig): Promise<Result<boolean>> {
    const checked = AiConfigStore.validate(config);
    if (!checked.ok) {
      return checked;
    }
    try {
      const store = await preferences.getPreferences(context, AiConfigStore.FILE_NAME);
      await store.put(AiConfigStore.KEY_ENDPOINT, AiConfigStore.effectiveEndpoint(config.endpoint));
      await store.put(AiConfigStore.KEY_MODEL, config.model.trim());
      await store.put(AiConfigStore.KEY_API_KEY, config.apiKey.trim());
      await store.put(AiConfigStore.KEY_ENABLED, config.enabled);
      await store.flush();
      return Result.success(true);
    } catch (e) {
      return Result.failure(ErrorCode.E_IO, `保存 AI 设置失败：${AiConfigStore.errText(e)}`);
    }
  }

  /** 清除密钥与开关，保留地址和模型，便于用户重新填写 */
  static async clearKey(context: common.Context): Promise<Result<boolean>> {
    try {
      const store = await preferences.getPreferences(context, AiConfigStore.FILE_NAME);
      await store.delete(AiConfigStore.KEY_API_KEY);
      await store.put(AiConfigStore.KEY_ENABLED, false);
      await store.flush();
      return Result.success(true);
    } catch (e) {
      return Result.failure(ErrorCode.E_IO, `清除密钥失败：${AiConfigStore.errText(e)}`);
    }
  }

  /**
   * 归一化接口地址：允许用户只填中转站根地址或 /v1 结尾，
   * 统一补成 chat completions 路径，减少手填出错。
   */
  static effectiveEndpoint(raw: string): string {
    let endpoint = raw.trim();
    while (endpoint.length > 1 && endpoint.endsWith('/')) {
      endpoint = endpoint.substring(0, endpoint.length - 1);
    }
    if (endpoint.endsWith('/chat/completions')) {
      return endpoint;
    }
    if (endpoint.endsWith('/v1')) {
      return `${endpoint}/chat/completions`;
    }
    return `${endpoint}/v1/chat/completions`;
  }

  /** 配置校验：不联网，只检查字段与地址协议 */
  static validate(config: AiConfig): Result<boolean> {
    const endpoint = AiConfigStore.effectiveEndpoint(config.endpoint);
    const model = config.model.trim();
    const key = config.apiKey.trim();
    if (endpoint.length === 0) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '请填写接口地址。');
    }
    if (!endpoint.startsWith('https://')) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '接口地址必须以 https:// 开头，避免密钥明文传输。');
    }
    if (model.length === 0) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '请填写模型名称。');
    }
    if (key.length === 0) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '请填写 API Key。');
    }
    return Result.success(true);
  }

  private static errText(e: object): string {
    const msg = (e as Error).message;
    return msg !== undefined ? msg : JSON.stringify(e);
  }
}
