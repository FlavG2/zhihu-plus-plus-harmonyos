import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';

// 屏蔽记录（对齐安卓 BlockedFeedRecord，用于「屏蔽记录」页展示）
export interface BlockedFeedRecord {
  id: string;
  title: string;
  authorName: string;
  reason: string;
  url: string;
  time: number;
}

const FILE_NAME: string = 'zhihu_block_history';
const KEY: string = 'blocked_feed_records';
const MAX_RECORDS: number = 200;

export class BlockHistoryRepository {
  static getRecords(context: common.Context): BlockedFeedRecord[] {
    const raw = preferences.getPreferencesSync(context, { name: FILE_NAME }).getSync(KEY, '') as string;
    if (raw.length === 0) {
      return [];
    }
    try {
      return JSON.parse(raw) as BlockedFeedRecord[];
    } catch (e) {
      return [];
    }
  }

  static addRecord(context: common.Context, rec: BlockedFeedRecord): void {
    const list = this.getRecords(context);
    list.unshift(rec);
    const trimmed = list.slice(0, MAX_RECORDS);
    const store = preferences.getPreferencesSync(context, { name: FILE_NAME });
    store.putSync(KEY, JSON.stringify(trimmed));
    store.flushSync();
  }

  static clear(context: common.Context): void {
    const store = preferences.getPreferencesSync(context, { name: FILE_NAME });
    store.deleteSync(KEY);
    store.flushSync();
  }
}
