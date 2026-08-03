import common from '@ohos.app.ability.common';
import { HomeFeedPage } from '../models/ZhihuModels';
import { stripHtmlToText } from '../utils/ZhihuHtml';
import { HomeFeedService } from './HomeFeedService';
import { ZhihuApi } from './ZhihuApi';

type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];

interface JsonObject {
  [key: string]: JsonValue;
}

export type QuestionAnswerSortOrder = 'default' | 'updated';

export interface QuestionDetail {
  readonly id: string;
  readonly title: string;
  readonly detailHtml: string;
  readonly detailText: string;
  readonly excerpt: string;
  readonly answerCount: number;
  readonly visitCount: number;
  readonly commentCount: number;
  readonly followerCount: number;
  readonly voteupCount: number;
  readonly isFollowing: boolean;
}

export class QuestionFeedService {
  private static readonly QUESTION_INCLUDE: string =
    'read_count,visit_count,answer_count,voteup_count,comment_count,follower_count,detail,excerpt,author,relationship.is_following,topics';
  private static readonly PAGE_SIZE: number = 20;

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

  private static objectValue(value: JsonValue | undefined): JsonObject {
    return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as JsonObject : {};
  }

  private static questionDetailUrl(questionId: string): string {
    return `https://www.zhihu.com/api/v4/questions/${questionId}?include=${this.QUESTION_INCLUDE}`;
  }

  static answerFeedsUrl(questionId: string, order: QuestionAnswerSortOrder): string {
    let url = `https://www.zhihu.com/api/v4/questions/${questionId}/feeds?limit=${this.PAGE_SIZE}`;
    if (order !== 'default') {
      url = `${url}&order=${order}`;
    }
    return url;
  }

  static async loadQuestionDetail(context: common.Context, questionId: string): Promise<QuestionDetail> {
    const payload = await ZhihuApi.getJson(context, this.questionDetailUrl(questionId), { signed: true });
    if (payload === null) {
      throw new Error('问题详情为空');
    }
    const jsonPayload = payload as JsonObject;
    const relationship = this.objectValue(jsonPayload.relationship);
    const detailHtml = this.stringValue(jsonPayload.detail);
    return {
      id: `${jsonPayload.id ?? questionId}`,
      title: this.stringValue(jsonPayload.title),
      detailHtml,
      detailText: stripHtmlToText(detailHtml),
      excerpt: this.stringValue(jsonPayload.excerpt),
      answerCount: this.numberValue(jsonPayload.answer_count),
      visitCount: this.numberValue(jsonPayload.visit_count),
      commentCount: this.numberValue(jsonPayload.comment_count),
      followerCount: this.numberValue(jsonPayload.follower_count),
      voteupCount: this.numberValue(jsonPayload.voteup_count),
      isFollowing: relationship.is_following === true
    };
  }

  static async loadFirstPage(
    context: common.Context,
    questionId: string,
    questionTitle: string,
    order: QuestionAnswerSortOrder
  ): Promise<HomeFeedPage> {
    return this.loadPage(context, questionId, questionTitle, this.answerFeedsUrl(questionId, order));
  }

  static async loadNextPage(
    context: common.Context,
    questionId: string,
    questionTitle: string,
    nextUrl: string
  ): Promise<HomeFeedPage> {
    return this.loadPage(context, questionId, questionTitle, nextUrl);
  }

  private static async loadPage(
    context: common.Context,
    questionId: string,
    questionTitle: string,
    url: string
  ): Promise<HomeFeedPage> {
    const payload = await ZhihuApi.getJson(context, url, { signed: true });
    if (payload === null) {
      throw new Error('回答列表为空');
    }
    return HomeFeedService.mapQuestionFeedPage(payload, questionId, questionTitle);
  }

  static async setFollowState(context: common.Context, questionId: string, follow: boolean): Promise<void> {
    const url = `https://www.zhihu.com/api/v4/questions/${questionId}/followers`;
    if (follow) {
      await ZhihuApi.postJson(context, url, { signed: true });
      return;
    }
    await ZhihuApi.deleteJson(context, url, { signed: true });
  }
}
