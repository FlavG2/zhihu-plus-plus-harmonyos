import common from '@ohos.app.ability.common';
import {
  contentTargetUrl,
  ZhihuAuthorProfile,
  ZhihuCommentableTarget,
  ZhihuContentDetail,
  ZhihuSegmentParagraph,
  ZhihuVoteState
} from '../models/ZhihuContentModels';
import { escapeHtml, normalizeRichContentHtml, paragraphizeText } from '../utils/ZhihuHtml';
import { ZhihuApi } from './ZhihuApi';
import { ZhihuEmojiService } from './ZhihuEmojiService';

type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];

interface JsonObject {
  [key: string]: JsonValue;
}

export class ArticleDetailService {
  private static readonly ANSWER_INCLUDE =
    '.settings,content,editable_content,paid_info,can_comment,excerpt,thanks_count,voteup_count,comment_count,visited_count,attachment,reaction,ip_info,pagination_info,endorsements,question.topics,question.author,reaction.relation.voting,author.badge_v2,settings.table_of_contents.enabled,segment_infos,allow_segment_interaction';
  private static readonly ARTICLE_INCLUDE =
    'content,topics,paid_info,can_comment,excerpt,thanks_count,voteup_count,comment_count,visited_count,relationship,ip_info,relationship.vote,author.badge_v2,segment_infos,allow_segment_interaction';
  private static readonly QUESTION_INCLUDE =
    'read_count,visit_count,answer_count,voteup_count,comment_count,follower_count,detail,excerpt,author,relationship.is_following,topics';

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

  private static mapAuthor(raw: JsonObject): ZhihuAuthorProfile | undefined {
    const id = `${raw.id ?? ''}`;
    const name = this.stringValue(raw.name);
    if (name.length === 0) {
      return undefined;
    }
    return {
      id,
      name,
      headline: this.stringValue(raw.headline),
      avatarUrl: this.stringValue(raw.avatar_url) || this.stringValue(raw.avatarUrl),
      urlToken: this.stringValue(raw.url_token) || this.stringValue(raw.urlToken)
    };
  }

  private static mapVoteState(payload: JsonObject): ZhihuVoteState {
    const reaction = this.objectValue(payload.reaction);
    const relation = this.objectValue(reaction.relation);
    const relationship = this.objectValue(payload.relationship);
    const rawVote = (this.stringValue(relation.vote) || this.stringValue(relationship.vote)).toLowerCase();
    if (rawVote === 'up') {
      return 'up';
    }
    if (rawVote === 'down') {
      return 'down';
    }
    if (rawVote === 'neutral') {
      return 'neutral';
    }
    const voting = this.numberValue(relation.voting);
    if (voting > 0) {
      return 'up';
    }
    if (voting < 0) {
      return 'down';
    }
    return 'none';
  }

  private static canComment(payload: JsonObject): boolean {
    const canComment = this.objectValue(payload.can_comment);
    if ('status' in canComment) {
      return this.booleanValue(canComment.status);
    }
    const permission = this.stringValue(payload.comment_permission);
    return permission !== 'close' && permission !== 'closed';
  }

  private static sanitizeBodyHtml(html: string): string {
    return ZhihuEmojiService.replaceHtml(normalizeRichContentHtml(html));
  }

  private static mapSegmentMeta(raw: JsonValue | undefined): {
    segIds: string[];
    isLike: boolean;
    likeCount: number;
    commentCount: number;
    myCommentCount: number;
    isSpan: boolean;
  } {
    const o = this.objectValue(raw);
    const rawSegIds = this.arrayValue(o.seg_ids ?? o.segIds);
    const segIds = rawSegIds.map((v: JsonValue) => `${v}`).filter((v: string) => v.length > 0);
    return {
      segIds,
      isLike: this.booleanValue(o.is_like ?? o.isLike),
      likeCount: this.numberValue(o.like_count ?? o.likeCount),
      commentCount: this.numberValue(o.comment_count ?? o.commentCount),
      myCommentCount: this.numberValue(o.my_comment_count ?? o.myCommentCount),
      isSpan: this.booleanValue(o.is_span ?? o.isSpan)
    };
  }

