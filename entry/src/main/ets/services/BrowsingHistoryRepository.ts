import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import { ZhihuCommentableTarget } from '../models/ZhihuContentModels';
import { HomeFeedItem } from '../models/ZhihuModels';
import { resolveZhihuContent } from './ZhihuContentResolver';

type HistoryFeedType = 'answer' | 'article' | 'question' | 'pin';

const HISTORY_PREFERENCES_FILE: string = 'zhihu_browsing_history';
const HISTORY_DATA_KEY: string = 'history_items';
const MAX_HISTORY_ITEMS: number = 100;

export class BrowsingHistoryRepository {
  private static preferences(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, {
      name: HISTORY_PREFERENCES_FILE
    });
  }

  private static sanitizeItem(raw: Object | undefined): HomeFeedItem | undefined {
    if (raw === undefined || raw === null || typeof raw !== 'object') {
      return undefined;
    }
    const objectValue = raw as Record<string, Object>;
    const rawType = typeof objectValue.type === 'string' ? objectValue.type : '';
    const title = typeof objectValue.title === 'string' ? objectValue.title : '';
    const targetUrl = typeof objectValue.targetUrl === 'string' ? objectValue.targetUrl : '';
    if ((rawType !== 'answer' && rawType !== 'article' && rawType !== 'question' && rawType !== 'pin')
      || title.length === 0
      || targetUrl.length === 0) {
      return undefined;
    }
    const type = rawType as HistoryFeedType;
    return {
      id: typeof objectValue.id === 'string' ? objectValue.id : `${type}:${targetUrl}`,
      type,
      title,
      summary: typeof objectValue.summary === 'string' ? objectValue.summary : '',
      details: typeof objectValue.details === 'string' ? objectValue.details : '最近浏览',
      authorName: typeof objectValue.authorName === 'string' ? objectValue.authorName : '',
      authorHeadline: typeof objectValue.authorHeadline === 'string' ? objectValue.authorHeadline : '',
      authorAvatarUrl: typeof objectValue.authorAvatarUrl === 'string' ? objectValue.authorAvatarUrl : '',
      thumbnailUrl: typeof objectValue.thumbnailUrl === 'string' ? objectValue.thumbnailUrl : '',
      targetUrl,
      nativeTarget: objectValue.nativeTarget !== undefined && objectValue.nativeTarget !== null && typeof objectValue.nativeTarget === 'object'
        ? objectValue.nativeTarget as ZhihuCommentableTarget
        : undefined,
      actionText: typeof objectValue.actionText === 'string' ? objectValue.actionText : '',
      voteCount: typeof objectValue.voteCount === 'number' ? objectValue.voteCount as number : 0,
      commentCount: typeof objectValue.commentCount === 'number' ? objectValue.commentCount as number : 0
    };
  }

  private static targetType(target: ZhihuCommentableTarget | undefined): 'answer' | 'article' | 'question' | 'pin' {
    return target?.kind ?? 'article';
  }

  private static targetId(target: ZhihuCommentableTarget | undefined, url: string): string {
    if (target !== undefined) {
      return `${target.kind}:${target.id}`;
    }
    return `web:${url}`;
  }

  static load(context: common.Context): HomeFeedItem[] {
    const store = this.preferences(context);
    const encoded = store.getSync(HISTORY_DATA_KEY, '') as string;
    if (encoded.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(encoded) as Object[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed
        .map((item: Object) => this.sanitizeItem(item))
        .filter((item: HomeFeedItem | undefined): item is HomeFeedItem => item !== undefined);
    } catch (_) {
      return [];
    }
  }

  static save(context: common.Context, items: HomeFeedItem[]): HomeFeedItem[] {
    const trimmed = items.slice(0, MAX_HISTORY_ITEMS);
    const store = this.preferences(context);
    store.putSync(HISTORY_DATA_KEY, JSON.stringify(trimmed));
    store.flushSync();
    return trimmed;
  }

  static recordContent(
    context: common.Context,
    target: ZhihuCommentableTarget,
    title: string,
    url: string,
    summary: string = ''
  ): HomeFeedItem[] {
    return this.recordItem(context, {
      id: this.targetId(target, url),
      type: this.targetType(target),
      title: title.length > 0 ? title : '知乎内容',
      summary,
      details: '最近浏览',
      authorName: '',
      authorHeadline: '',
      authorAvatarUrl: '',
      thumbnailUrl: '',
      targetUrl: url,
      nativeTarget: target,
      actionText: '',
      voteCount: 0,
      commentCount: 0
    });
  }

  static recordWeb(context: common.Context, title: string, url: string): HomeFeedItem[] {
    const nativeTarget = resolveZhihuContent(url);
    return this.recordItem(context, {
      id: this.targetId(nativeTarget, url),
      type: this.targetType(nativeTarget),
      title: title.length > 0 ? title : '网页',
      summary: nativeTarget === undefined ? url : '',
      details: nativeTarget === undefined ? '网页' : '最近浏览',
      authorName: '',
      authorHeadline: '',
      authorAvatarUrl: '',
      thumbnailUrl: '',
      targetUrl: url,
      nativeTarget,
      actionText: '',
      voteCount: 0,
      commentCount: 0
    });
  }

  static recordItem(context: common.Context, item: HomeFeedItem): HomeFeedItem[] {
    const current = this.load(context);
    const merged = [
      item,
      ...current.filter((existing: HomeFeedItem) => existing.id !== item.id)
    ];
    return this.save(context, merged);
  }

  static clear(context: common.Context): HomeFeedItem[] {
    return this.save(context, []);
  }

  static removeItem(context: common.Context, itemId: string): HomeFeedItem[] {
    const current = this.load(context);
    const filtered = current.filter((existing: HomeFeedItem) => existing.id !== itemId);
    if (filtered.length === current.length) {
      return current;
    }
    return this.save(context, filtered);
  }
}
