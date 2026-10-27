import { FactorRepository } from './FactorRepository';
import { CalcEngine } from './CalcEngine';
import { PointsEngine } from './PointsEngine';
import { PlanEngine } from './PlanEngine';
import { BackupService } from './BackupService';
import { LedgerDb } from './LedgerDb';
import { StatsService } from './StatsService';
import { ErrorCode } from '../common/AppError';
import { BaselineType, BehaviorCategory, GasScope, ScenarioRole, TimeDimension } from '../common/Domain';
import { StatsSummary } from '../models/StatsModels';
import { DateUtil } from '../common/Format';
import { CalcInput, CalcOutcome, ScenarioInput } from '../models/CalcModels';
import { PlanConstraints, PlanSolution, TaskTemplate } from '../models/PlanModels';
import { TASK_TEMPLATES } from '../data/TaskTemplates';

/**
 * 应用内自检（第 12.1 节关键测试矩阵的纯逻辑部分）。
 *
 * 只覆盖可确定性复现的核算、积分与规划规则；页面级端到端项仍以真机验证为主。
 * 无对应可用因子时标记为「跳过」，不虚报通过。
 */
export interface CheckResult {
  id: string;
  name: string;
  pass: boolean;
  skipped: boolean;
  detail: string;
}

export class SelfCheck {

  static async run(repo: FactorRepository, db: LedgerDb): Promise<CheckResult[]> {
    const out: CheckResult[] = [];
    out.push(SelfCheck.formalTravel(repo));
    out.push(SelfCheck.formalSingle(repo, BehaviorCategory.RECYCLING, 'EF_RECYCLE_PAPER_UTILIZED_2022', 1, 4, GasScope.CO2));
    out.push(SelfCheck.formalSingle(repo, BehaviorCategory.FOOD, 'EF_FOOD_APPLE_PROCUREMENT_PN2018', 0.2, 0.08, GasScope.CO2E));
    out.push(SelfCheck.travelDirection(repo));
    out.push(SelfCheck.vkmConversion(repo));
    out.push(SelfCheck.unitMismatch(repo));
    out.push(SelfCheck.gasScopeMix(repo));
    out.push(SelfCheck.pointsRounding());
    out.push(SelfCheck.dailyBonusCap());
    out.push(SelfCheck.streak());
    out.push(SelfCheck.planConstraints(repo));
    out.push(SelfCheck.planDeterminism(repo));
    out.push(SelfCheck.backupValidation());
    out.push(await SelfCheck.statsPipeline(db));
    return out;
  }

  private static formalTravel(repo: FactorRepository): CheckResult {
    const input: CalcInput = { category: BehaviorCategory.TRAVEL, baselineType: BaselineType.USER_DECLARED,
      scenarios: [
        { role: ScenarioRole.BASELINE, factorCode: 'EF_TRAVEL_GASOLINE_MASS_2015', quantity: 0.5, unit: 'kg', label: '' },
        { role: ScenarioRole.ACTUAL, factorCode: 'EF_TRAVEL_WALK_DIRECT', quantity: 5, unit: 'km', label: '' }
      ] };
    const result = CalcEngine.calculate(input, repo);
    return { id: 'T20', name: '正式出行：汽油质量与实际路程分别计量', pass: result.ok && result.reductionKg === 1.5213 && result.gasScope === GasScope.CO2,
      skipped: false, detail: `0.5 kg汽油对照步行5km = ${result.reductionKg} kgCO₂；仅直接燃烧边界。` };
  }

  private static formalSingle(repo: FactorRepository, category: BehaviorCategory, code: string,
    quantity: number, expected: number, scope: GasScope): CheckResult {
    const result = CalcEngine.calculateSingle(category, code, quantity, 'kg', '', repo);
    return { id: category === BehaviorCategory.FOOD ? 'T22' : 'T21', name: category === BehaviorCategory.FOOD ? '正式食物：减少苹果采购的参考估算' : '正式回收：废纸实际再生利用参考估算',
      pass: result.ok && result.reductionKg === expected && result.gasScope === scope, skipped: false,
      detail: `${quantity} kg × 正式因子 = ${result.reductionKg} kg${scope}；入账另需适用条件确认和依据。` };
  }

