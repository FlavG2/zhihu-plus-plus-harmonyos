import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';

// 关注流类型筛选（对齐安卓：按「赞同了 XX / 想法 / 文章 / 回答」过滤），持久化到 preferences。
export type FollowFilterCategory = 'voteup' | 'pin' | 'article' | 'answer';

const PREFERENCES_FILE: string = 'zhihu_follow_filter';

const KEY_MAP: Record<FollowFilterCategory, string> = {
  voteup: 'filter_voteup',
  pin: 'filter_pin',
  article: 'filter_article',
  answer: 'filter_answer'
};

const DEFAULTS: Record<FollowFilterCategory, boolean> = {
  voteup: true,
  pin: true,
  article: true,
  answer: true
};

// 「屏蔽未关注作者」开关（独立于类型筛选，默认关 = 显示全部）
const KEY_HIDE_UNFOLLOWED: string = 'filter_hide_unfollowed';
const DEFAULT_HIDE_UNFOLLOWED: boolean = false;

export class FollowFilterRepository {
  // 读取全部筛选开关（默认 true = 显示该类别），同步写回 AppStorage 供 UI 直接读取。
  static load(context: common.Context): Record<FollowFilterCategory, boolean> {
    const prefs = preferences.getPreferencesSync(context, { name: PREFERENCES_FILE });
    const result: Record<FollowFilterCategory, boolean> = { ...DEFAULTS };
    (Object.keys(KEY_MAP) as FollowFilterCategory[]).forEach((cat: FollowFilterCategory) => {
      const stored = prefs.getSync(KEY_MAP[cat], DEFAULTS[cat]) as boolean;
      result[cat] = stored;
      AppStorage.setOrCreate<boolean>(KEY_MAP[cat], stored);
    });
    AppStorage.setOrCreate<boolean>(KEY_HIDE_UNFOLLOWED, this.getHideUnfollowed(context));
    return result;
  }

  static get(context: common.Context, cat: FollowFilterCategory): boolean {
    const prefs = preferences.getPreferencesSync(context, { name: PREFERENCES_FILE });
    return prefs.getSync(KEY_MAP[cat], DEFAULTS[cat]) as boolean;
  }

  static set(context: common.Context, cat: FollowFilterCategory, value: boolean): void {
    const prefs = preferences.getPreferencesSync(context, { name: PREFERENCES_FILE });
    prefs.putSync(KEY_MAP[cat], value);
    prefs.flushSync();
    AppStorage.setOrCreate<boolean>(KEY_MAP[cat], value);
  }

  static getHideUnfollowed(context: common.Context): boolean {
    const prefs = preferences.getPreferencesSync(context, { name: PREFERENCES_FILE });
    return prefs.getSync(KEY_HIDE_UNFOLLOWED, DEFAULT_HIDE_UNFOLLOWED) as boolean;
  }

  static setHideUnfollowed(context: common.Context, value: boolean): void {
    const prefs = preferences.getPreferencesSync(context, { name: PREFERENCES_FILE });
    prefs.putSync(KEY_HIDE_UNFOLLOWED, value);
    prefs.flushSync();
    AppStorage.setOrCreate<boolean>(KEY_HIDE_UNFOLLOWED, value);
  }
}
