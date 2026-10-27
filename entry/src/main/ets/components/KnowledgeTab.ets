import { Theme } from '../common/Theme';
import { AppIcon, PageIntro, SectionHeading, Notice, EmptyState, SubpageHeader } from '../components/DesignSystem';
import { LedgerDb } from '../services/LedgerDb';
import { AppService } from '../services/AppService';
import { CarbonFactor } from '../models/CarbonFactor';
import { FigureData, FigureExample } from '../services/FigureData';
import { Article, ArticleCategory, articleCategoryName } from '../models/ContentModels';
import {
  FigureElec, FigureGas, FigureBaseline, FigureBubble, FigureScope,
  FigureBoundary, FigurePartial, FigureCommute, FigureRecycle, FigurePlate
} from './Figures';

interface CatOption {
  key: string;
  label: string;
}

/**
 * 科普 Tab（第 4.1 节 B4 + T04）：12 篇离线文章，政策 / 知识 / 技巧分类。
 * 内容来自本地库，断网可读（应用未申请任何网络权限）；每篇展开时渲染
 * 与其内容直接相关的自绘图示，数字取自因子库真实值，避免与凭证口径漂移。
 */

/** 图示许可文案：与「确有自绘图示」的事实一致 */
const FIGURE_LICENSE: string =
  '配图许可：本文配图为应用内自绘示意图（布局形状组件直接绘制，不引用任何外部图片素材），无第三方授权要求。';

/** 图示数字所依赖的因子编码（change 时需同步更换对应图示） */
const FIG_CODES: string[] = [
  'EF_ELEC_CN_2023', 'EF_ELEC_CN_NONFOSSIL_EXCLUDED_2023', 'EF_ELEC_CN_FOSSIL_2023',
  'EF_ELEC_HENAN_2023', 'EF_TRAVEL_GASOLINE_MASS_2015', 'EF_RECYCLE_PAPER_UTILIZED_2022',
  'EF_FOOD_APPLE_PROCUREMENT_PN2018'
];

@Component
export struct KnowledgeTab {
  @Prop @Watch('onTick') tick: number = 0;
  @State articles: Article[] = [];
  @State filterKey: string = 'all';
  @State expandId: string = '';
  @State message: string = '';
  /** 图示因子：code → 完整数值、单位与边界；缺数据时该篇文章不渲染图示，许可行退回说明文字 */
  @State fMap: Map<string, CarbonFactor> = new Map<string, CarbonFactor>();

  private cats: CatOption[] = [
    { key: 'all', label: '全部' },
    { key: 'policy', label: '政策' },
    { key: 'knowledge', label: '知识' },
    { key: 'tip', label: '技巧' }
  ];

  aboutToAppear(): void {
    this.reload();
  }

  onTick(): void {
    // 离线内容无需随全局刷新变化；因子值在进入此 Tab 时已随库加载
  }

  private async reload(): Promise<void> {
    if (!AppService.isReady()) {
      this.message = '数据库尚未就绪。';
      return;
    }
    try {
      this.articles = await LedgerDb.get().listArticles();
      const map: Map<string, CarbonFactor> = new Map<string, CarbonFactor>();
      const defs = AppService.repo().listUsable();
      for (const code of FIG_CODES) {
        for (const f of defs) {
          if (f.code === code) {
            map.set(code, f);
          }
        }
      }
      this.fMap = map;
    } catch (e) {
      this.message = `读取文章失败：${(e as Error).message}`;
    }
  }

  private match(a: Article): boolean {
    if (this.filterKey === 'all') {
      return true;
    }
    if (this.filterKey === 'policy') {
      return a.category === ArticleCategory.POLICY;
    }
    if (this.filterKey === 'knowledge') {
      return a.category === ArticleCategory.KNOWLEDGE;
    }
    return a.category === ArticleCategory.TIP;
  }

  /** 图示数值读取：缺数据返回 0（调用处已用 figReady 保证不渲染） */
  private figVal(code: string): number {
    const v = this.fMap.get(code);
    if (v === undefined) {
      return 0;
    }
    return v.value;
  }

