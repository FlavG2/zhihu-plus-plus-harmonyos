import common from '@ohos.app.ability.common';
import { HomeFeedItem, ZhihuCollection } from '../models/ZhihuModels';
import { ZhihuCommentableTarget, serializeZhihuContentTarget } from '../models/ZhihuContentModels';
import { ZhihuApi } from './ZhihuApi';

// 对齐安卓 PeopleScreen.kt / DataHolder.People / BadgeV2 / SocialMedia
// 接口全部走签名请求（signed: true）。

type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];

interface JsonObject {
  [key: string]: JsonValue;
}

export interface OfficialBadgeDetail {
  readonly title: string;
  readonly description: string;
  readonly iconUrl: string;
  readonly type: string;
}

export interface GithubSocial {
  readonly title: string;
  readonly starCount: string;
  readonly profileUrl: string;
  readonly iconUrl: string;
}

export interface ZhihuPeopleProfile {
  readonly id: string;
  readonly name: string;
  readonly headline: string;
  readonly avatarUrl: string;
  readonly urlToken: string;
  readonly followerCount: number;
  readonly followingCount: number;
  readonly answerCount: number;
  readonly articleCount: number;
  readonly isFollowing: boolean;
  readonly isBlocking: boolean;
  readonly officialBadgeTitle: string;
  readonly officialBadgeIcon: string;
  readonly officialBadgeDetails: OfficialBadgeDetail[];
  githubSocial?: GithubSocial;
}

export interface ZhihuPeopleSummary {
  readonly id: string;
  readonly name: string;
  readonly headline: string;
  readonly avatarUrl: string;
  readonly urlToken: string;
  readonly answerCount: number;
  readonly articleCount: number;
  readonly followerCount: number;
  readonly officialBadgeTitle: string;
}

export interface ZhihuColumnSummary {
  readonly id: string;
  readonly title: string;
  readonly description: string;
  readonly articlesCount: number;
  readonly followerCount: number;
  readonly url: string;
}

export interface ZhihuTopicSummary {
  readonly id: string;
  readonly name: string;
  readonly avatarUrl: string;
}

export interface ZhihuFollowedQuestionSummary {
  readonly id: string;
  readonly title: string;
}

export interface ZhihuPinTopic {
  readonly id: string;
  readonly name: string;
  readonly avatarUrl: string;
}

export interface ZhihuPinAuthor {
  readonly id: string;
  readonly name: string;
  readonly headline: string;
  readonly avatarUrl: string;
  readonly urlToken: string;
  readonly officialBadgeTitle: string;
}

export interface ZhihuPin {
  readonly id: string;
  readonly contentHtml: string;
  readonly excerptTitle: string;
  readonly liked: boolean;
  readonly likeCount: number;
  readonly commentCount: number;
  readonly createdTime: number;
  readonly updatedTime: number;
  readonly author: ZhihuPinAuthor;
  readonly topics: ZhihuPinTopic[];
}

export interface PeoplePage<T> {
  readonly items: T[];
  readonly nextUrl: string;
  readonly isEnd: boolean;
}

const PROFILE_INCLUDE =
  'allow_message,is_followed,is_following,is_org,is_blocking,badge_v2,url_token,answer_count,follower_count,following_count,articles_count,question_count,pins_count';