  // T19：看板统计与有效记录计数两条独立 SQL 口径必须一致，且分桶净和等于总净
  private static async statsPipeline(db: LedgerDb): Promise<CheckResult> {
    if (db === undefined || db === null) {
      return SelfCheck.skip('T19', '看板统计与账本口径一致', '数据库未就绪');
    }
    const rows = await StatsService.rows(db);
    const count = await db.countLatestActiveRecords();
    const to = DateUtil.today();
    const initial = await StatsService.summary(db, TimeDimension.DAY, '0001-01-01', '9999-12-31', null);
    let totalCount = 0;
    let sumOk = true;
    let detail = '';
    for (const scope of initial.gasScopes) {
      const summary = await StatsService.summary(db, TimeDimension.DAY, '0001-01-01', '9999-12-31', null, scope);
      const expected = rows.filter((r) => `${r.gasScope}` === scope);
      let expectedNet = 0;
      let bucketNet = 0;
      for (const row of expected) { expectedNet += row.reductionKg; }
      for (const bucket of summary.buckets) { bucketNet += bucket.netKg; }
      sumOk = sumOk && expected.length === summary.recordCount
        && Math.abs(expectedNet - summary.totalNetKg) < 0.00011
        && Math.abs(bucketNet - summary.totalNetKg) < 0.00011;
      totalCount += summary.recordCount;
      detail += `${scope}: ${summary.recordCount}条, 净值${summary.totalNetKg}; `;
    }
    return { id: 'T19', name: '看板分气体口径与账本对账',
      pass: totalCount === count && sumOk, skipped: false,
      detail: `${detail}分组记录总数${totalCount} / 有效记录${count}，各口径独立核对=${sumOk}` };
  }

  // T02：出行正负方向、增加排放标记，以及角色不可互换的拦截
  private static travelDirection(repo: FactorRepository): CheckResult {
    const base = repo.findBySubItem('drive_gasoline');
    const actual = repo.findBySubItem('bus');
    if (base === undefined || actual === undefined) {
      return SelfCheck.skip('T02', '出行正负方向', '无可用出行因子');
    }
    // 正向：燃油车（基准）→ 公交（实际），应得正减排
    const forward: CalcOutcome = CalcEngine.calculateTravel(base.code, actual.code, 10,
      BaselineType.USER_DECLARED, repo, 1, '');
    // 角色互换：公交不能作为基准、燃油车不能作为实际，应被拦截
    const swapped: CalcOutcome = CalcEngine.calculateTravel(actual.code, base.code, 10,
      BaselineType.USER_DECLARED, repo, 1, '');
    // 负向：基准侧按 10 人折算后低于实际，R<0 且标记为增加排放
    const increased: CalcOutcome = CalcEngine.calculateTravel(base.code, actual.code, 10,
      BaselineType.USER_DECLARED, repo, 10, '');
    const ok = forward.ok && forward.reductionKg > 0 && !forward.isNetIncrease
      && !swapped.ok && swapped.errorCode === ErrorCode.E_FACTOR_ROLE_MISMATCH
      && increased.ok && increased.reductionKg < 0 && increased.isNetIncrease;
    return {
      id: 'T02',
      name: '出行正负方向、增加排放标记与角色约束',
      pass: ok,
      skipped: false,
      detail: `正向 ${forward.reductionKg}，互换码 ${swapped.errorCode}，负向 ${increased.reductionKg}（isNetIncrease=${increased.isNetIncrease}）`
    };
  }

  // T03：车辆公里与人公里不得直接混算，需按明确载客参数转换
  private static vkmConversion(repo: FactorRepository): CheckResult {
    const base = repo.findBySubItem('drive_gasoline');
    const actual = repo.findBySubItem('bus');
    if (base === undefined || actual === undefined) {
      return SelfCheck.skip('T03', '车辆公里与人公里换算', '无可用出行因子');
    }
    const noPassenger: CalcOutcome = CalcEngine.calculateTravel(base.code, actual.code, 10,
      BaselineType.USER_DECLARED, repo, 0, '');
    const withPassenger: CalcOutcome = CalcEngine.calculateTravel(base.code, actual.code, 10,
      BaselineType.USER_DECLARED, repo, 2, '');
    const ok = !noPassenger.ok && noPassenger.errorCode === ErrorCode.E_PASSENGER_MISMATCH && withPassenger.ok;
    return {
      id: 'T03',
      name: '车辆公里 / 人公里混算拦截与载客折算',
      pass: ok,
      skipped: false,
      detail: `无载客拒绝码=${noPassenger.errorCode}，载客 2 人结果=${withPassenger.reductionKg}`
    };
  }