  /** 该文章有图示所需全部数据时返回 true（缺数据则不渲染图示，许可行退回通用说明） */
  private figReady(a: Article): boolean {
    const need: string[] = [];
    if (a.articleId === 'A02' || a.articleId === 'A10') {
      need.push('EF_ELEC_CN_2023', 'EF_ELEC_CN_NONFOSSIL_EXCLUDED_2023', 'EF_ELEC_CN_FOSSIL_2023', 'EF_ELEC_HENAN_2023');
    } else if (a.articleId === 'A03' || a.articleId === 'A06' || a.articleId === 'A09') {
      need.push('EF_TRAVEL_GASOLINE_MASS_2015');
    } else if (a.articleId === 'A05') {
      need.push('EF_RECYCLE_PAPER_UTILIZED_2022', 'EF_FOOD_APPLE_PROCUREMENT_PN2018');
    } else if (a.articleId === 'A11') {
      need.push('EF_RECYCLE_PAPER_UTILIZED_2022');
    } else if (a.articleId === 'A07') {
      need.push('EF_TRAVEL_GASOLINE_MASS_2015', 'EF_ELEC_HENAN_2023', 'EF_RECYCLE_PAPER_UTILIZED_2022', 'EF_FOOD_APPLE_PROCUREMENT_PN2018');
    } else if (a.articleId === 'A12') {
      need.push('EF_FOOD_APPLE_PROCUREMENT_PN2018');
    } else if (a.articleId === 'A04' || a.articleId === 'A01' || a.articleId === 'A08') {
      return true;
    }
    for (const code of need) {
      const v = this.fMap.get(code);
      if (v === undefined || !Number.isFinite(v.value) || v.value < 0) {
        return false;
      }
    }
    return true;
  }

  private example(code: string, quantity: number, action: string): FigureExample {
    return FigureData.fromFactor(this.fMap.get(code) as CarbonFactor, quantity, action);
  }

  @Builder
  figureOf(a: Article) {
    if (a.articleId === 'A02' || a.articleId === 'A10') {
      FigureElec(
        this.figVal('EF_ELEC_CN_2023'),
        this.figVal('EF_ELEC_CN_NONFOSSIL_EXCLUDED_2023'),
        this.figVal('EF_ELEC_CN_FOSSIL_2023'),
        this.figVal('EF_ELEC_HENAN_2023')
      )
    } else if (a.articleId === 'A05') {
      FigureGas(
        this.example('EF_RECYCLE_PAPER_UTILIZED_2022', 1, '废纸实际再生利用'),
        this.example('EF_FOOD_APPLE_PROCUREMENT_PN2018', 1, '减少苹果采购')
      )
    } else if (a.articleId === 'A03') {
      FigureBaseline(
        this.example('EF_TRAVEL_GASOLINE_MASS_2015', 0.5, '个人分担汽油'),
        '不同方法学有不同基准；本图只演示同一行程以步行或普通骑行替代原本汽油驾车的燃烧对照'
      )
    } else if (a.articleId === 'A06') {
      FigureBaseline(
        this.example('EF_TRAVEL_GASOLINE_MASS_2015', 0.5, '个人分担汽油'),
        '基准情景必须在录入时由你声明并确认；没有对照情景，就没有减排量'
      )
    } else if (a.articleId === 'A04') {
      FigureBubble()
    } else if (a.articleId === 'A01') {
      FigureScope()
    } else if (a.articleId === 'A07') {
      FigureBoundary([
        this.example('EF_TRAVEL_GASOLINE_MASS_2015', 1, '汽油出行'),
        this.example('EF_ELEC_HENAN_2023', 1, '河南用电'),
        this.example('EF_RECYCLE_PAPER_UTILIZED_2022', 1, '废纸再生利用'),
        this.example('EF_FOOD_APPLE_PROCUREMENT_PN2018', 1, '减少苹果采购')
      ])
    } else if (a.articleId === 'A08') {
      FigurePartial()
    } else if (a.articleId === 'A09') {
      FigureCommute(this.example('EF_TRAVEL_GASOLINE_MASS_2015', 0.5, '个人分担汽油'))
    } else if (a.articleId === 'A11') {
      FigureRecycle(this.example('EF_RECYCLE_PAPER_UTILIZED_2022', 1, '废纸实际再生利用'))
    } else if (a.articleId === 'A12') {
      FigurePlate(this.example('EF_FOOD_APPLE_PROCUREMENT_PN2018', 1, '减少苹果采购'))
    }
  }

