import { PlanConstraints, PlanProposal, PlanSolution, TaskTemplate } from '../models/PlanModels';
import { FactorRepository } from './FactorRepository';
import { CalcEngine } from './CalcEngine';
import { CarbonFactor } from '../models/CarbonFactor';
import { BehaviorCategory, BaselineType, GasScope } from '../common/Domain';
import { DateUtil } from '../common/Format';
import { ErrorCode } from '../common/AppError';

/**
 * 七日减排计划引擎（纯业务模块，无 UI 依赖，可单元测试）。
 * 第 6.2 节：确定性贪心，不宣称全局最优。
 *
 * 步骤：
 *   1) 硬约束筛选：剔除类别不接受、用户排除、单次超出总预算、无可用日期、不适用「替代驾车」的任务；
 *   2) 以核算引擎实时计算每个「模板 × 日期」的预计结果（不硬编码减排数字）；
 *   3) 每份目标只用一种气体口径：按各口径潜在贡献选择主口径，其他口径降级为参与任务；
 *   4) 按「额外时间升序 → 额外费用升序 → 预计贡献降序 → 模板编号 → 日期」排序后贪心组合；
 *   5) 每次加入前检查累计时间、累计费用、频次上限与同日互斥组；候选规模 ≤ 30，窗口 ≤ 7 天；
 *   6) 目标未达成时如实给出剩余差额与可读建议，不虚增次数或抬高因子。
 *
 * 相同输入必须产生相同方案：全程不使用随机数，排序键完全确定。
 */

/** 内部候选（模板 × 日期） */
interface Candidate {
  templateId: string;
  name: string;
  category: BehaviorCategory;
  day: string;
  expectedKg: number;
  quantity: number;
  unit: string;
  extraMinutes: number;
  extraCost: number;
  mutexGroup: string;
  maxTimesPerWeek: number;
  participationOnly: boolean;
  gasScope: string;
  reason: string;
}

const WEEKDAY_LABELS: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
/** 计划窗口固定 7 天，候选规模上限 30（第 6.2 节） */
const MAX_CANDIDATES = 30;
/** 参与任务最多纳入的计划条数 */
const MAX_PARTICIPATION = 3;
/** 出行替代任务的基准：被替代的燃油私家车 */
const TRAVEL_BASELINE_SUBITEM = 'drive_gasoline';
/** 无排放的出行方式，用于排除「本来就零排放却推荐替代驾车」 */
const ZERO_EMISSION_SUBITEMS: string[] = ['walk', 'bike'];

export class PlanEngine {

