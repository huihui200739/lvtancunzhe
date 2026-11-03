import { Theme } from '../common/Theme';
import { CategoryStat } from '../models/StatsModels';

/**
 * 正向贡献占比：环形图 + 账本式图例。
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

  private static readonly COLORS: string[] = ['#244E40', '#5B8068', '#8AA37E', '#B6C6A4', '#D5DEC4'];

  private positiveCategoryCount(): number {
    let count = 0;
    for (const category of this.data) {
      if (category.positiveKg > 0) { count++; }
    }
    return count;
  }

  private positiveTotal(): number {
    let total = 0;
    for (const category of this.data) {
      if (category.positiveKg > 0) { total = total + category.positiveKg; }
    }
    return total;
  }

  build() {
    Column() {
      Row() {
        Text(this.title)
          .fontSize(15)
          .fontColor(Theme.ink)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text(this.unit).fontSize(10).fontColor(Theme.chartText).fontFeature('"tnum" on')
      }.width('100%')
      if (this.positiveCategoryCount() === 0) {
        Column() {
          Text('暂无可展示的正向贡献').fontSize(12).fontColor(Theme.muted)
        }.width('100%').height(96).justifyContent(FlexAlign.Center)
      } else {
        Canvas(this.ctx)
          .width('100%')
          .height(168)
          .backgroundColor(Theme.paper)
          .onReady(() => {
            this.ready = true;
            this.draw();
          })
      }
      Column() {
        ForEach(this.data.filter((c: CategoryStat) => c.positiveKg > 0), (c: CategoryStat, index: number) => {
          Row() {
            Circle().width(6).height(6).fill(PieChart.COLORS[this.data.indexOf(c) % PieChart.COLORS.length])
            Text(c.label).fontSize(12).fontColor(Theme.ink).layoutWeight(1).margin({ left: 8 }).maxLines(1)
            Text(`${c.positiveKg.toFixed(2)}`).fontSize(12).fontColor(Theme.muted).fontFeature('"tnum" on')
          }.width('100%').padding({ top: 10, bottom: 10 })
          if (index < this.positiveCategoryCount() - 1) {
            Divider().color(Theme.line)
          }
        })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 8 })
    .backgroundColor(Theme.paper)
    .border({ width: 1, color: Theme.line })
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
    const total = this.positiveTotal();
    if (total <= 0) {
      return;
    }
    const cx = w / 2;
    const cy = h / 2;
    const radius = Math.min(w, h) / 2 - 20;
    const ring = 22;
    const segments = this.positiveCategoryCount();
    // 多段之间留 1.5° 空隙，单段时保持完整环
    const gap = segments > 1 ? 0.026 : 0;
    let start = -Math.PI / 2;
    for (let i = 0; i < this.data.length; i++) {
      const v = this.data[i].positiveKg;
      if (v <= 0) {
        continue;
      }
      const angle = (v / total) * Math.PI * 2;
      ctx.beginPath();
      ctx.arc(cx, cy, radius, start + gap / 2, start + angle - gap / 2);
      ctx.strokeStyle = PieChart.COLORS[i % PieChart.COLORS.length];
      ctx.lineWidth = ring;
      ctx.lineCap = 'butt';
      ctx.stroke();
      start = start + angle;
    }

    // 中心读数：数值 + 口径说明
    const valueSize = this.getUIContext().vp2px(20);
    const labelSize = this.getUIContext().vp2px(10);
    ctx.textAlign = 'center';
    ctx.fillStyle = Theme.ink;
    ctx.font = `${valueSize}px sans-serif`;
    ctx.fillText(total.toFixed(2), cx, cy + 2);
    ctx.fillStyle = Theme.chartText;
    ctx.font = `${labelSize}px sans-serif`;
    ctx.fillText(`合计 ${this.unit}`, cx, cy + 18);
    ctx.textAlign = 'left';
  }
}
