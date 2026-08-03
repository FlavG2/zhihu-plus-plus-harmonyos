import { contentTargetUrl, ZhihuCommentableTarget } from '../models/ZhihuContentModels';
import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import { HomeFeedItem, HomeFeedPage, TextHighlightSegment } from '../models/ZhihuModels';
import { ZhihuApi } from './ZhihuApi';
import { resolveZhihuContent } from './ZhihuContentResolver';
import { decodeHtmlEntities, stripHtmlToText } from '../utils/ZhihuHtml';
import { FilterSettingsRepository, FILTER_KEYS, RecommendAlgo } from './FilterSettingsRepository';

type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];

interface JsonObject {
  [key: string]: JsonValue;
}

// 主页拉取选项：extra headers（安卓 PP 头）+ 可选 cookie 覆盖（游客模式传 {}）
interface FeedLoadOptions {
  readonly headers?: Record<string, string>;
  readonly cookies?: Record<string, string>;
}

export class HomeFeedService {
  private static readonly INITIAL_URL: string = 'https://api.zhihu.com/topstory/recommend';

  // 安卓端推荐头（对齐安卓 AccountData.ANDROID_HEADERS / ANDROID_USER_AGENT）
  private static readonly ANDROID_HEADERS: Record<string, string> = {
    'x-api-version': '3.1.8',
    'x-app-version': '10.61.0',
    'x-app-za': 'OS=Android&Release=12&Model=sdk_gphone64_arm64&VersionName=10.61.0&VersionCode=26107&Product=com.zhihu.android&Width=1440&Height=2952&Installer=%E7%81%B0%E5%BA%A6&DeviceType=AndroidPhone&Brand=google',
    'User-Agent': 'com.zhihu.android/Futureve/10.61.0 Mozilla/5.0 (Linux; Android 12; sdk_gphone64_arm64 Build/SE1A.220630.001.A1; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/57.0.1000.10 Mobile Safari/537.36'
  };

  // 翻页时沿用首屏选择的算法 / 游客标记（mixed 模式下后续页走 web 分支）
  private static nextPageAlgo: RecommendAlgo = 'web';
  private static nextPageGuest: boolean = false;

  // 启动缓存快照（关闭「启动时自动刷新」时优先展示）
  private static readonly HOME_SNAPSHOT_KEY: string = 'home_feed_snapshot_v1';
  private static readonly HOME_SNAPSHOT_MAX: number = 10;

