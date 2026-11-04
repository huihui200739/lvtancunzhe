import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Theme } from '../common/Theme';
import { SubpageHeader, PageIntro, SectionHeading, Notice } from '../components/DesignSystem';
import { AiConfig, AiModelOption, emptyAiConfig, maskKey } from '../models/AiModels';
import { AiConfigStore } from '../services/AiConfigStore';
import { AiCoachService } from '../services/AiCoachService';

/**
 * AI 助手设置页（可选功能，默认关闭）。
 * 密钥只保存在本机应用沙箱；不写账本、备份和导出，也不出现在日志里。
 */
@Entry
@Component
struct AiSettingsPage {
  @State config: AiConfig = emptyAiConfig();
  @State endpointText: string = '';
  @State modelText: string = '';
  @State keyText: string = '';
  @State aiEnabled: boolean = false;
  @State busy: boolean = false;
  @State message: string = '';
  @State passed: boolean = false;
  @State resultTitle: string = '';
  @State modelOptions: AiModelOption[] = [];
  @State modelsLoading: boolean = false;

  aboutToAppear(): void {
    AiConfigStore.load(this.context()).then((config: AiConfig) => {
      this.config = config;
      this.endpointText = config.endpoint;
      this.modelText = config.model;
      this.keyText = config.apiKey;
      this.aiEnabled = config.enabled;
    });
  }

