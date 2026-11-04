/**
 * 全局设计令牌（vp）。白底墨字，主操作用墨黑，类别用四色识别；
 * 旧名称保留以免改动所有页面：green 现为主操作墨色，sage 为浅灰底，lime 为深色卡上的强调色。
 */
export class Theme {
  static readonly bg: string = '#FFFFFF';
  static readonly paper: string = '#F6F6F4';
  static readonly ink: string = '#16181D';
  static readonly green: string = '#16181D';
  static readonly muted: string = '#7A7E86';
  static readonly line: string = '#ECEBE6';
  static readonly sage: string = '#F1F1EE';
  static readonly lime: string = '#FFFFFF';
  static readonly rust: string = '#C8442C';
  static readonly cardRadius: number = 18;
  static readonly panelRadius: number = 22;
  static readonly heroRadius: number = 24;
  static readonly controlRadius: number = 12;
  static readonly chartGrid: string = '#EFEFEC';
  static readonly chartText: string = '#9A9DA3';
  static readonly chartArea: string = '#293B63E0';
}

/**
 * 存折视觉：白底、墨黑字，四类行为各有一个识别色；首页卡面用钞券式的扭索纹与虹彩渐变。
 * 印章红只用于记账状态（“核”“撤”），不作装饰。
 */
export class Passbook {
  static readonly page: string = '#FFFFFF';
  static readonly sheet: string = '#FFFFFF';
  static readonly wash: string = '#F6F6F4';
  static readonly rule: string = '#ECEBE6';
  static readonly ruleStrong: string = '#D6D4CC';
  static readonly print: string = '#16181D';
  static readonly faint: string = '#8A8D93';
  static readonly seal: string = '#C8442C';
  static readonly mono: string = 'monospace';
  static readonly serif: string = 'PassbookSerif';
  static readonly numeral: string = 'PassbookNumeral';
}

/** 四类行为的识别色：线条图标、存入单色带与账页色点共用 */
export class Hue {
  static readonly travel: string = '#3B63E0';
  static readonly travelTint: string = '#EEF2FD';
  static readonly energy: string = '#C47F00';
  static readonly energyTint: string = '#FDF5E4';
  static readonly recycle: string = '#0E8F6E';
  static readonly recycleTint: string = '#E8F6F1';
  static readonly food: string = '#DA5533';
  static readonly foodTint: string = '#FDEFEA';
}

export function categoryHue(category: string): string {
  if (category === 'travel') { return Hue.travel; }
  if (category === 'water_energy') { return Hue.energy; }
  if (category === 'recycling') { return Hue.recycle; }
  return Hue.food;
}

export function categoryTint(category: string): string {
  if (category === 'travel') { return Hue.travelTint; }
  if (category === 'water_energy') { return Hue.energyTint; }
  if (category === 'recycling') { return Hue.recycleTint; }
  return Hue.foodTint;
}

export function iconResource(name: string, color: string = Theme.green): Resource {
  if (color === Passbook.print) {
    if (name === 'leaf') { return $r('app.media.ic_leaf_ink'); }
    if (name === 'plan') { return $r('app.media.ic_plan_ink'); }
    if (name === 'chart') { return $r('app.media.ic_chart_ink'); }
    if (name === 'book') { return $r('app.media.ic_book_ink'); }
    if (name === 'user') { return $r('app.media.ic_user_ink'); }
    if (name === 'arrow') { return $r('app.media.ic_arrow_ink'); }
  }
  if (color === 'hue') {
    if (name === 'travel') { return $r('app.media.ic_travel_hue'); }
    if (name === 'energy') { return $r('app.media.ic_energy_hue'); }
    if (name === 'recycle') { return $r('app.media.ic_recycle_hue'); }
    if (name === 'food') { return $r('app.media.ic_food_hue'); }
  }
  if (name === 'plus' && color === Theme.paper) { return $r('app.media.ic_plus_light'); }
  if (name === 'badge' && color === Theme.lime) { return $r('app.media.ic_badge_light'); }
  if (name === 'plan') { return $r('app.media.ic_plan'); }
  if (name === 'chart') { return $r('app.media.ic_chart'); }
  if (name === 'book') { return $r('app.media.ic_book'); }
  if (name === 'user') { return $r('app.media.ic_user'); }
  if (name === 'travel') { return $r('app.media.ic_travel'); }
  if (name === 'energy') { return $r('app.media.ic_energy'); }
  if (name === 'recycle') { return $r('app.media.ic_recycle'); }
  if (name === 'food') { return $r('app.media.ic_food'); }
  if (name === 'plus') { return $r('app.media.ic_plus'); }
  if (name === 'back') { return $r('app.media.ic_back'); }
  if (name === 'arrow') { return $r('app.media.ic_arrow'); }
  if (name === 'badge') { return $r('app.media.ic_badge'); }
  return $r('app.media.ic_leaf');
}

export function categoryIcon(category: string): string {
  if (category === 'travel') { return 'travel'; }
  if (category === 'water_energy') { return 'energy'; }
  if (category === 'recycling') { return 'recycle'; }
  return 'food';
}
