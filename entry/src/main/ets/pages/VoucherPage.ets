import { Theme } from '../common/Theme';
import { AppIcon, PageIntro, SectionHeading, Notice, EmptyState, SubpageHeader } from '../components/DesignSystem';
import { router, promptAction } from '@kit.ArkUI';
import { LedgerDb } from '../services/LedgerDb';
import { AppService } from '../services/AppService';
import { RecordService } from '../services/RecordService';
import { PlanService } from '../services/PlanService';
import { VoucherParams } from '../models/UiModels';
import { RecordDraft, VoucherFactorSource, VoucherView } from '../models/RecordModels';
import { ScenarioInput, ScenarioResult } from '../models/CalcModels';
import { Result } from '../common/AppError';
import { BaselineType, BehaviorCategory, RecordStatus, SCOPE_STATEMENT, ScenarioRole, categoryName, gasUnitLabel } from '../common/Domain';
import { NumUtil } from '../common/Format';

/**
 * 凭证页（第 5.3 节字段顺序：行为 → 对照 → 计算 → 来源 → 范围 → 变更）。
 * 先展示可读结果与解释，再提供完整计算明细；
 * 对照切换默认进入「试算」，不修改已入账记录；修订生成新版本并做积分差额调整。
 */
@Entry
@Component
struct VoucherPage {
  @State showDetails: boolean = false;
  @State showSources: boolean = false;
  @State recordId: string = '';
  @State revision: number = 1;
  @State view: VoucherView | null = null;
  @State swapped: boolean = false;
  @State revising: boolean = false;
  @State reviseQty: string = '';
  @State reviseFuelKg: string = '';
  @State revisePassengers: string = '1';
  @State reviseDate: string = '';
  @State message: string = '';

  aboutToAppear(): void {
    const p = router.getParams() as VoucherParams;
    if (p !== null && p !== undefined) {
      this.recordId = `${p.recordId}`;
      this.revision = p.revision;
    }
    this.load();
  }

  private async load(): Promise<void> {
    const res: Result<VoucherView> = await RecordService.getVoucher(LedgerDb.get(), this.recordId, this.revision);
    if (!res.ok || res.data === null) {
      this.message = res.message;
      return;
    }
    this.view = res.data;
    this.reviseQty = `${res.data.record.quantity}`;
    this.reviseDate = res.data.record.occurredAt;
    for (const scenario of res.data.scenarios) {
      if (scenario.role === ScenarioRole.BASELINE && scenario.unit === 'kg' && res.data.record.category === BehaviorCategory.TRAVEL) { this.reviseFuelKg = `${scenario.quantity}`; }
      if (scenario.role === ScenarioRole.BASELINE && scenario.passengers !== undefined && scenario.passengers > 0) {
        this.revisePassengers = `${scenario.passengers}`;
      } else if (scenario.role === ScenarioRole.BASELINE && scenario.emissionKg > 0 && scenario.factorValue > 0) {
        const f = AppService.repo().find(scenario.factorCode);
        if (f !== undefined && f.distanceBasis === 'vkm') {
          this.revisePassengers = `${Math.max(1, Math.round(scenario.quantity * scenario.factorValue / scenario.emissionKg))}`;
        }
      }
    }
    this.message = '';
  }

  private baselineSum(s: ScenarioResult[]): number {
    let v = 0;
    for (const x of s) {
      if (x.role === ScenarioRole.BASELINE) {
        v = v + x.emissionKg;
      }
    }
    return v;
  }

  private actualSum(s: ScenarioResult[]): number {
    let v = 0;
    for (const x of s) {
      if (x.role === ScenarioRole.ACTUAL) {
        v = v + x.emissionKg;
      }
    }
    return v;
  }

  /** 试算：互换对照与实际后的结果（不写库） */
  private swappedReduction(): number {
    if (this.view === null) {
      return 0;
    }
    return NumUtil.roundCalc(this.actualSum(this.view.scenarios) - this.baselineSum(this.view.scenarios));
  }

  @State private updating: boolean = false;

  private async doVoid(): Promise<void> {
    if (this.updating) { return; }
    this.updating = true;
    try { await this.voidCurrent(); }
    catch (e) { this.message = `撤销未完成：${(e as Error).message}`; }
    finally { this.updating = false; }
  }

