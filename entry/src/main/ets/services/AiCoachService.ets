import { http } from '@kit.NetworkKit';
import { AiConfig, AiModelOption, AiSuggestionView } from '../models/AiModels';
import { PlanOutcome } from '../models/PlanModels';
import { DateUtil, NumUtil } from '../common/Format';
import { Result, ErrorCode } from '../common/AppError';
import { AiConfigStore } from './AiConfigStore';
import { categoryName, PlanTaskStatus } from '../common/Domain';

/** OpenAI 兼容响应结构（只取需要的字段） */
interface AiChatMessage {
  content?: string;
}
/** 请求消息（显式接口，满足 ArkTS 对象字面量规则） */
interface AiChatRequestMessage {
  role: string;
  content: string;
}
interface AiChatChoice {
  message?: AiChatMessage;
}
interface AiChatError {
  message?: string;
}
interface AiChatResponse {
  choices?: AiChatChoice[];
  error?: AiChatError;
}
interface AiModelPricing {
  /** 单价可能是数字或字符串，不同中转站不一致 */
  prompt?: number | string;
  completion?: number | string;
}
interface AiModelEntry {
  id?: string;
  context_length?: number;
  pricing?: AiModelPricing;
}
interface AiModelListResponse {
  data?: AiModelEntry[];
  error?: AiChatError;
}

/**
 * AI 行动教练服务（可选、联网、默认关闭）。
 *
 * 只把"已保存计划"的公开摘要发给用户自己配置的 OpenAI 兼容接口：
 * 计划窗口、目标、预计值、预算和任务标题/类别/日期；
 * 不发送记录编号、备注、姓名、学号、积分明细或任何本地数据库内容。
 * AI 文本只作为执行提示，不参与核算、凭证、积分或目标达成判断。
 */
export class AiCoachService {
  private static readonly SYSTEM_PROMPT: string =
    '你是校园低碳记录应用里的行动教练。用户会给你一份已经生成的七日计划摘要。' +
    '请用不超过 120 个汉字，给出一段温和、具体、可执行的提醒，帮助用户完成其中一两项任务。' +
    '必须遵守：不得新增、修改或推测任何碳排放数值、因子、来源、核证或平台权益；' +
    '不得声称行为已被核实；不要使用列表符号、标题或英文；不要重复罗列任务清单。';

  /** 构造可审计的上下文摘要；不含身份与记录级隐私字段。 */
  static buildContext(outcome: PlanOutcome): string {
    const lines: string[] = [];
    lines.push(`计划窗口：${DateUtil.today()} 起 7 天`);
    lines.push(`目标：${NumUtil.show(outcome.plannedKg)}；剩余差额：${NumUtil.show(outcome.gapKg)}`);
    lines.push(`参与任务数：${outcome.participationCount}`);
    const visible = outcome.tasks.filter((t) => t.status !== PlanTaskStatus.SKIPPED);
    lines.push(`任务数：${visible.length}`);
    for (const t of visible) {
      const amount = t.participationOnly ? '只计参与，无减排数值' : `本地预计 ${NumUtil.show(t.expectedKg)}`;
      lines.push(`- ${t.day} ${categoryName(t.category)}「${t.name}」：${amount}`);
    }
    return lines.join('\n');
  }

  /** 发送一次补充建议请求；失败时返回可读原因，不抛出到界面。 */
  static async suggest(config: AiConfig, outcome: PlanOutcome): Promise<Result<AiSuggestionView>> {
    const context = AiCoachService.buildContext(outcome);
    const content = await AiCoachService.chat(config, AiCoachService.SYSTEM_PROMPT, context, 220);
    if (!content.ok || content.data === null) {
      return Result.failure(content.code, content.message);
    }
    const view: AiSuggestionView = {
      text: AiCoachService.sanitize(content.data),
      model: config.model.trim(),
      createdAt: DateUtil.toDateTime(new Date()),
      sentSummary: context
    };
    return Result.success(view);
  }

