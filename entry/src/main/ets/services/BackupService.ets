import { LedgerOperations } from './LedgerOperations';
import { DATA_ENVIRONMENT } from '../common/DataEnvironment';
import { DEV_FACTOR_MODE } from '../common/BuildConfig';
import { BackupPolicy } from './BackupPolicy';
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { LedgerDb } from './LedgerDb';
import { Tables } from './LedgerSchema';
import { Result, ErrorCode } from '../common/AppError';
import { DateUtil } from '../common/Format';
import { APP_VERSION, SCHEMA_VERSION } from '../common/BuildConfig';
import { BackupFile, BackupTables } from '../models/BackupModels';

/**
 * 备份与恢复服务（第 9.3 节、第 4.1 节 B5）。
 *
 * 备份：全量 JSON，包含 schema_version、导出时间、业务表、完整计算快照、
 *       积分事件、兑换、计划与所需附件；附件保存相对路径。
 * 恢复：先校验结构 / 版本 / 引用完整性 / 数量范围，再自动保存当前数据快照，
 *       最后事务替换；重复导入同一备份结果不变，不重放发分逻辑；
 *       损坏或高版本文件拒绝导入并保留原库。
 */
export class BackupService {

  private static readonly MAX_ROWS = 200000;
  private static readonly AUTOSAVE_NAME = 'backup_autosave_before_restore.json';

  /** 导出全量备份 JSON 文本 */
  static async buildBackup(db: LedgerDb): Promise<Result<string>> {
    return LedgerOperations.run(() => BackupService.buildBackupUnlocked(db));
  }

  private static async buildBackupUnlocked(db: LedgerDb): Promise<Result<string>> {
    try {
      const factorSetVersion = await db.getMeta('factor_set_version');
      const tables: BackupTables = {
        behavior_record: await db.dumpTable(Tables.BEHAVIOR_RECORD),
        calculation_snapshot: await db.dumpTable(Tables.CALCULATION_SNAPSHOT),
        carbon_factor: await db.dumpTable(Tables.CARBON_FACTOR),
        point_event: await db.dumpTable(Tables.POINT_EVENT),
        reward_def: await db.dumpTable(Tables.REWARD_DEF),
        redemption: await db.dumpTable(Tables.REDEMPTION),
        badge_def: await db.dumpTable(Tables.BADGE_DEF),
        badge_unlock: await db.dumpTable(Tables.BADGE_UNLOCK),
        task_template: await db.dumpTable(Tables.TASK_TEMPLATE),
        weekly_plan: await db.dumpTable(Tables.WEEKLY_PLAN),
        plan_task: await db.dumpTable(Tables.PLAN_TASK),
        article: await db.dumpTable(Tables.ARTICLE),
        attachment: await db.dumpTable(Tables.ATTACHMENT)
      };
      const file: BackupFile = {
        schemaVersion: SCHEMA_VERSION,
        dataEnvironment: DATA_ENVIRONMENT,
        appVersion: APP_VERSION,
        exportedAt: DateUtil.toDateTime(new Date()),
        factorSetVersion: factorSetVersion,
        tables: tables
      };
      return Result.success(JSON.stringify(file));
    } catch (e) {
      return Result.failure(ErrorCode.E_STORAGE, `导出备份失败：${BackupService.errText(e)}`);
    }
  }