  /** 生成七日计划方案 */
  static generate(constraints: PlanConstraints, templates: TaskTemplate[],
    repo: FactorRepository, reserved: PlanProposal[] = []): PlanSolution {
    const trace: string[] = [];
    if (!DateUtil.isValidDay(constraints.startDay) || !Number.isFinite(constraints.targetKg) || constraints.targetKg <= 0 || !Number.isFinite(constraints.budgetMinutes) || constraints.budgetMinutes < 0 || !Number.isFinite(constraints.budgetCost) || constraints.budgetCost < 0 || ['', 'CO2', 'CO2e'].indexOf(constraints.gasScope) < 0) {
      return { ok: false, code: ErrorCode.E_QUANTITY_INVALID, message: '请填写有效的日期、目标、预算和气体口径。', proposals: [], plannedKg: 0, gapKg: 0, participationCount: 0, targetMet: false, gasScope: '', trace: trace };
    }
    const week = PlanEngine.sevenDays(constraints.startDay);
    const endDay = week.length > 0 ? week[week.length - 1] : constraints.startDay;
    trace.push(`计划窗口：${constraints.startDay} 至 ${endDay}，共 ${week.length} 个自然日。`);

    // 可用日期：默认七天全可用
    const usableDays: string[] = [];
    if (constraints.availableDays.length === 0) {
      for (const d of week) {
        usableDays.push(d);
      }
    } else {
      for (const d of week) {
        if (constraints.availableDays.indexOf(d) >= 0) {
          usableDays.push(d);
        }
      }
    }
    trace.push(`可用日期 ${usableDays.length} 天。`);

    // 用户通常出行方式
    const usualFactor: CarbonFactor | undefined = repo.findBySubItem(constraints.usualTravelSubItem);
    const usualWay = usualFactor !== undefined ? usualFactor.scenarioLabel : '未填写';
    let usuallyClean = ZERO_EMISSION_SUBITEMS.indexOf(constraints.usualTravelSubItem) >= 0;
    if (usualFactor !== undefined && usualFactor.value <= 0) {
      usuallyClean = true;
    }
    trace.push(`用户通常出行方式：${usualWay}${usuallyClean ? '（本就不产生驾车排放）' : ''}。`);

    // 1) 展开候选
    const raw: Candidate[] = [];
    for (const t of templates) {
      const excluded = PlanEngine.filterTemplate(t, constraints, usuallyClean, trace);
      if (excluded) {
        continue;
      }
      if (PlanEngine.isOfferable(t, repo)) {
        PlanEngine.expandTemplate(t, usableDays, repo, usualWay, raw);
      } else {
        trace.push(`跳过「${t.name}」：该类别缺少可用的已核验因子，完成录入无法落库。`);
      }
    }

    if (raw.length === 0 && reserved.length === 0) {
      return {
        ok: false,
        code: ErrorCode.E_PLAN_NO_CANDIDATE,
        message: '在当前约束下没有可安排的候选任务。请放宽时间或费用预算、增加可用日期，或勾选更多愿意尝试的行为。',
        proposals: [],
        plannedKg: 0,
        gapKg: constraints.targetKg > 0 ? constraints.targetKg : 0,
        participationCount: 0,
        targetMet: constraints.targetKg <= 0,
        gasScope: '',
        trace: trace
      };
    }

    // 2) 选择主口径
    const primaryScope = constraints.gasScope.length > 0 ? constraints.gasScope : PlanEngine.chooseScope(raw, trace);
    for (const c of raw) {
      if (!c.participationOnly && c.gasScope.length > 0 && c.gasScope !== primaryScope && c.expectedKg > 0) {
        c.participationOnly = true;
        c.reason = `${c.reason} 该任务气体口径为 ${c.gasScope}，与本次目标口径 ${primaryScope} 不同，仅作参与任务，收益不计入目标总量。`;
        c.expectedKg = 0;
      }
    }

    // 3) 排序（确定性）
    const reductions: Candidate[] = [];
    const participations: Candidate[] = [];
    for (const c of raw) {
      if (c.participationOnly || c.expectedKg <= 0) {
        c.expectedKg = 0;
        c.participationOnly = true;
        participations.push(c);
      } else {
        reductions.push(c);
      }
    }
    PlanEngine.sortCandidates(reductions);
    PlanEngine.sortCandidates(participations);

    // 4) 贪心组合
    const selected: Candidate[] = [];
    const countByTemplate: Map<string, number> = new Map<string, number>();
    const mutexByDay: Map<string, string[]> = new Map<string, string[]>();
    let minutesUsed = 0;
    let costUsed = 0;
    let plannedKg = 0;
    let reservedParticipation = 0;
    for (const r of reserved) {
      const template = templates.find((t: TaskTemplate) => t.templateId === r.templateId);
      const candidate: Candidate = { templateId: r.templateId, name: r.name, category: r.category, day: r.day,
        expectedKg: r.expectedKg, quantity: r.quantity, unit: r.unit, extraMinutes: r.extraMinutes,
        extraCost: r.extraCost, mutexGroup: template !== undefined ? template.mutexGroup : '',
        maxTimesPerWeek: template !== undefined ? template.maxTimesPerWeek : 1, participationOnly: r.participationOnly,
        gasScope: primaryScope, reason: r.reason };
      PlanEngine.accept(candidate, selected, countByTemplate, mutexByDay);
      minutesUsed += r.extraMinutes; costUsed += r.extraCost;
      if (r.participationOnly) { reservedParticipation++; } else { plannedKg += r.expectedKg; }
    }
    if (minutesUsed > constraints.budgetMinutes || costUsed > constraints.budgetCost + 0.0001) {
      return { ok: false, code: ErrorCode.E_PLAN_NO_CANDIDATE, message: '新预算低于已完成任务的时间或费用，请增加预算。原计划保持不变。',
        proposals: [], plannedKg: 0, gapKg: constraints.targetKg, participationCount: 0, targetMet: false, gasScope: primaryScope, trace: trace };
    }

    for (const c of reductions) {
      if (reserved.some((r: PlanProposal) => r.templateId === c.templateId && r.day === c.day)) { continue; }
      if (selected.length >= MAX_CANDIDATES) {
        break;
      }
      if (constraints.targetKg > 0 && plannedKg >= constraints.targetKg) {
        break;
      }
      if (!PlanEngine.canAdd(c, constraints, countByTemplate, mutexByDay, minutesUsed, costUsed)) {
        continue;
      }
      PlanEngine.accept(c, selected, countByTemplate, mutexByDay);
      minutesUsed = minutesUsed + c.extraMinutes;
      costUsed = costUsed + c.extraCost;
      plannedKg = plannedKg + c.expectedKg;
    }
    trace.push(`贪心选取：减排任务 ${selected.length} 条，预计 ${plannedKg.toFixed(4)} kg，累计额外 ${minutesUsed} 分钟 / ${costUsed.toFixed(2)} 元。`);

    // 5) 参与任务（不纳入目标可达性）
    let participationAdded = reservedParticipation;
    for (const c of participations) {
      if (reserved.some((r: PlanProposal) => r.templateId === c.templateId && r.day === c.day)) { continue; }
      if (selected.length >= MAX_CANDIDATES || participationAdded >= MAX_PARTICIPATION) {
        break;
      }
      if (!PlanEngine.canAdd(c, constraints, countByTemplate, mutexByDay, minutesUsed, costUsed)) {
        continue;
      }
      PlanEngine.accept(c, selected, countByTemplate, mutexByDay);
      minutesUsed = minutesUsed + c.extraMinutes;
      costUsed = costUsed + c.extraCost;
      participationAdded = participationAdded + 1;
    }
    if (participationAdded > 0) {
      trace.push(`参与任务 ${participationAdded} 条：缺少可比数量或口径不同，只计参与积分。`);
    }

    if (selected.length === 0) {
      return {
        ok: false,
        code: ErrorCode.E_PLAN_NO_CANDIDATE,
        message: '候选任务在预算或互斥约束下无法组合出可行方案。请放宽时间或费用预算后再试。',
        proposals: [],
        plannedKg: 0,
        gapKg: constraints.targetKg > 0 ? constraints.targetKg : 0,
        participationCount: 0,
        targetMet: constraints.targetKg <= 0,
        gasScope: primaryScope,
        trace: trace
      };
    }

    const gap = constraints.targetKg > plannedKg ? constraints.targetKg - plannedKg : 0;
    const targetMet = gap <= 0;
    let message = '';
    if (targetMet) {
      message = `已在约束内安排 ${selected.length} 条任务，预计达成目标。`;
    } else {
      message = `在现有约束内最多可安排 ${plannedKg.toFixed(2)} kg，仍差 ${gap.toFixed(2)} kg。建议降低目标、放宽时间或费用预算，或增加可执行的减排行为；本方案不会通过虚增次数或抬高因子补足目标。`;
    }
    trace.push(targetMet ? '目标达成。' : `目标未达成，剩余差额 ${gap.toFixed(4)} kg。`);

    const proposals: PlanProposal[] = [];
    for (const c of selected) {
      proposals.push({
        templateId: c.templateId,
        name: c.name,
        category: c.category,
        day: c.day,
        expectedKg: c.expectedKg,
        quantity: c.quantity,
        unit: c.unit,
        extraMinutes: c.extraMinutes,
        extraCost: c.extraCost,
        reason: c.reason,
        participationOnly: c.participationOnly
      });
    }
    // 按日期与模板稳定排序输出
    proposals.sort((a: PlanProposal, b: PlanProposal) => {
      if (a.day !== b.day) {
        return a.day < b.day ? -1 : 1;
      }
      return a.templateId < b.templateId ? -1 : (a.templateId > b.templateId ? 1 : 0);
    });

    return {
      ok: true,
      code: ErrorCode.OK,
      message: message,
      proposals: proposals,
      plannedKg: plannedKg,
      gapKg: gap,
      participationCount: participationAdded,
      targetMet: targetMet,
      gasScope: primaryScope,
      trace: trace
    };
  }

