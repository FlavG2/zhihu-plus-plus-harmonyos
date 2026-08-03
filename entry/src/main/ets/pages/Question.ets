import common from '@ohos.app.ability.common';
import { promptAction, router } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import {
  CommentSortOrder,
  serializeZhihuContentTarget,
  ZhihuCommentableTarget,
  ZhihuCommentItem,
  ZhihuCommentTarget
} from '../models/ZhihuContentModels';
import { HomeFeedItem } from '../models/ZhihuModels';
import { BrowsingHistoryRepository } from '../services/BrowsingHistoryRepository';
import { CloudHistoryService } from '../services/CloudHistoryService';
import { CommentService } from '../services/CommentService';
import {
  QuestionAnswerSortOrder,
  QuestionDetail,
  QuestionFeedService
} from '../services/QuestionFeedService';
import { ThemeColors } from '../services/ThemeColors';
import { ZhihuEmojiItem, EmojiPickerItem, ZhihuEmojiService, CommentContentSegment } from '../services/ZhihuEmojiService';
import { formatTimestamp } from '../utils/Time';
import { stripCommentImageLinks } from '../utils/ZhihuHtml';

interface QuestionPageParams {
  readonly questionId?: string;
  readonly title?: string;
  readonly anchorCommentId?: string;
}

function formatQuestionCounter(value: number): string {
  if (value >= 10000) {
    return `${(value / 10000).toFixed(value >= 100000 ? 0 : 1)} 万`;
  }
  return `${value}`;
}


// 展开详情统一用原生 Text 渲染（字号 14fp 与收起态一致），而非 RichText/web 引擎。
// 因此这里将知乎 HTML 剥离标签、解码实体、保留段落换行，返回纯文本。
function stripHtmlToPlainText(html: string): string {
  let text = html ?? '';
  // 块级标签转换行，保留段落结构
  text = text.replace(/<br\s*\/?>/gi, '\n');
  text = text.replace(/<\/(p|div|li|h[1-6]|blockquote)>/gi, '\n');
  // 去除其余所有标签
  text = text.replace(/<[^>]+>/g, '');
  // HTML 实体解码
  text = text
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&hellip;/gi, '…')
    .replace(/&mdash;/gi, '—')
    .replace(/&ndash;/gi, '–')
    .replace(/&ldquo;|&rdquo;/gi, '"')
    .replace(/&lsquo;|&rsquo;/gi, "'")
    .replace(/&middot;/gi, '·')
    .replace(/&times;/gi, '×')
    .replace(/&rarr;/gi, '→');
  // 合并多余空行与首尾空白
  text = text.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
  return text;
}

// 展开详情的混合原生渲染：把知乎 HTML 拆成「文本段（含超链接）」与「图片」。
// 文本用原生 Text+Span(14fp)（与收起态字号一致），图片用原生 Image；超链接可点击跳浏览器。
interface InlineSpan {
  text: string;
  isLink: boolean;
  url?: string;
}

interface DetailBlock {
  type: 'paragraph' | 'image';
  spans?: InlineSpan[]; // 文本段内的行内片段（纯文本 / 超链接）
  url?: string;         // 图片地址
}

// 解析一段 HTML 片段，拆成「纯文本」与「超链接」行内片段（保留 <a> 标签）。
function parseInlineSpans(fragment: string): InlineSpan[] {
  const spans: InlineSpan[] = [];
  const aRegex = /<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
  let last = 0;
  let m: RegExpExecArray | null;
  while ((m = aRegex.exec(fragment)) !== null) {
    const before = stripHtmlToPlainText(fragment.substring(last, m.index));
    if (before.length > 0) {
      spans.push({ text: before, isLink: false });
    }
    const linkText = stripHtmlToPlainText(m[2]);
    if (linkText.length > 0) {
      spans.push({ text: linkText, isLink: true, url: m[1] });
    }
    last = aRegex.lastIndex;
  }
  const tail = stripHtmlToPlainText(fragment.substring(last));
  if (tail.length > 0) {
    spans.push({ text: tail, isLink: false });
  }
  return spans;
}

function parseDetailHtml(html: string): DetailBlock[] {
  const blocks: DetailBlock[] = [];
  // 逐个匹配 <img> 标签，标签前后分别作为文本段（含超链接）处理
  const imgTagRegex = /<img\b[^>]*>/gi;
  let last = 0;
  let m: RegExpExecArray | null;
  while ((m = imgTagRegex.exec(html)) !== null) {
    const before = parseInlineSpans(html.substring(last, m.index));
    if (before.length > 0) {
      blocks.push({ type: 'paragraph', spans: before });
    }
    // 知乎图片真实地址常放在 data-original / data-actualsrc，src 可能是占位图
    const urlMatch = m[0].match(/(?:data-original|data-actualsrc|src)=["']([^"']+)["']/i);
    if (urlMatch && urlMatch[1].startsWith('http')) {
      blocks.push({ type: 'image', url: urlMatch[1] });
    }
    last = imgTagRegex.lastIndex;
  }
  const tail = parseInlineSpans(html.substring(last));
  if (tail.length > 0) {
    blocks.push({ type: 'paragraph', spans: tail });
  }
  return blocks;
}

// ===== 评论子系统（移植自 Article.ets，已统一走 ThemeColors 主题）=====
const COMMENT_CHILD_PREVIEW_LIMIT: number = 2;
const COMMENT_FOOTER_INDENT: number = 46;

// 评论内点击图片/链接跳 WebContent 后，返回需重开评论 sheet（而非落回内容页）
let commentReopenPending: boolean = false;
const COMMENT_CHILD_INDENT: number = 44;

function formatUnixTime(seconds: number): string {
  if (seconds <= 0) {
    return '';
  }
  return formatTimestamp(new Date(seconds * 1000));
}

function mergeComments(existing: ZhihuCommentItem[], incoming: ZhihuCommentItem[]): ZhihuCommentItem[] {
  const merged = [...existing];
  const ids = new Set<string>(existing.map((item: ZhihuCommentItem) => item.id));
  incoming.forEach((item: ZhihuCommentItem) => {
    if (!ids.has(item.id)) {
      merged.push(item);
    }
  });
  return merged;
}

function copyComment(
  item: ZhihuCommentItem,
  childComments: ZhihuCommentItem[],
  liked?: boolean,
  likeCount?: number,
  childCommentCount?: number
): ZhihuCommentItem {
  return {
    id: item.id,
    contentHtml: item.contentHtml,
    contentText: item.contentText,
    previewImageUrl: item.previewImageUrl,
    createdTime: item.createdTime,
    liked: liked ?? item.liked,
    likeCount: likeCount ?? item.likeCount,
    childCommentCount: childCommentCount ?? item.childCommentCount,
    childComments,
    author: item.author,
    replyToAuthor: item.replyToAuthor,
    authorTag: item.authorTag,
    ipInfo: item.ipInfo
  };
}

function prependCommentPreview(existing: ZhihuCommentItem[], incoming: ZhihuCommentItem): ZhihuCommentItem[] {
  const filtered = existing.filter((item: ZhihuCommentItem) => item.id !== incoming.id);
  return [incoming, ...filtered].slice(0, COMMENT_CHILD_PREVIEW_LIMIT);
}

function appendReplyPreview(comments: ZhihuCommentItem[], parentId: string, reply: ZhihuCommentItem): ZhihuCommentItem[] {
  let changed = false;
  const next = comments.map((item: ZhihuCommentItem): ZhihuCommentItem => {
    const childComments = appendReplyPreview(item.childComments, parentId, reply);
    if (item.id !== parentId) {
      if (childComments === item.childComments) {
        return item;
      }
      changed = true;
      return copyComment(item, childComments);
    }
    changed = true;
    return copyComment(
      item,
      prependCommentPreview(item.childComments, reply),
      undefined,
      undefined,
      item.childCommentCount + 1
    );
  });
  return changed ? next : comments;
}

