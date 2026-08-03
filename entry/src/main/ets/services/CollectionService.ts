import common from '@ohos.app.ability.common';
import { ZhihuApi } from './ZhihuApi';
import { HomeFeedService } from './HomeFeedService';
import {
  CollectionPage,
  HomeFeedItem,
  HomeFeedPage,
  ZhihuCollection
} from '../models/ZhihuModels';
import { ZhihuCommentableTarget } from '../models/ZhihuContentModels';

type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];

interface JsonObject {
  [key: string]: JsonValue;
}

// 收藏夹相关 API（对齐安卓 CollectionViewModel / CollectionsViewModel / CollectionContentViewModel）
// 注意：api.zhihu.com 与 www.zhihu.com 两个域名的接口都需要签名请求。
export class CollectionService {
  private static stringValue(value: JsonValue | undefined): string {
    if (typeof value === 'string') {
      return value;
    }
    // 知乎 API 的 id 常为数字（如 1004316803），需转成字符串，否则会被后续的 id.length>0 过滤掉
    if (typeof value === 'number') {
      return String(value);
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

  private static booleanValue(value: JsonValue | undefined): boolean {
    return value === true;
  }

  private static objectValue(value: JsonValue | undefined): JsonObject {
    return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as JsonObject : {};
  }

  private static arrayValue(value: JsonValue | undefined): JsonValue[] {
    return Array.isArray(value) ? value : [];
  }

  // 若响应体带有 error 字段（知乎常返回 200 + {error:{message}}），抛出以便上层显示，避免静默空数据
  private static errorText(payload: JsonObject): string {
    const err = payload.error;
    if (err === undefined || err === null) {
      return '';
    }
    if (typeof err === 'string') {
      return err;
    }
    if (typeof err === 'object' && !Array.isArray(err)) {
      const obj = err as JsonObject;
      return this.stringValue(obj.message) || this.stringValue(obj.msg) || this.stringValue(obj.description);
    }
    return '';
  }

  // 把知乎收藏夹原始对象归一化为 ZhihuCollection
  private static mapCollection(raw: JsonObject): ZhihuCollection {
    return {
      id: this.stringValue(raw.id),
      title: this.stringValue(raw.title),
      description: this.stringValue(raw.description),
      isFavorited: this.booleanValue(raw.is_favorited) || this.booleanValue(raw.isFavorited),
      isPublic: this.booleanValue(raw.is_public) || this.booleanValue(raw.isPublic),
      itemCount: this.numberValue(raw.item_count) || this.numberValue(raw.itemCount),
      likeCount: this.numberValue(raw.like_count) || this.numberValue(raw.likeCount),
      commentCount: this.numberValue(raw.comment_count) || this.numberValue(raw.commentCount),
      viewCount: this.numberValue(raw.view_count) || this.numberValue(raw.viewCount),
      updatedTime: this.numberValue(raw.updated_time) || this.numberValue(raw.updatedTime),
      isDefault: this.booleanValue(raw.is_default) || this.booleanValue(raw.isDefault)
    };
  }

  // 我的收藏夹列表：GET https://www.zhihu.com/api/v4/people/{urlToken}/collections
  static async loadUserCollections(
    context: common.Context,
    urlToken: string,
    nextUrl?: string
  ): Promise<CollectionPage> {
    const url = nextUrl && nextUrl.length > 0
      ? nextUrl
      : `https://www.zhihu.com/api/v4/people/${urlToken}/collections`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('收藏夹列表为空');
    }
    const jsonPayload = payload as JsonObject;
    const errMsg = this.errorText(jsonPayload);
    if (errMsg.length > 0) {
      throw new Error(errMsg);
    }
    const items = this.arrayValue(jsonPayload.data)
      .map((item: JsonValue) => this.mapCollection(this.objectValue(item)))
      .filter((item: ZhihuCollection) => item.id.length > 0);
    const paging = this.objectValue(jsonPayload.paging);
    return {
      items,
      isEnd: this.booleanValue(paging.is_end),
      nextUrl: this.stringValue(paging.next)
    };
  }

  // 某条内容已加入的收藏夹列表（含 isFavorited 状态）：
  // GET https://api.zhihu.com/collections/contents/{type}/{id}?limit=50
  // 调用后可通过 lastRawResponse 获取原始响应文本用于诊断
  static lastRawResponse: string = '';

  static async loadCollectionsForContent(
    context: common.Context,
    target: ZhihuCommentableTarget
  ): Promise<ZhihuCollection[]> {
    const contentType = target.kind === 'answer' || target.kind === 'article' ? target.kind : '';
    if (contentType.length === 0) {
      const msg = `[CollectionService] loadCollectionsForContent: 不支持的 kind="${target.kind}"`;
      console.warn(msg);
      throw new Error(`不支持的内容类型：${target.kind}`);
    }
    const url = `https://api.zhihu.com/collections/contents/${contentType}/${target.id}?limit=50`;
    console.info(`[CollectionService] GET ${url}`);
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      const msg = `[CollectionService] loadCollectionsForContent: 返回为空(null)，可能请求失败或未登录`;
      console.warn(msg);
      throw new Error('API返回为空，请检查网络和登录状态');
    }
    const jsonPayload = payload as JsonObject;
    // 记录原始响应（截断避免过长）
    try {
      const rawStr = JSON.stringify(jsonPayload);
      CollectionService.lastRawResponse = rawStr.length > 2000 ? rawStr.substring(0, 2000) + '...(截断)' : rawStr;
      console.info(`[CollectionService] 原始响应长度: ${rawStr.length}, 前500字: ${rawStr.substring(0, 500)}`);
    } catch (e) {
      CollectionService.lastRawResponse = '(无法序列化响应)';
    }
    // 打印原始响应结构（脱敏）用于调试
    const keys = Object.keys(jsonPayload);
    const dataLen = Array.isArray(jsonPayload.data) ? jsonPayload.data.length : 'not array';
    console.info(`[CollectionService] 响应顶层keys: [${keys.join(', ')}], data长度: ${dataLen}`);
    const errMsg = this.errorText(jsonPayload);
    if (errMsg.length > 0) {
      console.error(`[CollectionService] 接口返回error字段: ${errMsg}`);
      throw new Error(errMsg);
    }
    const items = this.arrayValue(jsonPayload.data)
      .map((item: JsonValue) => this.mapCollection(this.objectValue(item)))
      .filter((item: ZhihuCollection) => item.id.length > 0);
    console.info(`[CollectionService] 解析完成，有效收藏夹数: ${items.length}`);
    return items;
  }