  /** 校验备份文本，返回可读错误（合法时 message 为空） */
  static validate(text: string): Result<BackupFile> {
    let file: BackupFile;
    try {
      file = JSON.parse(text) as BackupFile;
    } catch (e) {
      return Result.failure(ErrorCode.E_RESTORE_INVALID, '备份文件不是合法 JSON，已拒绝导入。');
    }
    if (file === null || file === undefined) {
      return Result.failure(ErrorCode.E_RESTORE_INVALID, '备份文件为空，已拒绝导入。');
    }
    if (typeof file.schemaVersion !== 'number' || !Number.isInteger(file.schemaVersion) || file.schemaVersion < 1) {
      return Result.failure(ErrorCode.E_RESTORE_INVALID, '备份文件缺少 schema 版本，已拒绝导入。');
    }
    if (file.schemaVersion > SCHEMA_VERSION) {
      return Result.failure(ErrorCode.E_RESTORE_VERSION,
        `备份版本 ${file.schemaVersion} 高于当前支持的 ${SCHEMA_VERSION}，请升级应用后再导入。`);
    }
    if (file.tables === null || file.tables === undefined) {
      return Result.failure(ErrorCode.E_RESTORE_INVALID, '备份文件缺少业务表，已拒绝导入。');
    }
    const shapeError = BackupService.checkShape(file.tables);
    if (shapeError.length > 0) {
      return Result.failure(ErrorCode.E_RESTORE_INVALID, shapeError);
    }
    const refError = BackupService.checkReferences(file.tables);
    if (refError.length > 0) {
      return Result.failure(ErrorCode.E_RESTORE_INVALID, refError);
    }
    const policyError = BackupPolicy.validate(file, DEV_FACTOR_MODE);
    if (policyError.length > 0) { return Result.failure(ErrorCode.E_RESTORE_INVALID, policyError); }
    return Result.success(file);
  }

  /**
   * 恢复：校验 → 自动保存当前快照 → 事务全量替换。
   * @param context 用于写入恢复前的自动快照（失败时保留原库并停止恢复）
   */
  static async restore(db: LedgerDb, text: string, context: common.Context): Promise<Result<boolean>> {
    return LedgerOperations.run(() => BackupService.restoreUnlocked(db, text, context));
  }

  private static async restoreUnlocked(db: LedgerDb, text: string, context: common.Context): Promise<Result<boolean>> {
    const checked = BackupService.validate(text);
    if (!checked.ok || checked.data === null) {
      return Result.failure(checked.code, checked.message);
    }
    const file = checked.data;

    // 恢复前自动保存当前数据（保存成功后才替换数据）
    const current = await BackupService.buildBackupUnlocked(db);
    if (!current.ok || current.data === null) { return Result.failure(ErrorCode.E_IO, '无法创建恢复前快照，原数据未修改。'); }
    const autosaved = await BackupService.writeToAppDir(context, BackupService.AUTOSAVE_NAME, current.data);
    if (!autosaved.ok) { return Result.failure(ErrorCode.E_IO, '无法保存恢复前快照，原数据未修改。'); }

    const t = file.tables;
    try {
      await db.begin();
      // 先清空，再按「定义表 → 业务表」顺序写入，重复导入结果一致
      const order: string[] = [
        Tables.CALCULATION_SNAPSHOT, Tables.POINT_EVENT, Tables.REDEMPTION,
        Tables.BADGE_UNLOCK, Tables.PLAN_TASK, Tables.ATTACHMENT,
        Tables.BEHAVIOR_RECORD, Tables.WEEKLY_PLAN,
        Tables.CARBON_FACTOR, Tables.REWARD_DEF, Tables.BADGE_DEF,
        Tables.TASK_TEMPLATE, Tables.ARTICLE
      ];
      for (const name of order) {
        await db.deleteAllRows(name);
      }
      await BackupService.insertRows(db, Tables.CARBON_FACTOR, t.carbon_factor);
      await BackupService.insertRows(db, Tables.REWARD_DEF, t.reward_def);
      await BackupService.insertRows(db, Tables.BADGE_DEF, t.badge_def);
      await BackupService.insertRows(db, Tables.TASK_TEMPLATE, t.task_template);
      await BackupService.insertRows(db, Tables.ARTICLE, t.article);
      await BackupService.insertRows(db, Tables.BEHAVIOR_RECORD, t.behavior_record);
      await BackupService.insertRows(db, Tables.CALCULATION_SNAPSHOT, t.calculation_snapshot);
      await BackupService.insertRows(db, Tables.POINT_EVENT, t.point_event);
      await BackupService.insertRows(db, Tables.REDEMPTION, t.redemption);
      await BackupService.insertRows(db, Tables.BADGE_UNLOCK, t.badge_unlock);
      await BackupService.insertRows(db, Tables.WEEKLY_PLAN, t.weekly_plan);
      await BackupService.insertRows(db, Tables.PLAN_TASK, t.plan_task);
      await BackupService.insertRows(db, Tables.ATTACHMENT, t.attachment);
      await db.setMeta('data_environment', DATA_ENVIRONMENT);
      await db.setMeta('factor_set_version', file.factorSetVersion);
      let latestPlanId = '';
      let latestVersion = -1;
      for (const restoredPlan of t.weekly_plan) {
        const version = restoredPlan['plan_version'] as number;
        if (version > latestVersion) { latestVersion = version; latestPlanId = restoredPlan['plan_id'] as string; }
      }
      await db.setMeta('latest_plan_id', latestPlanId);
      await db.commit();
    } catch (e) {
      await db.rollBack();
      return Result.failure(ErrorCode.E_STORAGE, `恢复失败，已回滚并保留原库：${BackupService.errText(e)}`);
    }
    return Result.success(true);
  }

