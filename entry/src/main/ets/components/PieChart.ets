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
  @Link @Watch('onSelect') selectedCategory: string;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;
  private canvasW: number = 0;
  private canvasH: number = 0;

  // 多类别时按“深绿 → 沙色 → 浅绿”分配，相邻段对比更清楚
  private static readonly COLORS: string[] = ['#1F4436', '#4C7560', '#8CA98F', '#C2B08C', '#D5DEC4'];

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
          .onAreaChange((oldValue: Area, newValue: Area) => {
            this.canvasW = Number(newValue.width);
            this.canvasH = Number(newValue.height);
          })
          .onClick((event: ClickEvent) => { this.handleTap(Number(event.x), Number(event.y)); })
          .onReady(() => {
            this.ready = true;
            this.draw();
          })
      }
      Column() {
        ForEach(this.data.filter((c: CategoryStat) => c.positiveKg > 0), (c: CategoryStat, index: number) => {
          Row() {
            Circle().width(6).height(6).fill(PieChart.COLORS[this.data.indexOf(c) % PieChart.COLORS.length])
            Text(c.label).fontSize(12).fontWeight(this.isSelected(c) ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.selectedCategory.length === 0 || this.isSelected(c) ? Theme.ink : Theme.muted)
              .layoutWeight(1).margin({ left: 8 }).maxLines(1)
            Text(`${c.positiveKg.toFixed(2)}`).fontSize(12).fontFeature('"tnum" on')
              .fontColor(this.selectedCategory.length === 0 || this.isSelected(c) ? Theme.ink : Theme.muted)
          }.width('100%').padding({ top: 10, bottom: 10 })
            .onClick(() => {
              this.selectedCategory = this.selectedCategory === `${c.category}` ? '' : `${c.category}`;
            })
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

  /** 画布内点扇区：命中环带则选中/取消，点中心或环外取消 */
  private handleTap(x: number, y: number): void {
    if (this.canvasW <= 0 || this.canvasH <= 0) {
      return;
    }
    const dx = x - this.canvasW / 2;
    const dy = y - this.canvasH / 2;
    const dist = Math.sqrt(dx * dx + dy * dy);
    const half = Math.min(this.canvasW, this.canvasH) / 2;
    const outer = half - 20;
    const inner = outer - 22;
    if (dist < inner - 8 || dist > outer + 8) {
      this.selectedCategory = '';
      return;
    }
    let angle = Math.atan2(dx, -dy);
    if (angle < 0) {
      angle = angle + Math.PI * 2;
    }
    const total = this.positiveTotal();
    if (total <= 0) {
      return;
    }
    let start = 0;
    for (const c of this.data) {
      if (c.positiveKg <= 0) {
        continue;
      }
      const span = (c.positiveKg / total) * Math.PI * 2;
      if (angle >= start && angle < start + span) {
        const key = `${c.category}`;
        this.selectedCategory = this.selectedCategory === key ? '' : key;
        return;
      }
      start = start + span;
    }
  }

  private isSelected(c: CategoryStat): boolean {
    return this.selectedCategory.length > 0 && this.selectedCategory === `${c.category}`;
  }

  // Canvas 只在 onReady 绘制一次；数据或选中类别变化时主动重绘
  private onSelect(): void {
    if (this.ready) {
      this.draw();
    }
  }

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
    const hasSelection = this.selectedCategory.length > 0;
    for (let i = 0; i < this.data.length; i++) {
      const v = this.data[i].positiveKg;
      if (v <= 0) {
        continue;
      }
      const angle = (v / total) * Math.PI * 2;
      const selected = hasSelection && this.selectedCategory === `${this.data[i].category}`;
      ctx.globalAlpha = hasSelection && !selected ? 0.28 : 1;
      ctx.beginPath();
      ctx.arc(cx, cy, radius, start + gap / 2, start + angle - gap / 2);
      ctx.strokeStyle = PieChart.COLORS[i % PieChart.COLORS.length];
      ctx.lineWidth = selected ? ring + 4 : ring;
      ctx.lineCap = 'butt';
      ctx.stroke();
      ctx.globalAlpha = 1;
      start = start + angle;
    }

    // 中心读数：未选中显示合计；选中某类时显示该类数值与占比
    let centerValue = total;
    let centerLabel = `合计 ${this.unit}`;
    if (this.selectedCategory.length > 0) {
      for (const c of this.data) {
        if (`${c.category}` === this.selectedCategory && c.positiveKg > 0) {
          centerValue = c.positiveKg;
          const share = total > 0 ? Math.round((c.positiveKg / total) * 100) : 0;
          centerLabel = `${c.label} · ${share}%`;
        }
      }
    }
    const valueSize = this.getUIContext().vp2px(20);
    const labelSize = this.getUIContext().vp2px(10);
    ctx.textAlign = 'center';
    ctx.fillStyle = Theme.ink;
    ctx.font = `${valueSize}px sans-serif`;
    ctx.fillText(centerValue.toFixed(2), cx, cy + 2);
    ctx.fillStyle = Theme.chartText;
    ctx.font = `${labelSize}px sans-serif`;
    ctx.fillText(centerLabel, cx, cy + 18);
    ctx.textAlign = 'left';
  }
}