function updateCommentLike(comments: ZhihuCommentItem[], commentId: string, liked: boolean): ZhihuCommentItem[] {
  return comments.map((item: ZhihuCommentItem): ZhihuCommentItem => {
    const childComments = updateCommentLike(item.childComments, commentId, liked);
    if (item.id !== commentId) {
      if (childComments === item.childComments) {
        return item;
      }
      return copyComment(item, childComments);
    }
    return copyComment(item, childComments, liked, liked ? item.likeCount + 1 : Math.max(0, item.likeCount - 1));
  });
}

@Entry
@Component
struct Question {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageProp('bottomSafeAreaVp') private bottomSafeAreaVp: number = 0;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;
  @State private questionId: string = '';
  @State private questionTitle: string = '问题';
  @State private detail?: QuestionDetail = undefined;
  @State private detailError: string = '';
  @State private detailExpanded: boolean = false;
  @State private sortOrder: QuestionAnswerSortOrder = 'default';
  @State private answers: HomeFeedItem[] = [];
  @State private answersLoading: boolean = false;
  @State private answersLoadingMore: boolean = false;
  @State private answersError: string = '';
  @State private answersNextUrl: string = '';
  @State private answersEnd: boolean = false;
  @State private answersHasLoaded: boolean = false;
  @State private refreshing: boolean = false;
  @State private followBusy: boolean = false;

  // 评论子系统（移植自 Article.ets，question 类型由 CommentService 支持）
  @State private showRootCommentSheet: boolean = false;
  @State private anchorCommentId: string = '';
  @State private anchorConsumed: boolean = false;
  @State private rootComments: ZhihuCommentItem[] = [];
  @State private rootCommentSortOrder: CommentSortOrder = 'score';
  @State private rootCommentLoading: boolean = false;
  @State private rootCommentLoadingMore: boolean = false;
  @State private rootCommentError: string = '';
  @State private rootCommentNextUrl: string = '';
  @State private rootCommentEnd: boolean = false;
  @State private rootCommentDraft: string = '';
  @State private rootSubmitting: boolean = false;
  @State private rootReplyTo?: ZhihuCommentItem = undefined;
  @State private showChildCommentSheet: boolean = false;
  @State private childTarget?: ZhihuCommentTarget = undefined;
  @State private childComments: ZhihuCommentItem[] = [];
  @State private childCommentLoading: boolean = false;
  @State private childCommentLoadingMore: boolean = false;
  @State private childCommentError: string = '';
  @State private childCommentNextUrl: string = '';
  @State private childCommentEnd: boolean = false;
  @State private childCommentDraft: string = '';
  @State private childSubmitting: boolean = false;
  @State private childReplyTo?: ZhihuCommentItem = undefined;
  @State private activeChildComment?: ZhihuCommentItem = undefined;
  @State private commentRenderVersion: number = 0;
  @State private showRootEmojiPanel: boolean = false;
  @State private showChildEmojiPanel: boolean = false;
  @State private rootCaret: number = 0;
  @State private childCaret: number = 0;
  @State private emojiCols: number = 7;
  @State private emojiItems: EmojiPickerItem[] = [];
  private rootInputController: TextInputController = new TextInputController();
  private childInputController: TextInputController = new TextInputController();

  aboutToAppear(): void {
    const params = router.getParams() as QuestionPageParams;
    this.questionId = params !== undefined && typeof params.questionId === 'string' ? params.questionId : '';
    this.anchorCommentId = params !== undefined && typeof params.anchorCommentId === 'string' ? params.anchorCommentId : '';
    if (params !== undefined && typeof params.title === 'string' && params.title.length > 0) {
      this.questionTitle = params.title;
    }
    if (this.questionId.length === 0) {
      this.detailError = '缺少问题 ID';
      return;
    }
    BrowsingHistoryRepository.recordContent(
      this.context(),
      { kind: 'question', id: this.questionId, title: this.questionTitle },
      this.questionTitle,
      `https://www.zhihu.com/question/${this.questionId}`
    );
    // 上报云端历史
    CloudHistoryService.reportHistory(this.context(), this.questionId, 'question');
    this.loadDetail();
    this.loadFirstPage();
    // 确保知乎贴纸数据就绪，用于表情选择器渲染原版贴纸图
    ZhihuEmojiService.initialize(this.context())
      .then(() => { this.emojiItems = ZhihuEmojiService.getEmojiPickerItems(); })
      .catch(() => {});
  }

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  private showToast(message: string): void {
    promptAction.showToast({
      message,
      duration: 1800
    });
  }

