import { LedgerOperations } from '../services/LedgerOperations';
import { router } from '@kit.ArkUI';
import { LedgerDb } from '../services/LedgerDb';
import { AppService } from '../services/AppService';
import { RecordService } from '../services/RecordService';
import { PointService } from '../services/PointService';
import { PlanService } from '../services/PlanService';
import { ActionCoachService, ActionRecommendation } from '../services/ActionCoachService';
import { RecordListItem } from '../models/UiModels';
import { BehaviorRecord, CalculationSnapshot, VoucherFactorSource } from '../models/RecordModels';
import { ScenarioResult } from '../models/CalcModels';
import { PlanConstraints, PlanOutcome } from '../models/PlanModels';
import { PointAccountView } from '../models/PointModels';
import { BehaviorCategory, categoryName, gasUnitLabel, RecordStatus, ScenarioRole } from '../common/Domain';
import { Theme, Passbook, Hue, categoryIcon, categoryHue, categoryTint } from '../common/Theme';
import { AppIcon, Notice } from './DesignSystem';
import { Seal, DoubleRule, HeroStat } from './Passbook';
import { DateUtil, NumUtil } from '../common/Format';

/** 账页一行：记录 + 该口径下截至此笔的结余 */
interface LedgerLine {
  item: RecordListItem;
  balance: number;
  counted: boolean;
}

/** 存入单：四类已开放核算的行为入口，提示语写明适用条件 */
interface SlipDef {
  category: string;
  no: string;
  title: string;
  hint: string;
}

const SLIPS: SlipDef[] = [
  { category: 'travel', no: '01', title: '换种出行', hint: '步行骑车，替代驾车' },
  { category: 'water_energy', no: '02', title: '省下的电', hint: '有对照电量的节电' },
  { category: 'recycling', no: '03', title: '废纸再生', hint: '仅限已确认再生利用' },
  { category: 'food', no: '04', title: '少买不浪费', hint: '有采购对照的苹果' }
];

function shortCategory(category: BehaviorCategory): string {
  if (category === BehaviorCategory.TRAVEL) { return '出行'; }
  if (category === BehaviorCategory.WATER_ENERGY) { return '节电'; }
  if (category === BehaviorCategory.RECYCLING) { return '回收'; }
  return '食物';
}

function plainLabel(label: string): string {
  return label.replace(/（[^）]*）/g, '').replace(/\([^)]*\)/g, '').replace(/用电$/, '').trim();
}

/** 账页摘要直接取冻结快照里的情景名，不重新计算、不另造描述 */
function describeSnapshot(snap: CalculationSnapshot, category: BehaviorCategory): string {
  try {
    const scenarios = JSON.parse(snap.scenariosJson) as ScenarioResult[];
    let baseline = '';
    let actual = '';
    for (const s of scenarios) {
      if (s.role === ScenarioRole.ACTUAL) {
        actual = plainLabel(s.scenarioLabel);
      } else if (baseline.length === 0) {
        baseline = plainLabel(s.scenarioLabel);
      }
    }
    if (actual.length > 0 && baseline.length > 0) { return `${actual}替代${baseline}`; }
    if (baseline.length > 0) { return `${shortCategory(category)} · ${baseline}`; }
    return categoryName(category);
  } catch (e) {
    return categoryName(category);
  }
}

/** “核”章只说明计算依据已核对，不代表行为本身经过认证 */
function sourcesVerified(snap: CalculationSnapshot): boolean {
  try {
    const sources = JSON.parse(snap.factorSourcesJson) as VoucherFactorSource[];
    return sources.length > 0 && sources.every((s: VoucherFactorSource) => s.reviewStatus === 'verified');
  } catch (e) {
    return false;
  }
}

function planUnitOf(constraintsJson: string): string {
  try {
    const c = JSON.parse(constraintsJson) as PlanConstraints;
    return c.gasScope === 'CO2e' ? 'kgCO₂e' : (c.gasScope === 'CO2' ? 'kgCO₂' : 'kg');
  } catch (e) {
    return 'kg';
  }
}

