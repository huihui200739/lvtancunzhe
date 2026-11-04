import { LedgerOperations } from '../services/LedgerOperations';
import { Theme } from '../common/Theme';
import { AppIcon, PageIntro, SectionHeading, Notice, EmptyState, SubpageHeader } from '../components/DesignSystem';
import { LedgerDb } from '../services/LedgerDb';
import { AppService } from '../services/AppService';
import { StatsService } from '../services/StatsService';
import { LineChart } from './LineChart';
import { BarChart } from './BarChart';
import { PieChart } from './PieChart';
import { StatBucket, StatsSummary } from '../models/StatsModels';
import { BehaviorCategory, TimeDimension, GasScope, gasUnitLabel } from '../common/Domain';
import { DateUtil, NumUtil } from '../common/Format';

function emptySummary(): StatsSummary {
  return {
    buckets: [],
    categories: [],
    totalPositiveKg: 0,
    totalNegativeKg: 0,
    totalNetKg: 0,
    recordCount: 0,
    allZero: true,
    gasScopes: []
  };
}

interface DimOption {
  key: string;
  label: string;
}

/**
 * 汇总单元格。用带 @Prop 的子组件而非按值传参的 @Builder：
 * ArkUI 的 @Builder 按值传参时不会随参数变化刷新，会停留在初始值。
 */
@Component
struct SummaryCell {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop color: string = Theme.ink;

  build() {
    Column() {
      Text(this.value).fontSize(22).fontColor(this.color).fontWeight(FontWeight.Medium).fontFeature('"tnum" on')
      Text(this.label).fontSize(11).fontColor(Theme.muted).margin({ top: 2 })
    }
    .layoutWeight(1)
  }
}

/**
 * 看板 Tab（第 4.1 节 B2）：折线、柱状、饼图三图齐全；
 * 日 / 周 / 月 / 年四种视图，支持分类与日期查询；与明细汇总口径一致。
 */
@Component
export struct DashboardTab {
  @Prop @Watch('onTick') tick: number = 0;
  @State scopeKey: string = '';
  @State showFilters: boolean = false;
  @State dimKey: string = 'day';
  @State categoryKey: string = 'all';
  @State from: string = DateUtil.addDays(DateUtil.today(), -6);
  @State to: string = DateUtil.today();
  @State draftFrom: string = this.from;
  @State draftTo: string = this.to;
  @State loading: boolean = false;
  @State appliedLabel: string = '';
  @State appliedScope: string = '';
  /** 周/月/年视图最近区间 chips：超过 3 个时默认收起，可点「更多」展开 */
  @State recentExpanded: boolean = false;
  private reloadVersion: number = 0;
  @State summary: StatsSummary = emptySummary();
  @State message: string = '';
  @State selectedKey: string = '';
  @State selectedCategory: string = '';
  @Link ledgerFrom: string;
  @Link ledgerTo: string;

  private dims: DimOption[] = [
    { key: 'day', label: '日' },
    { key: 'week', label: '周' },
    { key: 'month', label: '月' },
    { key: 'year', label: '年' }
  ];

  aboutToAppear(): void {
    this.applyDefaultRange();
    this.reload(true);
  }

  onTick(): void {
    this.reload();
  }

  private dimension(): TimeDimension {
    if (this.dimKey === 'week') {
      return TimeDimension.WEEK;
    } else if (this.dimKey === 'month') {
      return TimeDimension.MONTH;
    } else if (this.dimKey === 'year') {
      return TimeDimension.YEAR;
    }
    return TimeDimension.DAY;
  }

  private category(): BehaviorCategory | null {
    if (this.categoryKey === 'travel') {
      return BehaviorCategory.TRAVEL;
    } else if (this.categoryKey === 'water_energy') {
      return BehaviorCategory.WATER_ENERGY;
    } else if (this.categoryKey === 'recycling') {
      return BehaviorCategory.RECYCLING;
    } else if (this.categoryKey === 'food') {
      return BehaviorCategory.FOOD;
    }
    return null;
  }

  private applyDefaultRange(): void {
    const d = this.dimension();
    this.draftFrom = StatsService.defaultFrom(d);
    this.draftTo = DateUtil.today();
  }

