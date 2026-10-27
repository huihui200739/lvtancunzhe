import { Result } from '../common/AppError';
import { LedgerOperations } from '../services/LedgerOperations';
import { Theme } from '../common/Theme';
import { AppIcon, PageIntro, SectionHeading, Notice, EmptyState, SubpageHeader } from '../components/DesignSystem';
import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { LedgerDb } from '../services/LedgerDb';
import { AppService } from '../services/AppService';
import { PointService } from '../services/PointService';
import { RewardService } from '../services/RewardService';
import { BackupService } from '../services/BackupService';
import { CsvService } from '../services/CsvService';
import { SelfCheck, CheckResult } from '../services/SelfCheck';
import { BadgeDef } from '../models/ContentModels';
import { BadgeUnlock, PointAccountView, RedemptionView, RewardDef } from '../models/PointModels';
import { CarbonFactor, factorUnitText } from '../models/CarbonFactor';
import { TimeDimension, ReviewStatus } from '../common/Domain';
import { DateUtil, NumUtil } from '../common/Format';
import { Ids } from '../common/Ids';
import { APP_VERSION } from '../common/BuildConfig';

interface BadgeRow {
  def: BadgeDef;
  unlocked: boolean;
  unlockedAt: string;
}

interface RewardRow {
  def: RewardDef;
}

/**
 * 分组标题。用带 @Prop 的子组件而非按值传参的 @Builder：
 * ArkUI 的 @Builder 按值传参时不会随参数变化刷新（例如积分余额变化）。
 */
@Component
struct SectionTitle {
  @Prop text: string = '';

  build() {
    Text(this.text)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .margin({ top: 14, bottom: 6 })
  }
}

/**
 * 我的 Tab：徽章、积分、虚拟兑换与证书、数据管理（备份 / 恢复 / CSV）、因子与来源。
 */
