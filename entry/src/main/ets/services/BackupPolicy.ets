import { relationalStore } from '@kit.ArkData';
import { BackupFile } from '../models/BackupModels';
import { VoucherFactorSource } from '../models/RecordModels';
import { ScenarioResult } from '../models/CalcModels';
import { CarbonFactor } from '../models/CarbonFactor';
import { PROD_FACTORS } from '../data/ProdFactors';
import { ReviewStatus, gasUnitLabel, ScenarioRole, FactorUsableAs, BehaviorCategory } from '../common/Domain';
import { EnvironmentPolicy } from '../common/DataEnvironment';

/** Environment tags alone are insufficient: validate frozen production provenance too. */
export class BackupPolicy {
  static validate(file: BackupFile, development: boolean): string {
    const environmentError = EnvironmentPolicy.importError(file.dataEnvironment, development);
    if (environmentError.length > 0) { return environmentError; }
    if (development) { return ''; }
    return BackupPolicy.productionRowsError(file.tables.carbon_factor, file.tables.calculation_snapshot, file.tables.behavior_record);
  }
  private static trusted(code: string, version: string): CarbonFactor | undefined {
    return PROD_FACTORS.find((f: CarbonFactor) => f.code === code && f.version === version && f.reviewStatus === ReviewStatus.VERIFIED);
  }
  static productionRowsError(factors: relationalStore.ValuesBucket[], snapshots: relationalStore.ValuesBucket[], records: relationalStore.ValuesBucket[] = []): string {
    for (const row of factors) {
      const f = BackupPolicy.trusted(`${row['code']}`, `${row['version']}`);
      if (f === undefined || row['review_status'] !== 'verified' || row['value'] !== f.value || row['gas_scope'] !== f.gasScope || row['per_unit'] !== f.perUnit) {
        return '备份含测试、未核验或与正式注册表不一致的因子，已拒绝导入。';
      }
    }
    for (const row of snapshots) {
      try {
        const sources = JSON.parse(`${row['factor_sources_json']}`) as VoucherFactorSource[];
        const scenarios = JSON.parse(`${row['scenarios_json']}`) as ScenarioResult[];
        if (!Array.isArray(sources) || !Array.isArray(scenarios) || sources.length === 0 || scenarios.length === 0) {
          return '正式凭证缺少可核对的因子来源或计算情景。';
        }
        for (const source of sources) {
          const f = BackupPolicy.trusted(source.factorCode, source.factorVersion);
          if (f === undefined || source.reviewStatus !== 'verified' || source.value !== f.value || source.sourceUrl !== f.sourceUrl || source.gasScope !== `${gasUnitLabel(f.gasScope)}/${f.perUnit}`) {
            return '凭证来源包含测试或未经注册的因子，已拒绝导入。';
          }
        }
        if (row['category'] === BehaviorCategory.TRAVEL && (!scenarios.some((s: ScenarioResult) => s.role === ScenarioRole.BASELINE) || !scenarios.some((s: ScenarioResult) => s.role === ScenarioRole.ACTUAL))) { return '出行凭证缺少基准或实际情景。'; }
        const record = records.find((r: relationalStore.ValuesBucket) => r['record_id'] === row['record_id'] && r['revision'] === row['revision']);
        let net = 0;
        for (const sc of scenarios) {
          const f = BackupPolicy.trusted(sc.factorCode, sc.factorVersion);
          const source = sources.find((s: VoucherFactorSource) => s.factorCode === sc.factorCode && s.factorVersion === sc.factorVersion);
          if (record === undefined || record['category'] !== row['category'] || f === undefined || f.category !== row['category'] || source === undefined || sc.factorValue !== f.value || sc.unit !== f.perUnit || row['gas_scope'] !== f.gasScope || !Number.isFinite(sc.quantity) || sc.quantity <= 0) {
            return '凭证输入、单位或气体口径与正式因子不一致。';
          }
          if ((sc.role !== ScenarioRole.BASELINE && sc.role !== ScenarioRole.ACTUAL) || !Number.isFinite(sc.emissionKg) || sc.emissionKg < 0 || (sc.role === ScenarioRole.ACTUAL && (f.usableAs === FactorUsableAs.SINGLE || f.usableAs === FactorUsableAs.BASELINE)) || (sc.role === ScenarioRole.BASELINE && f.usableAs === FactorUsableAs.ACTUAL)) { return '凭证情景角色或排放数值无效。'; }
          if (f.evidenceRequirement && (source.applicabilityConfirmed !== true || record === undefined || typeof record['remark'] !== 'string' || (record['remark'] as string).trim().length === 0)) { return '凭证缺少限定场景适用条件的用户确认及依据。'; }
          const effective = f.distanceBasis === 'vkm' ? sc.quantity / (sc.passengers || 0) : sc.quantity;
          if (!Number.isFinite(effective) || effective <= 0 || (f.distanceBasis === 'vkm' && (!Number.isFinite(sc.passengers) || (sc.passengers || 0) <= 0)) || (sc.effectiveQuantity !== undefined && Math.abs(sc.effectiveQuantity - effective) > 0.00001) || Math.abs(Math.round(effective * f.value * 10000) / 10000 - sc.emissionKg) > 0.00001) {
            return '凭证排放量不能按冻结输入复算，已拒绝导入。';
          }
          net += sc.role === ScenarioRole.BASELINE ? sc.emissionKg : -sc.emissionKg;
        }
        if (typeof row['reduction_kg'] !== 'number' || !Number.isFinite(row['reduction_kg'] as number) || Math.abs(Math.round(net * 10000) / 10000 - (row['reduction_kg'] as number)) > 0.00001) {
          return '凭证减排结果不能复算，已拒绝导入。';
        }
      } catch (e) { return '凭证来源或情景数据损坏，已拒绝导入。'; }
    }
    return '';
  }
}
