import common from '@ohos.app.ability.common';
import { HomeFeedItem } from '../models/ZhihuModels';
import { BlocklistRepository, BlockedKeyword } from './BlocklistRepository';
import { FilterSettingsRepository, FILTER_KEYS } from './FilterSettingsRepository';

interface ViewRecord {
  count: number;
  lastSeen: number;
}

interface QualityThresholds {
  vote: number;
  videoFan: number;
  videoVote: number;
  articleFan: number;
  articleVote: number;
  questionAnswer: number;
  questionFollower: number;
}

// 对齐安卓 FeedContentFilterPipeline 的精确匹配逻辑（NLP 语义匹配推迟到 v2）。
// 质量过滤规则对齐安卓 Feed.kt filterReason；智能过滤对齐 ForegroundReadFilterPipeline。
export class FeedFilterService {
  static matchKeyword(text: string, kw: BlockedKeyword): boolean {
    if (text.length === 0) {
      return false;
    }
    try {
      if (kw.isRegex) {
        const re = kw.caseSensitive ? new RegExp(kw.text) : new RegExp(kw.text, 'i');
        return re.test(text);
      }
      return kw.caseSensitive
        ? text.includes(kw.text)
        : text.toLowerCase().includes(kw.text.toLowerCase());
    } catch (e) {
      return false;
    }
  }

  // 质量过滤阈值：未关注 / 已关注 各自独立一套（默认 0 = 不触发过滤）
  private static qualityThresholdsFor(context: common.Context, followed: boolean): QualityThresholds {
    const k = followed
      ? {
          vote: FILTER_KEYS.qualityVoteFollowed,
          videoFan: FILTER_KEYS.qualityVideoFanFollowed,
          videoVote: FILTER_KEYS.qualityVideoVoteFollowed,
          articleFan: FILTER_KEYS.qualityArticleFanFollowed,
          articleVote: FILTER_KEYS.qualityArticleVoteFollowed,
          questionAnswer: FILTER_KEYS.qualityQuestionAnswerFollowed,
          questionFollower: FILTER_KEYS.qualityQuestionFollowerFollowed,
        }
      : {
          vote: FILTER_KEYS.qualityVoteUnfollowed,
          videoFan: FILTER_KEYS.qualityVideoFanUnfollowed,
          videoVote: FILTER_KEYS.qualityVideoVoteUnfollowed,
          articleFan: FILTER_KEYS.qualityArticleFanUnfollowed,
          articleVote: FILTER_KEYS.qualityArticleVoteUnfollowed,
          questionAnswer: FILTER_KEYS.qualityQuestionAnswerUnfollowed,
          questionFollower: FILTER_KEYS.qualityQuestionFollowerUnfollowed,
        };
    return {
      vote: FilterSettingsRepository.getInt(context, k.vote, 0),
      videoFan: FilterSettingsRepository.getInt(context, k.videoFan, 0),
      videoVote: FilterSettingsRepository.getInt(context, k.videoVote, 0),
      articleFan: FilterSettingsRepository.getInt(context, k.articleFan, 0),
      articleVote: FilterSettingsRepository.getInt(context, k.articleVote, 0),
      questionAnswer: FilterSettingsRepository.getInt(context, k.questionAnswer, 0),
      questionFollower: FilterSettingsRepository.getInt(context, k.questionFollower, 0)
    };
  }

  // 质量过滤：返回 true 表示应被过滤（低质）。问题类型无关注豁免（由调用方控制 exempt）。
  private static qualityBlocked(item: HomeFeedItem, th: QualityThresholds): boolean {
    switch (item.type) {
      case 'answer':
        // 安卓：voteupCount < 10 && !isFollowing
        return (item.voteCount ?? 0) < th.vote;
      case 'article':
        // 安卓：(followers < 50 || vote < 20) && !isFollowing
        return (item.authorFollowerCount ?? 0) < th.articleFan || (item.voteCount ?? 0) < th.articleVote;
      case 'zvideo':
        // 安卓：followers < 50 && vote < 20 && !isFollowing
        return (item.authorFollowerCount ?? 0) < th.videoFan && (item.voteCount ?? 0) < th.videoVote;
      case 'question':
        // 安卓：answerCount < 5 && followerCount < 50（无关注豁免）
        return (item.questionFollowerCount ?? 0) < th.questionFollower && (item.commentCount ?? 0) < th.questionAnswer;
      case 'pin':
        // 安卓：想法 return null（不过滤）
        return false;
      default:
        return false;
    }
  }

  // 质量过滤「屏蔽规则」模式下的原因文案（对齐安卓 Feed.kt filterReason）。
  private static qualityReason(item: HomeFeedItem, th: QualityThresholds, followed: boolean): string {
    const who = followed ? '，已关注作者' : '，未关注作者';
    switch (item.type) {
      case 'answer':
        return `规则：回答；赞数 < ${th.vote}${who}`;
      case 'article':
        return `规则：文章；作者粉丝数 < ${th.articleFan} 或 文章赞数 < ${th.articleVote}${who}`;
      case 'zvideo':
        return `规则：所有视频${who}`;
      case 'question':
        return `规则：问题；回答数 < ${th.questionAnswer}，关注数 < ${th.questionFollower}${who}`;
      default:
        return `规则：低质内容${who}`;
    }
  }

