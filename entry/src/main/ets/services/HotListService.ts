import common from '@ohos.app.ability.common';
import { HomeFeedPage } from '../models/ZhihuModels';
import { HomeFeedService } from './HomeFeedService';
import { ZhihuApi } from './ZhihuApi';

export class HotListService {
  private static readonly INITIAL_URL: string = 'https://www.zhihu.com/api/v3/feed/topstory/hot-lists/total?limit=50&mobile=true';

  static async loadFirstPage(context: common.Context): Promise<HomeFeedPage> {
    return this.loadPage(context, this.INITIAL_URL);
  }

  static async loadNextPage(context: common.Context, nextUrl: string): Promise<HomeFeedPage> {
    return this.loadPage(context, nextUrl);
  }

  private static async loadPage(context: common.Context, url: string): Promise<HomeFeedPage> {
    const payload = await ZhihuApi.getJson(context, url, {
      signed: true,
      allowUnauthorized: true
    });
    if (payload === null) {
      throw new Error('热榜接口未授权，请稍后重试');
    }
    return HomeFeedService.mapHotListPage(payload);
  }
}
