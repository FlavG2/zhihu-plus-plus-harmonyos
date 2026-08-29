import common from '@ohos.app.ability.common';
import { HomeFeedItem, TopicDetail } from '../models/ZhihuModels';
import { PeoplePage, PeopleService } from './PeopleService';
import { ZhihuApi } from './ZhihuApi';

// 对齐安卓 TopicScreen.kt / TopicViewModel：
// - 话题详情：GET /api/v5.1/topics/{id}
// - 话题信息流（讨论/想法/待回答 × 排序）：/api/v5.1/topics/{id}/feeds/...
// - 关注：POST/DELETE /api/v4/topics/{id}/followers
// 接口全部走签名请求（signed: true），与 PeopleService 一致。

export type TopicFeedTab = 'discussion' | 'ideas' | 'unanswered';
export type TopicDiscussionSort = 'essence' | 'hot' | 'timeline';
export type TopicIdeasSort = 'hot' | 'latest';

type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];

interface JsonObject {
  [key: string]: JsonValue;
}

export class TopicService {
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

  // ---- 话题详情 ----
  static async getTopicDetail(context: common.Context, topicId: string): Promise<TopicDetail> {
    const url = `https://www.zhihu.com/api/v5.1/topics/${topicId}`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('话题详情为空');
    }
    const t = this.obj(payload);
    return {
      id: this.id(t.id),
      name: this.str(t.name),
      excerpt: this.str(t.excerpt),
      avatarUrl: this.str(t.avatar_url),
      followersCount: this.num(t.followers_count),
      questionsCount: this.num(t.questions_count),
      isFollowing: t.is_following === true,
      topicId: this.str(t.topic_id),
      totalPv: this.num(t.total_pv),
      discussCount: this.num(t.discuss_count)
    };
  }

  // ---- 信息流端点 ----
  private static feedUrl(topicId: string, tab: TopicFeedTab, sort: string): string {
    const base = `https://www.zhihu.com/api/v5.1/topics/${topicId}/feeds`;
    if (tab === 'discussion') {
      if (sort === 'hot') return `${base}/essence/v2?limit=20&offset=0`;
      if (sort === 'timeline') return `${base}/timeline_activity/v2?limit=20&offset=0`;
      return `${base}/top_activity/v2?limit=20&offset=0`; // essence（精华）
    }
    if (tab === 'ideas') {
      const endpoint = sort === 'latest' ? 'pin-new' : 'pin-hot';
      return `${base}/${endpoint}?offset=0&limit=10`;
    }
    // unanswered（待回答）
    return `${base}/top_question/v2?limit=20&offset=0`;
  }

  // ---- 信息流（讨论/想法/待回答），复用 PeopleService.mapContentTarget 映射 HomeFeedItem ----
  static async getTopicFeed(
    context: common.Context,
    topicId: string,
    tab: TopicFeedTab,
    sort: string,
    nextUrl?: string
  ): Promise<PeoplePage<HomeFeedItem>> {
    const url = nextUrl && nextUrl.length > 0 ? nextUrl : this.feedUrl(topicId, tab, sort);
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('话题信息流为空');
    }
    const obj = this.obj(payload);
    const data = this.arr(obj.data);
    const items: HomeFeedItem[] = [];
    for (const raw of data) {
      const item = this.obj(raw);
      // 讨论/待回答 feeds 把内容包在 item.target；想法 feeds 的 data[] 直接是 pin 对象
      const target = item.target !== undefined ? this.obj(item.target) : item;
      if (Object.keys(target).length === 0) {
        continue;
      }
      const mapped = PeopleService.mapContentTarget(target, '');
      if (mapped !== undefined) {
        items.push(mapped);
      }
    }
    const paging = this.parsePaging(obj);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }

  // ---- 关注 / 取消关注（乐观更新由页面层负责）----
  static async toggleFollowTopic(
    context: common.Context,
    topicId: string,
    follow: boolean
  ): Promise<{ followerCount: number; isFollowing: boolean }> {
    const url = `https://www.zhihu.com/api/v4/topics/${topicId}/followers`;
    const payload = follow
      ? await ZhihuApi.postJson(context, url, { signed: true })
      : await ZhihuApi.deleteJson(context, url, { signed: true });
    const obj = this.obj(payload);
    const followerCount = this.num(obj.follower_count);
    return {
      // 关注接口有时不回 follower_count，用 -1 让页面回退到本地乐观值
      followerCount: followerCount >= 0 ? followerCount : -1,
      isFollowing: follow
    };
  }
}