  private static stringValue(value: JsonValue | undefined): string {
    return typeof value === 'string' ? value : '';
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

  private static idValue(value: JsonValue | undefined): string {
    if (typeof value === 'number') {
      return `${value}`;
    }
    if (typeof value === 'string') {
      return value;
    }
    return '';
  }

  private static booleanValue(value: JsonValue | undefined): boolean {
    return value === true;
  }

  private static objectValue(value: JsonValue | undefined): JsonObject {
    return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as JsonObject : {};
  }

  private static arrayValue(value: JsonValue | undefined): JsonValue[] {
    return Array.isArray(value) ? value : [];
  }

  private static arrayOfObjects(value: JsonValue | undefined): JsonObject[] {
    return Array.isArray(value) ? value.map((item: JsonValue) => this.objectValue(item)) : [];
  }

  private static firstString(value: JsonValue | undefined): string {
    if (typeof value === 'string') {
      return value;
    }
    if (Array.isArray(value)) {
      const found = value.find((item: JsonValue) => typeof item === 'string');
      return typeof found === 'string' ? found : '';
    }
    return '';
  }

  private static highlightValue(rawSearchItem: JsonObject, key: string): string {
    const highlight = this.objectValue(rawSearchItem.highlight);
    return this.firstString(highlight[key]);
  }

  private static parseHighlightSegments(html: string): TextHighlightSegment[] {
    const segments: TextHighlightSegment[] = [];
    const pattern = /<em>(.*?)<\/em>/gi;
    let lastIndex = 0;
    let match: RegExpExecArray | null = pattern.exec(html);
    while (match !== null) {
      const before = html.slice(lastIndex, match.index);
      if (before.length > 0) {
        const text = stripHtmlToText(before);
        if (text.length > 0) {
          segments.push({ text, highlighted: false });
        }
      }
      const highlightedText = decodeHtmlEntities(match[1].replace(/<[^>]+>/g, ''));
      if (highlightedText.length > 0) {
        segments.push({ text: highlightedText, highlighted: true });
      }
      lastIndex = match.index + match[0].length;
      match = pattern.exec(html);
    }

    const after = html.slice(lastIndex);
    if (after.length > 0) {
      const text = stripHtmlToText(after);
      if (text.length > 0) {
        segments.push({ text, highlighted: false });
      }
    }
    return segments;
  }

  private static joinDetails(base: string, actionText: string): string {
    return actionText.length > 0 ? `${base} · ${actionText}` : base;
  }

  private static resolveTargetUrl(targetType: string, target: JsonObject, rawFeed: JsonObject): string {
    const originalUrl = this.stringValue(target.url);
    const resolvedOriginal = resolveZhihuContent(originalUrl);
    if (resolvedOriginal !== undefined) {
      return contentTargetUrl(resolvedOriginal);
    }
    if (originalUrl.startsWith('https://www.zhihu.com/')
      || originalUrl.startsWith('https://zhuanlan.zhihu.com/')
      || originalUrl.startsWith('https://www.zhihu.com/pin/')) {
      return originalUrl;
    }

    const targetId = this.idValue(target.id);
    if (targetType === 'answer') {
      const questionId = this.idValue(this.objectValue(target.question).id);
      if (questionId.length > 0 && targetId.length > 0) {
        return `https://www.zhihu.com/question/${questionId}/answer/${targetId}`;
      }
    }
    if (targetType === 'article' && targetId.length > 0) {
      return `https://zhuanlan.zhihu.com/p/${targetId}`;
    }
    if (targetType === 'question' && targetId.length > 0) {
      return `https://www.zhihu.com/question/${targetId}`;
    }
    if (targetType === 'pin' && targetId.length > 0) {
      return `https://www.zhihu.com/pin/${targetId}`;
    }

    const rawId = this.stringValue(rawFeed.id);
    return rawId.length > 0 ? `https://www.zhihu.com/${rawId}` : originalUrl;
  }

  private static stableItemId(type: string, target: JsonObject, rawFeed: JsonObject): string {
    const exactTargetId = this.exactTargetIdFromUrl(type, target, rawFeed);
    if (exactTargetId.length > 0) {
      return `${type}:${exactTargetId}`;
    }
    const targetId = this.idValue(target.id);
    if (targetId.length > 0) {
      return `${type}:${targetId}`;
    }
    const rawId = this.stringValue(rawFeed.id);
    if (rawId.length > 0) {
      return `${type}:${rawId}`;
    }
    const url = this.resolveTargetUrl(type, target, rawFeed);
    if (url.length > 0) {
      return `${type}:${url}`;
    }
    const title = this.stringValue(target.title) || this.stringValue(this.objectValue(target.question).title);
    return `${type}:${title}`;
  }

  private static pickThumbnail(target: JsonObject, fallback: JsonObject): string {
    const thumbnail = this.stringValue(target.thumbnail);
    if (thumbnail.length > 0) {
      return thumbnail;
    }
    const thumbnails = this.arrayValue(target.thumbnails);
    if (thumbnails.length > 0 && typeof thumbnails[0] === 'string') {
      return thumbnails[0];
    }
    const children = this.arrayValue(fallback.children);
    if (children.length > 0) {
      return this.stringValue(this.objectValue(children[0]).thumbnail);
    }
    return '';
  }

  private static exactTargetIdFromUrl(type: string, target: JsonObject, rawFeed: JsonObject): string {
    const originalUrl = this.stringValue(target.url);
    const resolvedOriginal = resolveZhihuContent(originalUrl);
    if (resolvedOriginal !== undefined && resolvedOriginal.kind === type) {
      return resolvedOriginal.id;
    }
    const resolvedTarget = resolveZhihuContent(this.resolveTargetUrl(type, target, rawFeed));
    if (resolvedTarget !== undefined && resolvedTarget.kind === type) {
      return resolvedTarget.id;
    }
    return '';
  }

  private static exactQuestionId(question: JsonObject): string {
    const resolved = resolveZhihuContent(this.stringValue(question.url));
    if (resolved !== undefined && resolved.kind === 'question') {
      return resolved.id;
    }
    return this.idValue(question.id);
  }

  private static nativeTargetFromUrl(
    type: string,
    target: JsonObject,
    rawFeed: JsonObject,
    title: string
  ): ZhihuCommentableTarget | undefined {
    const originalUrl = this.stringValue(target.url);
    const resolvedOriginal = resolveZhihuContent(originalUrl);
    const resolvedTarget = resolvedOriginal ?? resolveZhihuContent(this.resolveTargetUrl(type, target, rawFeed));
    if (resolvedTarget === undefined || resolvedTarget.kind !== type) {
      return undefined;
    }
    if (resolvedTarget.kind === 'answer') {
      return {
        kind: 'answer',
        id: resolvedTarget.id,
        questionId: resolvedTarget.questionId,
        title
      };
    }
    return {
      ...resolvedTarget,
      title
    };
  }

  private static extractTopics(question: JsonObject, target: JsonObject, rawFeed?: JsonObject): Array<{ id: string; name: string }> {
    const mapTopics = (src: JsonObject): Array<{ id: string; name: string }> => {
      return this.arrayValue(src.topics)
        .map((t: JsonValue) => {
          const o = this.objectValue(t);
          return { id: this.idValue(o.id), name: this.stringValue(o.name) };
        })
        .filter((t: { id: string; name: string }) => t.id.length > 0 || t.name.length > 0);
    };
    const list = [
      ...mapTopics(question),
      ...mapTopics(target),
      ...(rawFeed !== undefined ? mapTopics(rawFeed) : [])
    ];
    const seen = new Set<string>();
    return list.filter((t: { id: string; name: string }) => {
      const key = t.id.length > 0 ? t.id : t.name;
      if (seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    });
  }

  // 优先用 feed 响应里自带的 topics 对象（含 name，与安卓一致：安卓从 item.raw.question.topics 直接读名字，不反查接口）。
  // 兜底：当 topics 为空时，从 question/target.bound_topic_ids 取数字 ID（此时 name 暂为空，由上层补全或用户手填）。
  private static extractBoundTopicIds(question: JsonObject, target: JsonObject): Array<{ id: string; name: string }> {
    const ids: string[] = [];
    const collect = (src: JsonObject): void => {
      this.arrayValue(src.bound_topic_ids).forEach((v: JsonValue) => {
        const id = this.idValue(v);
        if (id.length > 0 && ids.indexOf(id) < 0) {
          ids.push(id);
        }
      });
    };
    collect(question);
    collect(target);
    return ids.map((id: string) => ({ id, name: '' }));
  }

  private static mergeTopics(
    a: Array<{ id: string; name: string }>,
    b: Array<{ id: string; name: string }>
  ): Array<{ id: string; name: string }> {
    const seen = new Set<string>();
    const out: Array<{ id: string; name: string }> = [];
    for (const t of [...a, ...b]) {
      const key = t.id.length > 0 ? t.id : t.name;
      if (key.length === 0 || seen.has(key)) {
        continue;
      }
      seen.add(key);
      out.push(t);
    }
    return out;
  }

  // 话题名按需从「内容详情 API + include=topics」补全（对齐安卓 FeedDisplayFilterPipeline）：
  // answer 用 answers/{id}?include=question.topics（topics 在响应 question.topics 里），
  // question/article/pin 用各自详情 + include=topics（topics 在响应根 topics 里）。
  // 不走 /topics/{id}（该端点恒 404）。路线 B：仅用户点「按话题屏蔽」时对该条 item 发请求，不影响 feed。
  static async fetchItemTopics(context: common.Context, item: HomeFeedItem): Promise<Array<{ id: string; name: string }>> {
    const native = item.nativeTarget;
    if (native === undefined) {
      return [];
    }
    let url: string = '';
    if (native.kind === 'answer') {
      url = `https://www.zhihu.com/api/v4/answers/${native.id}?include=question.topics`;
    } else if (native.kind === 'question') {
      url = `https://www.zhihu.com/api/v4/questions/${native.id}?include=topics`;
    } else if (native.kind === 'article') {
      url = `https://www.zhihu.com/api/v4/articles/${native.id}?include=topics`;
    } else if (native.kind === 'pin') {
      url = `https://www.zhihu.com/api/v4/pins/${native.id}?include=topics`;
    } else {
      return [];
    }
    try {
      const json = await ZhihuApi.getJson(context, url, { signed: true });
      if (!json) {
        return [];
      }
      const obj = json as JsonObject;
      // answer 的 topics 嵌在 question.topics；其余直接在响应根 topics
      const topicsSrc: JsonObject = native.kind === 'answer' ? this.objectValue(obj.question) : obj;
      const result = this.arrayValue(topicsSrc.topics)
        .map((t: JsonValue) => {
          const o = this.objectValue(t);
          return { id: this.idValue(o.id), name: this.stringValue(o.name) };
        })
        .filter((t: { id: string; name: string }) => t.id.length > 0);
      return result;
    } catch (e) {
      return [];
    }
  }

  private static mapTarget(target: JsonObject, rawFeed: JsonObject): HomeFeedItem | undefined {
    const targetType = this.stringValue(target.type);
    const actionText = this.stringValue(rawFeed.action_text) || this.stringValue(rawFeed.detail_text);
    // 活动动词（VOTEUP/ANSWER/ARTICLE/CREATE_PIN...），用于「赞同了 XX / 想法 / 文章 / 回答」筛选
    const verb = this.stringValue(rawFeed.verb);
    // 发布时间（epoch 秒）：优先内容自身 created_time，回退 created（pin）/ 动态时间线 created_time
    const createdTime =
      this.numberValue(target.created_time) ||
      this.numberValue(target.created) ||
      this.numberValue(rawFeed.created_time);
    const author = this.objectValue(target.author);
    const question = this.objectValue(target.question);
    const authorId = this.idValue(author.id);
    const authorUrlToken = this.stringValue(author.url_token);
    const authorFollowing = this.booleanValue(author.is_following);
    const authorFollowerCount = this.numberValue(author.follower_count);
    const questionAuthorObj = this.objectValue(question.author);
    const questionAuthorId = this.idValue(questionAuthorObj.id);
    const questionAuthorName = this.stringValue(questionAuthorObj.name);
    const topics = this.mergeTopics(
      this.extractTopics(question, target, rawFeed),
      this.extractBoundTopicIds(question, target)
    );
    let nativeTarget: ZhihuCommentableTarget | undefined;

    if (targetType === 'answer') {
      const title = this.stringValue(question.title) || this.stringValue(question.name);
      nativeTarget = this.nativeTargetFromUrl('answer', target, rawFeed, title) ?? {
        kind: 'answer',
        id: this.idValue(target.id),
        questionId: this.exactQuestionId(question),
        title
      };
      const voteCount = this.numberValue(target.voteup_count);
      const commentCount = this.numberValue(target.comment_count);
      return {
        id: this.stableItemId('answer', target, rawFeed),
        type: 'answer',
        title,
        summary: this.stringValue(target.excerpt),
        details: this.joinDetails(`回答 · ${voteCount} 赞同 · ${commentCount} 评论`, actionText),
        authorName: this.stringValue(author.name),
        authorHeadline: this.stringValue(author.headline),
        authorAvatarUrl: this.stringValue(author.avatar_url),
        thumbnailUrl: this.pickThumbnail(target, rawFeed),
        targetUrl: this.resolveTargetUrl('answer', target, rawFeed),
        nativeTarget,
        actionText,
        verb,
        createdTime,
        voteCount,
        commentCount,
        authorId,
        authorUrlToken,
        authorFollowing,
        authorFollowerCount,
        questionAuthorId,
        questionAuthorName,
        topics,
        paidInfo: (target.paid_info ?? target.paidInfo) as object
      };
    }

    if (targetType === 'article') {
      const title = this.stringValue(target.title);
      nativeTarget = this.nativeTargetFromUrl('article', target, rawFeed, title) ?? {
        kind: 'article',
        id: this.idValue(target.id),
        title
      };
      const voteCount = this.numberValue(target.voteup_count);
      const commentCount = this.numberValue(target.comment_count);
      return {
        id: this.stableItemId('article', target, rawFeed),
        type: 'article',
        title,
        summary: this.stringValue(target.excerpt),
        details: this.joinDetails(`文章 · ${voteCount} 赞同 · ${commentCount} 评论`, actionText),
        authorName: this.stringValue(author.name),
        authorHeadline: this.stringValue(author.headline),
        authorAvatarUrl: this.stringValue(author.avatar_url),
        thumbnailUrl: this.pickThumbnail(target, rawFeed),
        targetUrl: this.resolveTargetUrl('article', target, rawFeed),
        nativeTarget,
        actionText,
        verb,
        createdTime,
        voteCount,
        commentCount,
        authorId,
        authorUrlToken,
        authorFollowing,
        authorFollowerCount,
        questionAuthorId,
        questionAuthorName,
        topics,
        paidInfo: (target.paid_info ?? target.paidInfo) as object
      };
    }

    if (targetType === 'question') {
      const title = this.stringValue(target.title) || this.stringValue(target.name);
      nativeTarget = this.nativeTargetFromUrl('question', target, rawFeed, title) ?? {
        kind: 'question',
        id: this.idValue(target.id),
        title
      };
      return {
        id: this.stableItemId('question', target, rawFeed),
        type: 'question',
        title,
        summary: this.stringValue(target.excerpt),
        details: this.joinDetails(`问题 · ${this.numberValue(target.follower_count)} 关注 · ${this.numberValue(target.answer_count)} 回答`, actionText),
        authorName: '',
        authorHeadline: '',
        authorAvatarUrl: '',
        thumbnailUrl: this.pickThumbnail(target, rawFeed),
        targetUrl: this.resolveTargetUrl('question', target, rawFeed),
        nativeTarget,
        actionText,
        verb,
        createdTime,
        voteCount: 0,
        commentCount: this.numberValue(target.answer_count),
        questionFollowerCount: this.numberValue(target.follower_count),
        authorId,
        authorUrlToken,
        authorFollowing,
        authorFollowerCount,
        questionAuthorId,
        questionAuthorName,
        topics
      };
    }

    if (targetType === 'pin') {
      const authorName = this.stringValue(author.name);
      const title = authorName.length > 0 ? `${authorName}的想法` : '想法';
      nativeTarget = this.nativeTargetFromUrl('pin', target, rawFeed, title) ?? {
        kind: 'pin',
        id: this.idValue(target.id),
        title
      };
      return {
        id: this.stableItemId('pin', target, rawFeed),
        type: 'pin',
        title,
        summary: stripHtmlToText(this.stringValue(target.excerpt_title)),
        details: this.joinDetails(`想法 · ${this.numberValue(target.like_count)} 赞 · ${this.numberValue(target.comment_count)} 评论`, actionText),
        authorName,
        authorHeadline: this.stringValue(author.headline),
        authorAvatarUrl: this.stringValue(author.avatar_url),
        thumbnailUrl: this.pickThumbnail(target, rawFeed),
        targetUrl: this.resolveTargetUrl('pin', target, rawFeed),
        nativeTarget,
        actionText,
        verb,
        createdTime,
        voteCount: this.numberValue(target.like_count),
        commentCount: this.numberValue(target.comment_count),
        authorId,
        authorUrlToken,
        authorFollowing,
        authorFollowerCount,
        questionAuthorId,
        questionAuthorName,
        topics
      };
    }

    if (targetType === 'zvideo') {
      const id = this.idValue(target.id);
      if (id.length === 0) {
        return undefined;
      }
      const title = this.stringValue(target.title) || '视频';
      const authorName = this.stringValue(author.name);
      const authorHeadline = this.stringValue(author.headline);
      const authorAvatarUrl = this.stringValue(author.avatar_url);
      const playCount = this.numberValue(target.play_count) || this.numberValue(target.playCount);
      const thumbnailUrl = this.pickThumbnail(target, rawFeed);
      const videoUrl = 'https://www.zhihu.com/zvideo/' + id;
      return {
        id: this.stableItemId('zvideo', target, rawFeed),
        type: 'zvideo',
        title,
        summary: '',
        details: `视频 · ${playCount > 0 ? playCount + ' 播放' : '知乎视频'}`,
        authorName,
        authorHeadline,
        authorAvatarUrl,
        thumbnailUrl,
        targetUrl: videoUrl,
        nativeTarget: undefined,
        actionText,
        verb,
        createdTime,
        voteCount: this.numberValue(target.voteup_count),
        commentCount: 0,
        videoId: id,
        contentId: id,
        contentType: 'video',
        authorId,
        authorFollowing,
        authorFollowerCount,
        authorUrlToken,
        questionAuthorId,
        questionAuthorName,
        topics
      };
    }

    return undefined;
  }

  private static mapRawFeed(rawFeed: JsonObject): HomeFeedItem[] {
    const type = this.stringValue(rawFeed.type);
    // 安卓端推荐（带安卓头时）返回的是 ComponentCard 结构（内容在 children[] 里，而非 target），
    // 与 web 的 target 结构完全不同，需单独解析。
    if (type === 'ComponentCard') {
      const item = this.mapAndroidComponentCard(rawFeed);
      return item === undefined ? [] : [item];
    }
    if (type === 'feed_group') {
      return this.arrayValue(rawFeed.list)
        .map((item: JsonValue) => this.objectValue(item))
        .flatMap((item: JsonObject) => this.mapRawFeed(item));
    }
    if (type === 'hot_list_feed') {
      const target = this.objectValue(rawFeed.target);
      const children = this.arrayValue(rawFeed.children);
      const childThumbnail = children.length > 0 ? this.stringValue(this.objectValue(children[0]).thumbnail) : '';
      const mapped = this.mapTarget(target, {
        ...rawFeed,
        action_text: this.stringValue(rawFeed.detail_text) || this.stringValue(rawFeed.detailText),
        children
      });
      if (mapped === undefined || mapped.title.length === 0 || mapped.targetUrl.length === 0) {
        return [];
      }
      return [{
        ...mapped,
        id: `hot:${mapped.id}`,
        authorName: '',
        authorHeadline: '',
        authorAvatarUrl: '',
        thumbnailUrl: childThumbnail.length > 0 ? childThumbnail : mapped.thumbnailUrl,
        actionText: mapped.actionText.length > 0 ? mapped.actionText : '热榜'
      }];
    }
    if (type === 'feed_advert' || type.length === 0) {
      return [];
    }

    const mapped = this.mapTarget(this.objectValue(rawFeed.target), rawFeed);
    if (mapped === undefined || mapped.title.length === 0 || mapped.targetUrl.length === 0) {
      return [];
    }
    return [mapped];
  }

  // 解析安卓端 ComponentCard：从 action.parameter 抽取 route_url，从 children[] 按 id/style/type 抽取
  // 标题、作者、点赞数等，构造与 web 同构的 HomeFeedItem（对齐安卓 parseMobileHomeFeedDisplayItem）。
  private static mapAndroidComponentCard(card: JsonObject): HomeFeedItem | undefined {
    const action = this.objectValue(card.action);
    const parameter = this.stringValue(action.parameter);
    const marker = 'route_url=';
    const idx = parameter.indexOf(marker);
    if (idx < 0) {
      console.warn('[ANDROID_FEED] ComponentCard 缺少 route_url');
      return undefined;
    }
    let routeUrl = parameter.substring(idx + marker.length);
    const amp = routeUrl.indexOf('&');
    if (amp >= 0) {
      routeUrl = routeUrl.substring(0, amp);
    }
    try {
      routeUrl = decodeURIComponent(routeUrl);
    } catch (_e) {
      // 保留原文
    }
    const resolved = resolveZhihuContent(routeUrl);
    if (resolved === undefined) {
      console.warn('[ANDROID_FEED] 无法解析 route_url: ' + routeUrl);
      return undefined;
    }
    const children = this.arrayOfObjects(card.children);
    const title = this.androidChildText(children, 'id', 'Text');
    if (title.length === 0) {
      return undefined;
    }
    const summary = this.androidChildText(children, 'id', 'text_pin_summary');
    // 作者行（RecommendAuthorLine / LineAuthor_default）
    let authorName = '';
    let authorAvatarUrl = '';
    const authorLine = children.find((c: JsonObject) => {
      const style = this.stringValue(c.style);
      return style.startsWith('RecommendAuthorLine') || style.startsWith('LineAuthor_default');
    });
    if (authorLine !== undefined) {
      const elements = this.arrayOfObjects(authorLine.elements);
      const avatarEl = elements.find((e: JsonObject) => this.stringValue(e.style) === 'Avatar_default');
      if (avatarEl !== undefined) {
        authorAvatarUrl = this.stringValue(this.objectValue(avatarEl.image).url);
      }
      authorName = this.androidChildText(elements, 'type', 'Text');
    }
    // 底部数据行（第二个 Line）：点赞/评论/收藏数，或纯文本
    let footerText = '';
    const lines = children.filter((c: JsonObject) => this.stringValue(c.type) === 'Line');
    const footerLine = lines.length > 1 ? lines[1] : undefined;
    if (footerLine !== undefined) {
      const footerEls = this.arrayOfObjects(footerLine.elements);
      const vote = footerEls.find((e: JsonObject) => this.stringValue(e.reaction) === 'Vote');
      const comment = footerEls.find((e: JsonObject) => this.stringValue(e.reaction) === 'Comment');
      const collect = footerEls.find((e: JsonObject) => this.stringValue(e.reaction) === 'Collect');
      if (vote !== undefined && comment !== undefined && collect !== undefined) {
        footerText = `${this.numberValue(vote.count)} 赞同 · ${this.numberValue(comment.count)} 评论 · ${this.numberValue(collect.count)} 收藏`;
      } else {
        footerText = this.androidChildText(footerEls, 'type', 'Text');
      }
    }
    // 作者关注状态（用于「屏蔽未关注作者」过滤；仅当接口明确给出 true/false 才判定，缺失视为未知→不过滤）
    const cardAuthorObj = this.objectValue(card.author);
    const rawFollowing = cardAuthorObj.is_following;
    const authorFollowing = rawFollowing === true ? true : (rawFollowing === false ? false : undefined);
    return {
      id: `android:${resolved.kind}:${resolved.id}`,
      type: resolved.kind,
      title,
      summary,
      details: this.joinDetails(footerText, '手机版推荐'),
      authorName,
      authorHeadline: '',
      authorAvatarUrl,
      thumbnailUrl: '',
      targetUrl: contentTargetUrl(resolved),
      nativeTarget: resolved,
      actionText: '手机版推荐',
      verb: this.stringValue(card.verb),
      createdTime: this.numberValue(card.created_time) || this.numberValue(card.feed_created_time),
      voteCount: 0,
      commentCount: 0,
      authorId: '',
      authorUrlToken: '',
      authorFollowing,
      questionAuthorId: '',
      questionAuthorName: '',
      topics: []
    };
  }

  private static androidChildText(children: JsonObject[], key: string, value: string): string {
    const found = children.find((c: JsonObject) => this.stringValue(c[key]) === value);
    if (found === undefined) {
      return '';
    }
    return this.stringValue(found.text);
  }

  private static mapPage(payload: JsonObject): HomeFeedPage {
    const data = this.arrayValue(payload.data);
    const items = data
      .map((item: JsonValue) => this.objectValue(item))
      .flatMap((item: JsonObject) => this.mapRawFeed(item));
    const paging = this.objectValue(payload.paging);
    const rawNext = this.stringValue(paging.next);
    // 归一化为绝对 URL：知乎 topstory/recommend（尤其带安卓头时）返回的 paging.next 可能是相对路径，
    // 直接用于签名请求会失败或回退到首屏，导致「加载更多」永远拉不到下一页。
    const nextUrl = rawNext.length > 0 && !rawNext.startsWith('http')
      ? `https://www.zhihu.com${rawNext.startsWith('/') ? '' : '/'}${rawNext}`
      : rawNext;
    return {
      items,
      paging: {
        isEnd: paging.is_end === true,
        nextUrl
      }
    };
  }

  static mapSearchPage(payload: Object): HomeFeedPage {
    const jsonPayload = payload as JsonObject;
    const data = this.arrayValue(jsonPayload.data);
    const items = data
      .map((item: JsonValue) => this.objectValue(item))
      .flatMap((item: JsonObject): HomeFeedItem[] => {
        if (this.stringValue(item.type) !== 'search_result') {
          return [];
        }
        const target = this.objectValue(item.object);
        const rawFeed: JsonObject = {
          id: this.idValue(item.id),
          target,
          action_text: '搜索结果'
        };
        const mapped = this.mapTarget(target, rawFeed);
        if (mapped === undefined || mapped.title.length === 0 || mapped.targetUrl.length === 0) {
          return [];
        }
        const titleHighlight = this.highlightValue(item, 'title');
        const summaryHighlight = this.highlightValue(item, 'description') || this.highlightValue(item, 'excerpt');
        const titleHighlightSegments = titleHighlight.length > 0 ? this.parseHighlightSegments(titleHighlight) : undefined;
        const summaryHighlightSegments = summaryHighlight.length > 0 ? this.parseHighlightSegments(summaryHighlight) : undefined;
        return [{
          ...mapped,
          id: `search:${mapped.id}`,
          title: titleHighlight.length > 0 ? stripHtmlToText(titleHighlight) : stripHtmlToText(mapped.title),
          summary: summaryHighlight.length > 0 ? stripHtmlToText(summaryHighlight) : stripHtmlToText(mapped.summary),
          titleHighlightSegments,
          summaryHighlightSegments,
          actionText: mapped.actionText.length > 0 ? mapped.actionText : '搜索结果'
        }];
      });
    const paging = this.objectValue(jsonPayload.paging);
    const rawNext = this.stringValue(paging.next);
    // 归一化为绝对 URL：Zhihu 的 paging.next 有时返回相对路径，直接用于签名请求会失败，
    // 导致无法加载后续内容（offset/limit 分页失效）。
    const nextUrl = rawNext.length > 0 && !rawNext.startsWith('http')
      ? `https://www.zhihu.com${rawNext.startsWith('/') ? '' : '/'}${rawNext}`
      : rawNext;
    return {
      items,
      paging: {
        isEnd: paging.is_end === true,
        nextUrl
      }
    };
  }

  static mapHotListPage(payload: Object): HomeFeedPage {
    return this.mapPage(payload as JsonObject);
  }

  static mapQuestionFeedPage(payload: Object, questionId: string, questionTitle: string): HomeFeedPage {
    const jsonPayload = payload as JsonObject;
    const data = this.arrayValue(jsonPayload.data);
    const items = data
      .map((item: JsonValue) => this.objectValue(item))
      .flatMap((item: JsonObject): HomeFeedItem[] => {
        const target = this.objectValue(item.target);
        const targetType = this.stringValue(item.target_type) || this.stringValue(target.type);
        if (targetType.length === 0) {
          return [];
        }
        const normalizedTarget: JsonObject = {
          ...target,
          type: targetType
        };
        const mapped = this.mapTarget(normalizedTarget, item);
        if (mapped === undefined) {
          return [];
        }
        if (mapped.type !== 'answer') {
          return [mapped];
        }
        const native = mapped.nativeTarget;
        const answerId = native !== undefined && native.kind === 'answer' && native.id.length > 0
          ? native.id
          : this.idValue(target.id);
        if (answerId.length === 0) {
          return [];
        }
        const resolvedQuestionId = native !== undefined && native.kind === 'answer'
          && typeof native.questionId === 'string' && native.questionId.length > 0
          ? native.questionId
          : questionId;
        const patchedNative: ZhihuCommentableTarget = {
          kind: 'answer',
          id: answerId,
          questionId: resolvedQuestionId,
          title: mapped.title.length > 0 ? mapped.title : questionTitle
        };
        return [{
          ...mapped,
          id: `question-answer:${answerId}`,
          title: mapped.title.length > 0 ? mapped.title : questionTitle,
          nativeTarget: patchedNative,
          targetUrl: `https://www.zhihu.com/question/${resolvedQuestionId}/answer/${answerId}`
        }];
      });
    const paging = this.objectValue(jsonPayload.paging);
    const rawNext = this.stringValue(paging.next);
    // 归一化为绝对 URL：Zhihu 的 paging.next 有时返回相对路径，直接用于签名请求会失败，
    // 导致无法加载后续内容（offset/limit 分页失效）。
    const nextUrl = rawNext.length > 0 && !rawNext.startsWith('http')
      ? `https://www.zhihu.com${rawNext.startsWith('/') ? '' : '/'}${rawNext}`
      : rawNext;
    return {
      items,
      paging: {
        isEnd: paging.is_end === true,
        nextUrl
      }
    };
  }

  // guest=true 时游客请求（不携带 session cookie）；false 时用 session cookie（默认行为）
  static async loadFirstPage(context: common.Context, opts?: { guest?: boolean }): Promise<HomeFeedPage> {
    const rawAlgo = FilterSettingsRepository.getStr(context, FILTER_KEYS.recommendAlgo, 'mixed');
    const algo: RecommendAlgo = (rawAlgo === 'web' || rawAlgo === 'android' || rawAlgo === 'mixed') ? rawAlgo : 'mixed';
    const guest = opts?.guest === true;
    const cookies: Record<string, string> | undefined = guest ? {} : undefined;

    // web：普通网页端推荐
    if (algo === 'web') {
      this.nextPageAlgo = 'web';
      this.nextPageGuest = guest;
      return this.loadSignedPage(context, this.INITIAL_URL, { headers: {}, cookies });
    }
    if (algo === 'android') {
      this.nextPageAlgo = 'android';
      this.nextPageGuest = guest;
      return this.loadSignedPage(context, this.INITIAL_URL, { headers: this.ANDROID_HEADERS, cookies });
    }
    // mixed：web + 安卓端并行双拉，web 必拉、安卓端失败则回退 web
    this.nextPageAlgo = 'web';
    this.nextPageGuest = guest;
    const webPromise = this.loadSignedPage(context, this.INITIAL_URL, { headers: {}, cookies });
    const androidPromise = this.loadSignedPage(context, this.INITIAL_URL, { headers: this.ANDROID_HEADERS, cookies })
      .catch(() => null);
    const webPage = await webPromise;
    const androidPage = await androidPromise;
    if (androidPage === null) {
      return webPage;
    }
    return this.mergePages(webPage, androidPage);
  }

  static async loadNextPage(context: common.Context, nextUrl: string): Promise<HomeFeedPage> {
    const headers = this.nextPageAlgo === 'android' ? this.ANDROID_HEADERS : {};
    const cookies: Record<string, string> | undefined = this.nextPageGuest ? {} : undefined;
    return this.loadSignedPage(context, nextUrl, { headers, cookies });
  }

  static async loadSignedPage(context: common.Context, url: string, opts?: FeedLoadOptions): Promise<HomeFeedPage> {
    const headers: Record<string, string> = opts?.headers ?? {};
    const cookies: Record<string, string> | undefined = opts?.cookies;
    const payload = await ZhihuApi.getJson(context, url, {
      signed: true,
      headers: headers,
      cookies: cookies
    });
    if (payload === null) {
      throw new Error('主页内容为空');
    }
    return this.mapPage(payload as JsonObject);
  }

  // 混合推荐：web 与安卓端结果交错合并、按 id 去重（web 的 paging 作为后续翻页依据）
  private static mergePages(a: HomeFeedPage, b: HomeFeedPage): HomeFeedPage {
    const seen = new Set<string>();
    const items: HomeFeedItem[] = [];
    const aItems = a.items;
    const bItems = b.items;
    const max = Math.max(aItems.length, bItems.length);
    for (let i = 0; i < max; i++) {
      if (i < aItems.length) {
        const it = aItems[i];
        if (!seen.has(it.id)) {
          seen.add(it.id);
          items.push(it);
        }
      }
      if (i < bItems.length) {
        const it = bItems[i];
        if (!seen.has(it.id)) {
          seen.add(it.id);
          items.push(it);
        }
      }
    }
    return { items, paging: a.paging };
  }

  // —— 启动缓存快照（关闭「启动时自动刷新首页」时优先展示）——
  static saveHomeSnapshot(context: common.Context, items: HomeFeedItem[]): void {
    try {
      const store = preferences.getPreferencesSync(context, { name: 'zhihu_filter' });
      const slice = items.slice(0, this.HOME_SNAPSHOT_MAX);
      store.putSync(this.HOME_SNAPSHOT_KEY, JSON.stringify(slice));
      store.flushSync();
    } catch (_e) {
      // 缓存写入失败不应影响正常流程
    }
  }

  static loadHomeSnapshot(context: common.Context): HomeFeedItem[] {
    try {
      const store = preferences.getPreferencesSync(context, { name: 'zhihu_filter' });
      const raw = store.getSync(this.HOME_SNAPSHOT_KEY, '') as string;
      if (raw.length === 0) {
        return [];
      }
      const parsed = JSON.parse(raw) as HomeFeedItem[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (_e) {
      return [];
    }
  }

  // 清空启动快照（切换/登出账号时调用，避免旧账号首页缓存被回显导致串号）
  static clearHomeSnapshot(context: common.Context): void {
    try {
      const store = preferences.getPreferencesSync(context, { name: 'zhihu_filter' });
      store.putSync(this.HOME_SNAPSHOT_KEY, '');
      store.flushSync();
    } catch (_e) {
      // 缓存清除失败不应影响正常流程
    }
  }

  // 收藏夹内容条目里的 content 对象与 topstory 的 target 同构，
  // 这里复用私有的 mapTarget 把它映射成 HomeFeedItem（过滤掉无标题/无链接的脏数据）。
  static mapCollectionItem(rawContent: Object): HomeFeedItem | undefined {
    const content = rawContent as JsonObject;
    const rawFeed: JsonObject = {
      type: this.stringValue(content.type),
      target: content,
      action_text: ''
    };
    const mapped = this.mapTarget(this.objectValue(rawFeed.target), rawFeed);
    if (mapped === undefined || mapped.title.length === 0 || mapped.targetUrl.length === 0) {
      return undefined;
    }
    return mapped;
  }

  // 把收藏夹内容接口返回的 data[]（每项含 content）转成 HomeFeedItem 列表
  static mapCollectionContentPage(payload: Object): HomeFeedPage {
    const jsonPayload = payload as JsonObject;
    const data = this.arrayValue(jsonPayload.data);
    const items = data
      .map((item: JsonValue) => this.mapCollectionItem(this.objectValue(this.objectValue(item as JsonObject).content)))
      .filter((item: HomeFeedItem | undefined): item is HomeFeedItem => item !== undefined);
    const paging = this.objectValue(jsonPayload.paging);
    return {
      items,
      paging: {
        isEnd: paging.is_end === true,
        nextUrl: this.stringValue(paging.next)
      }
    };
  }
}
