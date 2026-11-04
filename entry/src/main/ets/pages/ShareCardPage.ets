import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { Theme, Passbook, categoryHue } from '../common/Theme';
import { Notice, SubpageHeader, PageIntro, EmptyState } from '../components/DesignSystem';
import { Seal } from '../components/Passbook';
import { LedgerDb } from '../services/LedgerDb';
import { ShareCardService, ShareCardData, ShareCardScope, ShareCardLine } from '../services/ShareCardService';
import { NumUtil } from '../common/Format';

const CARD_ID: string = 'share-card';

/**
 * 七日分享卡：把近七天的分口径汇总渲染成一张存折票面，用系统「保存到图库」控件存成图片，
 * 由用户自己决定发到哪里。卡面不含记录编号、备注或任何身份信息。
 */
@Entry
@Component
struct ShareCardPage {
  @State card: ShareCardData | null = null;
  @State message: string = '';
  @State saved: string = '';

  aboutToAppear(): void {
    ShareCardService.build(LedgerDb.get()).then((res) => {
      if (res.ok && res.data !== null) { this.card = res.data; } else { this.message = res.message; }
    });
  }

  private async saveImage(): Promise<void> {
    try {
      const pixelMap: image.PixelMap = await this.getUIContext().getComponentSnapshot().get(CARD_ID, { scale: 2 });
      const data: ArrayBuffer = await image.createImagePacker().packToData(pixelMap, { format: 'image/png', quality: 100 });
      pixelMap.release();
      const helper = photoAccessHelper.getPhotoAccessHelper(getContext(this) as common.UIAbilityContext);
      const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'png');
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(file.fd, data);
      fileIo.closeSync(file);
      this.saved = '已保存到图库，可以从相册分享。';
    } catch (e) {
      this.message = `保存失败：${(e as Error).message}`;
    }
  }

  build() {
    Column() {
      SubpageHeader({ title: '七日分享卡' })
      Scroll() {
        Column() {
          PageIntro({ eyebrow: '分享', title: '把这一周，\n存成一张图', subtitle: '只包含周期与分口径合计，不含记录编号、备注或个人信息。' })
          if (this.card === null) {
            EmptyState({ title: '正在整理这一周', detail: this.message })
          } else {
            this.cardFace(this.card!)
            if (this.card!.recordCount > 0) {
              Row() {
                SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE_TO_GALLERY, buttonType: ButtonType.Capsule })
                  .width('100%').height(50).backgroundColor(Passbook.print).fontColor('#FFFFFF').iconColor('#FFFFFF')
                .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
                  if (result === SaveButtonOnClickResult.SUCCESS) {
                    this.saveImage();
                  } else {
                    this.message = '没有获得保存到图库的授权。';
                  }
                })
              }.width('100%').margin({ top: 20 })
            }
            if (this.saved.length > 0) { Notice({ text: this.saved }).margin({ top: 12 }) }
            if (this.message.length > 0) { Notice({ text: this.message, warning: true }).margin({ top: 12 }) }
            Text('图片只保存在本机相册；是否发出、发给谁，由你自己决定。').fontSize(11).lineHeight(18)
              .fontColor(Theme.muted).width('100%').margin({ top: 14, bottom: 30 })
          }
        }.width('100%').padding({ left: 24, right: 24 }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(Theme.bg)
  }

  @Builder
  cardFace(card: ShareCardData) {
    Stack({ alignContent: Alignment.TopStart }) {
      Image($r('app.media.passbook_hero')).width('100%').height('100%').objectFit(ImageFit.Cover)
        .draggable(false).accessibilityLevel('no')
      Column({ space: 8 }) {
        Row() {
          Column({ space: 2 }) {
            Text('GREEN CARBON PASSBOOK').fontSize(9).letterSpacing(1.5).fontColor('#3A3F4A')
            Text('绿碳存折 · 七日回顾').fontSize(20).fontFamily(Passbook.serif).fontColor(Passbook.print)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Seal({ label: '核', sealSize: 34, angle: -12 })
        }.width('100%')
        Text(`${card.fromDay.replace(/-/g, '.')} — ${card.toDay.replace(/-/g, '.')}`).fontSize(12)
          .fontFamily(Passbook.numeral).fontColor('#3A3F4A')
        if (card.scopes.length === 0) {
          Text('这一周还没有有效记录。').fontSize(14).fontColor(Passbook.print).margin({ top: 24 })
        }
        ForEach(card.scopes, (scope: ShareCardScope) => {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text(NumUtil.signed(scope.netKg, 2)).fontSize(44).fontFamily(Passbook.numeral).fontColor(Passbook.print)
              Text(`${scope.unit} · ${scope.count} 笔`).fontSize(12).fontColor('#3A3F4A').margin({ bottom: 8 })
            }.alignItems(VerticalAlign.Bottom)
            ForEach(scope.lines, (line: ShareCardLine) => {
              Row({ space: 8 }) {
                Row().width(3).height(14).borderRadius(2).backgroundColor(categoryHue(`${line.category}`))
                Text(`${line.label} ${line.count} 笔`).fontSize(12).fontColor(Passbook.print).layoutWeight(1)
                Text(NumUtil.signed(line.netKg, 2)).fontSize(13).fontFamily(Passbook.numeral).fontColor(Passbook.print)
              }.width('100%')
            }, (line: ShareCardLine) => `${scope.unit}-${line.category}`)
          }.width('100%').padding({ left: 14, right: 14, top: 10, bottom: 12 }).backgroundColor('#8CFFFFFF').borderRadius(14)
        }, (scope: ShareCardScope) => scope.unit)
        Blank()
        Text(card.disclaimer).fontSize(10).lineHeight(15).fontColor('#4A505C').width('100%')
      }.width('100%').height('100%').alignItems(HorizontalAlign.Start).padding({ left: 20, right: 20, top: 18, bottom: 16 })
    }
    .id(CARD_ID)
    .width('100%').height(card.scopes.length > 1 ? 470 : 380).borderRadius(24).clip(true)
    .border({ width: 0.5, color: '#1F16181D' })
  }
}
