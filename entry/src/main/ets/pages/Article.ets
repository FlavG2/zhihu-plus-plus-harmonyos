import common from '@ohos.app.ability.common';
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { promptAction, router, curves, window } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import fileUri from '@ohos.file.fileuri';
import { HdsNavDestination, HdsTabs, HdsTabsController, HdsAnimationMode } from '@kit.UIDesignKit';
import { ZhihuMaterial } from '../services/ZhihuMaterial';
import vibrator from '@ohos.vibrator';
import {
  ArticlePageParams,
  CommentSortOrder,
  contentTargetDisplayTitle,
  parseZhihuContentTarget,
  rootContentTarget,
  serializeZhihuContentTarget,
  ZhihuCommentableTarget,
  ZhihuCommentItem,
  ZhihuCommentTarget,
  ZhihuContentDetail,
  ZhihuContentTarget,
  ZhihuSegmentParagraph,
  ZhihuVoteState
} from '../models/ZhihuContentModels';
import { SessionSnapshot, DEFAULT_SESSION_SNAPSHOT, HomeFeedItem, ZhihuCollection } from '../models/ZhihuModels';
import { ZhihuRichWeb } from '../components/ZhihuRichWeb';
import { DraggableFab } from '../components/DraggableFab';
import { ContentTopBar } from '../components/ContentTopBar';
import { ArticleDetailService } from '../services/ArticleDetailService';
import { QuestionFeedService } from '../services/QuestionFeedService';
import { AppearanceSettingsRepository, AppearanceThemeMode } from '../services/AppearanceSettingsRepository';
import { ThemeColors } from '../services/ThemeColors';
import { BrowsingHistoryRepository } from '../services/BrowsingHistoryRepository';
import { CloudHistoryService } from '../services/CloudHistoryService';
import { CommentService } from '../services/CommentService';
import { CollectionService } from '../services/CollectionService';
import { ZhihuSessionRepository } from '../services/ZhihuSessionRepository';
import { resolveZhihuContent } from '../services/ZhihuContentResolver';
import { ZhihuApi } from '../services/ZhihuApi';
import { ZhihuEmojiItem, EmojiPickerItem, ZhihuEmojiService, CommentContentSegment } from '../services/ZhihuEmojiService';
import { startSummary as startSummaryStream, SummaryOptions } from '../services/SummaryService';
import { TtsController } from '../services/TtsService';
import {
  ArticleExportMeta,
  buildExportHtml,
  buildExportMarkdown,
  buildCommentsHtml,
  buildExportFileName,
  saveTextFile,
  copyText
} from '../services/ExportService';
import {
  buildArticleHtmlDocument,
  escapeHtml,
  stripCommentImageLinks,
  type ArticleSummaryData
} from '../utils/ZhihuHtml';
import { resolveZhihuThemeMode, ZhihuSegmentTapInfo } from '../utils/ZhihuWebBridge';
import { formatTimestamp } from '../utils/Time';

interface SegmentInjectionPayload {
  allow: boolean;
  sourceUrl: string;
  contentId: string;
  contentType: string;
  paragraphs: ZhihuSegmentParagraph[];
}

interface SegmentLikePositionOffset {
  paragraph_id: string;
  offset: number;
}

interface SegmentLikePosition {
  start: SegmentLikePositionOffset;
  end: SegmentLikePositionOffset;
}

interface SegmentLikeBody {
  seg_id: string;
  content: string;
  position: SegmentLikePosition;
}

interface SegmentUnlikeBody {
  seg_ids: string;
}

interface DialogResult {
  index: number;
}

const COMMENT_FOOTER_INDENT: number = 46;

// 评论内点击图片/链接跳 WebContent 后，返回需重开评论 sheet（而非落回内容页）
let commentReopenPending: boolean = false;
const COMMENT_CHILD_INDENT: number = 44;
const COMMENT_CHILD_PREVIEW_LIMIT: number = 2;

// 评论正文超链接：复用问题页同款解析，把 HTML 拆成「纯文本 / 超链接」行内片段，蓝色可点击。
function stripHtmlToPlainText(html: string): string {
  let text = html ?? '';
  text = text.replace(/<br\s*\/?>/gi, '\n');
  text = text.replace(/<\/(p|div|li|h[1-6]|blockquote)>/gi, '\n');
  text = text.replace(/<[^>]+>/g, '');
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
  text = text.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
  return text;
}

interface InlineSpan {
  text: string;
  isLink: boolean;
  url?: string;
}

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

// 左右滑动切换回答：手势/阻尼/灵敏度参数（对齐安卓 AnswerHorizontalOverscroll）
const ANSWER_SWITCH_MAX_OVERSCROLL_VP: number = 300;
const ANSWER_SWITCH_TRIGGER_VP: number = 46;
const ANSWER_SWITCH_DAMPING: number = 1.2;
const ANSWER_SWITCH_SENSITIVITY: number = 1;
// 拖动时主内容模糊：起手最大模糊半径，拖到屏宽该比例时完全清晰（对齐用户"30% 无模糊"需求）
const ANSWER_SWITCH_BLUR_MAX_VP: number = 12;
const ANSWER_SWITCH_BLUR_CLEAR_RATIO: number = 0.3;
// 顶栏改为 ContentTopBar 悬浮栏后，正文摘要卡片需要下移避开「返回+⋮」栏（不含状态栏的高度）
const ARTICLE_TOP_BAR_CLEARANCE_VP: number = 56;

function formatCounter(value: number, unit: string): string {
  if (value >= 10000) {
    return `${(value / 10000).toFixed(value >= 100000 ? 0 : 1)} 万${unit}`;
  }
  return `${value} ${unit}`;
}

function formatVoteCount(value: number): string {
  if (value >= 10000) {
    return `${(value / 10000).toFixed(value >= 100000 ? 0 : 1)} 万`;
  }
  return `${value}`;
}

function formatUnixTime(seconds: number): string {
  if (seconds <= 0) {
    return '';
  }
  return formatTimestamp(new Date(seconds * 1000));
}

// 通知「回复了你的评论」：API 只给根评论（reply_root_id），回复 B 的 ID 不在 payload，
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

