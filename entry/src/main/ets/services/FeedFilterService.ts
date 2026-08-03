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

  private static qualityThresholds(context: common.Context): QualityThresholds {
    return {
      vote: FilterSettingsRepository.getInt(context, FILTER_KEYS.qualityVote, 10),
      videoFan: FilterSettingsRepository.getInt(context, FILTER_KEYS.qualityVideoFan, 50),
      videoVote: FilterSettingsRepository.getInt(context, FILTER_KEYS.qualityVideoVote, 20),
      articleFan: FilterSettingsRepository.getInt(context, FILTER_KEYS.qualityArticleFan, 50),
      articleVote: FilterSettingsRepository.getInt(context, FILTER_KEYS.qualityArticleVote, 20),
      questionAnswer: FilterSettingsRepository.getInt(context, FILTER_KEYS.qualityQuestionAnswer, 5),
      questionFollower: FilterSettingsRepository.getInt(context, FILTER_KEYS.qualityQuestionFollower, 50)
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

  // 推荐次数记录（独立于过滤开关）：key=item.id，value=被推荐出现次数。
  private static loadRecommendRecords(context: common.Context): Record<string, number> {
    try {
      const raw = FilterSettingsRepository.getStr(context, FILTER_KEYS.recommendRecords, '');
      if (raw.length === 0) {
        return {};
      }
      const parsed = JSON.parse(raw) as Record<string, number>;
      const out: Record<string, number> = {};
      for (const k of Object.keys(parsed)) {
        const v = parsed[k];
        if (typeof v === 'number') {
          out[k] = v;
        }
      }
      return out;
    } catch (_e) {
      return {};
    }
  }

  private static saveRecommendRecords(context: common.Context, records: Record<string, number>): void {
    try {
      FilterSettingsRepository.setStr(context, FILTER_KEYS.recommendRecords, JSON.stringify(records));
    } catch (_e) {
      // 忽略持久化失败
    }
  }

  // 推荐次数统计：每次「新一批内容加载」时调用（不受任何过滤开关影响）。
  // 对每条 item 自增并赋给 item.recommendCount，持久化到 recommendRecords。
  static recordRecommendCounts(context: common.Context, items: HomeFeedItem[]): void {
    const records = this.loadRecommendRecords(context);
    let dirty = false;
    for (const item of items) {
      if (!item.id) {
        continue;
      }
      const next = (records[item.id] ?? 0) + 1;
      records[item.id] = next;
      item.recommendCount = next;
      dirty = true;
    }
    if (dirty) {
      this.saveRecommendRecords(context, records);
    }
  }

  // 推荐页精确过滤（受「启用关键词/用户/主题屏蔽」开关控制）。仅推荐页调用，关注页不受影响。
  // 管道顺序（鸿蒙端定）：精确匹配（关键词/用户/话题/广告/学堂/微信/盐选）
  //   → 质量过滤（含「已关注作者豁免」）
  //   → 智能过滤（低质检测 + 浏览记录阈值，保留的 item 记录浏览）
  static filterHomeFeed(context: common.Context, items: HomeFeedItem[]): HomeFeedItem[] {
    const keywordOn = FilterSettingsRepository.getBool(context, FILTER_KEYS.keywordBlock, true);
    const userOn = FilterSettingsRepository.getBool(context, FILTER_KEYS.userBlock, true);
    const topicOn = FilterSettingsRepository.getBool(context, FILTER_KEYS.topicBlock, true);
    const topicThreshold = FilterSettingsRepository.getInt(context, FILTER_KEYS.topicThreshold, 1);
    const blockEdu = FilterSettingsRepository.getBool(context, FILTER_KEYS.blockEdu, true);
    const blockWechat = FilterSettingsRepository.getBool(context, FILTER_KEYS.blockWechat, true);
    const blockYanxuan = FilterSettingsRepository.getBool(context, FILTER_KEYS.blockYanxuan, true);
    const blockAd = FilterSettingsRepository.getBool(context, FILTER_KEYS.blockAd, true);

    // 质量 / 智能 / 过滤已关注 总开关
    const qualityOn = FilterSettingsRepository.getBool(context, FILTER_KEYS.qualityFilter, true);
    const smartOn = FilterSettingsRepository.getBool(context, FILTER_KEYS.smartFilter, true);
    const filterFollowedOn = FilterSettingsRepository.getBool(context, FILTER_KEYS.filterFollowed, false);
    const th = this.qualityThresholds(context);

    // 智能过滤：浏览记录（仅在 smartOn 时加载/保存）
    let records: Record<string, ViewRecord> = {};
    let now = 0;
    let smartViewThreshold = 2;
    let smartLowQuality = true;
    let dirty = false;
    if (smartOn) {
      records = this.loadViewRecords(context);
      now = Date.now();
      const expireDays = FilterSettingsRepository.getInt(context, FILTER_KEYS.smartExpireDays, 7);
      const maxRecords = FilterSettingsRepository.getInt(context, FILTER_KEYS.smartMaxRecords, 10000);
      const expireMs = expireDays * 24 * 60 * 60 * 1000;
      let entries = Object.entries(records).filter(([, v]) => (now - v.lastSeen) < expireMs);
      if (entries.length > maxRecords) {
        // 超过最大记录数 → 全量清理（对齐安卓上限策略）
        entries = [];
      }
      records = {};
      for (const [k, v] of entries) {
        records[k] = v;
      }
      smartViewThreshold = FilterSettingsRepository.getInt(context, FILTER_KEYS.smartViewThreshold, 2);
      smartLowQuality = FilterSettingsRepository.getBool(context, FILTER_KEYS.smartLowQuality, true);
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

      // 已关注且「过滤已关注」关闭 → 豁免（问题类型无豁免，安卓问题质量过滤无视 isFollowing）
      const followed = item.authorFollowing === true;
      const exempt = !filterFollowedOn && followed && item.type !== 'question';

      // 质量过滤（含关注豁免）
      if (qualityOn && !exempt && this.qualityBlocked(item, th)) {
        return false;
      }

      // 智能过滤（低质检测 + 浏览记录阈值），保留的 item 记录浏览
      if (smartOn && !exempt) {
        if (smartLowQuality && this.isLowQuality(item)) {
          return false;
        }
        const seen = records[item.id]?.count ?? 0;
        if (seen >= smartViewThreshold) {
          return false;
        }
        records[item.id] = { count: seen + 1, lastSeen: now };
        dirty = true;
      }

      return true;
    });

    if (smartOn && dirty) {
      this.saveViewRecords(context, records);
    }
    return result;
  }
}