  private async voidCurrent(): Promise<void> {
    const confirm = await promptAction.showDialog({
      title: '撤销记录',
      message: '撤销后该记录不再计入统计与积分，并写冲正事件（不物理删除）。是否继续？',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '确认撤销', color: '#C62828' }
      ]
    });
    if (confirm.index !== 1) {
      return;
    }
    const db = LedgerDb.get();
    const res = await RecordService.voidRecord(db, this.recordId, this.revision);
    if (!res.ok) {
      this.message = res.message;
      return;
    }
    promptAction.showToast({ message: '已撤销，账目与积分已同步调整。' });
    router.back();
  }

  private async doRevise(): Promise<void> {
    if (this.updating) { return; }
    this.updating = true;
    try { await this.reviseCurrent(); }
    catch (e) { this.message = `修订未完成：${(e as Error).message}`; }
    finally { this.updating = false; }
  }

  private async reviseCurrent(): Promise<void> {
    if (this.view === null) {
      return;
    }
    const qty = NumUtil.parseQuantity(this.reviseQty);
    if (!Number.isFinite(qty) || qty <= 0) {
      this.message = '修订数量必须是大于 0 的数字。';
      return;
    }
    const scenarios: ScenarioResult[] = this.view.scenarios;
    const drafts: ScenarioInput[] = [];
    for (const s of scenarios) {
      drafts.push({
        role: s.role,
        factorCode: s.factorCode,
        quantity: this.view.record.category === BehaviorCategory.TRAVEL && s.role === ScenarioRole.BASELINE && s.unit === 'kg' ? NumUtil.parseQuantity(this.reviseFuelKg) : qty,
        unit: s.unit,
        label: s.label
      });
    }
    const draft: RecordDraft = {
      category: this.view.record.category,
      baselineType: this.view.snapshot.baselineType,
      scenarios: drafts,
      occurredAt: this.reviseDate,
      entrySource: this.view.record.entrySource,
      remark: this.view.record.remark,
      applicabilityAccepted: this.view.sources.every((f: VoucherFactorSource) => !f.applicabilityNote || f.applicabilityConfirmed === true),
      passengers: this.view.record.category === BehaviorCategory.TRAVEL ? NumUtil.parseQuantity(this.revisePassengers) : 0
    };
    const res = await RecordService.reviseRecord(LedgerDb.get(), AppService.repo(), this.recordId, this.revision, draft);
    if (!res.ok || res.data === null) {
      this.message = res.message;
      return;
    }
    promptAction.showToast({ message: '已生成新版本，积分按差额调整。' });
    this.revision = res.data.record.revision;
    // 先取回新版本数据，再收起修订面板：避免面板收起瞬间凭证区闪现旧数量（T03 观察项①）
    await this.load();
    this.revising = false;
  }

  private evidence(): string {
    if (this.view === null) {
      return '';
    }
    return this.view.snapshot.evidenceLabel;
  }

  build() {
    Column() {
      SubpageHeader({ title: '这笔行动的减排凭证' })
      if (this.view === null) {
        EmptyState({ title: '正在翻开这笔记录', detail: this.message }).margin(22)
      } else {
        Scroll() {
          Column() {
            Column({ space: 14 }) {
              Row() {
                Text('GREEN RECEIPT').fontSize(10).letterSpacing(2).fontColor('#BFCEC1').layoutWeight(1)
                AppIcon({ name: 'leaf', iconSize: 24 })
              }.width('100%')
              Text(`${categoryName(this.view.record.category)} · ${this.view.record.quantity} ${this.view.record.unit}`)
                .fontSize(21).fontColor(Theme.paper).fontWeight(FontWeight.Medium).width('100%')
              Text(this.view.record.status === RecordStatus.VOIDED ? '这笔记录已撤销' : (this.view.snapshot.isNetIncrease ? '相对基准增加排放' : '相对基准的估算减排'))
                .fontSize(12).fontColor('#BFCEC1').width('100%').margin({ top: 10 })
              Row({ space: 8 }) {
                Text(NumUtil.signed(this.view.snapshot.reductionKg, 2)).fontSize(44).fontColor(Theme.lime).fontWeight(FontWeight.Medium)
                Text(gasUnitLabel(this.view.snapshot.gasScope)).fontSize(12).fontColor('#BFCEC1').margin({ top: 20 })
              }.width('100%')
              Divider().color('#527365').margin({ top: 8, bottom: 8 })
              Row() {
                Text(this.view.record.occurredAt).fontSize(12).fontColor('#BFCEC1').layoutWeight(1)
                Text(`积分 ${this.view.pointDelta > 0 ? '+' : ''}${this.view.pointDelta} · v${this.view.record.revision}`)
                  .fontSize(12).fontColor('#BFCEC1')
              }.width('100%')
            }.width('100%').padding(24).backgroundColor(Theme.green).borderRadius(28)
            SectionHeading({ title: '从哪里，算到哪里' })
            Column({ space: 14 }) {
              ForEach(this.view.scenarios, (s: ScenarioResult) => {
                Row({ space: 12 }) {
                  Text(s.role === ScenarioRole.BASELINE ? '原本' : '实际').fontSize(11).fontColor(Theme.muted).width(36)
                  Column({ space: 6 }) {
                    Text(s.scenarioLabel).fontSize(15).fontColor(Theme.ink)
                    Text(`${NumUtil.fixed(s.quantity, 2)} ${s.unit} × ${s.factorValue} ${s.factorUnit}${s.conversionNote ? ' · ' + s.conversionNote : ''}`).fontSize(11).lineHeight(19).fontColor(Theme.muted)
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Text(`${NumUtil.fixed(s.emissionKg, 2)} kg`).fontSize(13).fontColor(Theme.green)
                }.width('100%')
              }, (s: ScenarioResult, i: number) => `${this.revision}-${i}-${s.factorCode}`)
              Text(this.view.snapshot.baselineType === BaselineType.USER_DECLARED ? '基准来自你声明的替代情景' : '基准按所选方法和适用情景设置')
                .fontSize(11).lineHeight(20).fontColor(Theme.muted).width('100%')
            }.width('100%').padding(22).backgroundColor(Theme.paper).borderRadius(24)
            if (this.view.record.category === BehaviorCategory.TRAVEL) {
              Button(this.swapped ? '收起对照试算' : '换个对照，看看会怎样').fontSize(13).height(48).width('100%')
                .fontColor(Theme.green).backgroundColor(Theme.sage).margin({ top: 16 }).onClick(() => { this.swapped = !this.swapped; })
              if (this.swapped) {
                Notice({ text: `只做数学对照：互换后为 ${NumUtil.signed(this.swappedReduction(), 4)} ${gasUnitLabel(this.view.snapshot.gasScope)}。不修改账本，也不代表因子角色允许互换。` }).margin({ top: 12 })
              }
            }
            Row() {
              Text('每一步计算，都可追溯').fontSize(15).fontColor(Theme.ink).layoutWeight(1)
              Text(this.showDetails ? '收起 ↑' : '展开 ↓').fontSize(12).fontColor(Theme.muted)
            }.width('100%').padding(22).backgroundColor(Theme.paper).borderRadius(24).margin({ top: 22 })
              .onClick(() => { this.showDetails = !this.showDetails; })
            if (this.showDetails) {
              Column({ space: 12 }) {
                Text(this.view.snapshot.formulaText).fontSize(12).lineHeight(23).fontColor(Theme.ink).width('100%')
                Text(`公式 ${this.view.snapshot.formulaVersion} · ${this.view.snapshot.roundingNote}`).fontSize(11).lineHeight(20).fontColor(Theme.muted).width('100%')
                Text(`备注依据：${this.view.record.remark}\n记录 ${this.view.record.recordId}\n创建 ${this.view.record.createdAt}\n更新 ${this.view.record.updatedAt}\n${this.evidence()}`)
                  .fontSize(10).lineHeight(20).fontColor(Theme.muted).width('100%')
              }.width('100%').padding(22).backgroundColor(Theme.paper).borderRadius(24).margin({ top: 10 })
            }
            Row() {
              Text('数值的来处').fontSize(15).fontColor(Theme.ink).layoutWeight(1)
              Text(this.showSources ? '收起 ↑' : '来源与边界 ↓').fontSize(12).fontColor(Theme.muted)
            }.width('100%').padding(22).backgroundColor(Theme.paper).borderRadius(24).margin({ top: 10 })
              .onClick(() => { this.showSources = !this.showSources; })
            if (this.showSources) {
              ForEach(this.view.sources, (f: VoucherFactorSource) => {
                Column({ space: 10 }) {
                  Text(f.factorName).fontSize(15).fontColor(Theme.ink).width('100%')
                  Text(`${f.region} · ${f.dataYear} · ${f.factorCode}@${f.factorVersion}`).fontSize(10).fontColor(Theme.muted).width('100%')
                  Text(`${f.sourceTitle}\n${f.sourceLocator}\n${f.sourceUrl}`).fontSize(11).lineHeight(21).fontColor(Theme.muted).width('100%')
                  Text(`边界：${f.boundary}\n方法：${f.methodology}\n${f.applicabilityNote || ''}${f.applicabilityNote ? (f.applicabilityConfirmed ? '（适用条件由用户确认，依据见备注）' : '（未确认）') : ''}`).fontSize(11).lineHeight(21).fontColor(Theme.muted).width('100%')
                  Text(`${f.reviewStatus === 'verified' ? '原文数值已核对' : '未核验 · 仅供开发'} · ${f.licenseNote}`).fontSize(10).lineHeight(20).fontColor(Theme.rust).width('100%')
                }.width('100%').padding(22).backgroundColor(Theme.paper).borderRadius(24).margin({ top: 10 })
              }, (f: VoucherFactorSource, i: number) => `${this.revision}-${i}-${f.factorCode}`)
            }
            Text(this.view.snapshot.scopeNote).fontSize(11).lineHeight(21).fontColor(Theme.muted).width('100%').margin({ top: 22 })
            if (this.view.record.status === RecordStatus.ACTIVE && this.view.isLatest) {
              if (this.revising) {
                Column({ space: 12 }) {
                  Text('修订会保留原版本，并调整积分差额').fontSize(12).fontColor(Theme.muted).width('100%')
                  TextInput({ text: this.reviseQty }).fontSize(16).height(50).type(InputType.Number).backgroundColor(Theme.paper)
                    .onChange((v: string) => { this.reviseQty = v; })
                  if (this.view.record.category === BehaviorCategory.TRAVEL && this.reviseFuelKg.length > 0) {
                    Text('原本驾车的个人分担汽油质量 / kg').fontSize(12).fontColor(Theme.muted).width('100%')
                    TextInput({ text: this.reviseFuelKg }).fontSize(16).height(50).type(InputType.Number).backgroundColor(Theme.paper)
                      .onChange((v: string) => { this.reviseFuelKg = v; })
                  }
                  if (this.view.record.category === BehaviorCategory.TRAVEL && this.reviseFuelKg.length === 0) {
                    Text('原本车辆的载客人数 / 人').fontSize(12).fontColor(Theme.muted).width('100%')
                    TextInput({ text: this.revisePassengers }).fontSize(16).height(50).type(InputType.Number).backgroundColor(Theme.paper)
                      .onChange((v: string) => { this.revisePassengers = v; })
                  }
                  TextInput({ text: this.reviseDate }).fontSize(14).height(50).backgroundColor(Theme.paper)
                    .onChange((v: string) => { this.reviseDate = v; })
                  Button('确认修订').enabled(!this.updating).height(48).width('100%').backgroundColor(Theme.green).onClick(() => this.doRevise())
                }.width('100%').margin({ top: 22 })
              }
              Row({ space: 12 }) {
                Button(this.revising ? '取消修订' : '修订记录').height(48).fontSize(13).layoutWeight(1).fontColor(Theme.green).backgroundColor(Theme.sage)
                  .onClick(() => { this.revising = !this.revising; })
                Button('撤销记录').enabled(!this.updating).height(48).fontSize(13).layoutWeight(1).fontColor(Theme.rust).backgroundColor('#FAEEE5').onClick(() => this.doVoid())
              }.width('100%').margin({ top: 24 })
            }
            if (this.message.length > 0) { Notice({ text: this.message, warning: true }).margin({ top: 14 }) }
            Text('每一笔改变，都经得起回看。').fontSize(11).fontColor(Theme.muted).width('100%').textAlign(TextAlign.Center).margin({ top: 28, bottom: 30 })
          }.width('100%').padding({ left: 22, right: 22, top: 14 }).alignItems(HorizontalAlign.Start)
        }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
      }
    }.width('100%').height('100%').backgroundColor(Theme.bg)
  }

  @Builder
  section(t: string) {
    Text(t)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .margin({ top: 12, bottom: 4 })
  }

  @Builder
  kv(k: string, v: string) {
    Row() {
      Text(k).fontSize(12).fontColor('#888888').width(90)
      Text(v).fontSize(12).fontColor('#333333').layoutWeight(1)
    }
    .width('100%')
    .margin({ bottom: 3 })
  }
}
