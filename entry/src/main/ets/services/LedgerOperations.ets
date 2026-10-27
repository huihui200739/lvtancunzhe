/**
 * 同一应用中的账本操作按进入顺序执行。余额、版本等检查也必须在队列内，
 * 只锁 begin/commit 不能防止检查读取旧值。内部步骤不再入队，避免嵌套等待。
 */
export class LedgerOperations {
  private static tail: Promise<void> = Promise.resolve();

  static async run<T>(operation: () => Promise<T>): Promise<T> {
    const previous = LedgerOperations.tail;
    let release: () => void = () => {};
    LedgerOperations.tail = new Promise<void>((resolve) => { release = resolve; });
    await previous;
    try {
      return await operation();
    } finally {
      release();
    }
  }
}
