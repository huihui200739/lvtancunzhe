import { PlanLinkPolicy } from '../services/PlanLinkPolicy';
import { Theme } from '../common/Theme';
import { QuantityField } from '../components/QuantityField';
import { AppIcon, PageIntro, SectionHeading, Notice, EmptyState, SubpageHeader } from '../components/DesignSystem';
import { router } from '@kit.ArkUI';
import { AppService } from '../services/AppService';
import { LedgerDb } from '../services/LedgerDb';
import { RecordService } from '../services/RecordService';
import { PlanService } from '../services/PlanService';
import { CalcEngine } from '../services/CalcEngine';
import { CarbonFactor, factorUnitText } from '../models/CarbonFactor';
import { CalcOutcome, ScenarioInput } from '../models/CalcModels';
import { RecordDraft } from '../models/RecordModels';
import { EntryParams } from '../models/UiModels';
import { BaselineType, BehaviorCategory, EntrySource, FactorUsableAs, ReviewStatus, ScenarioRole, categoryName } from '../common/Domain';
import { DateUtil, NumUtil } from '../common/Format';

interface CatChip {
  key: string;
  label: string;
}

interface FactorChip {
  code: string;
  label: string;
  detail: string;
}

/**
 * 因子候选片。用 @Link 双向绑定选中项而非按值传参的 @Builder，
 * 否则切换因子时高亮不会刷新（@Builder 按值传参不随参数变化重绘）。
 */
@Component
struct FactorChips {
  @Prop chips: FactorChip[] = [];
  @Link selected: string;

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.chips, (c: FactorChip) => {
        Column() {
          Text(c.label)
            .fontSize(12)
            .fontColor(this.selected === c.code ? '#FFFFFF' : Theme.ink)
          Text(c.detail)
            .fontSize(10)
            .fontColor(this.selected === c.code ? '#C8D9C6' : Theme.muted)
            .margin({ top: 2 })
        }
        .padding(14)
        .margin({ right: 8, bottom: 8 })
        .backgroundColor(this.selected === c.code ? Theme.green : '#FFFFFF')
        .borderRadius(16)
        .onClick(() => {
          this.selected = c.code;
        })
      }, (c: FactorChip) => `${c.code}`)
    }
    .width('100%')
  }
}

/**
 * 录入页（第 4.1 节 B1、第 5.3 节）。四类行为；数量、单位、日期、对照情景与实时试算。
 * 出行按「对照 vs 实际」核算；其余类别按单一情景核算。保存后生成可追溯凭证。
 */
@Entry
@Component
struct RecordEntry {
  @State category: BehaviorCategory = BehaviorCategory.TRAVEL;
  @State @Watch('onFactorChanged') baselineCode: string = '';
  @State @Watch('onFactorChanged') actualCode: string = '';
  @State showFactorChoices: boolean = false;
  @State @Watch('onFactorChanged') singleCode: string = '';
  @State fuelKgText: string = '';
  @State applicabilityAccepted: boolean = false;
  @State qtyText: string = '5';
  @State passengersText: string = '1';
  @State dateText: string = DateUtil.today();
  @State remark: string = '';
  @State baselineTypeKey: string = 'user_declared';
  @State previewText: string = '';
  @State previewOk: boolean = true;
  @State errMsg: string = '';
  @State saving: boolean = false;
  @State savedRecordId: string = '';
  private planTaskId: string = '';
  @State planContext: string = '';
  @State planReady: boolean = true;

  private cats: CatChip[] = [
    { key: 'travel', label: '出行' },
    { key: 'water_energy', label: '节水节电' },
    { key: 'recycling', label: '旧物回收' },
    { key: 'food', label: '光盘行动' }
  ];

  aboutToAppear(): void {
    const params = router.getParams() as EntryParams;
    if (params !== null && params !== undefined) {
      if (params.category !== undefined && `${params.category}`.length > 0) {
        this.category = `${params.category}` as BehaviorCategory;
      }
      if (params.planTaskId !== undefined && `${params.planTaskId}`.length > 0) {
        this.planTaskId = `${params.planTaskId}`;
      }
    }
    this.resetFactors();
    if (this.planTaskId.length > 0) { this.planReady = false; this.loadPlanTask(); }
  }