  private static mapSegmentMark(raw: JsonObject): {
    startIndex: number;
    endIndex: number;
    segInfo?: ReturnType<typeof ArticleDetailService.mapSegmentMeta>;
    masterSegInfo?: ReturnType<typeof ArticleDetailService.mapSegmentMeta>;
  } {
    return {
      startIndex: this.numberValue(raw.start_index ?? raw.startIndex),
      endIndex: this.numberValue(raw.end_index ?? raw.endIndex),
      segInfo: raw.seg_info !== undefined ? this.mapSegmentMeta(raw.seg_info) : undefined,
      masterSegInfo: raw.master_seg_info !== undefined ? this.mapSegmentMeta(raw.master_seg_info) : undefined
    };
  }

  private static mapSegmentParagraphs(raw: JsonValue | undefined): ZhihuSegmentParagraph[] {
    const arr = this.arrayValue(raw);
    const result: ZhihuSegmentParagraph[] = [];
    arr.forEach((item: JsonValue) => {
      const o = this.objectValue(item);
      const pid = this.stringValue(o.pid);
      if (pid.length === 0) {
        return;
      }
      const marks = this.arrayValue(o.marks).map((m: JsonValue) => this.mapSegmentMark(this.objectValue(m)));
      result.push({
        pid,
        text: this.stringValue(o.text),
        marks
      });
    });
    return result;
  }

  private static buildPinHtml(payload: JsonObject): string {
    const contentHtml = this.stringValue(payload.content_html) || this.stringValue(payload.contentHtml);
    if (contentHtml.length > 0) {
      return contentHtml;
    }

    const blocks: string[] = [];
    this.arrayValue(payload.content).forEach((item: JsonValue) => {
      const objectValue = this.objectValue(item);
      const type = this.stringValue(objectValue.type);
      if (type === 'text') {
        const text = this.stringValue(objectValue.content) || this.stringValue(objectValue.title);
        if (text.length > 0) {
          blocks.push(paragraphizeText(text));
        }
        return;
      }
      if (type === 'image') {
        const url = this.stringValue(objectValue.url) || this.stringValue(objectValue.original_url);
        if (url.length > 0) {
          blocks.push(`<p><img src="${escapeHtml(url)}" /></p>`);
        }
        return;
      }
      if (type === 'link_card') {
        const url = this.stringValue(objectValue.url);
        const title = this.stringValue(objectValue.title) || url;
        if (url.length > 0) {
          blocks.push(`<p><a href="${escapeHtml(url)}">${escapeHtml(title)}</a></p>`);
        }
      }
    });
    return blocks.join('');
  }

  private static answerUrl(target: ZhihuCommentableTarget): string {
    return `https://www.zhihu.com/api/v4/answers/${target.id}?include=${this.ANSWER_INCLUDE}`;
  }

  private static articleUrl(target: ZhihuCommentableTarget): string {
    return `https://www.zhihu.com/api/v4/articles/${target.id}?include=${this.ARTICLE_INCLUDE}`;
  }

  private static questionUrl(target: ZhihuCommentableTarget): string {
    return `https://www.zhihu.com/api/v4/questions/${target.id}?include=${this.QUESTION_INCLUDE}`;
  }

  private static pinUrl(target: ZhihuCommentableTarget): string {
    return `https://www.zhihu.com/api/v4/pins/${target.id}`;
  }

