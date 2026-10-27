/**
 * 科普文章（article 表）与徽章（badge 表）。
 * 第 4.1 节 B4：12 篇离线文章，政策 / 知识 / 技巧三类，每篇有标题、正文、配图及来源，断网可读。
 */

export enum ArticleCategory {
  POLICY = 'policy',   // 政策
  KNOWLEDGE = 'knowledge', // 知识
  TIP = 'tip'          // 技巧
}

/** 科普文章 */
export interface Article {
  articleId: string;
  title: string;
  category: ArticleCategory;
  /** 摘要 */
  summary: string;
  /** 正文（Markdown 风格纯文本，段落以 \n\n 分隔） */
  body: string;
  /** 配图资源名（media 资源）或空串 */
  image: string;
  /** 来源标题 */
  sourceTitle: string;
  sourceUrl: string;
  /** 图片许可说明 */
  imageLicense: string;
  /** 阅读时长（分钟）估 */
  readMinutes: number;
}

/** 徽章定义 */
export interface BadgeDef {
  badgeId: string;
  name: string;
  /** 解锁条件说明 */
  condition: string;
  /** 解锁规则类型 */
  ruleKind: string;   // 'first_record' | 'category_count' | 'streak_days' | 'purchase'
  /** 规则参数：类别 / 次数 / 天数 / 价格 */
  ruleCategory: string;
  ruleThreshold: number;
  /** 是否为成就类（解锁即得，不消耗积分） */
  achievement: boolean;
}

export function articleCategoryName(c: ArticleCategory): string {
  if (c === ArticleCategory.POLICY) {
    return '政策';
  } else if (c === ArticleCategory.KNOWLEDGE) {
    return '知识';
  }
  return '技巧';
}
