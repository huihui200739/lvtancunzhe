import { Theme } from '../common/Theme';
import { FigureExample } from '../services/FigureData';

/**
 * 科普图示（T04）：全部为应用内布局/形状组件自绘，不引用任何外部图片素材；
 * 数字参数由调用方从因子库读取，与凭证口径一致，避免与数据漂移。
 * 视觉规则：形状差异 + 文字标签双通道传达，不完全依赖颜色；文字与底色对比满足可读。
 */

const CO2_INK: string = '#2F3E37';
const WARN_RED: string = '#B3402F';
const BLUE_DEEP: string = '#15508C';
const PLUM_DEEP: string = '#5B4A78';
const AMBER_DEEP: string = '#8A5300';
const CARD_BG: string = '#FBF8F1';

/** 图卡通用样式（虚线边框 + 图注），各图自行以 Column 承接 */
@Styles
function figureCardStyle() {
  .width('100%')
  .padding(14)
  .backgroundColor(CARD_BG)
  .borderRadius(18)
}

@Builder
function CardTitle(text: string) {
  Text(text).fontSize(12).fontWeight(FontWeight.Medium).fontColor(CO2_INK)
}

@Builder
function CardFoot(text: string, color: string) {
  Text(text).fontSize(10).lineHeight(16).fontColor(color).textAlign(TextAlign.Start)
}

/** 竖向柱 + 顶部数值 + 底部名称：柱高按值占比映射到 18..90vp */
@Builder
function Bar(val: number, maxVal: number, label: string, display: string, color: string) {
  Column({ space: 4 }) {
    Text(display).fontSize(11).fontColor(CO2_INK).fontWeight(FontWeight.Medium)
    Column()
      .width(30)
      .height(Math.max(18, Math.round(90 * (val / (maxVal > 0 ? maxVal : 1)))))
      .backgroundColor(color)
      .borderRadius(6)
      .border({ width: 1, color: CO2_INK })
    Text(label).fontSize(10).lineHeight(14).fontColor(Theme.muted).textAlign(TextAlign.Center)
  }
  .alignItems(HorizontalAlign.Center)
}

/**
 * 图示 1：电力因子口径对比（A02 / 复用于 A10）。
 * 四条柱：全国平均 / 不含市场非化石 / 化石能源 / 河南省级（本应用主用）。
 */
@Builder
export function FigureElec(vNational: number, vNonfossil: number, vFossil: number, vHenan: number) {
  Column({ space: 8 }) {
    CardTitle('图 · 电力因子：同一个电，口径不同')
    Row({ space: 14 }) {
      Bar(vNational, vFossil, '全国平均\nkgCO₂/kWh', vNational.toFixed(2), '#7FA7C6')
      Bar(vNonfossil, vFossil, '不含市场化\n非化石电量', vNonfossil.toFixed(2), '#C4AC74')
      Bar(vFossil, vFossil, '仅化石能源\n电力', vFossil.toFixed(2), '#D89C8E')
      Bar(vHenan, vFossil, '河南省级\n本项目用', vHenan.toFixed(2), Theme.green)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Bottom)
    CardFoot('柱高随因子值变化；凭证按选定口径折算并写明「算到哪一步」', Theme.muted)
  }
  .figureCardStyle()
  .border({ width: 1.2, color: Theme.line, style: BorderStyle.Dashed })
}

