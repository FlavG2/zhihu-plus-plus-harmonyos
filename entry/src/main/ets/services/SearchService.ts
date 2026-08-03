import common from '@ohos.app.ability.common';
import { HomeFeedPage } from '../models/ZhihuModels';
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
}
