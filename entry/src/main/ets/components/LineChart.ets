import { Theme } from '../common/Theme';
import { StatBucket } from '../models/StatsModels';

interface ChartPoint {
  x: number;
  y: number;
}

/**
 * 净变化趋势图：柔和曲线 + 零基线，网格只保留水平发丝线。
 * 数据为空或全零时给出安静的空状态，不画假线。
 */
@Component
export struct LineChart {
  @Prop title: string = '';
  @Prop unit: string = 'kgCO₂';
  @Prop @Watch('onData') data: StatBucket[] = [];
  @Link @Watch('onSelect') selectedKey: string;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;
  private touchWidth: number = 0;
  private touchStartX: number = 0;
  private touchStartY: number = 0;

  private populatedCount(): number {
    let count = 0;
    for (const bucket of this.data) {
      if (bucket.count > 0) { count++; }
    }
    return count;
  }

  private allNetZero(): boolean {
    if (this.populatedCount() === 0) { return false; }
    for (const bucket of this.data) {
      if (bucket.count > 0 && bucket.netKg !== 0) { return false; }
    }
    return true;
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
      if (this.populatedCount() === 0) {
        Column() {
          Text('暂无已记录数据').fontSize(12).fontColor(Theme.muted)
        }.width('100%').height(96).justifyContent(FlexAlign.Center)
      } else if (this.allNetZero()) {
        Column() {
          Text('已记录 · 净变化为 0').fontSize(12).fontColor(Theme.muted)
        }.width('100%').height(96).justifyContent(FlexAlign.Center)
      } else {
        Stack() {
          Canvas(this.ctx)
            .width('100%')
            .height(158)
            .backgroundColor(Theme.paper)
            .onReady(() => {
              this.ready = true;
              this.draw();
            })
          Row() {
          }.width('100%').height(158).padding({ left: 12, right: 8 })
            .onAreaChange((oldValue: Area, newValue: Area) => { this.touchWidth = Number(newValue.width); })
            .onClick((event: ClickEvent) => { this.selectAt(Number(event.x)); })
        }.width('100%').height(158)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 12 })
    .backgroundColor(Theme.paper)
    .border({ width: 1, color: Theme.line })
    .borderRadius(Theme.cardRadius)
  }

  // Canvas 只在 onReady 绘制一次；数据或选中项变化时主动重绘
  private onSelect(): void {
    if (this.ready) {
      this.draw();
    }
  }

  /** 按触点位置换算到最近的时间桶；拖动时连续更新 */
  private selectAt(x: number): void {
    if (this.data.length === 0 || this.touchWidth <= 24) {
      return;
    }
    const inner = this.touchWidth - 20;
    const cell = inner / this.data.length;
    let index = Math.floor((x - 12) / cell);
    if (index < 0) { index = 0; }
    if (index > this.data.length - 1) { index = this.data.length - 1; }
    this.selectedKey = this.data[index].key;
  }

  private indexOfSelected(): number {
    if (this.selectedKey.length === 0) {
      return -1;
    }
    for (let i = 0; i < this.data.length; i++) {
      if (this.data[i].key === this.selectedKey) {
        return i;
      }
    }
    return -1;
  }

  private onData(): void {
    if (this.populatedCount() === 0 || this.allNetZero()) {
      this.ready = false;
      return;
    }
    if (this.ready) {
      this.draw();
    }
  }

  /** 依次连接各点，使用 Catmull-Rom 转三次贝塞尔，避免折线生硬 */
  private traceCurve(points: ChartPoint[]): void {
    const ctx = this.ctx;
    ctx.moveTo(points[0].x, points[0].y);
    for (let i = 0; i < points.length - 1; i++) {
      const p0 = points[i === 0 ? 0 : i - 1];
      const p1 = points[i];
      const p2 = points[i + 1];
      const p3 = points[i + 2 < points.length ? i + 2 : points.length - 1];
      // 控制点限制在本段两端之间，避免曲线冲出零线造成“负值”错觉
      const lo = Math.min(p1.y, p2.y);
      const hi = Math.max(p1.y, p2.y);
      const c1x = p1.x + (p2.x - p0.x) / 8;
      const c2x = p2.x - (p3.x - p1.x) / 8;
      const c1y = Math.max(lo, Math.min(hi, p1.y + (p2.y - p0.y) / 8));
      const c2y = Math.max(lo, Math.min(hi, p2.y - (p3.y - p1.y) / 8));
      ctx.bezierCurveTo(c1x, c1y, c2x, c2y, p2.x, p2.y);
    }
  }

  private draw(): void {
    const ctx = this.ctx;
    const w = ctx.width;
    const h = ctx.height;
    ctx.clearRect(0, 0, w, h);
    const padL = 34;
    const padR = 10;
    const padT = 10;
    const padB = 22;
    const plotW = w - padL - padR;
    const plotH = h - padT - padB;
    const n = this.data.length;
    const labelSize = this.getUIContext().vp2px(10);
    const valueSize = this.getUIContext().vp2px(10);
    if (n === 0) {
      return;
    }
    let maxV = 0;
    let minV = 0;
    for (let i = 0; i < n; i++) {
      if (this.data[i].netKg > maxV) { maxV = this.data[i].netKg; }
      if (this.data[i].netKg < minV) { minV = this.data[i].netKg; }
    }
    const span = maxV - minV === 0 ? 1 : maxV - minV;
    // 全为正向/全为负向时把坐标轴锚在 0，避免出现没有意义的负刻度
    const top = maxV > 0 ? maxV + span * 0.18 : 0;
    const bottom = minV < 0 ? minV - span * 0.18 : 0;
    const rangeSafe = top - bottom === 0 ? 1 : top - bottom;
    const range = rangeSafe;
    const yOf = (v: number): number => padT + plotH * ((top - v) / range);
    const zeroY = yOf(0);

    // 水平发丝网格：顶、零线、底；零线略深，其余极淡
    ctx.lineWidth = 1;
    const rows: number[] = [padT, zeroY, padT + plotH];
    for (const y of rows) {
      ctx.strokeStyle = y === zeroY ? '#CBD5C6' : Theme.chartGrid;
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(padL + plotW, y);
      ctx.stroke();
    }

    // 纵轴只保留上下两个刻度，避免噪声
    ctx.fillStyle = Theme.chartText;
    ctx.font = `${valueSize}px sans-serif`;
    ctx.textAlign = 'right';
    ctx.fillText(this.formatTick(top), padL - 8, padT + 4);
    ctx.fillText(this.formatTick(bottom), padL - 8, padT + plotH + 4);
    ctx.textAlign = 'left';

    // 数据点坐标
    const stepX = n > 1 ? plotW / (n - 1) : 0;
    const points: ChartPoint[] = [];
    for (let i = 0; i < n; i++) {
      points.push({ x: padL + (n > 1 ? stepX * i : plotW / 2), y: yOf(this.data[i].netKg) });
    }

    // 面积：从曲线落到零线，自上而下渐隐
    const baseY = Math.max(padT, Math.min(padT + plotH, zeroY));
    const gradient = ctx.createLinearGradient(0, padT, 0, padT + plotH);
    gradient.addColorStop(0, Theme.chartArea);
    gradient.addColorStop(1, '#00244E40');
    ctx.beginPath();
    ctx.moveTo(points[0].x, baseY);
    ctx.lineTo(points[0].x, points[0].y);
    this.traceCurve(points);
    ctx.lineTo(points[points.length - 1].x, baseY);
    ctx.closePath();
    ctx.fillStyle = gradient;
    ctx.fill();

    // 曲线
    ctx.beginPath();
    this.traceCurve(points);
    ctx.strokeStyle = Theme.green;
    ctx.lineWidth = 2;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.stroke();

    // 选中项：竖向发丝线 + 空心环，帮助定位某一天
    const selected = this.indexOfSelected();
    if (selected >= 0 && selected < points.length) {
      const sp = points[selected];
      ctx.strokeStyle = '#B9C8B6';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(sp.x, padT);
      ctx.lineTo(sp.x, padT + plotH);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(sp.x, sp.y, 6, 0, Math.PI * 2);
      ctx.strokeStyle = Theme.green;
      ctx.lineWidth = 1.6;
      ctx.stroke();
      if (this.data[selected].count > 0) {
        const label = this.data[selected].netKg.toFixed(2);
        ctx.font = `${this.getUIContext().vp2px(10)}px sans-serif`;
        const textW = ctx.measureText(label).width;
        const labelY = sp.y - 12 < padT + 10 ? sp.y + 20 : sp.y - 12;
        const labelX = Math.max(padL, Math.min(sp.x - textW / 2, padL + plotW - textW));
        ctx.fillStyle = Theme.ink;
        ctx.fillText(label, labelX, labelY);
      }
    }

    // 数据点只标有记录的日期：点代表真实记录，空白天不画点
    let lastCounted = -1;
    for (let i = 0; i < this.data.length; i++) {
      if (this.data[i].count > 0) { lastCounted = i; }
    }
    for (let i = 0; i < points.length; i++) {
      if (this.data[i].count === 0) {
        continue;
      }
      const isLast = i === lastCounted;
      ctx.beginPath();
      ctx.arc(points[i].x, points[i].y, isLast ? 3.4 : 2.4, 0, Math.PI * 2);
      ctx.fillStyle = Theme.green;
      ctx.fill();
      ctx.beginPath();
      ctx.arc(points[i].x, points[i].y, isLast ? 5.4 : 4.2, 0, Math.PI * 2);
      ctx.strokeStyle = Theme.paper;
      ctx.lineWidth = isLast ? 1.6 : 1.2;
      ctx.stroke();
    }

    // 横轴标签：按最大 5 个均匀取样，逐个做重叠检查，末尾优先补齐
    ctx.fillStyle = Theme.chartText;
    ctx.font = `${labelSize}px sans-serif`;
    const maxLabels = 5;
    const stride = Math.max(1, Math.ceil(n / maxLabels));
    let lastRight = padL - 8;
    for (let i = 0; i < n; i += stride) {
      lastRight = this.drawAxisLabel(i, points[i].x, padL, plotW, padT + plotH + 16, labelSize, lastRight);
    }
    this.drawAxisLabel(n - 1, points[n - 1].x, padL, plotW, padT + plotH + 16, labelSize, lastRight);
  }

  /** 绘制一个横轴标签，返回右边界；与前一个重叠时跳过并返回原边界 */
  private drawAxisLabel(index: number, centerX: number, padL: number, plotW: number,
    y: number, size: number, lastRight: number): number {
    const ctx = this.ctx;
    const label = this.data[index].label;
    const width = ctx.measureText(label).width;
    let x = centerX - width / 2;
    if (x < padL) { x = padL; }
    if (x + width > padL + plotW) { x = padL + plotW - width; }
    if (x < lastRight + 8) {
      return lastRight;
    }
    ctx.fillText(label, x, y);
    return x + width;
  }

  private formatTick(value: number): string {
    const abs = Math.abs(value);
    if (abs >= 100) {
      return value.toFixed(0);
    }
    return value.toFixed(1);
  }
}
