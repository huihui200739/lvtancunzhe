import { CarbonFactor } from '../models/CarbonFactor';
import { gasUnitLabel, GasScope } from '../common/Domain';
import { NumUtil } from '../common/Format';

/** A figure carries its factor identity and unit with the displayed result. */
export interface FigureExample {
  factorCode: string;
  action: string;
  quantity: number;
  inputUnit: string;
  gasScope: GasScope;
  resultKg: number;
  resultUnit: string;
  boundary: string;
}

export class FigureData {
  static fromFactor(factor: CarbonFactor, quantity: number, action: string): FigureExample {
    if (!Number.isFinite(quantity) || quantity <= 0 || !Number.isFinite(factor.value) || factor.value < 0) {
      throw new Error('图示数量或因子无效。');
    }
    return { factorCode: factor.code, action: action, quantity: quantity, inputUnit: factor.perUnit,
      gasScope: factor.gasScope, resultKg: NumUtil.roundCalc(quantity * factor.value),
      resultUnit: gasUnitLabel(factor.gasScope), boundary: factor.boundary };
  }
}