  static async loadDetail(context: common.Context, target: ZhihuCommentableTarget): Promise<ZhihuContentDetail> {
    await ZhihuEmojiService.initialize(context);
    let payload: JsonObject | null = null;
    if (target.kind === 'answer') {
      payload = await ZhihuApi.getJson(context, this.answerUrl(target), { signed: true });
      if (payload === null) {
        throw new Error('回答内容为空');
      }
      const question = this.objectValue(payload.question);
      const questionId = `${question.id ?? target.questionId ?? ''}`;
      const rawHtmlContent = this.stringValue(payload.content) || paragraphizeText(this.stringValue(payload.excerpt));
      const paginationRaw = this.objectValue(payload.pagination_info);
      const prevIdsRaw = this.arrayValue(paginationRaw.prev_answer_ids ?? paginationRaw.prevAnswerIds);
      const nextIdsRaw = this.arrayValue(paginationRaw.next_answer_ids ?? paginationRaw.nextAnswerIds);
      const paginationInfo: { prevAnswerIds: string[]; nextAnswerIds: string[] } | undefined =
        prevIdsRaw.length > 0 || nextIdsRaw.length > 0
          ? {
              prevAnswerIds: prevIdsRaw.map((v: JsonValue) => `${v}`),
              nextAnswerIds: nextIdsRaw.map((v: JsonValue) => `${v}`)
            }
          : undefined;
      const segmentInfos = this.mapSegmentParagraphs(payload.segment_infos);
      const allowSegmentInteraction = this.numberValue(payload.allow_segment_interaction) === 1 || segmentInfos.length > 0;
      return {
        target: {
          ...target,
          questionId,
          title: this.stringValue(question.title) || target.title
        },
        title: this.stringValue(question.title) || target.title || '回答',
        browserUrl: contentTargetUrl({
          ...target,
          questionId
        }),
        author: this.mapAuthor(this.objectValue(payload.author)),
        excerpt: this.stringValue(payload.excerpt),
        htmlContent: this.sanitizeBodyHtml(rawHtmlContent),
        commentCount: this.numberValue(payload.comment_count),
        voteCount: this.numberValue(payload.voteup_count),
        voteState: this.mapVoteState(payload),
        createdTime: this.numberValue(payload.created_time),
        updatedTime: this.numberValue(payload.updated_time),
        ipInfo: this.stringValue(payload.ip_info),
        questionId,
        questionTitle: this.stringValue(question.title),
        canComment: this.canComment(payload),
        canVote: true,
        supportsDownvote: true,
        segmentInfos,
        allowSegmentInteraction,
        paginationInfo
      };
    }
    if (target.kind === 'article') {
      payload = await ZhihuApi.getJson(context, this.articleUrl(target), { signed: true });
      if (payload === null) {
        throw new Error('文章内容为空');
      }
      const rawHtmlContent = this.stringValue(payload.content) || paragraphizeText(this.stringValue(payload.excerpt));
      const segmentInfos = this.mapSegmentParagraphs(payload.segment_infos);
      const allowSegmentInteraction = this.numberValue(payload.allow_segment_interaction) === 1 || segmentInfos.length > 0;
      return {
        target: {
          ...target,
          title: this.stringValue(payload.title) || target.title
        },
        title: this.stringValue(payload.title) || target.title || '文章',
        browserUrl: this.stringValue(payload.url) || contentTargetUrl(target),
        author: this.mapAuthor(this.objectValue(payload.author)),
        excerpt: this.stringValue(payload.excerpt),
        htmlContent: this.sanitizeBodyHtml(rawHtmlContent),
        commentCount: this.numberValue(payload.comment_count),
        voteCount: this.numberValue(payload.voteup_count),
        voteState: this.mapVoteState(payload),
        createdTime: this.numberValue(payload.created),
        updatedTime: this.numberValue(payload.updated),
        ipInfo: this.stringValue(payload.ip_info),
        questionId: '',
        questionTitle: '',
        canComment: this.canComment(payload),
        canVote: true,
        supportsDownvote: true,
        segmentInfos,
        allowSegmentInteraction
      };
    }
    if (target.kind === 'question') {
      payload = await ZhihuApi.getJson(context, this.questionUrl(target), { signed: true });
      if (payload === null) {
        throw new Error('问题内容为空');
      }
      const rawHtmlContent = this.stringValue(payload.detail) || paragraphizeText(this.stringValue(payload.excerpt));
      return {
        target: {
          ...target,
          title: this.stringValue(payload.title) || target.title
        },
        title: this.stringValue(payload.title) || target.title || '问题',
        browserUrl: this.stringValue(payload.url) || contentTargetUrl(target),
        author: this.mapAuthor(this.objectValue(payload.author)),
        excerpt: this.stringValue(payload.excerpt),
        htmlContent: this.sanitizeBodyHtml(rawHtmlContent),
        commentCount: this.numberValue(payload.comment_count),
        voteCount: this.numberValue(payload.voteup_count),
        voteState: 'none',
        createdTime: this.numberValue(payload.created),
        updatedTime: this.numberValue(payload.updated_time),
        ipInfo: '',
        questionId: target.id,
        questionTitle: this.stringValue(payload.title),
        canComment: true,
        canVote: false,
        supportsDownvote: false
      };
    }

    payload = await ZhihuApi.getJson(context, this.pinUrl(target), { signed: true });
    if (payload === null) {
      throw new Error('想法内容为空');
    }
    const author = this.mapAuthor(this.objectValue(payload.author));
    const rawHtmlContent = this.buildPinHtml(payload);
    return {
      target: {
        ...target,
        title: target.title || this.stringValue(payload.excerpt_title) || (author !== undefined ? `${author.name}的想法` : '想法')
      },
      title: target.title || this.stringValue(payload.excerpt_title) || (author !== undefined ? `${author.name}的想法` : '想法'),
      browserUrl: this.stringValue(payload.url) || contentTargetUrl(target),
      author,
      excerpt: this.stringValue(payload.excerpt_title),
      htmlContent: this.sanitizeBodyHtml(rawHtmlContent),
      commentCount: this.numberValue(payload.comment_count),
      voteCount: this.numberValue(payload.like_count),
      voteState: 'none',
      createdTime: this.numberValue(payload.created),
      updatedTime: this.numberValue(payload.updated),
      ipInfo: '',
      questionId: '',
      questionTitle: '',
      canComment: true,
      canVote: true,
      supportsDownvote: false
    };
  }

