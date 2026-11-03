import { LedgerOperations } from '../services/LedgerOperations';
import { router } from '@kit.ArkUI';
import { LedgerDb } from '../services/LedgerDb';
import { AppService } from '../services/AppService';
import { RecordService } from '../services/RecordService';
import { PointService } from '../services/PointService';
import { RecordListItem } from '../models/UiModels';
import { BehaviorRecord, CalculationSnapshot } from '../models/RecordModels';
import { PointAccountView } from '../models/PointModels';
import { categoryName, gasUnitLabel, RecordStatus } from '../common/Domain';
import { Theme, categoryIcon } from '../common/Theme';
import { AppIcon, PageIntro, SectionHeading, Notice, EmptyState, BreathingPlant } from './DesignSystem';
import { DateUtil, NumUtil } from '../common/Format';

/**
 * 存折 Tab（第 3.2 节主链路）：积分余额、已记录行为列表、记一笔入口。
 * 数值与口径来自快照，页面不重新计算。
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
  @State balance: number = 0;
  @State earned: number = 0;
  @State spent: number = 0;
  @State shortfall: number = 0;
  @State suspended: boolean = false;
  @State testMode: boolean = false;
  @State message: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  onTick(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    return LedgerOperations.run(() => this.reloadUnlocked());
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
          categoryLabel: categoryName(r.category)
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
      this.balance = acc.balance;
      this.earned = acc.earned;
      this.spent = acc.spent;
      this.shortfall = acc.shortfall;
      this.suspended = acc.redeemSuspended;
      this.message = '';
    } catch (e) {
      this.message = `读取账本失败：${(e as Error).message}`;
    }
  }

  /** 按日期区间筛选后的记录（不改累计与积分，仅影响列表展示） */
  private visibleItems(): RecordListItem[] {
    if (this.filterFrom.length === 0) {
      return this.items;
    }
    return this.items.filter((item: RecordListItem) =>
      item.record.occurredAt >= this.filterFrom && item.record.occurredAt <= this.filterTo);
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

  private netTotal(): number {
    let total = 0;
    for (const item of this.items) {
      if (item.record.status !== RecordStatus.VOIDED && item.gasScope === this.selectedScope) { total += item.reductionKg; }
    }
    return total;
  }
  private validCount(): number {
    return this.items.filter((item: RecordListItem) => item.record.status !== RecordStatus.VOIDED).length;
  }
  private openEntry(category: string): void {
    router.pushUrl({ url: 'pages/RecordEntry', params: { category: category } });
  }
  build() {
    Scroll() {
      Column() {
        Row() {
          Column({ space: 6 }) {
            Text('绿碳存折').fontSize(12).fontColor(Theme.muted)
            Text('校园低碳行动账本').fontSize(25).lineHeight(36).fontWeight(FontWeight.Medium).fontColor(Theme.ink)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          AppIcon({ name: 'leaf', iconSize: 28, color: '#8B9E79' })
        }.width('100%').margin({ top: 18, bottom: 26 })
        Stack({ alignContent: Alignment.End }) {
          BreathingPlant({ active: this.active }).margin({ right: 6 })
            .opacity(this.getUIContext().fp2px(1) > this.getUIContext().vp2px(1) * 1.2 ? 0.16 : 1)
          Column({ space: 9 }) {
            Text('每笔记录\n都留有依据').fontSize(25).lineHeight(36)
              .fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
            Text('累计记录 · 相对基准情景的净变化').fontSize(12).fontColor('#BFCEC1').margin({ top: 12 })
            Row({ space: 6 }) {
              Text(NumUtil.show(this.netTotal())).fontSize(37).fontWeight(FontWeight.Medium).fontColor(Theme.lime)
                .fontFeature('"tnum" on')
                .maxLines(1).minFontSize(20).maxFontSize(37).heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).flexShrink(1).constraintSize({ maxWidth: '80%' })
              Text(this.selectedScope).fontSize(11).fontColor('#BFCEC1').margin({ top: 17 }).flexShrink(0)
            }.width('100%')
            if (this.scopes.length > 1) {
              Row({ space: 10 }) {
                ForEach(this.scopes, (scope: string) => {
                  Text(scope).fontSize(11).fontColor(this.selectedScope === scope ? Theme.lime : '#BFCEC1')
                    .padding({ top: 6, bottom: 6 }).onClick(() => { this.selectedScope = scope; })
                }, (scope: string) => scope)
              }
            }
          }.width('100%').alignItems(HorizontalAlign.Start).padding(24)
        }.width('100%').backgroundColor(Theme.green).borderRadius(Theme.heroRadius).clip(true)
        Row() {
          Column({ space: 6 }) {
            Text(`${this.validCount()} 件`).fontSize(22).fontWeight(FontWeight.Medium).fontColor(Theme.ink).width('100%').maxLines(1)
            Text('已记录的绿色行动').fontSize(11).fontColor(Theme.muted).width('100%').maxLines(2).lineHeight(18)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Column({ space: 6 }) {
            Text(`${this.balance} 分`).fontSize(22).fontWeight(FontWeight.Medium).fontColor(Theme.ink).width('100%').maxLines(1)
            Text('我的可用积分').fontSize(11).fontColor(Theme.muted).width('100%').maxLines(2).lineHeight(18)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button({ type: ButtonType.Normal }) { AppIcon({ name: 'plus', iconSize: 24, color: Theme.paper }) }
            .width(48).height(48).borderRadius(24).backgroundColor(Theme.green)
            .accessibilityText('记一笔绿色行动').onClick(() => this.openEntry(''))
        }.width('100%').padding({ left: 6, right: 6, top: 24, bottom: 4 })
        SectionHeading({ title: '记录一项行动' })
        Row({ space: 10 }) {
          this.categoryTile('travel', '绿色出行', '换种方式')
          this.categoryTile('water_energy', '节约能源', '少一点消耗')
        }.width('100%')
        Row({ space: 10 }) {
          this.categoryTile('recycling', '旧物再生', '仅限实际再生利用')
          this.categoryTile('food', '减少食物采购', '需要真实采购对照')
        }.width('100%').margin({ top: 10 })
        if (this.filterFrom.length > 0) {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('‹').fontSize(16).fontColor(Theme.green).width(28).height(28).textAlign(TextAlign.Center)
                .onClick(() => this.shiftFilter(-1))
              Text(this.filterLabel()).fontSize(12).fontColor(Theme.ink).layoutWeight(1).maxLines(2)
              Text('›').fontSize(16).fontColor(Theme.green).width(28).height(28).textAlign(TextAlign.Center)
                .onClick(() => this.shiftFilter(1))
            }.width('100%')
            Row() {
              Text('最近记录').fontSize(11).fontColor(Theme.green)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .backgroundColor(Theme.paper).borderRadius(Theme.controlRadius)
                .onClick(() => this.jumpToLatestRecord())
              Blank()
              Text('显示全部 ×').fontSize(11).fontColor(Theme.green)
                .padding({ left: 6, right: 6, top: 6, bottom: 6 })
                .onClick(() => { this.filterFrom = ''; this.filterTo = ''; })
            }.width('100%')
          }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .backgroundColor(Theme.sage).borderRadius(Theme.controlRadius)
          Text('上方累计数字与积分仍为全部有效记录；此处只筛列表。').fontSize(10).fontColor(Theme.muted).width('100%')
        }
        if (this.suspended) { Notice({ text: `积分待补足 ${this.shortfall} 分，兑换暂时暂停。`, warning: true }).margin({ top: 16 }) }
        SectionHeading({ title: '最近记录', detail: '点击查看凭证' })
        if (this.message.length > 0) { Notice({ text: this.message, warning: true }) }
        if (this.items.length === 0) {
          EmptyState({ title: '还没有记录', detail: '记下一次真实行动，查看估算结果和对应依据。' })
        } else if (this.visibleItems().length === 0) {
          EmptyState({ title: '这段时间没有记录', detail: '可以用 ‹ › 换区间，或点「显示全部 ×」回到完整列表。' })
        } else {
          ForEach(this.visibleItems().slice(0, this.visibleCount), (item: RecordListItem) => { this.recordCard(item); },
            (item: RecordListItem) => `${item.record.recordId}#${item.record.revision}#${item.record.status}`)
        }
        if (this.filterFrom.length === 0 && this.items.length > this.visibleCount) {
          Button(`继续查看 · 已显示 ${Math.min(this.visibleCount, this.items.length)} / ${this.items.length} 条`).fontSize(12).height(46).width('100%')
            .fontColor(Theme.green).backgroundColor(Theme.sage).onClick(() => { this.visibleCount += 50; })
        }
        if (this.testMode) {
          Notice({ text: '开发预览 · 含未核验因子，数值仅供联调，不得用于参赛材料与对外结论。', warning: true }).margin({ top: 20 })
        }
        Text('小步改变，也值得认真记下。').fontSize(11).fontColor(Theme.muted).margin({ top: 28, bottom: 24 })
      }.width('100%').padding({ left: 24, right: 24 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Off).backgroundColor(Theme.bg)
  }
  @Builder
  categoryTile(category: string, title: string, subtitle: string) {
    Row({ space: 10 }) {
      AppIcon({ name: categoryIcon(category), iconSize: 24 })
      Column({ space: 5 }) {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(Theme.ink).width('100%').maxLines(2)
        Text(subtitle).fontSize(11).lineHeight(16).fontColor(Theme.muted).width('100%').maxLines(2)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }.layoutWeight(1).constraintSize({ minHeight: 86 }).padding(16).backgroundColor(Theme.paper)
      .border({ width: 1, color: Theme.line })
      .borderRadius(Theme.cardRadius)
      .onClick(() => this.openEntry(category))
  }
  @Builder
  recordCard(item: RecordListItem) {
    Row({ space: 13 }) {
      Stack() { AppIcon({ name: categoryIcon(item.record.category), iconSize: 22 }) }
        .width(44).height(44).borderRadius(Theme.controlRadius).backgroundColor(Theme.sage)
      Column({ space: 7 }) {
        Text(`${item.categoryLabel} · ${item.record.quantity} ${item.record.unit}`)
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(Theme.ink)
        Text(`${item.record.occurredAt.substring(5, 10)}  ·  ${item.record.status === RecordStatus.VOIDED ? '已撤销' : '可追溯凭证'}  ·  v${item.record.revision}`)
          .fontSize(11).fontColor(Theme.muted)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Column({ space: 6 }) {
        Text(NumUtil.signed(item.reductionKg, 2)).fontSize(18).fontWeight(FontWeight.Medium).fontFeature('"tnum" on')
          .fontColor(item.record.status === RecordStatus.VOIDED ? Theme.muted : (item.isNetIncrease ? Theme.rust : Theme.green))
        Text(item.gasScope).fontSize(11).fontColor(Theme.muted)
      }.alignItems(HorizontalAlign.End)
    }.width('100%').padding(16).backgroundColor(Theme.paper).borderRadius(Theme.cardRadius).margin({ bottom: 10 })
      .opacity(item.record.status === RecordStatus.VOIDED ? 0.55 : 1)
      .onClick(() => { router.pushUrl({ url: 'pages/VoucherPage', params: { recordId: item.record.recordId, revision: item.record.revision } }); })
  }
}
