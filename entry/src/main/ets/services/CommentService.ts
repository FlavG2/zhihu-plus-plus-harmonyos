import common from '@ohos.app.ability.common';
import {
  CommentSortOrder,
  ZhihuCommentAuthor,
  ZhihuCommentItem,
  ZhihuCommentPage,
  ZhihuCommentTarget,
  ZhihuCommentableTarget
} from '../models/ZhihuContentModels';
import { escapeHtml, extractFirstImageUrl, stripCommentImageLinks, stripHtmlToText } from '../utils/ZhihuHtml';
import { ZhihuApi } from './ZhihuApi';
import { ZhihuEmojiService } from './ZhihuEmojiService';

type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];

interface JsonObject {
  [key: string]: JsonValue;
}

export class CommentService {
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

  private static booleanValue(value: JsonValue | undefined): boolean {
    return value === true;
  }

  private static objectValue(value: JsonValue | undefined): JsonObject {
    return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as JsonObject : {};
  }

  private static arrayValue(value: JsonValue | undefined): JsonValue[] {
    return Array.isArray(value) ? value : [];
  }

  private static mapAuthor(raw: JsonObject): ZhihuCommentAuthor {
    return {
      id: `${raw.id ?? ''}`,
      name: this.stringValue(raw.name) || '知乎用户',
      headline: this.stringValue(raw.headline),
      avatarUrl: this.stringValue(raw.avatar_url) || this.stringValue(raw.avatarUrl),
      urlToken: this.stringValue(raw.url_token) || this.stringValue(raw.urlToken)
    };
  }

  private static mapComment(raw: JsonObject): ZhihuCommentItem {
    const authorTag = this.arrayValue(raw.author_tag)
      .map((item: JsonValue) => this.objectValue(item))
      .map((item: JsonObject) => this.stringValue(item.text))
      .find((item: string) => item.length > 0) ?? '';
    const ipInfo = this.arrayValue(raw.comment_tag)
      .map((item: JsonValue) => this.objectValue(item))
      .find((item: JsonObject) => this.stringValue(item.type) === 'ip_info');
    const contentHtml = this.stringValue(raw.content);
    const childComments = this.arrayValue(raw.child_comments)
      .map((item: JsonValue) => this.objectValue(item))
      .map((item: JsonObject) => this.mapComment(item));
    return {
      id: `${raw.id ?? ''}`,
      contentHtml,
      contentText: ZhihuEmojiService.replaceText(stripHtmlToText(stripCommentImageLinks(contentHtml))),
      previewImageUrl: extractFirstImageUrl(contentHtml),
      createdTime: this.numberValue(raw.created_time),
      liked: this.booleanValue(raw.liked),
      likeCount: this.numberValue(raw.like_count),
      childCommentCount: this.numberValue(raw.child_comment_count),
      childComments,
      author: this.mapAuthor(this.objectValue(raw.author)),
      replyToAuthor: 'reply_to_author' in raw ? this.mapAuthor(this.objectValue(raw.reply_to_author)) : undefined,
      authorTag,
      ipInfo: ipInfo !== undefined ? this.stringValue(ipInfo.text) : '',
      replyRootCommentId: this.stringValue(raw.reply_root_comment_id)
    };
  }

  private static submitCommentUrl(target: ZhihuCommentableTarget): string {
    if (target.kind === 'answer') {
      return `https://www.zhihu.com/api/v4/comment_v5/answers/${target.id}/comment`;
    }
    if (target.kind === 'article') {
      return `https://www.zhihu.com/api/v4/comment_v5/articles/${target.id}/comment`;
    }
    if (target.kind === 'question') {
      return `https://www.zhihu.com/api/v4/comment_v5/questions/${target.id}/comment`;
    }
    return `https://www.zhihu.com/api/v4/comment_v5/pins/${target.id}/comment`;
  }

