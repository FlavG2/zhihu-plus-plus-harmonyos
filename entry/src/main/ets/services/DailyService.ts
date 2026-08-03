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

  static async loadLatest(): Promise<DailyStoriesPage> {
    const payload = await ZhihuApi.getJson(this.LATEST_URL);
    return this.mapStoriesPage(payload as JsonObject);
  }

  static async loadBefore(date: string): Promise<DailyStoriesPage> {
    const payload = await ZhihuApi.getJson(`${this.BEFORE_URL}/${date}`);
    return this.mapStoriesPage(payload as JsonObject);
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
