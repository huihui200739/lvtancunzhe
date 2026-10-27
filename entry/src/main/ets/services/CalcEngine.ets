import { CalcInput, CalcOutcome, ScenarioInput, ScenarioResult } from '../models/CalcModels';
import { CarbonFactor, factorUnitText } from '../models/CarbonFactor';
import { ErrorCode } from '../common/AppError';
import { FactorRepository } from './FactorRepository';
import { BaselineType, BehaviorCategory, FactorUsableAs, FORMULA_VERSION, GasScope, ScenarioRole } from '../common/Domain';
import { NumUtil } from '../common/Format';

/**
 * 核算引擎（纯业务模块，无 UI 依赖，可单元测试）。
 *
 * 公式（第 5.1 节）：
 *   R = E基准 − E实际
 *   同距离同口径时 R = d × (EF基准 − EF实际)
 *   E = 数量 × 因子值（数量单位须与因子分母单位一致）
 *
 * 硬性约束：
 *  - 数量必须为有限数且大于 0；
 *  - 单位必须与因子分母单位一致；
 *  - 未通过核验的因子不得参与生产核算；
 *  - 跨气体口径不得混算；
 *  - 车辆公里与人公里不得直接混算，需按明确载客参数转换；
 *  - 结果保留原始符号，R 为负时如实返回，底层不改写成 0。
 */
