import { promptAction } from '@kit.ArkUI';
import { Theme } from '../common/Theme';
import { AppIcon, PageIntro, SectionHeading, Notice, EmptyState, SubpageHeader } from '../components/DesignSystem';
import { router } from '@kit.ArkUI';
import { LedgerDb } from '../services/LedgerDb';
import { AppService } from '../services/AppService';
import { PlanService } from '../services/PlanService';
import { PlanDraftState } from '../services/PlanDraftState';
import { QuantityField } from './QuantityField';
import { PlanConstraints, PlanOutcome, PlanTask } from '../models/PlanModels';
import { BehaviorCategory, PlanTaskStatus, categoryName } from '../common/Domain';
import { DateUtil, NumUtil } from '../common/Format';

function emptyOutcome(): PlanOutcome {
  return {
    ok: false,
    code: '',
    message: '',
    plan: null,
    tasks: [],
    plannedKg: 0,
    gapKg: 0,
    participationCount: 0,
    targetMet: false,
    trace: []
  };
}

interface DayGroup {
  day: string;
  tasks: PlanTask[];
}

interface KeyLabel {
  key: string;
  label: string;
}

/**
 * 计划 Tab（第 4.2 节 I2）：约束表单 → 规则筛选 → 任务组合 → 原因说明 → 执行关联。
 * 约束改变会改变结果；无解时如实提示；同一行为不重复计入多个任务。
 */
@Component
export struct PlanTab {
  @Prop @Watch('onTick') tick: number = 0;
  private formLoaded: boolean = false;
  @State showSettings: boolean = false;
  @State generating: boolean = false;
  @State commuteKmText: string = '5';
  @State targetText: string = '5';
  @State selectedScope: string = '';
  private scopeOptions: KeyLabel[] = [{ key: '', label: '自动选择' }, { key: 'CO2', label: 'CO₂' }, { key: 'CO2e', label: 'CO₂e' }];
  @State minutesText: string = '120';
  @State costText: string = '20';
  @State accepted: string[] = ['travel', 'water_energy', 'recycling', 'food'];
  @State usual: string = 'drive_gasoline';
  @State availDays: string[] = [];
  @State outcome: PlanOutcome = emptyOutcome();
  @State hasOutcome: boolean = false;
  @State showTrace: boolean = false;
  @State message: string = '';
  @State savedFormKey: string = '';

  private catOptions: KeyLabel[] = [
    { key: 'travel', label: '出行' },
    { key: 'water_energy', label: '节水节电' },
    { key: 'recycling', label: '旧物回收' },
    { key: 'food', label: '光盘行动' }
  ];

  private usualOptions: KeyLabel[] = [
    { key: 'drive_gasoline', label: '驾车' },
    { key: 'bus', label: '公交' },
    { key: 'metro', label: '地铁' },
    { key: 'bike', label: '骑行' },
    { key: 'walk', label: '步行' }
  ];

  aboutToAppear(): void {
    this.loadLatest();
  }

  onTick(): void {
    // 从「完成并录入」等子页返回时，重新读取已持久化的最新计划，
    // 同一计划只更新任务；恢复了另一份计划时同步加载其条件。
    this.loadLatest();
  }

  private week(): string[] {
    const out: string[] = [];
    const today = DateUtil.today();
    for (let i = 0; i < 7; i++) {
      out.push(DateUtil.addDays(today, i));
    }
    return out;
  }

  private async loadLatest(): Promise<void> {
    if (!AppService.isReady()) {
      this.message = '数据库尚未就绪。';
      return;
    }
    try {
      const latest = await PlanService.latestPlan(LedgerDb.get());
      if (latest !== null) {
        if (latest.plan !== null && this.outcome.plan !== null && latest.plan.planId === this.outcome.plan.planId) {
          latest.trace = this.outcome.trace;
        }
        if (!this.generating && latest.plan !== null && (!this.formLoaded || PlanDraftState.planChanged(this.outcome.plan, latest.plan))) {
          const saved = JSON.parse(latest.plan.constraintsJson) as PlanConstraints;
          this.targetText = `${saved.targetKg}`;
          this.selectedScope = saved.gasScope;
          this.minutesText = `${saved.budgetMinutes}`;
          this.costText = `${saved.budgetCost}`;
          this.usual = saved.usualTravelSubItem;
          this.commuteKmText = `${saved.usualTravelKm}`;
          this.accepted = saved.acceptedCategories;
          this.availDays = saved.availableDays;
          this.formLoaded = true;
          this.savedFormKey = this.formKey();
        }
        this.outcome = latest; this.hasOutcome = true;
      } else {
        this.outcome = emptyOutcome(); this.hasOutcome = false;
        this.formLoaded = false; this.savedFormKey = '';
      }
    } catch (e) { this.message = `读取计划失败：${(e as Error).message}`; }
  }

