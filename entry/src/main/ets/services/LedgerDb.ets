import { DATABASE_NAME, DATA_ENVIRONMENT } from '../common/DataEnvironment';
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Tables, DDL } from './LedgerSchema';
import { Result, ErrorCode } from '../common/AppError';
import { SCHEMA_VERSION } from '../common/BuildConfig';
import { DateUtil } from '../common/Format';
import { BehaviorRecord, CalculationSnapshot, VoucherFactorSource } from '../models/RecordModels';
import { PointEvent } from '../models/PointModels';
import { Redemption, RewardDef, BadgeUnlock } from '../models/PointModels';
import { PlanTask, WeeklyPlan, TaskTemplate } from '../models/PlanModels';
import { Article, ArticleCategory, BadgeDef } from '../models/ContentModels';
import { CarbonFactor } from '../models/CarbonFactor';
import { BehaviorCategory, BaselineType, EntrySource, GasScope, PlanTaskStatus, PointReason, QuantityUnit, RecordStatus } from '../common/Domain';
import { StatRow } from '../models/StatsModels';

const DOMAIN = 0x0000;
const TAG = 'LedgerDb';
const DB_NAME = DATABASE_NAME;

/**
 * 数据层：统一事务与查询（第 8.2 / 8.4 节）。
 * 页面与业务层不直接拼 SQL，全部经此访问。
 */
export class LedgerDb {
  private static instance: LedgerDb | null = null;
  private store: relationalStore.RdbStore | null = null;
  private txDepth: number = 0;

  static get(): LedgerDb {
    if (LedgerDb.instance === null) {
      LedgerDb.instance = new LedgerDb();
    }
    return LedgerDb.instance;
  }

