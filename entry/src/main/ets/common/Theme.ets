/** Calm botanical design tokens. All dimensions are vp. */
export class Theme {
  static readonly bg: string = '#F6F6F0';
  static readonly paper: string = '#FFFFFF';
  static readonly ink: string = '#203B33';
  static readonly green: string = '#244E40';
  static readonly muted: string = '#68766B';
  static readonly line: string = '#E6EAE0';
  static readonly sage: string = '#EAF0E3';
  static readonly lime: string = '#D8EBA6';
  static readonly rust: string = '#A65F46';
}

export function iconResource(name: string, color: string = Theme.green): Resource {
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

export function categoryTint(category: string): string {
  if (category === 'travel') { return '#E7EEDD'; }
  if (category === 'water_energy') { return '#F5EBD0'; }
  if (category === 'recycling') { return '#E6EBF2'; }
  return '#F5E4DC';
}
