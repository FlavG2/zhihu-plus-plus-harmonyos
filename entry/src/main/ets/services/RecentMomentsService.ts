import common from '@ohos.app.ability.common';
import { ZhihuApi } from './ZhihuApi';

type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];

interface JsonObject {
  [key: string]: JsonValue;
}

// 对齐安卓 RecentMomentsViewModel.FollowingUserItem：关注的人横排数据
export interface FollowingUserItem {
  readonly id: string;
  readonly urlToken: string;
  readonly name: string;
  readonly avatarUrl: string;
  readonly unreadCount: number;
}

export class RecentMomentsService {
  // 安卓 FollowViewModel.load 使用的端点（关注的人「最近动态」横排）
  private static readonly RECENT_URL: string = 'https://api.zhihu.com/moments/recent?type=raw';

  static async loadFollowingUsers(context: common.Context): Promise<FollowingUserItem[]> {
    try {
      const json = await ZhihuApi.getJson(context, this.RECENT_URL, { signed: true });
      if (json === null) {
        return [];
      }
      const data = json['data'];
      const arr: JsonValue[] = Array.isArray(data) ? (data as JsonValue[]) : [];
      const result: FollowingUserItem[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item = arr[i] as JsonObject;
        const actor = item['actor'] as JsonObject | undefined;
        if (actor === undefined) {
          continue;
        }
        const idVal = actor['id'];
        const id = typeof idVal === 'string' ? idVal : (idVal !== null && idVal !== undefined ? `${idVal}` : '');
        // 接口返回蛇形字段（url_token / avatar_url），驼峰兜底
        const urlToken = typeof actor['url_token'] === 'string' ? (actor['url_token'] as string)
          : (typeof actor['urlToken'] === 'string' ? (actor['urlToken'] as string) : '');
        const name = typeof actor['name'] === 'string' ? (actor['name'] as string) : '';
        const avatarUrl = typeof actor['avatar_url'] === 'string' ? (actor['avatar_url'] as string)
          : (typeof actor['avatarUrl'] === 'string' ? (actor['avatarUrl'] as string) : '');
        const unreadVal = item['unreadCount'];
        const unreadCount = typeof unreadVal === 'number' ? unreadVal : 0;
        if (id.length === 0) {
          continue;
        }
        result.push({ id, urlToken, name, avatarUrl, unreadCount });
      }
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      console.warn('[RECENT_MOMENTS] 加载关注的人失败: ' + message);
      return [];
    }
  }
}