export class CalcEngine {
  /**
   * 执行核算。
   * @param input 核算输入
   * @param repo 因子仓库
   * @param passengers 载客数（仅出行且基准为车辆公里时需要，> 0 才参与换算）
   */
  static calculate(input: CalcInput, repo: FactorRepository, passengers: number = 0): CalcOutcome {
    const empty = CalcEngine.makeEmpty(input);

    if (input.scenarios.length === 0) {
      return CalcEngine.fail(empty, ErrorCode.E_INPUT_EMPTY, '请至少填写一个情景后再核算。');
    }

    if (input.category === BehaviorCategory.TRAVEL && (!input.scenarios.some((s: ScenarioInput) => s.role === ScenarioRole.BASELINE) || !input.scenarios.some((s: ScenarioInput) => s.role === ScenarioRole.ACTUAL))) {
      return CalcEngine.fail(empty, ErrorCode.E_INPUT_EMPTY, '出行核算需要同时提供基准与实际情景。');
    }

    // 1) 逐情景校验与计算
    const results: ScenarioResult[] = [];
    const scopes: GasScope[] = [];
    let hasVkm = false;
    let hasPkm = false;

    for (const sc of input.scenarios) {
      const factor: CarbonFactor | undefined = repo.find(sc.factorCode);
      if (factor === undefined) {
        return CalcEngine.fail(empty, ErrorCode.E_FACTOR_NOT_FOUND, `未找到因子：${sc.factorCode}，暂不能估算。`);
      }
      if (factor.category !== input.category) { return CalcEngine.fail(empty, ErrorCode.E_INPUT_EMPTY, '行为类别与所选因子不一致。'); }
      if (!repo.isUsable(factor)) {
        return CalcEngine.fail(empty, ErrorCode.E_FACTOR_NOT_VERIFIED,
          `因子「${factor.scenarioLabel}」尚未通过来源核验，暂不能估算。`);
      }
      if (sc.role !== ScenarioRole.BASELINE && sc.role !== ScenarioRole.ACTUAL) { return CalcEngine.fail(empty, ErrorCode.E_FACTOR_ROLE_MISMATCH, '情景角色无效。'); }
      const roleCheck = CalcEngine.checkRole(factor, sc.role);
      if (roleCheck.length > 0) {
        return CalcEngine.fail(empty, ErrorCode.E_FACTOR_ROLE_MISMATCH, roleCheck);
      }
      if (!Number.isFinite(sc.quantity) || sc.quantity <= 0) {
        return CalcEngine.fail(empty, ErrorCode.E_QUANTITY_INVALID,
          `第 ${results.length + 1} 个情景的数量必须是大于 0 的有限数。`);
      }
      if (sc.unit !== factor.perUnit) {
        return CalcEngine.fail(empty, ErrorCode.E_UNIT_MISMATCH,
          `数量单位「${sc.unit}」与因子单位「${factorUnitText(factor)}」不一致。`);
      }

      if (factor.distanceBasis === 'vkm') {
        hasVkm = true;
      } else if (factor.distanceBasis === 'pkm') {
        hasPkm = true;
      }

      // 车辆公里按明确载客参数折算为人均份额
      let effectiveQuantity = sc.quantity;
      let conversionNote = '';
      if (factor.distanceBasis === 'vkm') {
        if (!Number.isFinite(passengers) || passengers <= 0) {
          return CalcEngine.fail(empty, ErrorCode.E_PASSENGER_MISMATCH,
            '该情景因子按车辆公里计，请填写载客人数后再核算（车辆公里与人公里不得直接混算）。');
        }
        effectiveQuantity = sc.quantity / passengers;
        conversionNote = `按载客 ${passengers} 人折算为人公里份额`;
      }

      const emission = NumUtil.roundCalc(effectiveQuantity * factor.value);
      if (!Number.isFinite(emission)) { return CalcEngine.fail(empty, ErrorCode.E_QUANTITY_INVALID, '数量过大，无法可靠核算。'); }
      if (scopes.indexOf(factor.gasScope) < 0) {
        scopes.push(factor.gasScope);
      }
      results.push({
        role: sc.role,
        factorCode: factor.code,
        factorVersion: factor.version,
        scenarioLabel: factor.scenarioLabel,
        label: sc.label.length > 0 ? sc.label : factor.scenarioLabel,
        quantity: sc.quantity,
        unit: factor.perUnit,
        factorValue: factor.value,
        factorUnit: factorUnitText(factor),
        effectiveQuantity: effectiveQuantity,
        passengers: factor.distanceBasis === 'vkm' ? passengers : 0,
        conversionNote: conversionNote,
        emissionKg: emission
      });
    }

    // 2) 不得跨气体口径混算
    if (scopes.length > 1) {
      return CalcEngine.fail(empty, ErrorCode.E_GAS_SCOPE_MIXED,
        '所选因子分属不同气体口径（CO₂ 与 CO₂e），请统一口径后再核算。');
    }

    // 3) R = ΣE基准 − ΣE实际
    let baselineSum = 0;
    let actualSum = 0;
    for (const r of results) {
      if (r.role === ScenarioRole.BASELINE) {
        baselineSum = baselineSum + r.emissionKg;
      } else {
        actualSum = actualSum + r.emissionKg;
      }
    }
    const reduction = NumUtil.roundCalc(baselineSum - actualSum);

    const formulaText = CalcEngine.buildFormula(results, reduction, input.baselineType);
    const outcome: CalcOutcome = {
      ok: true,
      errorCode: ErrorCode.OK,
      message: '',
      reductionKg: reduction,
      isNetIncrease: reduction < 0,
      gasScope: scopes[0],
      baselineType: input.baselineType,
      scenarioResults: results,
      formulaVersion: FORMULA_VERSION,
      formulaText: formulaText,
      roundingNote: '内部按 4 位小数运算，界面与导出按 2 位小数展示；先汇总后舍入。',
      gasScopes: scopes,
      comparable: true
    };
    return outcome;
  }

  /** 因子角色校验：基准因子不能当实际情景使用，反之亦然 */
  private static checkRole(factor: CarbonFactor, role: ScenarioRole): string {
    if (factor.usableAs === FactorUsableAs.BOTH) {
      return '';
    }
    if (factor.usableAs === FactorUsableAs.SINGLE) {
      // 单情景类因子只允许作为基准（对照）情景传入
      if (role === ScenarioRole.ACTUAL) {
        return `因子「${factor.scenarioLabel}」属于单情景对照类，不能作为实际情景使用。`;
      }
      return '';
    }
    if (role === ScenarioRole.BASELINE && factor.usableAs === FactorUsableAs.ACTUAL) {
      return `因子「${factor.scenarioLabel}」仅适用于实际情景，不能作为基准情景。`;
    }
    if (role === ScenarioRole.ACTUAL && factor.usableAs === FactorUsableAs.BASELINE) {
      return `因子「${factor.scenarioLabel}」仅适用于基准情景，不能作为实际情景。`;
    }
    return '';
  }

