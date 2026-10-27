import { Theme } from '../common/Theme';
import { AppIcon, PageIntro, SectionHeading, Notice, EmptyState, SubpageHeader } from '../components/DesignSystem';
import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { LedgerDb } from '../services/LedgerDb';
import { RewardService } from '../services/RewardService';
import { BackupService } from '../services/BackupService';
import { CertParams } from '../models/UiModels';
import { CertificateView } from '../models/PointModels';
import { Result } from '../common/AppError';
import { NumUtil } from '../common/Format';

/**
 * 虚拟植树成就证书（第 9.1 节、B3）：显示编号、日期与用户记录范围，
 * 明确不代表真实植树，也不代表正式碳权益；可经由系统保存入口交给用户。
 */
@Entry
@Component
struct CertificatePage {
  @State cert: CertificateView | null = null;
  @State message: string = '';

  aboutToAppear(): void {
    const p = router.getParams() as CertParams;
    const id = (p !== null && p !== undefined) ? `${p.redemptionId}` : '';
    this.load(id);
  }

  private async load(redemptionId: string): Promise<void> {
    const res: Result<CertificateView> = await RewardService.certificate(LedgerDb.get(), redemptionId);
    if (!res.ok || res.data === null) {
      this.message = res.message;
      return;
    }
    this.cert = res.data;
  }

  private certificateText(): string {
    if (this.cert === null) {
      return '';
    }
    const c = this.cert;
    return `【虚拟植树成就证书】\n证书编号：${c.serial}\n奖励名称：${c.rewardName}\n出具时间：${c.issuedAt}\n当前账本正向贡献：${c.reductionSummary}\n有效记录条数：${c.recordCount}\n${c.scopeNote}\n声明：${c.disclaimer}\n`;
  }

  private async save(): Promise<void> {
    if (this.cert === null) {
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    const res = await BackupService.saveAs(ctx, `${this.cert.serial}.txt`, this.certificateText());
    promptAction.showToast({ message: res.ok ? '证书已保存。' : res.message });
  }

  build() {
    Column() {
      SubpageHeader({ title: '收藏这一份坚持' })
      if (this.cert === null) {
        EmptyState({ title: '正在准备你的成就', detail: this.message }).margin(22)
      } else {
        Scroll() {
          Column({ space: 22 }) {
            Column({ space: 18 }) {
              Text('GREEN ACHIEVEMENT').fontSize(10).letterSpacing(3).fontColor(Theme.muted)
              Image($r('app.media.botanical')).width(140).height(210).objectFit(ImageFit.Contain).accessibilityLevel('no')
              Text('你的小小坚持\n正在长成一片绿').fontSize(26).lineHeight(38).fontWeight(FontWeight.Medium).fontColor(Theme.ink).textAlign(TextAlign.Center)
              Text(this.cert.rewardName).fontSize(15).fontColor(Theme.green).margin({ top: 4 })
              Text('应用内虚拟成就证书').fontSize(11).fontColor(Theme.muted)
              Divider().color(Theme.line).margin({ top: 10, bottom: 8 })
              Text(this.cert.serial).fontSize(10).fontColor(Theme.muted).textAlign(TextAlign.Center)
              Text(this.cert.issuedAt).fontSize(11).fontColor(Theme.muted)
            }.width('100%').padding({ left: 28, right: 28, top: 30, bottom: 28 }).backgroundColor(Theme.paper).borderRadius(28)
              .border({ width: 1, color: Theme.line })
            Column({ space: 12 }) {
              Text('此刻，存折里的绿色足迹').fontSize(16).fontColor(Theme.ink).width('100%')
              Text(this.cert.reductionSummary).fontSize(22).fontWeight(FontWeight.Medium).fontColor(Theme.green).width('100%')
              Text(`${this.cert.recordCount} 条有效记录 · 不同气体口径分别列示`).fontSize(11).fontColor(Theme.muted).width('100%')
            }.width('100%').padding(22).backgroundColor(Theme.sage).borderRadius(24)
            Text(this.cert.disclaimer).fontSize(12).lineHeight(21).fontColor(Theme.muted).width('100%')
            Button('保存证书文字到文件').height(52).fontSize(14).backgroundColor(Theme.green).width('100%').onClick(() => this.save())
            Text('虚拟成就，不代表真实植树或正式碳权益。').fontSize(10).fontColor(Theme.muted).margin({ bottom: 12 })
          }.width('100%').padding({ left: 22, right: 22, top: 14, bottom: 24 })
        }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
      }
    }.width('100%').height('100%').backgroundColor(Theme.bg)
  }

  @Builder
  line(k: string, v: string) {
    Row() {
      Text(k).fontSize(12).fontColor('#888888').width(120)
      Text(v).fontSize(12).fontColor('#333333').layoutWeight(1)
    }
    .width('100%')
    .margin({ bottom: 4 })
  }
}
