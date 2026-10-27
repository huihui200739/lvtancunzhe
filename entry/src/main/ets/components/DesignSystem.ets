import { DEV_FACTOR_MODE } from '../common/BuildConfig';
import { router } from '@kit.ArkUI';
import { Theme, iconResource } from '../common/Theme';

@Component
export struct DevelopmentBanner {
  build() {
    Column() {
      if (DEV_FACTOR_MODE) {
        Text('开发预览 · 含未核验因子，仅供联调，不用于参赛材料').fontSize(10).fontColor(Theme.rust)
          .width('100%').textAlign(TextAlign.Center).padding(7).backgroundColor('#FAEEE5')
      }
    }.width('100%')
  }
}

@Component
export struct AppIcon {
  @Prop name: string = 'leaf';
  @Prop iconSize: number = 22;
  @Prop color: string = Theme.green;
  build() {
    Image(iconResource(this.name, this.color)).width(this.iconSize).height(this.iconSize)
      .objectFit(ImageFit.Contain).draggable(false)
      .opacity(this.color === Theme.muted || this.color === '#89968A' || this.color === '#B2BDAA' ? 0.55 : 1)
      .accessibilityLevel('no')
  }
}

@Component
export struct PageIntro {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop eyebrow: string = '绿碳存折';
  build() {
    Column({ space: 8 }) {
      Text(this.eyebrow).fontSize(11).letterSpacing(2).fontColor(Theme.muted)
      Text(this.title).fontSize(29).fontWeight(FontWeight.Medium).fontColor(Theme.ink)
      if (this.subtitle.length > 0) {
        Text(this.subtitle).fontSize(13).lineHeight(21).fontColor(Theme.muted)
      }
    }.alignItems(HorizontalAlign.Start).width('100%').margin({ top: 14, bottom: 28 })
  }
}

@Component
export struct SectionHeading {
  @Prop title: string = '';
  @Prop detail: string = '';
  build() {
    Row() {
      Text(this.title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(Theme.ink).layoutWeight(1)
      Text(this.detail).fontSize(11).fontColor(Theme.muted)
    }.width('100%').margin({ top: 28, bottom: 16 })
  }
}

@Component
export struct Notice {
  @Prop text: string = '';
  @Prop warning: boolean = false;
  build() {
    Text(this.text).fontSize(12).lineHeight(20)
      .fontColor(this.warning ? Theme.rust : Theme.muted).width('100%')
      .padding(14).backgroundColor(this.warning ? '#FAEEE5' : Theme.sage).borderRadius(16)
  }
}

@Component
export struct EmptyState {
  @Prop title: string = '从一件小事开始';
  @Prop detail: string = '';
  build() {
    Column({ space: 12 }) {
      AppIcon({ name: 'leaf', iconSize: 30, color: '#91A681' })
      Text(this.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(Theme.ink)
      Text(this.detail).fontSize(13).lineHeight(22).fontColor(Theme.muted).textAlign(TextAlign.Center)
    }.width('100%').padding({ top: 32, bottom: 32, left: 24, right: 24 })
      .backgroundColor(Theme.paper).borderRadius(24)
  }
}

@Component
export struct SubpageHeader {
  @Prop title: string = '';
  build() {
    Column() {
      DevelopmentBanner()
      Row({ space: 14 }) {
      Button({ type: ButtonType.Normal }) {
        AppIcon({ name: 'back', iconSize: 22 })
      }.width(44).height(44).backgroundColor(Theme.paper).borderRadius(22)
        .accessibilityText('返回上一页').onClick(() => router.back())
      Text(this.title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(Theme.ink)
    }.width('100%').padding({ left: 22, right: 22, top: 10, bottom: 12 }).backgroundColor(Theme.bg)
    }.width('100%')
  }
}

@Component
export struct BreathingPlant {
  @Prop @Watch('updateMotion') active: boolean = true;
  @StorageLink('gentleMotion') @Watch('updateMotion') gentleMotion: boolean = true;
  @State growth: number = 1;
  private startTimer: number = -1;
  aboutToAppear(): void {
    // Schedule after the first frame: aboutToAppear runs before the scale's initial value is mounted.
    this.startTimer = setTimeout(() => { this.startTimer = -1; this.updateMotion(); }, 100);
  }
  aboutToDisappear(): void {
    if (this.startTimer >= 0) { clearTimeout(this.startTimer); this.startTimer = -1; }
    this.getUIContext().animateTo({ duration: 0, iterations: 1 }, () => { this.growth = 1; });
  }
  private updateMotion(): void {
    this.getUIContext().animateTo({ duration: 0, iterations: 1 }, () => { this.growth = 1; });
    if (this.active && this.gentleMotion) {
      this.getUIContext().animateTo({ duration: 3600, curve: Curve.EaseInOut,
        iterations: -1, playMode: PlayMode.Alternate }, () => { this.growth = 1.045; });
    }
  }
  build() {
    Image($r('app.media.botanical')).objectFit(ImageFit.Contain).draggable(false)
      .width(142).height(202).scale({ x: this.growth, y: this.growth })
      .accessibilityLevel('no')
  }
}