  static async toggleVote(
    context: common.Context,
    detail: ZhihuContentDetail,
    nextState: ZhihuVoteState
  ): Promise<{ voteCount: number; voteState: ZhihuVoteState }> {
    if (!detail.canVote) {
      throw new Error('当前内容不支持投票');
    }

    if (detail.target.kind === 'answer') {
      const endpoint = `https://www.zhihu.com/api/v4/answers/${detail.target.id}/voters`;
      const payload = await ZhihuApi.postJson(context, endpoint, {
        signed: true,
        body: JSON.stringify({ type: nextState }),
        headers: {
          'Content-Type': 'application/json'
        }
      });
      if (payload === null) {
        return {
          voteCount: detail.voteCount,
          voteState: nextState
        };
      }
      return {
        voteCount: this.numberValue(payload.voteup_count),
        voteState: nextState
      };
    }

    if (detail.target.kind === 'article') {
      const endpoint = `https://www.zhihu.com/api/v4/articles/${detail.target.id}/voters`;
      const payload = await ZhihuApi.postJson(context, endpoint, {
        signed: true,
        body: JSON.stringify({ type: nextState }),
        headers: {
          'Content-Type': 'application/json'
        }
      });
      if (payload === null) {
        return {
          voteCount: detail.voteCount,
          voteState: nextState
        };
      }
      return {
        voteCount: this.numberValue(payload.voteup_count),
        voteState: nextState
      };
    }

    if (detail.target.kind === 'pin') {
      // 想法：POST /api/v4/pins/{id}/voters/up（赞）/ DELETE（取消赞）
      const endpoint = `https://www.zhihu.com/api/v4/pins/${detail.target.id}/voters/up`;
      const finalState: ZhihuVoteState = nextState === 'up' ? 'up' : 'neutral';
      if (finalState === 'up') {
        const payload = await ZhihuApi.postJson(context, endpoint, { signed: true });
        if (payload === null) {
          return { voteCount: detail.voteCount, voteState: finalState };
        }
        return {
          voteCount: this.numberValue(payload.liked_count),
          voteState: finalState
        };
      } else {
        const payload = await ZhihuApi.deleteJson(context, endpoint, { signed: true });
        if (payload === null) {
          return { voteCount: detail.voteCount, voteState: finalState };
        }
        return {
          voteCount: this.numberValue(payload.liked_count),
          voteState: finalState
        };
      }
    }

    // 未知类型用 article 端点兜底
    const endpoint = `https://www.zhihu.com/api/v4/articles/${detail.target.id}/voters`;
    const payload = await ZhihuApi.postJson(context, endpoint, {
      signed: true,
      body: JSON.stringify({ type: nextState }),
      headers: {
        'Content-Type': 'application/json'
      }
    });
    if (payload === null) {
      return {
        voteCount: detail.voteCount,
        voteState: nextState
      };
    }
    return {
      voteCount: this.numberValue(payload.voteup_count),
      voteState: nextState
    };
  }
}