  /** 写入应用沙箱目录，返回完整路径 */
  static async writeToAppDir(context: common.Context, filename: string, text: string): Promise<Result<string>> {
    const path = `${context.filesDir}/${filename}`;
    try {
      const f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, text);
      fs.closeSync(f);
      return Result.success(path);
    } catch (e) {
      return Result.failure(ErrorCode.E_IO, `写入文件失败：${BackupService.errText(e)}`);
    }
  }

  /** 读取本地文件文本 */
  static readText(path: string): Result<string> {
    try {
      return Result.success(fs.readTextSync(path));
    } catch (e) {
      return Result.failure(ErrorCode.E_IO, `读取文件失败：${BackupService.errText(e)}`);
    }
  }

  /**
   * 通过系统保存入口把文本写到用户可见位置（第 9.4 节：写沙箱成功不等于相册 / 文件保存成功）。
   * 用户在系统文件选择器中确认位置，应用据此写入。
   */
  static async saveAs(context: common.Context, suggestedName: string, text: string): Promise<Result<string>> {
    try {
      const options: picker.DocumentSaveOptions = { newFileNames: [suggestedName] };
      const doc = new picker.DocumentViewPicker(context);
      const uris: string[] = await doc.save(options);
      if (uris.length === 0) {
        return Result.failure(ErrorCode.E_IO, '未选择保存位置，已取消。');
      }
      const f = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, text);
      fs.closeSync(f);
      return Result.success(uris[0]);
    } catch (e) {
      return Result.failure(ErrorCode.E_IO, `保存失败或已取消：${BackupService.errText(e)}`);
    }
  }

  /** 通过系统文件选择器让用户挑选并读取一个文本文件 */
  static async pickText(context: common.Context): Promise<Result<string>> {
    try {
      const options: picker.DocumentSelectOptions = { maxSelectNumber: 1 };
      const doc = new picker.DocumentViewPicker(context);
      const uris: string[] = await doc.select(options);
      if (uris.length === 0) {
        return Result.failure(ErrorCode.E_IO, '未选择文件，已取消。');
      }
      return Result.success(BackupService.readUriText(uris[0]));
    } catch (e) {
      return Result.failure(ErrorCode.E_IO, `读取失败或已取消：${BackupService.errText(e)}`);
    }
  }

  /**
   * 读取文件选择器返回的 URI 文本。
   * 注意：picker 返回的是 URI 而非沙箱路径，fs.readTextSync(uri) 会报
   * 「No such file or directory」，必须用 openSync(uri) 拿到 fd 再读取。
   */
  private static readUriText(uri: string): string {
    const f = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(f.fd);
      const size = stat.size;
      if (size <= 0) {
        return '';
      }
      const buf = new ArrayBuffer(size);
      const n = fs.readSync(f.fd, buf);
      return buffer.from(buf, 0, n).toString('utf-8');
    } finally {
      fs.closeSync(f);
    }
  }

  // —— 内部 ——

  private static async insertRows(db: LedgerDb, table: string,
    rows: relationalStore.ValuesBucket[]): Promise<void> {
    for (const row of rows) {
      await db.importRow(table, row);
    }
  }

  /** 结构校验：13 张表都存在且为数组，行数在合理范围内 */
  private static checkShape(t: BackupTables): string {
    const tables: relationalStore.ValuesBucket[][] = [
      t.behavior_record, t.calculation_snapshot, t.carbon_factor, t.point_event,
      t.reward_def, t.redemption, t.badge_def, t.badge_unlock, t.task_template,
      t.weekly_plan, t.plan_task, t.article, t.attachment
    ];
    const names: string[] = [
      'behavior_record', 'calculation_snapshot', 'carbon_factor', 'point_event',
      'reward_def', 'redemption', 'badge_def', 'badge_unlock', 'task_template',
      'weekly_plan', 'plan_task', 'article', 'attachment'
    ];
    for (let i = 0; i < tables.length; i++) {
      if (!Array.isArray(tables[i])) {
        return `备份缺少业务表 ${names[i]}，已拒绝导入。`;
      }
      for (const row of tables[i]) {
        if (row === null || typeof row !== 'object' || Array.isArray(row)) { return `业务表 ${names[i]} 含损坏行，已拒绝导入。`; }
      }
      if (tables[i].length > BackupService.MAX_ROWS) {
        return `业务表 ${names[i]} 行数异常（${tables[i].length}），已拒绝导入。`;
      }
    }
    return '';
  }

  /** 引用完整性校验（第 9.3 节） */
  private static checkReferences(t: BackupTables): string {
    const recordIds: Set<string> = new Set<string>();
    for (const r of t.behavior_record) {
      const id = BackupService.strOf(r, 'record_id');
      if (id.length > 0) {
        recordIds.add(id);
      }
    }
    const recordVersions: Set<string> = new Set<string>();
    for (const r of t.behavior_record) {
      const id = BackupService.strOf(r, 'record_id');
      const revision = r['revision'] as number;
      const key = `${id}#${revision}`;
      if (!id || !Number.isInteger(revision) || revision < 1 || recordVersions.has(key)) { return '备份记录版本缺失、重复或无效。'; }
      recordVersions.add(key);
    }
    const snapshotVersions: Set<string> = new Set<string>();
    for (const s of t.calculation_snapshot) {
      const key = `${s['record_id']}#${s['revision']}`;
      if (!recordVersions.has(key) || snapshotVersions.has(key)) { return '计算快照对应的记录版本不存在或重复。'; }
      snapshotVersions.add(key);
    }
    for (const key of recordVersions) { if (!snapshotVersions.has(key)) { return '行为记录缺少对应版本的计算快照。'; } }
    const planIds: Set<string> = new Set<string>();
    for (const p of t.weekly_plan) { planIds.add(BackupService.strOf(p, 'plan_id')); }
    for (const pt of t.plan_task) { if (!planIds.has(BackupService.strOf(pt, 'plan_id'))) { return '计划任务引用的计划不存在。'; } }
    const rewardIds: Set<string> = new Set<string>();
    for (const r of t.reward_def) {
      const id = BackupService.strOf(r, 'reward_id');
      if (id.length > 0) {
        rewardIds.add(id);
      }
    }
    for (const s of t.calculation_snapshot) {
      const rid = BackupService.strOf(s, 'record_id');
      if (rid.length > 0 && !recordIds.has(rid)) {
        return `计算快照引用了不存在的记录 ${rid}，已拒绝导入。`;
      }
    }
    for (const p of t.point_event) {
      const rid = BackupService.strOf(p, 'record_id');
      if (rid.length > 0 && !recordVersions.has(`${rid}#${p['revision']}`)) {
        return `积分事件引用了不存在的记录 ${rid}，已拒绝导入。`;
      }
    }
    for (const pt of t.plan_task) {
      const rid = BackupService.strOf(pt, 'linked_record_id');
      if (rid.length > 0 && !recordIds.has(rid)) {
        return `计划任务引用了不存在的记录 ${rid}，已拒绝导入。`;
      }
    }
    for (const rd of t.redemption) {
      const rewardId = BackupService.strOf(rd, 'reward_id');
      if (rewardId.length > 0 && !rewardIds.has(rewardId)) {
        return `兑换记录引用了不存在的奖励 ${rewardId}，已拒绝导入。`;
      }
    }
    return '';
  }

  private static strOf(row: relationalStore.ValuesBucket, key: string): string {
    const v = row[key];
    if (typeof v === 'string') {
      return v;
    }
    return '';
  }

  private static errText(e: object): string {
    const msg = (e as Error).message;
    return msg !== undefined ? msg : JSON.stringify(e);
  }
}