  /** 拉取中转站/接口的可用模型列表（含可选的上下文/价格元信息），便于避免模型名写错导致 404 */
  static async listModels(config: AiConfig): Promise<Result<AiModelOption[]>> {
    const endpoint = AiConfigStore.effectiveEndpoint(config.endpoint);
    const key = config.apiKey.trim();
    if (endpoint.length === 0 || key.length === 0) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '请先填写接口地址和 API Key。');
    }
    const modelsUrl = AiCoachService.modelsEndpoint(endpoint);
    const client = http.createHttp();
    try {
      const response = await client.request(modelsUrl, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': `Bearer ${key}` },
        connectTimeout: 15000,
        readTimeout: 20000,
        expectDataType: http.HttpDataType.STRING
      });
      const code = response.responseCode;
      const raw = typeof response.result === 'string' ? response.result : '';
      if (code !== 200) {
        return Result.failure(ErrorCode.E_IO, AiCoachService.describeHttpError(code, raw));
      }
      const parsed = JSON.parse(raw) as AiModelListResponse;
      if (parsed.data === undefined || parsed.data.length === 0) {
        return Result.failure(ErrorCode.E_IO, '接口没有返回模型列表，可直接手动填写模型名。');
      }
      const out: AiModelOption[] = [];
      for (const m of parsed.data) {
        const option = AiCoachService.parseModelOption(m);
        if (option !== null && out.findIndex((o: AiModelOption) => o.id === option.id) < 0) {
          out.push(option);
        }
      }
      return Result.success(out);
    } catch (e) {
      return Result.failure(ErrorCode.E_IO, `读取模型列表失败：${AiCoachService.describeNetworkError(AiCoachService.errText(e))}`);
    } finally {
      client.destroy();
    }
  }

  /** 把 /models 里的一条记录转成展示信息；id 缺失或为空时返回 null */
  static parseModelOption(entry: AiModelEntry): AiModelOption | null {
    if (entry.id === undefined || entry.id.length === 0) {
      return null;
    }
    const option: AiModelOption = { id: entry.id };
    if (entry.context_length !== undefined && Number.isFinite(entry.context_length) && entry.context_length > 0) {
      option.contextLength = entry.context_length;
    }
    const promptPrice = AiCoachService.pricePerMillion(entry.pricing?.prompt);
    if (promptPrice !== undefined) {
      option.priceIn = promptPrice;
    }
    const completionPrice = AiCoachService.pricePerMillion(entry.pricing?.completion);
    if (completionPrice !== undefined) {
      option.priceOut = completionPrice;
    }
    return option;
  }

  /**
   * 把接口返回的单价统一成"每百万 tokens"数值，便于横向比较。
   * 不同中转站单位不一：按 token 计价的数值通常远小于 0.001，按百万计价的通常不小于 0.001；
   * 该阈值只是展示参考，不参与任何结算，也不回写用户配置。
   */
  static pricePerMillion(raw: number | string | undefined): number | undefined {
    if (raw === undefined) {
      return undefined;
    }
    const value = typeof raw === 'string' ? Number.parseFloat(raw) : raw;
    if (!Number.isFinite(value) || value <= 0) {
      return undefined;
    }
    return value >= 0.001 ? value : value * 1000000;
  }

  /** 模型 chips 上的元信息文本，如「上下文64K · 输入0.27/输出1.1 每百万」；没有元数据时为空串 */
  static modelMetaText(option: AiModelOption): string {
    const parts: string[] = [];
    if (option.contextLength !== undefined) {
      parts.push(`上下文${AiCoachService.shortTokens(option.contextLength)}`);
    }
    if (option.priceIn !== undefined || option.priceOut !== undefined) {
      const inText = option.priceIn !== undefined ? AiCoachService.priceText(option.priceIn) : '?';
      const outText = option.priceOut !== undefined ? AiCoachService.priceText(option.priceOut) : '?';
      parts.push(`输入${inText}/输出${outText} 每百万`);
    }
    return parts.join(' · ');
  }

  private static shortTokens(tokens: number): string {
    if (tokens >= 1000000) {
      return `${AiCoachService.trimNumber(tokens / 1000000)}M`;
    }
    return `${Math.round(tokens / 1000)}K`;
  }

  private static priceText(value: number): string {
    return `${Number(value.toFixed(3))}`;
  }

  private static trimNumber(value: number): string {
    return `${Number(value.toFixed(1))}`;
  }

  /** 从 chat completions 地址推导模型列表地址 */
  static modelsEndpoint(endpoint: string): string {
    if (endpoint.endsWith('/chat/completions')) {
      return `${endpoint.substring(0, endpoint.length - '/chat/completions'.length)}/models`;
    }
    return endpoint;
  }

  /** 连通性测试：只发一句最小请求。 */
  static async test(config: AiConfig): Promise<Result<string>> {
    return AiCoachService.chat(config, '你是连通性测试助手。', '请只回复两个字：可用', 16);
  }

  /** 模型名可能的常见取值，仅用于错误提示，不自动替换用户配置。 */
  static modelHint(): string {
    return '常见示例：deepseek-chat、deepseek-v4-pro、gpt-4o-mini；请以中转站“模型广场/模型列表”为准。';
  }

  private static async chat(config: AiConfig, system: string, user: string, maxTokens: number): Promise<Result<string>> {
    const endpoint = AiConfigStore.effectiveEndpoint(config.endpoint);
    const model = config.model.trim();
    const key = config.apiKey.trim();
    if (endpoint.length === 0 || model.length === 0 || key.length === 0) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, 'AI 助手尚未配置，请先填写接口地址、模型和 API Key。');
    }
    if (!endpoint.startsWith('https://')) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '接口地址必须以 https:// 开头。');
    }
    const messages: AiChatRequestMessage[] = [];
    const systemMessage: AiChatRequestMessage = { role: 'system', content: system };
    const userMessage: AiChatRequestMessage = { role: 'user', content: user };
    messages.push(systemMessage);
    messages.push(userMessage);
    const body: string = JSON.stringify({
      model: model,
      messages: messages,
      temperature: 0.4,
      max_tokens: maxTokens,
      stream: false
    });
    const client = http.createHttp();
    try {
      const response = await client.request(endpoint, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${key}`
        },
        extraData: body,
        connectTimeout: 15000,
        readTimeout: 30000,
        expectDataType: http.HttpDataType.STRING
      });
      const code = response.responseCode;
      const raw = typeof response.result === 'string' ? response.result : '';
      if (code !== 200) {
        return Result.failure(ErrorCode.E_IO, AiCoachService.describeHttpError(code, raw));
      }
      const parsed = JSON.parse(raw) as AiChatResponse;
      if (parsed.error !== undefined && parsed.error.message !== undefined) {
        return Result.failure(ErrorCode.E_IO, `接口返回错误：${parsed.error.message}`);
      }
      if (parsed.choices === undefined || parsed.choices.length === 0) {
        return Result.failure(ErrorCode.E_IO, '接口没有返回可用内容，请检查模型名称与接口地址。');
      }
      const message = parsed.choices[0].message;
      const text = message !== undefined && message.content !== undefined ? message.content : '';
      if (text.trim().length === 0) {
        return Result.failure(ErrorCode.E_IO, '接口返回了空内容。');
      }
      return Result.success(text);
    } catch (e) {
      return Result.failure(ErrorCode.E_IO,
        `AI 请求未完成：${AiCoachService.describeNetworkError(AiCoachService.errText(e))}。本地记录、计划、周报与演练可继续离线使用。`);
    } finally {
      client.destroy();
    }
  }

  /** 把底层网络错误转成用户能看懂的中文，并保留必要原文。 */
  static describeNetworkError(detail: string): string {
    const lower = detail.toLowerCase();
    if (lower.indexOf('timeout') >= 0) {
      return '连接超时，请检查网络连接或接口地址';
    }
    if (lower.indexOf('resolve') >= 0 || lower.indexOf('host') >= 0 || lower.indexOf('dns') >= 0) {
      return '无法解析接口地址，请检查网络或域名';
    }
    if (lower.indexOf('refused') >= 0) {
      return '连接被拒绝，请检查接口地址与端口';
    }
    if (lower.indexOf('certificate') >= 0 || lower.indexOf('ssl') >= 0 || lower.indexOf('tls') >= 0) {
      return '证书校验失败，请确认接口使用有效的 https 证书';
    }
    return `网络不可用（${detail}）`;
  }

  /** 去掉列表符号与多余换行，避免把模型格式直接带进界面 */
  static sanitize(text: string): string {
    const lines: string[] = [];
    for (const raw of text.split('\n')) {
      let line = raw.trim();
      while (line.length > 0 && ('-•*· '.indexOf(line.charAt(0)) >= 0)) {
        line = line.substring(1).trim();
      }
      if (line.length > 0) {
        lines.push(line);
      }
    }
    return lines.join(' ').substring(0, 400);
  }

  private static describeHttpError(code: number, raw: string): string {
    if (code === 401 || code === 403) {
      return `接口拒绝访问（${code}），请检查 API Key 是否有效、是否有该模型的权限。`;
    }
    if (code === 404) {
      return '接口不存在（404）：请检查地址路径，或确认模型名在该中转站可用（部分中转站对未知模型返回 404）。';
    }
    if (code === 429) {
      return '接口限流或余额不足（429），请稍后再试。';
    }
    let detail = '';
    try {
      const parsed = JSON.parse(raw) as AiChatResponse;
      if (parsed.error !== undefined && parsed.error.message !== undefined) {
        detail = parsed.error.message;
      }
    } catch (e) {
      detail = '';
    }
    return detail.length > 0 ? `接口返回 ${code}：${detail}` : `接口返回 ${code}，请检查配置。`;
  }

  private static errText(e: object): string {
    const msg = (e as Error).message;
    return msg !== undefined ? msg : JSON.stringify(e);
  }
}
