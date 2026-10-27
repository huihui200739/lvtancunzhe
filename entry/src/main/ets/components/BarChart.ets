import { Theme } from '../common/Theme';
import { StatBucket } from '../models/StatsModels';

/**
 * 柱状图（第 4.1 节 B2）：同口径展示正向贡献与增加排放。
 * 正值向上、负值向下，零线居中；全零时正常显示。
 */
@Component
export struct BarChart {
  @Prop title: string = '';
  @Prop @Watch('onData') data: StatBucket[] = [];
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;

  build() {
    Column() {
      Text(this.title)
        .fontSize(15)
        .fontColor(Theme.ink)
        .fontWeight(FontWeight.Medium)
        .width('100%')
      Canvas(this.ctx)
        .width('100%')
        .height(180)
        .backgroundColor('#FFFFFF')
        .onReady(() => {
          this.ready = true;
          this.draw();
        })
    }
    .width('100%')
    .padding(20)
    .backgroundColor('#FFFFFF')
    .borderRadius(24)
  }

  // Canvas 只在 onReady 绘制一次；数据随后到达时需主动重绘
  private onData(): void {
    if (this.ready) {
      this.draw();
    }
  }

  private draw(): void {
    const ctx = this.ctx;
    const w = ctx.width;
    const h = ctx.height;
    ctx.clearRect(0, 0, w, h);
    const padL = 40;
    const padR = 12;
    const padT = 14;
    const padB = 24;
    const plotW = w - padL - padR;
    const plotH = h - padT - padB;
    const n = this.data.length;
    ctx.font = `${this.getUIContext().vp2px(11)}px sans-serif`;
    if (n === 0) {
      ctx.fillStyle = '#78867B';
      ctx.fillText('暂无数据', padL, h / 2);
      return;
    }
    let maxV = 0;
    let minV = 0;
    for (let i = 0; i < n; i++) {
      if (this.data[i].positiveKg > maxV) {
        maxV = this.data[i].positiveKg;
      }
      if (-this.data[i].negativeKg < minV) {
        minV = -this.data[i].negativeKg;
      }
    }
    let range = maxV - minV;
    if (range <= 0) {
      maxV = 1;
      range = 1;
    }
    const zeroY = padT + plotH * (maxV / range);

    ctx.strokeStyle = '#E6EAE0';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(padL, padT);
    ctx.lineTo(padL, padT + plotH);
    ctx.lineTo(padL + plotW, padT + plotH);
    ctx.stroke();
    ctx.strokeStyle = '#BBBBBB';
    ctx.beginPath();
    ctx.moveTo(padL, zeroY);
    ctx.lineTo(padL + plotW, zeroY);
    ctx.stroke();

    ctx.fillStyle = '#78867B';
    ctx.fillText(`${maxV.toFixed(1)}`, 2, padT + 8);

    const slot = plotW / n;
    const barW = slot > 26 ? 14 : slot * 0.5;
    for (let i = 0; i < n; i++) {
      const cx = padL + slot * i + slot / 2;
      const b = this.data[i];
      // 正向
      const posH = plotH * (b.positiveKg / range);
      if (posH > 0) {
        ctx.fillStyle = '#47735B';
        ctx.fillRect(cx - barW - 1, zeroY - posH, barW, posH);
      }
      // 增加排放（向下）
      const negH = plotH * (b.negativeKg / range);
      if (negH > 0) {
        ctx.fillStyle = '#BC8068';
        ctx.fillRect(cx + 1, zeroY, barW, negH);
      }
      if (i % 2 === 0 || n <= 6) {
        ctx.fillStyle = '#78867B';
        ctx.fillText(b.label, cx - 12, padT + plotH + 14);
      }
    }
  }
}
