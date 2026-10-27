import { Theme } from '../common/Theme';

/** Keep an editable quantity and its unit together, including while the text changes. */
@Component
export struct QuantityField {
  @Link value: string;
  @Prop unit: string = '';
  @Prop label: string = '数量';
  @Prop valueSize: number = 32;
  @State focused: boolean = false;
  onEdited: () => void = () => {};

  private inputWidth(): number {
    const width = this.getUIContext().getMeasureUtils().measureText({
      textContent: this.value.length > 0 ? this.value : '0',
      fontSize: `${this.valueSize}fp`, fontWeight: FontWeight.Medium
    });
    // A bounded editor scrolls long numbers internally; it never pushes the unit out.
    return Math.max(32, Math.min(160, Math.ceil(px2vp(width)) + 6));
  }

  private inputHeight(): number {
    const size = this.getUIContext().getMeasureUtils().measureTextSize({ textContent: '0123456789', fontSize: `${this.valueSize}fp` });
    return Math.max(58, px2vp(Number(size.height)) + 16);
  }

  build() {
    Row({ space: 8 }) {
      TextInput({ text: this.value, placeholder: '0' })
        .id(`${this.label}-数量`)
        .type(InputType.NUMBER_DECIMAL).fontSize(this.valueSize).fontWeight(FontWeight.Medium)
        .fontColor(Theme.green).height(this.inputHeight()).width(this.inputWidth()).padding(0)
        .backgroundColor(Color.Transparent).borderRadius(0)
        .border({ width: { bottom: 1 }, color: this.focused ? Theme.green : Theme.line })
        .accessibilityText(`${this.label}，可编辑`)
        .onEditChange((editing: boolean) => { this.focused = editing; })
        .onChange((text: string) => { this.value = text; this.onEdited(); })
      Text(this.unit).fontSize(13).fontColor(Theme.muted)
        .margin({ bottom: Math.max(8, (this.inputHeight() - this.valueSize) / 2 + 4) }).flexShrink(0)
    }.width('100%').alignItems(VerticalAlign.Bottom)
  }
}
