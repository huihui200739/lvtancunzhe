import { router, promptAction } from '@kit.ArkUI';
import { LedgerDb } from '../services/LedgerDb';
import { PlanService } from '../services/PlanService';
import { PlanTask } from '../models/PlanModels';
import { DateUtil } from '../common/Format';
import { Theme } from '../common/Theme';
import { SubpageHeader, PageIntro, Notice } from '../components/DesignSystem';

interface ParticipationParams { planTaskId: string; }
@Entry
@Component
struct ParticipationPage {
  @State task: PlanTask | null = null;
  @State evidence: string = '';
  @State confirmed: boolean = false;
  @State saving: boolean = false;
  @State message: string = '';
  private taskId: string = '';
  aboutToAppear(): void {
    const p = router.getParams() as ParticipationParams;
    this.taskId = p ? p.planTaskId : '';
    LedgerDb.get().getPlanTask(this.taskId).then((task: PlanTask | null) => {
      this.task = task;
      if (task === null) { this.message = '找不到这项任务。'; }
    }).catch((e: Error) => { this.message = e.message; });
  }
  private async save(): Promise<void> {
    if (this.saving || this.task === null || !this.confirmed) { return; }
    this.saving = true;
    try {
      const res = await PlanService.completeParticipation(LedgerDb.get(), this.taskId, this.task.day, this.evidence);
      if (!res.ok) { this.message = res.message; return; }
      promptAction.showToast({ message: '参与已记录；未生成减排量。' }); router.back();
    } catch (e) { this.message = `记录失败：${(e as Error).message}`; }
    finally { this.saving = false; }
  }
  build() {
    Column() {
      SubpageHeader({ title: '记下这次参与' })
      Scroll() {
        Column({ space: 20 }) {
          PageIntro({ title: '行动本身，也值得记下', subtitle: '这是一项参与任务，不生成碳减排数值。', eyebrow: '七日计划 / 参与记录' })
          if (this.task !== null) {
            Column({ space: 12 }) {
              Text(this.task.name).fontSize(20).fontColor(Theme.ink).width('100%')
              Text(`安排日期 ${this.task.day}`).fontSize(12).fontColor(Theme.muted).width('100%')
              Text(this.task.reason).fontSize(13).lineHeight(23).fontColor(Theme.muted).width('100%')
            }.width('100%').padding(22).backgroundColor(Theme.paper).borderRadius(24)
            TextArea({ text: this.evidence, placeholder: '写下这次完成的行为、数量和完成方式，留下可以回看的参与说明。' })
              .fontSize(14).height(160).padding(18).backgroundColor(Theme.paper).borderRadius(22).maxLength(500)
              .onChange((v: string) => { this.evidence = v; })
            Row({ space: 12 }) {
              Checkbox({ name: 'participation' }).select(this.confirmed).selectedColor(Theme.green)
                .onChange((v: boolean) => { this.confirmed = v; })
              Text('我确认这项行为已真实完成。说明由我填写，未独立核实。').fontSize(12).lineHeight(21).fontColor(Theme.muted).layoutWeight(1)
            }.width('100%')
            Notice({ text: '仅按规则记录参与并发放参与积分。不会创建减排凭证，不计入 kg 目标或碳资产。' })
            if (DateUtil.isFuture(this.task.day)) { Notice({ text: '安排日期尚未到来，请在完成当天记录。', warning: true }) }
            Button(this.saving ? '正在记录…' : '确认记录参与').width('100%').height(52).fontSize(15).backgroundColor(Theme.green)
              .enabled(this.confirmed && this.evidence.trim().length > 0 && !this.saving && !DateUtil.isFuture(this.task.day))
              .onClick(() => this.save())
          }
          if (this.message.length > 0) { Notice({ text: this.message, warning: true }) }
        }.width('100%').padding({ left: 22, right: 22, bottom: 30 }).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(Theme.bg)
  }
}