  // 收藏 / 取消收藏：PUT https://api.zhihu.com/collections/contents/{type}/{id}
  // 表单编码 body：add_collections={id} 或 remove_collections={id}
  static async toggleFavorite(
    context: common.Context,
    target: ZhihuCommentableTarget,
    collectionId: string,
    remove: boolean
  ): Promise<void> {
    const contentType = target.kind === 'answer' || target.kind === 'article' ? target.kind : '';
    if (contentType.length === 0) {
      throw new Error('该内容类型不支持收藏');
    }
    const url = `https://api.zhihu.com/collections/contents/${contentType}/${target.id}`;
    const action = remove ? 'remove' : 'add';
    const body = `${action}_collections=${collectionId}`;
    console.info(`[CollectionService] PUT ${url} body=${body}`);
    const result = await ZhihuApi.putJson(context, url, {
      signed: true,
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    });
    if (result === null) {
      console.error(`[CollectionService] toggleFavorite 返回为空`);
      throw new Error('收藏操作未返回结果');
    }
    console.info(`[CollectionService] toggleFavorite 成功`);
  }

  // 新建收藏夹：POST https://www.zhihu.com/api/v4/collections （JSON）
  static async createCollection(
    context: common.Context,
    title: string,
    description: string,
    isPublic: boolean
  ): Promise<void> {
    const url = 'https://www.zhihu.com/api/v4/collections';
    const body = JSON.stringify({
      title,
      description,
      is_public: isPublic
    });
    console.info(`[CollectionService] POST ${url} title="${title}"`);
    const result = await ZhihuApi.postJson(context, url, {
      signed: true,
      headers: { 'Content-Type': 'application/json' },
      body
    });
    if (result === null) {
      console.error(`[CollectionService] createCollection 返回为空`);
      throw new Error('新建收藏夹未返回结果');
    }
    // 检查创建接口是否返回了 error
    const jsonResult = result as JsonObject;
    const errMsg = this.errorText(jsonResult);
    if (errMsg.length > 0) {
      console.error(`[CollectionService] createCollection 接口返回error: ${errMsg}`);
      throw new Error(errMsg);
    }
    console.info(`[CollectionService] createCollection 成功`);
  }

  // 收藏夹信息：GET https://www.zhihu.com/api/v4/collections/{id} → 取 collection 字段
  static async loadCollectionInfo(context: common.Context, collectionId: string): Promise<ZhihuCollection | undefined> {
    const url = `https://www.zhihu.com/api/v4/collections/${collectionId}`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      return undefined;
    }
    const jsonPayload = payload as JsonObject;
    const raw = this.objectValue(jsonPayload.collection);
    if (this.stringValue(raw.id).length === 0) {
      return undefined;
    }
    return this.mapCollection(raw);
  }

  // 收藏夹内容条目：GET https://www.zhihu.com/api/v4/collections/{id}/items
  // 复用 HomeFeedService 的 FeedItem 解析（content 与 topstory target 同构）
  static async loadCollectionItems(
    context: common.Context,
    collectionId: string,
    nextUrl?: string
  ): Promise<HomeFeedPage> {
    const url = nextUrl && nextUrl.length > 0
      ? nextUrl
      : `https://www.zhihu.com/api/v4/collections/${collectionId}/items`;
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('收藏夹内容为空');
    }
    return HomeFeedService.mapCollectionContentPage(payload as Object);
  }
}
