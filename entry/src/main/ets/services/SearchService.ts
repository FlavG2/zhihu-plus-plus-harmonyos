import common from '@ohos.app.ability.common';
import { HomeFeedPage, SearchPeopleResult, SearchTopicResult } from '../models/ZhihuModels';
import { HomeFeedService } from './HomeFeedService';
import { ZhihuApi } from './ZhihuApi';

type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];

interface JsonObject {
  [key: string]: JsonValue;
}

export interface HotSearchItem {
  readonly query: string;
  readonly hotShow: string;
  readonly label: string;
}

export class SearchService {
  private static readonly HOT_SEARCH_URL: string = 'https://www.zhihu.com/api/v4/search/hot_search';
  private static readonly SEARCH_INCLUDE: string = 'data[*].highlight,object,type';

  private static stringValue(value: JsonValue | undefined): string {
    return typeof value === 'string' ? value : '';
  }

  private static objectValue(value: JsonValue | undefined): JsonObject {
    return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as JsonObject : {};
  }

  private static arrayValue(value: JsonValue | undefined): JsonValue[] {
    return Array.isArray(value) ? value : [];
  }

  private static idValue(value: JsonValue | undefined): string {
    if (typeof value === 'number') {
      return `${value}`;
    }
    if (typeof value === 'string') {
      return value;
    }
    return '';
  }