/**
 * 存折首页：一本按口径分页的减排存折。
 * 结余 = 逐笔「原本做法排放 − 实际做法排放」之和；数值全部来自冻结快照，页面不重新计算。
 */
@Component
export struct LedgerTab {
  @Prop @Watch('onTick') tick: number = 0;
  @Prop active: boolean = true;
  @Link filterFrom: string;
  @Link filterTo: string;
  @State selectedScope: string = 'kgCO₂';
  @State scopes: string[] = [];
  @State items: RecordListItem[] = [];
  @State visibleCount: number = 50;
  @State points: number = 0;
  @State shortfall: number = 0;
  @State suspended: boolean = false;
  @State testMode: boolean = false;
  @State message: string = '';
  @State todayAction: ActionRecommendation | null = null;
  @State hasPlan: boolean = false;
  @State planUnit: string = 'kg';
  /** 由首页容器切到计划 Tab */
  onOpenPlan: () => void = () => {};

  aboutToAppear(): void {
    this.reload();
  }

  onTick(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    await LedgerOperations.run(() => this.reloadUnlocked());
    // latestPlan 自行排队，不能放进上面的队列内部调用
    await this.loadTodayAction();
  }

  private async reloadUnlocked(): Promise<void> {
    if (!AppService.isReady()) {
      this.message = '数据库尚未就绪，请稍后重试。';
      return;
    }
    const db = LedgerDb.get();
    this.testMode = AppService.repo().isUsingTestData();
    try {
      const records: BehaviorRecord[] = await RecordService.listRecords(db);
      const list: RecordListItem[] = [];
      for (const r of records) {
        const snap: CalculationSnapshot | null = await db.getSnapshot(r.recordId, r.revision);
        if (snap === null) {
          continue;
        }
        list.push({
          record: r,
          reductionKg: snap.reductionKg,
          isNetIncrease: snap.isNetIncrease,
          gasScope: gasUnitLabel(snap.gasScope),
          categoryLabel: categoryName(r.category),
          summary: describeSnapshot(snap, r.category),
          verified: sourcesVerified(snap)
        });
      }
      this.items = list;
      const scopes: string[] = [];
      for (const item of list) {
        if (item.record.status !== RecordStatus.VOIDED && scopes.indexOf(item.gasScope) < 0) { scopes.push(item.gasScope); }
      }
      this.scopes = scopes;
      if (scopes.length > 0 && scopes.indexOf(this.selectedScope) < 0) { this.selectedScope = scopes[0]; }
      const acc: PointAccountView = await PointService.account(db);
      this.points = acc.balance;
      this.shortfall = acc.shortfall;
      this.suspended = acc.redeemSuspended;
      this.message = '';
    } catch (e) {
      this.message = `读取账本失败：${(e as Error).message}`;
    }
  }

  /** 今日一笔：只取已保存七日计划里今天起最近的未完成任务，不自动生成或完成任务 */
  private async loadTodayAction(): Promise<void> {
    if (!AppService.isReady()) {
      return;
    }
    try {
      const latest: PlanOutcome | null = await PlanService.latestPlan(LedgerDb.get());
      if (latest === null || latest.plan === null) {
        this.hasPlan = false;
        this.todayAction = null;
        return;
      }
      this.hasPlan = true;
      this.planUnit = planUnitOf(latest.plan.constraintsJson);
      const picks: ActionRecommendation[] = ActionCoachService.recommend(latest.tasks, DateUtil.today(), 1);
      this.todayAction = picks.length > 0 ? picks[0] : null;
    } catch (e) {
      this.todayAction = null;
    }
  }

