/**
 * 格式化与日期工具。
 * 日期按 Asia/Shanghai 自然日处理（第 9.2 节）；计算精度与显示舍入分开（第 8.3 节）。
 */

/** 补零 */
function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/** 日期工具 */
export class DateUtil {
  /** Date -> 'YYYY-MM-DD'（本地时区自然日） */
  static toDayKey(d: Date): string {
    return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
  }

  /** 今天 'YYYY-MM-DD' */
  static today(): string {
    return DateUtil.toDayKey(new Date());
  }

  /** Date -> 'YYYY-MM-DD HH:mm:ss' */
  static toDateTime(d: Date): string {
    return `${DateUtil.toDayKey(d)} ${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
  }

  /** 'YYYY-MM-DD' 解析为 Date（本地零时） */
  static parseDay(day: string): Date {
    const parts: string[] = day.split('-');
    if (parts.length !== 3) {
      return new Date();
    }
    const y = Number.parseInt(parts[0], 10);
    const m = Number.parseInt(parts[1], 10);
    const dd = Number.parseInt(parts[2], 10);
    return new Date(y, m - 1, dd);
  }

  static isValidDay(day: string): boolean {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) { return false; }
    const parsed = DateUtil.parseDay(day);
    return Number.isFinite(parsed.getTime()) && DateUtil.toDayKey(parsed) === day;
  }

  /** 两个自然日相差的天数 */
  static daysBetween(from: string, to: string): number {
    const a = DateUtil.parseDay(from).getTime();
    const b = DateUtil.parseDay(to).getTime();
    return Math.round((b - a) / 86400000);
  }

  /** 在给定自然日上加减天数，返回 'YYYY-MM-DD' */
  static addDays(day: string, delta: number): string {
    const d = DateUtil.parseDay(day);
    d.setDate(d.getDate() + delta);
    return DateUtil.toDayKey(d);
  }

  /** 是否为（本地时区）未来日期 */
  static isFuture(day: string): boolean {
    return day > DateUtil.today();
  }

  /** 自然日所属周一（周视图起点） */
  static weekStart(day: string): string {
    const d = DateUtil.parseDay(day);
    const dow = d.getDay() === 0 ? 7 : d.getDay();
    return DateUtil.addDays(day, 1 - dow);
  }

  /** 自然日所属月份 'YYYY-MM' */
  static monthKey(day: string): string {
    return day.substring(0, 7);
  }

  /** 自然日所属年份 'YYYY' */
  static yearKey(day: string): string {
    return day.substring(0, 4);
  }
}

/** 数值格式化 */
export class NumUtil {
  /** 按固定小数位格式化，避免浮点尾差 */
  static fixed(value: number, digits: number): string {
    if (!Number.isFinite(value)) {
      return '--';
    }
    const p = Math.pow(10, digits);
    // 十进制移位避免33.785 * 100变成3378.4999999999995；负数同样按绝对值四舍五入。
    const parts = Math.abs(value).toString().split('e');
    const exponent = parts.length > 1 ? Number(parts[1]) : 0;
    const shifted = Number(`${parts[0]}e${exponent + digits}`);
    return (Math.sign(value) * Math.round(shifted) / p).toFixed(digits);
  }

  /** 展示保留 2 位 */
  static show(value: number): string {
    return NumUtil.fixed(value, 2);
  }

  /** 带符号展示：正数加 +，负数保留 -，用于展示净变化与正负减排 */
  static signed(value: number, digits: number = 2): string {
    const s = NumUtil.fixed(Math.abs(value), digits);
    if (value > 0) {
      return `+${s}`;
    } else if (value < 0) {
      return `-${s}`;
    }
    return s;
  }

  /** 四舍五入到核算精度（4 位），保证同一输入同一结果 */
  static roundCalc(value: number): number {
    return Math.round(value * 10000) / 10000;
  }

  /** 向上取整到分（积分以整数计量） */
  static floorPoints(value: number): number {
    return Math.floor(value);
  }

  /** 安全解析用户输入的数量；非法返回 NaN */
  static parseQuantity(text: string): number {
    if (text === undefined || text === null) {
      return Number.NaN;
    }
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      return Number.NaN;
    }
    const v = Number(trimmed);
    return Number.isFinite(v) ? v : Number.NaN;
  }
}