  private async reload(applyDates: boolean = false): Promise<void> {
    const version = ++this.reloadVersion;
    const from = applyDates ? this.draftFrom : this.from;
    const to = applyDates ? this.draftTo : this.to;
    const dimension = this.dimension();
    const category = this.category();
    const scope = this.scopeKey;
    const label = `${this.catLabel(this.categoryKey)} · ${this.dims.filter((d: DimOption) => d.key === this.dimKey)[0].label}视图`;
    this.loading = false;
    if (!AppService.isReady()) { this.message = '数据库尚未就绪。'; return; }
    if (!DateUtil.isValidDay(from) || !DateUtil.isValidDay(to) || from > to) {
      this.message = '请选择有效的起止日期，起点不能晚于终点。下方保留上次查询结果。'; return;
    }
    this.loading = true;
    this.message = '';
    try {
      const summary = await LedgerOperations.run(() => StatsService.summary(LedgerDb.get(), dimension, from, to, category, scope));
      if (version !== this.reloadVersion) { return; }
      this.summary = summary;
      this.from = from; this.to = to; this.appliedLabel = label;
      this.selectedCategory = '';
      this.selectedKey = this.lastBucketWithData();
      this.scopeKey = summary.gasScopes.indexOf(scope) >= 0 ? scope : (summary.gasScopes.length > 0 ? summary.gasScopes[0] : scope);
      this.appliedScope = this.scopeKey;
    } catch (e) {
      if (version === this.reloadVersion) { this.message = `统计失败，下方保留上次查询结果：${(e as Error).message}`; }
    } finally {
      if (version === this.reloadVersion) { this.loading = false; }
    }
  }

  /**
   * 日视图按区间补齐没有记录的日期：趋势图需要连续时间轴，
   * 缺日按 0 显示，避免一个点或断开的折线。其他维度沿用服务端分桶。
   */
  private paddedBuckets(): StatBucket[] {
    const existing: Map<string, StatBucket> = new Map<string, StatBucket>();
    for (const b of this.summary.buckets) {
      existing.set(b.key, b);
    }
    const out: StatBucket[] = [];
    const dim = this.dimension();
    if (dim === TimeDimension.DAY) {
      let day = this.from;
      while (day <= this.to && out.length < 400) {
        out.push(this.bucketOrZero(existing, day, day.substring(5)));
        day = DateUtil.addDays(day, 1);
      }
    } else if (dim === TimeDimension.WEEK) {
      let week = DateUtil.weekStart(this.from);
      const last = DateUtil.weekStart(this.to);
      while (week <= last && out.length < 120) {
        out.push(this.bucketOrZero(existing, week, `${week.substring(5)} 起`));
        week = DateUtil.addDays(week, 7);
      }
    } else if (dim === TimeDimension.MONTH) {
      let year = Number.parseInt(this.from.substring(0, 4), 10);
      let month = Number.parseInt(this.from.substring(5, 7), 10);
      const endKey = DateUtil.monthKey(this.to);
      while (out.length < 120) {
        const key = `${year}-${month < 10 ? '0' : ''}${month}`;
        if (key > endKey) { break; }
        out.push(this.bucketOrZero(existing, key, key));
        month++;
        if (month > 12) { month = 1; year++; }
      }
    } else {
      let year = Number.parseInt(DateUtil.yearKey(this.from), 10);
      const endYear = Number.parseInt(DateUtil.yearKey(this.to), 10);
      while (year <= endYear && out.length < 60) {
        const key = `${year}`;
        out.push(this.bucketOrZero(existing, key, `${key}年`));
        year++;
      }
    }
    return out.length > 0 ? out : this.summary.buckets;
  }

  private bucketOrZero(existing: Map<string, StatBucket>, key: string, label: string): StatBucket {
    const found = existing.get(key);
    if (found !== undefined) {
      return found;
    }
    return { key: key, label: label, positiveKg: 0, negativeKg: 0, netKg: 0, count: 0 };
  }