  // —— 内部 ——

  /** 硬约束筛选，返回 true 表示应剔除 */
  private static filterTemplate(t: TaskTemplate, c: PlanConstraints, usuallyClean: boolean,
    trace: string[]): boolean {
    if (c.excludedTemplateIds.indexOf(t.templateId) >= 0) {
      trace.push(`剔除 ${t.templateId}「${t.name}」：用户已排除。`);
      return true;
    }
    if (c.acceptedCategories.length > 0 && c.acceptedCategories.indexOf(t.category) < 0) {
      trace.push(`剔除 ${t.templateId}「${t.name}」：不在用户愿意尝试的类别内。`);
      return true;
    }
    if (t.extraMinutes > c.budgetMinutes) {
      trace.push(`剔除 ${t.templateId}「${t.name}」：单次额外时间 ${t.extraMinutes} 分钟超过总预算 ${c.budgetMinutes} 分钟。`);
      return true;
    }
    if (t.extraCost > c.budgetCost + 0.0001) {
      trace.push(`剔除 ${t.templateId}「${t.name}」：单次额外费用 ${t.extraCost} 元超过总预算 ${c.budgetCost} 元。`);
      return true;
    }
    if (t.category === BehaviorCategory.TRAVEL && t.substituteScenario === '驾车' && usuallyClean) {
      trace.push(`剔除 ${t.templateId}「${t.name}」：用户通常出行方式本就不产生驾车排放，不推荐替代驾车。`);
      return true;
    }
    return false;
  }

