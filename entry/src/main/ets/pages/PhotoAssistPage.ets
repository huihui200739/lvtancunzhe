import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { cameraPicker, camera } from '@kit.CameraKit';
import { Theme, Passbook, categoryHue, categoryTint, categoryIcon } from '../common/Theme';
import { AppIcon, Notice, SubpageHeader, PageIntro, SectionHeading } from '../components/DesignSystem';
import { PhotoRecognizer, PhotoRecognition } from '../services/PhotoRecognizer';
import { PhotoSuggestion, LabelScore, labelName } from '../services/PhotoAssist';

interface SampleDef {
  file: string;
  label: string;
}

/** 随包演示样张（Wikimedia Commons，许可见 rawfile/samples/CREDITS.txt）；模拟器摄像头画面不适合演示识别 */
const SAMPLES: SampleDef[] = [
  { file: 'samples/bike.jpg', label: '自行车' },
  { file: 'samples/apples.jpg', label: '苹果' },
  { file: 'samples/newspaper.jpg', label: '报纸' },
  { file: 'samples/meal.jpg', label: '一餐饭' }
];

/**
 * 拍照记一笔：端侧模型只负责“认出画面里可能是什么”，并建议打开哪张存入单。
 * 不从照片推算数量或减排，不自动入账；进入录入页后标记为“图片辅助填写”，仍需用户填写并确认。
 */
@Entry
@Component
struct PhotoAssistPage {
  @State photoUri: string = '';
  @State sampleFile: string = '';
  @State busy: boolean = false;
  @State result: PhotoRecognition | null = null;
  @State message: string = '';

