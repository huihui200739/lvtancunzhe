import { LedgerOperations } from '../services/LedgerOperations';
import { Theme } from '../common/Theme';
import { AppIcon, PageIntro, SectionHeading, Notice, EmptyState, SubpageHeader } from '../components/DesignSystem';
import { LedgerDb } from '../services/LedgerDb';
import { AppService } from '../services/AppService';
import { StatsService } from '../services/StatsService';
import { LineChart } from './LineChart';
import { BarChart } from './BarChart';
import { PieChart } from './PieChart';
import { StatsSummary } from '../models/StatsModels';
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
      Text(this.value).fontSize(22).fontColor(this.color).fontWeight(FontWeight.Bold)
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
  private reloadVersion: number = 0;
  @State summary: StatsSummary = emptySummary();
  @State message: string = '';

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
      this.scopeKey = summary.gasScopes.indexOf(scope) >= 0 ? scope : (summary.gasScopes.length > 0 ? summary.gasScopes[0] : scope);
      this.appliedScope = this.scopeKey;
    } catch (e) {
      if (version === this.reloadVersion) { this.message = `统计失败，下方保留上次查询结果：${(e as Error).message}`; }
    } finally {
      if (version === this.reloadVersion) { this.loading = false; }
    }
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
        PageIntro({ title: '看见，每一点改变', subtitle: '让记录连成轨迹，也让进步有据可循。', eyebrow: '我的绿色轨迹 / INSIGHTS' })
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
            Text('这段时间的净减排').fontSize(13).fontColor(Theme.muted).layoutWeight(1)
            Text(this.appliedScope === 'CO2e' ? 'kgCO₂e' : 'kgCO₂').fontSize(11).fontColor(Theme.green)
          }.width('100%')
          Text(`${this.from} — ${this.to} · ${this.appliedLabel}`).fontSize(11).fontColor(Theme.muted).width('100%')
          Text(NumUtil.signed(this.summary.totalNetKg, 2)).fontSize(46).fontWeight(FontWeight.Medium).fontColor(Theme.green).maxLines(1).minFontSize(24).maxFontSize(46).heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).width('100%')
          Row() {
            SummaryCell({ label: '正向贡献', value: NumUtil.show(this.summary.totalPositiveKg), color: Theme.green })
            SummaryCell({ label: '增加排放', value: NumUtil.show(this.summary.totalNegativeKg), color: Theme.rust })
            SummaryCell({ label: '有效记录', value: `${this.summary.recordCount}`, color: Theme.ink })
          }.width('100%')
        }.width('100%').padding(24).backgroundColor(Theme.sage).borderRadius(28).alignItems(HorizontalAlign.Start)
        if (this.summary.gasScopes.length > 1) {
          Row({ space: 10 }) {
            ForEach(this.summary.gasScopes, (scope: string) => {
              Text(scope === 'CO2' ? 'CO₂ 口径' : 'CO₂e 口径').fontSize(12)
                .fontColor(this.scopeKey === scope ? Theme.paper : Theme.green)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 }).borderRadius(18)
                .backgroundColor(this.scopeKey === scope ? Theme.green : Theme.paper)
                .onClick(() => { this.scopeKey = scope; this.reload(); })
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
                  .onClick(() => { this.categoryKey = k; this.reload(); })
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
          }.width('100%').padding(18).backgroundColor(Theme.paper).borderRadius(22).margin({ bottom: 18 })
        }
        if (this.loading) { Notice({ text: '正在更新统计，下方显示上次查询结果。' }) }
        if (this.message.length > 0) { Notice({ text: this.message, warning: true }) }
        LineChart({ title: '01  净变化趋势', data: this.summary.buckets })
        BarChart({ title: '02  贡献与增加排放', data: this.summary.buckets }).margin({ top: 16 })
        PieChart({ title: '03  行动贡献分布', data: this.summary.categories }).margin({ top: 16 })
        Text('正值为相对基准的减排贡献，负值为增加排放。仅统计已记录的有效行为，不代表完整个人碳足迹。')
          .fontSize(11).lineHeight(20).fontColor(Theme.muted).width('100%').margin({ top: 24, bottom: 30 })
      }.width('100%').padding({ left: 22, right: 22 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Off).backgroundColor(Theme.bg)
  }
}