function copyDetail(
  detail: ZhihuContentDetail,
  voteCount?: number,
  voteState?: ZhihuVoteState,
  commentCount?: number
): ZhihuContentDetail {
  return {
    target: detail.target,
    title: detail.title,
    browserUrl: detail.browserUrl,
    author: detail.author,
    excerpt: detail.excerpt,
    htmlContent: detail.htmlContent,
    commentCount: commentCount ?? detail.commentCount,
    voteCount: voteCount ?? detail.voteCount,
    voteState: voteState ?? detail.voteState,
    createdTime: detail.createdTime,
    updatedTime: detail.updatedTime,
    ipInfo: detail.ipInfo,
    questionId: detail.questionId,
    questionTitle: detail.questionTitle,
    canComment: detail.canComment,
    canVote: detail.canVote,
    supportsDownvote: detail.supportsDownvote
  };
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
struct Article {
  @StorageProp('cardPadding') private cardPadding: number = 16;
  @StorageProp('buttonRadius') private buttonRadius: number = 20;
  @StorageProp('fontSymbol') private fontSymbol: string = '24fp';
  @StorageProp('fontSubhead') private fontSubhead: string = '18fp';
  @StorageProp('cardRadius') private cardRadius: number = 16;
  @StorageProp('fontHeading') private fontHeading: string = '20fp';
  @StorageProp('fontBody') private fontBody: string = '16fp';
  @StorageProp('fontMeta') private fontMeta: string = '13fp';
  @StorageProp('fontCaption') private fontCaption: string = '12fp';
  @StorageProp('pillRadius') private pillRadius: number = 18;
  @StorageProp('fontSecondary') private fontSecondary: string = '14fp';
  @StorageProp('fontLargeTitle') private fontLargeTitle: string = '26fp';
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageProp('bottomSafeAreaVp') private bottomSafeAreaVp: number = 0;
  @StorageProp('themeMode') private themeMode: AppearanceThemeMode = 'system';
  @StorageProp('materialLevel') private materialLevel: number = 10;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;
  @StorageLink('buttonSkipAnswer') private buttonSkipAnswer: boolean = false;
  @StorageLink('autoHideSkipAnswerButton') private autoHideSkipAnswerButton: boolean = false;
  @StorageProp('sessionSnapshot') private sessionSnapshot: SessionSnapshot = DEFAULT_SESSION_SNAPSHOT;
  @State private target?: ZhihuContentTarget = undefined;
  @State private fallbackTitle: string = '';
  @State private fallbackUrl: string = '';
  @State private detail?: ZhihuContentDetail = undefined;
  @State private pageTitle: string = '内容详情';
  @State private articleLoading: boolean = true;
  @State private articleError: string = '';
  @State private showRootCommentSheet: boolean = false;
  @State private showSegmentSheet: boolean = false;
  @State private selectedSegment: ZhihuSegmentTapInfo | null = null;
  @State private segmentLiking: boolean = false;
  @State private currentSegmentForComments: ZhihuSegmentTapInfo | null = null;
  @State private rootCommentCacheKey: string = '';
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
  // 评论所属回答的 target.id：确保 rootComments 永远只属于当前 this.detail 指向的回答（修复左右滑动后评论区停在旧回答）
  @State private rootCommentTargetId: string = '';
  // 收藏夹：当前内容已加入的收藏夹列表（含 isFavorited 状态）
  @State private collections: ZhihuCollection[] = [];
  // 收藏激活态：与 voteState 同套路，用独立布尔即时反映，避免依赖 collections 重载时机
  @State private favorited: boolean = false;
  @State private collectionLoading: boolean = false;
  @State private showCollectionSheet: boolean = false;
  @State private showCreateCollection: boolean = false;
  @State private newCollectionTitle: string = '';
  @State private newCollectionDesc: string = '';
  @State private newCollectionPublic: boolean = false;
  @State private creatingCollection: boolean = false;
  // 收藏夹列表渲染版本：切换收藏后数组引用不变但内部对象更新，靠它强制 ForEach 重建
  @State private collectionRenderVersion: number = 0;
  @State private collectionError: string = '';
  // 收藏夹调试日志（带时间戳，方便用户复制排查）
  @State private collectionDebugLog: string = '';
  private hdsTabsController: HdsTabsController = new HdsTabsController();
  // WebView 滚动位置（由 ZhihuRichWeb 桥上报），驱动顶栏/精简行隐显
  @State private summaryScrollTop: number = 0;
  // 摘要卡片底部位置（scrollTop 超过该值即完全滚出视野），由 WebView 内 JS 测量上报
  @State private summaryBottomPx: number = 999;
  // 是否已收到过有效的摘要底部测量；未收到前不显示精简行，避免阈值回退成 999 而常驻
  @State private summaryBoundsKnown: boolean = false;
  // 顶栏/底栏高度（由 onAreaChange 测量），用于随 WebView 滚动一起滑走
  @State private headerHeight: number = 0;
  @State private collapsedHeight: number = 0;
  // 顶/底栏偏移（移植安卓 topBarOffset/bottomBarOffset：0=显示, 负/正=隐藏），随 WebView 滚动方向跟手
  @State private topBarOffsetY: number = 0; // 0=显示；随 WebView 滚动跟手，负值滑出屏幕顶部
  @State private lastScrollTop: number = 0;
  @State private contentProgress: number = 0; // 顶栏 A→B 标题淡入进度 0..1（对齐安卓交叉淡入）
  private wasAtTop: boolean = true;           // atTop 翻转检测，用于回弹弹簧
  // 底部沉浸光感药丸栏：对齐安卓「跟手 + 滚动停止吸附最近端点」。
  // offsetY=0 完全显示；=bottomBarHideDistance 时完全滑出屏幕下沿（配合 opacity 淡出，杜绝从中间残留）。
  @State private bottomBarOffsetY: number = 0;
  private bottomBarHideDistance: number = 96;  // 隐藏位移：药丸高 + 底距 + 安全区
  private contentMaxScroll: number = 0;        // 已观测到的最大滚动位置（接近底部时强制显示）
  private bottomBarSnapTimer: number = -1;     // 滚动停止防抖计时器
  private bottomBarTweenTimer: number = -1;     // 底栏逐帧动画计时器
  // 沉浸阅读模式：隐藏顶部状态栏（保留底部小白条），系统侧滑返回退出沉浸
  @State private immersiveMode: boolean = false;
  private cachedWindow?: window.Window = undefined;            // 进入时缓存宿主窗口，退出同步还原
  // 左右滑动切换回答：水平偏移（vp）、拖动/切换状态、容器宽度、相邻回答 id
  @State private offsetX: number = 0;
  @State private dragging: boolean = false;
  @State private switching: boolean = false;
  @State private skipOpacity: number = 1;
  @State private containerWidth: number = 0;
  @State private hapticFired: boolean = false;
  @State private prevNeighborId?: string = undefined;
  @State private nextNeighborId?: string = undefined;
  @State private currentNeighborIdx: number = -1; // 当前回答在最热队列中的下标（-1=不在队列中）
  // 预览卡数据（必须 @State，否则 ArkUI @Builder 参数来自非响应式数组时不会重渲染）
  @State private prevPreviewItem?: HomeFeedItem = undefined;
  @State private nextPreviewItem?: HomeFeedItem = undefined;
  // 最热队列导航（对齐安卓 QuestionAnswerNavigator：/questions/{id}/feeds 默认最热序）。
  // 邻居 = 队列相邻项；detail.paginationInfo（相关推荐，无序）仅作队列加载失败的兜底。
  private neighborQuestionId: string = '';
  private neighborList: HomeFeedItem[] = [];
  private neighborNextUrl: string = '';
  private neighborLoading: boolean = false;

  // ===== 总结本文（SSE 流式） =====
  @State private showSummarySheet: boolean = false;
  @State private summaryText: string = '';
  @State private summaryLoading: boolean = false;
  @State private summaryError: string = '';
  @State private summaryStarted: boolean = false;
  private summaryCanceller: (() => void) | null = null;
  // ===== 导出文章 =====
  @State private showExportSheet: boolean = false;
  @State private exportCommentCount: number = 0;        // 0=关闭评论；1~10=包含的评论条数（对所有格式生效）
  @State private includeAppAttribution: boolean = true; // 导出底部开源说明开关（默认开，可关）
  // ===== TTS 朗读（鸿蒙原生 CoreSpeechKit） =====
  private ttsController: TtsController = new TtsController();
  @State private ttsSpeaking: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as ArticlePageParams;
    this.target = parseZhihuContentTarget(params.target);
    this.fallbackTitle = typeof params.fallbackTitle === 'string' ? params.fallbackTitle : '';
    this.fallbackUrl = typeof params.fallbackUrl === 'string' ? params.fallbackUrl : '';
    this.anchorCommentId = typeof params.anchorCommentId === 'string' ? params.anchorCommentId : '';
    const rootTargetValue = this.target !== undefined ? rootContentTarget(this.target) : undefined;
    this.pageTitle = rootTargetValue !== undefined ? contentTargetDisplayTitle(rootTargetValue) : '内容详情';
    this.loadArticle();
    // 确保知乎贴纸数据就绪，用于表情选择器渲染原版贴纸图（首次异步下载完成后刷新选择器数据源）
    ZhihuEmojiService.initialize(this.context())
      .then(() => { this.emojiItems = ZhihuEmojiService.getEmojiPickerItems(); })
      .catch(() => {});
  }

  // 离开页面（系统侧滑返回等）时若处于沉浸，必须还原窗口，避免影响其他页面
  onPageHide(): void {
    if (this.immersiveMode) {
      this.exitImmersive();
    }
  }

  // @Entry + router 体系下拦截返回（含侧滑手势）的正确钩子：
  // 沉浸态返回 true 消费事件（仅退出沉浸，不离开页面）；非沉浸态返回 false 正常返回上一页
  onBackPress(): boolean {
    if (this.immersiveMode) {
      this.exitImmersive();
      return true;
    }
    return false;
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


  private async loadArticle(): Promise<void> {
    const currentTarget = this.target;
    if (currentTarget === undefined) {
      this.articleLoading = false;
      this.articleError = '缺少内容目标';
      return;
    }
    const rootTargetValue = rootContentTarget(currentTarget);
    this.articleLoading = true;
    this.articleError = '';
    try {
      const detail = await ArticleDetailService.loadDetail(this.context(), rootTargetValue);
      this.detail = detail;
      // 通知评论定位：详情就绪后直接展开评论面板，定位到指定评论
      if (this.anchorCommentId.length > 0 && !this.anchorConsumed) {
        this.openComments();
      }
      this.refreshNeighbors(detail);
      this.pageTitle = detail.title;
      BrowsingHistoryRepository.recordContent(this.context(), detail.target, detail.title, detail.browserUrl, detail.excerpt);
      // 上报云端历史（异步，不阻塞）
      CloudHistoryService.reportViaTarget(this.context(), detail.target);
      // 拉取当前内容已加入的收藏夹（驱动底部「收藏」按钮状态）
      // pin 不支持收藏，跳过
      if (detail.target.kind !== 'pin') {
        this.loadCollectionsForContent();
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.articleError = `详情加载失败：${message}`;
    } finally {
      this.articleLoading = false;
    }
  }

  // ===== 左右滑动切换回答（对齐安卓 AnswerHorizontalOverscroll + QuestionAnswerNavigator） =====

  private applyPaginationFromDetail(detail: ZhihuContentDetail): void {
    const info = detail.paginationInfo;
    this.prevNeighborId = info !== undefined && info.prevAnswerIds.length > 0 ? `${info.prevAnswerIds[0]}` : undefined;
    this.nextNeighborId = info !== undefined && info.nextAnswerIds.length > 0 ? `${info.nextAnswerIds[0]}` : undefined;
  }

  // 详情加载完成后刷新左右邻居：
  // 回答 → 走问题最热队列（安卓 QuestionAnswerNavigator 行为）；其他内容 → paginationInfo
  private refreshNeighbors(detail: ZhihuContentDetail): void {
    if (detail.target.kind === 'answer' && detail.questionId.length > 0) {
      if (this.neighborQuestionId !== detail.questionId || this.neighborList.length === 0) {
        // 队列未就绪前先清空邻居，避免误滑到 paginationInfo 的随机推荐
        this.prevNeighborId = undefined;
        this.nextNeighborId = undefined;
      }
      this.setupNeighborQueue(detail);
      return;
    }
    this.applyPaginationFromDetail(detail);
  }

  private neighborAnswerIdAt(index: number): string | undefined {
    if (index < 0 || index >= this.neighborList.length) {
      return undefined;
    }
    const native = this.neighborList[index].nativeTarget;
    return native !== undefined && native.kind === 'answer' ? native.id : undefined;
  }

  private findNeighborIndex(answerId: string): number {
    return this.neighborList.findIndex((item: HomeFeedItem) => {
      const native = item.nativeTarget;
      return native !== undefined && native.kind === 'answer' && native.id === answerId;
    });
  }

  // 由邻居回答 id 取最热队列里的真实条目，用于左右滑动时的内容预览卡
  // 优先用 currentNeighborIdx 直接索引（消除 findNeighborIndex id 反查漂移），
  // 冷回答（currentNeighborIdx < 0）兜底走 id 搜索
  private neighborItem(id?: string): HomeFeedItem | undefined {
    if (id === undefined) {
      return undefined;
    }
    // 当前在热队列中 + prev/next id 匹配 → 直接用 currentNeighborIdx 索引
    if (this.currentNeighborIdx >= 0) {
      if (id === this.prevNeighborId && this.currentNeighborIdx > 0) {
        return this.neighborList[this.currentNeighborIdx - 1];
      }
      if (id === this.nextNeighborId && this.currentNeighborIdx + 1 < this.neighborList.length) {
        return this.neighborList[this.currentNeighborIdx + 1];
      }
    }
    // 冷回答（不在队列中）或未知 id 时用 id 反查
    const idx = this.findNeighborIndex(id);
    return idx >= 0 ? this.neighborList[idx] : undefined;
  }

  // 加载（或复用）当前问题的最热回答队列，并根据当前回答定位左右邻居
  private async setupNeighborQueue(detail: ZhihuContentDetail): Promise<void> {
    const answerId = detail.target.id;
    if (this.neighborQuestionId === detail.questionId && this.neighborList.length > 0) {
      this.updateNeighborsFromQueue(answerId);
      return;
    }
    if (this.neighborLoading) {
      return;
    }
    this.neighborLoading = true;
    let loaded = false;
    try {
      const page = await QuestionFeedService.loadFirstPage(
        this.context(), detail.questionId, detail.questionTitle, 'default');
      this.neighborQuestionId = detail.questionId;
      this.neighborList = page.items.filter((item: HomeFeedItem) => {
        const native = item.nativeTarget;
        return item.type === 'answer' && native !== undefined && native.kind === 'answer';
      });
      this.neighborNextUrl = page.paging.isEnd ? '' : page.paging.nextUrl;
      loaded = true;
    } catch (e) {
      // 最热队列加载失败：回退 paginationInfo，至少保证能滑
      this.applyPaginationFromDetail(detail);
    } finally {
      this.neighborLoading = false;
    }
    if (loaded) {
      this.updateNeighborsFromQueue(answerId);
    }
  }

  private updateNeighborsFromQueue(answerId: string): void {
    const idx = this.findNeighborIndex(answerId);
    if (idx >= 0) {
      this.currentNeighborIdx = idx;
      this.deriveNeighborsFromIndex();
      // 接近队尾时预取下一页，保证连续左滑不断档
      if (this.nextNeighborId === undefined || idx + 2 >= this.neighborList.length) {
        this.loadMoreNeighbors(answerId);
      }
      return;
    }
    // 当前回答不在最热队列（如从热榜/搜索点进的冷门回答）：无上一个，下一个 = 最热第一条
    this.currentNeighborIdx = -1;
    this.prevNeighborId = undefined;
    this.prevPreviewItem = undefined;
    const firstId = this.neighborAnswerIdAt(0);
    this.nextNeighborId = firstId === answerId ? this.neighborAnswerIdAt(1) : firstId;
    // 冷回答右预览 = 最热第一条（或第二条，若冷回答恰为第一条）
    const nextIdx = firstId === answerId ? 1 : 0;
    this.nextPreviewItem = nextIdx < this.neighborList.length ? this.neighborList[nextIdx] : undefined;
  }

  // 由 currentNeighborIdx 直接推导 prev/next 邻居 + 预览卡数据（不再依赖重载后用 id 反查，消除冻结根因）
  private deriveNeighborsFromIndex(): void {
    if (this.currentNeighborIdx < 0) {
      this.prevPreviewItem = undefined;
      this.nextPreviewItem = undefined;
      return;
    }
    this.prevNeighborId = this.neighborAnswerIdAt(this.currentNeighborIdx - 1);
    this.nextNeighborId = this.neighborAnswerIdAt(this.currentNeighborIdx + 1);
    // 同步更新预览卡 @State 数据（ArkUI 才会重渲染预览）
    this.prevPreviewItem = this.currentNeighborIdx > 0
      ? this.neighborList[this.currentNeighborIdx - 1] : undefined;
    this.nextPreviewItem = this.currentNeighborIdx + 1 < this.neighborList.length
      ? this.neighborList[this.currentNeighborIdx + 1] : undefined;
  }

  private async loadMoreNeighbors(answerId: string): Promise<void> {
    if (this.neighborLoading || this.neighborNextUrl.length === 0) {
      return;
    }
    this.neighborLoading = true;
    let loaded = false;
    try {
      const page = await QuestionFeedService.loadNextPage(
        this.context(), this.neighborQuestionId, this.pageTitle, this.neighborNextUrl);
      const knownIds = new Set<string>();
      this.neighborList.forEach((item: HomeFeedItem) => {
        const native = item.nativeTarget;
        if (native !== undefined) {
          knownIds.add(native.id);
        }
      });
      page.items.forEach((item: HomeFeedItem) => {
        const native = item.nativeTarget;
        if (item.type === 'answer' && native !== undefined && native.kind === 'answer' && !knownIds.has(native.id)) {
          knownIds.add(native.id);
          this.neighborList.push(item);
        }
      });
      this.neighborNextUrl = page.paging.isEnd ? '' : page.paging.nextUrl;
      loaded = true;
    } catch (e) {
      // 续页失败：保持现有队列，滑到尾部自然停下
    } finally {
      this.neighborLoading = false;
    }
    // 续页追加后仅从 currentNeighborIdx 重新推导邻居，
    // 不再用旧 answerId 反查（避免覆盖已被后续滑动手势更新的索引）
    if (loaded && this.currentNeighborIdx >= 0) {
      this.deriveNeighborsFromIndex();
      // 预取后仍接近队尾 → 继续预取下一页
      if (this.nextNeighborId === undefined || this.currentNeighborIdx + 2 >= this.neighborList.length) {
        if (this.neighborNextUrl.length > 0) {
          const currentId = this.currentNeighborIdx < this.neighborList.length
            ? (this.neighborList[this.currentNeighborIdx].nativeTarget?.id ?? '') : '';
          if (currentId.length > 0) {
            this.loadMoreNeighbors(currentId);
          }
        }
      }
    }
  }

  // tanh 阻尼：跟手但不越界，避免拖到屏幕外
  private dampedOffset(rawDelta: number): number {
    const maxPx = ANSWER_SWITCH_MAX_OVERSCROLL_VP;
    const damping = ANSWER_SWITCH_DAMPING;
    const sign = rawDelta >= 0 ? 1 : -1;
    return sign * Math.abs(maxPx * Math.tanh(Math.abs(rawDelta) / (maxPx * damping)));
  }

  // 拖动时主内容模糊半径：仅 finger down 时生效，松手回弹动画期间不模糊（避免 GPU 每帧重算）
  private get currentBlurRadius(): number {
    if (!this.dragging) {
      return 0;
    }
    const absOffset = Math.abs(this.offsetX);
    if (absOffset === 0) {
      return 0;
    }
    const clearAt = this.containerWidth * ANSWER_SWITCH_BLUR_CLEAR_RATIO;
    const progress = Math.min(1, absOffset / (clearAt || 1));
    return (1 - progress) * ANSWER_SWITCH_BLUR_MAX_VP;
  }

  private triggerHaptic(): void {
    try {
      vibrator.startVibration(
        { type: 'preset', effectId: 'haptic.medium' },
        { id: 0, usage: 'touch' }
      );
    } catch (e) {
      console.warn('[Article] haptic failed: ' + JSON.stringify(e));
    }
  }

  private animateOffsetTo(target: number): void {
    animateTo({ curve: curves.springMotion(), duration: 320 }, () => {
      this.offsetX = target;
    });
  }

  // 移植安卓 ArticleScreen 的顶/底栏跟手显隐（顶栏三态：A 紧凑返回+⋮ / B 标题+作者 / C 隐藏）：
  // atTop 时顶栏可见（紧凑态，返回+⋮），正文内摘要卡片承接标题/作者；下滑跟手隐藏；上滑跟手显示
  private updateBarsOnScroll(topPx: number): void {
    const atTop = topPx <= 1;
    const delta = topPx - this.lastScrollTop;
    const scrollingDown = delta > 0;
    // 顶栏浮层整条（含状态栏）随滚动滑出；隐藏终点 = 整条高度（headerHeight 恒 0，实为 collapsedHeight）；未测得时给兜底，避免 collapsedHeight 为 0 时整段跳过 → 顶栏不收
    const measured = this.headerHeight + this.collapsedHeight;
    const topTotal = measured > 0 ? measured : (this.topSafeAreaVp + 56);
    if (topTotal > 0) {
      if (atTop) {
        // atTop：顶栏可见（紧凑态 A），正文摘要卡片负责标题/作者；从隐藏回顶用弹簧回弹（对齐安卓）
        if (!this.wasAtTop) {
          animateTo({ curve: curves.springMotion(), duration: 300 }, () => { this.topBarOffsetY = 0; });
        } else {
          this.topBarOffsetY = 0;
        }
      } else if (scrollingDown) {
        // 下滑：整条隐藏（跟手）
        this.topBarOffsetY = Math.max(-topTotal, this.topBarOffsetY - delta);
      } else {
        // 上滑：整条显示（跟手）
        this.topBarOffsetY = Math.min(0, Math.max(-topTotal, this.topBarOffsetY - delta));
      }
    }
    this.lastScrollTop = topPx;
    this.wasAtTop = atTop;

    // 顶栏 A→B 标题连续淡入进度：摘要卡片底部滚过顶栏下方约 80px 区间完成淡入
    const fade = 80;
    const p = this.summaryBoundsKnown
      ? Math.min(1, Math.max(0, (this.summaryScrollTop - (this.summaryBottomPx - fade)) / fade))
      : 0;
    if (p !== this.contentProgress) {
      this.contentProgress = p;
    }

    // 「跳转下一个回答」FAB 显隐（对齐安卓 showSkipButton：回答页、开关开、非沉浸模式；
    // 开启自动隐藏时，仅上划(scrollingDown)时淡出，下划/置顶时淡入；其余情况常驻）
    const isAnswer = this.detail?.target.kind === 'answer';
    const baseVisible = isAnswer && this.buttonSkipAnswer && !this.immersiveMode;
    if (baseVisible) {
      const target = (!this.autoHideSkipAnswerButton || !scrollingDown || atTop) ? 1 : 0;
      if (target !== this.skipOpacity) {
        this.skipOpacity = target;
      }
    }

    // ===== 底部沉浸光感药丸栏：对齐主页「跟手 + 滚动停止吸附最近端点」=====
    // 纯 delta 跟手（无 atTop/nearBottom 强制显示分支，避免下滑途中误显）
    const barH = this.bottomBarHideDistance;
    if (Math.abs(delta) >= 1) {
      this.bottomBarOffsetY = Math.min(barH, Math.max(0, this.bottomBarOffsetY + delta));
      this.hdsTabsController.setTabBarTranslate({ x: 0, y: this.bottomBarOffsetY });
      this.hdsTabsController.setTabBarOpacity(Math.max(0, 1 - this.bottomBarOffsetY / barH));
      this.scheduleBottomBarSnap();
    }
  }

  /** 滚动停止后吸附底栏到最近端点（0 显示 / bottomBarHideDistance 隐藏） */
  private scheduleBottomBarSnap(): void {
    if (this.bottomBarSnapTimer >= 0) {
      clearTimeout(this.bottomBarSnapTimer);
    }
    this.bottomBarSnapTimer = setTimeout(() => {
      const barH = this.bottomBarHideDistance;
      const target = this.bottomBarOffsetY > barH / 2 ? barH : 0;
      this.animateBottomBarTo(target);
      this.bottomBarSnapTimer = -1;
    }, 120);
  }

  /** 用逐帧插值驱动 HdsTabs 浮动底栏的位移/透明度（对齐主页 animateHomeBarTo） */
  private animateBottomBarTo(target: number): void {
    if (this.bottomBarTweenTimer >= 0) {
      clearInterval(this.bottomBarTweenTimer);
      this.bottomBarTweenTimer = -1;
    }
    const barH = this.bottomBarHideDistance;
    const start = this.bottomBarOffsetY;
    const dist = target - start;
    if (Math.abs(dist) < 1) {
      this.hdsTabsController.setTabBarTranslate({ x: 0, y: target });
      this.hdsTabsController.setTabBarOpacity(target >= barH ? 0 : 1);
      this.bottomBarOffsetY = target;
      return;
    }
    const duration = 160;
    const startTime = Date.now();
    this.bottomBarTweenTimer = setInterval(() => {
      const t = Math.min(1, (Date.now() - startTime) / duration);
      const eased = 1 - Math.pow(1 - t, 3); // easeOutCubic
      this.bottomBarOffsetY = start + dist * eased;
      this.hdsTabsController.setTabBarTranslate({ x: 0, y: this.bottomBarOffsetY });
      this.hdsTabsController.setTabBarOpacity(Math.max(0, 1 - this.bottomBarOffsetY / barH));
      if (t >= 1) {
        clearInterval(this.bottomBarTweenTimer);
        this.bottomBarTweenTimer = -1;
      }
    }, 16);
  }

  /** 立即复位底栏到完全显示（切换回答 / 回到顶部时调用） */
  private resetBottomBar(): void {
    if (this.bottomBarTweenTimer >= 0) {
      clearInterval(this.bottomBarTweenTimer);
      this.bottomBarTweenTimer = -1;
    }
    if (this.bottomBarSnapTimer >= 0) {
      clearTimeout(this.bottomBarSnapTimer);
      this.bottomBarSnapTimer = -1;
    }
    this.bottomBarOffsetY = 0;
    this.hdsTabsController.setTabBarTranslate({ x: 0, y: 0 });
    this.hdsTabsController.setTabBarOpacity(1);
  }

  private clearBottomBarSnap(): void {
    if (this.bottomBarSnapTimer >= 0) {
      clearTimeout(this.bottomBarSnapTimer);
      this.bottomBarSnapTimer = -1;
    }
  }

  private async switchToNeighbor(direction: 'prev' | 'next'): Promise<void> {
    if (this.currentNeighborIdx >= 0) {
      // 在热队列内：直接用当前下标 ± 1 取目标，同步更新邻居，彻底消除"冻结点"
      const delta = direction === 'prev' ? -1 : 1;
      const targetIdx = this.currentNeighborIdx + delta;
      if (targetIdx < 0 || targetIdx >= this.neighborList.length) {
        this.animateOffsetTo(0);
        return;
      }
      const targetItem = this.neighborList[targetIdx];
      const nextTarget = targetItem.nativeTarget;
      if (nextTarget === undefined || nextTarget.kind !== 'answer') {
        this.animateOffsetTo(0);
        return;
      }
      // 立即更新当前下标和邻居（同步，不等 loadArticle 完成）
      this.currentNeighborIdx = targetIdx;
      this.deriveNeighborsFromIndex();
      // 立即隐藏预览（否则新邻居值会趁 offsetX 尚为动画值时闪现一帧）
      this.offsetX = 0;
      // 接近队尾时预取下一页
      if (this.nextNeighborId === undefined || targetIdx + 2 >= this.neighborList.length) {
        this.loadMoreNeighbors(nextTarget.id);
      }
      this.switching = true;
      try {
        this.target = nextTarget;
        this.topBarOffsetY = 0;
        this.summaryScrollTop = 0;
        this.summaryBottomPx = 999;
        this.summaryBoundsKnown = false;
        this.lastScrollTop = 0;
        this.contentProgress = 0;
        this.wasAtTop = true;
        this.resetBottomBar();
        this.contentMaxScroll = 0;
        this.clearBottomBarSnap();
        // 切换回答时清空评论数据，防止显示旧回答的评论
        this.rootComments = [];
        this.rootCommentNextUrl = '';
        this.rootCommentEnd = false;
        this.rootCommentError = '';
        this.rootCommentTargetId = '';
        await this.loadArticle();
        if (this.showRootCommentSheet) {
          this.ensureRootComments(true);
        }
      } catch (e) {
        this.showToast('切换回答失败');
        this.animateOffsetTo(0);
      } finally {
        this.switching = false;
        this.animateOffsetTo(0);
      }
      return;
    }
    // 冷回答（不在队列中）兜底：走原有的 prevNeighborId/nextNeighborId
    const id = direction === 'prev' ? this.prevNeighborId : this.nextNeighborId;
    if (id === undefined) {
      this.animateOffsetTo(0);
      return;
    }
    let nextTarget: ZhihuContentTarget = { kind: 'answer', id } as ZhihuContentTarget;
    const queueIdx = this.findNeighborIndex(id);
    if (queueIdx >= 0) {
      const native = this.neighborList[queueIdx].nativeTarget;
      if (native !== undefined) {
        nextTarget = native;
      }
    }
    this.switching = true;
    try {
      this.target = nextTarget;
        this.topBarOffsetY = 0;
        this.summaryScrollTop = 0;
        this.summaryBottomPx = 999;
        this.summaryBoundsKnown = false;
        this.lastScrollTop = 0;
        this.contentProgress = 0;
        this.wasAtTop = true;
        this.resetBottomBar();
        this.contentMaxScroll = 0;
        this.clearBottomBarSnap();
        this.rootComments = [];
        this.rootCommentNextUrl = '';
        this.rootCommentEnd = false;
        this.rootCommentError = '';
        this.rootCommentTargetId = '';
        await this.loadArticle();
        if (this.showRootCommentSheet) {
          this.ensureRootComments(true);
        }
    } catch (e) {
      this.showToast('切换回答失败');
      this.animateOffsetTo(0);
    } finally {
      this.switching = false;
      this.animateOffsetTo(0);
    }
  }

  // 由 Web 内 JS 桥上报的水平滑动事件驱动（PanGesture 被 Web 吞掉，改走桥）
  private handleHorizontalSwipe(state: string, dx: number): void {
    if (this.switching) {
      return;
    }
    if (state === 'start') {
      this.dragging = true;
      this.hapticFired = false;
      return;
    }
    if (state === 'move') {
      let next = this.dampedOffset(dx);
      if (next > 0 && this.prevNeighborId === undefined) {
        next = 0;
      }
      if (next < 0 && this.nextNeighborId === undefined) {
        next = 0;
      }
      this.offsetX = next;
      const threshold = ANSWER_SWITCH_TRIGGER_VP / ANSWER_SWITCH_SENSITIVITY;
      if (!this.hapticFired && Math.abs(next) >= threshold) {
        this.triggerHaptic();
        this.hapticFired = true;
      }
      return;
    }
    // state === 'end'
    this.dragging = false;
    const threshold = ANSWER_SWITCH_TRIGGER_VP / ANSWER_SWITCH_SENSITIVITY;
    const reached = Math.abs(this.offsetX) >= threshold;
    if (reached) {
      if (this.offsetX > 0 && this.prevNeighborId !== undefined) {
        this.switchToNeighbor('prev');
        return;
      }
      if (this.offsetX < 0 && this.nextNeighborId !== undefined) {
        this.switchToNeighbor('next');
        return;
      }
    }
    this.animateOffsetTo(0);
  }

  private async toggleVote(nextState: ZhihuVoteState): Promise<void> {
    const detail = this.detail;
    if (detail === undefined) {
      return;
    }
    try {
      const result = await ArticleDetailService.toggleVote(this.context(), detail, nextState);
      this.detail = copyDetail(detail, result.voteCount, result.voteState);
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.showToast(`投票失败：${message}`);
    }
  }

  // ===== 收藏夹（对齐安卓 ArticleScreen 收藏交互） =====

  private get isFavorited(): boolean {
    return this.collections.some((collection: ZhihuCollection) => collection.isFavorited);
  }

  private async loadCollectionsForContent(): Promise<void> {
    const detail = this.detail;
    if (detail === undefined) {
      const msg = '[CollectionDebug] loadCollections 跳过：detail 为空';
      console.warn(msg);
      this.collectionDebugLog += '\n' + msg;
      return;
    }
    this.collectionLoading = true;
    this.collectionError = '';
    const target = detail.target;
    const ts = new Date().toLocaleTimeString('zh-CN', { hour12: false });
    let log = `[${ts}] ===== 开始加载收藏夹 =====`;
    log += `\n目标类型(kind): "${target.kind}"`;
    log += `\n目标ID(id): "${target.id}"`;
    try {
      this.collectionDebugLog += '\n' + log;
      console.info(log);
      // 对齐安卓 ArticleViewModel.loadCollections：
      // api.zhihu.com/collections/contents/{type}/{id}?limit=50
      const url = `https://api.zhihu.com/collections/contents/${target.kind}/${target.id}?limit=50`;
      log = `[CollectionDebug] 请求URL: ${url}`;
      console.info(log);
      this.collectionDebugLog += '\n' + log;
      this.collections = await CollectionService.loadCollectionsForContent(this.context(), target);
      this.favorited = this.isFavorited;
      log = `[CollectionDebug] 加载成功，共 ${this.collections.length} 个收藏夹`;
      this.collections.forEach((c, i) => {
        log += `\n  [${i}] id=${c.id} title="${c.title}" isFavorited=${c.isFavorited} itemCount=${c.itemCount}`;
      });
      // 追加原始响应 body 用于诊断
      if (CollectionService.lastRawResponse.length > 0) {
        log += `\n[CollectionDebug] 原始API响应:\n${CollectionService.lastRawResponse}`;
      }
      console.info(log);
      this.collectionDebugLog += '\n' + log;
      this.collectionRenderVersion += 1;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      log = `[CollectionDebug] ❌ 加载失败：${message}`;
      console.error(log);
      this.collectionDebugLog += '\n' + log;
      this.collectionError = `收藏夹加载失败：${message}`;
      this.showToast(this.collectionError);
    } finally {
      this.collectionLoading = false;
    }
  }

  private openCollectionSheet(): void {
    // 想法（pin）暂不支持收藏
    if (this.detail?.target?.kind === 'pin') {
      this.showToast('想法暂不支持收藏');
      return;
    }
    const ts = new Date().toLocaleTimeString('zh-CN', { hour12: false });
    // 每次打开都记录状态，并强制重新加载
    let log = `[${ts}] ===== openCollectionSheet 被调用 =====`;
    log += `\ndetail 存在: ${this.detail !== undefined}`;
    if (this.detail !== undefined) {
      log += `\n  target.kind="${this.detail.target.kind}" target.id="${this.detail.target.id}"`;
    } else {
      log += `\n  ⚠️ detail 为空！loadCollections 将被跳过！`;
    }
    log += `\ncollections 当前数量: ${this.collections.length}`;
    log += `\ncollectionLoading: ${this.collectionLoading}`;
    // 尝试读取登录状态
    try {
      const session = ZhihuSessionRepository.load(this.context());
      const cookies = session.cookies;
      const cookieKeys = Object.keys(cookies);
      log += `\n登录cookie数量: ${cookieKeys.length}`;
      log += `\ncookie keys: [${cookieKeys.join(', ')}]`;
      log += `\nd_c0 存在: ${!!cookies.d_c0}`;
      log += `\n_xsrf 存在: ${!!cookies._xsrf}`;
      log += `\nz_c0 存在: ${!!cookies.z_c0}`;
    } catch (e) {
      log += `\n⚠️ 读取会话失败: ${(e instanceof Error ? e.message : String(e))}`;
    }
    console.info(log);
    this.collectionDebugLog += '\n' + log;
    // 每次打开都重新加载收藏夹列表
    this.loadCollectionsForContent();
    this.showCollectionSheet = true;
  }

  private async toggleCollectionFavorite(collection: ZhihuCollection): Promise<void> {
    const detail = this.detail;
    if (detail === undefined) {
      return;
    }
    const remove = collection.isFavorited;
    const ts = new Date().toLocaleTimeString('zh-CN', { hour12: false });
    let log = `[${ts}] ===== 切换收藏状态 =====`;
    log += `\n收藏夹ID: ${collection.id} 标题: "${collection.title}"`;
    log += `\n操作: ${remove ? '取消收藏' : '收藏'}`;
    log += `\n目标: kind=${detail.target.kind} id=${detail.target.id}`;
    try {
      console.info(log);
      this.collectionDebugLog += '\n' + log;
      await CollectionService.toggleFavorite(this.context(), detail.target, collection.id, remove);
      // 本地即时更新收藏夹列表的 isFavorited，驱动弹窗里 ★/☆ 立即切换；
      // 同时把底栏书签 favorited 置位（与点赞同套路，乐观更新，不依赖 contents 接口回读，
      // 避免知乎接口最终一致性延迟把 favorited 覆盖回 false）。
      this.collections = this.collections.map((c: ZhihuCollection) =>
        c.id === collection.id
          ? {
              id: c.id,
              title: c.title,
              description: c.description,
              isFavorited: !remove,
              isPublic: c.isPublic,
              itemCount: c.itemCount,
              likeCount: c.likeCount,
              commentCount: c.commentCount,
              viewCount: c.viewCount,
              updatedTime: c.updatedTime,
              isDefault: c.isDefault
            }
          : c
      );
      this.favorited = !remove;
      this.collectionRenderVersion += 1;
      log = `[CollectionDebug] ✅ 操作成功：${remove ? '已取消收藏' : '已收藏'}`;
      console.info(log);
      this.collectionDebugLog += '\n' + log;
      this.showToast(remove ? '取消收藏成功' : '收藏成功');
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      log = `[CollectionDebug] ❌ 操作失败：${message}`;
      console.error(log);
      this.collectionDebugLog += '\n' + log;
      this.showToast(`收藏操作失败：${message}`);
    }
  }

  private async submitNewCollection(): Promise<void> {
    const title = this.newCollectionTitle.trim();
    if (title.length === 0 || this.creatingCollection) {
      return;
    }
    this.creatingCollection = true;
    const ts = new Date().toLocaleTimeString('zh-CN', { hour12: false });
    let log = `[${ts}] ===== 创建新收藏夹 =====`;
    log += `\n标题: "${title}"`;
    log += `\n描述: "${this.newCollectionDesc.trim()}"`;
    log += `\n公开: ${this.newCollectionPublic}`;
    try {
      console.info(log);
      this.collectionDebugLog += '\n' + log;
      await CollectionService.createCollection(
        this.context(),
        title,
        this.newCollectionDesc.trim(),
        this.newCollectionPublic
      );
      log = `[CollectionDebug] ✅ 创建成功`;
      console.info(log);
      this.collectionDebugLog += '\n' + log;
      this.newCollectionTitle = '';
      this.newCollectionDesc = '';
      this.newCollectionPublic = false;
      this.showCreateCollection = false;
      this.showToast('收藏夹已创建');
      await this.loadCollectionsForContent();
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      log = `[CollectionDebug] ❌ 创建失败：${message}`;
      console.error(log);
      this.collectionDebugLog += '\n' + log;
      this.showToast(`创建失败：${message}`);
    } finally {
      this.creatingCollection = false;
    }
  }

  /** 复制收藏夹调试日志到剪贴板 */
  private copyCollectionDebugLog(): void {
    const log = this.collectionDebugLog.trim();
    if (log.length === 0) {
      this.showToast('暂无日志');
      return;
    }
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      const pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, log);
      systemPasteboard.setData(pasteData);
      this.showToast('日志已复制到剪贴板');
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : String(e);
      this.showToast('复制失败：' + errMsg);
    }
  }

  private openWebVersion(): void {
    const detail = this.detail;
    const url = detail?.browserUrl ?? this.fallbackUrl;
    const title = detail?.title ?? this.fallbackTitle;
    if (url.length === 0) {
      return;
    }
    router.pushUrl({
      url: 'pages/WebContent',
      params: { title, url }
    });
  }

  // ===== 右上角三点菜单功能 =====

  /** 在知乎 App 中打开 */
  private openInZhihuApp(): void {
    const url = this.detail?.browserUrl ?? this.fallbackUrl;
    if (url.length === 0) {
      return;
    }
    this.tryOpenExternal(url);
  }

  /** 在系统默认浏览器中打开 */
  private openInDefaultBrowser(): void {
    const url = this.detail?.browserUrl ?? this.fallbackUrl;
    if (url.length === 0) {
      return;
    }
    this.tryOpenExternal(url);
  }

  /** 复制链接到剪贴板 */
  private copyCurrentLink(): void {
    const url = this.detail?.browserUrl ?? this.fallbackUrl;
    if (url.length === 0) {
      return;
    }
    try {
      const pb = pasteboard.getSystemPasteboard();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pb.setData(pasteData);
      this.showToast('链接已复制');
    } catch (_) {
      this.showToast('复制失败');
    }
  }

  /** 系统分享（使用 systemShare.ShareController 拉起系统分享面板） */
  private systemShare(): void {
    const url = this.detail?.browserUrl ?? this.fallbackUrl;
    const title = this.detail?.title ?? this.fallbackTitle;
    if (url.length === 0) {
      return;
    }
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

  // ===== 沉浸阅读模式（隐藏顶部状态栏、保留底部导航栏小白条；侧滑返回退出沉浸） =====

  /** 取/缓存当前页面宿主窗口（失败返回 undefined，避免沉浸功能影响主流程） */
  private async ensureWindow(): Promise<window.Window | undefined> {
    if (this.cachedWindow !== undefined) {
      return this.cachedWindow;
    }
    try {
      this.cachedWindow = await window.getLastWindow(getContext(this) as common.UIAbilityContext);
    } catch (e) {
      console.error('[Immersive] ensureWindow 失败:', (e as Error)?.message ?? String(e));
      this.cachedWindow = undefined;
    }
    return this.cachedWindow;
  }

  /** 进入沉浸：隐藏状态栏（保留底部小白条），同时隐藏应用内顶/底栏 */
  private async enterImmersive(): Promise<void> {
    const win = await this.ensureWindow();
    if (win === undefined) {
      return;
    }
    try {
      win.setWindowLayoutFullScreen(true);
      // 仅保留底部导航栏（小白条），顶部状态栏彻底不显示；正文顶部留安全区避免贴边
      // 注意：当前基础 SDK 的 SystemBarType 为 'status' | 'navigation'（非 'statusBar'/'navigationBar'）
      win.setWindowSystemBarEnable(['navigation'] as Array<'status' | 'navigation'>);
      this.immersiveMode = true;
      this.showToast('已进入沉浸模式，侧滑返回退出');
    } catch (e) {
      console.error('[Immersive] 进入失败:', (e as Error)?.message ?? String(e));
      this.showToast('进入沉浸失败');
    }
  }

  /** 退出沉浸：按 App 基线还原窗口（EntryAbility 基线 = 全屏布局 + 系统栏透明，不是 false） */
  private exitImmersive(): void {
    this.immersiveMode = false;
    const win = this.cachedWindow;
    if (win === undefined) {
      return;
    }
    try {
      // 还原为 App 基线：状态栏+导航栏均启用、保持全屏布局、系统栏透明（与 EntryAbility 一致）
      // 注意：不能用 setWindowLayoutFullScreen(false)，否则窗口回退到系统默认布局，
      // 导致顶部下移、底部出现黑框（窗口基色露白）。
      win.setWindowSystemBarEnable(['status', 'navigation'] as Array<'status' | 'navigation'>);
      win.setWindowLayoutFullScreen(true);
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000'
      });
    } catch (e) {
      console.error('[Immersive] 退出失败:', (e as Error)?.message ?? String(e));
    }
  }

  // ===== 总结本文（SSE 流式，对齐安卓 requestAiSummary） =====
  private startSummary(): void {
    if (this.detail === undefined) {
      return;
    }
    this.summaryText = '';
    this.summaryError = '';
    this.summaryLoading = true;
    this.summaryStarted = true;
    this.showSummarySheet = true;
    const target = this.detail.target;
    const options: SummaryOptions = {
      contentId: target.id,
      contentType: target.kind === 'article' ? 'article' : 'answer',
      title: this.detail.title
    };
    this.summaryCanceller = startSummaryStream(this.context(), options, {
      onStart: () => {
        this.summaryLoading = true;
      },
      onDelta: (text: string) => {
        this.summaryText = text;
        this.summaryLoading = false;
      },
      onError: (message: string) => {
        this.summaryError = message;
        this.summaryLoading = false;
      },
      onDone: () => {
        this.summaryLoading = false;
      }
    });
  }

  private cancelSummaryStream(): void {
    if (this.summaryCanceller !== null) {
      this.summaryCanceller();
      this.summaryCanceller = null;
    }
    this.summaryLoading = false;
  }

  private stopSummary(): void {
    this.cancelSummaryStream();
    this.showSummarySheet = false;
  }

  // ===== TTS 朗读（鸿蒙原生 CoreSpeechKit，对齐安卓 articleSpeechText / toggleSpeech） =====
  private toggleTts(): void {
    if (this.detail === undefined) {
      return;
    }
    if (this.ttsSpeaking) {
      this.ttsController.stop();
      return;
    }
    this.ttsController.start(this.context(), this.detail.title, this.detail.htmlContent, {
      onStateChange: (speaking: boolean) => {
        this.ttsSpeaking = speaking;
      },
      onError: (message: string) => {
        this.showToast(message);
        this.ttsSpeaking = false;
      }
    });
  }

  // ===== 导出文章（HTML / 带评论 / Markdown / 图片 / PDF，对齐安卓 ExportDialogComponent） =====
  private buildExportMeta(): ArticleExportMeta {
    const d = this.detail!;
    return {
      title: d.title,
      authorName: d.author?.name ?? '匿名用户',
      authorBio: d.author?.headline ?? '',
      authorAvatarSrc: d.author?.avatarUrl ?? '',
      voteUpCount: d.voteCount,
      commentCount: d.commentCount,
      contentHtml: d.htmlContent,
      createdEpochSeconds: d.createdTime,
      updatedEpochSeconds: d.updatedTime,
      contentId: d.target.id,
      contentType: d.target.kind === 'article' ? 'article' : 'answer'
    };
  }

  private async doExport(type: 'html' | 'markdown'): Promise<void> {
    if (this.detail === undefined) {
      return;
    }
    this.showExportSheet = false;
    this.showToast('正在准备导出…');
    try {
      const meta = this.buildExportMeta();
      const wantComments = this.exportCommentCount > 0;
      let commentsHtml = '';
      if (wantComments) {
        let comments = this.rootComments;
        if (comments.length === 0) {
          try {
            const page = await CommentService.loadRootComments(
              this.context(),
              this.detail!.target,
              this.rootCommentSortOrder
            );
            comments = page.items;
          } catch (_e) {
            comments = [];
          }
        }
        const limited = comments.slice(0, this.exportCommentCount);
        commentsHtml = buildCommentsHtml(limited, limited.length);
      }
      if (type === 'markdown') {
        const md = buildExportMarkdown(meta, {
          commentsHtml: wantComments ? commentsHtml : '',
          includeAppAttribution: this.includeAppAttribution
        });
        await copyText(md);
        this.showToast('Markdown 已复制到剪贴板');
        return;
      }
      const html = await buildExportHtml(meta, {
        includeComments: wantComments,
        commentsHtml,
        includeImages: true,
        includeAppAttribution: this.includeAppAttribution
      });
      const fileName = buildExportFileName(meta, 'html');
      const ok = await saveTextFile(this.context(), html, fileName);
      this.showToast(ok ? `已导出：${fileName}` : '导出失败，请重试');
    } catch (e) {
      this.showToast('导出失败：' + (e instanceof Error ? e.message : '未知错误'));
    }
  }

  private openCommentImage(url: string): void {
    commentReopenPending = true;
    this.openImage(url);
  }

  private openCommentLink(url: string, text: string): void {
    commentReopenPending = true;
    this.openBodyLink(url, text);
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

  private openVideo(videoId: string): void {
    if (videoId.trim().length === 0) {
      return;
    }
    const target = this.detail?.target;
    const contentType = target?.kind === 'article' ? 'article' : 'answer';
    const contentId = target?.id ?? videoId;
    const title = this.detail?.title ?? '视频';
    router.pushUrl({
      url: 'pages/VideoPlayerPage',
      params: {
        videoId,
        contentId,
        contentType,
        title
      }
    });
  }

  /** 保存图片到系统相册（使用 photoAccessHelper createAsset + write） */
  private async saveImageToGallery(url: string): Promise<void> {
    if (url.trim().length === 0) {
      return;
    }
    this.showToast('正在下载图片…');
    try {
      // 先请求相册写入权限
      const atManager = abilityAccessCtrl.createAtManager();
      const permResult = await atManager.requestPermissionsFromUser(
        getContext(this) as common.UIAbilityContext,
        ['ohos.permission.WRITE_IMAGEVIDEO' as Permissions]
      );
      if (permResult.authResults[0] !== 0) {
        console.error('[ImageSave] 相册权限被拒 authResult=', permResult.authResults[0]);
        this.showToast('需要相册写入权限');
        return;
      }
      console.info('[ImageSave] 相册权限已授权');

      const httpReq = http.createHttp();
      const resp = await httpReq.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      httpReq.destroy();

      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        console.error('[ImageSave] 下载失败 responseCode=', resp.responseCode);
        this.showToast('图片下载失败');
        return;
      }

      const imageData = resp.result as ArrayBuffer;
      if (imageData.byteLength === 0) {
        console.error('[ImageSave] 图片数据为空');
        this.showToast('图片为空');
        return;
      }

      const ext = url.includes('.png') ? 'png' : 'jpg';
      const helper = photoAccessHelper.getPhotoAccessHelper(getContext(this));
      const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, ext);
      console.info('[ImageSave] createAsset URI:', uri);
      const file = await fileIo.open(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      await fileIo.write(file.fd, imageData);
      fileIo.closeSync(file);
      console.info('[ImageSave] 图片写入成功');
      this.showToast('已保存到图库');
    } catch (e) {
      const errMsg = (e as Error)?.message ?? String(e);
      console.error('[ImageSave] 保存异常:', errMsg, JSON.stringify(e));
      this.showToast('保存失败：' + errMsg);
    }
  }

  /** 长按图片弹出菜单：查看 / 保存 / 分享 */
  private showImageMenu(url: string): void {
    promptAction.showDialog({
      title: '图片操作',
      buttons: [
        { text: '查看图片', color: '#000000' },
        { text: '保存图片', color: '#000000' },
        { text: '分享图片', color: '#000000' }
      ]
    }).then((result: DialogResult) => {
      if (result.index === 0) {
        this.openImage(url);
      } else if (result.index === 1) {
        this.saveImageToGallery(url);
      } else if (result.index === 2) {
        this.shareImageUrl(url);
      }
    }).catch(() => {
    });
  }

  /** 分享图片（下载 → temp → file:// URI → systemShare.ShareController） */
  private async shareImageUrl(url: string): Promise<void> {
    if (url.trim().length === 0) {
      return;
    }
    this.showToast('正在准备分享…');
    try {
      const httpReq = http.createHttp();
      const resp = await httpReq.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      httpReq.destroy();
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        this.showToast('图片下载失败');
        return;
      }
      const imageData = resp.result as ArrayBuffer;
      const ext = url.includes('.png') ? 'png' : 'jpg';
      const tmpPath = `${getContext(this).cacheDir}/zhihu_share_${Date.now()}.${ext}`;
      const file = fileIo.openSync(tmpPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, imageData);
      fileIo.closeSync(file.fd);

      const uri = fileUri.getUriFromPath(tmpPath);
      const utdType = ext === 'png' ? utd.UniformDataType.PNG : utd.UniformDataType.JPEG;
      const data = new systemShare.SharedData({
        utd: utdType,
        uri: uri,
        title: '分享图片'
      });
      const ctx = getContext(this) as common.UIAbilityContext;
      const controller = new systemShare.ShareController(data);
      controller.show(ctx, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      }).then(() => {
        console.info('[ImageShare] 分享面板已打开');
      }).catch((err: Error) => {
        console.error('[ImageShare] 分享失败:', (err as Object)?.toString() ?? String(err));
      });
    } catch (e) {
      console.error('[ImageShare] 分享异常:', (e as Error)?.message ?? String(e));
      this.showToast('分享失败');
    }
  }

  /** 复制公式 LaTeX 源码到剪贴板 */
  private copyMathLatex(latex: string): void {
    if (latex.trim().length === 0) {
      return;
    }
    try {
      const pb = pasteboard.getSystemPasteboard();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, latex);
      pb.setData(pasteData);
      this.showToast('公式源码已复制');
    } catch (_) {
      this.showToast('复制失败');
    }
  }

  private openQuestion(): void {
    const detail = this.detail;
    if (detail === undefined) {
      return;
    }
    const questionId = detail.questionId ?? '';
    if (questionId.length === 0) {
      this.showToast('该内容没有关联的问题');
      return;
    }
    router.pushUrl({
      url: 'pages/Question',
      params: {
        questionId: questionId,
        title: detail.questionTitle
      }
    });
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

  private openBodyLink(url: string, text: string): void {
    const normalized = url.trim();
    if (normalized.length === 0) {
      return;
    }

    // 拦截 WebView 内摘要标题的 zhihu://openQuestion 链接
    if (normalized.startsWith('zhihu://openQuestion?id=')) {
      const qId = decodeURIComponent(normalized.replace('zhihu://openQuestion?id=', ''));
      if (qId.length > 0) {
        router.pushUrl({
          url: 'pages/Question',
          params: {
            questionId: qId,
            title: this.detail?.questionTitle ?? text
          }
        });
      }
      return;
    }

    // 拦截 WebView 内摘要作者头像/昵称的 zhihu://openPerson 链接 → 跳作者主页
    if (normalized.startsWith('zhihu://openPerson?urlToken=')) {
      const token = decodeURIComponent(normalized.replace('zhihu://openPerson?urlToken=', ''));
      if (token.length > 0) {
        router.pushUrl({ url: 'pages/People', params: { urlToken: token } });
      }
      return;
    }

    const zhihuTarget = resolveZhihuContent(normalized);
    if (zhihuTarget !== undefined) {
      router.pushUrl({
        url: 'pages/Article',
        params: {
          target: serializeZhihuContentTarget(zhihuTarget),
          fallbackTitle: text,
          fallbackUrl: normalized
        }
      });
      return;
    }

    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      router.pushUrl({
        url: 'pages/WebContent',
        params: {
          title: text.length > 0 ? text : '网页',
          url: normalized
        }
      });
      return;
    }

    this.showToast('暂不支持打开该链接');
  }

  private async ensureRootComments(forceReload: boolean = false): Promise<void> {
    const detail = this.detail;
    if (detail === undefined) {
      return;
    }
    const tid = detail.target.id;
    const seg = this.currentSegmentForComments;
    const segmentId = seg ? seg.segIds.join(',') : '';
    const cacheKey = segmentId.length > 0 ? `seg:${segmentId}` : tid;
    if (!forceReload && this.rootCommentCacheKey === cacheKey && this.rootComments.length > 0) {
      return;
    }
    if (this.rootCommentLoading && !forceReload) {
      return;
    }
    this.rootCommentLoading = true;
    try {
      const page = await CommentService.loadRootComments(
        this.context(),
        detail.target,
        this.rootCommentSortOrder,
        undefined,
        segmentId.length > 0 ? segmentId : undefined
      );
      // 滑动期间若 this.detail 已被切到别的回答，丢弃这次结果，避免把旧回答的评论写回
      if (this.detail === undefined || this.detail.target.id !== tid) {
        return;
      }
      this.rootComments = page.items;
      this.rootCommentNextUrl = page.nextUrl;
      this.rootCommentEnd = page.isEnd;
      this.rootCommentError = '';
      this.rootCommentTargetId = tid;
      this.rootCommentCacheKey = cacheKey;
      // 通知评论定位：根评论加载完成后，置顶锚点评论（必要时自动展开楼中楼）
      this.consumeAnchorComment();
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.rootCommentError = `评论加载失败：${message}`;
    } finally {
      this.rootCommentLoading = false;
    }
  }

  private async loadMoreRootComments(): Promise<void> {
    const detail = this.detail;
    if (detail === undefined || this.rootCommentLoadingMore || this.rootCommentEnd || this.rootCommentNextUrl.length === 0) {
      return;
    }
    this.rootCommentLoadingMore = true;
    try {
      const page = await CommentService.loadRootComments(
        this.context(),
        detail.target,
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
    const detail = this.detail;
    if (detail === undefined || this.rootSubmitting) {
      return;
    }
    this.rootSubmitting = true;
    try {
      const created = await CommentService.submitComment(
        this.context(),
        detail.target,
        this.rootCommentDraft,
        this.rootReplyTo?.id,
        this.currentSegmentForComments
          ? {
              segmentContent: this.currentSegmentForComments.displayText,
              paragraphId: this.currentSegmentForComments.paragraphId,
              startOffset: this.currentSegmentForComments.startOffset,
              endOffset: this.currentSegmentForComments.endOffset
            }
          : undefined
      );
      this.rootComments = [created, ...this.rootComments];
      this.rootCommentDraft = '';
      this.rootReplyTo = undefined;
      this.showRootEmojiPanel = false;
      if (this.currentSegmentForComments === null) {
        this.detail = copyDetail(detail, undefined, undefined, detail.commentCount + 1);
      } else {
        // 片段评论：重新拉取该片段评论列表以反映最新评论
        await this.ensureRootComments(true);
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
    const detail = this.detail;
    if (detail === undefined) {
      return;
    }
    this.childTarget = {
      kind: 'comment',
      commentId: comment.id,
      article: detail.target
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
        // 楼中楼：自动打开该根的回复层，并把目标回复（B item）置顶
        this.openChildComments(root, target);
      }
    } catch (e) {
      // 锚点评论详情拉取失败时静默吞掉，保持 UI 稳定（诊断日志已确认根因，移除）
    }
  }

  private openComments(): void {
    this.showRootCommentSheet = true;
    this.ensureRootComments();
  }

  private openSegmentComments(): void {
    const seg = this.selectedSegment;
    if (seg === null) {
      return;
    }
    this.currentSegmentForComments = seg;
    this.showSegmentSheet = false;
    this.showRootCommentSheet = true;
    this.ensureRootComments(true);
  }

  /** 顶部右侧三点菜单：固定在问题标题首行右侧，不随正文滚动（无 translate）。
   *  问题标题在 WebView 内已做 padding-right 让位，三点始终浮在顶部。
   */
  @Builder
  private SummarySection(): void {
    if (this.detail !== undefined) {
      Column({ space: 14 }) {
        Row({ space: 8 }) {
          Text(this.detail?.target.kind === 'answer' && (this.detail?.questionTitle.length ?? 0) > 0
            ? this.detail?.questionTitle ?? ''
            : this.detail?.title ?? '')
            .fontSize(this.fontHeading)
            .fontWeight(FontWeight.Bold)
            .lineHeight(28)
            .fontColor($r('app.color.text_primary'))
            .copyOption(CopyOptions.InApp)
            .layoutWeight(1)
            .onClick(() => {
              this.openQuestion();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row({ space: 12 }) {
          if ((this.detail?.author?.avatarUrl ?? '').length > 0) {
            Image(this.detail?.author?.avatarUrl ?? '')
              .width(44)
              .height(44)
              .objectFit(ImageFit.Cover)
              .borderRadius(22)
          } else {
            Column() {
              Text(this.detail?.author?.name.slice(0, 1) ?? '知')
                .fontSize(this.fontBody)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.action_text'))
            }
            .width(44)
            .height(44)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor($r('app.color.action_background'))
            .borderRadius(22)
          }

          Column({ space: 2 }) {
            Text(this.detail?.author?.name ?? this.pageTitle)
              .fontSize(this.fontBody)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))

            if ((this.detail?.author?.headline ?? '').length > 0) {
              Text(this.detail?.author?.headline ?? '')
                .fontSize(this.fontCaption)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .onClick(() => {
          this.openPerson(this.detail?.author?.urlToken ?? '');
        })

        Row({ space: 10 }) {
          Text(formatCounter(this.detail?.voteCount ?? 0, this.detail?.canVote === true ? '赞同' : '喜欢'))
            .fontSize(this.fontCaption)
            .fontColor($r('app.color.text_secondary'))

          Text(formatCounter(this.detail?.commentCount ?? 0, '评论'))
            .fontSize(this.fontCaption)
            .fontColor($r('app.color.text_secondary'))

          if (formatUnixTime(this.detail?.updatedTime || this.detail?.createdTime || 0).length > 0) {
            Text(formatUnixTime(this.detail?.updatedTime || this.detail?.createdTime || 0))
              .fontSize(this.fontCaption)
              .fontColor($r('app.color.text_secondary'))
          }

          if ((this.detail?.ipInfo ?? '').length > 0) {
            Text(this.detail?.ipInfo ?? '')
              .fontSize(this.fontCaption)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 8, bottom: 16 })
    }
  }

  @Builder
  private ArticleBody(): void {
    if (this.articleLoading) {
      Column({ space: 10 }) {
        Text('正在加载详情...')
          .fontSize(this.fontSubhead)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('正在同步知乎内容与评论入口')
          .fontSize(this.fontMeta)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 60, left: 24, right: 24 })
    } else if (this.articleError.length > 0 || this.detail === undefined) {
      Column({ space: 12 }) {
        Text(this.articleError.length > 0 ? this.articleError : '内容不存在')
          .fontSize(this.fontBody)
          .fontColor($r('app.color.error_text'))
          .textAlign(TextAlign.Center)

        Text('重新加载')
          .fontSize(this.fontSecondary)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.action_text'))
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(this.pillRadius)
          .onClick(() => {
            this.loadArticle();
          })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 60, left: 24, right: 24 })
    } else {
      Column() {
        ZhihuRichWeb({
          html: buildArticleHtmlDocument(
            this.detail.title,
            `${this.detail.htmlContent}`,
            this.detail.browserUrl,
            resolveZhihuThemeMode(this.context(), this.themeMode),
            {
              questionId: this.detail?.questionId ?? '',
              questionTitle: this.detail?.target.kind === 'answer' && (this.detail?.questionTitle.length ?? 0) > 0
                ? this.detail?.questionTitle ?? ''
                : this.detail?.title ?? '',
              authorName: this.detail?.author?.name ?? this.pageTitle,
              authorAvatar: this.detail?.author?.avatarUrl ?? '',
              authorHeadline: this.detail?.author?.headline ?? '',
              authorUrlToken: this.detail?.author?.urlToken ?? '',
              voteCount: this.detail?.voteCount ?? 0,
              canVote: this.detail?.canVote === true,
              commentCount: this.detail?.commentCount ?? 0,
              updatedTime: this.detail?.updatedTime ?? 0,
              createdTime: this.detail?.createdTime ?? 0,
              ipInfo: this.detail?.ipInfo ?? '',
            } as ArticleSummaryData,
            this.topSafeAreaVp + ARTICLE_TOP_BAR_CLEARANCE_VP,
            100,
            100,
            undefined,
            this.buildSegmentJson()
          ),
          sourceUrl: this.detail.browserUrl,
          title: this.detail.title,
          themeMode: this.themeMode,
          fillHeight: true,
          onLinkTap: (url: string, text: string) => {
            this.openBodyLink(url, text);
          },
          onImageTap: (url: string) => {
            this.openImage(url);
          },
          onImageMenu: (url: string) => {
            this.showImageMenu(url);
          },
          onCopyMath: (latex: string) => {
            this.copyMathLatex(latex);
          },
          onVideoTap: (videoId: string) => {
            this.openVideo(videoId);
          },
          onScrollChange: (topPx: number) => {
            this.summaryScrollTop = topPx;
            this.updateBarsOnScroll(topPx);
          },
          onSummaryBoundsChange: (bottomPx: number) => {
            if (bottomPx > 0) {
              this.summaryBottomPx = bottomPx;
              this.summaryBoundsKnown = true;
            }
          },
          onHorizontalSwipe: (state: string, dx: number) => {
            this.handleHorizontalSwipe(state, dx);
          },
          onSegmentTap: (seg: ZhihuSegmentTapInfo) => {
            if (this.detail?.allowSegmentInteraction !== true) {
              return;
            }
            this.selectedSegment = seg;
            this.showSegmentSheet = true;
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(ThemeColors.articleBackground(this.oledBlack, this.isDark))
    }
  }

  @Builder
  private ActionBar(): void {
    if (this.detail !== undefined) {
      Row({ space: 10 }) {
        if (this.detail?.canVote === true) {
          Text(this.detail?.voteState === 'up' ? '取消赞同' : '赞同')
            .fontSize(this.fontSecondary)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.detail?.voteState === 'up' ? $r('app.color.action_text') : $r('app.color.text_primary'))
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .backgroundColor(this.detail?.voteState === 'up' ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({
              width: 1,
              color: this.detail?.voteState === 'up' ? $r('app.color.action_text') : $r('app.color.card_border')
            })
            .borderRadius(this.pillRadius)
            .onClick(() => {
              this.toggleVote(this.detail?.voteState === 'up' ? 'neutral' : 'up');
            })
        }

        if (this.detail?.canVote === true && this.detail?.supportsDownvote === true) {
          Text(this.detail?.voteState === 'down' ? '取消反对' : '反对')
            .fontSize(this.fontSecondary)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .backgroundColor(this.detail?.voteState === 'down' ? $r('app.color.tab_selected_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({ width: 1, color: $r('app.color.card_border') })
            .borderRadius(this.pillRadius)
            .onClick(() => {
              this.toggleVote(this.detail?.voteState === 'down' ? 'neutral' : 'down');
            })
        }

        Text(`评论 ${this.detail?.commentCount ?? 0}`)
          .fontSize(this.fontSecondary)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(this.pillRadius)
          .onClick(() => {
            this.openComments();
          })

        Text('网页')
          .fontSize(this.fontSecondary)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(this.pillRadius)
          .onClick(() => {
            this.openWebVersion();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: this.bottomSafeAreaVp + 10 })
      .backgroundColor($r('app.color.tab_bar_background'))
      .border({
        width: {
          top: 1
        },
        color: $r('app.color.tab_bar_border')
      })
      .backdropBlur(24)
    }
  }

  /** 底部沉浸光感药丸栏：图标改用 SVG 资源（Image + Template 着色），尺寸固定 20px、由 fillColor 控激活/默认态，
   *  彻底消除 Path 自绘「偏小/靠左上」的问题（viewBox 与路径坐标同用 24 系，居中满尺寸）。
   */
  @Builder
  private ActionBarTab(): void {
    Row({ space: 10 }) {
      // 左组：赞同（👍 + 数字）药丸
      if (this.detail?.canVote === true) {
        Row({ space: 4 }) {
          // 改用官方系统符号（HarmonyOS Symbol）：风格与系统一致、自动适配深浅色，不再依赖自定义 SVG。
          // SymbolGlyph 用 fontSize 控制大小、fontColor 传数组；Image 的 renderMode/fillColor 不适用。
          SymbolGlyph($r('sys.symbol.hand_thumbsup_fill'))
            .fontSize(this.fontHeading)
            .fontColor([this.detail?.voteState === 'up' ? '#FFFFFF' : $r('app.color.action_pill_icon')])
          Text(formatVoteCount(this.detail?.voteCount ?? 0))
            .fontSize(this.fontSecondary)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.detail?.voteState === 'up' ? '#FFFFFF' : $r('app.color.action_pill_icon'))
        }
        .alignItems(VerticalAlign.Center)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor(this.detail?.voteState === 'up' ? $r('app.color.action_text') : ThemeColors.oledBlack(this.oledBlack, this.isDark, $r('app.color.action_pill_button_inactive')))
        .borderRadius(this.pillRadius)
        .onClick(() => {
          this.toggleVote(this.detail?.voteState === 'up' ? 'neutral' : 'up');
        })

        // 反对（👎）药丸（无数字）
        if (this.detail?.supportsDownvote === true) {
          Row() {
            SymbolGlyph($r('sys.symbol.hand_thumbsdown'))
              .fontSize(this.fontHeading)
              .fontColor([this.detail?.voteState === 'down' ? '#FFFFFF' : $r('app.color.action_pill_icon')])
          }
          .alignItems(VerticalAlign.Center)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(this.detail?.voteState === 'down' ? $r('app.color.action_text') : ThemeColors.oledBlack(this.oledBlack, this.isDark, $r('app.color.action_pill_button_inactive')))
          .borderRadius(this.pillRadius)
          .onClick(() => {
            this.toggleVote(this.detail?.voteState === 'down' ? 'neutral' : 'down');
          })
        }
      }

      Blank()

      // 右组：收藏（书签）药丸
      Row() {
        SymbolGlyph($r('sys.symbol.bookmark'))
          .fontSize(this.fontHeading)
          .fontColor([this.favorited ? '#FFFFFF' : $r('app.color.action_pill_icon')])
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.favorited ? $r('app.color.action_text') : ThemeColors.oledBlack(this.oledBlack, this.isDark, $r('app.color.action_pill_button_inactive')))
      .borderRadius(this.pillRadius)
      .onClick(() => {
        this.openCollectionSheet();
      })

      // 评论（💬 + 数字）药丸
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.message'))
          .fontSize(this.fontHeading)
          .fontColor([$r('app.color.action_pill_icon')])
        Text(`${this.detail?.commentCount ?? 0}`)
          .fontSize(this.fontSecondary)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.action_pill_icon'))
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(ThemeColors.oledBlack(this.oledBlack, this.isDark, $r('app.color.action_pill_button_inactive')))
      .borderRadius(this.pillRadius)
      .onClick(() => {
        this.openComments();
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 6, bottom: 6 })
  }


  /** HdsTabs 主内容区：正文 + 底部沉浸光感导航栏 */
  @Builder
  private MainContent(): void {
    // 去掉 HdsTabs 容器：其 TabContent 未配 tabBar 时仍会渲染一个系统默认色的底部 bar 占位，
    // 形成「浅色白/深色黑」常驻底块。横滑手势与沉浸光感分别由外层 Stack / HdsNavDestination 承载，故直接用 Stack。
    Stack({ alignContent: Alignment.BottomStart }) {
      // 主内容列
      Column() {
        this.ArticleBody()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeColors.articleBackground(this.oledBlack, this.isDark))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .padding({ top: this.immersiveMode ? this.topSafeAreaVp : 0 })
          .bindSheet($$this.showRootCommentSheet, this.RootCommentSheet(), {
              showClose: false,
              dragBar: true,
              preferType: SheetType.BOTTOM,
              detents: [SheetSize.LARGE],
              backgroundColor: ThemeColors.articleBackground(this.oledBlack, this.isDark),
              onDisappear: () => {
                this.showRootCommentSheet = false;
                this.rootReplyTo = undefined;
                this.currentSegmentForComments = null;
                this.rootCommentCacheKey = '';
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

          // 底栏由外层 HdsTabs barFloatingStyle 承载（真·HDS 沉浸光感材质）

          // 顶栏悬浮层（沉浸模式整体隐藏）：返回 + 标题/作者 + ⋮，随 WebView 滚动跟手显隐
          if (!this.immersiveMode) {
            ContentTopBar({
              title: this.detail?.target.kind === 'answer' && (this.detail?.questionTitle.length ?? 0) > 0
                ? this.detail?.questionTitle ?? ''
                : this.detail?.title ?? '',
              authorName: this.detail?.author?.name ?? '',
              authorAvatar: this.detail?.author?.avatarUrl ?? '',
              contentProgress: this.contentProgress,
              offsetY: this.topBarOffsetY,
              menuItems: [
                { value: '在知乎中打开', action: () => this.openInZhihuApp() },
                { value: '复制链接', action: () => this.copyCurrentLink() },
                { value: '分享', action: () => this.systemShare() },
                { value: '进入沉浸', action: () => this.enterImmersive() },
                { value: this.ttsSpeaking ? '停止朗读' : '开始朗读', action: () => this.toggleTts() },
                { value: '总结本文', action: () => this.startSummary() },
                { value: '导出文章…', action: () => { this.showExportSheet = true; } }
              ],
              onBack: () => {
                router.back({ url: '' });
              },
              onTitleClick: () => {
                this.openQuestion();
              },
              onAuthorClick: () => {
                this.openPerson(this.detail?.author?.urlToken ?? '');
              },
              onHeightChange: (h: number) => {
                this.collapsedHeight = h;
              }
            })
            .position({ x: 0, y: 0 })
            .zIndex(40)
          }

          // child comment bindSheet
          Column()
            .width(1)
            .height(1)
            .bindSheet($$this.showChildCommentSheet, this.ChildCommentSheet(), {
              showClose: false,
              dragBar: true,
              preferType: SheetType.BOTTOM,
              detents: [SheetSize.LARGE],
              backgroundColor: ThemeColors.articleBackground(this.oledBlack, this.isDark),
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

          // 收藏夹选择 bindSheet
          Column()
            .width(1)
            .height(1)
            .bindSheet($$this.showCollectionSheet, this.CollectionSheetContent(), {
              showClose: false,
              dragBar: true,
              preferType: SheetType.BOTTOM,
              detents: [SheetSize.MEDIUM, SheetSize.LARGE],
              backgroundColor: ThemeColors.articleBackground(this.oledBlack, this.isDark),
              onDisappear: () => {
                this.showCollectionSheet = false;
                this.showCreateCollection = false;
              }
            })

          // 总结本文 bindSheet
          Column()
            .width(1)
            .height(1)
            .bindSheet($$this.showSummarySheet, this.SummarySheet(), {
              showClose: true,
              dragBar: true,
              preferType: SheetType.BOTTOM,
              detents: [SheetSize.LARGE],
              backgroundColor: ThemeColors.articleBackground(this.oledBlack, this.isDark),
              onDisappear: () => {
                this.cancelSummaryStream();
              }
            })

          // 导出文章 bindSheet
          Column()
            .width(1)
            .height(1)
            .bindSheet($$this.showExportSheet, this.ExportSheet(), {
              showClose: true,
              dragBar: true,
              preferType: SheetType.BOTTOM,
              detents: [SheetSize.MEDIUM, SheetSize.LARGE],
              backgroundColor: ThemeColors.articleBackground(this.oledBlack, this.isDark),
              onDisappear: () => {
                this.showExportSheet = false;
              }
            })

          // 划线片段 bindSheet（独立节点，避免与评论弹窗同一节点冲突）
          Column()
            .width(1)
            .height(1)
            .bindSheet($$this.showSegmentSheet, this.SegmentActionSheet(), {
              showClose: true,
              dragBar: true,
              preferType: SheetType.BOTTOM,
              detents: [SheetSize.MEDIUM, SheetSize.LARGE],
              backgroundColor: ThemeColors.articleBackground(this.oledBlack, this.isDark),
              onDisappear: () => {
                this.showSegmentSheet = false;
                this.selectedSegment = null;
              }
            })
        }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeColors.articleBackground(this.oledBlack, this.isDark))
      .translate({ x: this.offsetX })
      .blur(this.currentBlurRadius)
      .onAreaChange((_old: Area, newValue: Area) => {
        if (newValue && newValue.width > 0) {
          this.containerWidth = Number(newValue.width);
        }
      })
  }

  // 选择收藏夹底部弹层（对齐安卓 CollectionDialogComponent）
  @Builder
  private CollectionSheetContent(): void {
    Column({ space: 0 }) {
      if (this.showCreateCollection) {
        // 新建收藏夹表单（居中卡片，避免贴边）
        Column({ space: 0 }) {
          Row({ space: 8 }) {
            Text('新建收藏夹')
              .fontSize(this.fontSubhead)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)

            Text('取消')
              .fontSize(this.fontSecondary)
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .onClick(() => {
                this.showCreateCollection = false;
                this.newCollectionTitle = '';
                this.newCollectionDesc = '';
                this.newCollectionPublic = false;
              })
          }
          .width('100%')
          .padding({ bottom: 12 })

        TextInput({ text: this.newCollectionTitle, placeholder: '收藏夹名称' })
          .width('100%')
          .height(44)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .borderRadius(this.cardRadius)
          .border({ width: 1, color: $r('app.color.card_border') })
          .padding({ left: 14, right: 14 })
          .margin({ bottom: 12 })
          .onChange((value: string) => {
            this.newCollectionTitle = value;
          })

        TextInput({ text: this.newCollectionDesc, placeholder: '描述（可选）' })
          .width('100%')
          .height(44)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .borderRadius(this.cardRadius)
          .border({ width: 1, color: $r('app.color.card_border') })
          .padding({ left: 14, right: 14 })
          .margin({ bottom: 12 })
          .onChange((value: string) => {
            this.newCollectionDesc = value;
          })

        Row({ space: 10 }) {
          Text('公开收藏夹')
            .fontSize(this.fontSecondary)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.newCollectionPublic })
            .onChange((isOn: boolean) => {
              this.newCollectionPublic = isOn;
            })
        }
        .width('100%')
        .padding({ bottom: 12 })

        Text(this.creatingCollection ? '创建中…' : '创建')
          .fontSize(this.fontSecondary)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.newCollectionTitle.trim().length === 0 || this.creatingCollection
            ? $r('app.color.text_tertiary')
            : $r('app.color.action_text'))
          .padding({ left: 16, right: 16, top: 11, bottom: 11 })
          .backgroundColor(this.newCollectionTitle.trim().length === 0
            ? ThemeColors.articleBackground(this.oledBlack, this.isDark)
            : $r('app.color.action_background'))
          .borderRadius(this.buttonRadius)
          .border({ width: 1, color: $r('app.color.card_border') })
          .alignSelf(ItemAlign.End)
          .enabled(this.newCollectionTitle.trim().length > 0 && !this.creatingCollection)
          .onClick(() => {
            this.submitNewCollection();
          })
        }
        .width('86%')
        .alignSelf(ItemAlign.Center)
        .margin({ top: 8, bottom: 16 })
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .borderRadius(this.cardRadius)
        .border({ width: 1, color: $r('app.color.card_border') })
      } else {
        Text('选择收藏夹')
          .fontSize(this.fontSubhead)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 12 })

        // 新建收藏夹入口
        Row({ space: 10 }) {
          Text('＋')
            .fontSize(this.fontHeading)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.action_text'))

          Text('新建收藏夹')
            .fontSize(this.fontBody)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.action_text'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor($r('app.color.action_background'))
        .borderRadius(this.cardRadius)
        .margin({ left: 16, right: 16, bottom: 8 })
        .onClick(() => {
          this.showCreateCollection = true;
        })

        if (this.collectionError.length > 0 && this.collections.length === 0) {
          Column({ space: 12 }) {
            Text(this.collectionError)
              .fontSize(this.fontSecondary)
              .fontColor($r('app.color.error_text'))
              .width('100%')
              .textAlign(TextAlign.Center)
            Text('重新加载')
              .fontSize(this.fontSecondary)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.action_text'))
              .padding({ left: 18, right: 18, top: 10, bottom: 10 })
              .backgroundColor($r('app.color.action_background'))
              .borderRadius(this.pillRadius)
              .onClick(() => {
                this.loadCollectionsForContent();
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 40, bottom: 40 })
        } else if (this.collectionLoading && this.collections.length === 0) {
          Text('正在加载收藏夹…')
            .fontSize(this.fontSecondary)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 20, bottom: 20 })
        } else if (this.collections.length === 0) {
          Text('还没有收藏夹，点击上方新建')
            .fontSize(this.fontSecondary)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 20, bottom: 20 })
        } else {
          List() {
            ForEach(this.collections, (collection: ZhihuCollection) => {
              ListItem() {
                this.CollectionRow(collection);
              }
            }, (collection: ZhihuCollection) => `${collection.id}:${this.collectionRenderVersion}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.articleBackground(this.oledBlack, this.isDark))
  }

  @Builder
  private CollectionRow(collection: ZhihuCollection): void {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(collection.title)
          .fontSize(this.fontBody)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (collection.description.length > 0) {
          Text(collection.description)
            .fontSize(this.fontCaption)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Text(`${collection.itemCount} 篇内容`)
          .fontSize(this.fontCaption)
          .fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(collection.isFavorited ? '★' : '☆')
        .fontSize(this.fontSymbol)
        .fontColor(collection.isFavorited ? $r('app.color.action_text') : $r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick(() => {
      this.toggleCollectionFavorite(collection);
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
      // 畅联风格：长条圆角悬浮胶囊（输入区 + 表情/键盘切换 + 纸飞机发送，均在栏内）
      // 鸿蒙7(API26) 沉浸光感预留：把外层容器改为
      //   .backgroundColor(Color.Transparent).backgroundBlurStyle(BlurStyle.Thin)
      // 并令 useImmersive 返回 true 即可，布局无需改动。
      Row({ space: 8 }) {
        TextArea({
          controller: inputController,
          text: this.liveCommentDraft(isChild),
          placeholder: this.resolveReplyTo(isChild) !== undefined ? `回复 ${this.resolveReplyTo(isChild)?.author.name ?? ''}...` : '写下你的评论...'
        })
          .layoutWeight(1)
          .maxLines(4)
          .enterKeyType(EnterKeyType.NEW_LINE)
          .constraintSize({ minHeight: 38 })
          .id(isChild ? 'childCommentInput' : 'rootCommentInput')
          .focusable(true)
          .backgroundColor(Color.Transparent)
          .fontSize(this.fontBody)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .padding({ left: 6, right: 6 })
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

        if (this.liveEmojiPanelOpen(isChild)) {
          SymbolGlyph($r('sys.symbol.keyboard'))
            .fontSize(this.fontHeading)
            .fontColor([$r('app.color.text_secondary')])
            .onClick(() => {
              onToggleEmoji();
            })
        } else {
          SymbolGlyph($r('sys.symbol.face_smiling'))
            .fontSize(this.fontHeading)
            .fontColor([$r('app.color.text_secondary')])
            .onClick(() => {
              onToggleEmoji();
            })
        }

        SymbolGlyph($r('sys.symbol.paperplane'))
          .fontSize(this.fontHeading)
          .fontColor([
            this.liveCommentSubmitting(isChild) || this.liveCommentDraft(isChild).trim().length === 0
              ? $r('app.color.text_tertiary')
              : $r('app.color.action_text')
          ])
          .enabled(!this.liveCommentSubmitting(isChild) && this.liveCommentDraft(isChild).trim().length > 0)
          .onClick(() => {
            onSubmit();
          })
      }
      .width('100%')
      .padding({ left: 14, right: 10, top: 5, bottom: 5 })
      .backgroundColor(ThemeColors.floatBarBackground(this.oledBlack, this.isDark))
      .backgroundBlurStyle(BlurStyle.Thin)
      .border({
        width: 1,
        color: this.isDark ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.06)',
        radius: this.cardRadius * 2
      })
      .shadow(this.isDark
        ? { radius: 10, color: 'rgba(0,0,0,0.45)', offsetX: 0, offsetY: -2 }
        : { radius: 8, color: 'rgba(0,0,0,0.08)', offsetX: 0, offsetY: -1 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: this.bottomSafeAreaVp + 8 })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private SortChip(label: string, selected: boolean, onClick: () => void): void {
    Text(label)
      .fontSize(this.fontCaption)
      .fontWeight(selected ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(selected ? $r('app.color.action_text') : $r('app.color.text_secondary'))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor(selected ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .borderRadius(this.cardRadius)
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
        .fontSize(this.fontSecondary)
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
              .fontSize(this.fontSymbol)
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
        .fontSize(this.fontCaption)
        .fontWeight(FontWeight.Medium)
        .fontColor(enabled ? $r('app.color.action_text') : $r('app.color.text_tertiary'))
    }
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .backgroundColor(ThemeColors.articleBackground(this.oledBlack, this.isDark))
    .borderRadius(this.cardRadius)
    .border({ width: 1, color: $r('app.color.card_border') })
    .enabled(enabled)
    .onClick(() => {
      onClick();
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
              .fontSize(this.fontCaption)
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
                .fontSize(this.fontCaption)
                .fontColor($r('app.color.action_text'))
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor($r('app.color.action_background'))
                .borderRadius(10)
            }

            if (comment.replyToAuthor !== undefined) {
              Text(`回复 ${comment.replyToAuthor.name}`)
                .fontSize(this.fontCaption)
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
                      this.openCommentLink(seg.url!, seg.text ?? '');
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
              .borderRadius(this.cardRadius)
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
            .fontSize(this.fontCaption)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)

          if (comment.ipInfo.length > 0) {
            Text(comment.ipInfo)
              .layoutWeight(1)
              .fontSize(this.fontCaption)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)

        Row({ space: 12 }) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.message'))
              .fontSize(this.fontBody)
              .fontColor([$r('app.color.action_pill_icon')])

            if (!fromChildSheet && comment.childCommentCount > 0) {
              Text(`${comment.childCommentCount}`)
                .fontSize(this.fontCaption)
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
            SymbolGlyph($r('sys.symbol.hand_thumbsup_fill'))
              .fontSize(this.fontBody)
              .fontColor([comment.liked ? $r('app.color.action_text') : $r('app.color.action_pill_icon')])

            Text(`${comment.likeCount}`)
              .fontSize(this.fontCaption)
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
              .fontSize(this.fontCaption)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor(ThemeColors.articleBackground(this.oledBlack, this.isDark))
          .borderRadius(this.cardRadius)
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
        if (this.currentSegmentForComments !== null) {
          Text('划线评论')
            .fontSize(this.fontHeading)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(`「${this.currentSegmentForComments.displayText}」`)
            .fontSize(this.fontCaption)
            .fontColor($r('app.color.text_secondary'))
        } else {
          Text('评论')
            .fontSize(this.fontHeading)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(`${this.detail?.commentCount ?? 0} 条评论`)
            .fontSize(this.fontCaption)
            .fontColor($r('app.color.text_secondary'))
        }

        Row({ space: 10 }) {
          if (this.rootCommentSortOrder === 'score') {
            this.SortChip('最热', true, () => {
              if (this.rootCommentSortOrder !== 'score') {
                this.rootCommentSortOrder = 'score';
                this.ensureRootComments(true);
              }
            })
          } else {
            this.SortChip('最热', false, () => {
              if (this.rootCommentSortOrder !== 'score') {
                this.rootCommentSortOrder = 'score';
                this.ensureRootComments(true);
              }
            })
          }

          if (this.rootCommentSortOrder === 'time') {
            this.SortChip('最新', true, () => {
              if (this.rootCommentSortOrder !== 'time') {
                this.rootCommentSortOrder = 'time';
                this.ensureRootComments(true);
              }
            })
          } else {
            this.SortChip('最新', false, () => {
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
    .backgroundColor(ThemeColors.articleBackground(this.oledBlack, this.isDark))
  }

  /** 划线片段弹窗：对齐安卓 SegmentActionSheet。标题「划线片段」+ 原句引用 + 赞/评论/复制三按钮 */
  @Builder
  private SegmentActionSheet(): void {
    Column() {
      Column({ space: 14 }) {
        Text('划线片段')
          .fontSize(this.fontSubhead)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .alignSelf(ItemAlign.Start)

        if (this.selectedSegment !== null) {
          Column() {
            Text(`「${this.selectedSegment?.displayText ?? ''}」`)
              .fontSize(this.fontBody)
              .lineHeight(24)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .padding(14)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .borderRadius(this.cardRadius)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 18, bottom: 10 })

      Row({ space: 8 }) {
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.hand_thumbsup_fill'))
              .fontSize(this.fontHeading)
              .fontColor([this.selectedSegment?.isLike === true ? $r('app.color.action_text') : $r('app.color.text_secondary')])
            Text(`${this.selectedSegment?.likeCount ?? 0}`)
              .fontSize(this.fontSecondary)
              .fontColor(this.selectedSegment?.isLike === true ? $r('app.color.action_text') : $r('app.color.text_secondary'))
          }
        }
        .height(44)
        .padding({ left: 16, right: 16 })
        .borderRadius(22)
        .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .onClick(() => {
          this.toggleSegmentLike();
        })

        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.message'))
              .fontSize(this.fontHeading)
              .fontColor([$r('app.color.text_secondary')])
            Text(`${this.selectedSegment?.commentCount ?? 0}`)
              .fontSize(this.fontSecondary)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .height(44)
        .padding({ left: 16, right: 16 })
        .borderRadius(22)
        .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .onClick(() => {
          this.openSegmentComments();
        })

        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.doc'))
              .fontSize(this.fontHeading)
              .fontColor([$r('app.color.text_secondary')])
            Text('复制')
              .fontSize(this.fontSecondary)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .height(44)
        .padding({ left: 16, right: 16 })
        .borderRadius(22)
        .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .onClick(() => {
          this.copySegmentText();
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 20, right: 20, bottom: 28 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.articleBackground(this.oledBlack, this.isDark))
  }

  private buildSegmentJson(): string | undefined {
    const detail = this.detail;
    if (detail === undefined || detail.allowSegmentInteraction !== true) {
      return undefined;
    }
    const segmentInfos = detail.segmentInfos;
    if (segmentInfos === undefined || segmentInfos.length === 0) {
      return undefined;
    }
    const payload: SegmentInjectionPayload = {
      allow: true,
      sourceUrl: detail.browserUrl,
      contentId: detail.target.id,
      contentType: detail.target.kind,
      paragraphs: segmentInfos
    };
    return JSON.stringify(payload);
  }

  private async toggleSegmentLike(): Promise<void> {
    const seg = this.selectedSegment;
    const detail = this.detail;
    if (seg === null || detail === undefined || this.segmentLiking) {
      return;
    }
    const context = this.context();
    const url = `https://www.zhihu.com/api/v4/reaction/${seg.contentType}s/${seg.contentId}/segment_reaction`;
    const segIdsJoined = seg.segIds.join(',');
    this.segmentLiking = true;
    try {
      if (seg.isLike) {
        const unlikeBody: SegmentUnlikeBody = { seg_ids: segIdsJoined };
        await ZhihuApi.deleteJson(context, url, { signed: true, body: JSON.stringify(unlikeBody) });
      } else {
        const likeBody: SegmentLikeBody = {
          seg_id: segIdsJoined,
          content: seg.displayText,
          position: {
            start: { paragraph_id: seg.paragraphId, offset: seg.startOffset },
            end: { paragraph_id: seg.paragraphId, offset: seg.endOffset }
          }
        };
        await ZhihuApi.postJson(context, url, { signed: true, body: JSON.stringify(likeBody) });
      }
      const nowLiked = !seg.isLike;
      const delta = nowLiked ? 1 : -1;
      this.selectedSegment = {
        id: seg.id,
        likeCount: Math.max(0, seg.likeCount + delta),
        commentCount: seg.commentCount,
        isLike: nowLiked,
        displayText: seg.displayText,
        contentId: seg.contentId,
        contentType: seg.contentType,
        paragraphId: seg.paragraphId,
        startOffset: seg.startOffset,
        endOffset: seg.endOffset,
        segIds: seg.segIds
      };
      this.showToast(nowLiked ? '已赞' : '已取消赞');
    } catch (e) {
      this.showToast('操作失败，请重试');
    } finally {
      this.segmentLiking = false;
    }
  }

  private copySegmentText(): void {
    const seg = this.selectedSegment;
    if (seg === null) {
      return;
    }
    try {
      const pb = pasteboard.getSystemPasteboard();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, seg.displayText);
      pb.setData(pasteData);
      this.showToast('已复制划线内容');
    } catch (e) {
      this.showToast('复制失败');
    }
  }

  @Builder
  private ChildCommentSheet(): void {
    Column() {
      Column({ space: 6 }) {
        Text('回复')
          .fontSize(this.fontHeading)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(`${this.activeChildComment?.childCommentCount ?? this.childComments.length} 条回复`)
          .fontSize(this.fontCaption)
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
                .fontSize(this.fontCaption)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))

              this.CommentCard(this.activeChildComment, true, false, false)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 14, bottom: 14 })
            .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .borderRadius(this.pillRadius)
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
    .backgroundColor(ThemeColors.articleBackground(this.oledBlack, this.isDark))
  }

  // 左预览：直接读 @State prevPreviewItem（不通过参数传递，ArkUI 才能正确追踪 @State 依赖）
  @Builder
  private PrevNeighborPreview() {
    Column() {
      if (this.prevPreviewItem !== undefined) {
        Column() {
          Text(this.prevPreviewItem.title)
            .fontSize(this.fontHeading)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Row({ space: 8 }) {
            if (this.prevPreviewItem.authorAvatarUrl.length > 0) {
              Image(this.prevPreviewItem.authorAvatarUrl)
                .width(36)
                .height(36)
                .borderRadius(this.pillRadius)
                .objectFit(ImageFit.Cover)
            }
            Column() {
              Text(this.prevPreviewItem.authorName)
                .fontSize(this.fontSecondary)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.prevPreviewItem.authorHeadline.length > 0) {
                Text(this.prevPreviewItem.authorHeadline)
                  .fontSize(this.fontCaption)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .margin({ top: 14 })
          .width('100%')

          Text(this.prevPreviewItem.summary)
            .fontSize(this.fontBody)
            .fontColor($r('app.color.text_primary'))
            .lineHeight(23)
            .maxLines(8)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 14 })
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 24, right: 64 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
  }

  // 右预览：直接读 @State nextPreviewItem
  @Builder
  private NextNeighborPreview() {
    Column() {
      if (this.nextPreviewItem !== undefined) {
        Column() {
          Text(this.nextPreviewItem.title)
            .fontSize(this.fontHeading)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Row({ space: 8 }) {
            if (this.nextPreviewItem.authorAvatarUrl.length > 0) {
              Image(this.nextPreviewItem.authorAvatarUrl)
                .width(36)
                .height(36)
                .borderRadius(this.pillRadius)
                .objectFit(ImageFit.Cover)
            }
            Column() {
              Text(this.nextPreviewItem.authorName)
                .fontSize(this.fontSecondary)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.nextPreviewItem.authorHeadline.length > 0) {
                Text(this.nextPreviewItem.authorHeadline)
                  .fontSize(this.fontCaption)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .margin({ top: 14 })
          .width('100%')

          Text(this.nextPreviewItem.summary)
            .fontSize(this.fontBody)
            .fontColor($r('app.color.text_primary'))
            .lineHeight(23)
            .maxLines(8)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 14 })
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ right: 24, left: 64 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.End)
  }

  // 总结本文弹层（流式文本）
  @Builder
  private SummarySheet(): void {
    Column() {
      Row() {
        Text('总结本文')
          .fontSize(this.fontSubhead)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (this.summaryLoading) {
          LoadingProgress().width(20).height(20).color($r('app.color.text_secondary'))
        } else if (this.summaryStarted && this.summaryText.length > 0) {
          Button('停止')
            .fontSize(this.fontMeta)
            .height(32)
            .onClick(() => this.cancelSummaryStream())
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column() {
          if (this.summaryError.length > 0) {
            Text(this.summaryError)
              .fontSize(this.fontSecondary)
              .fontColor('#e5484d')
              .padding(this.cardPadding)
          } else if (this.summaryText.length > 0) {
            Text(this.summaryText)
              .fontSize(this.fontBody)
              .lineHeight(28)
              .fontColor($r('app.color.text_primary'))
              .padding(this.cardPadding)
          } else if (this.summaryLoading) {
            Text('正在生成总结…')
              .fontSize(this.fontSecondary)
              .fontColor($r('app.color.text_secondary'))
              .padding(this.cardPadding)
          } else {
            Text('点击开始生成总结')
              .fontSize(this.fontSecondary)
              .fontColor($r('app.color.text_secondary'))
              .padding(this.cardPadding)
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.articleBackground(this.oledBlack, this.isDark))
  }

  // 导出文章弹层：禁用功能在上、可用功能在中、带评论 + 开源说明开关在下
  @Builder
  private ExportSheet(): void {
    Column() {
      Text('导出文章')
        .fontSize(this.fontSubhead)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column() {
          // 禁用功能（上方）
          this.ExportItem('导出为 PDF', '暂时禁用，后续切第三方库实现', () => {}, true)
          Divider().color($r('app.color.card_border'))
          this.ExportItem('导出为图片', '当前版本暂不支持', () => {}, true)
          Divider().color($r('app.color.card_border'))
          // 可用功能
          this.ExportItem('导出为 HTML', '图片内联为 data URL，便于离线保存', () => this.doExport('html'))
          Divider().color($r('app.color.card_border'))
          this.ExportItem('复制 Markdown', '把正文转为 Markdown 写入剪贴板', () => this.doExport('markdown'))

          // 带评论导出（对所有格式生效）
          Column() {
            Text('带评论导出')
              .fontSize(this.fontBody)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            Text(`包含评论数量：${this.exportCommentCount} 条（0 = 关闭）`)
              .fontSize(this.fontMeta)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 8, bottom: 4 })
              .width('100%')
            Slider({
              value: this.exportCommentCount,
              min: 0,
              max: 10,
              step: 1,
              style: SliderStyle.OutSet
            })
              .width('100%')
              .blockColor($r('app.color.action_text'))
              .trackColor($r('app.color.card_border'))
              .selectedColor($r('app.color.action_text'))
              .onChange((value: number) => {
                this.exportCommentCount = value;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 8 })

          Divider().color($r('app.color.card_border'))

          // 开源说明开关
          Row() {
            Toggle({ type: ToggleType.Checkbox, isOn: this.includeAppAttribution })
              .onChange((isOn: boolean) => {
                this.includeAppAttribution = isOn;
              })
              .margin({ right: 10 })
            Text('在导出底部加入知乎++开源项目说明')
              .fontSize(this.fontSecondary)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')

      Button('取消')
        .width('100%')
        .margin({ left: 16, right: 16, bottom: 16 })
        .backgroundColor($r('app.color.card_border'))
        .fontColor($r('app.color.text_primary'))
        .onClick(() => {
          this.showExportSheet = false;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.articleBackground(this.oledBlack, this.isDark))
  }

  @Builder
  private ExportItem(title: string, desc: string, action: () => void, disabled: boolean = false): void {
    Row() {
      Column() {
        Text(title)
          .fontSize(this.fontBody)
          .fontColor(disabled ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
        Text(desc)
          .fontSize(this.fontCaption)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (!disabled) {
        Text('›')
          .fontSize(this.fontSymbol)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .opacity(disabled ? 0.5 : 1)
    .onClick(() => {
      if (!disabled) {
        action();
      }
    })
  }

  build() {
    HdsNavDestination() {
      HdsTabs({ controller: this.hdsTabsController }) {
        TabContent() {
        // 视口：固定不动，承载两侧预览（拖出时露出）与可水平平移的主场景
        Stack({ alignContent: Alignment.BottomStart }) {
      // 左预览：向右拖动（切上一篇）时从左侧露出。
      if (this.prevPreviewItem !== undefined) {
        Column() {
          this.PrevNeighborPreview()
        }
        .width('100%')
        .height('100%')
        .opacity(this.offsetX > 0 ? Math.min(1, this.offsetX / (this.containerWidth * 0.5 || 1)) : 0)
      }
      // 右预览：向左拖动（切下一篇）时从右侧露出。
      if (this.nextPreviewItem !== undefined) {
        Column() {
          this.NextNeighborPreview()
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.containerWidth + this.offsetX })
        .opacity(this.offsetX < 0 ? Math.min(1, -this.offsetX / (this.containerWidth * 0.5 || 1)) : 0)
      }

      // 主场景：HdsTabs 包裹（正文）
      this.MainContent()

      // 「跳转下一个回答」可拖动 FAB（对齐安卓 SkipNext 按钮；仅回答页、非沉浸模式显示，常驻/自动淡出）。
      // 注意：空 Stack 的默认 alignContent 是 Center、BottomStart 则贴底，position 均会叠加在对齐槽位之上
      // （曾三次把 FAB 推出屏幕外）；必须用 TopStart 显式归零对齐基准到 (0,0)，position 才等于屏幕坐标。
      // 外层视口 Stack 有 translate({x: offsetX})（左右切回答跟手平移），这里用反向 translate 抵消，保证 FAB 原地不动。
      if (this.detail?.target.kind === 'answer' && this.buttonSkipAnswer && !this.immersiveMode) {
        Stack({ alignContent: Alignment.TopStart }) {
          DraggableFab({
            prefKey: 'buttonSkipAnswer',
            symbol: 'forward_end_fill',
            loading: this.switching,
            initiallyOnLeft: false,
            onFabClick: () => this.switchToNeighbor('next')
          })
          .opacity(this.skipOpacity)
          .animation({ duration: 200 })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
        .translate({ x: -this.offsetX })
      }
    }
    .width('100%')
    .height('100%')
    .translate({ x: this.offsetX })
    .blur(this.currentBlurRadius)
    .onAreaChange((_old: Area, newValue: Area) => {
      if (newValue && newValue.width > 0) {
        this.containerWidth = Number(newValue.width);
      }
    })
        }
        .tabBar(this.ActionBarTab)
      }
      .barPosition(BarPosition.End)
      .barOverlap(true)
      .width('100%')
      .height('100%')
      .barFloatingStyle({
        barWidth: { smallWidth: 360, mediumWidth: 360, largeWidth: 560 },
        barSideMargin: 16,
        barBottomMargin: 12,
        systemMaterialEffect: {
          materialType: ZhihuMaterial.resolveType(),
          materialLevel: ZhihuMaterial.resolveLevel(this.materialLevel)
        }
      })
    }
  .width('100%')
  .height('100%')
}
}
