import { Passbook } from '../common/Theme';

/**
 * 印章：存折上的“盖章”语义，只表示记账状态（来源已核、撤销等），不作装饰。
 * stampIn 为 true 时首次出现会有一次落章动作；关闭“柔和动效”后直接显示。
 */
@Component
export struct Seal {
  @Prop label: string = '核';
  @Prop sealSize: number = 22;
  @Prop angle: number = -12;
  @Prop color: string = Passbook.seal;
  @Prop stampIn: boolean = false;
  @StorageLink('gentleMotion') gentleMotion: boolean = true;
  @State pressScale: number = 1;
  @State pressOpacity: number = 0.86;
  aboutToAppear(): void {
    if (this.stampIn && this.gentleMotion) {
      this.pressScale = 2.2;
      this.pressOpacity = 0;
    }
  }
  build() {
    Text(this.label)
      .fontSize(this.sealSize * (this.label.length > 1 ? 0.34 : 0.5))
      .fontWeight(FontWeight.Bold).fontColor(this.color)
      .textAlign(TextAlign.Center)
      .width(this.sealSize).height(this.sealSize)
      .border({ width: Math.max(1, this.sealSize * 0.06), color: this.color })
      .borderRadius(this.sealSize / 2)
      .rotate({ angle: this.angle })
      .scale({ x: this.pressScale, y: this.pressScale })
      .opacity(this.pressOpacity)
      .onAppear(() => {
        if (this.pressScale !== 1) {
          setTimeout(() => {
            this.getUIContext().animateTo({ duration: 420, curve: Curve.Friction }, () => {
              this.pressScale = 1;
              this.pressOpacity = 0.86;
            });
          }, 260);
        }
      })
      .accessibilityText(`印章：${this.label}`)
  }
}

/** 账页双线：表头与正文之间的分隔。 */
@Component
export struct DoubleRule {
  @Prop color: string = Passbook.ruleStrong;
  build() {
    Column({ space: 2 }) {
      Row().width('100%').height(1).backgroundColor(this.color)
      Row().width('100%').height(0.5).backgroundColor(this.color)
    }.width('100%')
  }
}

/** 首页卡面下方的小栏位；用 @Prop 组件而非按值传参的 @Builder，数据加载后才会刷新。 */
@Component
export struct HeroStat {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop unit: string = '';
  build() {
    Column({ space: 2 }) {
      Text(this.label).fontSize(10).letterSpacing(1).fontColor('#5A606B')
      Row({ space: 3 }) {
        Text(this.value).fontSize(20).fontFamily(Passbook.numeral).fontColor(Passbook.print).maxLines(1)
        if (this.unit.length > 0) { Text(this.unit).fontSize(10).fontColor('#5A606B').margin({ bottom: 3 }) }
      }.alignItems(VerticalAlign.Bottom)
    }.width('100%').alignItems(HorizontalAlign.Center)
  }
}

/** 结余卡下方的小栏位；用 @Prop 组件而非按值传参的 @Builder，数据加载后才会刷新。 */
@Component
export struct StatCell {
  @Prop label: string = '';
  @Prop value: string = '';
  build() {
    Column({ space: 4 }) {
      Text(this.label).fontSize(10).fontColor(Passbook.faint)
      Text(this.value).fontSize(16).fontFamily(Passbook.mono).fontColor(Passbook.print).maxLines(1)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

/** 虚线：存单的撕边与分栏。 */
@Component
export struct DashedRule {
  @Prop color: string = Passbook.ruleStrong;
  build() {
    Row().width('100%').height(1)
      .border({ width: { top: 1 }, color: this.color, style: BorderStyle.Dashed })
  }
}