// 收藏夹列表默认不返回 answer_count 等字段，必须显式 include
const COLLECTION_INCLUDE = 'data[*].updated_time,answer_count,follower_count,creator';
// 专栏列表的 articles_count / followers 默认不返回，需要 include（支持 column-contributions 与 following-columns 两种嵌套）
const COLUMN_INCLUDE = 'data[*].articles_count,data[*].followers,data[*].column.articles_count,data[*].column.followers';
// 以下 v4 接口默认不返回 voteup_count / comment_count / like_count 等统计字段，必须显式 include（对齐安卓 PeopleScreen.kt）
// 注意：members/{token}/answers 等端点对精简 include 会丢弃 voteup_count，必须用安卓线上完整字段串才能拿到赞同数
const ANSWER_INCLUDE = 'data[*].is_normal,admin_closed_comment,reward_info,is_collapsed,annotation_action,annotation_detail,collapse_reason,collapsed_by,suggest_edit,comment_count,thanks_count,can_comment,content,editable_content,attachment,voteup_count,reshipment_settings,comment_permission,created_time,updated_time,review_info,excerpt,paid_info,reaction_instruction,is_labeled,label_info,relationship.is_authorized,voting,is_author,is_thanked,is_nothelp,author.badge_v2';
const ARTICLE_INCLUDE = 'data[*].comment_count,suggest_edit,is_normal,thumbnail_extra_info,thumbnail,can_comment,comment_permission,admin_closed_comment,content,voteup_count,created,updated,upvoted_followees,voting,review_info,reaction_instruction,is_labeled,label_info,author.badge_v2;data[*].vessay_info;data[*].author.badge[?(type=best_answerer)].topics;';
const ACTIVITY_INCLUDE = 'data[*].comment_count,voteup_count,like_count,answer_count,follower_count,excerpt,excerpt_title,content,author.badge_v2';
const QUESTION_INCLUDE = 'data[*].created,answer_count,follower_count,author,visit_count,comment_count,detail,relationship,topics,voteup_count';
const PIN_INCLUDE = 'data[*].like_count,comment_count,created,updated,excerpt_title,content';
const FOLLOW_INCLUDE = 'data[*].answer_count,articles_count,gender,follower_count,is_followed,is_following,badge_v2,badge[?(type=best_answerer)].topics';

export class PeopleService {
  // ---- 通用 JSON 取值助手 ----
  private static str(value: JsonValue | undefined): string {
    return typeof value === 'string' ? value : '';
  }