  private context(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private draft(): AiConfig {
    return {
      endpoint: this.endpointText,
      model: this.modelText,
      apiKey: this.keyText,
      enabled: this.aiEnabled
    };
  }

  private async save(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.message = '';
    this.resultTitle = '';
    try {
      const checked = AiConfigStore.validate(this.draft());
      if (!checked.ok) {
        this.passed = false;
        this.message = checked.message;
        return;
      }
      const saved = await AiConfigStore.save(this.context(), this.draft());
      if (!saved.ok) {
        this.passed = false;
        this.message = saved.message;
        return;
      }
      this.config = this.draft();
      this.passed = true;
      this.resultTitle = '设置已保存';
      this.message = '已保存到本机。联网开关关闭时不会发起任何请求。';
    } finally {
      this.busy = false;
    }
  }

  private async loadModels(): Promise<void> {
    if (this.modelsLoading) {
      return;
    }
    this.modelsLoading = true;
    this.message = '';
    try {
      const res = await AiCoachService.listModels(this.draft());
      if (!res.ok || res.data === null) {
        this.passed = false;
        this.message = res.message;
        return;
      }
      this.modelOptions = res.data;
      this.passed = true;
      this.resultTitle = '已读取模型列表';
      this.message = `共 ${res.data.length} 个可用模型，点一下即可填入。`;
    } finally {
      this.modelsLoading = false;
    }
  }

  private async test(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.message = '';
    this.passed = false;
    this.resultTitle = '';
    try {
      const res = await AiCoachService.test(this.draft());
      this.passed = res.ok;
      this.resultTitle = res.ok ? '连通成功' : '连通失败';
      this.message = res.ok ? `模型返回：${res.data}` : res.message;
      if (res.ok) {
        const models = await AiCoachService.listModels(this.draft());
        if (models.ok && models.data !== null) {
          this.modelOptions = models.data;
        }
      }
    } finally {
      this.busy = false;
    }
  }

  private async clearKey(): Promise<void> {
    if (this.busy) { return; }
    const confirm = await promptAction.showDialog({
      title: '清除 API Key',
      message: '清除后 AI 补充建议将不可用，本地记账、计划与统计不受影响。',
      buttons: [
        { text: '保留', color: Theme.green },
        { text: '确认清除', color: Theme.rust }
      ]
    });
    if (confirm.index !== 1) { return; }
    const res = await AiConfigStore.clearKey(this.context());
    this.keyText = '';
    this.aiEnabled = false;
    this.config = this.draft();
    this.passed = res.ok;
    this.message = res.ok ? '密钥已清除。' : res.message;
  }

  build() {
    Column() {
      SubpageHeader({ title: 'AI 行动教练（可选）' })
      Scroll() {
        Column({ space: 16 }) {
          PageIntro({ title: '让 AI 补充一句执行提醒', subtitle: '默认关闭。开启后只把已保存计划的公开摘要发给你自己的接口。', eyebrow: '联网功能' })
          Notice({ text: '发送内容仅包括：计划窗口、目标、预计值、参与任务数和任务标题/类别/日期。不发送记录编号、备注、姓名、学号、积分明细或数据库文件。AI 文本不参与核算、凭证、积分和目标判断。' })
          SectionHeading({ title: '接口设置' })
          Column({ space: 14 }) {
            Text('接口地址（OpenAI 兼容 chat completions）').fontSize(12).fontColor(Theme.muted).width('100%')
            TextInput({ text: this.endpointText, placeholder: 'https://中转站根地址 或 .../v1/chat/completions' }).fontSize(13).height(48).backgroundColor(Theme.bg)
              .onChange((v: string) => { this.endpointText = v; })
            Text('可直接填中转站根地址，保存与请求时会自动补 /v1/chat/completions').fontSize(11).fontColor(Theme.muted).width('100%')
            Row() {
              Text('模型名称').fontSize(12).fontColor(Theme.muted).layoutWeight(1)
              Text(this.modelsLoading ? '读取中…' : '读取可用模型').fontSize(11).fontColor(Theme.green)
                .onClick(() => this.loadModels())
            }.width('100%')
            TextInput({ text: this.modelText }).fontSize(13).height(48).backgroundColor(Theme.bg)
              .onChange((v: string) => { this.modelText = v; })
            Button(this.modelsLoading ? '正在读取可用模型…' : '读取可用模型').height(40).fontSize(12).width('100%')
              .fontColor(Theme.green).backgroundColor(Theme.sage).enabled(!this.modelsLoading)
              .onClick(() => this.loadModels())
            if (this.modelOptions.length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.modelOptions, (m: AiModelOption) => {
                  Column() {
                    Text(m.id).fontSize(11)
                      .fontColor(this.modelText === m.id ? Theme.paper : Theme.green)
                    if (AiCoachService.modelMetaText(m).length > 0) {
                      Text(AiCoachService.modelMetaText(m)).fontSize(9).lineHeight(13)
                        .fontColor(this.modelText === m.id ? Theme.paper : Theme.muted)
                    }
                  }.alignItems(HorizontalAlign.Start)
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .backgroundColor(this.modelText === m.id ? Theme.green : Theme.sage)
                  .borderRadius(Theme.controlRadius)
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => { this.modelText = m.id; })
                }, (m: AiModelOption) => m.id)
              }.width('100%')
            }
            Text('API Key').fontSize(12).fontColor(Theme.muted).width('100%')
            TextInput({ text: this.keyText }).fontSize(13).height(48).type(InputType.Password).backgroundColor(Theme.bg)
              .onChange((v: string) => { this.keyText = v; })
            Text(`当前密钥：${maskKey(this.config.apiKey)}`).fontSize(11).fontColor(Theme.muted).width('100%')
            Row() {
              Column({ space: 2 }) {
                Text('允许联网请求').fontSize(14).fontColor(Theme.ink).width('100%')
                Text('关闭时应用完全离线，所有功能仍可用').fontSize(11).fontColor(Theme.muted).width('100%')
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.aiEnabled }).selectedColor(Theme.green)
                .onChange((v: boolean) => { this.aiEnabled = v; })
            }.width('100%')
          }.width('100%').padding(20).backgroundColor(Theme.paper).borderRadius(Theme.cardRadius)
          Row({ space: 12 }) {
            Button(this.busy ? '处理中…' : '保存设置').layoutWeight(1).height(48).fontSize(14)
              .backgroundColor(Theme.green).enabled(!this.busy).onClick(() => this.save())
            Button('测试连通').layoutWeight(1).height(48).fontSize(14).fontColor(Theme.green)
              .backgroundColor(Theme.sage).enabled(!this.busy).onClick(() => this.test())
          }.width('100%')
          if (this.passed) {
            Column({ space: 6 }) {
              Text(this.resultTitle.length > 0 ? this.resultTitle : '已完成').fontSize(14).fontColor(Theme.green).width('100%')
              Text(this.message).fontSize(12).lineHeight(19).fontColor(Theme.ink).width('100%')
            }.width('100%').padding(16).backgroundColor(Theme.sage).borderRadius(Theme.cardRadius)
          } else if (this.message.length > 0) {
            Notice({ text: this.message, warning: true })
          }
          SectionHeading({ title: '密钥与数据' })
          Text('密钥保存在本机应用沙箱的偏好文件里，不写入账本数据库，不进入 JSON 备份、CSV 导出或应用日志；卸载应用即清除。若设备共用，请在使用后清除密钥。\n\n离线时 AI 请求会失败并给出提示，本地记录、计划、周报和模拟演练不依赖网络。')
            .fontSize(11).lineHeight(20).fontColor(Theme.muted).width('100%')
          Button('清除 API Key').height(46).fontSize(13).width('100%').fontColor(Theme.rust)
            .backgroundColor('#FCEDE8').enabled(!this.busy).onClick(() => this.clearKey())
          Button('返回').height(46).fontSize(13).width('100%').fontColor(Theme.green)
            .backgroundColor(Theme.paper).onClick(() => router.back())
        }.width('100%').padding({ left: 24, right: 24, top: 8, bottom: 30 }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(Theme.bg)
  }
}
