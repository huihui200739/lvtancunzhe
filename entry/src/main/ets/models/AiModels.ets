/** AI 助手配置与结果模型。密钥只保存在本机应用沙箱，不进入账本、备份或导出。 */
export interface AiConfig {
  /** OpenAI 兼容的 chat completions 地址，必须使用 https */
  endpoint: string;
  /** 模型名，例如 deepseek-chat */
  model: string;
  /** 用户自备的 API Key，仅本机保存 */
  apiKey: string;
  /** 用户是否明确开启 AI 补充建议（默认关闭） */
  enabled: boolean;
}

/** 一次 AI 建议结果，带来源标注，便于界面如实展示。 */
export interface AiSuggestionView {
  text: string;
  model: string;
  createdAt: string;
  /** 本次请求实际发送的上下文摘要，便于用户核对没有隐私字段 */
  sentSummary: string;
}

export function emptyAiConfig(): AiConfig {
  return {
    endpoint: 'https://api.deepseek.com/chat/completions',
    model: 'deepseek-chat',
    apiKey: '',
    enabled: false
  };
}

/** 密钥展示用掩码：只保留后四位。 */
export function maskKey(key: string): string {
  if (key.length === 0) {
    return '未填写';
  }
  if (key.length <= 4) {
    return '••••';
  }
  return `••••${key.substring(key.length - 4)}`;
}

/** /models 列表里单个模型的展示信息；元数据缺失时保持未定义，界面如实省略 */
export interface AiModelOption {
  /** 模型名，可直接填入模型配置 */
  id: string;
  /** 上下文窗口（tokens），中转站未返回时不展示 */
  contextLength?: number;
  /** 每百万 tokens 输入价格（已归一化），未返回或不可信时不展示 */
  priceIn?: number;
  /** 每百万 tokens 输出价格（已归一化），未返回或不可信时不展示 */
  priceOut?: number;
}

/** 一条 AI 周报备注：只含清洗后的建议文本、模型名与生成时间；只存本机偏好文件，不进账本与导出 */
export interface AiNoteEntry {
  text: string;
  model: string;
  createdAt: string;
}