  /** 点选图表后的单日/单周明细；未选中时返回空串 */
  private selectedDetail(): string {
    if (this.selectedKey.length === 0) {
      return '';
    }
    for (const b of this.paddedBuckets()) {
      if (b.key === this.selectedKey) {
        if (b.count === 0) {
          return `${b.label} · ${this.periodWord()}没有记录`;
        }
        return `${b.label} · 净变化 ${NumUtil.signed(b.netKg, 2)} · 正向 ${NumUtil.show(b.positiveKg)} / 增加 ${NumUtil.show(b.negativeKg)} · ${b.count} 条记录`;
      }
    }
    return '';
  }

  /** 默认聚焦最后一个有记录的区间，便于直接看明细 */
  private lastBucketWithData(): string {
    const list = this.paddedBuckets();
    for (let i = list.length - 1; i >= 0; i--) {
      if (list[i].count > 0) {
        return list[i].key;
      }
    }
    return '';
  }

  /** 点明细跳到存折，并按当前维度给出筛选区间 */
  private jumpToSelectedRange(): void {
    if (this.selectedKey.length === 0) {
      return;
    }
    for (const b of this.paddedBuckets()) {
      if (b.key !== this.selectedKey || b.count === 0) {
        continue;
      }
      const dim = this.dimension();
      if (dim === TimeDimension.DAY) {
        this.ledgerFrom = b.key;
        this.ledgerTo = b.key;
      } else if (dim === TimeDimension.WEEK) {
        this.ledgerFrom = b.key;
        this.ledgerTo = DateUtil.addDays(b.key, 6);
      } else if (dim === TimeDimension.MONTH) {
        this.ledgerFrom = `${b.key}-01`;
        this.ledgerTo = `${b.key}-${this.daysInMonth(b.key)}`;
      } else {
        this.ledgerFrom = `${b.key}-01-01`;
        this.ledgerTo = `${b.key}-12-31`;
      }
      return;
    }
  }

  /** 最近有记录的若干个区间，作为周/月/年视图的快捷入口；limit<=0 表示全部 */
  private recentWithData(limit: number): StatBucket[] {
    const list = this.paddedBuckets();
    const out: StatBucket[] = [];
    for (let i = list.length - 1; i >= 0; i--) {
      if (list[i].count > 0 && (limit <= 0 || out.length < limit)) {
        out.unshift(list[i]);
      }
    }
    return out;
  }

  private daysInMonth(monthKey: string): string {
    const year = Number.parseInt(monthKey.substring(0, 4), 10);
    const month = Number.parseInt(monthKey.substring(5, 7), 10);
    const days: number[] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    let last = days[month - 1];
    if (month === 2 && (year % 4 === 0 && year % 100 !== 0 || year % 400 === 0)) {
      last = 29;
    }
    return last < 10 ? `0${last}` : `${last}`;
  }

  /** 逐格前后查看：在有数据的区间之间移动也会经过空区间，文案会说明“没有记录” */
  private stepSelection(delta: number): void {
    const list = this.paddedBuckets();
    if (list.length === 0) {
      return;
    }
    let index = -1;
    for (let i = 0; i < list.length; i++) {
      if (list[i].key === this.selectedKey) { index = i; }
    }
    if (index < 0) {
      index = list.length - 1;
    }
    let next = index + delta;
    if (next < 0) { next = 0; }
    if (next > list.length - 1) { next = list.length - 1; }
    this.selectedKey = list[next].key;
  }

  /** 空区间的说法随维度变化 */
  private periodWord(): string {
    const dim = this.dimension();
    if (dim === TimeDimension.DAY) { return '当天'; }
    if (dim === TimeDimension.WEEK) { return '该周'; }
    if (dim === TimeDimension.MONTH) { return '该月'; }
    return '该年';
  }

  private catLabel(key: string): string {
    if (key === 'travel') {
      return '出行';
    } else if (key === 'water_energy') {
      return '节水节电';
    } else if (key === 'recycling') {
      return '旧物回收';
    } else if (key === 'food') {
      return '光盘行动';
    }
    return '全部';
  }