  // 低质推广检测：对齐安卓 isLowQualityForegroundFeed（details 含「小时前/分钟前/浏览」）。
  // 鸿蒙端 details 不含 actionText，故同时扫 details 与 actionText。
  private static isLowQuality(item: HomeFeedItem): boolean {
    const hay = `${item.details ?? ''} ${item.actionText ?? ''}`;
    return hay.includes('小时前') || hay.includes('分钟前') || hay.includes('浏览');
  }

  private static loadViewRecords(context: common.Context): Record<string, ViewRecord> {
    try {
      const raw = FilterSettingsRepository.getStr(context, FILTER_KEYS.smartViewRecords, '');
      if (raw.length === 0) {
        return {};
      }
      const parsed = JSON.parse(raw) as Record<string, ViewRecord>;
      const out: Record<string, ViewRecord> = {};
      for (const k of Object.keys(parsed)) {
        const v = parsed[k];
        if (v && typeof v.count === 'number' && typeof v.lastSeen === 'number') {
          out[k] = v;
        }
      }
      return out;
    } catch (_e) {
      return {};
    }
  }

  private static saveViewRecords(context: common.Context, records: Record<string, ViewRecord>): void {
    try {
      FilterSettingsRepository.setStr(context, FILTER_KEYS.smartViewRecords, JSON.stringify(records));
    } catch (_e) {
      // 忽略持久化失败
    }
  }

