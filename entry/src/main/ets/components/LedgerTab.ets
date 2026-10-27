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
import { Theme, categoryIcon, categoryTint } from '../common/Theme';
import { AppIcon, PageIntro, SectionHeading, Notice, EmptyState, BreathingPlant } from './DesignSystem';
import { NumUtil } from '../common/Format';

/**
 * 存折 Tab（第 3.2 节主链路）：积分余额、已记录行为列表、记一笔入口。
 * 数值与口径来自快照，页面不重新计算。
 */
@Component
export struct LedgerTab {
  @Prop @Watch('onTick') tick: number = 0;
  @Prop active: boolean = true;
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
            Text('绿碳存折').fontSize(11).letterSpacing(3).fontColor(Theme.muted)
            Text('让日常，慢慢变绿').fontSize(25).fontWeight(FontWeight.Medium).fontColor(Theme.ink)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          AppIcon({ name: 'leaf', iconSize: 28, color: '#8B9E79' })
        }.width('100%').margin({ top: 18, bottom: 26 })
        Stack({ alignContent: Alignment.End }) {
          BreathingPlant({ active: this.active }).margin({ right: 6 })
            .opacity(this.getUIContext().fp2px(1) > this.getUIContext().vp2px(1) * 1.2 ? 0.16 : 1)
          Column({ space: 9 }) {
            Text('每一件小事\n都在悄悄生长。').fontSize(25).lineHeight(36)
              .fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
            Text('累计记录 · 相对基准情景的净减排').fontSize(10).fontColor('#BFCEC1').margin({ top: 14 })
            Row({ space: 6 }) {
              Text(NumUtil.show(this.netTotal())).fontSize(37).fontWeight(FontWeight.Medium).fontColor(Theme.lime)
                .maxLines(1).minFontSize(20).maxFontSize(37).heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).flexShrink(1).constraintSize({ maxWidth: '80%' })
              Text(this.selectedScope).fontSize(11).fontColor('#BFCEC1').margin({ top: 17 }).flexShrink(0)
            }.width('100%')
            if (this.scopes.length > 1) {
              Row({ space: 10 }) {
                ForEach(this.scopes, (scope: string) => {
                  Text(scope).fontSize(10).fontColor(this.selectedScope === scope ? Theme.lime : '#BFCEC1')
                    .padding({ top: 6, bottom: 6 }).onClick(() => { this.selectedScope = scope; })
                }, (scope: string) => scope)
              }
            }
          }.width('100%').alignItems(HorizontalAlign.Start).padding(24)
        }.width('100%').backgroundColor(Theme.green).borderRadius(28).clip(true)
        Row() {
          Column({ space: 6 }) {
            Text(`${this.validCount()} 件`).fontSize(20).fontWeight(FontWeight.Medium).fontColor(Theme.ink)
            Text('已记录的绿色行动').fontSize(11).fontColor(Theme.muted)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Column({ space: 6 }) {
            Text(`${this.balance} 分`).fontSize(20).fontWeight(FontWeight.Medium).fontColor(Theme.ink)
            Text('我的可用积分').fontSize(11).fontColor(Theme.muted)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button({ type: ButtonType.Normal }) { AppIcon({ name: 'plus', iconSize: 24, color: Theme.paper }) }
            .width(48).height(48).borderRadius(24).backgroundColor(Theme.green)
            .accessibilityText('记一笔绿色行动').onClick(() => this.openEntry(''))
        }.width('100%').padding({ left: 6, right: 6, top: 24, bottom: 4 })
        SectionHeading({ title: '今天，从这件小事开始', detail: '记一笔' })
        Row({ space: 10 }) {
          this.categoryTile('travel', '绿色出行', '换种方式')
          this.categoryTile('water_energy', '节约能源', '少一点消耗')
        }.width('100%')
        Row({ space: 10 }) {
          this.categoryTile('recycling', '旧物新生', '让资源循环')
          this.categoryTile('food', '好好吃饭', '珍惜每一口')
        }.width('100%').margin({ top: 10 })
        if (this.suspended) { Notice({ text: `积分待补足 ${this.shortfall} 分，兑换暂时暂停。`, warning: true }).margin({ top: 16 }) }
        SectionHeading({ title: '行动留下的足迹', detail: '点击查看凭证' })
        if (this.message.length > 0) { Notice({ text: this.message, warning: true }) }
        if (this.items.length === 0) {
          EmptyState({ title: '第一片绿，等你种下', detail: '记录一次节约、一次替代。\n每笔行动都有自己的计算依据。' })
        } else {
          ForEach(this.items.slice(0, this.visibleCount), (item: RecordListItem) => { this.recordCard(item); },
            (item: RecordListItem) => `${item.record.recordId}#${item.record.revision}#${item.record.status}`)
        }
        if (this.items.length > this.visibleCount) {
          Button(`继续查看 · 已显示 ${Math.min(this.visibleCount, this.items.length)} / ${this.items.length} 条`).fontSize(12).height(46).width('100%')
            .fontColor(Theme.green).backgroundColor(Theme.sage).onClick(() => { this.visibleCount += 50; })
        }
        if (this.testMode) {
          Notice({ text: '开发预览 · 含未核验因子，数值仅供联调，不得用于参赛材料与对外结论。', warning: true }).margin({ top: 20 })
        }
        Text('小步改变，也值得认真记下。').fontSize(11).fontColor(Theme.muted).margin({ top: 28, bottom: 24 })
      }.width('100%').padding({ left: 22, right: 22 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Off).backgroundColor(Theme.bg)
  }
  @Builder
  categoryTile(category: string, title: string, subtitle: string) {
    Row({ space: 10 }) {
      AppIcon({ name: categoryIcon(category), iconSize: 24 })
      Column({ space: 5 }) {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(Theme.ink)
        Text(subtitle).fontSize(10).fontColor(Theme.muted)
      }.alignItems(HorizontalAlign.Start)
    }.layoutWeight(1).height(86).padding(16).backgroundColor(categoryTint(category)).borderRadius(20)
      .onClick(() => this.openEntry(category))
  }
  @Builder
  recordCard(item: RecordListItem) {
    Row({ space: 13 }) {
      Stack() { AppIcon({ name: categoryIcon(item.record.category), iconSize: 22 }) }
        .width(44).height(44).borderRadius(16).backgroundColor(categoryTint(item.record.category))
      Column({ space: 7 }) {
        Text(`${item.categoryLabel} · ${item.record.quantity} ${item.record.unit}`)
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(Theme.ink)
        Text(`${item.record.occurredAt.substring(5, 10)}  ·  ${item.record.status === RecordStatus.VOIDED ? '已撤销' : '可追溯凭证'}  ·  v${item.record.revision}`)
          .fontSize(10).fontColor(Theme.muted)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Column({ space: 6 }) {
        Text(NumUtil.signed(item.reductionKg, 2)).fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor(item.record.status === RecordStatus.VOIDED ? Theme.muted : (item.isNetIncrease ? Theme.rust : Theme.green))
        Text(item.gasScope).fontSize(9).fontColor(Theme.muted)
      }.alignItems(HorizontalAlign.End)
    }.width('100%').padding(16).backgroundColor(Theme.paper).borderRadius(22).margin({ bottom: 10 })
      .opacity(item.record.status === RecordStatus.VOIDED ? 0.55 : 1)
      .onClick(() => { router.pushUrl({ url: 'pages/VoucherPage', params: { recordId: item.record.recordId, revision: item.record.revision } }); })
  }
}
