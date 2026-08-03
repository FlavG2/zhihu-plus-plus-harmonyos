import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';

const FILTER_PREFERENCES_FILE: string = 'zhihu_filter';

export type RecommendAlgo = 'web' | 'android' | 'mixed';

// 屏蔽 / 过滤设置偏好键（与安卓 zhihu++ 的「推荐系统与内容过滤」对齐）
export const FILTER_KEYS = {
  recommendAlgo: 'recommend_algo',
  recommendLogin: 'recommend_login',
  autoRefresh: 'auto_refresh_on_launch',
  qualityFilter: 'quality_filter',
  smartFilter: 'smart_filter',
  filterFollowed: 'filter_followed',
  blockEdu: 'block_zhihu_edu',
  blockWechat: 'block_wechat',
  blockYanxuan: 'block_yanxuan',
  keywordBlock: 'keyword_block',
  userBlock: 'user_block',
  topicBlock: 'topic_block',
  topicThreshold: 'topic_threshold',
  blockAd: 'block_ad',
  // 质量过滤阈值（对齐安卓 Feed.kt filterReason）
  qualityVote: 'quality_vote',
  qualityVideoFan: 'quality_video_fan',
  qualityVideoVote: 'quality_video_vote',
  qualityArticleFan: 'quality_article_fan',
  qualityArticleVote: 'quality_article_vote',
  qualityQuestionAnswer: 'quality_question_answer',
  qualityQuestionFollower: 'quality_question_follower',
  // 智能过滤
  smartViewThreshold: 'smart_view_threshold',
  smartLowQuality: 'smart_low_quality',
  smartExpireDays: 'smart_expire_days',
  smartMaxRecords: 'smart_max_records',
  smartViewRecords: 'smart_view_records',
  recommendRecords: 'recommend_records',
  // 推荐次数角标总开关（标题末尾显示「第 N 次」标记）
  showRecommendBadge: 'show_recommend_badge',
} as const;

export class FilterSettingsRepository {
  private static preferences(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: FILTER_PREFERENCES_FILE });
  }

  static getBool(context: common.Context, key: string, def: boolean): boolean {
    const store = this.preferences(context);
    return store.getSync(key, def) as boolean;
  }

  static setBool(context: common.Context, key: string, value: boolean): void {
    const store = this.preferences(context);
    store.putSync(key, value);
    store.flushSync();
  }

  static getStr(context: common.Context, key: string, def: string): string {
    const store = this.preferences(context);
    return store.getSync(key, def) as string;
  }

  static setStr(context: common.Context, key: string, value: string): void {
    const store = this.preferences(context);
    store.putSync(key, value);
    store.flushSync();
  }

  static getInt(context: common.Context, key: string, def: number): number {
    const store = this.preferences(context);
    return store.getSync(key, def) as number;
  }

  static setInt(context: common.Context, key: string, value: number): void {
    const store = this.preferences(context);
    store.putSync(key, value);
    store.flushSync();
  }

  // 预加载（确保 preferences 实例已创建）
  static load(context: common.Context): void {
    this.preferences(context);
  }
}