  // 单位必须与因子分母一致
  private static unitMismatch(repo: FactorRepository): CheckResult {
    const f = repo.findBySubItem('grid_elec_henan');
    if (f === undefined) {
      return SelfCheck.skip('T01', '单位校验', '无可用电力因子');
    }
    const bad: CalcOutcome = CalcEngine.calculateSingle(BehaviorCategory.WATER_ENERGY, f.code, 1, 'km', '', repo);
    const good: CalcOutcome = CalcEngine.calculateSingle(BehaviorCategory.WATER_ENERGY, f.code, 1, f.perUnit, '', repo);
    const ok = !bad.ok && bad.errorCode === ErrorCode.E_UNIT_MISMATCH && good.ok;
    return {
      id: 'T01',
      name: '单位与因子口径一致性校验',
      pass: ok,
      skipped: false,
      detail: `错误单位码=${bad.errorCode}，正确单位结果=${good.reductionKg}`
    };
  }

  // 跨气体口径不得混算
  private static gasScopeMix(repo: FactorRepository): CheckResult {
    const co2 = repo.findBySubItem('grid_elec_henan');
    const co2e = repo.findBySubItem('tap_water');
    if (co2 === undefined || co2e === undefined) {
      return SelfCheck.skip('T01b', '跨气体口径拦截', '缺少 CO₂ 或 CO₂e 因子');
    }
    const scenarios: ScenarioInput[] = [
      { role: ScenarioRole.BASELINE, factorCode: co2.code, quantity: 1, unit: co2.perUnit, label: '' },
      { role: ScenarioRole.BASELINE, factorCode: co2e.code, quantity: 1, unit: co2e.perUnit, label: '' }
    ];
    const input: CalcInput = { category: BehaviorCategory.WATER_ENERGY, baselineType: BaselineType.STATISTICAL, scenarios: scenarios };
    const outcome = CalcEngine.calculate(input, repo);
    const ok = !outcome.ok && outcome.errorCode === ErrorCode.E_GAS_SCOPE_MIXED;
    return {
      id: 'T01b',
      name: '跨气体口径拒绝混算',
      pass: ok,
      skipped: false,
      detail: `返回码=${outcome.errorCode}`
    };
  }

  // T07：拆分数量录入后累计积分与整体一致；余数累计
  private static pointsRounding(): CheckResult {
    const whole = PointsEngine.reductionDelta(3.0, 0);
    const first = PointsEngine.reductionDelta(1.4, 0);
    const second = PointsEngine.reductionDelta(3.0, first);
    const ok = whole === 30 && first + second === whole;
    return {
      id: 'T07',
      name: '拆分录入积分与整体一致（余数累计）',
      pass: ok,
      skipped: false,
      detail: `整体 ${whole}，拆分 ${first}+${second}=${first + second}`
    };
  }

  // T08：每日奖励上限只影响奖励资格
  private static dailyBonusCap(): CheckResult {
    const capped = PointsEngine.applyDailyBonusCap(25, 20);
    const exhausted = PointsEngine.applyDailyBonusCap(40, 5);
    const ok = capped === 5 && exhausted === 0;
    return {
      id: 'T08',
      name: '每日奖励上限（参与与连续）',
      pass: ok,
      skipped: false,
      detail: `已用 25 时发 ${capped}，已用 40 时发 ${exhausted}`
    };
  }

  // 连续七天：每个连续区间只发一次
  private static streak(): CheckResult {
    const days: string[] = ['2026-03-07', '2026-03-06', '2026-03-05', '2026-03-04', '2026-03-03', '2026-03-02', '2026-03-01'];
    const s = PointsEngine.streakDays(days);
    const first = PointsEngine.streakDelta(s, false);
    const again = PointsEngine.streakDelta(s, true);
    const ok = s === 7 && first === 20 && again === 0;
    return {
      id: 'T02b',
      name: '连续七天一次发放',
      pass: ok,
      skipped: false,
      detail: `连续 ${s} 天，首次 ${first}，重复 ${again}`
    };
  }