  private buildConstraints(): PlanConstraints {
    const cats: BehaviorCategory[] = [];
    for (const c of this.accepted) {
      cats.push(c as BehaviorCategory);
    }
    const target = NumUtil.parseQuantity(this.targetText);
    const minutes = NumUtil.parseQuantity(this.minutesText);
    const cost = NumUtil.parseQuantity(this.costText);
    return {
      startDay: DateUtil.today(),
      targetKg: target,
      gasScope: this.selectedScope,
      budgetMinutes: minutes,
      budgetCost: cost,
      availableDays: this.availDays,
      acceptedCategories: cats,
      usualTravelSubItem: this.usual,
      usualTravelKm: NumUtil.parseQuantity(this.commuteKmText),
      excludedTemplateIds: []
    };
  }

  private async generate(replan: boolean): Promise<void> {
    if (!AppService.isReady()) {
      this.message = '数据库尚未就绪。';
      return;
    }
    if (this.generating) { return; }
    if (!Number.isFinite(NumUtil.parseQuantity(this.commuteKmText)) || NumUtil.parseQuantity(this.commuteKmText) <= 0) { this.message = '请填写大于 0 的通勤距离。'; return; }
    const target = NumUtil.parseQuantity(this.targetText);
    const minutes = NumUtil.parseQuantity(this.minutesText);
    const cost = NumUtil.parseQuantity(this.costText);
    if (!Number.isFinite(target) || target <= 0 || !Number.isFinite(minutes) || minutes < 0 || !Number.isFinite(cost) || cost < 0) { this.message = '目标应大于 0，时间和费用应为有效的非负数字。'; return; }
    this.generating = true;
    this.message = '';
    try {
    const db = LedgerDb.get();
    const repo = AppService.repo();
    const constraints = this.buildConstraints();
    const submittedKey = PlanDraftState.key(constraints);
    const res = replan
      ? await PlanService.replan(db, repo, constraints)
      : await PlanService.generatePlan(db, repo, constraints);
    if (!res.ok || res.data === null) {
      this.message = res.message;
      return;
    }
    if (res.data.plan !== null) {
      this.outcome = res.data;
      this.hasOutcome = true;
      this.formLoaded = true;
      this.savedFormKey = submittedKey;
    }
    if (!res.data.ok) {
      this.message = res.data.message;
    }
    } catch (e) { this.message = `安排未完成：${(e as Error).message}`; }
    finally { this.generating = false; }
  }

  private planUnit(): string {
    if (this.outcome.plan !== null) {
      try { const c = JSON.parse(this.outcome.plan.constraintsJson) as PlanConstraints; return c.gasScope === 'CO2e' ? 'kgCO₂e' : (c.gasScope === 'CO2' ? 'kgCO₂' : 'kg（暂无核算口径）'); } catch (e) { return 'kg'; }
    }
    return 'kg';
  }

  private formKey(): string { return PlanDraftState.key(this.buildConstraints()); }

  private draftChanged(): boolean {
    return this.hasOutcome && this.savedFormKey.length > 0 && this.formKey() !== this.savedFormKey;
  }

  private planPeriod(): string {
    if (this.outcome.plan === null) { return ''; }
    try {
      const saved = JSON.parse(this.outcome.plan.constraintsJson) as PlanConstraints;
      return `${saved.startDay} — ${DateUtil.addDays(saved.startDay, 6)} · 目标 ${NumUtil.show(saved.targetKg)} ${this.planUnit()}`;
    } catch (e) { return ''; }
  }

  private groups(): DayGroup[] {
    const out: DayGroup[] = [];
    let current: DayGroup | null = null;
    for (const t of this.outcome.tasks) {
      if (current === null || current.day !== t.day) {
        current = { day: t.day, tasks: [] };
        out.push(current);
      }
      current.tasks.push(t);
    }
    return out;
  }

  /** 分组内容签名：任一任务状态 / 实际减排变化都会改变签名，驱动 ForEach 重建该项 */
  private groupKey(g: DayGroup): string {
    let sig = g.day;
    for (const t of g.tasks) {
      sig = sig + `|${t.planTaskId}:${t.status}:${t.actualKg}:${t.rewarded}`;
    }
    return sig;
  }

