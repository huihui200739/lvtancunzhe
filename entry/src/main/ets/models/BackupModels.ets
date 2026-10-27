import { relationalStore } from '@kit.ArkData';

/**
 * 备份文件结构（第 9.3 节）。
 * 全量替换恢复，包含 schema_version、导出时间、业务表、完整计算快照、
 * 积分事件、兑换、计划与所需附件；附件随包保存相对路径。
 */
export interface BackupTables {
  behavior_record: relationalStore.ValuesBucket[];
  calculation_snapshot: relationalStore.ValuesBucket[];
  carbon_factor: relationalStore.ValuesBucket[];
  point_event: relationalStore.ValuesBucket[];
  reward_def: relationalStore.ValuesBucket[];
  redemption: relationalStore.ValuesBucket[];
  badge_def: relationalStore.ValuesBucket[];
  badge_unlock: relationalStore.ValuesBucket[];
  task_template: relationalStore.ValuesBucket[];
  weekly_plan: relationalStore.ValuesBucket[];
  plan_task: relationalStore.ValuesBucket[];
  article: relationalStore.ValuesBucket[];
  attachment: relationalStore.ValuesBucket[];
}

export interface BackupFile {
  /** 导出时的 schema 版本，用于恢复校验 */
  schemaVersion: number;
  /** Older untagged backups are accepted only by the development environment. */
  dataEnvironment?: string;
  /** 导出时的应用版本 */
  appVersion: string;
  exportedAt: string;
  /** 因子集合版本标识 */
  factorSetVersion: string;
  tables: BackupTables;
}