  private async loadPlanTask(): Promise<void> {
    try {
      const db = LedgerDb.get();
      const task = await db.getPlanTask(this.planTaskId);
      if (task === null) { this.errMsg = '找不到这项任务，请返回计划重新选择。'; return; }
      const taskError = PlanLinkPolicy.taskError(task);
      if (taskError.length > 0 || task.participationOnly || task.linkedRecordId.length > 0) {
        this.errMsg = taskError.length > 0 ? taskError : '这项任务不能再从核算录入入口完成，请返回计划。'; return;
      }
      this.category = task.category; this.resetFactors(); this.dateText = task.day;
      const templates = await db.listTemplates();
      const template = templates.find((t) => t.templateId === task.templateId);
      const factor = template === undefined ? undefined : this.usableFor(task.category).find((f: CarbonFactor) => f.subItem === template.factorSubItem);
      if (factor === undefined) { this.errMsg = '任务需要的适用因子不可用，请返回计划。'; return; }
      if (this.category === BehaviorCategory.TRAVEL) { this.actualCode = factor.code; }
      else { this.singleCode = factor.code; }
      this.planContext = `正在完成：${task.name} · ${task.day}。数量请按真实发生填写，计划预计 ${NumUtil.show(task.quantity)} ${task.unit} 仅作参考。`;
      this.planReady = true;
    } catch (e) { this.errMsg = `读取任务失败，请返回重试：${(e as Error).message}`; }
  }

  private usableFor(c: BehaviorCategory): CarbonFactor[] {
    const repo = AppService.repo();
    const out: CarbonFactor[] = [];
    for (const f of repo.listByCategory(c)) {
      if (repo.isUsable(f)) {
        out.push(f);
      }
    }
    return out;
  }

  private roleMatches(f: CarbonFactor, role: ScenarioRole): boolean {
    if (f.usableAs === FactorUsableAs.BOTH) {
      return true;
    }
    if (role === ScenarioRole.BASELINE) {
      return f.usableAs === FactorUsableAs.BASELINE || f.usableAs === FactorUsableAs.SINGLE;
    }
    return f.usableAs === FactorUsableAs.ACTUAL;
  }

  private baselineCandidates(): CarbonFactor[] {
    const out: CarbonFactor[] = [];
    for (const f of this.usableFor(this.category)) {
      if (f.usableAs === FactorUsableAs.BASELINE || f.usableAs === FactorUsableAs.BOTH) {
        out.push(f);
      }
    }
    return out;
  }

  private actualCandidates(): CarbonFactor[] {
    const out: CarbonFactor[] = [];
    for (const f of this.usableFor(this.category)) {
      if (f.usableAs === FactorUsableAs.ACTUAL || f.usableAs === FactorUsableAs.BOTH) {
        out.push(f);
      }
    }
    return out;
  }

  private singleCandidates(): CarbonFactor[] {
    const out: CarbonFactor[] = [];
    for (const f of this.usableFor(this.category)) {
      if (f.usableAs === FactorUsableAs.SINGLE || f.usableAs === FactorUsableAs.BOTH
        || f.usableAs === FactorUsableAs.BASELINE) {
        out.push(f);
      }
    }
    return out;
  }

  private resetFactors(): void {
    const base = this.baselineCandidates();
    this.baselineCode = base.length > 0 ? base[0].code : '';
    const act = this.actualCandidates();
    this.actualCode = act.length > 0 ? act[0].code : '';
    const single = this.singleCandidates();
    this.singleCode = single.length > 0 ? single[0].code : '';
    this.qtyText = this.category === BehaviorCategory.TRAVEL ? '5' : '1';
    this.previewText = ''; this.applicabilityAccepted = false; this.fuelKgText = '';
  }

  private onFactorChanged(): void { this.previewText = ''; this.showFactorChoices = false; this.applicabilityAccepted = false; }