  /** 当前口径的账页：按发生顺序累计结余，再按看板传来的区间筛选显示 */
  private ledgerLines(): LedgerLine[] {
    const out: LedgerLine[] = [];
    let running = 0;
    for (let i = this.items.length - 1; i >= 0; i--) {
      const item = this.items[i];
      if (item.gasScope !== this.selectedScope) {
        continue;
      }
      const counted = item.record.status !== RecordStatus.VOIDED;
      if (counted) {
        running += item.reductionKg;
      }
      out.push({ item: item, balance: running, counted: counted });
    }
    out.reverse();
    if (this.filterFrom.length === 0) {
      return out;
    }
    return out.filter((line: LedgerLine) =>
      line.item.record.occurredAt >= this.filterFrom && line.item.record.occurredAt <= this.filterTo);
  }

  private netTotal(): number {
    let total = 0;
    for (const item of this.items) {
      if (item.record.status !== RecordStatus.VOIDED && item.gasScope === this.selectedScope) { total += item.reductionKg; }
    }
    return total;
  }

  private monthNet(): number {
    const month = DateUtil.monthKey(DateUtil.today());
    let total = 0;
    for (const item of this.items) {
      if (item.record.status !== RecordStatus.VOIDED && item.gasScope === this.selectedScope &&
        DateUtil.monthKey(item.record.occurredAt) === month) {
        total += item.reductionKg;
      }
    }
    return total;
  }

  private depositCount(): number {
    return this.items.filter((item: RecordListItem) =>
      item.record.status !== RecordStatus.VOIDED && item.gasScope === this.selectedScope).length;
  }

  private filterLabel(): string {
    if (this.filterFrom === this.filterTo) {
      return `只看 ${this.filterFrom} 的记录`;
    }
    return `只看 ${this.filterFrom} 至 ${this.filterTo} 的记录`;
  }

  /** 当前筛选跨度：day / week / month / year */
  private filterUnit(): string {
    if (this.filterFrom === this.filterTo) {
      return 'day';
    }
    if (this.filterFrom.endsWith('-01-01') && this.filterTo.endsWith('-12-31')) {
      return 'year';
    }
    if (this.filterFrom.endsWith('-01') && this.filterTo.substring(0, 7) === this.filterFrom.substring(0, 7)) {
      return 'month';
    }
    return 'week';
  }

  /** 直接跳到最近一条记录所在的区间，保留当前跨度 */
  private jumpToLatestRecord(): void {
    let latest = '';
    for (const item of this.items) {
      if (item.record.occurredAt > latest) {
        latest = item.record.occurredAt;
      }
    }
    if (latest.length === 0) {
      return;
    }
    const unit = this.filterUnit();
    if (unit === 'year') {
      const year = latest.substring(0, 4);
      this.filterFrom = `${year}-01-01`;
      this.filterTo = `${year}-12-31`;
    } else if (unit === 'month') {
      const key = latest.substring(0, 7);
      this.filterFrom = `${key}-01`;
      this.filterTo = `${key}-${this.lastDay(key)}`;
    } else if (unit === 'week') {
      const weekStart = DateUtil.weekStart(latest);
      this.filterFrom = weekStart;
      this.filterTo = DateUtil.addDays(weekStart, 6);
    } else {
      this.filterFrom = latest;
      this.filterTo = latest;
    }
  }

  /** 按当前筛选跨度移动一天 / 一周 / 一月 / 一年 */
  private shiftFilter(delta: number): void {
    if (this.filterFrom.length === 0) {
      return;
    }
    const from = this.filterFrom;
    const to = this.filterTo;
    if (from === to) {
      this.filterFrom = DateUtil.addDays(from, delta);
      this.filterTo = this.filterFrom;
      return;
    }
    if (from.endsWith('-01-01') && to.endsWith('-12-31')) {
      const year = Number.parseInt(from.substring(0, 4), 10) + delta;
      this.filterFrom = `${year}-01-01`;
      this.filterTo = `${year}-12-31`;
      return;
    }
    if (from.endsWith('-01') && to.substring(0, 7) === from.substring(0, 7)) {
      let year = Number.parseInt(from.substring(0, 4), 10);
      let month = Number.parseInt(from.substring(5, 7), 10) + delta;
      while (month > 12) { month = month - 12; year = year + 1; }
      while (month < 1) { month = month + 12; year = year - 1; }
      const key = `${year}-${month < 10 ? '0' : ''}${month}`;
      this.filterFrom = `${key}-01`;
      this.filterTo = `${key}-${this.lastDay(key)}`;
      return;
    }
    this.filterFrom = DateUtil.addDays(from, delta * 7);
    this.filterTo = DateUtil.addDays(to, delta * 7);
  }