  /** 生成可读公式文本 */
  private static buildFormula(results: ScenarioResult[], reduction: number, baselineType: BaselineType): string {
    const parts: string[] = [];
    for (const r of results) {
      const roleText = r.role === ScenarioRole.BASELINE ? '基准' : '实际';
      const unitText = r.factorUnit;
      const effective = r.effectiveQuantity !== undefined ? r.effectiveQuantity : r.quantity;
      const conversion = r.conversionNote !== undefined && r.conversionNote.length > 0 ? `（${r.conversionNote}，折算数量 ${NumUtil.fixed(effective, 4)}）` : '';
      parts.push(`${roleText}「${r.scenarioLabel}」${NumUtil.fixed(r.quantity, 2)}${conversion} × ${r.factorValue} ${unitText} = ${NumUtil.fixed(r.emissionKg, 4)} kg`);
    }
    const typeText = baselineType === BaselineType.USER_DECLARED ? '用户声明的替代情景' : '方法学规定的统计基线';
    return `基准类型：${typeText}\n${parts.join('\n')}\nR = ΣE基准 − ΣE实际 = ${NumUtil.fixed(reduction, 4)} kg`;
  }

  /** 空结果模板 */
  private static makeEmpty(input: CalcInput): CalcOutcome {
    return {
      ok: false,
      errorCode: ErrorCode.OK,
      message: '',
      reductionKg: 0,
      isNetIncrease: false,
      gasScope: GasScope.CO2,
      baselineType: input.baselineType,
      scenarioResults: [],
      formulaVersion: FORMULA_VERSION,
      formulaText: '',
      roundingNote: '',
      gasScopes: [],
      comparable: false
    };
  }

  /** 失败结果 */
  private static fail(base: CalcOutcome, code: string, message: string): CalcOutcome {
    const out: CalcOutcome = {
      ok: false,
      errorCode: code,
      message: message,
      reductionKg: 0,
      isNetIncrease: false,
      gasScope: base.gasScope,
      baselineType: base.baselineType,
      scenarioResults: base.scenarioResults,
      formulaVersion: FORMULA_VERSION,
      formulaText: '',
      roundingNote: '',
      gasScopes: [],
      comparable: false
    };
    return out;
  }

  /** 便捷入口：单情景核算（节电 / 节水 / 回收 / 光盘），R 即该情景排放量 */
  static calculateSingle(category: BehaviorCategory, factorCode: string, quantity: number,
    unit: string, label: string, repo: FactorRepository): CalcOutcome {
    const scenarios: ScenarioInput[] = [
      { role: ScenarioRole.BASELINE, factorCode: factorCode, quantity: quantity, unit: unit, label: label }
    ];
    const input: CalcInput = {
      category: category,
      baselineType: BaselineType.STATISTICAL,
      scenarios: scenarios
    };
    return CalcEngine.calculate(input, repo);
  }

  /** 便捷入口：出行对照核算（基准 vs 实际） */
  static calculateTravel(baselineCode: string, actualCode: string, distanceKm: number,
    baselineType: BaselineType, repo: FactorRepository, passengers: number = 0,
    label: string = ''): CalcOutcome {
    const scenarios: ScenarioInput[] = [
      { role: ScenarioRole.BASELINE, factorCode: baselineCode, quantity: distanceKm, unit: 'km', label: label },
      { role: ScenarioRole.ACTUAL, factorCode: actualCode, quantity: distanceKm, unit: 'km', label: label }
    ];
    const input: CalcInput = {
      category: BehaviorCategory.TRAVEL,
      baselineType: baselineType,
      scenarios: scenarios
    };
    return CalcEngine.calculate(input, repo, passengers);
  }
}
