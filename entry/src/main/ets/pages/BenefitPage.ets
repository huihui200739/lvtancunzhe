import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Theme, Passbook } from '../common/Theme';
import { Notice, SubpageHeader, SectionHeading } from '../components/DesignSystem';
import { Seal } from '../components/Passbook';
import { MockBenefitPlatform, MockBenefitAccount, MockBenefitSummary, MockPerk, MockRedemption, MockTransfer } from '../services/MockBenefitPlatform';
import { Ids } from '../common/Ids';
import { NumUtil } from '../common/Format';

/**
 * 模拟碳普惠平台页：显示从存折转存过来的凭证、模拟积分和可兑换的模拟权益。
 * 所有内容只存本机偏好文件，不联网、不写账本，也不影响应用内积分。
 */
@Entry
@Component
struct BenefitPage {
  @State account: MockBenefitAccount = MockBenefitPlatform.empty();
  @State summary: MockBenefitSummary = { earned: 0, spent: 0, balance: 0, transferCount: 0 };
  @State message: string = '';
  @State busy: boolean = false;

  aboutToAppear(): void {
    this.reload();
  }

  onPageShow(): void {
    this.reload();
  }

  private context(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private async reload(): Promise<void> {
    this.account = await MockBenefitPlatform.load(this.context());
    this.summary = MockBenefitPlatform.summary(this.account);
  }

  private async redeem(perk: MockPerk): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.summary.balance < perk.price) {
      this.message = `模拟积分不足：还差 ${perk.price - this.summary.balance} 分。`;
      return;
    }
    const confirm = await promptAction.showDialog({
      title: '兑换模拟权益',
      message: `用 ${perk.price} 个模拟积分兑换「${perk.name}」。这是演示流程，兑换码不能在任何平台使用。`,
      buttons: [{ text: '取消', color: Theme.muted }, { text: '兑换', color: Theme.ink }]
    });
    if (confirm.index !== 1) {
      return;
    }
    this.busy = true;
    const res = await MockBenefitPlatform.redeem(this.context(), perk.perkId, Ids.withPrefix('mockredeem'));
    this.busy = false;
    this.message = res.ok && res.data !== null ? `已兑换，演示兑换码 ${res.data.code}` : res.message;
    await this.reload();
  }

  build() {
    Column() {
      SubpageHeader({ title: '碳普惠平台（模拟）' })
      Scroll() {
        Column() {
          Stack({ alignContent: Alignment.TopStart }) {
            Image($r('app.media.note_cool')).width('100%').height('100%').objectFit(ImageFit.Cover)
              .draggable(false).accessibilityLevel('no')
            Column({ space: 6 }) {
              Row() {
                Text('MOCK CARBON INCLUSION').fontSize(10).letterSpacing(1.5).fontColor('#3A3F4A').layoutWeight(1)
                Seal({ label: '模拟', sealSize: 38, angle: -10, color: '#3B63E0' })
              }.width('100%')
              Text(MockBenefitPlatform.PLATFORM_NAME).fontSize(18).fontFamily(Passbook.serif).fontColor(Passbook.print)
              Row({ space: 6 }) {
                Text(`${this.summary.balance}`).fontSize(56).fontFamily(Passbook.numeral).fontColor(Passbook.print)
                Text('模拟积分').fontSize(12).fontColor('#3A3F4A').margin({ bottom: 12 })
              }.alignItems(VerticalAlign.Bottom)
              Blank()
              Row() {
                Text(`已转存 ${this.summary.transferCount} 笔`).fontSize(11).fontColor(Passbook.print).layoutWeight(1)
                Text(`累计 ${this.summary.earned} · 已用 ${this.summary.spent}`).fontSize(11).fontColor(Passbook.print)
              }.width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 }).backgroundColor('#8CFFFFFF').borderRadius(12)
            }.width('100%').height('100%').alignItems(HorizontalAlign.Start).padding({ left: 20, right: 20, top: 16, bottom: 16 })
          }
          .width('100%').height(240).borderRadius(Theme.heroRadius).clip(true).margin({ top: 8 })
          .border({ width: 0.5, color: '#1F16181D' })
          Notice({ text: MockBenefitPlatform.NOTICE, warning: true }).margin({ top: 14 })
          Text(`换算规则（演示假设）：每 0.1 kg 估算减排记 1 个模拟积分，同一记录版本只能转存一次。转存不改动存折账本和应用积分。`)
            .fontSize(11).lineHeight(18).fontColor(Theme.muted).width('100%').margin({ top: 10 })
          if (this.message.length > 0) { Notice({ text: this.message }).margin({ top: 12 }) }
          SectionHeading({ title: '可兑换的模拟权益', detail: '合作方均为虚构' })
          ForEach(MockBenefitPlatform.PERKS, (p: MockPerk) => {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text(p.name).fontSize(15).fontFamily(Passbook.serif).fontColor(Theme.ink)
                Text(`${p.partner} · ${p.description}`).fontSize(11).lineHeight(17).fontColor(Theme.muted)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Button(`${p.price} 分`).height(36).fontSize(12)
                .fontColor(this.summary.balance >= p.price ? '#FFFFFF' : Theme.muted)
                .backgroundColor(this.summary.balance >= p.price ? Passbook.print : Theme.sage)
                .enabled(!this.busy).onClick(() => this.redeem(p))
            }.width('100%').padding(16).margin({ bottom: 10 }).backgroundColor(Theme.paper).borderRadius(18)
          }, (p: MockPerk) => p.perkId)
          SectionHeading({ title: '转存记录', detail: `${this.account.transfers.length} 笔` })
          if (this.account.transfers.length === 0) {
            Text('还没有转存。打开存折里任一张已核验的凭证，点「转存到碳普惠平台」。').fontSize(12).lineHeight(19)
              .fontColor(Theme.muted).width('100%').padding(16).backgroundColor(Theme.paper).borderRadius(18)
          } else {
            Column() {
              ForEach(this.account.transfers.slice().reverse(), (t: MockTransfer) => {
                Row() {
                  Column({ space: 2 }) {
                    Text(t.requestId).fontSize(12).fontFamily(Passbook.numeral).fontColor(Theme.ink)
                    Text(`${t.createdAt} · 第 ${t.revision} 版 · ${NumUtil.show(t.amountKg)} ${MockBenefitPlatform.unitText(t)}`)
                      .fontSize(10).fontColor(Theme.muted)
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Text(`+${t.credits}`).fontSize(16).fontFamily(Passbook.numeral).fontColor(Theme.ink)
                }.width('100%').padding({ top: 12, bottom: 12 })
                Divider().color(Theme.line)
              }, (t: MockTransfer) => t.requestId)
            }.width('100%').padding({ left: 16, right: 16 }).backgroundColor(Theme.paper).borderRadius(18)
          }
          if (this.account.redemptions.length > 0) {
            SectionHeading({ title: '兑换记录', detail: '演示兑换码' })
            Column() {
              ForEach(this.account.redemptions.slice().reverse(), (r: MockRedemption) => {
                Row() {
                  Column({ space: 2 }) {
                    Text(r.perkName).fontSize(13).fontColor(Theme.ink)
                    Text(`${r.createdAt} · ${r.code}`).fontSize(10).fontFamily(Passbook.numeral).fontColor(Theme.muted)
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Text(`-${r.price}`).fontSize(16).fontFamily(Passbook.numeral).fontColor(Theme.rust)
                }.width('100%').padding({ top: 12, bottom: 12 })
                Divider().color(Theme.line)
              }, (r: MockRedemption) => r.requestId)
            }.width('100%').padding({ left: 16, right: 16 }).backgroundColor(Theme.paper).borderRadius(18)
          }
          Text('本页数据只保存在这台设备上，卸载应用即清除；不进入账本备份或 CSV 导出。').fontSize(11).lineHeight(18)
            .fontColor(Theme.muted).width('100%').margin({ top: 18, bottom: 30 })
        }.width('100%').padding({ left: 24, right: 24 }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(Theme.bg)
  }
}