  /** 把一个模板展开到各可用日期 */
  /**
   * 只提供「用户能真正完成」的任务模板。
   * 所有模板均可安排；缺少可用因子时走独立参与流程，不产生减排记录。
   */
  private static isOfferable(t: TaskTemplate, repo: FactorRepository): boolean {
    // Missing factors are now supported by the separate participation-only flow.
    return true;
  }

  private static expandTemplate(t: TaskTemplate, usableDays: string[],
    repo: FactorRepository, usualWay: string, out: Candidate[]): void {    const weekdayOf = PlanEngine.weekday;
    let factor: CarbonFactor | undefined = undefined;
    if (t.factorSubItem.length > 0) {
      factor = repo.findBySubItem(t.factorSubItem);
    }
    let baseline: CarbonFactor | undefined = undefined;
    if (t.category === BehaviorCategory.TRAVEL) {
      baseline = repo.findBySubItem(TRAVEL_BASELINE_SUBITEM);
    }

    let baseParticipation = (t.category === BehaviorCategory.TRAVEL && baseline === undefined) || !t.hasComparableQuantity || t.factorSubItem.length === 0 || factor === undefined;
    let note = '';
    if (t.category === BehaviorCategory.TRAVEL && baseline === undefined) { note = '出行需另填个人汽油用量对照，本计划只安排参与，不预估减排量。'; }
    else if (baseParticipation && !t.hasComparableQuantity) {
      note = '该任务缺少可比较数量，只计参与积分。';
    } else if (baseParticipation && factor === undefined) {
      note = '缺少已核验的可用因子，暂不能估算，只计参与积分。';
    }

    // 预计贡献（复用核算引擎；出行按单车载客 1 人对照）
    let expected = 0;
    let scope = '';
    let unit = `${t.measureUnit}`;
    if (!baseParticipation && factor !== undefined) {
      if (t.category === BehaviorCategory.TRAVEL && baseline !== undefined) {
        const outcome = CalcEngine.calculateTravel(baseline.code, factor.code, t.defaultQuantity,
          BaselineType.USER_DECLARED, repo, 1, '');
        unit = 'km';
        if (outcome.ok) {
          expected = outcome.reductionKg;
          scope = `${outcome.gasScope}`;
        } else {
          baseParticipation = true;
          note = `出行对照核算不可用（${outcome.message}），只计参与积分。`;
        }
      } else {
        const outcome = CalcEngine.calculateSingle(t.category, factor.code, t.defaultQuantity,
          factor.perUnit, '', repo);
        unit = factor.perUnit;
        if (outcome.ok) {
          expected = outcome.reductionKg;
          scope = `${outcome.gasScope}`;
        } else {
          baseParticipation = true;
          note = `核算不可用（${outcome.message}），只计参与积分。`;
        }
      }
    }
    if (!baseParticipation && expected <= 0) {
      // 该替代情景不会带来减排，按计划书不制造减排
      baseParticipation = true;
      note = '按当前因子，该情景不产生正减排，只计参与积分。';
      expected = 0;
      scope = '';
    }

    for (const day of usableDays) {
      if (t.allowedWeekdays.length > 0 && t.allowedWeekdays.indexOf(weekdayOf(day)) < 0) {
        continue;
      }
      const reason = PlanEngine.renderReason(t, day, usualWay, baseParticipation ? note : '');
      out.push({
        templateId: t.templateId,
        name: t.name,
        category: t.category,
        day: day,
        expectedKg: baseParticipation ? 0 : expected,
        quantity: t.defaultQuantity,
        unit: unit,
        extraMinutes: t.extraMinutes,
        extraCost: t.extraCost,
        mutexGroup: t.mutexGroup,
        maxTimesPerWeek: t.maxTimesPerWeek,
        participationOnly: baseParticipation,
        gasScope: baseParticipation ? '' : scope,
        reason: reason
      });
    }
  }