  private static num(value: JsonValue | undefined): number {
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsed = Number(value);
      return Number.isFinite(parsed) ? parsed : 0;
    }
    return 0;
  }

  private static id(value: JsonValue | undefined): string {
    if (typeof value === 'number') {
      return `${value}`;
    }
    if (typeof value === 'string') {
      return value;
    }
    return '';
  }

  private static obj(value: JsonValue | undefined): JsonObject {
    return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as JsonObject : {};
  }

  private static arr(value: JsonValue | undefined): JsonValue[] {
    return Array.isArray(value) ? value : [];
  }

  // 剥掉知乎接口返回的富文本标签（想法 excerpt_title/content 含 <br>/<a class="hash_tag">/<img> 等），取纯文本
  // public → 供 People.ets FeedCard 渲染层保底调用
  static stripHtml(raw: string): string {
    if (raw.length === 0) return raw;
    return raw
      // HTML 标签（含自闭合 <img/> <br/>）
      .replace(/<[^>]+>/g, '')
      // 常见 HTML 实体
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#(\d+);/g, (_m: string, code: string): string => {
        const cp = parseInt(code, 10);
        return (cp >= 32 && cp <= 126) ? String.fromCharCode(cp) : '';
      })
      // 压缩连续空白
      .replace(/[ \t]+/g, ' ')
      .replace(/\n{2,}/g, '\n')
      .trim();
  }

  private static normalizeNextUrl(raw: string): string {
    if (raw.length === 0) {
      return '';
    }
    if (raw.startsWith('http')) {
      return raw;
    }
    return `https://www.zhihu.com${raw.startsWith('/') ? '' : '/'}${raw}`;
  }

  private static parsePaging(payload: JsonObject): { nextUrl: string; isEnd: boolean } {
    const paging = this.obj(payload.paging);
    return {
      nextUrl: this.normalizeNextUrl(this.str(paging.next)),
      isEnd: paging.is_end === true
    };
  }

  private static officialBadgeTitleFromDetails(details: OfficialBadgeDetail[]): string {
    const primary =
      details.find((d: OfficialBadgeDetail) => d.type !== 'identity' && d.iconUrl.length > 0) ??
      details.find((d: OfficialBadgeDetail) => d.iconUrl.length > 0);
    return primary !== undefined ? primary.title : '';
  }

  private static parseBadgeV2(badgeV2Raw: JsonValue | undefined): {
    title: string;
    icon: string;
    details: OfficialBadgeDetail[];
  } {
    const badgeV2 = this.obj(badgeV2Raw);
    if (Object.keys(badgeV2).length === 0) {
      return { title: '', icon: '', details: [] };
    }
    const asDetail = (raw: JsonValue): OfficialBadgeDetail | undefined => {
      const b = this.obj(raw);
      const badgeStatus = this.str(b.badge_status);
      if (badgeStatus.length > 0 && badgeStatus !== 'passed') {
        return undefined;
      }
      const title = this.str(b.title);
      if (title.length === 0) {
        return undefined;
      }
      const description = this.str(b.description).length > 0 ? this.str(b.description) : title;
      return {
        title,
        description,
        iconUrl: this.str(b.icon),
        type: this.str(b.type)
      };
    };
    const detailBadges = this.arr(badgeV2.detail_badges).map(asDetail).filter((d): d is OfficialBadgeDetail => d !== undefined);
    const details =
      detailBadges.length > 0
        ? detailBadges
        : this.arr(badgeV2.merged_badges).map(asDetail).filter((d): d is OfficialBadgeDetail => d !== undefined);
    const title = this.officialBadgeTitleFromDetails(details);
    const primary =
      details.find((d: OfficialBadgeDetail) => d.type !== 'identity' && d.iconUrl.length > 0) ??
      details.find((d: OfficialBadgeDetail) => d.iconUrl.length > 0);
    const icon = primary !== undefined ? (this.str(badgeV2.icon).length > 0 ? this.str(badgeV2.icon) : primary.iconUrl) : '';
    return { title, icon, details };
  }

  private static parseGithubSocial(socialMediasRaw: JsonValue | undefined): GithubSocial | undefined {
    const medias = this.arr(socialMediasRaw);
    for (const raw of medias) {
      const media = this.obj(raw);
      const title = this.str(media.title);
      if (!title.startsWith('GitHub') && !title.startsWith('github')) {
        continue;
      }
      const modules = this.arr(media.modules);
      let starCount = '';
      for (const m of modules) {
        const mod = this.obj(m);
        if (this.str(mod.title).toLowerCase() === 'stars') {
          starCount = this.str(mod.value);
          break;
        }
      }
      if (starCount.length === 0) {
        continue;
      }
      const profileUrl = this.str(media.link);
      if (profileUrl.length === 0) {
        continue;
      }
      return {
        title,
        starCount,
        profileUrl,
        iconUrl: this.str(media.icon)
      };
    }
    return undefined;
  }

  // ---- 个人资料 ----
  static async loadProfile(context: common.Context, identifier: string): Promise<ZhihuPeopleProfile> {
    const url = `https://api.zhihu.com/people/${identifier}?include=${encodeURIComponent(PROFILE_INCLUDE)}`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('用户资料为空');
    }
    const person = this.obj(payload);
    const id = this.id(person.id);
    const name = this.str(person.name);
    const urlToken = this.str(person.url_token);
    const badge = this.parseBadgeV2(person.badge_v2);

    const profile: ZhihuPeopleProfile = {
      id,
      name,
      headline: this.str(person.headline),
      avatarUrl: this.str(person.avatar_url),
      urlToken,
      followerCount: this.num(person.follower_count),
      followingCount: this.num(person.following_count),
      answerCount: this.num(person.answer_count),
      articleCount: this.num(person.articles_count),
      isFollowing: person.is_following === true,
      isBlocking: person.is_blocking === true,
      officialBadgeTitle: badge.title,
      officialBadgeIcon: badge.icon,
      officialBadgeDetails: badge.details,
      githubSocial: undefined
    };

    // 可选：GitHub 等社交信息
    try {
      const detailUrl = `https://api.zhihu.com/people/${identifier}/profile/detail`;
      const detail = await ZhihuApi.getJson(context, detailUrl, { signed: true });
      if (detail !== null) {
        const github = this.parseGithubSocial(detail.social_medias);
        if (github !== undefined) {
          profile.githubSocial = github;
        }
      }
    } catch (_) {
      // 社交信息可选，失败不影响主资料
    }
    return profile;
  }

  // ---- 关注 / 拉黑 ----
  static async toggleFollow(context: common.Context, urlToken: string, follow: boolean): Promise<{ followerCount: number; isFollowing: boolean }> {
    const url = `https://www.zhihu.com/api/v4/members/${urlToken}/followers`;
    const payload = follow
      ? await ZhihuApi.postJson(context, url, { signed: true })
      : await ZhihuApi.deleteJson(context, url, { signed: true });
    const obj = this.obj(payload);
    return {
      followerCount: this.num(obj.follower_count),
      isFollowing: follow
    };
  }

  static async toggleBlock(context: common.Context, urlToken: string, block: boolean): Promise<{ isBlocking: boolean }> {
    const url = `https://www.zhihu.com/api/v4/members/${urlToken}/actions/block`;
    if (block) {
      await ZhihuApi.postJson(context, url, { signed: true });
    } else {
      await ZhihuApi.deleteJson(context, url, { signed: true });
    }
    return { isBlocking: block };
  }

  // ---- 内容条目 → HomeFeedItem 通用映射（回答/文章/问题/想法）----
  private static mapContentTarget(target: JsonObject, actionText: string): HomeFeedItem | undefined {
    const targetType = this.str(target.type);
    const author = this.obj(target.author);
    const question = this.obj(target.question);

    if (targetType === 'answer') {
      const qId = this.id(question.id);
      const title = this.str(question.title).length > 0 ? this.str(question.title) : this.str(question.name);
      const id = this.id(target.id);
      const voteCount = this.num(target.voteup_count);
      const commentCount = this.num(target.comment_count);
      const nativeTarget: ZhihuCommentableTarget = {
        kind: 'answer',
        id,
        questionId: qId,
        title
      };
      return {
        id: `answer:${id}`,
        type: 'answer',
        title,
        summary: this.str(target.excerpt),
        details: `回答 · ${voteCount} 赞同 · ${commentCount} 评论`,
        authorName: this.str(author.name),
        authorHeadline: this.str(author.headline),
        authorAvatarUrl: this.str(author.avatar_url),
        thumbnailUrl: '',
        targetUrl: `https://www.zhihu.com/question/${qId}/answer/${id}`,
        nativeTarget,
        actionText,
        voteCount,
        commentCount
      };
    }

    if (targetType === 'article') {
      const title = this.str(target.title);
      const id = this.id(target.id);
      const voteCount = this.num(target.voteup_count);
      const commentCount = this.num(target.comment_count);
      const nativeTarget: ZhihuCommentableTarget = { kind: 'article', id, title };
      return {
        id: `article:${id}`,
        type: 'article',
        title,
        summary: this.str(target.excerpt),
        details: `文章 · ${voteCount} 赞同 · ${commentCount} 评论`,
        authorName: this.str(author.name),
        authorHeadline: this.str(author.headline),
        authorAvatarUrl: this.str(author.avatar_url),
        thumbnailUrl: '',
        targetUrl: `https://zhuanlan.zhihu.com/p/${id}`,
        nativeTarget,
        actionText,
        voteCount,
        commentCount
      };
    }

    if (targetType === 'question') {
      const title = this.str(target.title).length > 0 ? this.str(target.title) : this.str(target.name);
      const id = this.id(target.id);
      const answerCount = this.num(target.answer_count);
      const followerCount = this.num(target.follower_count);
      const nativeTarget: ZhihuCommentableTarget = { kind: 'question', id, title };
      return {
        id: `question:${id}`,
        type: 'question',
        title,
        summary: this.str(target.excerpt),
        details: `${answerCount} 回答 · ${followerCount} 关注`,
        authorName: '',
        authorHeadline: '',
        authorAvatarUrl: '',
        thumbnailUrl: '',
        targetUrl: `https://www.zhihu.com/question/${id}`,
        nativeTarget,
        actionText,
        voteCount: 0,
        commentCount: answerCount
      };
    }

    if (targetType === 'pin') {
      const id = this.id(target.id);
      const likeCount = this.num(target.like_count);
      const commentCount = this.num(target.comment_count);
      const authorName = this.str(author.name);
      // 对照安卓 PeopleScreen.PinListItem：只用 excerpt_title / excerpt 作摘要，绝不回退到 content（content 是整篇 HTML 正文）
      const rawSummary = this.str(target.excerpt_title) || this.str(target.excerpt);
      const strippedSummary = this.stripHtml(rawSummary);
      // 概览卡片只给短摘要，不让整段正文铺开（正文属于详情页 Pin.ets，靠 content_html 渲染）
      const pinSummary = strippedSummary.length > 60 ? `${strippedSummary.substring(0, 60)}…` : strippedSummary;
      const nativeTarget: ZhihuCommentableTarget = { kind: 'pin', id };
      return {
        id: `pin:${id}`,
        type: 'pin',
        title: authorName.length > 0 ? `${authorName}的想法` : '想法',
        summary: pinSummary,
        details: `想法 · ${likeCount} 赞 · ${commentCount} 评论`,
        authorName,
        authorHeadline: this.str(author.headline),
        authorAvatarUrl: this.str(author.avatar_url),
        thumbnailUrl: '',
        targetUrl: `https://www.zhihu.com/pin/${id}`,
        nativeTarget,
        actionText,
        voteCount: likeCount,
        commentCount
      };
    }

    return undefined;
  }

  // ---- 回答 ----
  static async loadAnswers(context: common.Context, token: string, sortBy: string, nextUrl?: string): Promise<PeoplePage<HomeFeedItem>> {
    const url =
      nextUrl && nextUrl.length > 0
      ? nextUrl
      : `https://www.zhihu.com/api/v4/members/${token}/answers?sort_by=${sortBy}&include=${encodeURIComponent(ANSWER_INCLUDE)}`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('回答列表为空');
    }
    const items = this.arr(payload.data)
      .map((raw) => this.mapContentTarget(this.obj(raw), ''))
      .filter((it): it is HomeFeedItem => it !== undefined);
    const paging = this.parsePaging(payload);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }

  // ---- 文章 ----
  static async loadArticles(context: common.Context, token: string, sortBy: string, nextUrl?: string): Promise<PeoplePage<HomeFeedItem>> {
    const url =
      nextUrl && nextUrl.length > 0
      ? nextUrl
      : `https://www.zhihu.com/api/v4/members/${token}/articles?sort_by=${sortBy}&include=${encodeURIComponent(ARTICLE_INCLUDE)}`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('文章列表为空');
    }
    const items = this.arr(payload.data)
      .map((raw) => this.mapContentTarget(this.obj(raw), ''))
      .filter((it): it is HomeFeedItem => it !== undefined);
    const paging = this.parsePaging(payload);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }

  // ---- 动态（moment）----
  static async loadActivities(context: common.Context, id: string, nextUrl?: string): Promise<PeoplePage<HomeFeedItem>> {
    const url =
      nextUrl && nextUrl.length > 0
      ? nextUrl
      : `https://www.zhihu.com/api/v3/moments/${id}/activities?include=${encodeURIComponent(ACTIVITY_INCLUDE)}`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('动态列表为空');
    }
    const items = this.arr(payload.data)
      .map((raw) => {
        const moment = this.obj(raw);
        let target = this.obj(moment.target);
        // 防御：某些动态会把内容再包一层 target.target
        if (Object.keys(target).length === 0 && this.obj(moment.target).target !== undefined) {
          target = this.obj(this.obj(moment.target).target);
        }
        if (Object.keys(target).length === 0) {
          return undefined;
        }
        return this.mapContentTarget(target, '');
      })
      .filter((it): it is HomeFeedItem => it !== undefined);
    const paging = this.parsePaging(payload);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }

  // ---- 提问 ----
  static async loadQuestions(context: common.Context, token: string, nextUrl?: string): Promise<PeoplePage<HomeFeedItem>> {
    const url =
      nextUrl && nextUrl.length > 0
      ? nextUrl
      : `https://www.zhihu.com/api/v4/members/${token}/questions?include=${encodeURIComponent(QUESTION_INCLUDE)}`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('提问列表为空');
    }
    const items = this.arr(payload.data)
      .map((raw) => this.mapContentTarget(this.obj(raw), ''))
      .filter((it): it is HomeFeedItem => it !== undefined);
    const paging = this.parsePaging(payload);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }

  // ---- 想法 ----
  static async loadPins(context: common.Context, token: string, nextUrl?: string): Promise<PeoplePage<HomeFeedItem>> {
    const url =
      nextUrl && nextUrl.length > 0
      ? nextUrl
      : `https://www.zhihu.com/api/v4/v2/pins/${token}/moments?include=${encodeURIComponent(PIN_INCLUDE)}`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('想法列表为空');
    }
    // pins 端点（/api/v4/v2/pins/{token}/moments）的 data[] 直接就是 Pin 对象，
    // 没有 .target 包裹层（对照安卓 PeopleScreen.kt:244 include = data[*].like_count…）。
    // 不要照搬 loadActivities 的 moment.target 拆包，否则全部被过滤成空。
    const items = this.arr(payload.data)
      .map((raw) => this.mapContentTarget(this.obj(raw), ''))
      .filter((it): it is HomeFeedItem => it !== undefined);
    const paging = this.parsePaging(payload);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }

  // ---- 想法详情（单条 pin）----
  static async loadPin(context: common.Context, pinId: string): Promise<ZhihuPin> {
    const url = `https://www.zhihu.com/api/v4/pins/${pinId}`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('想法内容为空');
    }
    const p = this.obj(payload);
    const author = this.obj(p.author);
    const authorBadge = this.parseBadgeV2(author.badge_v2);
    return {
      id: this.id(p.id),
      // 知乎 Pin 详情：content 是结构化 ContentItem 数组（str() 对数组返回 ''），
      // 渲染用的 HTML 在 content_html（对照安卓 DataHolder.Pin.contentHtml）。
      contentHtml: this.str(p.content_html),
      excerptTitle: this.str(p.excerpt_title),
      liked: p.liked === true,
      likeCount: this.num(p.like_count),
      commentCount: this.num(p.comment_count),
      createdTime: this.num(p.created),
      updatedTime: this.num(p.updated),
      author: {
        id: this.id(author.id),
        name: this.str(author.name),
        headline: this.str(author.headline),
        avatarUrl: this.str(author.avatar_url),
        urlToken: this.str(author.url_token),
        officialBadgeTitle: authorBadge.title
      },
      topics: this.arr(p.topics).map((raw) => {
        const t = this.obj(raw);
        return {
          id: this.id(t.id),
          name: this.str(t.name),
          avatarUrl: this.str(t.avatar_url)
        } as ZhihuPinTopic;
      })
    };
  }

  // 想法点赞/取消点赞（对齐安卓 PinScreen.togglePinLike：POST/DELETE /pins/{id}/voters/up）
  static async togglePinLike(context: common.Context, pinId: string, isLiked: boolean): Promise<{ liked: boolean; likeCount: number }> {
    const url = `https://www.zhihu.com/api/v4/pins/${pinId}/voters/up`;
    const payload = isLiked
      ? await ZhihuApi.deleteJson(context, url, { signed: true })
      : await ZhihuApi.postJson(context, url, { signed: true });
    const obj = this.obj(payload);
    const likeCount = this.num(obj.liked_count);
    return { liked: !isLiked, likeCount: likeCount >= 0 ? likeCount : -1 };
  }

  // ---- 收藏夹 ----
  static async loadCollections(context: common.Context, token: string, nextUrl?: string): Promise<PeoplePage<ZhihuCollection>> {
    const url =
      nextUrl && nextUrl.length > 0
        ? nextUrl
        : `https://www.zhihu.com/api/v4/members/${token}/favlists?include=${encodeURIComponent(COLLECTION_INCLUDE)}`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('收藏夹列表为空');
    }
    const items = this.arr(payload.data).map((raw) => {
      const c = this.obj(raw);
      return {
        id: this.id(c.id),
        title: this.str(c.title),
        description: this.str(c.description),
        isFavorited: c.is_favorited === true,
        isPublic: c.is_public === true,
        itemCount: this.num(c.answer_count),
        likeCount: 0,
        commentCount: 0,
        viewCount: this.num(c.view_count),
        updatedTime: this.num(c.updated_time),
        isDefault: c.is_default === true
      } as ZhihuCollection;
    });
    const paging = this.parsePaging(payload);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }

  // ---- 专栏 ----
  static async loadColumns(context: common.Context, token: string, nextUrl?: string): Promise<PeoplePage<ZhihuColumnSummary>> {
    const url =
      nextUrl && nextUrl.length > 0
        ? nextUrl
        : `https://www.zhihu.com/api/v4/members/${token}/column-contributions?include=${encodeURIComponent(COLUMN_INCLUDE)}`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('专栏列表为空');
    }
    const items = this.arr(payload.data).map((raw) => {
      const item = this.obj(raw);
      const c = this.obj(item.column);
      const source = Object.keys(c).length > 0 ? c : item;
      return {
        id: this.id(source.id),
        title: this.str(source.title),
        description: this.str(source.description).length > 0 ? this.str(source.description) : this.str(source.introduction),
        articlesCount: this.num(source.articles_count),
        followerCount: Math.max(this.num(item.followers), this.num(source.followers), this.num(source.follower_count)),
        url: this.str(source.url)
      } as ZhihuColumnSummary;
    });
    const paging = this.parsePaging(payload);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }

  // ---- 粉丝（对齐安卓 PeopleScreen.kt：新 api/v4/members/{token}/followers 端点签名 bug 会 403，回退到旧 api.zhihu.com/people/{数字id}/followers）----
  static async loadFollowers(context: common.Context, id: string, nextUrl?: string): Promise<PeoplePage<ZhihuPeopleSummary>> {
    const url =
      nextUrl && nextUrl.length > 0
      ? nextUrl
      : `https://api.zhihu.com/people/${id}/followers?include=${encodeURIComponent(FOLLOW_INCLUDE)}`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('粉丝列表为空');
    }
    const items = this.arr(payload.data).map((raw) => this.mapPeopleSummary(this.obj(raw)));
    const paging = this.parsePaging(payload);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }

  // ---- 关注 ----
  static async loadFollowing(context: common.Context, token: string, nextUrl?: string): Promise<PeoplePage<ZhihuPeopleSummary>> {
    const url =
      nextUrl && nextUrl.length > 0
      ? nextUrl
      : `https://www.zhihu.com/api/v4/members/${token}/followees?include=${encodeURIComponent(FOLLOW_INCLUDE)}`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('关注列表为空');
    }
    const items = this.arr(payload.data).map((raw) => this.mapPeopleSummary(this.obj(raw)));
    const paging = this.parsePaging(payload);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }

  private static mapPeopleSummary(p: JsonObject): ZhihuPeopleSummary {
    const badge = this.parseBadgeV2(p.badge_v2);
    return {
      id: this.id(p.id),
      name: this.str(p.name),
      headline: this.str(p.headline),
      avatarUrl: this.str(p.avatar_url),
      urlToken: this.str(p.url_token),
      answerCount: this.num(p.answer_count),
      articleCount: this.num(p.articles_count),
      followerCount: this.num(p.follower_count),
      officialBadgeTitle: badge.title
    };
  }

  // ---- 关注订阅：四个子列表 ----
  static async loadFollowingColumns(context: common.Context, token: string, nextUrl?: string): Promise<PeoplePage<ZhihuColumnSummary>> {
    const url =
      nextUrl && nextUrl.length > 0
        ? nextUrl
        : `https://www.zhihu.com/api/v4/members/${token}/following-columns?include=${encodeURIComponent(COLUMN_INCLUDE)}`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('订阅专栏为空');
    }
    const items = this.arr(payload.data).map((raw) => {
      const item = this.obj(raw);
      const c = this.obj(item.column);
      const source = Object.keys(c).length > 0 ? c : item;
      return {
        id: this.id(source.id),
        title: this.str(source.title),
        description: this.str(source.description).length > 0 ? this.str(source.description) : this.str(source.introduction),
        articlesCount: this.num(source.articles_count),
        followerCount: Math.max(this.num(item.followers), this.num(source.followers), this.num(source.follower_count)),
        url: this.str(source.url)
      } as ZhihuColumnSummary;
    });
    const paging = this.parsePaging(payload);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }

  static async loadFollowingTopics(context: common.Context, token: string, nextUrl?: string): Promise<PeoplePage<ZhihuTopicSummary>> {
    const url =
      nextUrl && nextUrl.length > 0
        ? nextUrl
        : `https://www.zhihu.com/api/v4/members/${token}/following-topic-contributions`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('订阅话题为空');
    }
    const items = this.arr(payload.data).map((raw) => {
      const item = this.obj(raw);
      const t = this.obj(item.topic);
      const source = Object.keys(t).length > 0 ? t : item;
      return {
        id: this.id(source.id),
        name: this.str(source.name),
        avatarUrl: this.str(source.avatar_url)
      } as ZhihuTopicSummary;
    });
    const paging = this.parsePaging(payload);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }

  static async loadFollowingQuestions(context: common.Context, token: string, nextUrl?: string): Promise<PeoplePage<ZhihuFollowedQuestionSummary>> {
    const url =
      nextUrl && nextUrl.length > 0
        ? nextUrl
        : `https://www.zhihu.com/api/v4/members/${token}/following-questions`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('订阅问题为空');
    }
    const items = this.arr(payload.data).map((raw) => {
      const q = this.obj(raw);
      return {
        id: this.id(q.id),
        title: this.str(q.title)
      } as ZhihuFollowedQuestionSummary;
    });
    const paging = this.parsePaging(payload);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }

  static async loadFollowingCollections(context: common.Context, token: string, nextUrl?: string): Promise<PeoplePage<ZhihuCollection>> {
    const url =
      nextUrl && nextUrl.length > 0
        ? nextUrl
        : `https://www.zhihu.com/api/v4/members/${token}/following-favlists?include=${encodeURIComponent(COLLECTION_INCLUDE)}`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('订阅收藏夹为空');
    }
    const items = this.arr(payload.data).map((raw) => {
      const c = this.obj(raw);
      return {
        id: this.id(c.id),
        title: this.str(c.title),
        description: this.str(c.description),
        isFavorited: c.is_favorited === true,
        isPublic: c.is_public === true,
        itemCount: this.num(c.answer_count),
        likeCount: 0,
        commentCount: 0,
        viewCount: this.num(c.view_count),
        updatedTime: this.num(c.updated_time),
        isDefault: c.is_default === true
      } as ZhihuCollection;
    });
    const paging = this.parsePaging(payload);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }
}