  private factorOf(code: string): CarbonFactor | undefined {
    return AppService.repo().find(code);
  }

  private labelOf(f: CarbonFactor): string {
    const suffix = f.reviewStatus === ReviewStatus.VERIFIED ? '' : '（测试）';
    return `${f.scenarioLabel}${suffix}`;
  }

  private chipsFor(list: CarbonFactor[]): FactorChip[] {
    const out: FactorChip[] = [];
    for (const f of list) {
      out.push({ code: f.code, label: this.labelOf(f), detail: `${f.value} ${factorUnitText(f)}` });
    }
    return out;
  }

  private buildScenarios(): ScenarioInput[] | null {
    const qty = NumUtil.parseQuantity(this.qtyText);
    if (!Number.isFinite(qty) || qty <= 0) {
      this.errMsg = '数量必须是大于 0 的数字。';
      return null;
    }
    if (this.category === BehaviorCategory.TRAVEL) {
      if (this.baselineCode.length === 0 || this.actualCode.length === 0) {
        this.errMsg = '出行需要同时选择对照情景与实际情景。';
        return null;
      }
      if (this.baselineCode === this.actualCode) {
        this.errMsg = '对照情景与实际情景不能相同。';
        return null;
      }
      const base: CarbonFactor | undefined = this.factorOf(this.baselineCode);
      const act: CarbonFactor | undefined = this.factorOf(this.actualCode);
      if (base === undefined || act === undefined) {
        this.errMsg = '所选因子不可用。';
        return null;
      }
      if (base.gasScope !== act.gasScope) {
        this.errMsg = '对照与实际的气体口径不同（CO₂ 与 CO₂e），不能混算。';
        return null;
      }
      return [
        { role: ScenarioRole.BASELINE, factorCode: this.baselineCode, quantity: base.perUnit === 'km' ? qty : NumUtil.parseQuantity(this.fuelKgText), unit: base.perUnit, label: base.perUnit === 'kg' ? '原本驾车的个人分担汽油质量（用户声明）' : '' },
        { role: ScenarioRole.ACTUAL, factorCode: this.actualCode, quantity: qty, unit: 'km', label: '' }
      ];
    }
    if (this.singleCode.length === 0) {
      this.errMsg = '请选择一个可用因子。';
      return null;
    }
    const f: CarbonFactor | undefined = this.factorOf(this.singleCode);
    if (f === undefined) {
      this.errMsg = '所选因子不可用。';
      return null;
    }
    return [{ role: ScenarioRole.BASELINE, factorCode: this.singleCode, quantity: qty, unit: f.perUnit, label: '' }];
  }

  private baselineType(): BaselineType {
    return this.baselineTypeKey === 'statistical' ? BaselineType.STATISTICAL : BaselineType.USER_DECLARED;
  }

  private passengers(): number {
    const p = NumUtil.parseQuantity(this.passengersText);
    return Number.isFinite(p) && p > 0 ? p : 0;
  }

  private calculate(): CalcOutcome | null {
    this.errMsg = '';
    if (!DateUtil.isValidDay(this.dateText)) { this.errMsg = '请输入有效日期，格式为 YYYY-MM-DD。'; return null; }
    if (DateUtil.isFuture(this.dateText)) {
      this.errMsg = '未来日期不能作为已完成的行为记录。';
      return null;
    }
    const scenarios = this.buildScenarios();
    if (scenarios === null) {
      return null;
    }
    return CalcEngine.calculate({
      category: this.category,
      baselineType: this.baselineType(),
      scenarios: scenarios
    }, AppService.repo(), this.passengers());
  }

  private doPreview(): void {
    const outcome = this.calculate();
    if (outcome === null) {
      this.previewText = '';
      return;
    }
    this.previewOk = outcome.ok;
    this.previewText = outcome.ok
      ? `预计减排 ${NumUtil.signed(outcome.reductionKg, 4)} kg（${outcome.gasScope}）${outcome.isNetIncrease ? '，相对所选情景增加排放，不发减排积分。' : ''}`
      : outcome.message;
  }

