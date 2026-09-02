import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';

const FILTER_PREFERENCES_FILE: string = 'zhihu_filter';

export type RecommendAlgo = 'web' | 'android' | 'mixed';

// 过滤模式：不屏蔽(off) / 屏蔽规则(rules，渲染「已屏蔽」占位卡) / 隐藏(hide，整条移除)
export type FilterMode = 'off' | 'rules' | 'hide';

// 屏蔽 / 过滤设置偏好键（与安卓 zhihu++ 的「推荐系统与内容过滤」对齐）
export const FILTER_KEYS = {
  recommendAlgo: 'recommend_algo',
  recommendLogin: 'recommend_login',
  autoRefresh: 'auto_refresh_on_launch',
  qualityFilter: 'quality_filter',
  smartFilter: 'smart_filter',
  blockEdu: 'block_zhihu_edu',
  blockWechat: 'block_wechat',
  blockYanxuan: 'block_yanxuan',
  keywordBlock: 'keyword_block',
  userBlock: 'user_block',
  topicBlock: 'topic_block',
  topicThreshold: 'topic_threshold',
  blockAd: 'block_ad',
  // 质量过滤模式（未关注 / 已关注 各自独立；默认 off）
  qualityModeUnfollowed: 'quality_filter_mode_unfollowed',
  qualityModeFollowed: 'quality_filter_mode_followed',
  // 质量过滤阈值（未关注 / 已关注 各自独立；默认 0）
  qualityVoteUnfollowed: 'quality_vote_unfollowed',
  qualityVideoFanUnfollowed: 'quality_video_fan_unfollowed',
  qualityVideoVoteUnfollowed: 'quality_video_vote_unfollowed',
  qualityArticleFanUnfollowed: 'quality_article_fan_unfollowed',
  qualityArticleVoteUnfollowed: 'quality_article_vote_unfollowed',
  qualityQuestionAnswerUnfollowed: 'quality_question_answer_unfollowed',
  qualityQuestionFollowerUnfollowed: 'quality_question_follower_unfollowed',
  qualityVoteFollowed: 'quality_vote_followed',
  qualityVideoFanFollowed: 'quality_video_fan_followed',
  qualityVideoVoteFollowed: 'quality_video_vote_followed',
  qualityArticleFanFollowed: 'quality_article_fan_followed',
  qualityArticleVoteFollowed: 'quality_article_vote_followed',
  qualityQuestionAnswerFollowed: 'quality_question_answer_followed',
  qualityQuestionFollowerFollowed: 'quality_question_follower_followed',
  // 智能过滤模式（未关注 / 已关注 各自独立；默认 off）
  smartModeUnfollowed: 'smart_filter_mode_unfollowed',
  smartModeFollowed: 'smart_filter_mode_followed',
  smartViewThresholdUnfollowed: 'smart_view_threshold_unfollowed',
  smartViewThresholdFollowed: 'smart_view_threshold_followed',
  smartLowQualityUnfollowed: 'smart_low_quality_unfollowed',
  smartLowQualityFollowed: 'smart_low_quality_followed',
  // 智能过滤全局记录管理（两套模式共用同一份带过期的浏览记录）
  smartExpireDays: 'smart_expire_days',
  smartMaxRecords: 'smart_max_records',
  smartViewRecords: 'smart_view_records',
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

  // 质量过滤模式（未关注 / 已关注 各自独立一套）：不屏蔽(off) / 屏蔽规则(rules) / 隐藏(hide)。
  // 默认 off（关闭则该节不生效）。
  static getQualityMode(context: common.Context, followed: boolean): FilterMode {
    const key = followed ? FILTER_KEYS.qualityModeFollowed : FILTER_KEYS.qualityModeUnfollowed;
    const raw = this.getStr(context, key, '');
    if (raw === 'off' || raw === 'rules' || raw === 'hide') {
      return raw;
    }
    return 'off';
  }

  static setQualityMode(context: common.Context, followed: boolean, mode: FilterMode): void {
    const key = followed ? FILTER_KEYS.qualityModeFollowed : FILTER_KEYS.qualityModeUnfollowed;
    this.setStr(context, key, mode);
  }

  // 占位卡「调整质量屏蔽」一键隐藏：两套作者全部置为 hide
  static setQualityFilterModeAll(context: common.Context, mode: FilterMode): void {
    this.setQualityMode(context, false, mode);
    this.setQualityMode(context, true, mode);
  }

  // 智能过滤模式（未关注 / 已关注 各自独立一套）：不屏蔽(off) / 屏蔽规则(rules) / 隐藏(hide)。
  static getSmartMode(context: common.Context, followed: boolean): FilterMode {
    const key = followed ? FILTER_KEYS.smartModeFollowed : FILTER_KEYS.smartModeUnfollowed;
    const raw = this.getStr(context, key, '');
    if (raw === 'off' || raw === 'rules' || raw === 'hide') {
      return raw;
    }
    return 'off';
  }

  static setSmartMode(context: common.Context, followed: boolean, mode: FilterMode): void {
    const key = followed ? FILTER_KEYS.smartModeFollowed : FILTER_KEYS.smartModeUnfollowed;
    this.setStr(context, key, mode);
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