  private static numberValue(value: JsonValue | undefined): number {
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsed = Number(value);
      return Number.isFinite(parsed) ? parsed : 0;
    }
    return 0;
  }

  // 内容类型 vertical 参数：回答/文章走服务端 vertical，问题无对应 vertical 故客户端过滤（传空）
  private static readonly SEARCH_VERTICAL_INFO: string = '0,0,0,0,0,0,0,0,0,0,0,0';

  private static initialSearchUrl(
    query: string,
    sortOption: string = '',
    contentType: string = '',
    timeRange: string = '',
    restrictedMemberHashId?: string
  ): string {
    const encodedQuery = encodeURIComponent(query);
    const params: string[] = [
      `gk_version=gz-gaokao`,
      `t=general`,
      `q=${encodedQuery}`,
      `correction=1`,
      `offset=0`,
      `limit=10`,
      `show_all_topics=0`
    ];
    const hasActiveFilter = sortOption.length > 0 || contentType.length > 0 || timeRange.length > 0;
    params.push(`search_source=${hasActiveFilter ? 'Filter' : 'Normal'}`);
    if (restrictedMemberHashId !== undefined && restrictedMemberHashId.length > 0) {
      params.push(
        `restricted_scene=member`,
        `restricted_field=member_hash_id`,
        `restricted_value=${encodeURIComponent(restrictedMemberHashId)}`
      );
    }
    if (contentType.length > 0) {
      params.push(`vertical=${contentType}`, `vertical_info=${this.SEARCH_VERTICAL_INFO}`);
    }
    if (sortOption.length > 0) {
      params.push(`sort=${sortOption}`);
    }
    if (timeRange.length > 0) {
      params.push(`time_interval=${timeRange}`);
    }
    return `https://www.zhihu.com/api/v4/search_v3?${params.join('&')}`;
  }

  static async loadHotSearch(): Promise<HotSearchItem[]> {
    const payload = await ZhihuApi.getJson(this.HOT_SEARCH_URL);
    if (payload === null) {
      return [];
    }
    return this.arrayValue((payload as JsonObject).hot_search_queries)
      .slice(0, 15)
      .map((item: JsonValue): HotSearchItem => {
        const value = this.objectValue(item);
        return {
          query: this.stringValue(value.query),
          hotShow: this.stringValue(value.hotShow),
          label: this.stringValue(value.label)
        };
      })
      .filter((item: HotSearchItem) => item.query.length > 0);
  }

  static async searchFirstPage(
    context: common.Context,
    query: string,
    restrictedMemberHashId?: string,
    sortOption: string = '',
    contentType: string = '',
    timeRange: string = ''
  ): Promise<HomeFeedPage> {
    const url = this.initialSearchUrl(query, sortOption, contentType, timeRange, restrictedMemberHashId);
    return this.searchPage(context, url);
  }

  static async searchNextPage(context: common.Context, nextUrl: string): Promise<HomeFeedPage> {
    return this.searchPage(context, nextUrl);
  }

  private static async searchPage(context: common.Context, url: string): Promise<HomeFeedPage> {
    const separator = url.includes('?') ? '&' : '?';
    const requestUrl = url.includes('include=') ? url : `${url}${separator}include=${encodeURIComponent(this.SEARCH_INCLUDE)}`;
    const payload = await ZhihuApi.getJson(context, requestUrl, { signed: true });
    if (payload === null) {
      throw new Error('搜索结果为空');
    }
    return HomeFeedService.mapSearchPage(payload as JsonObject);
  }

  // ---- 实体搜索（用户 / 话题），对齐安卓 SearchViewModel.SearchTab.People / Topic ----
  private static entitySearchUrl(query: string, type: 'people' | 'topic', nextUrl?: string): string {
    if (nextUrl !== undefined && nextUrl.length > 0) {
      return nextUrl;
    }
    const encodedQuery = encodeURIComponent(query);
    const params: string[] = [
      `t=${type}`,
      `q=${encodedQuery}`,
      `correction=1`,
      `offset=0`,
      `limit=10`
    ];
    return `https://www.zhihu.com/api/v4/search_v3?${params.join('&')}`;
  }

  private static parseEntityPaging(payload: JsonObject): { nextUrl: string; isEnd: boolean } {
    const paging = this.objectValue(payload.paging);
    const next = this.stringValue(paging.next);
    return {
      nextUrl: next.startsWith('http') ? next : (next.length > 0 ? `https://www.zhihu.com${next.startsWith('/') ? '' : '/'}${next}` : ''),
      isEnd: paging.is_end === true
    };
  }

  static async searchPeople(
    context: common.Context,
    query: string,
    nextUrl?: string
  ): Promise<SearchEntityPage<SearchPeopleResult>> {
    const url = this.entitySearchUrl(query, 'people', nextUrl);
    const requestUrl = url.includes('include=') ? url : `${url}&include=${encodeURIComponent(this.SEARCH_INCLUDE)}`;
    const payload = await ZhihuApi.getJson(context, requestUrl, { signed: true });
    if (payload === null) {
      throw new Error('用户搜索结果为空');
    }
    const root = payload as JsonObject;
    const items = this.arrayValue(root.data)
      .map((raw: JsonValue): SearchPeopleResult | undefined => {
        const entry = this.objectValue(raw);
        if (entry.type !== 'search_result') {
          return undefined;
        }
        const o = this.objectValue(entry.object);
        if (this.stringValue(o.type) !== 'people') {
          return undefined;
        }
        return {
          id: this.idValue(o.id),
          name: this.stringValue(o.name).replace(/<em>/g, '').replace(/<\/em>/g, ''),
          avatarUrl: this.stringValue(o.avatar_url),
          headline: this.stringValue(o.headline).replace(/<em>/g, '').replace(/<\/em>/g, ''),
          followerCount: this.numberValue(o.follower_count),
          urlToken: this.stringValue(o.url_token)
        };
      })
      .filter((it): it is SearchPeopleResult => it !== undefined && it.id.length > 0);
    const paging = this.parseEntityPaging(root);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }

  static async searchTopics(
    context: common.Context,
    query: string,
    nextUrl?: string
  ): Promise<SearchEntityPage<SearchTopicResult>> {
    const url = this.entitySearchUrl(query, 'topic', nextUrl);
    const requestUrl = url.includes('include=') ? url : `${url}&include=${encodeURIComponent(this.SEARCH_INCLUDE)}`;
    const payload = await ZhihuApi.getJson(context, requestUrl, { signed: true });
    if (payload === null) {
      throw new Error('话题搜索结果为空');
    }
    const root = payload as JsonObject;
    const items = this.arrayValue(root.data)
      .map((raw: JsonValue): SearchTopicResult | undefined => {
        const entry = this.objectValue(raw);
        if (entry.type !== 'search_result') {
          return undefined;
        }
        const o = this.objectValue(entry.object);
        if (this.stringValue(o.type) !== 'topic') {
          return undefined;
        }
        return {
          id: this.idValue(o.id),
          name: this.stringValue(o.name).replace(/<em>/g, '').replace(/<\/em>/g, ''),
          avatarUrl: this.stringValue(o.avatar_url),
          excerpt: this.stringValue(o.excerpt).replace(/<em>/g, '').replace(/<\/em>/g, ''),
          visitCount: this.numberValue(o.visit_count),
          discussCount: this.numberValue(o.top_answer_count),
          isFollowing: o.is_following === true
        };
      })
      .filter((it): it is SearchTopicResult => it !== undefined && it.id.length > 0);
    const paging = this.parseEntityPaging(root);
    return { items, nextUrl: paging.nextUrl, isEnd: paging.isEnd };
  }
}

export interface SearchEntityPage<T> {
  readonly items: T[];
  readonly nextUrl: string;
  readonly isEnd: boolean;
}