  private async save(): Promise<void> {
    try { await this.saveRecord(); }
    catch (e) { this.errMsg = `保存未完成，请重试：${(e as Error).message}`; this.saving = false; }
  }

  private async saveRecord(): Promise<void> {
    if (this.saving) {
      return;
    }
    if (this.savedRecordId.length > 0) {
      this.saving = true;
      try {
        const retry = await PlanService.completeTask(LedgerDb.get(), this.planTaskId, this.savedRecordId);
        if (!retry.ok) { this.errMsg = `记录已入账，关联仍未成功：${retry.message}`; return; }
        router.back();
      } catch (e) { this.errMsg = `记录已入账，关联未完成：${(e as Error).message}`; }
      finally { this.saving = false; }
      return;
    }
    const outcome = this.calculate();
    if (outcome === null) {
      return;
    }
    if (!outcome.ok) {
      this.errMsg = outcome.message;
      return;
    }
    this.saving = true;
    const scenarios = this.buildScenarios();
    if (scenarios === null) {
      this.saving = false;
      return;
    }
    const draft: RecordDraft = {
      category: this.category,
      baselineType: this.baselineType(),
      scenarios: scenarios,
      occurredAt: this.dateText,
      entrySource: EntrySource.USER_INPUT,
      remark: this.remark,
      passengers: this.passengers(),
      applicabilityAccepted: this.applicabilityAccepted
    };
    const db = LedgerDb.get();
    if (this.planTaskId.length > 0) {
      const task = await db.getPlanTask(this.planTaskId);
      const templates = await db.listTemplates();
      const template = task === null ? undefined : templates.find((t) => t.templateId === task.templateId);
      const error = task === null ? '找不到这项任务，请返回计划。' : PlanLinkPolicy.draftError(task, draft, template, AppService.repo());
      if (error.length > 0) { this.errMsg = error; this.saving = false; return; }
    }
    const res = await RecordService.createRecord(db, AppService.repo(), draft);
    if (!res.ok || res.data === null) {
      this.errMsg = res.message;
      this.saving = false;
      return;
    }
    this.savedRecordId = res.data.record.recordId;
    if (this.planTaskId.length > 0) {
      const linked = await PlanService.completeTask(db, this.planTaskId, res.data.record.recordId);
      if (!linked.ok) {
        this.errMsg = `记录已保存，但任务关联失败：${linked.message}`;
        this.saving = false;
        return;
      }
    }
    this.saving = false;
    router.back();
  }

  private conditionText(): string {
    const base = this.category === BehaviorCategory.TRAVEL ? this.factorOf(this.baselineCode) : this.selectedFactor();
    return base !== undefined && base.evidenceRequirement ? base.evidenceRequirement : '';
  }

  private fuelBaseline(): boolean { const f = this.factorOf(this.baselineCode); return this.category === BehaviorCategory.TRAVEL && f !== undefined && f.perUnit === 'kg'; }

  private selectedFactor(): CarbonFactor | undefined {
    if (this.category === BehaviorCategory.TRAVEL) {
      return this.factorOf(this.actualCode);
    }
    return this.factorOf(this.singleCode);
  }