  private lastDay(monthKey: string): string {
    const year = Number.parseInt(monthKey.substring(0, 4), 10);
    const month = Number.parseInt(monthKey.substring(5, 7), 10);
    const days: number[] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    let last = days[month - 1];
    if (month === 2 && (year % 4 === 0 && year % 100 !== 0 || year % 400 === 0)) {
      last = 29;
    }
    return last < 10 ? `0${last}` : `${last}`;
  }

  private openEntry(category: string): void {
    router.pushUrl({ url: 'pages/RecordEntry', params: { category: category } });
  }

  private openAction(action: ActionRecommendation): void {
    router.pushUrl({
      url: action.participationOnly ? 'pages/ParticipationPage' : 'pages/RecordEntry',
      params: { planTaskId: action.planTaskId, category: action.category }
    });
  }

  build() {
    Scroll() {
      Column() {
        this.masthead()
        this.heroNote()
        this.todaySlip()
        this.sectionTitle('存入单', '只记真实发生的')
        this.photoSlip()
        Row({ space: 10 }) {
          this.slip(SLIPS[0])
          this.slip(SLIPS[1])
        }.width('100%')
        Row({ space: 10 }) {
          this.slip(SLIPS[2])
          this.slip(SLIPS[3])
        }.width('100%').margin({ top: 10 })
        if (this.suspended) { Notice({ text: `积分待补足 ${this.shortfall} 分，兑换暂时暂停。`, warning: true }).margin({ top: 16 }) }
        if (this.message.length > 0) { Notice({ text: this.message, warning: true }).margin({ top: 16 }) }
        this.sectionTitle('账页', `${this.selectedScope} · 点任一行看凭证`)
        if (this.filterFrom.length > 0) {
          this.filterBar()
        }
        this.ledgerSheet()
        if (this.testMode) {
          Notice({ text: '开发预览 · 含未核验因子，数值仅供联调，不得用于参赛材料与对外结论。', warning: true }).margin({ top: 20 })
        }
        Row({ space: 8 }) {
          Seal({ label: '核', sealSize: 18, angle: -12 })
          Text('「核」表示这笔的计算因子来源已核对，不代表行为本身经过认证。数量由你申报；结余是估算，不是经核证的碳资产。')
            .fontSize(11).lineHeight(18).fontColor(Passbook.faint).layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Top).margin({ top: 18, bottom: 30 })
      }.width('100%').padding({ left: 20, right: 20 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Off).backgroundColor(Passbook.page)
  }

  @Builder
  masthead() {
    Row() {
      Column({ space: 3 }) {
        Text('No. 0001 · 本机离线账本').fontSize(10).fontFamily(Passbook.numeral).letterSpacing(1).fontColor(Passbook.faint)
        Text('绿碳存折').fontSize(28).fontFamily(Passbook.serif).fontColor(Passbook.print)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Column({ space: 2 }) {
        Text(DateUtil.today().substring(8)).fontSize(30).fontFamily(Passbook.numeral).fontColor(Passbook.print)
        Text(this.monthLabel()).fontSize(10).letterSpacing(1).fontColor(Passbook.faint)
      }.alignItems(HorizontalAlign.End)
    }.width('100%').alignItems(VerticalAlign.Bottom).margin({ top: 14, bottom: 16 })
  }

  private monthLabel(): string {
    const months: string[] = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    const today = DateUtil.today();
    return `${months[Number.parseInt(today.substring(5, 7), 10) - 1]} ${today.substring(0, 4)}`;
  }

  /** 首页卡面：钞券式扭索纹 + 虹彩渐变；结余数字用衬线体，口径切换做成票面上的小面额牌 */
  @Builder
  heroNote() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image($r('app.media.passbook_hero')).width('100%').height('100%').objectFit(ImageFit.Cover)
        .draggable(false).accessibilityLevel('no')
      Column() {
        Row() {
          Text('本折结余').fontSize(12).letterSpacing(2).fontColor('#3A3F4A')
          Blank()
          if (this.scopes.length > 1) {
            Row({ space: 2 }) {
              ForEach(this.scopes, (scope: string) => {
                Text(scope).fontSize(11).fontFamily(Passbook.numeral)
                  .fontColor(this.selectedScope === scope ? '#FFFFFF' : Passbook.print)
                  .backgroundColor(this.selectedScope === scope ? Passbook.print : Color.Transparent)
                  .borderRadius(12).padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .accessibilityText(`切换到 ${scope} 账页`)
                  .onClick(() => { this.selectedScope = scope; })
              }, (scope: string) => scope)
            }.padding(2).backgroundColor('#99FFFFFF').borderRadius(14)
          } else {
            Text(this.selectedScope).fontSize(11).fontFamily(Passbook.numeral).fontColor('#3A3F4A')
          }
        }.width('100%')
        Row({ space: 6 }) {
          Text(NumUtil.show(this.netTotal())).fontSize(68).fontFamily(Passbook.numeral)
            .fontColor(Passbook.print).maxLines(1).minFontSize(34).maxFontSize(68)
            .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).flexShrink(1)
          Text(this.selectedScope).fontSize(14).fontFamily(Passbook.numeral).fontColor('#3A3F4A')
            .margin({ bottom: 14 }).flexShrink(0)
        }.width('100%').alignItems(VerticalAlign.Bottom).margin({ top: 6 })
        Text('每一笔 ＝ 原本做法的排放 − 这次实际的排放').fontSize(11).fontColor('#4A505C').width('100%')
        Blank()
        Row() {
          HeroStat({ label: '存入', value: `${this.depositCount()}`, unit: '笔' }).layoutWeight(1)
          Row().width(0.5).height(30).backgroundColor('#5916181D')
          HeroStat({ label: '本月', value: NumUtil.signed(this.monthNet(), 2) }).layoutWeight(1)
          Row().width(0.5).height(30).backgroundColor('#5916181D')
          HeroStat({ label: '积分', value: `${this.points}`, unit: '分' }).layoutWeight(1)
        }.width('100%').padding({ top: 12, bottom: 12 }).backgroundColor('#8CFFFFFF').borderRadius(14)
      }.width('100%').height('100%').padding({ left: 20, right: 20, top: 18, bottom: 16 })
    }
    .width('100%').height(272).borderRadius(24).clip(true)
    .border({ width: 0.5, color: '#1F16181D' })
    .shadow({ radius: 28, color: '#1A3B4A78', offsetY: 12 })
    .accessibilityGroup(true)
    .accessibilityText(`本折结余 ${NumUtil.show(this.netTotal())} ${this.selectedScope}，存入 ${this.depositCount()} 笔，可用积分 ${this.points}`)
  }

