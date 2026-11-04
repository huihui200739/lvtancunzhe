import { BehaviorCategory } from '../common/Domain';

/** 一个类别标签与端侧模型给出的置信度（已按模型示例的阈值归一化到 0–1） */
export interface LabelScore {
  label: string;
  score: number;
}

/** 根据识别标签给出的存入单建议；只用于预选类别与提示，不产生任何数量或减排值 */
export interface PhotoSuggestion {
  category: BehaviorCategory;
  categoryLabel: string;
  /** 触发这条建议的识别标签（中文） */
  evidence: string[];
  score: number;
  /** 打开存入单后需要用户自己补齐的事项 */
  hint: string;
}

/** 一次识别的结论：建议列表为空时如实说明 */
export interface PhotoInsight {
  suggestions: PhotoSuggestion[];
  /** 置信度最高的若干标签，界面上原样展示，方便核对模型看到了什么 */
  topLabels: LabelScore[];
  message: string;
}

interface CategoryRule {
  category: BehaviorCategory;
  categoryLabel: string;
  labels: string[];
  hint: string;
}

/**
 * 识别标签 → 存入单的映射。只挑与四类已开放场景直接相关的标签；
 * Vehicle/Car/Bus 这类“驾车或公交”的画面不推断为减排，避免把拍到汽车当作绿色出行。
 */
const RULES: CategoryRule[] = [
  { category: BehaviorCategory.TRAVEL, categoryLabel: '换种出行', labels: ['Bicycle', 'Cycling', 'Wheel'],
    hint: '照片只能说明画面里有自行车。请自己填写骑行公里数，以及原本驾车会消耗的汽油质量。' },
  { category: BehaviorCategory.FOOD, categoryLabel: '少买不浪费', labels: ['Fruit', 'Food', 'Vegetable', 'Meal', 'Lunch', 'Supper', 'Cuisine'],
    hint: '照片不能证明少买了多少。当前只开放“按需采购苹果”场景，请填写减少采购的重量与对照依据；吃完一顿饭不计 kg。' },
  { category: BehaviorCategory.RECYCLING, categoryLabel: '废纸再生', labels: ['Paper', 'Newspaper', 'News'],
    hint: '照片只能说明画面里有纸张。只有已确认进入再生利用的废纸才能计入，请填写重量与接收方。' },
  { category: BehaviorCategory.WATER_ENERGY, categoryLabel: '省下的电', labels: ['Television', 'Computer', 'Lampshade', 'Desk'],
    hint: '照片只能说明画面里有用电设备。请按电表或功率×时长填写实际少用的 kWh。' }
];

/** 识别标签中文名，用于界面展示 */
const LABEL_ZH: Record<string, string> = {
  'Bicycle': '自行车', 'Cycling': '骑行', 'Wheel': '车轮', 'Fruit': '水果', 'Food': '食物', 'Vegetable': '蔬菜',
  'Meal': '餐食', 'Lunch': '午餐', 'Supper': '晚餐', 'Cuisine': '菜肴', 'Paper': '纸张', 'Newspaper': '报纸',
  'News': '新闻纸', 'Television': '电视', 'Computer': '电脑', 'Lampshade': '灯罩', 'Desk': '书桌',
  'Vehicle': '车辆', 'Car': '汽车', 'Bus': '公交车', 'Plant': '植物', 'Person': '人物', 'Product': '物品',
  'Room': '室内', 'Wall': '墙面', 'Building': '建筑', 'Infrastructure': '道路设施', 'Sky': '天空', 'Tire': '轮胎'
};

export function labelName(label: string): string {
  const zh = LABEL_ZH[label];
  return zh !== undefined ? `${zh} ${label}` : label;
}

/**
 * 拍照辅助记账：把端侧模型的类别分数整理成“建议填写哪张存入单”。
 * 纯函数，不读写数据库；数量、对照情景和依据始终由用户在录入页填写并确认。
 */
export class PhotoAssist {
  /** 示例代码的判定线：归一化分数 ≥ 0.5 视为模型认为画面中出现了该类别 */
  static readonly PRESENT: number = 0.5;
  static readonly TOP_N: number = 5;

  /**
   * 按模型示例的阈值把原始分数归一化：低于阈值压到 0–0.5，高于阈值拉到 0.5–1。
   * 与 MindSpore 图像分类示例 ProcessRunnetResult 的处理一致。
   */
  static normalize(raw: number[], thresholds: number[]): number[] {
    const out: number[] = [];
    for (let i = 0; i < raw.length; i++) {
      const t = i < thresholds.length ? thresholds[i] : 0.5;
      const p = Number.isFinite(raw[i]) ? Math.min(1, Math.max(0, raw[i])) : 0;
      if (t <= 0 || t >= 1) {
        out.push(p);
      } else if (p < t) {
        out.push(p / t * 0.5);
      } else {
        out.push((p - t) / (1 - t) * 0.5 + 0.5);
      }
    }
    return out;
  }

  static topLabels(scores: number[], labels: string[], n: number = PhotoAssist.TOP_N): LabelScore[] {
    const idx: number[] = [];
    for (let i = 0; i < Math.min(scores.length, labels.length); i++) {
      idx.push(i);
    }
    idx.sort((a: number, b: number) => scores[b] - scores[a] || a - b);
    return idx.slice(0, Math.max(0, n)).map((i: number) => ({ label: labels[i], score: scores[i] }) as LabelScore);
  }

  static suggest(scores: number[], labels: string[]): PhotoInsight {
    const top = PhotoAssist.topLabels(scores, labels);
    const byLabel = new Map<string, number>();
    for (let i = 0; i < Math.min(scores.length, labels.length); i++) {
      byLabel.set(labels[i], scores[i]);
    }
    const suggestions: PhotoSuggestion[] = [];
    for (const rule of RULES) {
      let best = 0;
      const evidence: string[] = [];
      for (const label of rule.labels) {
        const s = byLabel.get(label);
        if (s !== undefined && s >= PhotoAssist.PRESENT) {
          evidence.push(labelName(label));
          best = Math.max(best, s);
        }
      }
      if (evidence.length > 0) {
        suggestions.push({ category: rule.category, categoryLabel: rule.categoryLabel, evidence: evidence,
          score: best, hint: rule.hint });
      }
    }
    suggestions.sort((a: PhotoSuggestion, b: PhotoSuggestion) => b.score - a.score);
    let message = '';
    if (suggestions.length === 0) {
      message = '没有认出与四类存入单直接相关的物体。照片不会自动记账，可以换一张，或直接手动选择存入单。';
    } else {
      message = '只是建议填写哪张存入单。数量、原本做法和依据仍需你自己填写并确认。';
    }
    return { suggestions: suggestions, topLabels: top, message: message };
  }
}