  /** 初始化：打开数据库、建表、写入 schema 版本 */
  async init(context: common.Context): Promise<Result<boolean>> {
    if (this.store !== null) {
      return Result.success(true);
    }
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    try {
      const store = await relationalStore.getRdbStore(context, config);
      for (const sql of DDL) {
        await store.executeSql(sql);
      }
      this.store = store;
      const environment = await this.getMeta('data_environment');
      if (environment.length > 0 && environment !== DATA_ENVIRONMENT) { throw new Error('数据库环境不匹配，原数据未修改。'); }
      await this.migrateRecordVersions(store);
      await this.setMeta('data_environment', DATA_ENVIRONMENT);
      await this.setMeta('schema_version', `${SCHEMA_VERSION}`);
      if ((await this.getMeta('db_created_at')).length === 0) { await this.setMeta('db_created_at', DateUtil.toDateTime(new Date())); }
      hilog.info(DOMAIN, TAG, 'database ready, schema %{public}d', SCHEMA_VERSION);
      return Result.success(true);
    } catch (e) {
      if (this.store !== null) { this.store.close(); this.store = null; }
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'init failed: %{public}s', JSON.stringify(err));
      return Result.failure(ErrorCode.E_STORAGE, `数据库初始化失败：${err.message}`);
    }
  }

  /** Schema 1 used record_id alone, which replaced old revisions. Preserve all existing rows on migration. */
  private async migrateRecordVersions(store: relationalStore.RdbStore): Promise<void> {
    const info = await store.querySql('PRAGMA table_info(behavior_record)');
    let composite = false;
    try {
      while (info.goToNextRow()) {
        if (info.getString(info.getColumnIndex('name')) === 'revision' && info.getLong(info.getColumnIndex('pk')) > 0) { composite = true; }
      }
    } finally { info.close(); }
    if (composite) { return; }
    store.beginTransaction();
    try {
      await store.executeSql('ALTER TABLE behavior_record RENAME TO behavior_record_schema1');
      await store.executeSql(DDL[0]);
      await store.executeSql('INSERT INTO behavior_record SELECT * FROM behavior_record_schema1');
      await store.executeSql('DROP TABLE behavior_record_schema1');
      await store.executeSql(DDL[1]);
      await store.executeSql(DDL[2]);
      store.commit();
    } catch (e) { store.rollBack(); throw new Error((e as Error).message); }
  }

  /** 是否已就绪 */
  isReady(): boolean {
    return this.store !== null;
  }

  private db(): relationalStore.RdbStore {
    if (this.store === null) {
      throw new Error('数据库尚未初始化');
    }
    return this.store;
  }

  // —— 事务 ——
  // 第 8.4 节：提交记录时行为、快照与积分事件在同一事务内完成；任何失败均回滚。
  // 服务写入口由 LedgerOperations 排队，不能用 txDepth 把并发请求当作嵌套事务。

  async begin(): Promise<void> {
    if (this.txDepth === 0) {
      this.db().beginTransaction();
    }
    this.txDepth = this.txDepth + 1;
  }

  async commit(): Promise<void> {
    if (this.txDepth === 0) {
      return;
    }
    this.txDepth = this.txDepth - 1;
    if (this.txDepth === 0) {
      this.db().commit();
    }
  }

  async rollBack(): Promise<void> {
    if (this.txDepth === 0) {
      return;
    }
    this.txDepth = 0;
    try {
      this.db().rollBack();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'rollback failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 执行写操作（事务内或独立执行） */
  async exec(sql: string, args: relationalStore.ValueType[] = []): Promise<void> {
    await this.db().executeSql(sql, args);
  }

  /** 查询单值 */
  async scalar(sql: string, args: relationalStore.ValueType[] = []): Promise<number> {
    const rs = await this.db().querySql(sql, args);
    let value = 0;
    try {
      if (rs.goToNextRow()) {
        value = rs.getDouble(0);
      }
    } finally {
      rs.close();
    }
    return value;
  }

  /** 查询单个文本值 */
  async scalarText(sql: string, args: relationalStore.ValueType[] = []): Promise<string> {
    const rs = await this.db().querySql(sql, args);
    let value = '';
    try {
      if (rs.goToNextRow()) {
        value = rs.getString(0);
      }
    } finally {
      rs.close();
    }
    return value;
  }

  private async upsert(table: string, bucket: relationalStore.ValuesBucket): Promise<void> {
    await this.db().insert(table, bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  // ================= app_meta =================

  async setMeta(key: string, value: string): Promise<void> {
    const bucket: relationalStore.ValuesBucket = { 'k': key, 'v': value };
    await this.db().insert(Tables.APP_META, bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async getMeta(key: string): Promise<string> {
    return this.scalarText(`SELECT v FROM ${Tables.APP_META} WHERE k = ?`, [key]);
  }

  // ================= behavior_record =================

  async insertRecord(rec: BehaviorRecord): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'record_id': rec.recordId,
      'revision': rec.revision,
      'category': rec.category,
      'quantity': rec.quantity,
      'unit': rec.unit,
      'occurred_at': rec.occurredAt,
      'day_key': rec.occurredAt,
      'status': rec.status,
      'entry_source': rec.entrySource,
      'entry_note': rec.entryNote,
      'remark': rec.remark,
      'parent_record_id': rec.parentRecordId,
      'created_at': rec.createdAt,
      'updated_at': rec.updatedAt
    };
    await this.upsert(Tables.BEHAVIOR_RECORD, bucket);
  }

  async updateRecordStatus(recordId: string, revision: number, status: RecordStatus): Promise<void> {
    await this.exec(
      `UPDATE ${Tables.BEHAVIOR_RECORD} SET status = ?, updated_at = ? WHERE record_id = ? AND revision = ?`,
      [status, DateUtil.toDateTime(new Date()), recordId, revision]);
  }

  async updateRecord(rec: BehaviorRecord): Promise<void> {
    await this.exec(
      `UPDATE ${Tables.BEHAVIOR_RECORD} SET quantity = ?, unit = ?, occurred_at = ?, day_key = ?, status = ?,
       entry_source = ?, entry_note = ?, remark = ?, updated_at = ? WHERE record_id = ? AND revision = ?`,
      [rec.quantity, rec.unit, rec.occurredAt, rec.occurredAt, rec.status, rec.entrySource, rec.entryNote,
        rec.remark, rec.updatedAt, rec.recordId, rec.revision]);
  }

  private readRecord(rs: relationalStore.ResultSet): BehaviorRecord {
    const rec: BehaviorRecord = {
      recordId: rs.getString(rs.getColumnIndex('record_id')),
      revision: rs.getLong(rs.getColumnIndex('revision')),
      category: rs.getString(rs.getColumnIndex('category')) as BehaviorCategory,
      quantity: rs.getDouble(rs.getColumnIndex('quantity')),
      unit: rs.getString(rs.getColumnIndex('unit')),
      occurredAt: rs.getString(rs.getColumnIndex('occurred_at')),
      status: rs.getString(rs.getColumnIndex('status')) as RecordStatus,
      entrySource: rs.getString(rs.getColumnIndex('entry_source')) as EntrySource,
      entryNote: rs.getString(rs.getColumnIndex('entry_note')),
      remark: rs.getString(rs.getColumnIndex('remark')),
      createdAt: rs.getString(rs.getColumnIndex('created_at')),
      updatedAt: rs.getString(rs.getColumnIndex('updated_at')),
      parentRecordId: rs.getString(rs.getColumnIndex('parent_record_id'))
    };
    return rec;
  }

  /** 最新版本的记录（同 record_id 取最大 revision）；limit=-1 表示全量导出。 */
  async listLatestRecords(limit: number = 200): Promise<BehaviorRecord[]> {
    const rs = await this.db().querySql(
      `SELECT r.* FROM ${Tables.BEHAVIOR_RECORD} r
       JOIN (SELECT record_id, MAX(revision) AS mx FROM ${Tables.BEHAVIOR_RECORD} GROUP BY record_id) m
         ON r.record_id = m.record_id AND r.revision = m.mx
       ORDER BY r.occurred_at DESC, r.created_at DESC LIMIT ?`, [limit]);
    const out: BehaviorRecord[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push(this.readRecord(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  /** 某记录的全部版本（含被修订的旧版本） */
  async listRecordVersions(recordId: string): Promise<BehaviorRecord[]> {
    const rs = await this.db().querySql(
      `SELECT * FROM ${Tables.BEHAVIOR_RECORD} WHERE record_id = ? ORDER BY revision ASC`, [recordId]);
    const out: BehaviorRecord[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push(this.readRecord(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  async getRecord(recordId: string, revision: number): Promise<BehaviorRecord | null> {
    const rs = await this.db().querySql(
      `SELECT * FROM ${Tables.BEHAVIOR_RECORD} WHERE record_id = ? AND revision = ?`, [recordId, revision]);
    let rec: BehaviorRecord | null = null;
    try {
      if (rs.goToNextRow()) {
        rec = this.readRecord(rs);
      }
    } finally {
      rs.close();
    }
    return rec;
  }

  // ================= calculation_snapshot =================

  async insertSnapshot(s: CalculationSnapshot): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'snapshot_id': s.snapshotId,
      'record_id': s.recordId,
      'revision': s.revision,
      'category': s.category,
      'baseline_type': s.baselineType,
      'gas_scope': s.gasScope,
      'reduction_kg': s.reductionKg,
      'is_net_increase': s.isNetIncrease ? 1 : 0,
      'formula_version': s.formulaVersion,
      'formula_text': s.formulaText,
      'rounding_note': s.roundingNote,
      'scenarios_json': s.scenariosJson,
      'factor_sources_json': s.factorSourcesJson,
      'evidence_label': s.evidenceLabel,
      'scope_note': s.scopeNote,
      'created_at': s.createdAt
    };
    await this.upsert(Tables.CALCULATION_SNAPSHOT, bucket);
  }

  async getSnapshot(recordId: string, revision: number): Promise<CalculationSnapshot | null> {
    const rs = await this.db().querySql(
      `SELECT * FROM ${Tables.CALCULATION_SNAPSHOT} WHERE record_id = ? AND revision = ?`, [recordId, revision]);
    let s: CalculationSnapshot | null = null;
    try {
      if (rs.goToNextRow()) {
        s = {
          snapshotId: rs.getString(rs.getColumnIndex('snapshot_id')),
          recordId: rs.getString(rs.getColumnIndex('record_id')),
          revision: rs.getLong(rs.getColumnIndex('revision')),
          category: rs.getString(rs.getColumnIndex('category')) as BehaviorCategory,
          baselineType: rs.getString(rs.getColumnIndex('baseline_type')) as BaselineType,
          gasScope: rs.getString(rs.getColumnIndex('gas_scope')) as GasScope,
          reductionKg: rs.getDouble(rs.getColumnIndex('reduction_kg')),
          isNetIncrease: rs.getLong(rs.getColumnIndex('is_net_increase')) === 1,
          formulaVersion: rs.getString(rs.getColumnIndex('formula_version')),
          formulaText: rs.getString(rs.getColumnIndex('formula_text')),
          roundingNote: rs.getString(rs.getColumnIndex('rounding_note')),
          scenariosJson: rs.getString(rs.getColumnIndex('scenarios_json')),
          factorSourcesJson: rs.getString(rs.getColumnIndex('factor_sources_json')),
          evidenceLabel: rs.getString(rs.getColumnIndex('evidence_label')),
          scopeNote: rs.getString(rs.getColumnIndex('scope_note')),
          createdAt: rs.getString(rs.getColumnIndex('created_at'))
        };
      }
    } finally {
      rs.close();
    }
    return s;
  }

  /** 有效记录的最新快照，用于统计汇总 */
  async listLatestSnapshots(): Promise<CalculationSnapshot[]> {
    const rs = await this.db().querySql(
      `SELECT s.record_id AS rid, s.revision AS rev FROM ${Tables.CALCULATION_SNAPSHOT} s
       JOIN ${Tables.BEHAVIOR_RECORD} r ON r.record_id = s.record_id AND r.revision = s.revision
       JOIN (SELECT record_id, MAX(revision) AS mx FROM ${Tables.BEHAVIOR_RECORD} GROUP BY record_id) m
         ON m.record_id = s.record_id AND m.mx = s.revision
       WHERE r.status = 'active'
       ORDER BY r.occurred_at DESC`);
    // 先取出键，关闭游标后再逐条读取快照，避免在同一 ResultSet 上嵌套查询
    const ids: string[] = [];
    const revs: number[] = [];
    try {
      while (rs.goToNextRow()) {
        ids.push(rs.getString(rs.getColumnIndex('rid')));
        revs.push(rs.getLong(rs.getColumnIndex('rev')));
      }
    } finally {
      rs.close();
    }
    const out: CalculationSnapshot[] = [];
    for (let i = 0; i < ids.length; i++) {
      const snap = await this.getSnapshot(ids[i], revs[i]);
      if (snap !== null) {
        out.push(snap);
      }
    }
    return out;
  }

  // ================= point_event =================

  async insertPointEvent(ev: PointEvent, dayKey: string): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'event_id': ev.eventId,
      'record_id': ev.recordId,
      'revision': ev.revision,
      'reason': ev.reason,
      'unique_key': ev.uniqueKey,
      'delta': ev.delta,
      'detail': ev.detail,
      'day_key': dayKey,
      'created_at': ev.createdAt
    };
    await this.upsert(Tables.POINT_EVENT, bucket);
  }

  async hasPointEvent(uniqueKey: string): Promise<boolean> {
    const n = await this.scalar(`SELECT COUNT(1) FROM ${Tables.POINT_EVENT} WHERE unique_key = ?`, [uniqueKey]);
    return n > 0;
  }

  /** 按唯一键读取积分事件（撤销冲正用） */
  async findPointEventByKey(uniqueKey: string): Promise<PointEvent | null> {
    const rs = await this.db().querySql(
      `SELECT * FROM ${Tables.POINT_EVENT} WHERE unique_key = ?`, [uniqueKey]);
    let ev: PointEvent | null = null;
    try {
      if (rs.goToNextRow()) {
        ev = {
          eventId: rs.getString(rs.getColumnIndex('event_id')),
          recordId: rs.getString(rs.getColumnIndex('record_id')),
          revision: rs.getLong(rs.getColumnIndex('revision')),
          reason: rs.getString(rs.getColumnIndex('reason')) as PointReason,
          uniqueKey: rs.getString(rs.getColumnIndex('unique_key')),
          delta: rs.getLong(rs.getColumnIndex('delta')),
          detail: rs.getString(rs.getColumnIndex('detail')),
          createdAt: rs.getString(rs.getColumnIndex('created_at'))
        };
      }
    } finally {
      rs.close();
    }
    return ev;
  }

  async listPointEvents(limit: number = 300): Promise<PointEvent[]> {
    const rs = await this.db().querySql(
      `SELECT * FROM ${Tables.POINT_EVENT} ORDER BY created_at DESC LIMIT ?`, [limit]);
    const out: PointEvent[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push({
          eventId: rs.getString(rs.getColumnIndex('event_id')),
          recordId: rs.getString(rs.getColumnIndex('record_id')),
          revision: rs.getLong(rs.getColumnIndex('revision')),
          reason: rs.getString(rs.getColumnIndex('reason')) as PointReason,
          uniqueKey: rs.getString(rs.getColumnIndex('unique_key')),
          delta: rs.getLong(rs.getColumnIndex('delta')),
          detail: rs.getString(rs.getColumnIndex('detail')),
          createdAt: rs.getString(rs.getColumnIndex('created_at'))
        });
      }
    } finally {
      rs.close();
    }
    return out;
  }

  /** 已发放的减排积分合计（用于余数累计换算） */
  async sumPointsByReason(reason: PointReason): Promise<number> {
    return this.scalar(`SELECT COALESCE(SUM(delta),0) FROM ${Tables.POINT_EVENT} WHERE reason = ?`, [reason]);
  }

  /** 某日已发放的奖励类积分合计（每日上限用） */
  async sumBonusPointsOnDay(dayKey: string): Promise<number> {
    return this.scalar(
      `SELECT COALESCE(SUM(delta),0) FROM ${Tables.POINT_EVENT}
       WHERE day_key = ? AND reason IN ('daily_first','streak7','participation') AND delta > 0`,
      [dayKey]);
  }

  /** 有有效记录的日期集合（连续打卡计算用） */
  async listActiveDays(): Promise<string[]> {
    const rs = await this.db().querySql(
      `SELECT DISTINCT r.day_key FROM ${Tables.BEHAVIOR_RECORD} r
       JOIN (SELECT record_id, MAX(revision) AS mx FROM ${Tables.BEHAVIOR_RECORD} GROUP BY record_id) m ON r.record_id = m.record_id AND r.revision = m.mx
       WHERE r.status = 'active' ORDER BY r.day_key DESC`);
    const out: string[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push(rs.getString(0));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  /** 某类别有效记录次数（徽章解锁用） */
  async countActiveByCategory(category: BehaviorCategory): Promise<number> {
    return this.scalar(
      `SELECT COUNT(1) FROM ${Tables.BEHAVIOR_RECORD} r
       WHERE r.category = ? AND r.status = 'active'
         AND r.revision = (SELECT MAX(b.revision) FROM ${Tables.BEHAVIOR_RECORD} b WHERE b.record_id = r.record_id)`,
      [category]);
  }

  // ================= reward / redemption / badge =================

  async insertRedemption(r: Redemption): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'redemption_id': r.redemptionId,
      'request_id': r.requestId,
      'reward_id': r.rewardId,
      'price': r.price,
      'price_version': r.priceVersion,
      'point_event_id': r.pointEventId,
      'status': r.status,
      'created_at': r.createdAt
    };
    await this.upsert(Tables.REDEMPTION, bucket);
  }

  async getRedemptionByRequest(requestId: string): Promise<Redemption | null> {
    const rs = await this.db().querySql(
      `SELECT * FROM ${Tables.REDEMPTION} WHERE request_id = ?`, [requestId]);
    let r: Redemption | null = null;
    try {
      if (rs.goToNextRow()) {
        r = {
          redemptionId: rs.getString(rs.getColumnIndex('redemption_id')),
          requestId: rs.getString(rs.getColumnIndex('request_id')),
          rewardId: rs.getString(rs.getColumnIndex('reward_id')),
          price: rs.getLong(rs.getColumnIndex('price')),
          priceVersion: rs.getString(rs.getColumnIndex('price_version')),
          pointEventId: rs.getString(rs.getColumnIndex('point_event_id')),
          status: rs.getString(rs.getColumnIndex('status')),
          createdAt: rs.getString(rs.getColumnIndex('created_at'))
        };
      }
    } finally {
      rs.close();
    }
    return r;
  }

  async listRedemptions(): Promise<Redemption[]> {
    const rs = await this.db().querySql(`SELECT * FROM ${Tables.REDEMPTION} ORDER BY created_at DESC`);
    const out: Redemption[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push({
          redemptionId: rs.getString(rs.getColumnIndex('redemption_id')),
          requestId: rs.getString(rs.getColumnIndex('request_id')),
          rewardId: rs.getString(rs.getColumnIndex('reward_id')),
          price: rs.getLong(rs.getColumnIndex('price')),
          priceVersion: rs.getString(rs.getColumnIndex('price_version')),
          pointEventId: rs.getString(rs.getColumnIndex('point_event_id')),
          status: rs.getString(rs.getColumnIndex('status')),
          createdAt: rs.getString(rs.getColumnIndex('created_at'))
        });
      }
    } finally {
      rs.close();
    }
    return out;
  }

  async listRewards(): Promise<RewardDef[]> {
    const rs = await this.db().querySql(`SELECT * FROM ${Tables.REWARD_DEF} ORDER BY price ASC`);
    const out: RewardDef[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push({
          rewardId: rs.getString(rs.getColumnIndex('reward_id')),
          name: rs.getString(rs.getColumnIndex('name')),
          price: rs.getLong(rs.getColumnIndex('price')),
          kind: rs.getString(rs.getColumnIndex('kind')),
          description: rs.getString(rs.getColumnIndex('description')),
          repeatable: rs.getLong(rs.getColumnIndex('repeatable')) === 1,
          priceVersion: rs.getString(rs.getColumnIndex('price_version'))
        });
      }
    } finally {
      rs.close();
    }
    return out;
  }

  async listBadgeDefs(): Promise<BadgeDef[]> {
    const rs = await this.db().querySql(`SELECT * FROM ${Tables.BADGE_DEF}`);
    const out: BadgeDef[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push({
          badgeId: rs.getString(rs.getColumnIndex('badge_id')),
          name: rs.getString(rs.getColumnIndex('name')),
          condition: rs.getString(rs.getColumnIndex('condition')),
          ruleKind: rs.getString(rs.getColumnIndex('rule_kind')),
          ruleCategory: rs.getString(rs.getColumnIndex('rule_category')),
          ruleThreshold: rs.getLong(rs.getColumnIndex('rule_threshold')),
          achievement: rs.getLong(rs.getColumnIndex('achievement')) === 1
        });
      }
    } finally {
      rs.close();
    }
    return out;
  }

  async listBadgeUnlocks(): Promise<BadgeUnlock[]> {
    const rs = await this.db().querySql(`SELECT * FROM ${Tables.BADGE_UNLOCK} ORDER BY unlocked_at DESC`);
    const out: BadgeUnlock[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push({
          badgeId: rs.getString(rs.getColumnIndex('badge_id')),
          unlockedAt: rs.getString(rs.getColumnIndex('unlocked_at')),
          reason: rs.getString(rs.getColumnIndex('reason'))
        });
      }
    } finally {
      rs.close();
    }
    return out;
  }

  async unlockBadge(badgeId: string, reason: string): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'badge_id': badgeId,
      'unlocked_at': DateUtil.toDateTime(new Date()),
      'reason': reason
    };
    await this.upsert(Tables.BADGE_UNLOCK, bucket);
  }

  // ================= plan =================

  async insertPlan(plan: WeeklyPlan): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'plan_id': plan.planId,
      'plan_version': plan.planVersion,
      'constraints_json': plan.constraintsJson,
      'factor_set_version': plan.factorSetVersion,
      'created_at': plan.createdAt
    };
    await this.upsert(Tables.WEEKLY_PLAN, bucket);
  }

  async insertPlanTask(t: PlanTask): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'plan_task_id': t.planTaskId,
      'plan_id': t.planId,
      'template_id': t.templateId,
      'name': t.name,
      'category': t.category,
      'day': t.day,
      'status': t.status,
      'expected_kg': t.expectedKg,
      'quantity': t.quantity,
      'unit': t.unit,
      'extra_minutes': t.extraMinutes,
      'extra_cost': t.extraCost,
      'reason': t.reason,
      'participation_only': t.participationOnly ? 1 : 0,
      'linked_record_id': t.linkedRecordId,
      'actual_kg': t.actualKg,
      'rewarded': t.rewarded ? 1 : 0
    };
    await this.upsert(Tables.PLAN_TASK, bucket);
  }

  async updatePlanTask(t: PlanTask): Promise<void> {
    await this.insertPlanTask(t);
  }

  private readPlanTask(rs: relationalStore.ResultSet): PlanTask {
    return {
      planTaskId: rs.getString(rs.getColumnIndex('plan_task_id')),
      planId: rs.getString(rs.getColumnIndex('plan_id')),
      templateId: rs.getString(rs.getColumnIndex('template_id')),
      name: rs.getString(rs.getColumnIndex('name')),
      category: rs.getString(rs.getColumnIndex('category')) as BehaviorCategory,
      day: rs.getString(rs.getColumnIndex('day')),
      status: rs.getString(rs.getColumnIndex('status')) as PlanTaskStatus,
      expectedKg: rs.getDouble(rs.getColumnIndex('expected_kg')),
      quantity: rs.getDouble(rs.getColumnIndex('quantity')),
      unit: rs.getString(rs.getColumnIndex('unit')),
      extraMinutes: rs.getLong(rs.getColumnIndex('extra_minutes')),
      extraCost: rs.getDouble(rs.getColumnIndex('extra_cost')),
      reason: rs.getString(rs.getColumnIndex('reason')),
      participationOnly: rs.getLong(rs.getColumnIndex('participation_only')) === 1,
      linkedRecordId: rs.getString(rs.getColumnIndex('linked_record_id')),
      actualKg: rs.getDouble(rs.getColumnIndex('actual_kg')),
      rewarded: rs.getLong(rs.getColumnIndex('rewarded')) === 1
    };
  }

  async listPlanTasks(planId: string): Promise<PlanTask[]> {
    const rs = await this.db().querySql(
      `SELECT * FROM ${Tables.PLAN_TASK} WHERE plan_id = ? ORDER BY day ASC, template_id ASC`, [planId]);
    const out: PlanTask[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push(this.readPlanTask(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  async getLatestPlanId(): Promise<string> {
    return this.scalarText(`SELECT plan_id FROM ${Tables.WEEKLY_PLAN} ORDER BY created_at DESC LIMIT 1`);
  }

  async getPlan(planId: string): Promise<WeeklyPlan | null> {
    const rs = await this.db().querySql(`SELECT * FROM ${Tables.WEEKLY_PLAN} WHERE plan_id = ?`, [planId]);
    let p: WeeklyPlan | null = null;
    try {
      if (rs.goToNextRow()) {
        p = {
          planId: rs.getString(rs.getColumnIndex('plan_id')),
          planVersion: rs.getLong(rs.getColumnIndex('plan_version')),
          constraintsJson: rs.getString(rs.getColumnIndex('constraints_json')),
          createdAt: rs.getString(rs.getColumnIndex('created_at')),
          factorSetVersion: rs.getString(rs.getColumnIndex('factor_set_version'))
        };
      }
    } finally {
      rs.close();
    }
    return p;
  }

  // ================= content =================

  async listArticles(): Promise<Article[]> {
    const rs = await this.db().querySql(`SELECT * FROM ${Tables.ARTICLE} ORDER BY category ASC, article_id ASC`);
    const out: Article[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push({
          articleId: rs.getString(rs.getColumnIndex('article_id')),
          title: rs.getString(rs.getColumnIndex('title')),
          category: rs.getString(rs.getColumnIndex('category')) as ArticleCategory,
          summary: rs.getString(rs.getColumnIndex('summary')),
          body: rs.getString(rs.getColumnIndex('body')),
          image: rs.getString(rs.getColumnIndex('image')),
          sourceTitle: rs.getString(rs.getColumnIndex('source_title')),
          sourceUrl: rs.getString(rs.getColumnIndex('source_url')),
          imageLicense: rs.getString(rs.getColumnIndex('image_license')),
          readMinutes: rs.getLong(rs.getColumnIndex('read_minutes'))
        });
      }
    } finally {
      rs.close();
    }
    return out;
  }

  // ================= 计数（备份校验与统计） =================

  async countRows(table: string): Promise<number> {
    return this.scalar(`SELECT COUNT(1) FROM ${table}`);
  }

  /** 已记录行为的累计合格减排量（仅统计有效记录、最新版本、结果为正的减排） */
  async sumEligibleReductionKg(): Promise<number> {
    return this.scalar(
      `SELECT COALESCE(SUM(s.reduction_kg),0) FROM ${Tables.CALCULATION_SNAPSHOT} s
       JOIN ${Tables.BEHAVIOR_RECORD} r ON r.record_id = s.record_id AND r.revision = s.revision
       JOIN (SELECT record_id, MAX(revision) AS mx FROM ${Tables.BEHAVIOR_RECORD} GROUP BY record_id) m
         ON m.record_id = s.record_id AND m.mx = s.revision
       WHERE r.status = 'active' AND s.reduction_kg > 0`);
  }

  /**
   * 排除指定记录（含其全部版本）后的累计合格减排量。
   * 事务内读不到未提交写入，因此积分结算在开启写事务前用此口径推算「变更后累计量」。
   */
  async sumEligibleReductionKgExcluding(recordId: string): Promise<number> {
    return this.scalar(
      `SELECT COALESCE(SUM(s.reduction_kg),0) FROM ${Tables.CALCULATION_SNAPSHOT} s
       JOIN ${Tables.BEHAVIOR_RECORD} r ON r.record_id = s.record_id AND r.revision = s.revision
       JOIN (SELECT record_id, MAX(revision) AS mx FROM ${Tables.BEHAVIOR_RECORD} GROUP BY record_id) m
         ON m.record_id = s.record_id AND m.mx = s.revision
       WHERE r.status = 'active' AND s.reduction_kg > 0 AND r.record_id <> ?`,
      [recordId]);
  }

  async eligibleReductionTotalsExcluding(recordId: string): Promise<Map<string, number>> {
    const totals: Map<string, number> = new Map<string, number>();
    for (const row of await this.queryStatRows()) {
      if (row.recordId !== recordId && row.reductionKg > 0) { totals.set(`${row.gasScope}`, (totals.get(`${row.gasScope}`) || 0) + row.reductionKg); }
    }
    return totals;
  }

  /** 有效记录日期集合（排除指定记录后），用于连续打卡推算 */
  async listActiveDaysExcluding(recordId: string): Promise<string[]> {
    const rs = await this.db().querySql(
      `SELECT DISTINCT r.day_key FROM ${Tables.BEHAVIOR_RECORD} r
       JOIN (SELECT record_id, MAX(revision) AS mx FROM ${Tables.BEHAVIOR_RECORD} GROUP BY record_id) m ON r.record_id = m.record_id AND r.revision = m.mx
       WHERE r.status = 'active' AND r.record_id <> ? ORDER BY r.day_key DESC`, [recordId]);
    const out: string[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push(rs.getString(0));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  /** 有效记录条数（最新版本） */
  async countLatestActiveRecords(): Promise<number> {
    return this.scalar(
      `SELECT COUNT(1) FROM ${Tables.BEHAVIOR_RECORD} r
       JOIN (SELECT record_id, MAX(revision) AS mx FROM ${Tables.BEHAVIOR_RECORD} GROUP BY record_id) m
         ON m.record_id = r.record_id AND m.mx = r.revision
       WHERE r.status = 'active'`);
  }

  /** 参与统计的有效记录行（最新版本，含发生日期、类别、结果与口径） */
  async queryStatRows(): Promise<StatRow[]> {
    const rs = await this.db().querySql(
      `SELECT s.record_id AS rid, s.revision AS rev, r.occurred_at AS day_key, s.category AS category,
              s.reduction_kg AS reduction_kg, s.gas_scope AS gas_scope
       FROM ${Tables.CALCULATION_SNAPSHOT} s
       JOIN ${Tables.BEHAVIOR_RECORD} r ON r.record_id = s.record_id AND r.revision = s.revision
       JOIN (SELECT record_id, MAX(revision) AS mx FROM ${Tables.BEHAVIOR_RECORD} GROUP BY record_id) m
         ON m.record_id = s.record_id AND m.mx = s.revision
       WHERE r.status = 'active'
       ORDER BY r.occurred_at DESC`);
    const out: StatRow[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push({
          recordId: rs.getString(rs.getColumnIndex('rid')),
          revision: rs.getLong(rs.getColumnIndex('rev')),
          dayKey: rs.getString(rs.getColumnIndex('day_key')),
          category: rs.getString(rs.getColumnIndex('category')) as BehaviorCategory,
          reductionKg: rs.getDouble(rs.getColumnIndex('reduction_kg')),
          gasScope: rs.getString(rs.getColumnIndex('gas_scope')) as GasScope
        });
      }
    } finally {
      rs.close();
    }
    return out;
  }

  // ================= 种子数据 =================

  async seedFactors(factors: CarbonFactor[]): Promise<void> {
    for (const f of factors) {
      const bucket: relationalStore.ValuesBucket = {
        'code': f.code, 'version': f.version, 'category': f.category, 'sub_item': f.subItem,
        'scenario_label': f.scenarioLabel, 'value': f.value, 'gas_scope': f.gasScope,
        'per_unit': f.perUnit, 'distance_basis': f.distanceBasis, 'usable_as': f.usableAs,
        'region': f.region, 'data_year': f.dataYear, 'boundary': f.boundary, 'methodology': f.methodology,
        'source_title': f.sourceTitle, 'source_url': f.sourceUrl, 'source_locator': f.sourceLocator,
        'published_at': f.publishedAt, 'license_note': f.licenseNote, 'review_status': f.reviewStatus,
        'reviewer': f.reviewer, 'verified_by': f.verifiedBy, 'note': f.note
      };
      await this.upsert(Tables.CARBON_FACTOR, bucket);
    }
  }

  async seedRewards(rewards: RewardDef[]): Promise<void> {
    for (const r of rewards) {
      const bucket: relationalStore.ValuesBucket = {
        'reward_id': r.rewardId, 'name': r.name, 'price': r.price, 'kind': r.kind,
        'description': r.description, 'repeatable': r.repeatable ? 1 : 0, 'price_version': r.priceVersion
      };
      await this.upsert(Tables.REWARD_DEF, bucket);
    }
  }

  async seedBadges(badges: BadgeDef[]): Promise<void> {
    for (const b of badges) {
      const bucket: relationalStore.ValuesBucket = {
        'badge_id': b.badgeId, 'name': b.name, 'condition': b.condition, 'rule_kind': b.ruleKind,
        'rule_category': b.ruleCategory, 'rule_threshold': b.ruleThreshold, 'achievement': b.achievement ? 1 : 0
      };
      await this.upsert(Tables.BADGE_DEF, bucket);
    }
  }

  async seedTemplates(templates: TaskTemplate[]): Promise<void> {
    for (const t of templates) {
      const bucket: relationalStore.ValuesBucket = {
        'template_id': t.templateId, 'name': t.name, 'category': t.category,
        'applicable_when': t.applicableWhen, 'evidence_rule': t.evidenceRule, 'measure_unit': t.measureUnit,
        'factor_sub_item': t.factorSubItem, 'substitute_scenario': t.substituteScenario,
        'default_quantity': t.defaultQuantity, 'extra_minutes': t.extraMinutes, 'extra_cost': t.extraCost,
        'allowed_weekdays': t.allowedWeekdays.join(','), 'mutex_group': t.mutexGroup,
        'max_times_per_week': t.maxTimesPerWeek,
        'has_comparable_quantity': t.hasComparableQuantity ? 1 : 0, 'explain_template': t.explainTemplate
      };
      await this.upsert(Tables.TASK_TEMPLATE, bucket);
    }
  }

  async seedArticles(articles: Article[]): Promise<void> {
    for (const a of articles) {
      const bucket: relationalStore.ValuesBucket = {
        'article_id': a.articleId, 'title': a.title, 'category': a.category, 'summary': a.summary,
        'body': a.body, 'image': a.image, 'source_title': a.sourceTitle, 'source_url': a.sourceUrl,
        'image_license': a.imageLicense, 'read_minutes': a.readMinutes
      };
      await this.upsert(Tables.ARTICLE, bucket);
    }
  }

  // ================= 模板读取 =================

  /** 读取任务模板池（供计划引擎使用） */
  async listTemplates(): Promise<TaskTemplate[]> {
    const rs = await this.db().querySql(`SELECT * FROM ${Tables.TASK_TEMPLATE} ORDER BY template_id ASC`);
    const out: TaskTemplate[] = [];
    try {
      while (rs.goToNextRow()) {
        const weekdaysText = rs.getString(rs.getColumnIndex('allowed_weekdays'));
        const weekdays: number[] = [];
        if (weekdaysText.length > 0) {
          for (const piece of weekdaysText.split(',')) {
            const n = Number.parseInt(piece, 10);
            if (!Number.isNaN(n)) {
              weekdays.push(n);
            }
          }
        }
        out.push({
          templateId: rs.getString(rs.getColumnIndex('template_id')),
          name: rs.getString(rs.getColumnIndex('name')),
          category: rs.getString(rs.getColumnIndex('category')) as BehaviorCategory,
          applicableWhen: rs.getString(rs.getColumnIndex('applicable_when')),
          evidenceRule: rs.getString(rs.getColumnIndex('evidence_rule')),
          measureUnit: rs.getString(rs.getColumnIndex('measure_unit')) as QuantityUnit,
          factorSubItem: rs.getString(rs.getColumnIndex('factor_sub_item')),
          substituteScenario: rs.getString(rs.getColumnIndex('substitute_scenario')),
          defaultQuantity: rs.getDouble(rs.getColumnIndex('default_quantity')),
          extraMinutes: rs.getLong(rs.getColumnIndex('extra_minutes')),
          extraCost: rs.getDouble(rs.getColumnIndex('extra_cost')),
          allowedWeekdays: weekdays,
          mutexGroup: rs.getString(rs.getColumnIndex('mutex_group')),
          maxTimesPerWeek: rs.getLong(rs.getColumnIndex('max_times_per_week')),
          hasComparableQuantity: rs.getLong(rs.getColumnIndex('has_comparable_quantity')) === 1,
          explainTemplate: rs.getString(rs.getColumnIndex('explain_template'))
        });
      }
    } finally {
      rs.close();
    }
    return out;
  }

  // ================= 计划任务读取 =================

  async getPlanTask(planTaskId: string): Promise<PlanTask | null> {
    const rs = await this.db().querySql(
      `SELECT * FROM ${Tables.PLAN_TASK} WHERE plan_task_id = ?`, [planTaskId]);
    let t: PlanTask | null = null;
    try {
      if (rs.goToNextRow()) {
        t = this.readPlanTask(rs);
      }
    } finally {
      rs.close();
    }
    return t;
  }

  /** 按关联记录查找计划任务（记录撤销后回算任务状态） */
  async listPlanTasksByRecord(recordId: string): Promise<PlanTask[]> {
    const rs = await this.db().querySql(
      `SELECT * FROM ${Tables.PLAN_TASK} WHERE linked_record_id = ?`, [recordId]);
    const out: PlanTask[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push(this.readPlanTask(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  // ================= 备份通用读写 =================

  /** 整表导出为值桶数组（表名来自固定白名单，不拼接用户输入） */
  async dumpTable(table: string): Promise<relationalStore.ValuesBucket[]> {
    const rs = await this.db().querySql(`SELECT * FROM ${table}`);
    const out: relationalStore.ValuesBucket[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push(rs.getRow());
      }
    } finally {
      rs.close();
    }
    return out;
  }

  /** 逐行写入（恢复用，冲突时替换，保证重复导入结果一致） */
  async importRow(table: string, row: relationalStore.ValuesBucket): Promise<void> {
    await this.db().insert(table, row, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  /** 清空整表 */
  async deleteAllRows(table: string): Promise<void> {
    await this.exec(`DELETE FROM ${table}`);
  }

  /** 统计某引用值的行数（恢复前引用完整性校验） */
  async countWhere(table: string, column: string, value: relationalStore.ValueType): Promise<number> {
    return this.scalar(`SELECT COUNT(1) FROM ${table} WHERE ${column} = ?`, [value]);
  }

  /** 备份与恢复需要的表清单（第 9.3 节） */
  static backupTables(): string[] {
    return [
      Tables.BEHAVIOR_RECORD, Tables.CALCULATION_SNAPSHOT, Tables.CARBON_FACTOR,
      Tables.POINT_EVENT, Tables.REWARD_DEF, Tables.REDEMPTION,
      Tables.BADGE_DEF, Tables.BADGE_UNLOCK, Tables.TASK_TEMPLATE,
      Tables.WEEKLY_PLAN, Tables.PLAN_TASK, Tables.ARTICLE, Tables.ATTACHMENT
    ];
  }
}
