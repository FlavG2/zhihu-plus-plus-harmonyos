import common from '@ohos.app.ability.common';
import { promptAction, router, window, curves } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppearanceThemeMode } from '../services/AppearanceSettingsRepository';
import {
  CommentSortOrder,
  ZhihuCommentableTarget,
  ZhihuCommentTarget,
  ZhihuCommentItem
} from '../models/ZhihuContentModels';
import { DEFAULT_SESSION_SNAPSHOT, SessionSnapshot } from '../models/ZhihuModels';
import { PeopleService, ZhihuPin, ZhihuPinTopic } from '../services/PeopleService';
import { CommentService } from '../services/CommentService';
import { ZhihuSessionRepository } from '../services/ZhihuSessionRepository';
import { ZhihuRichWeb } from '../components/ZhihuRichWeb';
import { ContentTopBar } from '../components/ContentTopBar';
import { HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { ZhihuMaterial } from '../services/ZhihuMaterial';
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
  buildPinSummaryHtml,
  normalizeRichContentHtml,
  stripCommentImageLinks
} from '../utils/ZhihuHtml';
import { resolveZhihuThemeMode } from '../utils/ZhihuWebBridge';
import { ThemeColors } from '../services/ThemeColors';
import { ZhihuEmojiItem, EmojiPickerItem, ZhihuEmojiService, CommentContentSegment } from '../services/ZhihuEmojiService';
import { ZhihuContentTarget, serializeZhihuContentTarget } from '../models/ZhihuContentModels';
import { resolveZhihuContent } from '../services/ZhihuContentResolver';

interface PinPageParams {
  readonly pinId?: string;
  readonly fallbackUrl?: string;
  readonly anchorCommentId?: string;
}

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

function formatUnixTime(seconds: number): string {
  if (seconds <= 0) {
    return '';
  }
  const d = new Date(seconds * 1000);
  const y = `${d.getFullYear()}`;
  const M = `${d.getMonth() + 1}`.padStart(2, '0');
  const D = `${d.getDate()}`.padStart(2, '0');
  const h = `${d.getHours()}`.padStart(2, '0');
  const m = `${d.getMinutes()}`.padStart(2, '0');
  return `${y}-${M}-${D} ${h}:${m}`;
}


function formatCounter(value: number, unit: string): string {
  if (value >= 10000) {
    return `${(value / 10000).toFixed(value >= 100000 ? 0 : 1)} 万${unit}`;
  }
  return `${value} ${unit}`;
}

function errMsg(error: Object): string {
  return error instanceof Error ? error.message : '未知错误';
}

const COMMENT_FOOTER_INDENT: number = 46;

// 评论内点击图片/链接跳 WebContent 后，返回需重开评论 sheet（而非落回内容页）
let commentReopenPending: boolean = false;
const COMMENT_CHILD_INDENT: number = 44;
const COMMENT_CHILD_PREVIEW_LIMIT: number = 2;

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
struct Pin {
  // 软尺寸：由 DesignMetrics 按「官方基线 × 用户倍率」算出后写入 AppStorage，
  // 默认值与迁移前完全一致，故视觉零变化；用户调整字号/密度后本页自动重排。
  @StorageProp('fontSymbol') private fontSymbol: string = '24fp';
  @StorageProp('fontCaption') private fontCaption: string = '12fp';
  @StorageProp('fontMeta') private fontMeta: string = '13fp';
  @StorageProp('fontSecondary') private fontSecondary: string = '14fp';
  @StorageProp('fontBody') private fontBody: string = '16fp';
  @StorageProp('fontSubhead') private fontSubhead: string = '18fp';
  @StorageProp('fontHeading') private fontHeading: string = '20fp';
  @StorageProp('fontTitle') private fontTitle: string = '22fp';
  @StorageProp('fontLargeTitle') private fontLargeTitle: string = '26fp';
  @StorageProp('cardRadius') private cardRadius: number = 16;
  @StorageProp('pillRadius') private pillRadius: number = 18;
  @StorageProp('buttonRadius') private buttonRadius: number = 20;

  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageProp('bottomSafeAreaVp') private bottomSafeAreaVp: number = 0;
  @StorageProp('themeMode') private themeMode: AppearanceThemeMode = 'system';
  @StorageProp('sessionSnapshot') private sessionSnapshot: SessionSnapshot = DEFAULT_SESSION_SNAPSHOT;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;