/** 图示 2：CO₂ 与 CO₂e 不可相加（A05） */
@Builder
export function FigureGas(paper: FigureExample, apple: FigureExample) {
  Column({ space: 8 }) {
    CardTitle('图 · 两种气体口径，分别取整')
    Row({ space: 16 }) {
      Column({ space: 6 }) {
        Circle({ width: 60, height: 60 }).fill('#DCE8D2').stroke(CO2_INK).strokeWidth(1.4)
        Text(`${paper.gasScope} 口径`).fontSize(10).fontColor(CO2_INK)
        Text(`${paper.action} ${paper.quantity} ${paper.inputUnit}`).fontSize(11).fontColor(CO2_INK)
        Text(`→ ${paper.resultKg.toFixed(2)} ${paper.resultUnit}`).fontSize(12).fontWeight(FontWeight.Medium).fontColor(CO2_INK)
      }
      .alignItems(HorizontalAlign.Center)
      Column({ space: 6 }) {
        Circle({ width: 60, height: 60 }).fill('#E8D9D3').stroke(WARN_RED).strokeWidth(1.4)
        Text(`${apple.gasScope} 口径`).fontSize(10).fontColor(CO2_INK)
        Text(`${apple.action} ${apple.quantity} ${apple.inputUnit}`).fontSize(11).fontColor(CO2_INK)
        Text(`→ ${apple.resultKg.toFixed(2)} ${apple.resultUnit}`).fontSize(12).fontWeight(FontWeight.Medium).fontColor(CO2_INK)
      }
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    Row({ space: 6 }) {
      Text('✕').fontSize(12).fontColor(WARN_RED).fontWeight(FontWeight.Bold)
      Text('气体口径与系统边界不同，分开展示，不直接相加').fontSize(10).fontColor(WARN_RED)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }
  .figureCardStyle()
  .border({ width: 1.2, color: Theme.line, style: BorderStyle.Dashed })
}

/** 图示 3：基准 − 实际 = 减排（A03 碳普惠 / A06 基准），note 请在调用处按文章语境给出 */
@Builder
export function FigureBaseline(gasoline: FigureExample, note: string) {
  Column({ space: 8 }) {
    CardTitle('图 · 没有对照，就没有减排量')
    Row({ space: 12 }) {
      Rect({ width: 52, height: 34 }).radius(8).fill('#ECD9CE').stroke(AMBER_DEEP).strokeWidth(1.4)
      Column({ space: 3 }) {
        Text('基准情景 · 替代前的燃油出行').fontSize(11).fontWeight(FontWeight.Medium).fontColor(CO2_INK)
        Text(`${gasoline.quantity} ${gasoline.inputUnit} 汽油 ≈ ${gasoline.resultKg.toFixed(2)} ${gasoline.resultUnit}`).fontSize(11).lineHeight(17).fontColor(AMBER_DEEP).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(VerticalAlign.Center)
    Text('−').fontSize(20).fontColor(CO2_INK).width('100%').textAlign(TextAlign.Center)
    Row({ space: 12 }) {
      Rect({ width: 52, height: 34 }).radius(8).fill(Theme.sage).stroke(Theme.green).strokeWidth(1.4)
      Column({ space: 3 }) {
        Text('实际情景 · 替代后的步行/普通骑行').fontSize(11).fontWeight(FontWeight.Medium).fontColor(CO2_INK)
        Text('仅限有依据的替代行程').fontSize(10).lineHeight(16).fontColor(Theme.muted).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(VerticalAlign.Center)
    Text('=').fontSize(20).fontColor(CO2_INK).width('100%').textAlign(TextAlign.Center)
    Row({ space: 12 }) {
      Rect({ width: 52, height: 34 }).radius(8).fill('#F4EFE2').stroke(CO2_INK).strokeWidth(1.8).strokeDashArray([6, 4])
      Column({ space: 3 }) {
        Text('减排量 · 两者之差').fontSize(11).fontWeight(FontWeight.Medium).fontColor(CO2_INK)
        Text('先核对情景，再记入存折').fontSize(10).lineHeight(16).fontColor(Theme.muted).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(VerticalAlign.Center)
    CardFoot(note, AMBER_DEEP)
  }
  .figureCardStyle()
  .border({ width: 1.2, color: Theme.line, style: BorderStyle.Dashed })
}

/** 图示 4：应用内积分闭环，与碳市场断开（A04） */
@Builder
export function FigureBubble() {
  Column({ space: 8 }) {
    CardTitle('图 · 积分只是应用内激励')
    Row({ space: 10 }) {
      Column({ space: 6 }) {
        Text('已记录行为 → 积分 → 虚拟徽章/证书').fontSize(12).fontColor(CO2_INK)
        Text('闭环：不产生现金、不可转让、不在官方登记').fontSize(10).fontColor(Theme.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Column({ space: 4 }) {
        Rect({ width: 86, height: 54 }).radius(10).fill('#EFEAE2').stroke(Theme.muted).strokeWidth(1.2).strokeDashArray([5, 4])
        Text('碳市场（需核证）✕').fontSize(10).fontColor(Theme.muted).textAlign(TextAlign.Center)
      }
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
  .figureCardStyle()
  .border({ width: 1.2, color: Theme.line, style: BorderStyle.Dashed })
}

/** 图示 5：记录范围与边界（A01）：四类场景 → 存折；自报数据不入官方核算 */
@Builder
export function FigureScope() {
  Column({ space: 8 }) {
    CardTitle('图 · 记录的是哪一段')
    Flex({ wrap: FlexWrap.Wrap }) {
      Text('出行').fontSize(11).fontColor(Theme.green).padding({ left: 9, right: 9, top: 4, bottom: 4 }).backgroundColor(Theme.sage).borderRadius(8).margin(3)
      Text('宿舍用电水').fontSize(11).fontColor(Theme.green).padding({ left: 9, right: 9, top: 4, bottom: 4 }).backgroundColor(Theme.sage).borderRadius(8).margin(3)
      Text('旧物回收').fontSize(11).fontColor(Theme.green).padding({ left: 9, right: 9, top: 4, bottom: 4 }).backgroundColor(Theme.sage).borderRadius(8).margin(3)
      Text('餐饮').fontSize(11).fontColor(Theme.green).padding({ left: 9, right: 9, top: 4, bottom: 4 }).backgroundColor(Theme.sage).borderRadius(8).margin(3)
    }
    .width('100%')
    Text('↓  逐条记录，来源与依据可填').fontSize(10).fontColor(CO2_INK)
    Rect({ width: '100%', height: 30 }).radius(8).fill(Theme.sage).stroke(Theme.green).strokeWidth(1.4)
    Text('我的存折（已记录行为的估算减排）').fontSize(11).fontColor(CO2_INK)
    CardFoot('右下方框示意「官方核算/碳资产」通道关闭：自报行为仅用于自我观察与激励', WARN_RED)
  }
  .figureCardStyle()
  .border({ width: 1.2, color: Theme.line, style: BorderStyle.Dashed })
}

/** 图示 6：分别显示实际因子的系统边界，不假设整份账本使用同一边界。 */
@Builder
export function FigureBoundary(examples: FigureExample[]) {
  Column({ space: 10 }) {
    CardTitle('图 · 每种场景，有自己的核算边界')
    ForEach(examples, (item: FigureExample) => {
      Column({ space: 4 }) {
        Text(`${item.action} · ${item.resultUnit}`).fontSize(11).fontColor(Theme.green).fontWeight(FontWeight.Medium)
        Text(item.boundary).fontSize(10).lineHeight(17).fontColor(CO2_INK).width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)
    }, (item: FigureExample) => item.factorCode)
    CardFoot('边界不同，数字含义不同；先核对可比性与重复计量风险，再解释结果。', Theme.muted)
  }.figureCardStyle().border({ width: 1.2, color: Theme.line, style: BorderStyle.Dashed })
}

/** 图示 7：存折是完整足迹的子集（A08）：大虚圈（全部排放）内嵌小实圈（已记录） */
@Builder
export function FigurePartial() {
  Column({ space: 8 }) {
    CardTitle('图 · 存折 ≠ 我的所有排放')
    Stack({ alignContent: Alignment.Center }) {
      Ellipse({ width: 244, height: 104 }).fill('#EFEAE2').stroke(Theme.muted).strokeWidth(1.6).strokeDashArray([7, 5])
      Ellipse({ width: 140, height: 62 }).fill(Theme.sage).stroke(Theme.green).strokeWidth(1.8)
      Text('已记录、有依据的场景').fontSize(10).fontColor(Theme.green)
    }
    .width('100%')
    .height(112)
    CardFoot('大虚圈示意「实际还有很多未记录的行为与排放」，因此存折只能代表本次记录范围', Theme.muted)
  }
  .figureCardStyle()
  .border({ width: 1.2, color: Theme.line, style: BorderStyle.Dashed })
}

/** 图示 8：通勤替代关系（A09） */
@Builder
export function FigureCommute(gasoline: FigureExample) {
  Column({ space: 8 }) {
    CardTitle('图 · 真的被替代了，才计入')
    Row({ space: 8 }) {
      Column({ space: 4 }) {
        Text('驾车 / 燃油出行').fontSize(12).fontColor(CO2_INK).fontWeight(FontWeight.Medium)
        TagText('基准情景', '#ECD9CE', AMBER_DEEP)
        Text(`${gasoline.quantity} ${gasoline.inputUnit} 汽油 ≈ ${gasoline.resultKg.toFixed(2)} ${gasoline.resultUnit}`).fontSize(10).lineHeight(16).fontColor(AMBER_DEEP).width('100%').textAlign(TextAlign.Center)
      }
      .alignItems(HorizontalAlign.Center).layoutWeight(1)
      Column({ space: 4 }) {
        Text('→').fontSize(18)
        Text('真替代').fontSize(9).fontColor(Theme.green)
      }
      .alignItems(HorizontalAlign.Center).width(28)
      Column({ space: 4 }) {
        Text('普通骑行 / 步行').fontSize(12).fontColor(CO2_INK).fontWeight(FontWeight.Medium)
        TagText('实际情景', Theme.sage, Theme.green)
        Text('本图限定汽油燃烧直接排放\n差额才入存折').fontSize(10).lineHeight(15).fontColor(Theme.muted).width('100%').textAlign(TextAlign.Center)
      }
      .alignItems(HorizontalAlign.Center).layoutWeight(1)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    CardFoot('若只是顺路多坐、或本来就不开车，就构不成替代，也就没有基准可减', WARN_RED)
  }
  .figureCardStyle()
  .border({ width: 1.2, color: Theme.line, style: BorderStyle.Dashed })
}

/** 图示 9：回收两阶段（A11）：投放是参与，实际再生利用才按重量核算 */
@Builder
export function FigureRecycle(paper: FigureExample) {
  Column({ space: 8 }) {
    CardTitle('图 · 回收的减排来自两个阶段')
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text('分类投放').fontSize(12).fontColor(CO2_INK).fontWeight(FontWeight.Medium)
        TagText('参与行为（不计 kg）', '#EFE3DA', AMBER_DEEP)
      }
      .alignItems(HorizontalAlign.Center).layoutWeight(1)
      Text('→').fontSize(18).fontColor(CO2_INK)
      Column({ space: 4 }) {
        Text('实际再生利用').fontSize(12).fontColor(CO2_INK).fontWeight(FontWeight.Medium)
        TagText(`废纸 1 kg 再生 → ${paper.resultKg.toFixed(2)} ${paper.resultUnit}`, '#F4EFE2', CO2_INK)
      }
      .alignItems(HorizontalAlign.Center).layoutWeight(1)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    CardFoot('闸门：材料越纯、再生路径越明确，数字越可靠；只投放不等于已经再生', AMBER_DEEP)
  }
  .figureCardStyle()
  .border({ width: 1.2, color: Theme.line, style: BorderStyle.Dashed })
}

/** 图示 10：光盘行动（A12）：先少取，再谈吃完 */
@Builder
export function FigurePlate(apple: FigureExample) {
  Column({ space: 8 }) {
    CardTitle('图 · 少取在前，光盘在后')
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text('少打一份（首选）').fontSize(12).fontColor(CO2_INK).fontWeight(FontWeight.Medium)
        Row({ space: 6 }) {
          Rect({ width: 44, height: 40 }).radius(6).fill('#F3E6DE').stroke(PLUM_DEEP).strokeWidth(1)
          Text('→').fontSize(14)
          Rect({ width: 26, height: 24 }).radius(5).fill('#F3E6DE').stroke(PLUM_DEEP).strokeWidth(1)
        }
        .alignItems(VerticalAlign.Center)
        Text('份量从大变小：源头浪费随之减少').fontSize(10).lineHeight(16).fontColor(Theme.muted).width('100%').textAlign(TextAlign.Center)
      }
      .alignItems(HorizontalAlign.Center).layoutWeight(1)
      Column({ space: 4 }) {
        Text('光盘（参与）').fontSize(12).fontColor(CO2_INK).fontWeight(FontWeight.Medium)
        TagText('只记参与 · 不折算 kg', '#EFE3DA', AMBER_DEEP)
        Text(`可核算的参照场景：\n减少采购 ${apple.quantity} ${apple.inputUnit} 苹果 → ${apple.resultKg.toFixed(1)} ${apple.resultUnit}`).fontSize(10).lineHeight(15).fontColor(CO2_INK).width('100%').textAlign(TextAlign.Center)
      }
      .alignItems(HorizontalAlign.Center).layoutWeight(1)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    CardFoot('把多打的硬吃完，不能把已产生的排放变没；顺序是先少取', WARN_RED)
  }
  .figureCardStyle()
  .border({ width: 1.2, color: Theme.line, style: BorderStyle.Dashed })
}

/** 底色标签：深色文字保证对比 */
@Builder
function TagText(text: string, bg: string, fg: string) {
  Text(text)
    .width('100%')
    .fontSize(10.5)
    .fontColor(fg)
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(bg)
    .borderRadius(8)
    .textAlign(TextAlign.Center)
}
