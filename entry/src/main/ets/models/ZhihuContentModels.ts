export type ZhihuContentKind = 'answer' | 'article' | 'question' | 'pin' | 'comment' | 'message';
export type ZhihuVoteState = 'up' | 'down' | 'neutral' | 'none';
export type CommentSortOrder = 'score' | 'time';

export interface ZhihuAnswerTarget {
  readonly kind: 'answer';
  readonly id: string;
  readonly questionId?: string;
  readonly title?: string;
  readonly anchorCommentId?: string;
}

export interface ZhihuArticleTarget {
  readonly kind: 'article';
  readonly id: string;
  readonly title?: string;
  readonly anchorCommentId?: string;
}

export interface ZhihuQuestionTarget {
  readonly kind: 'question';
  readonly id: string;
  readonly title?: string;
  readonly anchorCommentId?: string;
}

export interface ZhihuPinTarget {
  readonly kind: 'pin';
  readonly id: string;
  readonly title?: string;
  readonly anchorCommentId?: string;
}

// 私信会话（对齐安卓 NavDestination.Notification.Message）：zhihu.com/inbox/{peerId}?title=
// 注：私信会话不是"可评论内容"，但为兼容 ZhihuCommentableTarget 联合里大量已有 .id/.title 访问，
// 这里让 id/title 必填（id 复用 peerId、title 复用 name），anchorCommentId 不需要故省略。
// 实际 message 分支在 openNotification 里读 peerId/name，不依赖 .id/.title。
export interface ZhihuMessageTarget {
  readonly kind: 'message';
  readonly peerId: string;
  readonly name?: string;
  readonly id: string;
  readonly title: string;
  readonly anchorCommentId?: string;
}

export type ZhihuCommentableTarget =
  | ZhihuAnswerTarget
  | ZhihuArticleTarget
  | ZhihuQuestionTarget
  | ZhihuPinTarget
  | ZhihuMessageTarget;

export interface ZhihuCommentTarget {
  readonly kind: 'comment';
  readonly commentId: string;
  readonly article: ZhihuCommentableTarget;
}

export type ZhihuContentTarget = ZhihuCommentableTarget | ZhihuCommentTarget;

export interface ArticlePageParams {
  readonly target?: string;
  readonly fallbackTitle?: string;
  readonly fallbackUrl?: string;
  // 同一问题下的回答列表（序列化后的 ZhihuCommentableTarget）与当前索引，
  // 用于 Article 页以 Swiper 上下滑动切换上一条/下一条回答。
  readonly answerList?: string[];
  readonly startIndex?: number;
  readonly questionId?: string;
  readonly questionTitle?: string;
  // 通知评论定位：直接进入内容后定位到指定评论
  readonly anchorCommentId?: string;
}

export interface ZhihuAuthorProfile {
  readonly id: string;
  readonly name: string;
  readonly headline: string;
  readonly avatarUrl: string;
  readonly urlToken: string;
}

export interface ZhihuAnswerPagination {
  readonly prevAnswerIds: string[];
  readonly nextAnswerIds: string[];
}

// 划线片段（句子/段落高亮）：对齐安卓 SegmentInfo。知乎 API 字段为 segment_infos / allow_segment_interaction。
export interface ZhihuSegmentMeta {
  readonly segIds: string[];
  readonly isLike: boolean;
  readonly likeCount: number;
  readonly commentCount: number;
  readonly myCommentCount: number;
  readonly isSpan: boolean;
}

export interface ZhihuSegmentMark {
  readonly startIndex: number;
  readonly endIndex: number;
  readonly segInfo?: ZhihuSegmentMeta;
  readonly masterSegInfo?: ZhihuSegmentMeta;
}

export interface ZhihuSegmentParagraph {
  readonly pid: string;
  readonly text: string;
  readonly marks: ZhihuSegmentMark[];
}

export interface ZhihuContentDetail {
  readonly target: ZhihuCommentableTarget;
  readonly title: string;
  readonly browserUrl: string;
  readonly author?: ZhihuAuthorProfile;
  readonly excerpt: string;
  readonly htmlContent: string;
  readonly commentCount: number;
  readonly voteCount: number;
  readonly voteState: ZhihuVoteState;
  readonly createdTime: number;
  readonly updatedTime: number;
  readonly ipInfo: string;
  readonly questionId: string;
  readonly questionTitle: string;
  readonly canComment: boolean;
  readonly canVote: boolean;
  readonly supportsDownvote: boolean;
  // 划线片段：仅部分回答/文章详情返回（API 字段 segment_infos / allow_segment_interaction）
  readonly segmentInfos?: ZhihuSegmentParagraph[];
  readonly allowSegmentInteraction?: boolean;
  // 仅回答详情返回：用于左右滑动切换上一个/下一个回答
  readonly paginationInfo?: ZhihuAnswerPagination;
}