  @StorageProp('materialLevel') private materialLevel: number = 10;


  private pinTabsController: HdsTabsController = new HdsTabsController();

  @State private pinId: string = '';
  @State private fallbackUrl: string = '';
  @State private pin: ZhihuPin | null = null;
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private contentHeightPx: number = 320;

  // 点赞状态（独立镜像，避免对象展开）
  @State private liked: boolean = false;
  @State private likeCount: number = 0;
  @State private pinLiking: boolean = false;

  // 评论 sheet
  @State private showRootCommentSheet: boolean = false;
  @State private anchorCommentId: string = '';
  @State private anchorConsumed: boolean = false;
  // 评论
  @State private rootComments: ZhihuCommentItem[] = [];
  @State private rootCommentNextUrl: string = '';
  @State private rootCommentEnd: boolean = false;
  @State private rootCommentLoading: boolean = false;
  @State private rootCommentLoadingMore: boolean = false;
  @State private rootCommentError: string = '';
  @State private rootCommentSortOrder: CommentSortOrder = 'score';
  @State private rootReplyTo: ZhihuCommentItem | undefined = undefined;
  @State private rootCommentDraft: string = '';
  @State private rootSubmitting: boolean = false;
  @State private commentRenderVersion: number = 0;
  @State private showRootEmojiPanel: boolean = false;
  @State private showChildEmojiPanel: boolean = false;
  @State private rootCaret: number = 0;
  @State private childCaret: number = 0;
  @State private emojiCols: number = 7;
  @State private emojiItems: EmojiPickerItem[] = [];
  private rootInputController: TextInputController = new TextInputController();
  private childInputController: TextInputController = new TextInputController();

  // 子评论（二级面板，对标回答页 Article.ets）
  @State private showChildCommentSheet: boolean = false;
  @State private childComments: ZhihuCommentItem[] = [];
  @State private childCommentNextUrl: string = '';
  @State private childCommentEnd: boolean = false;
  @State private childCommentLoading: boolean = false;
  @State private childCommentLoadingMore: boolean = false;
  @State private childCommentError: string = '';
  @State private childReplyTo: ZhihuCommentItem | undefined = undefined;
  @State private childCommentDraft: string = '';
  @State private childSubmitting: boolean = false;
  @State private childTarget?: ZhihuCommentTarget = undefined;
  @State private activeChildComment: ZhihuCommentItem | undefined = undefined;

  // 底部沉浸光感药丸栏：跟手 + 滚动停止吸附最近端点（对标回答页 Article.ets）
  @State private bottomBarOffsetY: number = 0;        // 0 完全显示；=bottomBarHideDistance 时滑出屏幕下沿
  private bottomBarHideDistance: number = 96;          // 隐藏位移：药丸高 + 底距 + 安全区
  private bottomBarSnapTimer: number = -1;             // 滚动停止防抖计时器
  private bottomBarTweenTimer: number = -1;            // 底栏逐帧动画计时器
  private lastScrollTop: number = 0;                   // 上一次滚动偏移，用于算 delta

  // 顶栏（XX的想法）：顶部可见，下滑隐藏、上滑显示（对标回答页 Article.ets）
  @State private topBarOffsetY: number = 0;            // 0 完全显示；=-topBarHeight 时滑出屏幕顶部
  @State private topBarHeight: number = 0;             // 顶栏实测高度，用于隐藏位移终点
  private wasAtTop: boolean = true;                    // atTop 翻转检测，用于回弹弹簧