  // 推荐页精确过滤（受「启用关键词/用户/主题屏蔽」开关控制）。仅推荐页调用，关注页不受影响。
  // 管道顺序（鸿蒙端定）：精确匹配（关键词/用户/话题/广告/学堂/微信/盐选）
  //   → 质量过滤（未关注 / 已关注 各自独立模式与阈值）
  //   → 智能过滤（低质检测 + 浏览记录阈值，未关注 / 已关注 各自独立模式）
  // recordCount=true 时（首屏 / 加载更多）对展示中的内容自增统一计数；
  // 该计数同时驱动「推荐次数角标」与「展示 N 次后屏蔽」，并随浏览记录过期而清零。
  static filterHomeFeed(context: common.Context, items: HomeFeedItem[], recordCount: boolean = false): HomeFeedItem[] {
    const keywordOn = FilterSettingsRepository.getBool(context, FILTER_KEYS.keywordBlock, true);
    const userOn = FilterSettingsRepository.getBool(context, FILTER_KEYS.userBlock, true);
    const topicOn = FilterSettingsRepository.getBool(context, FILTER_KEYS.topicBlock, true);
    const topicThreshold = FilterSettingsRepository.getInt(context, FILTER_KEYS.topicThreshold, 1);
    const blockEdu = FilterSettingsRepository.getBool(context, FILTER_KEYS.blockEdu, true);
    const blockWechat = FilterSettingsRepository.getBool(context, FILTER_KEYS.blockWechat, true);
    const blockYanxuan = FilterSettingsRepository.getBool(context, FILTER_KEYS.blockYanxuan, true);
    const blockAd = FilterSettingsRepository.getBool(context, FILTER_KEYS.blockAd, true);

    // 浏览记录（带过期清理，未关注 / 已关注 两套模式共用同一份 smartViewRecords）
    let records: Record<string, ViewRecord> = {};
    let now = 0;
    let dirty = false;
    {
      const expireDays = FilterSettingsRepository.getInt(context, FILTER_KEYS.smartExpireDays, 7);
      const maxRecords = FilterSettingsRepository.getInt(context, FILTER_KEYS.smartMaxRecords, 10000);
      const expireMs = expireDays * 24 * 60 * 60 * 1000;
      now = Date.now();
      const loaded = this.loadViewRecords(context);
      let entries = Object.entries(loaded).filter(([, v]) => (now - v.lastSeen) < expireMs);
      if (entries.length > maxRecords) {
        // 超过最大记录数 → 全量清理（对齐安卓上限策略）
        entries = [];
      }
      for (const [k, v] of entries) {
        records[k] = v;
      }
      if (Object.keys(loaded).length !== Object.keys(records).length) {
        dirty = true; // 有过期项被清理，稍后落盘
      }
    }

    const keywords = keywordOn ? BlocklistRepository.getKeywords(context) : [];
    const users = userOn ? BlocklistRepository.getUsers(context) : [];
    const qaList = userOn ? BlocklistRepository.getQuestionAuthors(context) : [];
    const topics = topicOn ? BlocklistRepository.getTopics(context) : [];

    const userIds = new Set<string>(users.map((u) => u.id).filter((id) => id.length > 0));
    const userTokens = new Set<string>(users.map((u) => u.urlToken).filter((t) => t.length > 0));
    const userNames = new Set<string>(users.map((u) => u.name).filter((n) => n.length > 0));
    const qaIds = new Set<string>(qaList.map((q) => q.id).filter((id) => id.length > 0));
    const topicIds = new Set<string>(topics.map((t) => t.id).filter((id) => id.length > 0));

    const result = items.filter((item: HomeFeedItem) => {
      const authorId: string = item.authorId ?? '';
      const authorToken: string = item.authorUrlToken ?? '';
      const authorName: string = item.authorName ?? '';
      const qaId: string = item.questionAuthorId ?? '';
      const itemTopics = item.topics;
      // 用户 / 提问者屏蔽（对齐安卓 enableUserBlocking 同时管 user 与 questionAuthor）
      if (userOn) {
        if (authorId.length > 0 && userIds.has(authorId)) {
          return false;
        }
        if (authorToken.length > 0 && userTokens.has(authorToken)) {
          return false;
        }
        if (authorId.length === 0 && authorToken.length === 0 && authorName.length > 0 && userNames.has(authorName)) {
          return false;
        }
        if (qaId.length > 0 && qaIds.has(qaId)) {
          return false;
        }
      }
      // 关键词屏蔽（标题 + 摘要）
      if (keywordOn && keywords.length > 0) {
        const hay = `${item.title} ${item.summary}`;
        if (keywords.some((kw) => this.matchKeyword(hay, kw))) {
          return false;
        }
      }
      // 话题屏蔽（命中数 >= 阈值）
      if (topicOn && topicIds.size > 0 && itemTopics && itemTopics.length > 0) {
        const hit = itemTopics.filter((t) => topicIds.has(t.id)).length;
        if (hit >= topicThreshold && hit > 0) {
          return false;
        }
      }
      // 内容屏蔽（对齐安卓 getFeedAdBlockReason）：学堂 / 微信外链 / 盐选付费
      const contentHay = `${item.targetUrl} ${item.summary}`;
      if (blockEdu && (contentHay.includes('d.zhihu.com') || contentHay.includes('data-edu-card-id'))) {
        return false;
      }
      if (blockWechat && contentHay.includes('mp.weixin.qq.com')) {
        return false;
      }
      if (blockYanxuan && item.paidInfo != null) {
        return false;
      }
      // 知乎广告平台内容（对齐安卓 getLinkBasedAdReason：匹配 xg.zhihu.com）
      if (blockAd && contentHay.includes('xg.zhihu.com')) {
        return false;
      }

      const followed = item.authorFollowing === true;
      const id: string = item.id ?? '';

      // 质量过滤（未关注 / 已关注 各自独立）：仅 off 之外的模式生效，
      // hide 整条移除，rules 打标占位卡（仍可点开，对齐安卓 RULES 占位卡）
      const qMode = FilterSettingsRepository.getQualityMode(context, followed);
      if (qMode !== 'off') {
        const qTh = this.qualityThresholdsFor(context, followed);
        if (this.qualityBlocked(item, qTh)) {
          if (qMode === 'hide') {
            return false;
          }
          item.blockReason = this.qualityReason(item, qTh, followed);
        }
      }

      // 推荐次数统一计数 + 智能过滤（未关注 / 已关注 各自独立）：
      // 计数同时驱动「推荐次数角标」与「展示 N 次后屏蔽」，随浏览记录过期清零。
      const seen = id.length > 0 ? (records[id]?.count ?? 0) : 0;
      const sMode = FilterSettingsRepository.getSmartMode(context, followed);
      let blocked = false;
      let blockReason = '';
      if (sMode !== 'off') {
        const sTh = followed
          ? FilterSettingsRepository.getInt(context, FILTER_KEYS.smartViewThresholdFollowed, 2)
          : FilterSettingsRepository.getInt(context, FILTER_KEYS.smartViewThresholdUnfollowed, 2);
        const sLow = followed
          ? FilterSettingsRepository.getBool(context, FILTER_KEYS.smartLowQualityFollowed, true)
          : FilterSettingsRepository.getBool(context, FILTER_KEYS.smartLowQualityUnfollowed, true);
        if (sLow && this.isLowQuality(item)) {
          blocked = true;
          blockReason = '规则：低质推广内容';
        } else if (seen >= sTh) {
          blocked = true;
          blockReason = `规则：已展示 ${seen} 次，超过阈值 ${sTh}`;
        }
      }

      if (blocked) {
        if (sMode === 'hide') {
          return false;
        }
        item.blockReason = blockReason + (followed ? '，已关注作者' : '，未关注作者');
        item.recommendCount = seen;
      } else if (recordCount && id.length > 0) {
        records[id] = { count: seen + 1, lastSeen: now };
        dirty = true;
        item.recommendCount = seen + 1;
      } else {
        item.recommendCount = seen;
      }

      return true;
    });

    if (dirty) {
      this.saveViewRecords(context, records);
    }
    return result;
  }
}
