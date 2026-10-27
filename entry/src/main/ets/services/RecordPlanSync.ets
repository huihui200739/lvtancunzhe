import { LedgerDb } from './LedgerDb';
import { PlanLinkPolicy } from './PlanLinkPolicy';
import { PointService } from './PointService';
import { FactorRepository } from './FactorRepository';
import { BehaviorRecord, CalculationSnapshot } from '../models/RecordModels';
import { TaskTemplate } from '../models/PlanModels';
import { DateUtil } from '../common/Format';
import { PlanTaskStatus, RecordStatus } from '../common/Domain';

/** Runs inside the record transaction; failures roll back record, points and task together. */
export class RecordPlanSync {
  static async apply(db: LedgerDb, record: BehaviorRecord, snapshot: CalculationSnapshot | null,
    repo: FactorRepository): Promise<void> {
    const tasks = await db.listPlanTasksByRecord(record.recordId);
    const templates = tasks.length > 0 ? await db.listTemplates() : [];
    for (const task of tasks) {
      const template = templates.find((t: TaskTemplate) => t.templateId === task.templateId);
      const valid = record.status === RecordStatus.ACTIVE && snapshot !== null &&
        PlanLinkPolicy.recordError(task, record, snapshot, template, tasks, repo).length === 0;
      if (valid && snapshot !== null) {
        task.actualKg = task.participationOnly ? 0 : snapshot.reductionKg;
      } else {
        await PointService.revokeParticipation(db, task.planTaskId, DateUtil.today());
        task.status = PlanTaskStatus.PLANNED;
        task.linkedRecordId = '';
        task.actualKg = 0;
        task.rewarded = false;
      }
      await db.updatePlanTask(task);
    }
  }
}
