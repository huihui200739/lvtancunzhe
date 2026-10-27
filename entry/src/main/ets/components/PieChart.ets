import { Theme } from '../common/Theme';
import { CategoryStat } from '../models/StatsModels';

/**
 * 饼图（第 4.1 节 B2）：展示正向贡献占比，增加排放单列。
 * 全零时不画扇区并提示；不出现除零。
 */
@Component
export struct PieChart {
  @Prop title: string = '';
  @Prop @Watch('onData') data: CategoryStat[] = [];
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;

  private static readonly COLORS: string[] = ['#47735B', '#81966F', '#C5AD73', '#96ABA4', '#00838F'];

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
      Column() {
        ForEach(this.data, (c: CategoryStat, i: number) => {
          Row() {
            Text('■')
              .fontSize(12)
              .fontColor(PieChart.COLORS[i % PieChart.COLORS.length])
            Text(` ${c.label} 正向 ${c.positiveKg.toFixed(2)} kg`)
              .fontSize(12)
              .fontColor('#444444')
          }
          .width('100%')
        })
      }
      .width('100%')
      .margin({ top: 4 })
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
    let total = 0;
    for (const c of this.data) {
      total = total + c.positiveKg;
    }
    ctx.font = `${this.getUIContext().vp2px(12)}px sans-serif`;
    if (total <= 0) {
      ctx.fillStyle = '#78867B';
      ctx.fillText('暂无可展示的正向贡献', 12, h / 2);
      return;
    }
    const cx = w / 2;
    const cy = h / 2;
    const radius = Math.min(w, h) / 2 - 12;
    let start = -Math.PI / 2;
    for (let i = 0; i < this.data.length; i++) {
      const v = this.data[i].positiveKg;
      if (v <= 0) {
        continue;
      }
      const angle = (v / total) * Math.PI * 2;
      ctx.fillStyle = PieChart.COLORS[i % PieChart.COLORS.length];
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.arc(cx, cy, radius, start, start + angle);
      ctx.closePath();
      ctx.fill();
      start = start + angle;
    }
    // 中心留白形成环形
    ctx.fillStyle = '#FFFFFF';
    ctx.beginPath();
    ctx.arc(cx, cy, radius * 0.5, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#47735B';
    ctx.font = `${this.getUIContext().vp2px(12)}px sans-serif`;
    const text = `${total.toFixed(1)} kg`;
    ctx.fillText(text, cx - ctx.measureText(text).width / 2, cy + 4);
  }
}