  build() {
    Scroll() {
      Column() {
        PageIntro({ title: '记录趋势', subtitle: '按日期和类别查看已记录行为的净变化。', eyebrow: '账本趋势' })
        Row({ space: 8 }) {
          ForEach(this.dims, (d: DimOption) => {
            Text(d.label).fontSize(14).fontColor(this.dimKey === d.key ? Theme.paper : Theme.muted)
              .layoutWeight(1).textAlign(TextAlign.Center).padding({ top: 13, bottom: 13 }).borderRadius(18)
              .backgroundColor(this.dimKey === d.key ? Theme.green : Theme.paper)
              .onClick(() => { this.dimKey = d.key; this.applyDefaultRange(); this.reload(true); })
          }, (d: DimOption) => d.key)
        }.width('100%').margin({ bottom: 20 })
        Column({ space: 20 }) {
          Row() {
            Text('这段时间的净变化').fontSize(13).fontColor(Theme.muted).layoutWeight(1)
            Text(this.appliedScope === 'CO2e' ? 'kgCO₂e' : 'kgCO₂').fontSize(11).fontColor(Theme.green)
          }.width('100%')
          Text(`${this.from} — ${this.to} · ${this.appliedLabel}`).fontSize(11).fontColor(Theme.muted).width('100%')
          Text(NumUtil.signed(this.summary.totalNetKg, 2)).fontSize(46).fontWeight(FontWeight.Medium).fontColor(Theme.green).fontFeature('"tnum" on').maxLines(1).minFontSize(24).maxFontSize(46).heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).width('100%')
          Divider().color('#D6D4CC').margin({ top: 2, bottom: 14 })
          Row() {
            SummaryCell({ label: '正向贡献', value: NumUtil.show(this.summary.totalPositiveKg), color: Theme.green })
            Divider().vertical(true).height(26).color('#D6D4CC')
            SummaryCell({ label: '增加排放', value: NumUtil.show(this.summary.totalNegativeKg), color: Theme.rust })
            Divider().vertical(true).height(26).color('#D6D4CC')
            SummaryCell({ label: '有效记录', value: `${this.summary.recordCount}`, color: Theme.ink })
          }.width('100%')
        }.width('100%').padding(20).backgroundColor(Theme.sage).borderRadius(Theme.panelRadius).alignItems(HorizontalAlign.Start)
        if (this.summary.gasScopes.length > 1) {
          Row({ space: 10 }) {
            ForEach(this.summary.gasScopes, (scope: string) => {
              Text(scope === 'CO2' ? 'CO₂ 口径' : 'CO₂e 口径').fontSize(12)
                .fontColor(this.scopeKey === scope ? Theme.paper : Theme.green)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 }).borderRadius(18)
                .backgroundColor(this.scopeKey === scope ? Theme.green : Theme.paper)
                .onClick(() => { this.scopeKey = scope; this.selectedKey = ''; this.selectedCategory = ''; this.reload(); })
            }, (scope: string) => scope)
          }.width('100%').margin({ top: 16 })
          Text('两种气体口径分别查看，所有图表随选择同步。').fontSize(11).fontColor(Theme.muted).margin({ top: 10 })
        }
        Row() {
          Text(`${this.from} — ${this.to}`).fontSize(11).fontColor(Theme.muted).layoutWeight(1)
          Text(this.showFilters ? '收起筛选 ↑' : '筛选记录 ↓').fontSize(12).fontColor(Theme.green)
            .padding({ top: 20, bottom: 20 }).onClick(() => { this.showFilters = !this.showFilters; })
        }.width('100%')
        if (this.showFilters) {
          Column({ space: 12 }) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(['all', 'travel', 'water_energy', 'recycling', 'food'], (k: string) => {
                Text(this.catLabel(k)).fontSize(12).fontColor(this.categoryKey === k ? Theme.paper : Theme.muted)
                  .padding({ left: 14, right: 14, top: 12, bottom: 12 }).borderRadius(18)
                  .backgroundColor(this.categoryKey === k ? Theme.green : Theme.bg).margin({ right: 8, bottom: 8 })
                  .onClick(() => { this.categoryKey = k; this.selectedKey = ''; this.selectedCategory = ''; this.reload(); })
              }, (k: string) => k)
            }.width('100%')
            Row({ space: 8 }) {
              TextInput({ text: this.draftFrom }).id('stats-from').fontSize(11).height(46).layoutWeight(1).backgroundColor(Theme.bg)
                .onChange((v: string) => { this.draftFrom = v; })
              Text('至').fontSize(11).fontColor(Theme.muted)
              TextInput({ text: this.draftTo }).id('stats-to').fontSize(11).height(46).layoutWeight(1).backgroundColor(Theme.bg)
                .onChange((v: string) => { this.draftTo = v; })
            }.width('100%')
            if (this.draftFrom !== this.from || this.draftTo !== this.to) {
              Text('日期已修改，点击查看这个区间后更新统计。').fontSize(11).fontColor(Theme.rust).width('100%')
            }
            Button('查看这个区间').height(46).width('100%').fontSize(13).backgroundColor(Theme.green).onClick(() => this.reload(true))
          }.width('100%').padding(16).backgroundColor(Theme.paper).borderRadius(Theme.cardRadius).margin({ bottom: 18 })
        }
        if (this.loading) { Notice({ text: '正在更新统计，下方显示上次查询结果。' }) }
        if (this.message.length > 0) { Notice({ text: this.message, warning: true }) }
        LineChart({ title: '净变化趋势', unit: this.appliedScope === 'CO2e' ? 'kgCO₂e' : 'kgCO₂', data: this.paddedBuckets(), selectedKey: $selectedKey })
        if (this.dimension() !== TimeDimension.DAY && this.recentWithData(3).length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.recentExpanded ? this.recentWithData(0) : this.recentWithData(3), (b: StatBucket) => {
              Text(b.label).fontSize(11)
                .fontColor(this.selectedKey === b.key ? Theme.paper : Theme.green)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .backgroundColor(this.selectedKey === b.key ? Theme.green : Theme.sage)
                .borderRadius(Theme.controlRadius)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => { this.selectedKey = b.key; this.jumpToSelectedRange(); })
            }, (b: StatBucket) => b.key)
            if (this.recentWithData(0).length > 3) {
              Text(this.recentExpanded ? '收起' : `更多 ${this.recentWithData(0).length - 3}`)
                .fontSize(11)
                .fontColor(Theme.muted)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .backgroundColor(Theme.sage)
                .borderRadius(Theme.controlRadius)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => { this.recentExpanded = !this.recentExpanded; })
            }
          }.width('100%').margin({ top: 4 })
        }
        if (this.selectedDetail().length > 0) {
          Row({ space: 8 }) {
            Text('‹').fontSize(18).fontColor(Theme.green).width(32).height(32).textAlign(TextAlign.Center)
              .backgroundColor(Theme.paper).borderRadius(Theme.controlRadius)
              .onClick(() => this.stepSelection(-1))
            Text(this.selectedDetail()).fontSize(11).lineHeight(18).fontColor(Theme.ink).layoutWeight(1)
              .onClick(() => this.jumpToSelectedRange())
            Text('›').fontSize(18).fontColor(Theme.green).width(32).height(32).textAlign(TextAlign.Center)
              .backgroundColor(Theme.paper).borderRadius(Theme.controlRadius)
              .onClick(() => this.stepSelection(1))
          }.width('100%').padding({ left: 10, right: 10, top: 6, bottom: 6 }).backgroundColor(Theme.sage)
            .borderRadius(Theme.controlRadius).margin({ top: 8 })
        } else {
          Text('用 ‹ › 逐格查看；点明细可跳到存折并按当前区间筛选').fontSize(10).fontColor(Theme.muted)
            .width('100%').margin({ top: 8 })
        }
        BarChart({ title: '减排贡献与增加排放', unit: this.appliedScope === 'CO2e' ? 'kgCO₂e' : 'kgCO₂', data: this.paddedBuckets(), selectedKey: $selectedKey }).margin({ top: 12 })
        PieChart({ title: '各类行动的正向贡献', unit: this.appliedScope === 'CO2e' ? 'kgCO₂e' : 'kgCO₂', data: this.summary.categories, selectedCategory: $selectedCategory }).margin({ top: 12 })
        Text('正值为相对基准的减排贡献，负值为增加排放。仅统计已记录的有效行为，不代表完整个人碳足迹。')
          .fontSize(11).lineHeight(20).fontColor(Theme.muted).width('100%').margin({ top: 24, bottom: 30 })
      }.width('100%').padding({ left: 24, right: 24 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Off).backgroundColor(Theme.bg)
  }
}