  private static rootCommentUrl(target: ZhihuCommentableTarget, sortOrder: CommentSortOrder): string {
    const orderBy = sortOrder === 'time' ? 'ts' : 'score';
    if (target.kind === 'answer') {
      return `https://www.zhihu.com/api/v4/comment_v5/answers/${target.id}/root_comment?order_by=${orderBy}`;
    }
    if (target.kind === 'article') {
      return `https://www.zhihu.com/api/v4/comment_v5/articles/${target.id}/root_comment?order_by=${orderBy}`;
    }
    if (target.kind === 'question') {
      return `https://www.zhihu.com/api/v4/comment_v5/questions/${target.id}/root_comment?order_by=${orderBy}`;
    }
    return `https://www.zhihu.com/api/v4/comment_v5/pins/${target.id}/root_comment?order_by=${orderBy}`;
  }

  private static childCommentUrl(target: ZhihuCommentTarget): string {
    return `https://www.zhihu.com/api/v4/comment_v5/comment/${target.commentId}/child_comment`;
  }

  private static mapPage(payload: JsonObject): ZhihuCommentPage {
    const paging = this.objectValue(payload.paging);
    return {
      items: this.arrayValue(payload.data)
        .map((item: JsonValue) => this.objectValue(item))
        .map((item: JsonObject) => this.mapComment(item)),
      nextUrl: this.stringValue(paging.next),
      isEnd: paging.is_end === true
    };
  }

  static async loadRootComments(
    context: common.Context,
    target: ZhihuCommentableTarget,
    sortOrder: CommentSortOrder,
    nextUrl?: string
  ): Promise<ZhihuCommentPage> {
    await ZhihuEmojiService.initialize(context);
    const payload = await ZhihuApi.getJson(context, nextUrl ?? this.rootCommentUrl(target, sortOrder), {
      signed: true
    });
    if (payload === null) {
      return {
        items: [],
        nextUrl: '',
        isEnd: true
      };
    }
    return this.mapPage(payload);
  }

  static async loadCommentDetail(context: common.Context, commentId: string): Promise<ZhihuCommentItem> {
    await ZhihuEmojiService.initialize(context);
    const payload = await ZhihuApi.getJson(context, `https://www.zhihu.com/api/v4/comment_v5/comment/${commentId}`, {
      signed: true
    });
    if (payload === null || typeof payload !== 'object') {
      throw new Error('评论详情为空');
    }
    return this.mapComment(payload as JsonObject);
  }

  static async loadChildComments(
    context: common.Context,
    target: ZhihuCommentTarget,
    nextUrl?: string
  ): Promise<ZhihuCommentPage> {
    await ZhihuEmojiService.initialize(context);
    const payload = await ZhihuApi.getJson(context, nextUrl ?? this.childCommentUrl(target), {
      signed: true
    });
    if (payload === null) {
      return {
        items: [],
        nextUrl: '',
        isEnd: true
      };
    }
    return this.mapPage(payload);
  }

  static async submitComment(
    context: common.Context,
    target: ZhihuCommentableTarget,
    commentText: string,
    replyCommentId?: string
  ): Promise<ZhihuCommentItem> {
    const trimmed = commentText.trim();
    if (trimmed.length === 0) {
      throw new Error('评论不能为空');
    }
    const body = JSON.stringify({
      content: `<p>${escapeHtml(trimmed)}</p>`,
      ...(typeof replyCommentId === 'string' && replyCommentId.length > 0 ? { reply_comment_id: replyCommentId } : {})
    });
    const payload = await ZhihuApi.postJson(context, this.submitCommentUrl(target), {
      signed: true,
      body,
      headers: {
        'Content-Type': 'application/json'
      }
    });
    if (payload === null) {
      throw new Error('评论返回为空');
    }
    return this.mapComment(payload);
  }

  static async toggleLikeComment(
    context: common.Context,
    commentId: string,
    liked: boolean
  ): Promise<boolean> {
    const endpoint = `https://www.zhihu.com/api/v4/comments/${commentId}/like`;
    if (liked) {
      await ZhihuApi.deleteJson(context, endpoint, { signed: true });
      return false;
    }
    await ZhihuApi.postJson(context, endpoint, { signed: true });
    return true;
  }
}