export interface ZhihuCommentAuthor {
  readonly id: string;
  readonly name: string;
  readonly headline: string;
  readonly avatarUrl: string;
  readonly urlToken: string;
}

export interface ZhihuCommentItem {
  readonly id: string;
  readonly contentHtml: string;
  readonly contentText: string;
  readonly previewImageUrl: string;
  readonly createdTime: number;
  readonly liked: boolean;
  readonly likeCount: number;
  readonly childCommentCount: number;
  readonly childComments: ZhihuCommentItem[];
  readonly author: ZhihuCommentAuthor;
  readonly replyToAuthor?: ZhihuCommentAuthor;
  readonly authorTag: string;
  readonly ipInfo: string;
  readonly replyRootCommentId?: string;
}

export interface ZhihuCommentPage {
  readonly items: ZhihuCommentItem[];
  readonly nextUrl: string;
  readonly isEnd: boolean;
}

export function contentTargetKey(target: ZhihuContentTarget): string {
  if (target.kind === 'comment') {
    return `comment:${target.commentId}:${contentTargetKey(target.article)}`;
  }
  return `${target.kind}:${target.id}`;
}

export function rootContentTarget(target: ZhihuContentTarget): ZhihuCommentableTarget {
  return target.kind === 'comment' ? target.article : target;
}

export function contentTargetUrl(target: ZhihuCommentableTarget): string {
  if (target.kind === 'answer') {
    if (typeof target.questionId === 'string' && target.questionId.length > 0) {
      return `https://www.zhihu.com/question/${target.questionId}/answer/${target.id}`;
    }
    return `https://www.zhihu.com/answer/${target.id}`;
  }
  if (target.kind === 'article') {
    return `https://zhuanlan.zhihu.com/p/${target.id}`;
  }
  if (target.kind === 'question') {
    return `https://www.zhihu.com/question/${target.id}`;
  }
  return `https://www.zhihu.com/pin/${target.id}`;
}

export function contentTargetDisplayTitle(target: ZhihuCommentableTarget): string {
  if (typeof target.title === 'string' && target.title.length > 0) {
    return target.title;
  }
  if (target.kind === 'answer') {
    return '回答';
  }
  if (target.kind === 'article') {
    return '文章';
  }
  if (target.kind === 'question') {
    return '问题';
  }
  return '想法';
}

function normalizeCommentableTarget(raw: Record<string, Object>): ZhihuCommentableTarget | undefined {
  const kind = typeof raw.kind === 'string' ? raw.kind : '';
  const id = `${raw.id ?? ''}`;
  const title = typeof raw.title === 'string' ? raw.title : undefined;
  if (id.length === 0) {
    return undefined;
  }
  if (kind === 'answer') {
    const questionId = typeof raw.questionId === 'string' ? raw.questionId : undefined;
    const anchorCommentId = typeof raw.anchorCommentId === 'string' && raw.anchorCommentId.length > 0 ? raw.anchorCommentId : undefined;
    return { kind, id, questionId, title, anchorCommentId };
  }
  if (kind === 'article' || kind === 'question' || kind === 'pin') {
    const anchorCommentId = typeof raw.anchorCommentId === 'string' && raw.anchorCommentId.length > 0 ? raw.anchorCommentId : undefined;
    return { kind, id, title, anchorCommentId };
  }
  return undefined;
}

export function parseZhihuContentTarget(raw: string | Object | undefined): ZhihuContentTarget | undefined {
  if (raw === undefined) {
    return undefined;
  }
  let parsed: Object | undefined;
  if (typeof raw === 'string') {
    if (raw.length === 0) {
      return undefined;
    }
    try {
      parsed = JSON.parse(raw) as Object;
    } catch (_) {
      return undefined;
    }
  } else {
    parsed = raw;
  }
  if (parsed === undefined || parsed === null || typeof parsed !== 'object') {
    return undefined;
  }

  const objectValue = parsed as Record<string, Object>;
  const kind = typeof objectValue.kind === 'string' ? objectValue.kind : '';
  if (kind === 'comment') {
    const commentId = `${objectValue.commentId ?? ''}`;
    const articleRaw = objectValue.article;
    if (commentId.length === 0 || articleRaw === undefined || articleRaw === null || typeof articleRaw !== 'object') {
      return undefined;
    }
    const article = normalizeCommentableTarget(articleRaw as Record<string, Object>);
    if (article === undefined) {
      return undefined;
    }
    return {
      kind: 'comment',
      commentId,
      article
    };
  }
  return normalizeCommentableTarget(objectValue);
}

export function serializeZhihuContentTarget(target: ZhihuContentTarget): string {
  return JSON.stringify(target);
}