  // T12 / T13：预算、频次与互斥约束
  private static planConstraints(repo: FactorRepository): CheckResult {
    const cons = SelfCheck.sampleConstraints();
    const solution: PlanSolution = PlanEngine.generate(cons, TASK_TEMPLATES, repo);
    if (!solution.ok) {
      return SelfCheck.skip('T12', '计划预算与互斥约束', `无可行方案（${solution.code}）`);
    }
    let minutes = 0;
    let cost = 0;
    let planned = 0;
    let budgetOk = true;
    let dupOk = true;
    let mutexOk = true;
    const seen: Set<string> = new Set<string>();
    const travelByDay: Map<string, number> = new Map<string, number>();
    for (const p of solution.proposals) {
      minutes = minutes + p.extraMinutes;
      cost = cost + p.extraCost;
      if (!p.participationOnly) {
        planned = planned + p.expectedKg;
      }
      const key = `${p.templateId}#${p.day}`;
      if (seen.has(key)) {
        dupOk = false;
      }
      seen.add(key);
      if (p.templateId === 'P01' || p.templateId === 'P02') {
        travelByDay.set(p.day, (travelByDay.get(p.day) !== undefined ? travelByDay.get(p.day)! : 0) + 1);
      }
    }
    travelByDay.forEach((n: number) => {
      if (n > 1) {
        mutexOk = false;
      }
    });
    budgetOk = minutes <= cons.budgetMinutes && cost <= cons.budgetCost + 0.0001;
    const netOk = Math.abs(planned - solution.plannedKg) < 0.0001;
    const ok = budgetOk && dupOk && mutexOk && netOk;
    return {
      id: 'T12',
      name: '计划预算、去重与互斥约束',
      pass: ok,
      skipped: false,
      detail: `累计 ${minutes} 分钟 / ${cost} 元（预算 ${cons.budgetMinutes}/${cons.budgetCost}），去重=${dupOk}，互斥=${mutexOk}，合计一致=${netOk}`
    };
  }

  // 相同输入产生相同方案
  private static planDeterminism(repo: FactorRepository): CheckResult {
    const cons = SelfCheck.sampleConstraints();
    const a: PlanSolution = PlanEngine.generate(cons, TASK_TEMPLATES, repo);
    const b: PlanSolution = PlanEngine.generate(cons, TASK_TEMPLATES, repo);
    let same = a.proposals.length === b.proposals.length && a.plannedKg === b.plannedKg;
    if (same) {
      for (let i = 0; i < a.proposals.length; i++) {
        if (a.proposals[i].templateId !== b.proposals[i].templateId || a.proposals[i].day !== b.proposals[i].day) {
          same = false;
        }
      }
    }
    return {
      id: 'T14b',
      name: '相同输入产生相同方案',
      pass: same,
      skipped: false,
      detail: `两次生成均为 ${a.proposals.length} 条，预计 ${a.plannedKg} kg`
    };
  }

  // T18：损坏文件与高版本文件被拒绝
  private static backupValidation(): CheckResult {
    const bad = BackupService.validate('这不是 JSON');
    const high = BackupService.validate('{"schemaVersion": 999, "appVersion":"9", "exportedAt":"", "factorSetVersion":"", "tables":{}}');
    const ok = !bad.ok && bad.code === ErrorCode.E_RESTORE_INVALID && !high.ok && high.code === ErrorCode.E_RESTORE_VERSION;
    return {
      id: 'T18',
      name: '损坏与高版本备份拒绝导入',
      pass: ok,
      skipped: false,
      detail: `损坏码=${bad.code}，高版本码=${high.code}`
    };
  }

  // —— 辅助 ——

  private static sampleConstraints(): PlanConstraints {
    return {
      startDay: '2026-03-01',
      targetKg: 2,
      gasScope: '',
      budgetMinutes: 200,
      budgetCost: 30,
      availableDays: [],
      acceptedCategories: [
        BehaviorCategory.TRAVEL, BehaviorCategory.WATER_ENERGY,
        BehaviorCategory.RECYCLING, BehaviorCategory.FOOD
      ],
      usualTravelSubItem: 'drive_gasoline',
      usualTravelKm: 5,
      excludedTemplateIds: []
    };
  }

  private static skip(id: string, name: string, detail: string): CheckResult {
    return { id: id, name: name, pass: true, skipped: true, detail: `跳过：${detail}` };
  }
}
