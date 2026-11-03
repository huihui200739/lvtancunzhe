import { Theme } from '../common/Theme';
import { StatBucket } from '../models/StatsModels';

/**
 * 正向贡献与增加排放：同一零基线的双向条形，细网格 + 圆角柱端。
 * 空数据或全零时给出安静的空状态。
 */
@Component
export struct BarChart {
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

  private allContributionsZero(): boolean {
    if (this.populatedCount() === 0) { return false; }
    for (const bucket of this.data) {
      if (bucket.count > 0 && (bucket.positiveKg !== 0 || bucket.negativeKg !== 0)) { return false; }
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
      } else if (this.allContributionsZero()) {
        Column() {
          Text('已记录 · 正向与增加排放均为 0').fontSize(12).fontColor(Theme.muted)
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

  /** 按触点位置换算到最近的柱；拖动时连续更新 */
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
    if (this.populatedCount() === 0 || this.allContributionsZero()) {
      this.ready = false;
      return;
    }
    if (this.ready) {
      this.draw();
    }
  }

  /** 单向柱体：只在一端收圆角，另一端贴零线 */
  private bar(x: number, y: number, width: number, height: number, up: boolean): void {
    if (height <= 0.5) {
      return;
    }
    const ctx = this.ctx;
    const r = Math.min(3, width / 2, height);
    ctx.beginPath();
    if (up) {
      ctx.moveTo(x, y + height);
      ctx.lineTo(x, y + r);
      ctx.quadraticCurveTo(x, y, x + r, y);
      ctx.lineTo(x + width - r, y);
      ctx.quadraticCurveTo(x + width, y, x + width, y + r);
      ctx.lineTo(x + width, y + height);
    } else {
      ctx.moveTo(x, y);
      ctx.lineTo(x, y + height - r);
      ctx.quadraticCurveTo(x, y + height, x + r, y + height);
      ctx.lineTo(x + width - r, y + height);
      ctx.quadraticCurveTo(x + width, y + height, x + width, y + height - r);
      ctx.lineTo(x + width, y);
    }
    ctx.closePath();
    ctx.fill();
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
      if (this.data[i].positiveKg > maxV) { maxV = this.data[i].positiveKg; }
      if (-this.data[i].negativeKg < minV) { minV = -this.data[i].negativeKg; }
    }
    const span = maxV - minV === 0 ? 1 : maxV - minV;
    const top = maxV > 0 ? maxV + span * 0.16 : 0;
    const bottom = minV < 0 ? minV - span * 0.16 : 0;
    const range = top - bottom === 0 ? 1 : top - bottom;
    const yOf = (v: number): number => padT + plotH * ((top - v) / range);
    const zeroY = yOf(0);

    ctx.lineWidth = 1;
    for (const v of [top, 0, bottom]) {
      const y = yOf(v);
      ctx.strokeStyle = v === 0 ? '#CBD5C6' : Theme.chartGrid;
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(padL + plotW, y);
      ctx.stroke();
    }

    ctx.fillStyle = Theme.chartText;
    ctx.font = `${valueSize}px sans-serif`;
    ctx.textAlign = 'right';
    ctx.fillText(this.formatTick(top), padL - 8, padT + 4);
    ctx.fillText(this.formatTick(bottom), padL - 8, padT + plotH + 4);
    ctx.textAlign = 'left';

    const slot = plotW / n;
    const barW = Math.max(6, Math.min(18, slot * 0.42));
    // 选中列加一层极淡底，点击后像账本里圈的格子
    const selected = this.indexOfSelected();
    if (selected >= 0) {
      ctx.fillStyle = '#F5F7F1';
      ctx.fillRect(padL + slot * selected, padT, slot, plotH);
      ctx.strokeStyle = '#CBD5C6';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(padL + slot * selected, padT);
      ctx.lineTo(padL + slot * selected, padT + plotH);
      ctx.moveTo(padL + slot * (selected + 1), padT);
      ctx.lineTo(padL + slot * (selected + 1), padT + plotH);
      ctx.stroke();
    }
    for (let i = 0; i < n; i++) {
      const cx = padL + slot * i + slot / 2;
      const b = this.data[i];
      const posH = plotH * (b.positiveKg / range);
      if (posH > 0.5) {
        ctx.fillStyle = Theme.green;
        this.bar(cx - barW / 2, zeroY - posH, barW, posH, true);
      }
      const negH = plotH * (b.negativeKg / range);
      if (negH > 0.5) {
        ctx.fillStyle = Theme.rust;
        this.bar(cx - barW / 2, zeroY, barW, negH, false);
      }
    }

    // 横轴标签：优先首位与末位，中间按密度补一个
    ctx.fillStyle = Theme.chartText;
    ctx.font = `${labelSize}px sans-serif`;
    const idxs: number[] = [0];
    if (n > 1) { idxs.push(n - 1); }
    if (n > 4) { idxs.push(Math.floor((n - 1) / 2)); }
    for (const i of idxs) {
      const label = this.data[i].label;
      const width = ctx.measureText(label).width;
      const cx = padL + slot * i + slot / 2;
      const x = Math.max(padL, Math.min(cx - width / 2, padL + plotW - width));
      ctx.fillText(label, x, padT + plotH + 16);
    }
  }

  private formatTick(value: number): string {
    return Math.abs(value) >= 100 ? value.toFixed(0) : value.toFixed(1);
  }
}