  build() {
    Column() {
      SubpageHeader({ title: '记一笔绿色行动' })
      Scroll() {
        Column() {
          PageIntro({ title: '今天，做了哪件小事？', subtitle: '填写真实发生的行动，留下有依据的绿色记录。', eyebrow: '一笔一笔，存下改变' })
          if (this.planContext.length > 0) { Notice({ text: this.planContext }).margin({ bottom: 16 }) }
          Column() {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.cats, (c: CatChip) => {
              Text(c.label).fontSize(12).fontColor(`${this.category}` === c.key ? Theme.paper : Theme.muted)
                .padding({ left: 16, right: 16, top: 13, bottom: 13 }).borderRadius(18)
                .backgroundColor(`${this.category}` === c.key ? Theme.green : Theme.paper).margin({ right: 8, bottom: 10 })
                .enabled(this.savedRecordId.length === 0).onClick(() => { this.category = c.key as BehaviorCategory; this.resetFactors(); })
            }, (c: CatChip) => c.key)
          }.width('100%')
          if (!this.hasUsableFactor()) {
            EmptyState({ title: '这类行动，正在补齐计算依据', detail: '当前没有适用且已核验的因子，暂不能估算。\n你可以先记录其他已开放的行动。' }).margin({ top: 20 })
          } else {
            SectionHeading({ title: this.category === BehaviorCategory.TRAVEL ? '01  原本与这次' : '01  选择你的行动' })
            if (this.category === BehaviorCategory.TRAVEL) {
              Text('原本会选择').fontSize(12).fontColor(Theme.muted).margin({ bottom: 12 })
              FactorChips({ chips: this.chipsFor(this.baselineCandidates()), selected: $baselineCode })
              Text('这次实际选择').fontSize(12).fontColor(Theme.muted).margin({ top: 12, bottom: 12 })
              FactorChips({ chips: this.chipsFor(this.actualCandidates()), selected: $actualCode })
              Notice({ text: '按你声明的替代情景计算。请只记录确实替代了原出行方式的同一段路程。' }).margin({ top: 8 })
            } else {
              if (this.showFactorChoices) {
                FactorChips({ chips: this.chipsFor(this.singleCandidates()), selected: $singleCode })
              } else {
                FactorChips({ chips: this.chipsFor(this.singleCandidates().filter((f: CarbonFactor) => f.code === this.singleCode)), selected: $singleCode })
              }
              Text(this.showFactorChoices ? '收起其他情景 ↑' : '选择其他适用情景 ↓').fontSize(12).fontColor(Theme.green)
                .padding({ top: 10, bottom: 14 }).onClick(() => { this.showFactorChoices = !this.showFactorChoices; })
            }
            if (this.selectedFactor() !== undefined) {
              Text(this.selectedFactor()!.note).fontSize(11).lineHeight(20).fontColor(Theme.muted).width('100%').margin({ top: 8 })
            }
            SectionHeading({ title: '02  记下真实数量' })
            Column({ space: 14 }) {
              Text(this.category === BehaviorCategory.TRAVEL ? '实际步行或骑行的行程长度' : '实际节约或符合条件的数量')
                .fontSize(12).fontColor(Theme.muted).width('100%')
              QuantityField({ value: $qtyText, unit: this.unitOfSelected(), label: '实际数量', valueSize: 38,
                onEdited: () => { this.previewText = ''; } })
              if (this.fuelBaseline()) {
                Text('原本驾车会消耗的个人分担汽油质量 / kg').fontSize(12).lineHeight(21).fontColor(Theme.muted).width('100%')
                TextInput({ text: this.fuelKgText, placeholder: '根据行程和油耗资料估算，必须有依据' }).id('record-fuel-kg').fontSize(16).height(52).type(InputType.NUMBER_DECIMAL).backgroundColor(Theme.bg)
                  .onChange((v: string) => { this.fuelKgText = v; this.previewText = ''; })
              }
              if (this.category === BehaviorCategory.TRAVEL && this.baselineUsesVkm()) {
                Row({ space: 10 }) {
                  Text('原本车辆的载客人数').fontSize(12).fontColor(Theme.muted).layoutWeight(1)
                  TextInput({ text: this.passengersText }).width(90).height(46).type(InputType.Number).backgroundColor(Theme.bg)
                    .onChange((v: string) => { this.passengersText = v; this.previewText = ''; })
                }.width('100%')
                Text('车辆公里因子按载客人数折算为个人份额。').fontSize(11).fontColor(Theme.muted).width('100%')
              }
            }.width('100%').padding(22).backgroundColor(Theme.paper).borderRadius(24)
            SectionHeading({ title: '03  记下依据与日期', detail: this.conditionText().length > 0 ? '依据必填' : '备注可选' })
            Column({ space: 14 }) {
              Row({ space: 10 }) {
                Text('发生日期').fontSize(12).fontColor(Theme.muted).width(60)
                TextInput({ text: this.dateText }).id('record-date').fontSize(13).height(48).layoutWeight(1).backgroundColor(Theme.bg)
                  .onChange((v: string) => { this.dateText = v; this.previewText = ''; this.errMsg = ''; })
              }.width('100%')
              Row({ space: 12 }) {
                Text('今天').fontSize(12).fontColor(Theme.green).padding(10).backgroundColor(Theme.sage).borderRadius(14)
                  .onClick(() => { this.dateText = DateUtil.today(); this.previewText = ''; this.errMsg = ''; })
                Text('昨天').fontSize(12).fontColor(Theme.green).padding(10).backgroundColor(Theme.sage).borderRadius(14)
                  .onClick(() => { this.dateText = DateUtil.addDays(DateUtil.today(), -1); this.previewText = ''; this.errMsg = ''; })
              }.width('100%')
              TextInput({ text: this.remark, placeholder: this.conditionText().length > 0 ? '填写数量、原本情景及实际处理／采购依据' : '比如：今天骑车去图书馆' }).id('record-evidence').fontSize(13).height(52).backgroundColor(Theme.bg)
                .onChange((v: string) => { this.remark = v; })
            }.width('100%').padding(20).backgroundColor(Theme.paper).borderRadius(24)
            if (this.conditionText().length > 0) {
              Notice({ text: this.conditionText(), warning: true }).margin({ top: 20 })
              Row({ space: 10 }) {
                Checkbox({ name: 'applicability' }).id('record-applicability').select(this.applicabilityAccepted).selectedColor(Theme.green)
                  .onChange((v: boolean) => { this.applicabilityAccepted = v; })
                Text('我确认本次行为满足以上条件，数量与依据如实填写。').fontSize(12).lineHeight(22).fontColor(Theme.muted).layoutWeight(1)
              }.width('100%').margin({ top: 14 })
            }
          }
          }.width('100%').alignItems(HorizontalAlign.Start).enabled(!this.saving && this.savedRecordId.length === 0 && this.planReady)
          if (this.savedRecordId.length > 0) { Notice({ text: '这笔记录已入账，表单已锁定。可重试关联计划，也可返回存折查看凭证。' }).margin({ top: 16 }) }
          if (this.previewText.length > 0) { Notice({ text: this.previewText, warning: !this.previewOk }).margin({ top: 20 }) }
          if (this.errMsg.length > 0) { Notice({ text: this.errMsg, warning: true }).margin({ top: 16 }) }
          if (this.hasUsableFactor()) {
            Row({ space: 12 }) {
              Button('先算一算').fontSize(14).height(52).fontColor(Theme.green).backgroundColor(Theme.sage).layoutWeight(1)
                .enabled(!this.saving && this.savedRecordId.length === 0).onClick(() => this.doPreview())
              Button(this.saving ? '正在存入…' : (this.savedRecordId.length > 0 ? '重试关联计划' : '存入我的存折'))
                .fontSize(14).height(52).backgroundColor(Theme.green).layoutWeight(1.4).enabled(!this.saving && this.planReady).onClick(() => this.save())
            }.width('100%').margin({ top: 28 })
          }
          Text('数量由你填写，未独立核实；估算结果不构成经核证碳资产。').fontSize(11).lineHeight(20).fontColor(Theme.muted)
            .width('100%').margin({ top: 18, bottom: 30 })
        }.width('100%').padding({ left: 22, right: 22 }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(Theme.bg)
  }

  private unitOfSelected(): string {
    const f = this.selectedFactor();
    if (f === undefined) {
      return '';
    }
    return f.perUnit;
  }

  /** 当前类别是否有适用且允许在本构建中使用的因子 */
  private hasUsableFactor(): boolean {
    return this.category === BehaviorCategory.TRAVEL
      ? this.baselineCandidates().length > 0 && this.actualCandidates().length > 0
      : this.singleCandidates().length > 0;
  }

  private baselineUsesVkm(): boolean {
    const f = this.factorOf(this.baselineCode);
    return f !== undefined && f.distanceBasis === 'vkm';
  }
}