  build() {
    Scroll() {
      Column() {
        PageIntro({ title: '懂一点，绿一点', subtitle: '把低碳知识，变成触手可及的日常。', eyebrow: '给生活的一点灵感 / JOURNAL' })
        Row() {
          Column({ space: 12 }) {
            Text('GREEN NOTES').fontSize(10).letterSpacing(2).fontColor(Theme.muted)
            Text('好的改变，\n从理解开始。').fontSize(25).lineHeight(36).fontWeight(FontWeight.Medium).fontColor(Theme.ink)
            Text(`${this.articles.length} 篇离线读物 · 随时翻阅`).fontSize(11).fontColor(Theme.muted)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Image($r('app.media.botanical')).width(this.getUIContext().fp2px(1) > this.getUIContext().vp2px(1) * 1.2 ? 56 : 100).height(172).objectFit(ImageFit.Contain).accessibilityLevel('no')
        }.width('100%').padding(24).backgroundColor('#E7EDD9').borderRadius(28)
        Row({ space: 8 }) {
          ForEach(this.cats, (c: CatOption) => {
            Text(c.label).fontSize(13).fontColor(this.filterKey === c.key ? Theme.paper : Theme.muted)
              .layoutWeight(1).textAlign(TextAlign.Center).padding({ top: 13, bottom: 13 }).borderRadius(18)
              .backgroundColor(this.filterKey === c.key ? Theme.green : Theme.paper)
              .onClick(() => { this.filterKey = c.key; this.expandId = ''; })
          }, (c: CatOption) => c.key)
        }.width('100%').margin({ top: 24, bottom: 22 })
        if (this.message.length > 0) { Notice({ text: this.message, warning: true }) }
        ForEach(this.articles.filter((a: Article) => this.match(a)), (a: Article) => { this.articleCard(a); }, (a: Article) => a.articleId)
        Text('读懂一件事，再试着做一件小事。').fontSize(11).fontColor(Theme.muted).margin({ top: 16, bottom: 30 })
      }.width('100%').padding({ left: 22, right: 22 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Off).backgroundColor(Theme.bg)
  }

  @Builder
  articleCard(a: Article) {
    Column({ space: 12 }) {
      Row() {
        Text(articleCategoryName(a.category)).fontSize(10).fontColor(Theme.green).padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(Theme.sage).borderRadius(8)
        Blank()
        Text(`${a.readMinutes} 分钟阅读`).fontSize(10).fontColor(Theme.muted)
      }.width('100%')
      Text(a.title).fontSize(19).lineHeight(29).fontWeight(FontWeight.Medium).fontColor(Theme.ink).width('100%')
      Text(a.summary).fontSize(13).lineHeight(23).fontColor(Theme.muted).width('100%')
      if (this.expandId === a.articleId) {
        if (this.figReady(a)) {
          this.figureOf(a)
        } else {
          Text('配图说明：本篇图示依赖的因子数据未就绪，暂以正文说明替代。').fontSize(10).fontColor(Theme.muted).width('100%')
        }
        Divider().color(Theme.line).margin({ top: 4, bottom: 4 })
        Text(a.body).fontSize(15).lineHeight(28).fontColor(Theme.ink).width('100%')
        Text(`来源：${a.sourceTitle}`).fontSize(11).lineHeight(20).fontColor(Theme.muted).width('100%')
        Text(this.figReady(a) ? FIGURE_LICENSE : '配图许可：本篇暂无叠加图示；顶部植物为本应用统一品牌插图，非本篇内容图。')
          .fontSize(10).lineHeight(16).fontColor(Theme.muted).width('100%')
      }
      Row() {
        Text(this.expandId === a.articleId ? '收起文章' : '慢慢读一读').fontSize(12).fontColor(Theme.green).layoutWeight(1)
        AppIcon({ name: 'arrow', iconSize: 18 })
      }.width('100%').padding({ top: 6, bottom: 4 })
    }.width('100%').padding(22).backgroundColor(Theme.paper).borderRadius(24).margin({ bottom: 14 })
      .onClick(() => { this.expandId = this.expandId === a.articleId ? '' : a.articleId; })
  }
}
