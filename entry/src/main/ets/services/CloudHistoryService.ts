/*
 * Zhihu++ - Free & Ad-Free Zhihu client for all platforms.
 * Copyright (C) 2024-2026, zly2006 <i@zly2006.me>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation (version 3 only).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import common from '@ohos.app.ability.common';
import { ZhihuApi } from './ZhihuApi';
import { HomeFeedItem } from '../models/ZhihuModels';
import { ZhihuCommentableTarget, contentTargetUrl } from '../models/ZhihuContentModels';

// ==============================
// 云端历史数据模型
// ==============================

export interface CloudHistoryItem {
  readonly cardType: string;
  readonly data: CloudHistoryData;
}

export interface CloudHistoryData {
  readonly header: CloudHistoryHeader;
  readonly content?: CloudHistoryContent;
  readonly action: CloudHistoryAction;
  readonly extra: CloudHistoryExtra;
  readonly matrix?: CloudHistoryMatrixItem[];
}

export interface CloudHistoryMatrixItem {
  readonly type: string;
  readonly data: CloudHistoryMatrixData;
}

export interface CloudHistoryMatrixData {
  readonly text: string;
}

export interface CloudHistoryHeader {
  readonly icon: string;
  readonly title: string;
  readonly action?: CloudHistoryAction;
}

export interface CloudHistoryContent {
  readonly authorName?: string;
  readonly summary?: string;
  readonly coverImage?: string;
}

export interface CloudHistoryAction {
  readonly type: string;
  readonly url: string;
}

export interface CloudHistoryExtra {
  readonly contentToken: string;
  readonly contentType: string;
  readonly readTime: number;
  readonly questionToken: string;
}

export interface CloudHistoryPage {
  readonly data: CloudHistoryItem[];
  readonly paging: {
    readonly isEnd: boolean;
    readonly next?: string;
  };
}

// ==============================
// 云端历史 Service
// ==============================

const CLOUD_HISTORY_LIMIT: number = 20;

export class CloudHistoryService {
  /**
   * 拉取云端历史记录（分页）
   * GET /unify-consumption/read_history?offset=0&limit=20
   */
  static async fetchHistory(
    context: common.Context,
    offset: number = 0,
    limit: number = CLOUD_HISTORY_LIMIT
  ): Promise<CloudHistoryPage> {
    const url = `https://api.zhihu.com/unify-consumption/read_history?offset=${offset}&limit=${limit}`;
    const response = await ZhihuApi.getJson(context, url, { signed: true });
    if (response === null) {
      return { data: [], paging: { isEnd: true } };
    }
    return this.parseHistoryPage(response);
  }

  /**
   * 从 paging.next 继续加载更多
   */
  static async fetchNextPage(context: common.Context, nextUrl: string): Promise<CloudHistoryPage> {
    const response = await ZhihuApi.getJson(context, nextUrl, { signed: true });
    if (response === null) {
      return { data: [], paging: { isEnd: true } };
    }
    return this.parseHistoryPage(response);
  }

  /**
   * 上报阅读历史到云端
   * POST /api/v4/read_history/add
   * body: { "content_token": "...", "content_type": "answer|article|question|pin" }
   * 可选：question_token
   */
  static async reportHistory(
    context: common.Context,
    contentToken: string,
    contentType: string,
    questionToken?: string
  ): Promise<void> {
    const url = 'https://www.zhihu.com/api/v4/read_history/add';
    const bodyObj: Record<string, string> = {
      content_token: contentToken,
      content_type: contentType
    };
    if (questionToken !== undefined && questionToken.length > 0) {
      bodyObj.question_token = questionToken;
    }
    try {
      await ZhihuApi.postJson(context, url, {
        signed: true,
        body: JSON.stringify(bodyObj),
        allowUnauthorized: true
      });
    } catch (_) {
      // 静默失败 – 上报历史不应阻断用户操作
    }
  }

  /**
   * 通过 ZhihuCommentableTarget 上报
   */
  static async reportViaTarget(
    context: common.Context,
    target: ZhihuCommentableTarget
  ): Promise<void> {
    const contentToken = target.id;
    const contentType = target.kind;
    const questionToken = target.kind === 'answer' ? target.questionId : undefined;
    return this.reportHistory(context, contentToken, contentType, questionToken);
  }

  /**
   * 清除云端历史
   * POST /api.zhihu.com/read_history/batch_del
   * body: { "tokens": [...] }
   */
  static async clearHistory(context: common.Context): Promise<void> {
    const url = 'https://api.zhihu.com/read_history/batch_del';
    try {
      await ZhihuApi.postJson(context, url, {
        signed: true,
        body: JSON.stringify({ pairs: [], clear: true }),
        allowUnauthorized: true
      });
    } catch (_) {
      // 静默失败
    }
  }

  /**
   * 删除单条云端历史（对齐安卓 batch_del）
   * POST /api.zhihu.com/read_history/batch_del
   * body: { "pairs": [{ "content_token": "...", "content_type": "..." }], "clear": false }
   */
  static async deleteHistoryItem(
    context: common.Context,
    contentToken: string,
    contentType: string
  ): Promise<void> {
    const url = 'https://api.zhihu.com/read_history/batch_del';
    const bodyObj = {
      pairs: [{ content_token: contentToken, content_type: contentType }],
      clear: false
    };
    try {
      await ZhihuApi.postJson(context, url, {
        signed: true,
        body: JSON.stringify(bodyObj),
        allowUnauthorized: true
      });
    } catch (_) {
      // 静默失败
    }
  }

  /**
   * 将云端历史条目映射为 HomeFeedItem（复用现有卡片 UI）
   */
  static mapToHomeFeedItems(items: CloudHistoryItem[]): HomeFeedItem[] {
    return items
      .map((item: CloudHistoryItem, index: number): HomeFeedItem | undefined => {
        const d = item.data;
        const extra = d.extra;
        const content = d.content;
        const action = d.action;

        // 确定 type
        let feedType: 'answer' | 'article' | 'question' | 'pin' | 'message' = 'article';
        if (extra.contentType === 'answer') {
          feedType = 'answer';
        } else if (extra.contentType === 'article') {
          feedType = 'article';
        } else if (extra.contentType === 'question') {
          feedType = 'question';
        } else if (extra.contentType === 'pin') {
          feedType = 'pin';
        }

        const title = d.header.title;
        if (title.length === 0 && (content === undefined || (content.summary ?? '').length === 0)) {
          return undefined;
        }

        const targetUrl = action.url.length > 0 ? action.url : '';
        const summary = content?.summary ?? '';
        const authorName = content?.authorName ?? '';
        const thumbnailUrl = content?.coverImage ?? '';

        // 构建 nativeTarget（用于导航）
        let nativeTarget: ZhihuCommentableTarget | undefined;
        if (extra.contentType === 'answer') {
          nativeTarget = {
            kind: 'answer',
            id: extra.contentToken,
            questionId: extra.questionToken.length > 0 ? extra.questionToken : undefined,
            title
          };
        } else if (extra.contentType === 'article') {
          nativeTarget = { kind: 'article', id: extra.contentToken, title };
        } else if (extra.contentType === 'question') {
          nativeTarget = { kind: 'question', id: extra.contentToken, title };
        } else if (extra.contentType === 'pin') {
          nativeTarget = { kind: 'pin', id: extra.contentToken, title };
        }

        // 格式化阅读时间
        const readTimeText = this.formatReadTime(extra.readTime);

        return {
          id: `cloud:${extra.contentType}:${extra.contentToken}`,
          type: feedType,
          title,
          summary,
          details: readTimeText,
          authorName,
          authorHeadline: '',
          authorAvatarUrl: '',
          thumbnailUrl,
          targetUrl,
          nativeTarget,
          actionText: '',
          voteCount: 0,
          commentCount: 0
        };
      })
      .filter((item: HomeFeedItem | undefined): item is HomeFeedItem => item !== undefined);
  }

  private static parseHistoryPage(response: Record<string, Object>): CloudHistoryPage {
    const dataRaw = response.data;
    const data: CloudHistoryItem[] = Array.isArray(dataRaw)
      ? (dataRaw as Record<string, Object>[]).map((raw: Record<string, Object>) => this.parseItem(raw))
      : [];

    const pagingRaw = response.paging as Record<string, Object> | undefined;
    const paging = {
      isEnd: typeof pagingRaw?.is_end === 'boolean' ? pagingRaw.is_end as boolean : true,
      next: typeof pagingRaw?.next === 'string' ? pagingRaw.next as string : undefined
    };

    return { data, paging };
  }

  private static parseItem(raw: Record<string, Object>): CloudHistoryItem {
    const d = raw.data as Record<string, Object> | undefined;
    const data: CloudHistoryData = {
      header: this.parseHeader(d?.header as Record<string, Object> | undefined),
      content: d?.content !== undefined ? this.parseContent(d.content as Record<string, Object>) : undefined,
      action: this.parseAction(d?.action as Record<string, Object> | undefined),
      extra: this.parseExtra(d?.extra as Record<string, Object> | undefined),
      matrix: d?.matrix !== undefined
        ? (d.matrix as Record<string, Object>[]).map((m: Record<string, Object>) => ({
          type: typeof m.type === 'string' ? m.type as string : '',
          data: { text: typeof (m.data as Record<string, Object>)?.text === 'string' ? (m.data as Record<string, Object>).text as string : '' }
        }))
        : undefined
    };
    return {
      cardType: typeof raw.cardType === 'string' ? raw.cardType as string : typeof raw.card_type === 'string' ? raw.card_type as string : '',
      data
    };
  }

  private static parseHeader(raw: Record<string, Object> | undefined): CloudHistoryHeader {
    if (raw === undefined) {
      return { icon: '', title: '' };
    }
    return {
      icon: typeof raw.icon === 'string' ? raw.icon as string : '',
      title: typeof raw.title === 'string' ? raw.title as string : '',
      action: raw.action !== undefined ? this.parseAction(raw.action as Record<string, Object>) : undefined
    };
  }

  private static parseContent(raw: Record<string, Object> | undefined): CloudHistoryContent | undefined {
    if (raw === undefined) {
      return undefined;
    }
    return {
      authorName: typeof raw.authorName === 'string' ? raw.authorName as string : typeof raw.author_name === 'string' ? raw.author_name as string : undefined,
      summary: typeof raw.summary === 'string' ? raw.summary as string : undefined,
      coverImage: typeof raw.coverImage === 'string' ? raw.coverImage as string : typeof raw.cover_image === 'string' ? raw.cover_image as string : undefined
    };
  }

  private static parseAction(raw: Record<string, Object> | undefined): CloudHistoryAction {
    if (raw === undefined) {
      return { type: '', url: '' };
    }
    return {
      type: typeof raw.type === 'string' ? raw.type as string : '',
      url: typeof raw.url === 'string' ? raw.url as string : ''
    };
  }

  private static parseExtra(raw: Record<string, Object> | undefined): CloudHistoryExtra {
    if (raw === undefined) {
      return { contentToken: '', contentType: '', readTime: 0, questionToken: '' };
    }
    const readTimeRaw =
      typeof raw.readTime === 'number' ? raw.readTime as number :
      typeof raw.read_time === 'number' ? raw.read_time as number : 0;
    // 知乎 read_time 为 Unix 秒；统一换算为毫秒（已是毫秒的超大值保持不变）
    const readTime = readTimeRaw > 0 && readTimeRaw < 1e12 ? readTimeRaw * 1000 : readTimeRaw;
    return {
      contentToken: typeof raw.contentToken === 'string' ? raw.contentToken as string : typeof raw.content_token === 'string' ? raw.content_token as string : '',
      contentType: typeof raw.contentType === 'string' ? raw.contentType as string : typeof raw.content_type === 'string' ? raw.content_type as string : '',
      readTime,
      questionToken: typeof raw.questionToken === 'string' ? raw.questionToken as string : typeof raw.question_token === 'string' ? raw.question_token as string : ''
    };
  }

  private static formatReadTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '最近浏览';
    }
    const now = Date.now();
    const diffMs = now - timestamp;
    const diffMinutes = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMs / 3600000);
    const diffDays = Math.floor(diffMs / 86400000);

    if (diffMinutes < 1) {
      return '刚刚';
    }
    if (diffMinutes < 60) {
      return `${diffMinutes} 分钟前`;
    }
    if (diffHours < 24) {
      return `${diffHours} 小时前`;
    }
    if (diffDays < 30) {
      return `${diffDays} 天前`;
    }
    const date = new Date(timestamp);
    // 异常时间（早于 2000-01-01，如 1970 纪元起点）兜底，不显示裸日期
    if (date.getTime() < new Date(2000, 0, 1).getTime()) {
      return '最近浏览';
    }
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }
}
