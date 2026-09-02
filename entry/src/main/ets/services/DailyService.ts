import { ZhihuApi } from './ZhihuApi';

type JsonPrimitive = string | number | boolean | null | undefined;
type JsonValue = JsonPrimitive | JsonObject | JsonValue[];

interface JsonObject {
  [key: string]: JsonValue;
}

export interface DailyStory {
  readonly id: string;
  readonly title: string;
  readonly hint: string;
  readonly url: string;
  readonly image?: string;
}

export interface DailyStoriesPage {
  readonly date: string;
  readonly stories: DailyStory[];
}

export class DailyService {
  private static readonly LATEST_URL = 'https://news-at.zhihu.com/api/4/stories/latest';
  private static readonly BEFORE_URL = 'https://news-at.zhihu.com/api/4/stories/before';
  private static readonly STORY_URL = 'https://daily.zhihu.com/api/7/story';

  static async loadLatest(): Promise<DailyStoriesPage> {
    const payload = await ZhihuApi.getJson(this.LATEST_URL);
    return this.mapStoriesPage(payload as JsonObject);
  }

  static async loadBefore(date: string): Promise<DailyStoriesPage> {
    const payload = await ZhihuApi.getJson(`${this.BEFORE_URL}/${date}`);
    return this.mapStoriesPage(payload as JsonObject);
  }

  /**
   * 拉取单篇日报详情，返回正文 HTML（含 <a class="originUrl"> 原文链接）。
   * 对齐安卓 DailyScreen：请求 https://daily.zhihu.com/api/7/story/{id} 读 response["body"]。
   * 失败或字段缺失返回 undefined，由调用方退化到网页。
   */
  static async getStoryBody(id: string): Promise<string | undefined> {
    if (id.length === 0) {
      return undefined;
    }
    try {
      const payload = await ZhihuApi.getJson(`${this.STORY_URL}/${id}`);
      if (payload === null) {
        return undefined;
      }
      const body = payload['body'];
      return typeof body === 'string' ? body : undefined;
    } catch (e) {
      return undefined;
    }
  }

  /**
   * 从日报正文 HTML 抠出知乎原文链接（对齐安卓 Ksoup 解析）。
   * 主：<a class="...originUrl..."> 的 href；兜底：<div class="...view-more..."> 内的 <a href>。
   * HTML 实体 &amp; 还原为 &。取不到返回 undefined。
   */
  static extractOriginUrl(html: string): string | undefined {
    const primary = html.match(/<a\b[^>]*\bclass="[^"]*\boriginUrl\b[^"]*"[^>]*\bhref="([^"]*)"[^>]*>/i)
      ?? html.match(/<a\b[^>]*\bhref="([^"]*)"[^>]*\bclass="[^"]*\boriginUrl\b[^"]*"[^>]*>/i);
    if (primary !== null) {
      const href = primary[1];
      if (href.length > 0) {
        return href.replace(/&amp;/g, '&');
      }
    }
    const viewMore = html.match(/<div\b[^>]*\bclass="[^"]*\bview-more\b[^"]*"[^>]*>([\s\S]*?)<\/div>/i);
    if (viewMore !== null) {
      const inner = viewMore[1];
      const a = inner.match(/<a\b[^>]*\bhref="([^"]*)"[^>]*>/i);
      if (a !== null) {
        const href = a[1];
        if (href.length > 0) {
          return href.replace(/&amp;/g, '&');
        }
      }
    }
    return undefined;
  }

  private static mapStoriesPage(payload: JsonObject): DailyStoriesPage {
    const storiesValue = payload.stories;
    const stories = Array.isArray(storiesValue) ? storiesValue : [];

    return {
      date: typeof payload.date === 'string' ? payload.date : '',
      stories: stories.map((item: JsonValue): DailyStory => {
        const story = item as JsonObject;
        const images = Array.isArray(story.images) ? story.images : [];
        return {
          id: `${story.id ?? ''}`,
          title: typeof story.title === 'string' ? story.title : '未命名日报',
          hint: typeof story.hint === 'string' ? story.hint : '知乎日报',
          url: typeof story.url === 'string' ? story.url : '',
          image: typeof images[0] === 'string' ? images[0] : undefined
        };
      })
    };
  }
}