  // 用系统浏览器打开第三方链接（展开详情里的 <a> 超链接）
  private openUrl(url: string): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.startAbility({
        action: 'ohos.want.action.viewData',
        uri: url
      });
    } catch (e) {
      // 打开失败忽略
    }
  }

  private async loadDetail(): Promise<void> {
    try {
      const detail = await QuestionFeedService.loadQuestionDetail(this.context(), this.questionId);
      this.detail = detail;
      if (this.anchorCommentId.length > 0 && !this.anchorConsumed) {
        this.openComments();
      }
      if (detail.title.length > 0) {
        this.questionTitle = detail.title;
      }
      this.detailError = '';
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.detailError = `问题详情加载失败：${message}`;
    }
  }

  private async loadFirstPage(): Promise<void> {
    if (this.answersLoading) {
      return;
    }
    this.answersLoading = true;
    this.answersError = '';
    try {
      const page = await QuestionFeedService.loadFirstPage(
        this.context(),
        this.questionId,
        this.questionTitle,
        this.sortOrder
      );
      this.answers = page.items;
      this.answersNextUrl = page.paging.nextUrl;
      this.answersEnd = page.paging.isEnd || page.paging.nextUrl.length === 0;
      this.answersHasLoaded = true;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.answersError = `回答加载失败：${message}`;
    } finally {
      this.answersLoading = false;
      this.refreshing = false;
    }
  }

  private async loadMoreAnswers(): Promise<void> {
    if (this.answersLoadingMore || this.answersEnd || this.answersNextUrl.length === 0 || !this.answersHasLoaded) {
      return;
    }
    this.answersLoadingMore = true;
    try {
      const page = await QuestionFeedService.loadNextPage(
        this.context(),
        this.questionId,
        this.questionTitle,
        this.answersNextUrl
      );
      const existed = new Set<string>(this.answers.map((item: HomeFeedItem) => item.id));
      const merged = [...this.answers];
      page.items.forEach((item: HomeFeedItem) => {
        if (!existed.has(item.id)) {
          merged.push(item);
        }
      });
      this.answers = merged;
      this.answersNextUrl = page.paging.nextUrl;
      this.answersEnd = page.paging.isEnd || page.paging.nextUrl.length === 0;
      this.answersError = '';
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.answersError = `继续加载失败：${message}`;
    } finally {
      this.answersLoadingMore = false;
    }
  }

  private refreshAll(): void {
    this.answersNextUrl = '';
    this.answersEnd = false;
    this.loadDetail();
    this.loadFirstPage();
  }

  private switchSortOrder(order: QuestionAnswerSortOrder): void {
    if (this.sortOrder === order || this.answersLoading) {
      return;
    }
    this.sortOrder = order;
    this.answers = [];
    this.answersNextUrl = '';
    this.answersEnd = false;
    this.answersHasLoaded = false;
    this.loadFirstPage();
  }

  private async toggleFollow(): Promise<void> {
    const detail = this.detail;
    if (detail === undefined || this.followBusy) {
      return;
    }
    this.followBusy = true;
    const nextFollowing = !detail.isFollowing;
    try {
      await QuestionFeedService.setFollowState(this.context(), this.questionId, nextFollowing);
      this.detail = {
        id: detail.id,
        title: detail.title,
        detailHtml: detail.detailHtml,
        detailText: detail.detailText,
        excerpt: detail.excerpt,
        answerCount: detail.answerCount,
        visitCount: detail.visitCount,
        commentCount: detail.commentCount,
        followerCount: Math.max(0, detail.followerCount + (nextFollowing ? 1 : -1)),
        voteupCount: detail.voteupCount,
        isFollowing: nextFollowing
      };
      this.showToast(nextFollowing ? '已关注问题' : '已取消关注问题');
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.showToast(`操作失败：${message}`);
    } finally {
      this.followBusy = false;
    }
  }

  private openAnswer(item: HomeFeedItem): void {
    const nativeTarget: ZhihuCommentableTarget = item.nativeTarget !== undefined && item.nativeTarget.kind === 'answer'
      ? item.nativeTarget
      : {
        kind: 'answer',
        id: item.id.replace('question-answer:', ''),
        questionId: this.questionId,
        title: this.questionTitle
      };
    // 组装同问题下的回答列表（序列化 nativeTarget），供 Article 页以 Swiper 上下滑动切换上一条/下一条。
    const answerList: string[] = [];
    for (const answer of this.answers) {
      const target = answer.nativeTarget;
      if (target !== undefined && target.kind === 'answer') {
        answerList.push(serializeZhihuContentTarget(target));
      }
    }
    const index = this.answers.findIndex((candidate: HomeFeedItem) => candidate.id === item.id);
    BrowsingHistoryRepository.recordContent(this.context(), nativeTarget, this.questionTitle, item.targetUrl);
    CloudHistoryService.reportViaTarget(this.context(), nativeTarget);
    router.pushUrl({
      url: 'pages/Article',
      params: {
        target: serializeZhihuContentTarget(nativeTarget),
        fallbackTitle: this.questionTitle,
        fallbackUrl: item.targetUrl,
        answerList,
        startIndex: Math.max(0, index),
        questionId: this.questionId,
        questionTitle: this.questionTitle
      }
    });
  }

  private openWebVersion(): void {
    if (this.questionId.length === 0) {
      return;
    }
    router.pushUrl({
      url: 'pages/WebContent',
      params: {
        title: this.questionTitle,
        url: `https://www.zhihu.com/question/${this.questionId}`
      }
    });
  }

  private statsText(): string {
    const detail = this.detail;
    if (detail === undefined) {
      return '';
    }
    return `${formatQuestionCounter(detail.answerCount)} 个回答 · ${formatQuestionCounter(detail.visitCount)} 次浏览 · ${formatQuestionCounter(detail.commentCount)} 条评论 · ${formatQuestionCounter(detail.followerCount)} 人关注`;
  }

  // ===== 问题页四个入口：日志 / 分享 / 评论 / 在知乎中打开 =====

  /** 日志：对标安卓 openZhihuWebUrl("…/log")，内嵌网页版打开问题日志 */
  private openQuestionLog(): void {
    if (this.questionId.length === 0) {
      return;
    }
    router.pushUrl({
      url: 'pages/WebContent',
      params: {
        title: this.questionTitle,
        url: `https://www.zhihu.com/question/${this.questionId}/log`
      }
    });
  }

  /** 系统分享（复用 Article.ets 的 systemShare 实现，拉起系统分享面板） */
  private systemShare(): void {
    if (this.questionId.length === 0) {
      return;
    }
    const url = `https://www.zhihu.com/question/${this.questionId}`;
    const title = this.questionTitle;
    try {
      const text = title.length > 0 ? `${title}\n${url}` : url;
      const data = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: text
      });
      const ctx = getContext(this) as common.UIAbilityContext;
      const controller = new systemShare.ShareController(data);
      controller.show(ctx, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      }).then(() => {
        console.info('[Share] 分享面板已打开');
      }).catch((err: Error) => {
        console.error('[Share] 分享失败:', (err as Object)?.toString() ?? String(err));
      });
    } catch (e) {
      console.error('[Share] 分享异常:', (e as Error)?.message ?? String(e));
      this.showToast('分享失败');
    }
  }

  /** 在知乎 App 中打开（复用 Article.ets 的外部唤起实现） */
  private openInZhihuApp(): void {
    const url = `https://www.zhihu.com/question/${this.questionId}`;
    if (url.length === 0) {
      return;
    }
    this.tryOpenExternal(url);
  }

  /** 用系统能力打开外部链接（浏览器 / 知乎 App） */
  private tryOpenExternal(url: string): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.startAbility({
        action: 'ohos.want.action.viewData',
        uri: url
      });
    } catch (_) {
      this.showToast('打开失败');
    }
  }

  private openPerson(urlToken: string): void {
    if (urlToken.length === 0) {
      return;
    }
    router.pushUrl({
      url: 'pages/People',
      params: { urlToken }
    });
  }

  private openCommentImage(url: string): void {
    commentReopenPending = true;
    this.openImage(url);
  }

  private openCommentLink(url: string): void {
    commentReopenPending = true;
    this.openUrl(url);
  }

  onPageShow(): void {
    if (commentReopenPending) {
      commentReopenPending = false;
      this.showRootCommentSheet = true;
    }
  }

  private openImage(url: string): void {
    if (url.trim().length === 0) {
      return;
    }
    router.pushUrl({
      url: 'pages/WebContent',
      params: {
        title: '图片',
        url
      }
    });
  }

  private commentTarget(): ZhihuCommentableTarget {
    return { kind: 'question', id: this.questionId, title: this.questionTitle };
  }

  private async ensureRootComments(forceReload: boolean = false): Promise<void> {
    const tid = this.questionId;
    if (!forceReload && this.rootComments.length > 0) {
      return;
    }
    if (this.rootCommentLoading && !forceReload) {
      return;
    }
    this.rootCommentLoading = true;
    try {
      const page = await CommentService.loadRootComments(this.context(), this.commentTarget(), this.rootCommentSortOrder);
      this.rootComments = page.items;
      this.rootCommentNextUrl = page.nextUrl;
      this.rootCommentEnd = page.isEnd;
      this.rootCommentError = '';
      this.consumeAnchorComment();
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.rootCommentError = `评论加载失败：${message}`;
    } finally {
      this.rootCommentLoading = false;
    }
  }

  private async loadMoreRootComments(): Promise<void> {
    if (this.rootCommentLoadingMore || this.rootCommentEnd || this.rootCommentNextUrl.length === 0) {
      return;
    }
    this.rootCommentLoadingMore = true;
    try {
      const page = await CommentService.loadRootComments(
        this.context(),
        this.commentTarget(),
        this.rootCommentSortOrder,
        this.rootCommentNextUrl
      );
      this.rootComments = mergeComments(this.rootComments, page.items);
      this.rootCommentNextUrl = page.nextUrl;
      this.rootCommentEnd = page.isEnd;
      this.rootCommentError = '';
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.rootCommentError = `评论继续加载失败：${message}`;
    } finally {
      this.rootCommentLoadingMore = false;
    }
  }

  private async loadChildComments(forceReload: boolean = false): Promise<void> {
    const target = this.childTarget;
    if (target === undefined) {
      return;
    }
    if (forceReload) {
      this.childComments = [];
      this.childCommentNextUrl = '';
      this.childCommentEnd = false;
      this.childCommentError = '';
    }
    if (this.childCommentLoading || (this.childComments.length > 0 && !forceReload)) {
      return;
    }
    this.childCommentLoading = true;
    try {
      const page = await CommentService.loadChildComments(this.context(), target);
      this.childComments = page.items;
      this.childCommentNextUrl = page.nextUrl;
      this.childCommentEnd = page.isEnd;
      this.childCommentError = '';
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.childCommentError = `回复加载失败：${message}`;
    } finally {
      this.childCommentLoading = false;
    }
  }

  private async loadMoreChildComments(): Promise<void> {
    const target = this.childTarget;
    if (target === undefined || this.childCommentLoadingMore || this.childCommentEnd || this.childCommentNextUrl.length === 0) {
      return;
    }
    this.childCommentLoadingMore = true;
    try {
      const page = await CommentService.loadChildComments(this.context(), target, this.childCommentNextUrl);
      this.childComments = mergeComments(this.childComments, page.items);
      this.childCommentNextUrl = page.nextUrl;
      this.childCommentEnd = page.isEnd;
      this.childCommentError = '';
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.childCommentError = `回复继续加载失败：${message}`;
    } finally {
      this.childCommentLoadingMore = false;
    }
  }

  private async submitRootComment(): Promise<void> {
    if (this.rootSubmitting || this.questionId.length === 0) {
      return;
    }
    this.rootSubmitting = true;
    try {
      const created = await CommentService.submitComment(
        this.context(),
        this.commentTarget(),
        this.rootCommentDraft,
        this.rootReplyTo?.id
      );
      this.rootComments = [created, ...this.rootComments];
      this.rootCommentDraft = '';
      this.rootReplyTo = undefined;
      this.showRootEmojiPanel = false;
      if (this.detail !== undefined) {
        const d = this.detail;
        this.detail = {
          id: d.id,
          title: d.title,
          detailHtml: d.detailHtml,
          detailText: d.detailText,
          excerpt: d.excerpt,
          answerCount: d.answerCount,
          visitCount: d.visitCount,
          commentCount: d.commentCount + 1,
          followerCount: d.followerCount,
          voteupCount: d.voteupCount,
          isFollowing: d.isFollowing
        };
      }
      this.showToast('评论已发送');
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.showToast(`发送失败：${message}`);
    } finally {
      this.rootSubmitting = false;
    }
  }

  private async submitChildComment(): Promise<void> {
    const target = this.childTarget;
    if (target === undefined || this.childSubmitting) {
      return;
    }
    this.childSubmitting = true;
    try {
      const created = await CommentService.submitComment(
        this.context(),
        target.article,
        this.childCommentDraft,
        this.childReplyTo?.id ?? target.commentId
      );
      this.childComments = [created, ...this.childComments];
      this.rootComments = appendReplyPreview(this.rootComments, target.commentId, created);
      if (this.activeChildComment !== undefined && this.activeChildComment.id === target.commentId) {
        this.activeChildComment = copyComment(
          this.activeChildComment,
          prependCommentPreview(this.activeChildComment.childComments, created),
          undefined,
          undefined,
          this.activeChildComment.childCommentCount + 1
        );
      }
      this.childCommentDraft = '';
      this.childReplyTo = undefined;
      this.showChildEmojiPanel = false;
      this.showToast('回复已发送');
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.showToast(`发送失败：${message}`);
    } finally {
      this.childSubmitting = false;
    }
  }

  private async toggleCommentLike(commentId: string, liked: boolean, fromChildSheet: boolean): Promise<void> {
    try {
      const nextLiked = await CommentService.toggleLikeComment(this.context(), commentId, liked);
      this.rootComments = updateCommentLike(this.rootComments, commentId, nextLiked);
      this.childComments = updateCommentLike(this.childComments, commentId, nextLiked);
      if (this.activeChildComment !== undefined && this.activeChildComment.id === commentId) {
        this.activeChildComment = copyComment(
          this.activeChildComment,
          this.activeChildComment.childComments,
          nextLiked,
          nextLiked ? this.activeChildComment.likeCount + 1 : Math.max(0, this.activeChildComment.likeCount - 1)
        );
      }
      this.commentRenderVersion += 1;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.showToast(`操作失败：${message}`);
    }
  }

  private openChildComments(comment: ZhihuCommentItem, anchorChildComment?: ZhihuCommentItem): void {
    this.childTarget = {
      kind: 'comment',
      commentId: comment.id,
      article: this.commentTarget()
    };
    this.childComments = [];
    this.childCommentNextUrl = '';
    this.childCommentEnd = false;
    this.childCommentError = '';
    this.childCommentDraft = '';
    this.childReplyTo = undefined;
    this.activeChildComment = comment;
    this.showChildCommentSheet = true;
    this.loadChildComments(true).then(() => {
      if (anchorChildComment !== undefined) {
        this.childComments = [anchorChildComment, ...this.childComments.filter((c) => c.id !== anchorChildComment.id)];
        this.commentRenderVersion += 1;
      }
    });
  }

  // 通知评论定位：把锚点评论置顶到对应位置（根评论置顶；楼中楼则自动展开其根评论的回复层并置顶目标回复）
  private async consumeAnchorComment(): Promise<void> {
    const anchorId = this.anchorCommentId;
    if (anchorId.length === 0 || this.anchorConsumed) {
      return;
    }
    this.anchorConsumed = true;
    try {
      const target = await CommentService.loadCommentDetail(this.context(), anchorId);
      const replyRoot: string = target.replyRootCommentId ?? '';
      let rootId = target.id;
      if (replyRoot.length > 0 && replyRoot !== target.id) {
        rootId = replyRoot;
      }
      const root = rootId === target.id ? target : await CommentService.loadCommentDetail(this.context(), rootId);
      this.rootComments = [root, ...this.rootComments.filter((c) => c.id !== root.id)];
      this.commentRenderVersion += 1;
      if (rootId !== target.id) {
        this.openChildComments(root, target);
      }
    } catch (e) {
      // 忽略，保持 UI 稳定
    }
  }

  private openComments(): void {
    this.showRootCommentSheet = true;
    this.ensureRootComments();
  }

  @Builder
  private TopBar(): void {
    Row({ space: 10 }) {
      Text('返回')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.action_text'))
        .padding({ left: 12, right: 12, top: 9, bottom: 9 })
        .backgroundColor($r('app.color.action_background'))
        .borderRadius(18)
        .onClick(() => {
          router.back({ url: '' });
        })

      Text('问题')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text('网页版')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .onClick(() => {
          this.openWebVersion();
        })
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topSafeAreaVp + 12, bottom: 12 })
    .backgroundColor($r('app.color.glass_top_bar_background'))
    .border({
      width: {
        bottom: 1
      },
      color: $r('app.color.glass_top_bar_border')
    })
    .backdropBlur(28)
  }

  @Builder
  private SortChip(label: string, order: QuestionAnswerSortOrder): void {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.sortOrder === order ? $r('app.color.tab_selected_text') : $r('app.color.text_secondary'))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor(this.sortOrder === order ? $r('app.color.tab_selected_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .border({
        width: 1,
        color: this.sortOrder === order ? $r('app.color.tab_selected_border') : $r('app.color.card_border')
      })
      .borderRadius(16)
      .onClick(() => {
        this.switchSortOrder(order);
      })
  }

  // 对标安卓 QuestionScreen item(2) 第二个 FlowRow（日志/分享/写回答/评论）。
  // 鸿蒙版已打通：日志→内置网页版 /log，分享→系统分享，评论→评论面板，在知乎中打开→外部唤起。
  @Builder
  private ActionButtons(): void {
    Scroll() {
      Row({ space: 10 }) {
        Text('日志')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.action_text'))
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(16)
          .onClick(() => {
            this.openQuestionLog();
          })

        Text(`评论 ${this.detail?.commentCount ?? 0}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(16)
          .onClick(() => {
            this.openComments();
          })

        Text('分享')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(16)
          .onClick(() => {
            this.systemShare();
          })

        Text('在知乎中打开')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(16)
          .onClick(() => {
            this.openInZhihuApp();
          })
      }
      .alignItems(VerticalAlign.Center)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  private QuestionHeader(): void {
    Column({ space: 12 }) {
      // 第一行：标题（用户要求移除返回按钮）
      Row({ space: 10 }) {
        Text(this.questionTitle)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .lineHeight(31)
          .fontColor($r('app.color.text_primary'))
          .copyOption(CopyOptions.InApp)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ left: 16, right: 16, top: this.topSafeAreaVp + 12, bottom: 0 })

      // 以下内容左对齐到"返"字位置（Row的padding-left 16 + 返回按钮padding-left 12 = 28）
      Column({ space: 12 }) {
        if (this.detailError.length > 0) {
          Text(this.detailError)
            .fontSize(12)
            .fontColor($r('app.color.error_text'))
            .width('100%')
        }

        if ((this.detail?.detailText ?? '').length > 0 || (this.detail?.excerpt ?? '').length > 0 || (this.detail?.detailHtml ?? '').length > 0) {
          Column({ space: 8 }) {
            Row() {
              Text('问题详情')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)

              Text(this.detailExpanded ? '收起详情' : '展开详情')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.action_text'))
                .onClick(() => {
                  this.detailExpanded = !this.detailExpanded;
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            if (this.detailExpanded) {
              // 展开后：混合原生渲染（文字 Text+Span + 图片 Image），字号 14fp 与收起态一致；超链接可点击。
              if ((this.detail?.detailHtml ?? '').length > 0) {
                Column({ space: 12 }) {
                  ForEach(
                    parseDetailHtml(this.detail?.detailHtml ?? ''),
                    (block: DetailBlock, index: number) => {
                      if (block.type === 'image') {
                        Image(block.url!)
                          .width('100%')
                          .objectFit(ImageFit.Cover)
                          .borderRadius(8)
                      } else {
                        Text() {
                          ForEach(
                            block.spans ?? [],
                            (span: InlineSpan, si: number) => {
                              if (span.isLink && span.url) {
                                Span(span.text)
                                  .fontSize(14)
                                  .fontColor('#1565C0')
                                  .decoration({ type: TextDecorationType.Underline, color: '#1565C0' })
                                  .onClick(() => {
                                    this.openUrl(span.url!);
                                  })
                              } else {
                                Span(span.text)
                                  .fontSize(14)
                                  .fontColor($r('app.color.text_secondary'))
                              }
                            },
                            (span: InlineSpan, si: number) => `${si}_${span.isLink ? 'link' : 'text'}`
                          )
                        }
                        .fontSize(14)
                        .lineHeight(22)
                        .fontColor($r('app.color.text_secondary'))
                        .width('100%')
                        .copyOption(CopyOptions.LocalDevice)
                      }
                    },
                    (block: DetailBlock, index: number) =>
                      `${index}_${block.type}_${(block.url ?? block.spans?.[0]?.text ?? '').substring(0, 16)}`
                  )
                }
                .width('100%')
              } else {
                Text(this.detail?.detailText ?? this.detail?.excerpt ?? '')
                  .fontSize(14)
                  .lineHeight(22)
                  .fontColor($r('app.color.text_secondary'))
                  .copyOption(CopyOptions.LocalDevice)
                  .width('100%')
              }
            } else {
              Text((this.detail?.detailText ?? this.detail?.excerpt ?? '').length > 0
                ? (this.detail?.detailText ?? this.detail?.excerpt ?? '')
                : '（点击展开查看问题描述）')
                .fontSize(14)
                .lineHeight(22)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .copyOption(CopyOptions.LocalDevice)
            }
          }
          .width('100%')
          .padding({ left: 0, right: 14, top: 14, bottom: 14 })
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(14)
        }

        Row({ space: 8 }) {
          Text('排序：')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))

          this.SortChip('默认', 'default');
          this.SortChip('最新', 'updated');

          Blank()

          Text(this.detail?.isFollowing === true ? '已关注' : '关注问题')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.detail?.isFollowing === true ? $r('app.color.text_secondary') : $r('app.color.action_text'))
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .backgroundColor(this.detail?.isFollowing === true ? ThemeColors.cardBackground(this.oledBlack, this.isDark) : $r('app.color.action_background'))
            .border({ width: 1, color: $r('app.color.card_border') })
            .borderRadius(16)
            .enabled(this.detail !== undefined && !this.followBusy)
            .onClick(() => {
              this.toggleFollow();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        this.ActionButtons();

        if (this.statsText().length > 0) {
          Text(this.statsText())
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      // 返回按钮已移除：标题左边缘在 16vp，下面内容同列对齐
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .padding({ left: 0, right: 0, top: 14, bottom: 6 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private AnswerCard(item: HomeFeedItem): void {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        if (item.authorAvatarUrl.length > 0) {
          Image(item.authorAvatarUrl)
            .width(38)
            .height(38)
            .objectFit(ImageFit.Cover)
            .borderRadius(19)
            .clip(true)
        } else {
          Column() {
            Text(item.authorName.length > 0 ? item.authorName.slice(0, 1) : '答')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.action_text'))
          }
          .width(38)
          .height(38)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(19)
        }

        Column({ space: 2 }) {
          Text(item.authorName.length > 0 ? item.authorName : '匿名用户')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))

          if (item.authorHeadline.length > 0) {
            Text(item.authorHeadline)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Row({ space: 12 }) {
        Column({ space: 8 }) {
      if (item.summary.length > 0) {
        Text(item.summary)
          .fontSize(14)
          .lineHeight(22)
          .fontColor($r('app.color.text_primary'))
          .maxLines(4)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          Text(item.details)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
          this.openAnswer(item);
        })

        if (item.thumbnailUrl.length > 0) {
          Image(item.thumbnailUrl)
            .width(88)
            .height(88)
            .objectFit(ImageFit.Cover)
            .borderRadius(12)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .padding(16)
    .margin({ left: 16, right: 16, bottom: 12 })
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .border({
      width: 1,
      color: $r('app.color.card_border')
    })
    .borderRadius(18)
    .clip(true)
    .onClick(() => {
      this.openAnswer(item);
    })
  }

  @Builder
  private AnswerListState(): void {
    if (this.answersLoading && !this.answersHasLoaded) {
      Column({ space: 12 }) {
        LoadingProgress()
          .width(34)
          .height(34)
          .color($r('app.color.action_text'))
        Text('正在加载回答...')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ top: 46, bottom: 46 })
      .alignItems(HorizontalAlign.Center)
    } else if (this.answersError.length > 0 && !this.answersHasLoaded) {
      Column({ space: 12 }) {
        Text(this.answersError)
          .fontSize(13)
          .fontColor($r('app.color.error_text'))
          .textAlign(TextAlign.Center)

        Text('重试')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.action_text'))
          .padding({ left: 18, right: 18, top: 9, bottom: 9 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(18)
          .onClick(() => {
            this.loadFirstPage();
          })
      }
      .width('100%')
      .padding({ top: 38, bottom: 38, left: 24, right: 24 })
      .alignItems(HorizontalAlign.Center)
    } else if (this.answersHasLoaded && this.answers.length === 0) {
      Text('暂时没有回答')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 42, bottom: 42 })
    } else {
      ForEach(this.answers, (item: HomeFeedItem) => {
        this.AnswerCard(item);
      }, (item: HomeFeedItem) => item.id)

      if (!this.answersEnd && this.answersHasLoaded && this.answers.length > 0 && !this.answersLoadingMore) {
        Row({ space: 8 }) {
          Text('加载更多回答')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.action_text'))
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 10, bottom: 18 })
        .onClick(() => {
          this.loadMoreAnswers();
        })
      }

      if (this.answersError.length > 0) {
        Text(this.answersError)
          .fontSize(12)
          .fontColor($r('app.color.error_text'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 2, bottom: 10 })
      }

      if (this.answersLoadingMore) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color($r('app.color.action_text'))
          Text('正在加载更多...')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 6, bottom: 18 })
      } else if (this.answersEnd) {
        Text('已经到底了')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 6, bottom: 18 })
      }
    }
  }

  @Builder
  private CommentSortChip(label: string, selected: boolean, onClick: () => void): void {
    Text(label)
      .fontSize(12)
      .fontWeight(selected ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(selected ? $r('app.color.action_text') : $r('app.color.text_secondary'))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor(selected ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .borderRadius(16)
      .border({
        width: 1,
        color: selected ? $r('app.color.action_background') : $r('app.color.card_border')
      })
      .onClick(() => {
        onClick();
      })
  }

  @Builder
  private CommentSheetStatus(message: string, error: boolean = false): void {
    Column({ space: 8 }) {
      Text(message)
        .fontSize(14)
        .textAlign(TextAlign.Center)
        .fontColor(error ? $r('app.color.error_text') : $r('app.color.text_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 28, right: 28, top: 36, bottom: 36 })
  }

  private emojiColumnsTemplate(): string {
    return Array(this.emojiCols).fill('1fr').join(' ');
  }

  @Builder
  private EmojiPanel(isChild: boolean): void {
    Grid() {
      ForEach(this.emojiItems, (item: EmojiPickerItem) => {
        GridItem() {
          if (item.dataUrl !== undefined) {
            Image(item.dataUrl)
              .width(30)
              .height(30)
              .objectFit(ImageFit.Contain)
          } else {
            Text(item.fallback ?? '')
              .fontSize(28)
              .textAlign(TextAlign.Center)
              .width('100%')
              .height('100%')
              .maxLines(1)
          }
        }
        .width('100%')
        .aspectRatio(1)
        .onClick(() => {
          const draft = isChild ? this.childCommentDraft : this.rootCommentDraft;
          const caret = isChild ? this.childCaret : this.rootCaret;
          const insert = `[${item.token}]`;
          const safeCaret = caret >= 0 && caret <= draft.length ? caret : draft.length;
          const next = draft.slice(0, safeCaret) + insert + draft.slice(safeCaret);
          const newCaret = safeCaret + insert.length;
          if (isChild) {
            this.childCommentDraft = next;
            this.childCaret = newCaret;
          } else {
            this.rootCommentDraft = next;
            this.rootCaret = newCaret;
          }
          const controller = isChild ? this.childInputController : this.rootInputController;
          controller.caretPosition(newCaret);
        })
      }, (item: EmojiPickerItem) => item.token)
    }
    .columnsTemplate(this.emojiColumnsTemplate())
    .columnsGap(8)
    .rowsGap(8)
    .onAreaChange((_old: Area, newValue: Area) => {
      const w = Number(newValue.width);
      if (w > 0) {
        const cols = Math.max(4, Math.floor((w + 8) / (48 + 8)));
        if (cols !== this.emojiCols) {
          this.emojiCols = cols;
        }
      }
    })
    .padding({ left: 12, right: 12, top: 12, bottom: this.bottomSafeAreaVp + 12 })
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .width('100%')
    .height(240)
    .scrollBar(BarState.Off)
  }

  @Builder
  private CommentListLoadMore(label: string, enabled: boolean, onClick: () => void): void {
    Row() {
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(enabled ? $r('app.color.action_text') : $r('app.color.text_tertiary'))
    }
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.card_border') })
    .enabled(enabled)
    .onClick(() => {
      onClick();
    })
  }

  private resolveReplyTo(isChild: boolean): ZhihuCommentItem | undefined {
    return isChild ? this.childReplyTo : this.rootReplyTo;
  }

  private liveCommentDraft(isChild: boolean): string {
    return isChild ? this.childCommentDraft : this.rootCommentDraft;
  }

  private liveCommentSubmitting(isChild: boolean): boolean {
    return isChild ? this.childSubmitting : this.rootSubmitting;
  }

  private liveEmojiPanelOpen(isChild: boolean): boolean {
    return isChild ? this.showChildEmojiPanel : this.showRootEmojiPanel;
  }

  @Builder
  private CommentInputBar(
    draft: string,
    isChild: boolean,
    submitting: boolean,
    showEmoji: boolean,
    inputController: TextInputController,
    onDraftChange: (value: string) => void,
    onClearReply: () => void,
    onToggleEmoji: () => void,
    onSubmit: () => void
  ): void {
    Column({ space: 0 }) {
      if (this.resolveReplyTo(isChild) !== undefined) {
        Row({ space: 8 }) {
          Text(`回复 ${this.resolveReplyTo(isChild)?.author.name ?? ''}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.action_text'))
            .layoutWeight(1)

          Text('取消')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => {
              onClearReply();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 9, bottom: 9 })
        .backgroundColor($r('app.color.action_background'))
        .borderRadius(14)
      }

      Row({ space: 10 }) {
        if (this.liveEmojiPanelOpen(isChild)) {
          Image($r('app.media.ic_keyboard'))
            .width(26)
            .height(26)
            .fillColor($r('app.color.text_secondary'))
            .renderMode(ImageRenderMode.Template)
            .onClick(() => {
              onToggleEmoji();
            })
        } else {
          Image($r('app.media.ic_emoji'))
            .width(26)
            .height(26)
            .fillColor($r('app.color.text_secondary'))
            .renderMode(ImageRenderMode.Template)
            .onClick(() => {
              onToggleEmoji();
            })
        }

        TextArea({
          controller: inputController,
          text: this.liveCommentDraft(isChild),
          placeholder: this.resolveReplyTo(isChild) !== undefined ? `回复 ${this.resolveReplyTo(isChild)?.author.name ?? ''}...` : '写下你的评论...'
        })
          .layoutWeight(1)
          .maxLines(5)
          .enterKeyType(EnterKeyType.NEW_LINE)
          .constraintSize({ minHeight: 44 })
          .id(isChild ? 'childCommentInput' : 'rootCommentInput')
          .focusable(true)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .borderRadius(22)
          .border({ width: 1, color: $r('app.color.card_border') })
          .padding({ left: 14, right: 14 })
          .onChange((value: string) => {
            onDraftChange(value);
          })
          .onTextSelectionChange((_start: number, end: number) => {
            if (isChild) {
              this.childCaret = end;
            } else {
              this.rootCaret = end;
            }
          })
          .onFocus(() => {
            if (isChild) {
              this.showChildEmojiPanel = false;
            } else {
              this.showRootEmojiPanel = false;
            }
          })

        Text(this.liveCommentSubmitting(isChild) ? '发送中' : '发送')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(
            this.liveCommentSubmitting(isChild) || this.liveCommentDraft(isChild).trim().length === 0
              ? $r('app.color.text_tertiary')
              : $r('app.color.action_text')
          )
          .padding({ left: 16, right: 16, top: 11, bottom: 11 })
          .backgroundColor(
            this.liveCommentDraft(isChild).trim().length === 0
              ? ThemeColors.feedBackground(this.oledBlack, this.isDark)
              : $r('app.color.action_background')
          )
          .borderRadius(20)
          .border({ width: 1, color: $r('app.color.card_border') })
          .enabled(!this.liveCommentSubmitting(isChild) && this.liveCommentDraft(isChild).trim().length > 0)
          .onClick(() => {
            onSubmit();
          })
      }
      .width('100%')
      .margin({ top: this.resolveReplyTo(isChild) !== undefined ? 10 : 0 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: this.liveEmojiPanelOpen(isChild) ? 10 : this.bottomSafeAreaVp + 10 })
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .border({
      width: {
        top: 1
      },
      color: $r('app.color.card_border')
    })
  }

  @Builder
  private CommentCard(
    comment: ZhihuCommentItem,
    fromChildSheet: boolean,
    compact: boolean = false,
    showReplyThreadEntry: boolean = true
  ): void {
    Column({ space: compact ? 8 : 10 }) {
      Row({ space: 10 }) {
        if (comment.author.avatarUrl.length > 0) {
          Image(comment.author.avatarUrl)
            .width(compact ? 30 : 36)
            .height(compact ? 30 : 36)
            .objectFit(ImageFit.Cover)
            .borderRadius(compact ? 15 : 18)
            .onClick(() => {
              this.openPerson(comment.author.urlToken);
            })
        } else {
          Column() {
            Text(comment.author.name.slice(0, 1))
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.action_text'))
          }
          .width(compact ? 30 : 36)
          .height(compact ? 30 : 36)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(compact ? 15 : 18)
          .onClick(() => {
            this.openPerson(comment.author.urlToken);
          })
        }

        Column({ space: compact ? 4 : 6 }) {
          Row({ space: 6 }) {
            Text(comment.author.name)
              .fontSize(compact ? 13 : 15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .onClick(() => {
                this.openPerson(comment.author.urlToken);
              })

            if (comment.authorTag.length > 0) {
              Text(comment.authorTag)
                .fontSize(11)
                .fontColor($r('app.color.action_text'))
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor($r('app.color.action_background'))
                .borderRadius(10)
            }

            if (comment.replyToAuthor !== undefined) {
              Text(`回复 ${comment.replyToAuthor.name}`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick(() => {
                  this.openPerson(comment.replyToAuthor?.urlToken ?? '');
                })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text() {
            ForEach(
              ZhihuEmojiService.parseCommentContent(comment.contentHtml),
              (seg: CommentContentSegment) => {
                if (seg.kind === 'emoji' && seg.dataUrl !== undefined) {
                  ImageSpan(seg.dataUrl)
                    .width(compact ? 16 : 18)
                    .height(compact ? 16 : 18)
                    .verticalAlign(ImageSpanAlignment.CENTER)
                    .margin({ left: 1, right: 1 })
                } else if (seg.kind === 'link' && seg.url) {
                  Span(seg.text ?? '')
                    .fontSize(compact ? 13 : 15)
                    .fontColor('#1565C0')
                    .decoration({ type: TextDecorationType.Underline, color: '#1565C0' })
                    .onClick(() => {
                      this.openCommentLink(seg.url!);
                    })
                } else {
                  Span(seg.text ?? '')
                    .fontSize(compact ? 13 : 15)
                }
              },
              (seg: CommentContentSegment) => `${seg.kind}_${seg.text ?? ''}_${seg.url ?? ''}_${seg.alt ?? ''}`
            )
          }
          .width('100%')
          .fontSize(compact ? 13 : 15)
          .lineHeight(compact ? 20 : 23)
          .fontColor($r('app.color.text_primary'))
          .copyOption(CopyOptions.LocalDevice)

          if (comment.previewImageUrl.length > 0) {
            Image(comment.previewImageUrl)
              .width(compact ? 128 : 180)
              .height(compact ? 96 : 120)
              .objectFit(ImageFit.Cover)
              .borderRadius(12)
              .onClick(() => {
                this.openCommentImage(comment.previewImageUrl);
              })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row({ space: 8 }) {
        Row({ space: 8 }) {
          Text(formatUnixTime(comment.createdTime))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)

          if (comment.ipInfo.length > 0) {
            Text(comment.ipInfo)
              .layoutWeight(1)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)

        Row({ space: 12 }) {
          Row({ space: 4 }) {
            Image($r('app.media.ic_comment'))
              .width(16)
              .height(16)
              .renderMode(ImageRenderMode.Template)
              .fillColor($r('app.color.action_pill_icon'))
              .draggable(false)
              .syncLoad(true)
              .interpolation(ImageInterpolation.Low)

            if (!fromChildSheet && comment.childCommentCount > 0) {
              Text(`${comment.childCommentCount}`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
          }
          .padding({ left: 4, right: 4, top: 4, bottom: 4 })
          .onClick(() => {
            if (fromChildSheet) {
              this.childReplyTo = comment;
              this.commentRenderVersion += 1;
            } else {
              this.openChildComments(comment);
            }
          })
          .alignItems(VerticalAlign.Center)

          Row({ space: 4 }) {
            Image($r('app.media.ic_agree'))
              .width(16)
              .height(16)
              .renderMode(ImageRenderMode.Template)
              .fillColor(comment.liked ? $r('app.color.action_text') : $r('app.color.action_pill_icon'))
              .draggable(false)
              .syncLoad(true)
              .interpolation(ImageInterpolation.Low)

            Text(`${comment.likeCount}`)
              .fontSize(12)
              .fontColor(comment.liked ? $r('app.color.action_text') : $r('app.color.text_secondary'))
          }
          .padding({ left: 4, right: 4, top: 4, bottom: 4 })
          .onClick(() => {
            this.toggleCommentLike(comment.id, comment.liked, fromChildSheet);
          })
          .alignItems(VerticalAlign.Center)
        }
        .constraintSize({
          minWidth: 84
        })
        .justifyContent(FlexAlign.End)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: compact ? 40 : COMMENT_FOOTER_INDENT })
      .alignItems(VerticalAlign.Center)

      if (!fromChildSheet && !compact && comment.childComments.length > 0) {
        Column() {
          Column({ space: 10 }) {
            ForEach(comment.childComments.slice(0, COMMENT_CHILD_PREVIEW_LIMIT), (item: ZhihuCommentItem) => {
              this.CommentCard(item, false, true);
            }, (item: ZhihuCommentItem) => `${item.id}:${this.commentRenderVersion}`)
          }
          .width('100%')
          .padding({ left: 10 })
          .border({ width: { left: 2 }, color: $r('app.color.card_border') })
        }
        .width('100%')
        .padding({ left: COMMENT_CHILD_INDENT })
      }

      if (!fromChildSheet && !compact && showReplyThreadEntry && comment.childCommentCount > 0) {
        Row() {
          Row({ space: 6 }) {
            Text(`查看 ${comment.childCommentCount} 条子评论`)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
          .borderRadius(16)
          .border({ width: 1, color: $r('app.color.card_border') })
          .onClick(() => {
            this.openChildComments(comment);
          })
        }
        .width('100%')
        .padding({ left: COMMENT_CHILD_INDENT })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: compact ? 0 : 8, bottom: compact ? 0 : 8 })
  }

  @Builder
  private RootCommentSheet(): void {
    Column() {
      Column({ space: 12 }) {
        Text('评论')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(`${this.detail?.commentCount ?? 0} 条评论`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))

        Row({ space: 10 }) {
          if (this.rootCommentSortOrder === 'score') {
            this.CommentSortChip('最热', true, () => {
              if (this.rootCommentSortOrder !== 'score') {
                this.rootCommentSortOrder = 'score';
                this.ensureRootComments(true);
              }
            })
          } else {
            this.CommentSortChip('最热', false, () => {
              if (this.rootCommentSortOrder !== 'score') {
                this.rootCommentSortOrder = 'score';
                this.ensureRootComments(true);
              }
            })
          }

          if (this.rootCommentSortOrder === 'time') {
            this.CommentSortChip('最新', true, () => {
              if (this.rootCommentSortOrder !== 'time') {
                this.rootCommentSortOrder = 'time';
                this.ensureRootComments(true);
              }
            })
          } else {
            this.CommentSortChip('最新', false, () => {
              if (this.rootCommentSortOrder !== 'time') {
                this.rootCommentSortOrder = 'time';
                this.ensureRootComments(true);
              }
            })
          }
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 18, bottom: 14 })

      Scroll() {
        Column({ space: 16 }) {
          if (this.rootCommentLoading && this.rootComments.length === 0) {
            this.CommentSheetStatus('正在加载评论...')
          } else if (this.rootCommentError.length > 0 && this.rootComments.length === 0) {
            this.CommentSheetStatus(this.rootCommentError, true)
          } else if (this.rootComments.length === 0) {
            this.CommentSheetStatus('还没有评论，抢先说点什么。')
          } else {
            ForEach(this.rootComments, (item: ZhihuCommentItem) => {
              this.CommentCard(item, false);
            }, (item: ZhihuCommentItem) => `${item.id}:${this.commentRenderVersion}`)
          }

          if (this.rootComments.length > 0) {
            this.CommentListLoadMore(
              this.rootCommentEnd ? '没有更多评论了' : (this.rootCommentLoadingMore ? '正在加载更多...' : '加载更多评论'),
              !this.rootCommentEnd && !this.rootCommentLoadingMore,
              () => {
                this.loadMoreRootComments();
              }
            )
          }
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
        .padding({ left: 16, right: 16, top: 4, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      this.CommentInputBar(
        this.rootCommentDraft,
        false,
        this.rootSubmitting,
        this.showRootEmojiPanel,
        this.rootInputController,
        (value: string) => {
          this.rootCommentDraft = value;
        },
        () => {
          this.rootReplyTo = undefined;
        },
        () => {
          this.showRootEmojiPanel = !this.showRootEmojiPanel;
          if (!this.showRootEmojiPanel) {
            this.rootInputController.caretPosition(this.rootCommentDraft.length)
focusControl.requestFocus('rootCommentInput');
          } else {
            this.rootInputController.stopEditing();
          }
        },
        () => {
          this.submitRootComment();
        }
      )

      if (this.showRootEmojiPanel) {
        this.EmojiPanel(false)
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
  }

  @Builder
  private ChildCommentSheet(): void {
    Column() {
      Column({ space: 6 }) {
        Text('回复')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(`${this.activeChildComment?.childCommentCount ?? this.childComments.length} 条回复`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 18, bottom: 14 })

      Scroll() {
        Column({ space: 16 }) {
          if (this.activeChildComment !== undefined) {
            Column({ space: 12 }) {
              Text('原评论')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))

              this.CommentCard(this.activeChildComment, true, false, false)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 14, bottom: 14 })
            .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .borderRadius(18)
            .border({ width: 1, color: $r('app.color.card_border') })
          }

          if (this.childCommentLoading && this.childComments.length === 0) {
            this.CommentSheetStatus('正在加载回复...')
          } else if (this.childCommentError.length > 0 && this.childComments.length === 0) {
            this.CommentSheetStatus(this.childCommentError, true)
          } else if (this.childComments.length === 0) {
            this.CommentSheetStatus('暂时还没有回复。')
          } else {
            ForEach(this.childComments, (item: ZhihuCommentItem) => {
              this.CommentCard(item, true);
            }, (item: ZhihuCommentItem) => `${item.id}:${this.commentRenderVersion}`)
          }

          if (this.childComments.length > 0) {
            this.CommentListLoadMore(
              this.childCommentEnd ? '没有更多回复了' : (this.childCommentLoadingMore ? '正在加载更多...' : '加载更多回复'),
              !this.childCommentEnd && !this.childCommentLoadingMore,
              () => {
                this.loadMoreChildComments();
              }
            )
          }
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
        .padding({ left: 16, right: 16, top: 4, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      this.CommentInputBar(
        this.childCommentDraft,
        true,
        this.childSubmitting,
        this.showChildEmojiPanel,
        this.childInputController,
        (value: string) => {
          this.childCommentDraft = value;
        },
        () => {
          this.childReplyTo = undefined;
        },
        () => {
          this.showChildEmojiPanel = !this.showChildEmojiPanel;
          if (!this.showChildEmojiPanel) {
            this.childInputController.caretPosition(this.childCommentDraft.length)
focusControl.requestFocus('childCommentInput');
          } else {
            this.childInputController.stopEditing();
          }
        },
        () => {
          this.submitChildComment();
        }
      )

      if (this.showChildEmojiPanel) {
        this.EmojiPanel(true)
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
  }

  build() {
    Column() {
      Refresh({ refreshing: $$this.refreshing }) {
        List() {
          ListItem() {
            this.QuestionHeader();
          }

          ListItem() {
            Column() {
              this.AnswerListState();
            }
            .width('100%')
          }

          ListItem() {
            Column()
              .width('100%')
              .height(this.bottomSafeAreaVp + 24)
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => {
          this.loadMoreAnswers();
        })
      }
      .onRefreshing(() => {
        this.refreshAll();
      })
      .width('100%')
      .layoutWeight(1)

      // 评论面板（根评论 / 子评论），统一走 ThemeColors 主题（浅蓝/白 + OLED黑/非OLED黑）
      Column()
        .width(1)
        .height(1)
        .bindSheet($$this.showRootCommentSheet, this.RootCommentSheet(), {
          showClose: false,
          dragBar: true,
          preferType: SheetType.BOTTOM,
          detents: [SheetSize.LARGE],
          backgroundColor: ThemeColors.feedBackground(this.oledBlack, this.isDark),
          onDisappear: () => {
            this.showRootCommentSheet = false;
            this.rootReplyTo = undefined;
          },
          onWillDismiss: (action: DismissSheetAction) => {
            if (this.showRootEmojiPanel || this.showChildEmojiPanel) {
              this.showRootEmojiPanel = false;
              this.showChildEmojiPanel = false;
            } else {
              action.dismiss();
            }
          }
        })

      Column()
        .width(1)
        .height(1)
        .bindSheet($$this.showChildCommentSheet, this.ChildCommentSheet(), {
          showClose: false,
          dragBar: true,
          preferType: SheetType.BOTTOM,
          detents: [SheetSize.LARGE],
          backgroundColor: ThemeColors.feedBackground(this.oledBlack, this.isDark),
          onDisappear: () => {
            this.showChildCommentSheet = false;
            this.childReplyTo = undefined;
            this.activeChildComment = undefined;
          },
          onWillDismiss: (action: DismissSheetAction) => {
            if (this.showRootEmojiPanel || this.showChildEmojiPanel) {
              this.showRootEmojiPanel = false;
              this.showChildEmojiPanel = false;
            } else {
              action.dismiss();
            }
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
