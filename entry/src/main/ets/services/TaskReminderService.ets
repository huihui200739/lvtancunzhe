import { calendarManager } from '@kit.CalendarKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Result, ErrorCode } from '../common/AppError';
import { DateUtil } from '../common/Format';
import { PlanTask } from '../models/PlanModels';
import { PlanTaskStatus } from '../common/Domain';

/** 已加入系统日历的计划任务 */
export interface TaskReminder {
  planTaskId: string;
  eventId: number;
  day: string;
  hour: number;
  title: string;
}

interface ReminderFile {
  items: TaskReminder[];
}

/**
 * 计划任务提醒：把用户保存的七日计划任务加入系统日历，由日历在当天按时提醒。
 * 用 calendarManager.editEvent 打开系统日历的新建页，用户在系统界面确认后才保存，无需日历读写权限；
 * 关闭应用后日历仍会提醒。只提醒，不自动完成任务、不生成记录；标识存在本机偏好文件，不进账本。
 *
 * 说明：系统代理提醒（reminderAgentManager）在未签名调试包上被系统拒绝（需要 reminder 能力），故不采用。
 */
export class TaskReminderService {
  private static readonly FILE: string = 'task_reminders';
  private static readonly KEY: string = 'items';
  static readonly DEFAULT_HOUR: number = 19;
  /** 日历事件时长（分钟）与提前提醒（分钟） */
  static readonly DURATION_MIN: number = 30;
  static readonly REMIND_BEFORE_MIN: number = 0;

  /** 纯函数：判断任务能否提醒，并给出开始时刻；不能时返回原因 */
  static plan(task: PlanTask, now: Date, hour: number = TaskReminderService.DEFAULT_HOUR): Result<Date> {
    if (task.status !== PlanTaskStatus.PLANNED && task.status !== PlanTaskStatus.IN_PROGRESS) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '这项任务已完成或已跳过，不再提醒。');
    }
    if (!DateUtil.isValidDay(task.day)) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '任务日期无效。');
    }
    if (!Number.isInteger(hour) || hour < 0 || hour > 23) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, '提醒时间无效。');
    }
    const at = DateUtil.parseDay(task.day);
    at.setHours(hour, 0, 0, 0);
    if (at.getTime() <= now.getTime() + 60000) {
      return Result.failure(ErrorCode.E_FUTURE_DATE, `${task.day} ${hour}:00 已经过去，换一项之后的任务。`);
    }
    return Result.success(at);
  }

  static content(task: PlanTask): string {
    return task.participationOnly ? `${task.name}：完成后在「绿碳存折」计划里记下参与（不计 kg）。`
      : `${task.name}：完成后打开「绿碳存折」，按真实数量记一笔。`;
  }

  /** 纯函数：生成日历事件；时间为本地时区毫秒时间戳 */
  static eventFor(task: PlanTask, at: Date): calendarManager.Event {
    return {
      type: calendarManager.EventType.NORMAL,
      title: `绿碳存折 · ${task.name}`,
      description: TaskReminderService.content(task),
      startTime: at.getTime(),
      endTime: at.getTime() + TaskReminderService.DURATION_MIN * 60000,
      reminderTime: [TaskReminderService.REMIND_BEFORE_MIN]
    };
  }

  static async list(context: common.Context): Promise<TaskReminder[]> {
    try {
      const store = await preferences.getPreferences(context, TaskReminderService.FILE);
      const raw = `${await store.get(TaskReminderService.KEY, '')}`;
      if (raw.length === 0) {
        return [];
      }
      const parsed = JSON.parse(raw) as ReminderFile;
      return Array.isArray(parsed.items) ? parsed.items : [];
    } catch (e) {
      return [];
    }
  }

  private static async save(context: common.Context, items: TaskReminder[]): Promise<void> {
    const store = await preferences.getPreferences(context, TaskReminderService.FILE);
    const file: ReminderFile = { items: items };
    await store.put(TaskReminderService.KEY, JSON.stringify(file));
    await store.flush();
  }

  /** 打开系统日历的新建事件页；用户保存后记下事件号，取消则不记 */
  static async schedule(context: common.UIAbilityContext, task: PlanTask,
    hour: number = TaskReminderService.DEFAULT_HOUR): Promise<Result<TaskReminder>> {
    const when = TaskReminderService.plan(task, new Date(), hour);
    if (!when.ok || when.data === null) {
      return Result.failure(when.code, when.message);
    }
    try {
      const manager = calendarManager.getCalendarManager(context);
      const eventId = await manager.editEvent(TaskReminderService.eventFor(task, when.data));
      if (!Number.isFinite(eventId) || eventId <= 0) {
        return Result.failure(ErrorCode.E_INPUT_EMPTY, '没有保存到日历。');
      }
      const item: TaskReminder = { planTaskId: task.planTaskId, eventId: eventId, day: task.day, hour: hour, title: task.name };
      const existing = await TaskReminderService.list(context);
      const kept = existing.filter((r: TaskReminder) => r.planTaskId !== task.planTaskId && r.day >= DateUtil.today());
      await TaskReminderService.save(context, kept.concat([item]));
      return Result.success(item);
    } catch (e) {
      return Result.failure(ErrorCode.E_IO, `打开系统日历失败：${(e as Error).message}`);
    }
  }

  /** 只清除本应用的记录；日历里的事件由用户在系统日历中删除（本应用不申请日历写权限） */
  static async forget(context: common.Context, planTaskId: string): Promise<void> {
    const existing = await TaskReminderService.list(context);
    await TaskReminderService.save(context, existing.filter((r: TaskReminder) => r.planTaskId !== planTaskId));
  }
}
