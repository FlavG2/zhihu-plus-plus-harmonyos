import common from '@ohos.app.ability.common';
import { HomeFeedPage } from '../models/ZhihuModels';
import { HomeFeedService } from './HomeFeedService';

export type FollowFeedTab = 'latest' | 'featured';

export class FollowFeedService {
  private static readonly RECOMMEND_URL: string = 'https://api.zhihu.com/moments_v3?feed_type=recommend';
  private static readonly DYNAMIC_URL: string = 'https://www.zhihu.com/api/v3/moments?limit=10&desktop=true';

  // latest（最新，左侧默认）= 动态时间线；featured（精选，右侧）= 推荐流
  private static initialUrl(tab: FollowFeedTab): string {
    return tab === 'latest' ? this.DYNAMIC_URL : this.RECOMMEND_URL;
  }

  static async loadFirstPage(context: common.Context, tab: FollowFeedTab): Promise<HomeFeedPage> {
    return HomeFeedService.loadSignedPage(context, this.initialUrl(tab));
  }

  static async loadNextPage(context: common.Context, nextUrl: string): Promise<HomeFeedPage> {
    return HomeFeedService.loadSignedPage(context, nextUrl);
  }
}