  private context(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private async takePhoto(): Promise<void> {
    try {
      const profile: cameraPicker.PickerProfile = { cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK };
      const picked = await cameraPicker.pick(this.context(), [cameraPicker.PickerMediaType.PHOTO], profile);
      if (picked.resultCode !== 0 || picked.resultUri.length === 0) {
        return;
      }
      await this.recognize(picked.resultUri, '');
    } catch (e) {
      this.message = `打开相机失败：${(e as Error).message}。可改用相册或演示样张。`;
    }
  }

  private async pickPhoto(): Promise<void> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const picked = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (picked.photoUris.length === 0) {
        return;
      }
      await this.recognize(picked.photoUris[0], '');
    } catch (e) {
      this.message = `打开相册失败：${(e as Error).message}`;
    }
  }

  private async recognize(uri: string, sample: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.message = '';
    this.result = null;
    this.photoUri = uri;
    this.sampleFile = sample;
    const res = sample.length > 0
      ? await PhotoRecognizer.recognizeRawfile(this.context(), sample)
      : await PhotoRecognizer.recognizeUri(this.context(), uri);
    this.busy = false;
    if (!res.ok || res.data === null) {
      this.message = res.message;
      return;
    }
    this.result = res.data;
  }

  private openSlip(s: PhotoSuggestion): void {
    router.pushUrl({ url: 'pages/RecordEntry', params: {
      category: `${s.category}`, planTaskId: '', imageAssisted: true,
      imageHint: `照片识别到：${s.evidence.join('、')}。${s.hint}`
    } });
  }

  build() {
    Column() {
      SubpageHeader({ title: '拍照记一笔' })
      Scroll() {
        Column() {
          PageIntro({ eyebrow: '端侧 AI · MindSpore Lite', title: '先拍一张，\n再决定记哪一笔',
            subtitle: '模型在这台设备上运行，照片不上传。它只帮你挑存入单，数量仍由你填写。' })
          Row({ space: 10 }) {
            this.actionButton('拍照', () => this.takePhoto())
            this.actionButton('从相册选', () => this.pickPhoto())
          }.width('100%')
          SectionHeading({ title: '或用演示样张', detail: '模拟器演示用' })
          Row({ space: 8 }) {
            ForEach(SAMPLES, (s: SampleDef) => {
              Column({ space: 6 }) {
                Image($rawfile(s.file)).width('100%').aspectRatio(1).objectFit(ImageFit.Cover).borderRadius(12)
                  .border({ width: this.sampleFile === s.file ? 2 : 0, color: Passbook.print })
                Text(s.label).fontSize(11).fontColor(this.sampleFile === s.file ? Passbook.print : Theme.muted)
              }.layoutWeight(1)
              .accessibilityGroup(true).accessibilityText(`识别演示样张：${s.label}`)
              .onClick(() => this.recognize('', s.file))
            }, (s: SampleDef) => s.file)
          }.width('100%')
          if (this.photoUri.length > 0 || this.sampleFile.length > 0) {
            Stack({ alignContent: Alignment.BottomStart }) {
              if (this.sampleFile.length > 0) {
                Image($rawfile(this.sampleFile)).width('100%').height(220).objectFit(ImageFit.Cover)
              } else {
                Image(this.photoUri).width('100%').height(220).objectFit(ImageFit.Cover)
              }
              Text(this.busy ? '正在本机识别…' : (this.result !== null ? `本机识别用时 ${this.result!.elapsedMs} ms · 未上传` : ''))
                .fontSize(11).fontColor('#FFFFFF').padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .backgroundColor('#99000000').borderRadius(10).margin(12)
            }.width('100%').height(220).borderRadius(20).clip(true).margin({ top: 20 })
          }
          if (this.message.length > 0) { Notice({ text: this.message, warning: true }).margin({ top: 14 }) }
          if (this.result !== null) {
            SectionHeading({ title: '模型看到了', detail: '分数越高越确定' })
            Column() {
              ForEach(this.result!.insight.topLabels, (l: LabelScore) => {
                Row({ space: 10 }) {
                  Text(labelName(l.label)).fontSize(12).fontColor(Theme.ink).width(120).maxLines(1)
                  Stack({ alignContent: Alignment.Start }) {
                    Row().width('100%').height(6).borderRadius(3).backgroundColor(Theme.line)
                    Row().width(`${Math.round(Math.max(0.02, l.score) * 100)}%`).height(6).borderRadius(3)
                      .backgroundColor(l.score >= 0.5 ? Passbook.print : '#C9CBD0')
                  }.layoutWeight(1)
                  Text(l.score.toFixed(2)).fontSize(11).fontFamily(Passbook.numeral).fontColor(Theme.muted).width(34).textAlign(TextAlign.End)
                }.width('100%').padding({ top: 7, bottom: 7 })
              }, (l: LabelScore) => l.label)
            }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 }).backgroundColor(Theme.paper).borderRadius(18)
            SectionHeading({ title: '建议填写', detail: `${this.result!.insight.suggestions.length} 张存入单` })
            ForEach(this.result!.insight.suggestions, (s: PhotoSuggestion) => {
              Row({ space: 12 }) {
                Stack() {
                  AppIcon({ name: categoryIcon(`${s.category}`), iconSize: 20 })
                }.width(40).height(40).borderRadius(12).backgroundColor(categoryTint(`${s.category}`))
                Column({ space: 4 }) {
                  Text(s.categoryLabel).fontSize(16).fontFamily(Passbook.serif).fontColor(Theme.ink)
                  Text(`识别到：${s.evidence.join('、')}`).fontSize(11).fontColor(categoryHue(`${s.category}`))
                  Text(s.hint).fontSize(11).lineHeight(17).fontColor(Theme.muted)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                AppIcon({ name: 'arrow', iconSize: 18 })
              }.width('100%').padding(14).margin({ bottom: 10 }).alignItems(VerticalAlign.Top)
              .backgroundColor('#FFFFFF').border({ width: 1, color: Theme.line }).borderRadius(18)
              .border({ width: { left: 4 }, color: categoryHue(`${s.category}`) })
              .onClick(() => this.openSlip(s))
            }, (s: PhotoSuggestion) => `${s.category}`)
            Notice({ text: this.result!.insight.message }).margin({ top: 4 })
          }
          Text('模型：MindSpore 官方示例 MobileNetV2（Open Images 410 类，Apache-2.0）。它不识别重量、里程或电量，也不能证明行为真实发生。')
            .fontSize(11).lineHeight(18).fontColor(Theme.muted).width('100%').margin({ top: 20, bottom: 30 })
        }.width('100%').padding({ left: 24, right: 24 }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(Theme.bg)
  }

  @Builder
  actionButton(label: string, action: () => void) {
    Button(label).layoutWeight(1).height(50).fontSize(14).fontColor('#FFFFFF').backgroundColor(Passbook.print)
      .enabled(!this.busy).onClick(action)
  }
}