  // 沉浸模式（对标 Article.ets）
  @State private immersiveMode: boolean = false;
  private cachedWindow: window.Window | undefined = undefined;

  // TTS 朗读（对标 Article.ets）
  private ttsController: TtsController = new TtsController();
  @State private ttsSpeaking: boolean = false;

  // 导出（对标 Article.ets）
  @State private showExportSheet: boolean = false;
  @State private exportCommentCount: number = 0;        // 0=关闭评论；1~10=包含评论条数
  @State private includeAppAttribution: boolean = true; // 导出底部开源说明开关（默认开）

  aboutToAppear(): void {
    const params = router.getParams() as PinPageParams;
    const id = typeof params.pinId === 'string' ? params.pinId : '';
    const fb = typeof params.fallbackUrl === 'string' ? params.fallbackUrl : '';
    this.pinId = id;
    this.anchorCommentId = typeof params.anchorCommentId === 'string' ? params.anchorCommentId : '';
    this.fallbackUrl = fb.length > 0 ? fb : `https://www.zhihu.com/pin/${id}`;
    this.loadPin();
    this.ensureRootComments(true);
    // 确保知乎贴纸数据就绪，用于表情选择器渲染原版贴纸图
    ZhihuEmojiService.initialize(this.context())
      .then(() => { this.emojiItems = ZhihuEmojiService.getEmojiPickerItems(); })
      .catch(() => {});
    // 通知评论定位：直接进入想法后直接展开评论面板，定位到指定评论
    if (this.anchorCommentId.length > 0) {
      this.showRootCommentSheet = true;
    }
  }

  onBackPress(): boolean {
    if (this.immersiveMode) {
      this.exitImmersive();
      return true;
    }
    if (this.showRootCommentSheet) {
      this.showRootCommentSheet = false;
      return true;
    }
    return false;
  }

  private currentTarget(): ZhihuCommentableTarget {
    return { kind: 'pin', id: this.pinId };
  }

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  private showToast(message: string): void {
    promptAction.showToast({ message, duration: 1800 });
  }

  // ---------- 三点菜单动作（对标 Article.ets）----------

  /** 在知乎 App / 浏览器中打开当前想法 */
  private openInZhihuApp(): void {
    this.tryOpenExternal(this.fallbackUrl);
  }

