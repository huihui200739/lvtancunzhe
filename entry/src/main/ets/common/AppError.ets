/**
 * 统一错误码与返回结构。
 * 第 8.2 节要求 10 月 19 日前确定入参、返回模型与错误码。
 */

/** 错误码。E_ 前缀便于日志检索。 */
export class ErrorCode {
  static readonly OK = 'OK';
  static readonly E_INPUT_EMPTY = 'E_INPUT_EMPTY';                 // 缺少必要输入
  static readonly E_QUANTITY_INVALID = 'E_QUANTITY_INVALID';       // 数量非有限数 / 小于等于 0
  static readonly E_UNIT_MISMATCH = 'E_UNIT_MISMATCH';             // 单位与因子口径不符
  static readonly E_FACTOR_NOT_FOUND = 'E_FACTOR_NOT_FOUND';       // 找不到因子
  static readonly E_FACTOR_NOT_VERIFIED = 'E_FACTOR_NOT_VERIFIED'; // 因子未通过核验
  static readonly E_FACTOR_ROLE_MISMATCH = 'E_FACTOR_ROLE_MISMATCH'; // 因子不能用于该情景角色
  static readonly E_GAS_SCOPE_MIXED = 'E_GAS_SCOPE_MIXED';         // 跨气体口径混算
  static readonly E_FUTURE_DATE = 'E_FUTURE_DATE';                 // 未来日期不能作为已完成行为
  static readonly E_PASSENGER_MISMATCH = 'E_PASSENGER_MISMATCH';   // 车辆公里与人公里混用
  static readonly E_DUPLICATE_REWARD = 'E_DUPLICATE_REWARD';       // 同一请求重复提交
  static readonly E_BALANCE_INSUFFICIENT = 'E_BALANCE_INSUFFICIENT'; // 余额不足
  static readonly E_RESTORE_INVALID = 'E_RESTORE_INVALID';         // 备份文件结构非法
  static readonly E_RESTORE_VERSION = 'E_RESTORE_VERSION';         // 备份版本高于当前
  static readonly E_PLAN_NO_CANDIDATE = 'E_PLAN_NO_CANDIDATE';     // 无可用候选任务
  static readonly E_STORAGE = 'E_STORAGE';                         // 数据库错误
  static readonly E_IO = 'E_IO';                                   // 文件错误
}

/** 通用返回结构：要么成功带数据，要么失败带可读信息。 */
export class Result<T> {
  ok: boolean;
  code: string;
  message: string;
  data: T | null;

  private constructor(ok: boolean, code: string, message: string, data: T | null) {
    this.ok = ok;
    this.code = code;
    this.message = message;
    this.data = data;
  }

  static success<T>(data: T): Result<T> {
    return new Result<T>(true, ErrorCode.OK, '', data);
  }

  static failure<T>(code: string, message: string): Result<T> {
    return new Result<T>(false, code, message, null);
  }
}