@Component
export struct ProfileTab {
  @Link @Watch('onTick') tick: number;
  @StorageLink('gentleMotion') gentleMotion: boolean = true;
  @State showSources: boolean = false;
  @State showData: boolean = false;
  @State showChecks: boolean = false;
  @State dataBusy: boolean = false;
  @State checking: boolean = false;
  @State badges: BadgeRow[] = [];
  @State rewards: RewardRow[] = [];
  @State redemptions: RedemptionView[] = [];
  @State factors: CarbonFactor[] = [];
  @State balance: number = 0;
  @State testMode: boolean = false;
  @State message: string = '';
  @State status: string = '';
  @State checks: CheckResult[] = [];
  @State selfCheckRan: boolean = false;
  /** 兑换 in-flight 守卫（T03 观察项③）：连点只发一次请求 */
  private redeeming: boolean = false;

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
      this.message = '数据库尚未就绪。';
      return;
    }
    const db = LedgerDb.get();
    this.testMode = AppService.repo().isUsingTestData();
    try {
      const defs: BadgeDef[] = await db.listBadgeDefs();
      const unlocks: BadgeUnlock[] = await db.listBadgeUnlocks();
      const unlockMap: Map<string, string> = new Map<string, string>();
      for (const u of unlocks) {
        unlockMap.set(u.badgeId, u.unlockedAt);
      }
      const rows: BadgeRow[] = [];
      for (const d of defs) {
        const at = unlockMap.get(d.badgeId);
        rows.push({ def: d, unlocked: at !== undefined, unlockedAt: at !== undefined ? at : '' });
      }
      this.badges = rows;

      const rewardDefs: RewardDef[] = await db.listRewards();
      const rr: RewardRow[] = [];
      for (const r of rewardDefs) {
        rr.push({ def: r });
      }
      this.rewards = rr;
      this.redemptions = await RewardService.listRedemptions(db);

      const usable = AppService.repo().listUsable();
      const fs: CarbonFactor[] = [];
      for (const f of usable) {
        fs.push(f);
      }
      this.factors = fs;

      const acc: PointAccountView = await PointService.account(db);
      this.balance = acc.balance;
      this.message = '';
    } catch (e) {
      this.message = `读取失败：${(e as Error).message}`;
    }
  }

  private context(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg, duration: 2500 });
  }

  private async doRedeem(rewardId: string): Promise<void> {
    // T03 观察项③：UI 层 in-flight 守卫，连点不重复发请求（经济安全仍由 RDB 串行 + requestId 幂等兜底）
    if (this.redeeming) {
      return;
    }
    this.redeeming = true;
    try {
      const res = await RewardService.redeem(LedgerDb.get(), rewardId, Ids.uuid());
      if (!res.ok) {
        this.toast(res.message);
        return;
      }
      this.toast('兑换成功，可在「我的兑换记录」查看。');
      this.tick = this.tick + 1;
    } catch (e) {
      this.toast(`兑换未完成：${(e as Error).message}`);
    } finally {
      this.redeeming = false;
    }
  }

  private async runDataAction(action: () => Promise<void>): Promise<void> {
    if (this.dataBusy) { return; }
    this.dataBusy = true;
    try { await action(); }
    catch (e) { this.message = `数据操作未完成：${(e as Error).message}`; }
    finally { this.dataBusy = false; }
  }

  private async exportBackup(): Promise<void> {
    const built = await BackupService.buildBackup(LedgerDb.get());
    if (!built.ok || built.data === null) {
      this.toast(built.message);
      return;
    }
    const name = `lvtancunzhe_backup_${DateUtil.today()}.json`;
    const saved = await BackupService.saveAs(this.context(), name, built.data);
    this.toast(saved.ok ? `备份已保存：${saved.data}` : saved.message);
    this.status = saved.ok ? `最近备份：${name}` : '';
  }

  private async restoreBackup(): Promise<void> {
    const picked = await BackupService.pickText(this.context());
    if (!picked.ok || picked.data === null) {
      this.toast(picked.message);
      return;
    }
    const checked = BackupService.validate(picked.data);
    if (!checked.ok) {
      this.toast(checked.message);
      return;
    }
    const confirm = await promptAction.showDialog({
      title: '确认恢复',
      message: '恢复将全量替换当前数据（记录、凭证、积分、计划与奖励），并自动保存一份恢复前快照。是否继续？',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '确认恢复', color: '#C62828' }
      ]
    });
    if (confirm.index !== 1) {
      return;
    }
    const res = await BackupService.restore(LedgerDb.get(), picked.data, this.context());
    this.toast(res.ok ? '恢复完成，账目已按备份替换。' : res.message);
    if (res.ok) {
      this.tick = this.tick + 1;
    }
  }

  private async exportCsv(kind: string): Promise<void> {
    const db = LedgerDb.get();
    let res: Result<string>;
    let name = `lvtancunzhe_detail_${DateUtil.today()}.csv`;
    if (kind === 'category') {
      res = await CsvService.categorySummaryCsv(db);
      name = `lvtancunzhe_category_${DateUtil.today()}.csv`;
    } else if (kind === 'period') {
      const from = DateUtil.addDays(DateUtil.today(), -180);
      res = await CsvService.periodSummaryCsv(db, TimeDimension.MONTH, from, DateUtil.today());
      name = `lvtancunzhe_month_${DateUtil.today()}.csv`;
    } else {
      res = await CsvService.detailCsv(db);
    }
    if (!res.ok || res.data === null) {
      this.toast(res.message);
      return;
    }
    const saved = await BackupService.saveAs(this.context(), name, res.data);
    this.toast(saved.ok ? `已导出：${name}` : saved.message);
  }

  private async runSelfCheck(): Promise<void> {
    if (!AppService.isReady()) {
      this.message = '数据库尚未就绪。';
      return;
    }
    if (this.checking) { return; }
    this.checking = true;
    try {
      this.checks = await LedgerOperations.run(() => SelfCheck.run(AppService.repo(), LedgerDb.get()));
      this.selfCheckRan = true;
    } catch (e) {
      this.message = `自检异常：${(e as Error).message}`;
    } finally { this.checking = false; }
  }

  private passedCount(): number {
    let n = 0;
    for (const c of this.checks) {
      if (c.pass && !c.skipped) {
        n = n + 1;
      }
    }
    return n;
  }

  private skippedCount(): number {
    let n = 0;
    for (const c of this.checks) {
      if (c.skipped) {
        n = n + 1;
      }
    }
    return n;
  }

  build() {
    Scroll() {
      Column() {
        PageIntro({ title: '我的绿色收藏', subtitle: '把认真生活的痕迹，好好收藏起来。', eyebrow: '每一步，都值得 / MY GARDEN' })
        Row() {
          Column({ space: 10 }) {
            Text('一点坚持，一点回响').fontSize(13).fontColor('#BFCEC1')
            Row({ space: 8 }) {
              Text(`${this.balance}`).fontSize(44).fontWeight(FontWeight.Medium).fontColor(Theme.lime)
                .maxLines(1).minFontSize(20).maxFontSize(44).heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST).flexShrink(1).constraintSize({ maxWidth: '60%' })
              Text('可用积分').fontSize(12).fontColor('#BFCEC1').margin({ top: 18 }).flexShrink(0)
            }.width('100%')
            Text('积分用于应用内虚拟奖励，无现金价值').fontSize(10).fontColor('#BFCEC1')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          AppIcon({ name: 'badge', iconSize: 52, color: Theme.lime })
        }.width('100%').padding(24).backgroundColor(Theme.green).borderRadius(28)
        if (this.message.length > 0) { Notice({ text: this.message, warning: true }).margin({ top: 16 }) }
        if (this.status.length > 0) { Notice({ text: this.status }).margin({ top: 16 }) }
        SectionHeading({ title: '慢慢点亮的成就', detail: '我的徽章' })
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.badges, (b: BadgeRow) => {
            Column({ space: 10 }) {
              AppIcon({ name: 'badge', iconSize: 30, color: b.unlocked ? Theme.green : '#B2BDAA' })
              Text(b.def.name).fontSize(12).fontColor(b.unlocked ? Theme.ink : Theme.muted).maxLines(2).textAlign(TextAlign.Center)
              Text(b.unlocked ? '已点亮' : '等待生长').fontSize(10).fontColor(Theme.muted)
            }.width('31%').height(132).padding(12).margin({ right: '2%', bottom: 10 })
              .backgroundColor(b.unlocked ? Theme.sage : Theme.paper).borderRadius(22).justifyContent(FlexAlign.Center)
          }, (b: BadgeRow) => `${b.def.badgeId}-${b.unlocked}`)
        }.width('100%')
        SectionHeading({ title: '给坚持，一份小奖励', detail: '虚拟权益' })
        ForEach(this.rewards, (r: RewardRow) => {
          Row({ space: 12 }) {
            Column({ space: 8 }) {
              Text(r.def.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(Theme.ink).width('100%')
              Text(r.def.description).fontSize(11).lineHeight(19).fontColor(Theme.muted).width('100%')
            }.layoutWeight(1)
            Button(`${r.def.price} 分`).fontSize(12).height(42).fontColor(Theme.green).backgroundColor(Theme.sage)
              .onClick(() => { this.doRedeem(r.def.rewardId); })
          }.width('100%').padding(20).backgroundColor(Theme.paper).borderRadius(22).margin({ bottom: 12 })
        }, (r: RewardRow) => r.def.rewardId)
        if (this.redemptions.length > 0) {
          SectionHeading({ title: '已收藏的奖励', detail: `${this.redemptions.length} 份` })
          ForEach(this.redemptions, (r: RedemptionView) => {
            Row({ space: 14 }) {
              AppIcon({ name: 'leaf', iconSize: 24 })
              Column({ space: 7 }) {
                Text(r.rewardName).fontSize(14).fontColor(Theme.ink)
                Text(`${r.redemption.createdAt.substring(0, 10)} · ${r.redemption.price} 积分`).fontSize(10).fontColor(Theme.muted)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              AppIcon({ name: 'arrow', iconSize: 18 })
            }.width('100%').padding(20).backgroundColor(Theme.paper).borderRadius(22).margin({ bottom: 10 })
              .onClick(() => router.pushUrl({ url: 'pages/CertificatePage', params: { redemptionId: r.redemption.redemptionId } }))
          }, (r: RedemptionView) => r.redemption.redemptionId)
        }
        SectionHeading({ title: '按自己的节奏' })
        Row() {
          Column({ space: 6 }) {
            Text('轻柔呼吸动效').fontSize(14).fontColor(Theme.ink)
            Text('首页植物缓慢舒展，可随时关闭').fontSize(11).fontColor(Theme.muted)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.gentleMotion }).selectedColor(Theme.green)
            .onChange((v: boolean) => { this.gentleMotion = v; })
        }.width('100%').padding(20).backgroundColor(Theme.paper).borderRadius(22)
        // T05：整行热区（Toggle 视觉尺寸 36x20vp 偏小；点击行任意位置均可切换）
        .onClick(() => { this.gentleMotion = !this.gentleMotion; })
        Row() {
          Text('我的数据').fontSize(14).fontColor(Theme.ink).layoutWeight(1)
          Text(this.showData ? '收起 ↑' : '备份与导出 ↓').fontSize(12).fontColor(Theme.muted)
        }.width('100%').padding(20).backgroundColor(Theme.paper).borderRadius(22).margin({ top: 10 })
          .onClick(() => { this.showData = !this.showData; })
        if (this.showData) {
          Column({ space: 12 }) {
            Row({ space: 10 }) {
              Button('导出备份').layoutWeight(1).height(46).fontSize(12).backgroundColor(Theme.green).enabled(!this.dataBusy).onClick(() => this.runDataAction(() => this.exportBackup()))
              Button('恢复备份').layoutWeight(1).height(46).fontSize(12).fontColor(Theme.rust).backgroundColor('#FAEEE5').enabled(!this.dataBusy).onClick(() => this.runDataAction(() => this.restoreBackup()))
            }.width('100%')
            Row({ space: 8 }) {
              Button('明细 CSV').layoutWeight(1).height(44).fontSize(11).fontColor(Theme.green).backgroundColor(Theme.sage).enabled(!this.dataBusy).onClick(() => this.runDataAction(() => this.exportCsv('detail')))
              Button('分类 CSV').layoutWeight(1).height(44).fontSize(11).fontColor(Theme.green).backgroundColor(Theme.sage).enabled(!this.dataBusy).onClick(() => this.runDataAction(() => this.exportCsv('category')))
              Button('期间 CSV').layoutWeight(1).height(44).fontSize(11).fontColor(Theme.green).backgroundColor(Theme.sage).enabled(!this.dataBusy).onClick(() => this.runDataAction(() => this.exportCsv('period')))
            }.width('100%')
            Text('备份包含私人记录，请妥善保存。恢复前会保留当前数据快照。').fontSize(11).lineHeight(20).fontColor(Theme.muted)
          }.width('100%').padding(18)
        }
        Row() {
          Text('每一个数值，都有来处').fontSize(14).fontColor(Theme.ink).layoutWeight(1)
          Text(this.showSources ? '收起 ↑' : '因子与来源 ↓').fontSize(12).fontColor(Theme.muted)
        }.width('100%').padding(20).backgroundColor(Theme.paper).borderRadius(22).margin({ top: 10 })
          .onClick(() => { this.showSources = !this.showSources; })
        if (this.showSources) {
          ForEach(this.factors, (f: CarbonFactor) => {
            Column({ space: 8 }) {
              Text(f.scenarioLabel).fontSize(14).fontColor(Theme.ink).width('100%')
              Text(`${f.value} ${factorUnitText(f)} · ${f.region} · ${f.dataYear}`).fontSize(11).fontColor(Theme.muted).width('100%')
              Text(`${f.sourceTitle} · ${f.sourceLocator}`).fontSize(11).lineHeight(20).fontColor(Theme.muted).width('100%')
              Text(f.reviewStatus === ReviewStatus.VERIFIED ? '原文数值已核对' : '未核验 · 仅供开发联调').fontSize(10)
                .fontColor(f.reviewStatus === ReviewStatus.VERIFIED ? Theme.green : Theme.rust).width('100%')
            }.width('100%').padding(20).backgroundColor(Theme.paper).borderRadius(20).margin({ top: 10 })
          }, (f: CarbonFactor) => `${f.code}@${f.version}`)
        }
        Row() {
          Text('账本健康检查').fontSize(14).fontColor(Theme.ink).layoutWeight(1)
          Text(this.showChecks ? '收起 ↑' : '展开 ↓').fontSize(12).fontColor(Theme.muted)
        }.width('100%').padding(20).backgroundColor(Theme.paper).borderRadius(22).margin({ top: 10 })
          .onClick(() => { this.showChecks = !this.showChecks; })
        if (this.showChecks) {
          Button(this.checking ? '正在检查…' : '检查计算与账目规则').height(46).fontSize(13).width('100%').backgroundColor(Theme.green)
            .enabled(!this.checking).margin({ top: 12 }).onClick(() => this.runSelfCheck())
          if (this.selfCheckRan) {
            Text(`通过 ${this.passedCount()} / ${this.checks.length} 项 · 跳过 ${this.skippedCount()} 项`).fontSize(12).fontColor(Theme.green).margin({ top: 14 })
          }
          ForEach(this.checks, (c: CheckResult) => {
            Text(`${c.skipped ? '跳过' : (c.pass ? '通过' : '失败')} · ${c.name}\n${c.detail}`).fontSize(11).lineHeight(20)
              .fontColor(c.pass || c.skipped ? Theme.muted : Theme.rust).width('100%').padding({ top: 8, bottom: 8 })
          }, (c: CheckResult, i: number) => `${i}-${c.name}`)
        }
        if (this.testMode) { Notice({ text: '开发预览 · 未核验因子仅供联调，不得用于参赛材料与对外结论。', warning: true }).margin({ top: 20 }) }
        Text(`绿碳存折 ${APP_VERSION}\n只记录局部行为估算，不代表完整个人碳足迹。`).fontSize(10).lineHeight(20).fontColor(Theme.muted)
          .textAlign(TextAlign.Center).width('100%').margin({ top: 28, bottom: 30 })
      }.width('100%').padding({ left: 22, right: 22 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Off).backgroundColor(Theme.bg)
  }
}