  /** 复制链接到剪贴板 */
  private copyCurrentLink(): void {
    if (this.fallbackUrl.length === 0) { return; }
    try {
      const pb = pasteboard.getSystemPasteboard();
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.fallbackUrl);
      pb.setData(pasteData);
      this.showToast('链接已复制');
    } catch (_) {
      this.showToast('复制失败');
    }
  }

  /** 系统分享（拉起系统分享面板） */
  private systemShare(): void {
    if (this.fallbackUrl.length === 0) { return; }
    try {
      const title = this.pin?.excerptTitle ?? '';
      const text = title.length > 0 ? `${title}\n${this.fallbackUrl}` : this.fallbackUrl;
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
        console.info('[Pin Share] 分享面板已打开');
      }).catch((err: Error) => {
        console.error('[Pin Share] 分享失败:', (err as Object)?.toString() ?? String(err));
      });
    } catch (e) {
      console.error('[Pin Share] 异常:', (e as Error)?.message ?? String(e));
      this.showToast('分享失败');
    }
  }

  /** 用系统能力打开外部链接（浏览器 / 知乎 App） */
  private tryOpenExternal(url: string): void {
    if (url.length === 0) { return; }
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

  /** 处理正文内链接点击（对标 Article.ets openBodyLink）：作者主页 / 问题 / 知乎内容 / 外链 */
  private openBodyLink(url: string, text: string): void {
    const normalized = url.trim();
    if (normalized.length === 0) {
      return;
    }
    // 作者头像 / 昵称 → 作者主页
    if (normalized.startsWith('zhihu://openPerson?urlToken=')) {
      const token = decodeURIComponent(normalized.replace('zhihu://openPerson?urlToken=', ''));
      if (token.length > 0) {
        router.pushUrl({ url: 'pages/People', params: { urlToken: token } });
      }
      return;
    }
    // 问题标题 → 问题页
    if (normalized.startsWith('zhihu://openQuestion?id=')) {
      const qId = decodeURIComponent(normalized.replace('zhihu://openQuestion?id=', ''));
      if (qId.length > 0) {
        router.pushUrl({ url: 'pages/Question', params: { questionId: qId, title: text } });
      }
      return;
    }
    // 知乎内容（回答 / 文章 / 想法）→ 对应详情页
    const zhihuTarget: ZhihuContentTarget | undefined = resolveZhihuContent(normalized);
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
    // 普通外链 → 内置浏览器
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

  // ===== 沉浸阅读模式（对标 Article.ets）=====

  private async ensureWindow(): Promise<window.Window | undefined> {
    if (this.cachedWindow !== undefined) { return this.cachedWindow; }
    try {
      this.cachedWindow = await window.getLastWindow(getContext(this) as common.UIAbilityContext);
    } catch (e) {
      console.error('[Pin Immersive] ensureWindow 失败:', (e as Error)?.message ?? String(e));
      this.cachedWindow = undefined;
    }
    return this.cachedWindow;
  }

  /** 进入沉浸：隐藏状态栏，保留底部导航栏 */
  private async enterImmersive(): Promise<void> {
    const win = await this.ensureWindow();
    if (win === undefined) { return; }
    try {
      win.setWindowLayoutFullScreen(true);
      win.setWindowSystemBarEnable(['navigation'] as Array<'status' | 'navigation'>);
      this.immersiveMode = true;
      this.showToast('已进入沉浸模式，侧滑返回退出');
    } catch (e) {
      console.error('[Pin Immersive] 进入失败:', (e as Error)?.message ?? String(e));
      this.showToast('进入沉浸失败');
    }
  }

  /** 退出沉浸：还原窗口基线 */
  private exitImmersive(): void {
    this.immersiveMode = false;
    const win = this.cachedWindow;
    if (win === undefined) { return; }
    try {
      win.setWindowLayoutFullScreen(true);
      win.setWindowSystemBarEnable(['status', 'navigation'] as Array<'status' | 'navigation'>);
    } catch (_) { /* ignore */ }
  }

  // ===== TTS 朗读（对标 Article.ets）=====
  private toggleTts(): void {
    if (this.pin === null) { return; }
    if (this.ttsSpeaking) {
      this.ttsController.stop();
      return;
    }
    this.ttsController.start(this.context(), this.pin.excerptTitle || '想法', this.pin.contentHtml, {
      onStateChange: (speaking: boolean) => {
        this.ttsSpeaking = speaking;
      },
      onError: (message: string) => {
        this.showToast(message);
        this.ttsSpeaking = false;
      }
    });
  }

  // ===== 导出想法（HTML / 带评论 / Markdown，对齐 Article.ets 导出） =====
  private buildExportMeta(): ArticleExportMeta {
    const p = this.pin!;
    return {
      title: p.excerptTitle || '想法',
      authorName: p.author.name || '匿名用户',
      authorBio: p.author.headline || '',
      authorAvatarSrc: p.author.avatarUrl || '',
      voteUpCount: p.likeCount,
      commentCount: p.commentCount,
      contentHtml: p.contentHtml,
      createdEpochSeconds: p.createdTime,
      updatedEpochSeconds: p.updatedTime,
      contentId: p.id,
      contentType: 'pin'
    };
  }

  private async doExport(type: 'html' | 'markdown'): Promise<void> {
    if (this.pin === null) { return; }
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
              this.currentTarget(),
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

  // ---------- 数据加载 ----------
  private async loadPin(): Promise<void> {
    if (this.pinId.length === 0) {
      this.error = '想法 ID 为空';
      return;
    }
    this.loading = true;
    this.error = '';
    try {
      this.pin = await PeopleService.loadPin(this.context(), this.pinId);
      this.liked = this.pin.liked;
      this.likeCount = this.pin.likeCount;
    } catch (e) {
      this.error = `想法加载失败：${errMsg(e)}`;
    } finally {
      this.loading = false;
    }
  }

  private async togglePinLike(): Promise<void> {
    if (this.pin === null || this.pinLiking) {
      return;
    }
    this.pinLiking = true;
    const wasLiked = this.liked;
    // 乐观更新
    this.liked = !wasLiked;
    this.likeCount = this.likeCount + (wasLiked ? -1 : 1);
    try {
      const res = await PeopleService.togglePinLike(this.context(), this.pinId, wasLiked);
      this.liked = res.liked;
      if (res.likeCount >= 0) {
        this.likeCount = res.likeCount;
      }
    } catch (e) {
      // 回滚
      this.liked = wasLiked;
      this.likeCount = this.likeCount + (wasLiked ? 1 : -1);
      this.showToast(`操作失败：${errMsg(e)}`);
    } finally {
      this.pinLiking = false;
    }
  }

  private async ensureRootComments(forceReload: boolean = false): Promise<void> {
    if (!forceReload && this.rootComments.length > 0) {
      return;
    }
    if (this.rootCommentLoading) {
      return;
    }
    this.rootCommentLoading = true;
    try {
      const page = await CommentService.loadRootComments(
        this.context(),
        this.currentTarget(),
        this.rootCommentSortOrder
      );
      this.rootComments = page.items;
      this.rootCommentNextUrl = page.nextUrl;
      this.rootCommentEnd = page.isEnd;
      this.rootCommentError = '';
      this.consumeAnchorComment();
    } catch (e) {
      this.rootCommentError = `评论加载失败：${errMsg(e)}`;
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
        this.currentTarget(),
        this.rootCommentSortOrder,
        this.rootCommentNextUrl
      );
      this.rootComments = mergeComments(this.rootComments, page.items);
      this.rootCommentNextUrl = page.nextUrl;
      this.rootCommentEnd = page.isEnd;
      this.rootCommentError = '';
    } catch (e) {
      this.rootCommentError = `评论继续加载失败：${errMsg(e)}`;
    } finally {
      this.rootCommentLoadingMore = false;
    }
  }

  private async submitRootComment(): Promise<void> {
    const text = this.rootCommentDraft.trim();
    if (text.length === 0 || this.rootSubmitting) {
      return;
    }
    this.rootSubmitting = true;
    try {
      const created = await CommentService.submitComment(this.context(), this.currentTarget(), text, this.rootReplyTo?.id);
      this.rootComments = [created, ...this.rootComments];
      this.rootCommentDraft = '';
      this.rootReplyTo = undefined;
      this.showRootEmojiPanel = false;
      if (this.pin !== null) {
        const p = this.pin;
        this.pin = {
          id: p.id,
          contentHtml: p.contentHtml,
          excerptTitle: p.excerptTitle,
          liked: p.liked,
          likeCount: p.likeCount,
          commentCount: p.commentCount + 1,
          createdTime: p.createdTime,
          updatedTime: p.updatedTime,
          author: p.author,
          topics: p.topics
        };
      }
      this.commentRenderVersion++;
      this.showToast('评论已发送');
    } catch (e) {
      this.showToast(`评论失败：${errMsg(e)}`);
    } finally {
      this.rootSubmitting = false;
    }
  }

  private async toggleCommentLike(commentId: string, liked: boolean, fromChildSheet: boolean = false): Promise<void> {
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
    } catch (e) {
      this.showToast(`操作失败：${errMsg(e)}`);
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
    } catch (e) {
      this.childCommentError = `回复加载失败：${errMsg(e)}`;
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
    } catch (e) {
      this.childCommentError = `回复继续加载失败：${errMsg(e)}`;
    } finally {
      this.childCommentLoadingMore = false;
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
    } catch (e) {
      this.showToast(`发送失败：${errMsg(e)}`);
    } finally {
      this.childSubmitting = false;
    }
  }

  private openChildComments(comment: ZhihuCommentItem, anchorChildComment?: ZhihuCommentItem): void {
    this.childTarget = {
      kind: 'comment',
      commentId: comment.id,
      article: this.currentTarget()
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

  private openPerson(urlToken: string): void {
    if (urlToken.length === 0) {
      return;
    }
    router.pushUrl({ url: 'pages/People', params: { urlToken } });
  }

  // ---------- 加载 / 错误 / 正文 三态 ----------
  // 作者卡片改为注入 WebView HTML（buildPinSummaryHtml），与正文同属一个 DOM 树，连成一块、
  // 随 WebView 内部滚动一起上滑消失；顶栏与底栏为 Stack 浮层，靠 onScrollChange 跟手显隐。

  @Builder
  private LoadingState(): void {
    Column({ space: 10 }) {
      Text('正在加载想法...')
        .fontSize(this.fontSubhead)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 60 })
  }

  @Builder
  private ErrorState(): void {
    Column({ space: 12 }) {
      Text(this.error.length > 0 ? this.error : '内容不存在')
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
          this.loadPin();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 60 })
  }

  // 想法正文：WebView 自己当滚动容器（fillHeight:true），作者卡片注入 HTML 与正文连成一块
  @Builder
  private PinWebView(): void {
    ZhihuRichWeb({
      html: buildArticleHtmlDocument(
        '',
        normalizeRichContentHtml(this.pin!.contentHtml),
        this.fallbackUrl,
        resolveZhihuThemeMode(this.context(), this.themeMode),
        undefined,
        this.topSafeAreaVp + (this.immersiveMode ? 0 : 64),
        16,
        0,
        buildPinSummaryHtml(this.pin!)
      ),
      sourceUrl: this.fallbackUrl,
      title: this.pin!.excerptTitle,
      themeMode: this.themeMode,
      fillHeight: true,
      onScrollChange: (topPx: number): void => {
        this.updateBarsOnScroll(topPx);
      },
      onLinkTap: (url: string, text: string): void => {
        this.openBodyLink(url, text);
      },
      onImageTap: (url: string): void => {
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
    })
    .layoutWeight(1)
  }

  // ---------- 底部沉浸光感操作栏（点赞 + 评论）—— 改为 Navigation.toolBar 的 builder，使用真·HDS systemMaterialEffect ----------
  @Builder
  private PinBottomBar(): void {
    Row({ space: 10 }) {
      // 左组：点赞药丸（对齐回答页 ActionBarTab，使用 hand_thumbsup_fill）
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.hand_thumbsup_fill'))
          .fontSize(this.fontHeading)
          .fontColor([this.liked ? '#FFFFFF' : $r('app.color.action_pill_icon')])
        Text(`${this.likeCount}`)
          .fontSize(this.fontSecondary)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.liked ? '#FFFFFF' : $r('app.color.action_pill_icon'))
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(this.liked ? $r('app.color.action_text') : ThemeColors.oledBlack(this.oledBlack, this.isDark, $r('app.color.action_pill_button_inactive')))
      .borderRadius(this.pillRadius)
      .onClick(() => {
        this.togglePinLike();
      })

      Blank()

      // 右组：评论药丸
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.message'))
          .fontSize(this.fontHeading)
          .fontColor([$r('app.color.action_pill_icon')])
        Text(`${this.pin?.commentCount ?? this.rootComments.length}`)
          .fontSize(this.fontSecondary)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.action_pill_icon'))
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(ThemeColors.oledBlack(this.oledBlack, this.isDark, $r('app.color.action_pill_button_inactive')))
      .borderRadius(this.pillRadius)
      .onClick(() => {
        this.showRootCommentSheet = true;
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 6, bottom: 6 })
  }

  // ===== 顶/底栏跟手显隐（对齐回答页 Article.ets updateBarsOnScroll）=====
  // 滚动事件来源改为 WebView 内部 onScrollChange（bridge），不再依赖外层 ArkUI Scroll
  private updateBarsOnScroll(topPx: number): void {
    const atTop = topPx <= 1;
    const delta = topPx - this.lastScrollTop;
    this.lastScrollTop = topPx;

    // 顶栏（XX的想法）：顶部可见，下滑隐藏，上滑显示；topBarHeight 未测得时给兜底，避免常驻
    const topTotal = this.topBarHeight > 0 ? this.topBarHeight : (this.topSafeAreaVp + 56);
    if (atTop) {
      if (!this.wasAtTop) {
        animateTo({ curve: curves.springMotion(), duration: 300 }, () => { this.topBarOffsetY = 0; });
      } else {
        this.topBarOffsetY = 0;
      }
    } else if (delta > 0) {
      this.topBarOffsetY = Math.max(-topTotal, this.topBarOffsetY - delta);
    } else {
      this.topBarOffsetY = Math.min(0, Math.max(-topTotal, this.topBarOffsetY - delta));
    }
    this.wasAtTop = atTop;

    // 底栏：纯 delta 跟手 + 滚动停止吸附最近端点（避免下滑途中误显）
    const barH = this.bottomBarHideDistance;
    if (Math.abs(delta) >= 1) {
      this.bottomBarOffsetY = Math.min(barH, Math.max(0, this.bottomBarOffsetY + delta));
      this.pinTabsController.setTabBarTranslate({ x: 0, y: this.bottomBarOffsetY });
      this.pinTabsController.setTabBarOpacity(Math.max(0, 1 - this.bottomBarOffsetY / barH));
      this.scheduleBottomBarSnap();
    }
  }

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
      this.pinTabsController.setTabBarTranslate({ x: 0, y: target });
      this.pinTabsController.setTabBarOpacity(target >= barH ? 0 : 1);
      this.bottomBarOffsetY = target;
      return;
    }
    const duration = 160;
    const startTime = Date.now();
    this.bottomBarTweenTimer = setInterval(() => {
      const t = Math.min(1, (Date.now() - startTime) / duration);
      const eased = 1 - Math.pow(1 - t, 3); // easeOutCubic
      this.bottomBarOffsetY = start + dist * eased;
      this.pinTabsController.setTabBarTranslate({ x: 0, y: this.bottomBarOffsetY });
      this.pinTabsController.setTabBarOpacity(Math.max(0, 1 - this.bottomBarOffsetY / barH));
      if (t >= 1) {
        clearInterval(this.bottomBarTweenTimer);
        this.bottomBarTweenTimer = -1;
      }
    }, 16);
  }

  /** 立即复位底栏到完全显示 */
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
    this.pinTabsController.setTabBarTranslate({ x: 0, y: 0 });
    this.pinTabsController.setTabBarOpacity(1);
  }

  private clearBottomBarSnap(): void {
    if (this.bottomBarSnapTimer >= 0) {
      clearTimeout(this.bottomBarSnapTimer);
      this.bottomBarSnapTimer = -1;
    }
  }

  // ---------- 评论 Sheet（bindSheet 弹出）----------
  @Builder
  private RootCommentSheet(): void {
    Column() {
      Column({ space: 12 }) {
        Text('评论')
          .fontSize(this.fontHeading)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(`${this.pin?.commentCount ?? this.rootComments.length} 条评论`)
          .fontSize(this.fontCaption)
          .fontColor($r('app.color.text_secondary'))

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
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
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
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
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
    if (this.sessionSnapshot.loggedIn) {
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
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
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
      .border({ width: 1, color: selected ? $r('app.color.action_background') : $r('app.color.card_border') })
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
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .borderRadius(this.cardRadius)
    .border({ width: 1, color: $r('app.color.card_border') })
    .enabled(enabled)
    .onClick(() => {
      onClick();
    })
    .margin({ top: 4, bottom: 8 })
    .alignSelf(ItemAlign.Center)
  }

  // 导出想法弹层（对标 Article.ets ExportSheet）
  @Builder
  private ExportSheet(): void {
    Column() {
      Text('导出想法')
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

          // 带评论导出
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
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
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
    .onClick(() => {
      if (!disabled) {
        action();
      }
    })
  }

  build() {
    HdsTabs({ controller: this.pinTabsController }) {
      TabContent() {
        Stack({ alignContent: Alignment.BottomStart }) {
      // 主内容：WebView 自己滚动（fillHeight:true），占满全屏；作者卡片已注入 HTML 与之连成一块
      Column() {
        if (this.loading && this.pin === null) {
          this.LoadingState();
        } else if (this.error.length > 0 && this.pin === null) {
          this.ErrorState();
        } else if (this.pin !== null) {
          this.PinWebView();
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeColors.articleBackground(this.oledBlack, this.isDark))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 顶栏浮层（沉浸模式隐藏；滚动时 translate 显隐）
      if (!this.immersiveMode) {
        ContentTopBar({
          title: this.pin !== null && this.pin.author.name.length > 0 ? `${this.pin.author.name}的想法` : '想法',
          contentProgress: 1,
          offsetY: this.topBarOffsetY,
          menuItems: [
            { value: '在知乎中打开', action: () => this.openInZhihuApp() },
            { value: '复制链接', action: () => this.copyCurrentLink() },
            { value: '分享', action: () => this.systemShare() },
            { value: '进入沉浸', action: () => this.enterImmersive() },
            { value: this.ttsSpeaking ? '停止朗读' : '开始朗读', action: () => this.toggleTts() },
            { value: '导出…', action: () => { this.showExportSheet = true; } }
          ],
          onBack: () => {
            router.back({ url: '' });
          },
          onHeightChange: (h: number) => {
            this.topBarHeight = h;
          }
        })
        .position({ x: 0, y: 0 })
        .zIndex(20)
      }

      // 底栏由 HdsTabs barFloatingStyle 承载（真·HDS 沉浸光感材质，见 build 外层包裹）

      Column()
        .width(1)
        .height(1)
        .bindSheet($$this.showRootCommentSheet, this.RootCommentSheet(), {
          showClose: false,
          dragBar: true,
          preferType: SheetType.BOTTOM,
          detents: [SheetSize.LARGE],
          backgroundColor: ThemeColors.cardBackground(this.oledBlack, this.isDark),
          onWillDismiss: (action: DismissSheetAction) => {
            if (this.showRootEmojiPanel || this.showChildEmojiPanel) {
              this.showRootEmojiPanel = false;
              this.showChildEmojiPanel = false;
            } else {
              action.dismiss();
            }
          },
          onDisappear: () => {
            this.showRootCommentSheet = false;
            this.rootReplyTo = undefined;
            this.showChildCommentSheet = false;
          }
        })

      Column()
        .width(1)
        .height(1)
        .bindSheet($$this.showExportSheet, this.ExportSheet(), {
          showClose: false,
          dragBar: true,
          preferType: SheetType.BOTTOM,
          detents: [SheetSize.LARGE],
          backgroundColor: ThemeColors.cardBackground(this.oledBlack, this.isDark),
          onDisappear: () => {
            this.showExportSheet = false;
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
          backgroundColor: ThemeColors.cardBackground(this.oledBlack, this.isDark),
          onWillDismiss: (action: DismissSheetAction) => {
            if (this.showRootEmojiPanel || this.showChildEmojiPanel) {
              this.showRootEmojiPanel = false;
              this.showChildEmojiPanel = false;
            } else {
              action.dismiss();
            }
          },
          onDisappear: () => {
            this.showChildCommentSheet = false;
            this.childReplyTo = undefined;
          }
        })
    }
    .width('100%')
    .height('100%')
      }
      .tabBar(this.PinBottomBar)
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
}