  private statusLabel(s: PlanTaskStatus): string {
    if (s === PlanTaskStatus.COMPLETED) {
      return '已完成';
    } else if (s === PlanTaskStatus.LINKED) {
      return '已关联记录';
    } else if (s === PlanTaskStatus.SKIPPED) {
      return '已跳过';
    } else if (s === PlanTaskStatus.IN_PROGRESS) {
      return '进行中';
    }
    return '计划中';
  }

  build() {
    Scroll() {
      Column() {
        PageIntro({ title: '把改变，放进这七天', subtitle: '从你愿意做的事开始，找到适合自己的节奏。', eyebrow: '我的行动计划 / 07 DAYS' })
        Column({ space: 14 }) {
          Row() {
            AppIcon({ name: 'plan', iconSize: 24 })
            Text('为这一周，定个小目标').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Theme.ink).margin({ left: 10 })
          }.width('100%')
          QuantityField({ value: $targetText, unit: 'kg / 七天', label: '计划目标' })
          Text('预计减排目标 · 每份计划只使用一种气体口径').fontSize(11).fontColor(Theme.muted).width('100%')
          Row({ space: 8 }) {
            ForEach(this.scopeOptions, (c: KeyLabel) => {
              Text(c.label).fontSize(12).fontColor(this.selectedScope === c.key ? Theme.paper : Theme.green)
                .padding({ left: 15, right: 15, top: 10, bottom: 10 }).borderRadius(18)
                .backgroundColor(this.selectedScope === c.key ? Theme.green : Theme.bg).onClick(() => { this.selectedScope = c.key; })
            }, (c: KeyLabel) => c.key)
          }.width('100%')
          Row() {
            Flex({ wrap: FlexWrap.Wrap }) {
              Text(`时间 ${this.minutesText} 分钟`).fontSize(12).fontColor(Theme.ink).margin({ right: 8 })
              Text(`费用 ${this.costText} 元`).fontSize(12).fontColor(Theme.ink)
            }.layoutWeight(1)
            Text(this.showSettings ? '收起设置 ↑' : '调整偏好 ↓').fontSize(12).fontColor(Theme.green)
              .padding({ top: 12, bottom: 12 }).onClick(() => { this.showSettings = !this.showSettings; })
          }.width('100%')
          if (this.showSettings) {
            Row({ space: 12 }) {
              Column({ space: 8 }) {
                Text('额外时间 / 分钟').fontSize(11).fontColor(Theme.muted)
                TextInput({ text: this.minutesText }).id('plan-minutes').type(InputType.Number).height(46).backgroundColor(Theme.bg)
                  .onChange((v: string) => { this.minutesText = v; })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Column({ space: 8 }) {
                Text('额外费用 / 元').fontSize(11).fontColor(Theme.muted)
                TextInput({ text: this.costText }).id('plan-cost').type(InputType.Number).height(46).backgroundColor(Theme.bg)
                  .onChange((v: string) => { this.costText = v; })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%')
            Text('我愿意尝试').fontSize(13).fontColor(Theme.ink).width('100%').margin({ top: 8 })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.catOptions, (c: KeyLabel) => {
                Text(c.label).fontSize(12).fontColor(this.accepted.indexOf(c.key) >= 0 ? Theme.paper : Theme.muted)
                  .padding({ left: 14, right: 14, top: 11, bottom: 11 }).borderRadius(18)
                  .backgroundColor(this.accepted.indexOf(c.key) >= 0 ? Theme.green : Theme.bg).margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    const next = this.accepted.filter((k: string) => k !== c.key);
                    if (this.accepted.indexOf(c.key) < 0) { next.push(c.key); }
                    this.accepted = next;
                  })
              }, (c: KeyLabel) => c.key)
            }.width('100%')
            Text('平时如何出行').fontSize(13).fontColor(Theme.ink).width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.usualOptions, (c: KeyLabel) => {
                Text(c.label).fontSize(12).fontColor(this.usual === c.key ? Theme.paper : Theme.muted)
                  .padding({ left: 14, right: 14, top: 11, bottom: 11 }).borderRadius(18)
                  .backgroundColor(this.usual === c.key ? Theme.green : Theme.bg).margin({ right: 8, bottom: 8 })
                  .onClick(() => { this.usual = c.key; })
              }, (c: KeyLabel) => c.key)
            }.width('100%')
            Row({ space: 12 }) {
              Text('单次通勤 / km').fontSize(12).fontColor(Theme.muted).layoutWeight(1)
              TextInput({ text: this.commuteKmText }).width(100).height(46).type(InputType.Number).backgroundColor(Theme.bg)
                .onChange((v: string) => { this.commuteKmText = v; })
            }.width('100%')
            if (PlanDraftState.outsideWeek(this.availDays, this.week()).length > 0) {
              Text('以下已选日期不在接下来七天内，点击可移除；保留它们不会变成每天可用。').fontSize(11).lineHeight(18).fontColor(Theme.rust).width('100%')
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(PlanDraftState.outsideWeek(this.availDays, this.week()), (d: string) => {
                  Text(`${d} ×`).fontSize(11).fontColor(Theme.rust).padding(11).backgroundColor(Theme.bg).borderRadius(14)
                    .margin({ right: 6, bottom: 8 }).onClick(() => { this.availDays = this.availDays.filter((k: string) => k !== d); })
                }, (d: string) => d)
              }.width('100%')
            }
            Text('可用日期 · 不选表示每天都可以').fontSize(12).fontColor(Theme.muted).width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.week(), (d: string) => {
                Text(d.substring(5)).fontSize(11).fontColor(this.availDays.indexOf(d) >= 0 ? Theme.paper : Theme.muted)
                  .padding(11).borderRadius(14).backgroundColor(this.availDays.indexOf(d) >= 0 ? Theme.green : Theme.bg)
                  .margin({ right: 6, bottom: 8 }).onClick(() => {
                    const next = this.availDays.filter((k: string) => k !== d);
                    if (this.availDays.indexOf(d) < 0) { next.push(d); } this.availDays = next;
                  })
              }, (d: string) => d)
            }.width('100%')
          }
          if (this.draftChanged()) {
            Text('目标或偏好已修改，重新安排后更新下方计划。').fontSize(11).lineHeight(18)
              .fontColor(Theme.rust).width('100%')
          }
          Button(this.generating ? '正在安排…' : (this.hasOutcome ? '重新安排这一周' : '生成我的七日计划'))
            .width('100%').height(50).fontSize(15).fontWeight(FontWeight.Medium).backgroundColor(Theme.green)
            .enabled(!this.generating).onClick(() => { this.generate(this.hasOutcome); })
        }.width('100%').padding(22).backgroundColor(Theme.paper).borderRadius(26).alignItems(HorizontalAlign.Start)
        if (this.message.length > 0) { Notice({ text: this.message, warning: true }).margin({ top: 16 }) }
        if (this.hasOutcome && this.outcome.tasks.length > 0) {
          SectionHeading({ title: this.draftChanged() ? '上次保存的计划' : '这一周的绿色提案', detail: `${this.outcome.tasks.filter((t: PlanTask) => t.status !== PlanTaskStatus.SKIPPED).length} 项行动` })
          Column({ space: 8 }) {
            Text(this.planPeriod()).fontSize(11).lineHeight(18).fontColor(Theme.muted).width('100%')
            Text(`预计 ${NumUtil.show(this.outcome.plannedKg)} ${this.planUnit()}`).fontSize(26).fontColor(Theme.green).fontWeight(FontWeight.Medium)
            Text(this.outcome.targetMet ? '计划预计覆盖目标，完成后才计入实际记录' : `距离预计目标还差 ${NumUtil.show(this.outcome.gapKg)} ${this.planUnit()}`)
              .fontSize(12).lineHeight(20).fontColor(Theme.muted)
            if (this.outcome.participationCount > 0) {
              Text(`${this.outcome.participationCount} 项为参与任务，不计入预计减排目标。`).fontSize(11).fontColor(Theme.muted)
            }
          }.width('100%').padding(22).backgroundColor(Theme.sage).borderRadius(24).alignItems(HorizontalAlign.Start)
          ForEach(this.groups(), (g: DayGroup) => { this.dayGroup(g); }, (g: DayGroup) => this.groupKey(g))
          if (this.outcome.trace.length > 0) {
          Text(this.showTrace ? '收起安排依据 ↑' : '为什么这样安排 ↓').fontSize(12).fontColor(Theme.green)
            .padding({ top: 20, bottom: 20 }).onClick(() => { this.showTrace = !this.showTrace; })
          if (this.showTrace) {
            Column({ space: 10 }) {
              ForEach(this.outcome.trace, (line: string) => { Text(line).fontSize(12).lineHeight(21).fontColor(Theme.muted).width('100%') },
                (line: string, i: number) => `${i}-${line}`)
            }.width('100%').padding(20).backgroundColor(Theme.paper).borderRadius(22)
          }
          }
        } else if (!this.hasOutcome) {
          SectionHeading({ title: '留一点空间，给新的习惯' })
          EmptyState({ title: '不必一次做到很多', detail: '计划会综合时间、费用和出行习惯。\n遇到做不到的任务，随时跳过再重排。' })
        }
        Text('预计值来自当前可用因子；计划不会自动生成已完成记录。').fontSize(11).lineHeight(20).fontColor(Theme.muted)
          .width('100%').margin({ top: 24, bottom: 30 })
      }.width('100%').padding({ left: 22, right: 22 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Off).backgroundColor(Theme.bg)
  }

  @Builder
  dayGroup(g: DayGroup) {
    Column() {
      Text(`${g.day}`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .margin({ top: 10, bottom: 4 })
      ForEach(g.tasks, (t: PlanTask) => {
        this.taskCard(t);
      }, (t: PlanTask) => `${t.planTaskId}#${t.status}#${t.actualKg}`)
    }
    .width('100%')
  }

  @Builder
  taskCard(t: PlanTask) {
    Column() {
      Row() {
        Text(`${t.name}`).fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
        Text(this.statusLabel(t.status))
          .fontSize(11)
          .fontColor(t.status === PlanTaskStatus.COMPLETED ? Theme.green : Theme.muted)
      }
      .width('100%')
      Text(`${categoryName(t.category)}　额外 ${t.extraMinutes} 分钟 / ${NumUtil.show(t.extraCost)} 元　${t.participationOnly ? '参与任务' : `预计 ${NumUtil.show(t.expectedKg)} ${this.planUnit()}`}`)
        .fontSize(11)
        .fontColor(Theme.muted)
        .width('100%')
        .margin({ top: 4 })
      Text(t.reason)
        .fontSize(12)
        .lineHeight(21)
        .fontColor(Theme.ink)
        .width('100%')
        .margin({ top: 6 })
      if (t.status === PlanTaskStatus.COMPLETED) {
        Text(t.participationOnly && t.linkedRecordId.length === 0 ? '参与已记录 · 不计减排量' : `已关联记录，实际减排 ${NumUtil.show(t.actualKg)} ${this.planUnit()}`)
          .fontSize(11)
          .fontColor(Theme.green)
          .width('100%')
          .margin({ top: 4 })
        if (t.participationOnly && t.linkedRecordId.length === 0) {
          Button('撤销这次参与').fontSize(12).fontColor(Theme.rust).backgroundColor('#FAEEE5').height(42).margin({ top: 12 })
            .onClick(() => this.cancelParticipation(t.planTaskId))
        }
      } else if (t.status === PlanTaskStatus.PLANNED || t.status === PlanTaskStatus.IN_PROGRESS) {
        Row() {
          Button(t.participationOnly ? '记录参与' : '完成并录入')
            .fontSize(12)
            .height(42)
            .backgroundColor(Theme.green)
            .layoutWeight(1)
            .enabled(!DateUtil.isFuture(t.day))
            .onClick(() => {
              router.pushUrl({
                url: t.participationOnly ? 'pages/ParticipationPage' : 'pages/RecordEntry',
                params: { category: `${t.category}`, planTaskId: t.planTaskId }
              });
            })
          Button('这项做不到')
            .fontSize(12)
            .height(42)
            .backgroundColor('#829478')
            .layoutWeight(1)
            .margin({ left: 8 })
            .onClick(() => {
              this.skip(t.planTaskId);
            })
        }
        .width('100%')
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(20)
    .backgroundColor(Theme.paper)
    .borderRadius(22)
    .margin({ bottom: 8 })
  }

  private async cancelParticipation(planTaskId: string): Promise<void> {
    const confirm = await promptAction.showDialog({ title: '撤销参与记录', message: '参与积分将冲正，任务转为已跳过，可重新安排。',
      buttons: [{ text: '保留', color: Theme.green }, { text: '确认撤销', color: Theme.rust }] });
    if (confirm.index !== 1) { return; }
    const res = await PlanService.cancelParticipation(LedgerDb.get(), planTaskId);
    if (!res.ok) { this.message = res.message; return; }
    await this.loadLatest();
  }

  private async skip(planTaskId: string): Promise<void> {
    const res = await PlanService.skipTask(LedgerDb.get(), planTaskId);
    if (!res.ok) {
      this.message = res.message;
      return;
    }
    // 重新拉取当前计划
    await this.loadLatest();
  }
}