  @Builder
  todaySlip() {
    Row({ space: 14 }) {
      Column({ space: 0 }) {
        Text('TODAY').fontSize(8).letterSpacing(1.5).fontColor('#A9B0BC')
        Text(DateUtil.today().substring(8)).fontSize(26).fontFamily(Passbook.numeral).fontColor('#FFFFFF')
      }.width(56).height(56).justifyContent(FlexAlign.Center).backgroundColor(Passbook.print).borderRadius(16)
      Column({ space: 3 }) {
        if (this.todayAction !== null) {
          Row({ space: 6 }) {
            Circle().width(6).height(6).fill(categoryHue(this.todayAction!.category))
            Text(`${this.todayAction!.isToday ? '今天' : this.todayAction!.day.substring(5)} · 七日计划`)
              .fontSize(10).fontColor(Passbook.faint)
          }
          Text(this.todayAction!.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Passbook.print)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.todayAction!.participationOnly ? '参与任务 · 只记参与，不计 kg'
            : `预计 ${NumUtil.show(this.todayAction!.expectedKg)} ${this.planUnit} · 额外 ${this.todayAction!.extraMinutes} 分钟`)
            .fontSize(11).fontColor(Passbook.faint).maxLines(1)
        } else if (this.hasPlan) {
          Text('七日计划').fontSize(10).fontColor(Passbook.faint)
          Text('近七天的任务都处理完了').fontSize(15).fontWeight(FontWeight.Medium).fontColor(Passbook.print)
          Text('想多做一点，可以重新排一周').fontSize(11).fontColor(Passbook.faint)
        } else {
          Text('七日计划').fontSize(10).fontColor(Passbook.faint)
          Text('还没有这一周的安排').fontSize(15).fontWeight(FontWeight.Medium).fontColor(Passbook.print)
          Text('按你的时间、费用和出行习惯排七天').fontSize(11).fontColor(Passbook.faint)
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Stack() {
        AppIcon({ name: 'arrow', iconSize: 16, color: Passbook.print })
      }.width(32).height(32).borderRadius(16).backgroundColor(Passbook.wash)
    }
    .width('100%').padding(12).margin({ top: 14 })
    .backgroundColor(Passbook.sheet).border({ width: 1, color: Passbook.rule }).borderRadius(20)
    .accessibilityGroup(true)
    .accessibilityText(this.todayAction !== null ? `今日一笔：${this.todayAction!.title}` : '打开七日计划')
    .onClick(() => {
      if (this.todayAction !== null) {
        this.openAction(this.todayAction!);
      } else {
        this.onOpenPlan();
      }
    })
  }

  @Builder
  sectionTitle(title: string, detail: string) {
    Row() {
      Text(title).fontSize(19).fontFamily(Passbook.serif).fontColor(Passbook.print).layoutWeight(1)
      Text(detail).fontSize(11).fontColor(Passbook.faint)
    }.width('100%').alignItems(VerticalAlign.Bottom).margin({ top: 28, bottom: 12 })
  }

  /** 拍照记一笔入口：端侧识别只建议填哪张存入单，不自动入账 */
  @Builder
  photoSlip() {
    Row({ space: 14 }) {
      Stack() {
        Circle().width(44).height(44).fill(Passbook.print)
        Row({ space: 3 }) {
          Circle().width(5).height(5).fill(Hue.travel)
          Circle().width(5).height(5).fill(Hue.energy)
          Circle().width(5).height(5).fill(Hue.recycle)
          Circle().width(5).height(5).fill(Hue.food)
        }
      }
      Column({ space: 3 }) {
        Text('拍照记一笔').fontSize(16).fontFamily(Passbook.serif).fontColor(Passbook.print)
        Text('端侧 AI 认出画面，建议填哪张存入单 · 照片不上传').fontSize(11).fontColor(Passbook.faint).maxLines(1)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Stack() {
        AppIcon({ name: 'arrow', iconSize: 16, color: Passbook.print })
      }.width(32).height(32).borderRadius(16).backgroundColor(Passbook.wash)
    }
    .width('100%').padding(12).margin({ bottom: 10 })
    .backgroundColor(Passbook.sheet).border({ width: 1, color: Passbook.rule }).borderRadius(20)
    .accessibilityGroup(true).accessibilityText('拍照记一笔：端侧识别照片，建议填写哪张存入单')
    .onClick(() => router.pushUrl({ url: 'pages/PhotoAssistPage' }))
  }

  /** 存入单：左侧票根色带 + 打孔线，颜色即类别 */
  @Builder
  slip(def: SlipDef) {
    Row() {
      Column() {
        Text(def.no).fontSize(13).fontFamily(Passbook.numeral).fontColor('#FFFFFF')
      }.width(28).height('100%').justifyContent(FlexAlign.Start).padding({ top: 14 })
      .backgroundColor(categoryHue(def.category))
      Column() {
        Row() {
          Stack() {
            AppIcon({ name: categoryIcon(def.category), iconSize: 18, color: 'hue' })
          }.width(32).height(32).borderRadius(10).backgroundColor(categoryTint(def.category))
          Blank()
          Text('存入单').fontSize(9).letterSpacing(1).fontColor(Passbook.faint)
        }.width('100%')
        Text(def.title).fontSize(16).fontFamily(Passbook.serif).fontColor(Passbook.print).margin({ top: 12 })
        Text(def.hint).fontSize(11).lineHeight(16).fontColor(Passbook.faint).maxLines(2).margin({ top: 3 })
      }.layoutWeight(1).height('100%').alignItems(HorizontalAlign.Start).padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .border({ width: { left: 1 }, color: '#33FFFFFF', style: BorderStyle.Dashed })
    }
    .layoutWeight(1).height(116)
    .backgroundColor(Passbook.sheet).border({ width: 1, color: Passbook.rule }).borderRadius(18).clip(true)
    .accessibilityGroup(true).accessibilityText(`填写存入单：${def.title}，${def.hint}`)
    .onClick(() => this.openEntry(def.category))
  }

  @Builder
  filterBar() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text('‹').fontSize(16).fontColor(Passbook.print).width(28).height(28).textAlign(TextAlign.Center)
          .onClick(() => this.shiftFilter(-1))
        Text(this.filterLabel()).fontSize(12).fontColor(Passbook.print).layoutWeight(1).maxLines(2)
        Text('›').fontSize(16).fontColor(Passbook.print).width(28).height(28).textAlign(TextAlign.Center)
          .onClick(() => this.shiftFilter(1))
      }.width('100%')
      Row() {
        Text('最近记录').fontSize(11).fontColor(Passbook.print)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(Passbook.page).borderRadius(14)
          .onClick(() => this.jumpToLatestRecord())
        Blank()
        Text('显示全部 ×').fontSize(11).fontColor(Passbook.print)
          .padding({ left: 6, right: 6, top: 6, bottom: 6 })
          .onClick(() => { this.filterFrom = ''; this.filterTo = ''; })
      }.width('100%')
      Text('结余仍按全部有效记录累计；这里只筛选显示的行。').fontSize(10).fontColor(Passbook.faint).width('100%')
    }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 }).margin({ bottom: 10 })
    .backgroundColor(Passbook.wash).borderRadius(16)
  }

  @Builder
  ledgerSheet() {
    Column() {
      Row() {
        Text('日期').fontSize(10).fontColor(Passbook.faint).width(58)
        Text('摘要').fontSize(10).fontColor(Passbook.faint).layoutWeight(1)
        Text('存入').fontSize(10).fontColor(Passbook.faint).width(64).textAlign(TextAlign.End)
        Text('结余').fontSize(10).fontColor(Passbook.faint).width(46).textAlign(TextAlign.End)
        Text('').width(32)
      }.width('100%').padding({ left: 16, right: 10 })
      DoubleRule({ color: Passbook.ruleStrong }).margin({ top: 8 }).padding({ left: 16, right: 16 })
      if (this.items.length === 0) {
        Text('账页还是空的。从上面任意一张存入单，记下第一笔。').fontSize(12).lineHeight(20).fontColor(Passbook.faint)
          .width('100%').padding({ top: 24, bottom: 24 }).textAlign(TextAlign.Center)
      } else if (this.ledgerLines().length === 0) {
        Text('这段时间在本账页没有记录。可以用 ‹ › 换区间，或显示全部。').fontSize(12).lineHeight(20).fontColor(Passbook.faint)
          .width('100%').padding({ top: 24, bottom: 24 }).textAlign(TextAlign.Center)
      } else {
        ForEach(this.ledgerLines().slice(0, this.visibleCount), (line: LedgerLine, index: number) => {
          this.ledgerRow(line, index === 0)
        }, (line: LedgerLine) => `${line.item.record.recordId}#${line.item.record.revision}#${line.item.record.status}`)
      }
      if (this.filterFrom.length === 0 && this.ledgerLines().length > this.visibleCount) {
        Text(`继续翻页 · 已显示 ${this.visibleCount} / ${this.ledgerLines().length} 笔`).fontSize(12).fontColor(Passbook.print)
          .width('100%').textAlign(TextAlign.Center).padding({ top: 14, bottom: 6 })
          .onClick(() => { this.visibleCount += 50; })
      }
    }
    .width('100%').padding({ top: 14, bottom: 4 })
    .backgroundColor(Passbook.sheet).border({ width: 1, color: Passbook.rule }).borderRadius(22).clip(true)
  }

  @Builder
  ledgerRow(line: LedgerLine, newest: boolean) {
    Column() {
      Row() {
        Row() {
          Row().width(3).height(30).borderRadius(2)
            .backgroundColor(line.counted ? categoryHue(line.item.record.category) : Passbook.ruleStrong)
        }.width(16).justifyContent(FlexAlign.Start)
        Text(line.item.record.occurredAt.substring(5).replace('-', '.')).fontSize(14).fontFamily(Passbook.numeral)
          .fontColor(Passbook.print).width(42)
        Column({ space: 2 }) {
          Text(line.item.summary).fontSize(13).fontColor(line.counted ? Passbook.print : Passbook.faint)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${line.item.record.quantity} ${line.item.record.unit} · 第 ${line.item.record.revision} 版`)
            .fontSize(10).fontColor(Passbook.faint).maxLines(1)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start).padding({ right: 4 })
        Text(NumUtil.signed(line.item.reductionKg, 2)).fontSize(15).fontFamily(Passbook.numeral)
          .fontColor(!line.counted ? Passbook.faint : (line.item.isNetIncrease ? Theme.rust : Passbook.print))
          .decoration({ type: line.counted ? TextDecorationType.None : TextDecorationType.LineThrough, color: Passbook.faint })
          .width(64).textAlign(TextAlign.End).maxLines(1).minFontSize(9).maxFontSize(15)
          .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
        Text(line.counted ? NumUtil.show(line.balance) : '—').fontSize(12).fontFamily(Passbook.numeral)
          .fontColor(Passbook.faint).width(46).textAlign(TextAlign.End).maxLines(1).minFontSize(8).maxFontSize(12)
          .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
        Stack() {
          if (!line.counted) {
            Seal({ label: '撤', sealSize: 22, angle: 8, color: Passbook.faint })
          } else if (line.item.verified) {
            Seal({ label: '核', sealSize: 22, stampIn: newest })
          }
        }.width(32).height(26)
      }.width('100%').padding({ left: 0, right: 10, top: 12, bottom: 12 })
      Row().width('100%').height(0.5).backgroundColor(Passbook.rule).margin({ left: 16 })
    }
    .width('100%')
    .accessibilityGroup(true)
    .accessibilityText(`${line.item.record.occurredAt}，${line.item.summary}，${line.counted ? '' : '已撤销，'}${NumUtil.signed(line.item.reductionKg, 2)} ${line.item.gasScope}，点击查看凭证`)
    .onClick(() => {
      router.pushUrl({ url: 'pages/VoucherPage', params: { recordId: line.item.record.recordId, revision: line.item.record.revision } });
    })
  }
}
