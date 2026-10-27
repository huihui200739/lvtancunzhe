import { Theme } from '../common/Theme';
import { StatBucket } from '../models/StatsModels';

/**
 * 折线图（第 4.1 节 B2）：展示净变化（可为负）随时间的走势。
 * 与明细汇总口径一致；全零或空数据时正常显示，不出现除零。
 */
@Component
export struct LineChart {
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
      if (this.data[i].netKg > maxV) {
        maxV = this.data[i].netKg;
      }
      if (this.data[i].netKg < minV) {
        minV = this.data[i].netKg;
      }
    }
    let range = maxV - minV;
    if (range <= 0) {
      maxV = maxV === 0 ? 1 : maxV;
      range = maxV - minV;
    }
    const zeroY = padT + plotH * (maxV / range);

    // 坐标轴与零线
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
    ctx.fillText(`${minV.toFixed(1)}`, 2, padT + plotH);

    // 折线
    const stepX = n > 1 ? plotW / (n - 1) : 0;
    ctx.strokeStyle = '#47735B';
    ctx.lineWidth = 2;
    ctx.beginPath();
    for (let i = 0; i < n; i++) {
      const x = padL + (n > 1 ? stepX * i : plotW / 2);
      const y = padT + plotH * ((maxV - this.data[i].netKg) / range);
      if (i === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.stroke();

    // 数据点
    ctx.fillStyle = '#47735B';
    for (let i = 0; i < n; i++) {
      const x = padL + (n > 1 ? stepX * i : plotW / 2);
      const y = padT + plotH * ((maxV - this.data[i].netKg) / range);
      ctx.beginPath();
      ctx.arc(x, y, 2.5, 0, Math.PI * 2);
      ctx.fill();
    }

    // 横轴标签：首、中、尾
    ctx.fillStyle = '#78867B';
    const idxs: number[] = [0];
    if (n > 2) {
      idxs.push(Math.floor((n - 1) / 2));
    }
    if (n > 1) {
      idxs.push(n - 1);
    }
    for (const i of idxs) {
      const x = padL + (n > 1 ? stepX * i : plotW / 2);
      const label = this.data[i].label;
      ctx.fillText(label, x - 14, padT + plotH + 14);
    }
  }
}
