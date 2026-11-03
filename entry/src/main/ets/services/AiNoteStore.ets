import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AiNoteEntry } from '../models/AiModels';
import { Result, ErrorCode } from '../common/AppError';
import { DateUtil } from '../common/Format';
import { AiCoachService } from './AiCoachService';

/** 偏好文件内容：键为周报周期（周一）日期 */
interface AiNoteFile {
  notes: Record<string, AiNoteEntry>;
}

/**
 * AI 周报备注存储（可选功能）。
 * 边界：只写应用沙箱 preferences，不写 RDB、不进备份/CSV 导出，不写日志；卸载应用即清除。
 * 每个周报周期保留一条，新存覆盖同周旧文本，最多保留最近 8 周；入库文本先经 AI 清洗（去符号、限长）。
 */
export class AiNoteStore {
  private static readonly FILE_NAME = 'ai_coach_notes';
  private static readonly MAX_WEEKS = 8;

  static async saveNote(context: common.Context, day: string, rawText: string, model: string): Promise<Result<boolean>> {
    const text = AiCoachService.sanitize(rawText);
    if (text.length === 0) {
      return Result.failure(ErrorCode.E_INPUT_EMPTY, 'AI 文本为空，未保存备注。');
    }
    try {
      const store = await preferences.getPreferences(context, AiNoteStore.FILE_NAME);
      const file = await AiNoteStore.readAll(store);
      const entry: AiNoteEntry = {
        text: text,
        model: model.trim(),
        createdAt: DateUtil.toDateTime(new Date())
      };
      file.notes[DateUtil.weekStart(day)] = entry;
      const kept = AiNoteStore.prune(file.notes);
      await store.put(AiNoteStore.FILE_NAME, JSON.stringify({ notes: kept }));
      await store.flush();
      return Result.success(true);
    } catch (e) {
      return Result.failure(ErrorCode.E_IO, `保存 AI 备注失败：${AiNoteStore.errText(e)}`);
    }
  }

  /** 读取某天所在周报周期的备注；没有则返回 null */
  static async loadNote(context: common.Context, day: string): Promise<AiNoteEntry | null> {
    try {
      const store = await preferences.getPreferences(context, AiNoteStore.FILE_NAME);
      const file = await AiNoteStore.readAll(store);
      const entry = file.notes[DateUtil.weekStart(day)];
      return entry !== undefined ? entry : null;
    } catch (e) {
      return null;
    }
  }

  static async readAll(store: preferences.Preferences): Promise<AiNoteFile> {
    const raw = `${await store.get(AiNoteStore.FILE_NAME, '')}`;
    if (raw.length === 0) {
      const empty: Record<string, AiNoteEntry> = {};
      return { notes: empty };
    }
    try {
      const parsed = JSON.parse(raw) as AiNoteFile;
      if (parsed.notes === undefined || parsed.notes === null) {
        const empty: Record<string, AiNoteEntry> = {};
        return { notes: empty };
      }
      return parsed;
    } catch (e) {
      const empty: Record<string, AiNoteEntry> = {};
      return { notes: empty };
    }
  }

  /** 只保留最近 MAX_WEEKS 周；键为周一日期，字典序即时间序，超出部分丢弃 */
  static prune(notes: Record<string, AiNoteEntry>): Record<string, AiNoteEntry> {
    const weeks = Object.keys(notes).sort();
    const out: Record<string, AiNoteEntry> = {};
    const skip = weeks.length > AiNoteStore.MAX_WEEKS ? weeks.length - AiNoteStore.MAX_WEEKS : 0;
    for (let i = skip; i < weeks.length; i++) {
      out[weeks[i]] = notes[weeks[i]];
    }
    return out;
  }

  private static errText(e: object): string {
    const msg = (e as Error).message;
    return msg !== undefined ? msg : JSON.stringify(e);
  }
}