  /** 选择本次目标的主气体口径：潜在贡献最大者，平手时 CO₂ 优先 */
  private static chooseScope(raw: Candidate[], trace: string[]): string {
    const totals: Map<string, number> = new Map<string, number>();
    for (const c of raw) {
      if (c.participationOnly || c.gasScope.length === 0 || c.expectedKg <= 0) {
        continue;
      }
      const cur = totals.get(c.gasScope);
      totals.set(c.gasScope, (cur !== undefined ? cur : 0) + c.expectedKg);
    }
    let best = '';
    let bestVal = -1;
    const scopes: GasScope[] = [GasScope.CO2, GasScope.CO2E];
    for (const s of scopes) {
      const v = totals.get(`${s}`);
      if (v !== undefined && v > bestVal) {
        best = `${s}`;
        bestVal = v;
      }
    }
    if (best.length > 0) {
      trace.push(`本次目标主气体口径：${best}（潜在贡献 ${bestVal.toFixed(4)} kg），其他口径任务降级为参与任务。`);
    }
    return best;
  }

  /** 确定性排序：额外时间升序 → 额外费用升序 → 预计贡献降序 → 模板编号 → 日期 */
  private static sortCandidates(list: Candidate[]): void {
    list.sort((a: Candidate, b: Candidate) => {
      if (a.extraMinutes !== b.extraMinutes) {
        return a.extraMinutes - b.extraMinutes;
      }
      if (a.extraCost !== b.extraCost) {
        return a.extraCost - b.extraCost;
      }
      if (a.expectedKg !== b.expectedKg) {
        return b.expectedKg - a.expectedKg;
      }
      if (a.templateId !== b.templateId) {
        return a.templateId < b.templateId ? -1 : 1;
      }
      if (a.day !== b.day) {
        return a.day < b.day ? -1 : 1;
      }
      return 0;
    });
  }

  /** 累计时间、费用、频次与同日互斥检查 */
  private static canAdd(c: Candidate, cons: PlanConstraints, countByTemplate: Map<string, number>,
    mutexByDay: Map<string, string[]>, minutesUsed: number, costUsed: number): boolean {
    const used = countByTemplate.get(c.templateId);
    if ((used !== undefined ? used : 0) >= c.maxTimesPerWeek) {
      return false;
    }
    if (minutesUsed + c.extraMinutes > cons.budgetMinutes) {
      return false;
    }
    if (costUsed + c.extraCost > cons.budgetCost + 0.0001) {
      return false;
    }
    if (c.mutexGroup.length > 0) {
      const groups = mutexByDay.get(c.day);
      if (groups !== undefined && groups.indexOf(c.mutexGroup) >= 0) {
        return false;
      }
    }
    return true;
  }

  /** 记录已选 */
  private static accept(c: Candidate, selected: Candidate[], countByTemplate: Map<string, number>,
    mutexByDay: Map<string, string[]>): void {
    selected.push(c);
    const used = countByTemplate.get(c.templateId);
    countByTemplate.set(c.templateId, (used !== undefined ? used : 0) + 1);
    if (c.mutexGroup.length > 0) {
      const groups = mutexByDay.get(c.day);
      if (groups === undefined) {
        mutexByDay.set(c.day, [c.mutexGroup]);
      } else {
        groups.push(c.mutexGroup);
      }
    }
  }

  /** 渲染推荐解释；附加 note 时补在末尾 */
  private static renderReason(t: TaskTemplate, day: string, usualWay: string, note: string): string {
    const wd = WEEKDAY_LABELS[PlanEngine.weekday(day) - 1];
    let s = t.explainTemplate;
    s = s.split('{weekday}').join(wd);
    s = s.split('{minutes}').join(`${t.extraMinutes}`);
    s = s.split('{cost}').join(`${t.extraCost}`);
    s = s.split('{quantity}').join(`${t.defaultQuantity}`);
    s = s.split('{usualWay}').join(usualWay);
    if (note.length > 0) {
      s = `${s} ${note}`;
    }
    return s;
  }

  /** 自然日所属星期：周一=1 … 周日=7 */
  static weekday(day: string): number {
    const d = DateUtil.parseDay(day);
    const dow = d.getDay();
    return dow === 0 ? 7 : dow;
  }

  /** 生成日起七个自然日 */
  private static sevenDays(startDay: string): string[] {
    const out: string[] = [];
    for (let i = 0; i < 7; i++) {
      out.push(DateUtil.addDays(startDay, i));
    }
    return out;
  }
}
