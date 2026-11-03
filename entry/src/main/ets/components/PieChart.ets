import { Theme } from '../common/Theme';
import { CategoryStat } from '../models/StatsModels';

/**
 * 饼图（第 4.1 节 B2）：展示正向贡献占比，增加排放单列。
 * 全零时不画扇区并提示；不出现除零。
 */
@Component
export struct PieChart {
  @Prop title: string = '';
  @Prop unit: string = 'kgCO₂';
  @Prop @Watch('onData') data: CategoryStat[] = [];
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;

  private static readonly COLORS: string[] = ['#2F5D4B', '#5B8068', '#8AA37E', '#B6C6A4', '#D5DEC4'];

  private positiveCategoryCount(): number {
    let count = 0;
    for (const category of this.data) {
      if (category.positiveKg > 0) { count++; }
    }
    return count;
  }

  build() {
    Column() {
      Row() {
        Text(this.title)
          .fontSize(15)
          .fontColor(Theme.ink)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text(this.unit).fontSize(11).fontColor(Theme.muted)
      }.width('100%')
      if (this.positiveCategoryCount() === 0) {
        Column() {
          Text('暂无可展示的正向贡献').fontSize(12).fontColor(Theme.muted)
        }.width('100%').height(76).justifyContent(FlexAlign.Center)
      } else {
        Canvas(this.ctx)
          .width('100%')
          .height(144)
          .backgroundColor(Theme.paper)
          .onReady(() => {
            this.ready = true;
            this.draw();
          })
      }
      Column({ space: 6 }) {
        ForEach(this.data.filter((c: CategoryStat) => c.positiveKg > 0), (c: CategoryStat) => {
          Row({ space: 8 }) {
            Circle().width(8).height(8).fill(PieChart.COLORS[this.data.indexOf(c) % PieChart.COLORS.length])
            Text(`${c.label} 正向 ${c.positiveKg.toFixed(2)} ${this.unit}`)
              .fontSize(12)
              .fontColor(Theme.ink)
          }
          .width('100%')
        })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Theme.paper)
    .borderRadius(Theme.cardRadius)
  }

  // Canvas 只在 onReady 绘制一次；数据随后到达时需主动重绘
  private onData(): void {
    if (this.positiveCategoryCount() === 0) {
      this.ready = false;
      return;
    }
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
      ctx.fillStyle = Theme.muted;
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
    ctx.fillStyle = Theme.paper;
    ctx.beginPath();
    ctx.arc(cx, cy, radius * 0.5, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = Theme.green;
    ctx.font = `${this.getUIContext().vp2px(12)}px sans-serif`;
    const text = `${total.toFixed(1)}`;
    ctx.fillText(text, cx - ctx.measureText(text).width / 2, cy + 4);
  }
}
