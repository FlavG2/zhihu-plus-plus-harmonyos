import common from '@ohos.app.ability.common';
import { promptAction, router } from '@kit.ArkUI';
import { BlocklistRepository } from '../services/BlocklistRepository';
import { FeedFilterService } from '../services/FeedFilterService';
import { BlockHistoryRepository } from '../services/BlockHistoryRepository';
import { FilterSettingsRepository, FILTER_KEYS } from '../services/FilterSettingsRepository';
import { pasteboard } from '@kit.BasicServicesKit';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { serializeZhihuContentTarget, ZhihuCommentableTarget } from '../models/ZhihuContentModels';
import { DailyService, DailyStoriesPage, DailyStory } from '../services/DailyService';
import { DEFAULT_SESSION_SNAPSHOT, HomeFeedItem, HomeFeedTopic, SessionSnapshot } from '../models/ZhihuModels';
import { HomeFeedService } from '../services/HomeFeedService';
import { HotListService } from '../services/HotListService';
import { LocalDebugSessionService } from '../services/LocalDebugSessionService';
import { resolveZhihuContent, resolveZhihuTopic } from '../services/ZhihuContentResolver';
import { openZhihuContentTarget } from '../services/ZhihuNavigation';
import { ZhihuSessionRepository } from '../services/ZhihuSessionRepository';
import { AppearanceSettingsRepository, APPEARANCE_KEYS, AppearanceThemeMode, AmbientBlurIntensity,
  MATERIAL_LEVEL_EXQUISITE, MATERIAL_LEVEL_GENTLE, MATERIAL_LEVEL_SMOOTH, MATERIAL_LEVEL_ADAPTIVE } from '../services/AppearanceSettingsRepository';
import { ThemeColors } from '../services/ThemeColors';
import { FollowFeedService, FollowFeedTab } from '../services/FollowFeedService';
import { RecentMomentsService, FollowingUserItem } from '../services/RecentMomentsService';
import { FollowFilterRepository, FollowFilterCategory } from '../services/FollowFilterRepository';
import { PeopleService } from '../services/PeopleService';
import { formatRelativeTime } from '../services/TimeFormat';
import { BrowsingHistoryRepository } from '../services/BrowsingHistoryRepository';
import { CloudHistoryService } from '../services/CloudHistoryService';
import { SliderSettingRow } from './FilterSettingRows';

type AppPortalKey = 'home' | 'follow' | 'hot' | 'daily';

// 卡片三点菜单项（用于 bindMenu，字段与 MenuElement 兼容）
interface BlockMenuItem {
  value: string;
  action: () => void;
}


interface AppPortalOption {
  readonly key: AppPortalKey;
  readonly title: string;
}

interface DailySection {
  readonly date: string;
  readonly stories: DailyStory[];
}

interface ThemeModeOptionItem {
  readonly mode: AppearanceThemeMode;
  readonly label: string;
}

interface FollowFeedTabOption {
  readonly key: FollowFeedTab;
  readonly title: string;
}

const TOP_BAR_BASE_PADDING: number = 10;
const HOME_TOP_BAR_SCROLL_INSET: number = 94;
const DEFAULT_TOP_BAR_SCROLL_INSET: number = 96;
const FOLLOW_TOP_BAR_SCROLL_INSET: number = 150;
const BOTTOM_PORTAL_BAR_CONTENT_INSET: number = 84;
const BOTTOM_PORTAL_BAR_BASE_OFFSET: number = 8;
const THEME_MODE_OPTIONS: ThemeModeOptionItem[] = [
  { mode: 'light', label: '日间' },
  { mode: 'dark', label: '黑暗' },
  { mode: 'system', label: '跟随系统' }
];

interface AmbientBlurOptionItem {
  readonly intensity: AmbientBlurIntensity;
  readonly label: string;
}
const AMBIENT_BLUR_OPTIONS: AmbientBlurOptionItem[] = [
  { intensity: 'off', label: '关闭' },
  { intensity: 'adaptive', label: '自适应' },
  { intensity: 'standard', label: '标准' },
  { intensity: 'rich', label: '浓郁' }
];

interface MaterialLevelOptionItem {
  readonly level: number;
  readonly label: string;
}
const MATERIAL_LEVEL_OPTIONS: MaterialLevelOptionItem[] = [
  { level: MATERIAL_LEVEL_ADAPTIVE, label: '自适应' },
  { level: MATERIAL_LEVEL_SMOOTH, label: '平滑' },
  { level: MATERIAL_LEVEL_GENTLE, label: '柔和' },
  { level: MATERIAL_LEVEL_EXQUISITE, label: '精致' }
];

const APP_PORTAL_TABS: AppPortalOption[] = [
  { key: 'home', title: '主页' },
  { key: 'follow', title: '关注' },
  { key: 'hot', title: '热榜' },
  { key: 'daily', title: '日报' }
];
const FOLLOW_FEED_TABS: FollowFeedTabOption[] = [
  { key: 'latest', title: '最新' },
  { key: 'featured', title: '精选' }
];

interface ScanError {
  code?: number;
  message?: string;
}

@Entry
@Component
struct Index {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageProp('bottomSafeAreaVp') private bottomSafeAreaVp: number = 0;
  @StorageProp('sessionSnapshot') private sessionSnapshot: SessionSnapshot = DEFAULT_SESSION_SNAPSHOT;
  // 会话版本：切换/创建马甲号或登录/登出时由 ZhihuSessionRepository 自增，用于清空身份相关缓存（对齐安卓 reloadApplication）
  @StorageLink('sessionEpoch') @Watch('onSessionEpochChanged') private sessionEpoch: number = 0;
  @StorageProp('themeMode') private themeMode: AppearanceThemeMode = 'system';
  @StorageProp('ambientBlur') private ambientBlur: AmbientBlurIntensity = 'adaptive';
  @StorageProp('materialLevel') private materialLevel: number = MATERIAL_LEVEL_ADAPTIVE;
  @State private selectedPortalTab: AppPortalKey = 'home';
  @State private dailySections: DailySection[] = [];
  @State private dailyLoading: boolean = false;
  @State private dailyLoadingMore: boolean = false;
  // 主页底部沉浸光感栏：对齐安卓「跟手 + 滚动停止吸附最近端点」
  @State private homeBottomBarOffset: number = 0;   // 0=显示，=homeBottomBarHideDistance 隐藏（跟手）
  private homeBottomBarHideDistance: number = 96;
  private homeBarSnapTimer: number = -1;
  private homeBarTweenTimer: number = -1;
  // 顶栏下滑隐藏 / 上滑恢复（镜像底栏机制，方向反向）
  @State private topBarOffsetY: number = 0;          // 0=展开，=topBarHideDistance 完全折叠
  private topBarHideDistance: number = 120;
  private topBarSnapTimer: number = -1;
  private topBarTweenTimer: number = -1;
  // 四个 tab 各自的 Scroller（用于「再点当前 tab → 回顶」）
  private homeScroller: Scroller = new Scroller();
  private followScroller: Scroller = new Scroller();
  private hotScroller: Scroller = new Scroller();
  private dailyScroller: Scroller = new Scroller();
  // 按关键词屏蔽输入弹窗状态（用 bindSheet 代替 CustomDialog，本 SDK 不导出 CustomDialogController）
  @State showKeywordSheet: boolean = false;
  @State keywordInput: string = '';
  @State keywordInputError: string = '';
  // 按话题屏蔽弹层状态（两步式：先点菜单项，再勾选具体话题）
  @State showTopicSheet: boolean = false;
  @State topicSheetItem: HomeFeedItem | null = null;
  @State selectedTopicIds: string[] = [];
  // 话题 ID -> 名字（按需从内容详情 API 补全：点「按话题屏蔽」时调 fetchItemTopics 灌入）
  @State topicNameMap: Record<string, string> = {};
  // 按话题屏蔽弹层用的真实话题列表（从内容详情 API 拉取，带 name；不用 feed 的 bound_topic_ids）
  @State topicSheetTopics: Array<HomeFeedTopic> = [];
  @State private dailyError: string = '';
  @State private nextDailyDate: string = '';
  @State private homeItems: HomeFeedItem[] = [];
  @State private homeLoading: boolean = false;
  @State private homeLoadingMore: boolean = false;
  @State private homeError: string = '';
  @State private homeNextUrl: string = '';
  @State private homeHasLoaded: boolean = false;
  @State private tabRefreshing: boolean = false;
  @State private showRecommendBadge: boolean = true;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;
  @StorageLink('showThumbnail') private showThumbnail: boolean = true;
  @StorageLink('showRefreshFab') private showRefreshFab: boolean = false;
  @State private followTab: FollowFeedTab = 'latest';
  @State private followRecommendItems: HomeFeedItem[] = [];
  @State private followRecommendLoading: boolean = false;
  @State private followRecommendLoadingMore: boolean = false;
  @State private followRecommendError: string = '';
  @State private followRecommendNextUrl: string = '';
  @State private followRecommendHasLoaded: boolean = false;
  @State private followDynamicItems: HomeFeedItem[] = [];
  @State private followDynamicLoading: boolean = false;
  @State private followDynamicLoadingMore: boolean = false;
  @State private followDynamicError: string = '';
  @State private followDynamicNextUrl: string = '';
  @State private followDynamicHasLoaded: boolean = false;
  // 关注的人横排（仅「最新」tab，对齐安卓 FollowingUsersRow）
  @State private followRecentUsers: FollowingUserItem[] = [];
  @State private followRecentLoading: boolean = false;
  @State private followRecentError: string = '';
  // 点击关注的人 → 底部弹层直接看其发布内容（不进主页）
  @State private showUserContentSheet: boolean = false;
  @State private userContentItems: HomeFeedItem[] = [];
  @State private userContentName: string = '';
  @State private userContentUrlToken: string = '';
  @State private userContentAvatar: string = '';
  @State private userContentLoading: boolean = false;
  // 关注流类型筛选（默认显示全部；持久化于 FollowFilterRepository）
  @State private followFilterVoteup: boolean = true;
  @State private followFilterPin: boolean = true;
  @State private followFilterArticle: boolean = true;
  @State private followFilterAnswer: boolean = true;
  // 「屏蔽未关注作者」开关（默认关 = 显示全部）
  @State private followHideUnfollowed: boolean = false;
  @State private showFollowFilterSheet: boolean = false;
  @State private hotItems: HomeFeedItem[] = [];
  @State private hotLoading: boolean = false;
  @State private hotLoadingMore: boolean = false;
  @State private hotError: string = '';
  @State private hotNextUrl: string = '';
  @State private hotHasLoaded: boolean = false;
  @State private historyItems: HomeFeedItem[] = [];
  @State private mergedHistoryItems: HomeFeedItem[] = [];
  @State private cloudHistoryItems: HomeFeedItem[] = [];
  @State private cloudHistoryLoading: boolean = false;
  @State private cloudHistoryLoadingMore: boolean = false;
  @State private cloudHistoryNextUrl: string = '';
  @State private cloudHistoryIsEnd: boolean = false;
  @State private cloudHistoryError: string = '';
  @State private showHomeAccountPanel: boolean = false;
  private hdsTabsController: HdsTabsController = new HdsTabsController();

  // 深链跳转：EntryAbility 捕获 want.uri 后写入，本页消费并 popup 导航（对齐安卓 navigate(popup)）。
  @StorageLink('pendingDeepLink') @Watch('onPendingDeepLinkChanged') private pendingDeepLink: string = '';

  aboutToAppear(): void {
    AppearanceSettingsRepository.load(this.context());
    ZhihuSessionRepository.load(this.context());
    this.loadHistoryItems();
    this.applyLocalDebugSession();
    this.showRecommendBadge = FilterSettingsRepository.getBool(this.context(), FILTER_KEYS.showRecommendBadge, true);
    this.showThumbnail = AppearanceSettingsRepository.getShowThumbnail(this.context());
    this.showRefreshFab = AppearanceSettingsRepository.getShowRefreshFab(this.context());
    this.loadFollowFilter();
    this.loadLatestDaily();
  }

  onPageShow(): void {
    if (this.selectedPortalTab === 'home' && !this.homeHasLoaded) {
      this.loadHomeFirstPage();
    }
    if (this.selectedPortalTab === 'follow' && this.sessionSnapshot.loggedIn && !this.followHasLoaded()) {
      this.loadFollowFirstPage(this.followTab);
    }
    if (this.selectedPortalTab === 'hot' && !this.hotHasLoaded) {
      this.loadHotFirstPage();
    }
    // 冷启动深链：EntryAbility 已在 onCreate 写入 pendingDeepLink，此处消费并 popup 导航。
    this.consumePendingDeepLink();
  }

  // @Watch 回调：会话版本自增（切换/创建马甲号、登录、登出）后清空身份相关内存缓存，
  // 回到首页时 onPageShow 会因 hasLoaded=false 自动重载，避免新旧账号串号（对齐安卓 reloadApplication 整页重启）。
  private onSessionEpochChanged(): void {
    if (this.sessionEpoch <= 0) {
      return;
    }
    this.homeItems = [];
    this.homeError = '';
    this.homeNextUrl = '';
    this.homeHasLoaded = false;
    this.followRecommendItems = [];
    this.followRecommendError = '';
    this.followRecommendNextUrl = '';
    this.followRecommendHasLoaded = false;
    this.followDynamicItems = [];
    this.followDynamicError = '';
    this.followDynamicNextUrl = '';
    this.followDynamicHasLoaded = false;
    this.dailySections = [];
    this.dailyLoading = false;
    this.dailyLoadingMore = false;
    // 同步清空磁盘上的首页快照，避免关闭「自动刷新」时旧账号缓存被回显（串号）
    HomeFeedService.clearHomeSnapshot(this.context());
  }

  // @Watch 回调：热启动(onNewWant)写入 pendingDeepLink 时消费。
  onPendingDeepLinkChanged(): void {
    this.consumePendingDeepLink();
  }

  private consumePendingDeepLink(): void {
    const link = this.pendingDeepLink;
    if (!link || link.length === 0) {
      return;
    }
    const topicId = resolveZhihuTopic(link);
    this.pendingDeepLink = ''; // 先清空，避免 pushUrl 重入/二次跳转
    if (topicId !== undefined) {
      router.pushUrl({ url: 'pages/Topic', params: { topicId } });
      return;
    }
    const target = resolveZhihuContent(link);
    if (target !== undefined) {
      openZhihuContentTarget(target);
    }
  }

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  private async applyLocalDebugSession(): Promise<void> {
    try {
      const applied = await LocalDebugSessionService.applyIfPresent(this.context());
      if (applied && this.selectedPortalTab === 'home' && !this.homeHasLoaded) {
        this.loadHomeFirstPage();
      }
    } catch (_) {
    }
  }

  private portalTitle(tab: AppPortalKey): string {
    if (tab === 'home') {
      return '知乎首页';
    }
    if (tab === 'follow') {
      return '关注';
    }
    if (tab === 'hot') {
      return '知乎热榜';
    }
    if (tab === 'daily') {
      return '知乎日报';
    }
    const selected = APP_PORTAL_TABS.find((item: AppPortalOption) => item.key === tab);
    if (selected !== undefined) {
      return selected.title;
    }
    return '知乎日报';
  }

  private topBarSubtitle(): string {
    if (this.selectedPortalTab === 'home') {
      if (!this.sessionSnapshot.loggedIn) {
        return '登录后查看真实推荐流';
      }
      if (this.homeLoading && !this.homeHasLoaded) {
        return '正在同步知乎推荐流';
      }
      return this.sessionSnapshot.accountName;
    }
    if (this.selectedPortalTab === 'follow') {
      if (!this.sessionSnapshot.loggedIn) {
        return '登录后查看关注流';
      }
      return this.followTab === 'featured' ? '关注精选' : '关注最新';
    }
    if (this.selectedPortalTab === 'hot') {
      if (this.hotLoading && !this.hotHasLoaded) {
        return '正在同步知乎热榜';
      }
      return this.hotItems.length > 0 ? `${this.hotItems.length} 条热门内容` : '全站热门内容';
    }
    if (this.dailySections.length > 0) {
      return this.dateLabel(this.dailySections[0].date);
    }
    return '正在同步知乎日报';
  }

  private portalPlaceholder(tab: AppPortalKey): string {
    if (tab === 'home') {
      return '主页推荐流待加载';
    }
    if (tab === 'follow') {
      return '关注流待加载';
    }
    if (tab === 'hot') {
      return '热榜待加载';
    }
    return '暂无最近浏览';
  }

  private dateLabel(date: string): string {
    if (date.length === 8) {
      return `${date.slice(4, 6)} 月 ${date.slice(6, 8)} 日`;
    }
    return date;
  }

  private openLoginPage(): void {
    router.pushUrl({
      url: 'pages/Login'
    });
  }

  private openWebContent(title: string, url: string, recordHistory: boolean = false): void {
    if (url.length === 0) {
      return;
    }
    if (recordHistory) {
      this.historyItems = BrowsingHistoryRepository.recordWeb(this.context(), title, url);
    }
    router.pushUrl({
      url: 'pages/WebContent',
      params: { title, url }
    });
  }

  private openNativeArticle(
    target: ZhihuCommentableTarget,
    fallbackTitle: string,
    fallbackUrl: string,
    recordHistory: boolean = true
  ): void {
    if (recordHistory) {
      this.historyItems = BrowsingHistoryRepository.recordContent(this.context(), target, fallbackTitle, fallbackUrl);
      // 上报云端历史（异步，不阻塞）
      CloudHistoryService.reportViaTarget(this.context(), target);
    }
    if (target.kind === 'question') {
      router.pushUrl({
        url: 'pages/Question',
        params: {
          questionId: target.id,
          title: (target.title ?? '').length > 0 ? target.title : fallbackTitle
        }
      });
      return;
    }
    if (target.kind === 'pin') {
      router.pushUrl({
        url: 'pages/Pin',
        params: {
          pinId: target.id,
          fallbackUrl
        }
      });
      return;
    }
    router.pushUrl({
      url: 'pages/Article',
      params: {
        target: serializeZhihuContentTarget(target),
        fallbackTitle,
        fallbackUrl
      }
    });
  }

  private openDailyStory(item: DailyStory): void {
    const nativeTarget = resolveZhihuContent(item.url);
    if (nativeTarget !== undefined) {
      this.openNativeArticle(nativeTarget, item.title, item.url);
      return;
    }
    this.openWebContent(item.title, item.url, true);
  }

  private openHomeFeedItem(item: HomeFeedItem): void {
    if (item.type === 'zvideo' && item.videoId !== undefined) {
      this.openVideo(item.videoId, item.contentId ?? item.videoId, item.contentType ?? 'video', item.title);
      return;
    }
    if (item.nativeTarget !== undefined) {
      this.openNativeArticle(item.nativeTarget, item.title, item.targetUrl);
      return;
    }
    const resolved = resolveZhihuContent(item.targetUrl);
    if (resolved !== undefined) {
      this.openNativeArticle(resolved, item.title, item.targetUrl);
      return;
    }
    this.openWebContent(item.title, item.targetUrl, true);
  }

  private openVideo(videoId: string, contentId: string, contentType: string, title: string): void {
    if (videoId.length === 0) {
      return;
    }
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

  private openSearchPage(): void {
    router.pushUrl({
      url: 'pages/Search'
    });
  }

  private openZhihuLink(url: string): void {
    const nativeTarget = resolveZhihuContent(url);
    if (nativeTarget !== undefined) {
      this.openNativeArticle(nativeTarget, '', url, true);
      return;
    }
    this.openWebContent('知乎链接', url, false);
  }

  private openSelfPage(): void {
    const data = ZhihuSessionRepository.load(this.context());
    const urlToken = data.self?.urlToken ?? '';
    if (urlToken.length === 0) {
      return;
    }
    this.showHomeAccountPanel = false;
    this.openWebContent(data.self?.name ?? '我的主页', `https://www.zhihu.com/people/${urlToken}`);
  }

  private refreshHomeFromPanel(): void {
    this.showHomeAccountPanel = false;
    this.homeItems = [];
    this.homeError = '';
    this.homeNextUrl = '';
    this.homeHasLoaded = false;
    this.loadHomeFirstPage();
  }

  private openProjectRepository(): void {
    this.showHomeAccountPanel = false;
    this.openWebContent('知乎++ 项目地址', 'https://github.com/zly2006/zhihu-plus-plus');
  }

  private openIdentityManagement(): void {
    this.showHomeAccountPanel = false;
    router.pushUrl({ url: 'pages/IdentityManagement' });
  }

  private openAppearanceSettings(): void {
    router.pushUrl({ url: 'pages/AppearanceSettings' });
  }

  private themeModeDescription(): string {
    if (this.themeMode === 'light') {
      return '当前为日间模式';
    }
    if (this.themeMode === 'dark') {
      return '当前为黑暗模式';
    }
    return '当前跟随系统模式';
  }

  private setThemeMode(mode: AppearanceThemeMode): void {
    AppearanceSettingsRepository.setThemeMode(this.context(), mode);
  }

  private setAmbientBlur(intensity: AmbientBlurIntensity): void {
    AppearanceSettingsRepository.setAmbientBlur(this.context(), intensity);
  }

  private setMaterialLevel(level: number): void {
    AppearanceSettingsRepository.setMaterialLevel(this.context(), level);
  }

  // 将沉浸光感强度映射到底栏 backgroundBlurStyle 的值
  private ambientBlurStyle(): BlurStyle {
    if (this.ambientBlur === 'rich') {
      return BlurStyle.Thick;
    }
    if (this.ambientBlur === 'standard') {
      return BlurStyle.Regular;
    }
    if (this.ambientBlur === 'off') {
      // 关闭档：用 BACKGROUND_THIN（视觉接近无模糊，低于常规 Thin）
      return BlurStyle.BACKGROUND_THIN;
    }
    // 'adaptive' 与默认：常规 Thin
    return BlurStyle.Thin;
  }

  private showPendingSettingToast(message: string): void {
    promptAction.showToast({
      message,
      duration: 1800
    });
  }

  // 从账号面板进入"浏览历史"：关闭面板并跳转到独立的历史页面
  private showHistoryFromPanel(): void {
    this.showHomeAccountPanel = false;
    router.pushUrl({ url: 'pages/History' }).catch(() => {});
  }

  private showHistoryItemMenu(item: HomeFeedItem): void {
    const menuItems: promptAction.ActionMenuOptions = {
      title: '',
      buttons: [
        { text: '复制链接', color: '#007AFF' },
        { text: '删除', color: '#FF3B30' }
      ]
    };
    promptAction.showActionMenu(menuItems).then((data: promptAction.ActionMenuSuccessResponse) => {
      if (data.index === 0) {
        this.copyToClipboard(item.targetUrl);
      } else if (data.index === 1) {
        this.removeHistoryItem(item);
      }
    }).catch(() => {
      // 用户取消或出错，静默
    });
  }

  private copyToClipboard(text: string): void {
    if (text.length === 0) {
      promptAction.showToast({ message: '暂无链接' });
      return;
    }
    try {
      const pb = pasteboard.getSystemPasteboard();
      const data = pasteboard.createData({ text });
      pb.setData(data);
      promptAction.showToast({ message: '已复制链接' });
    } catch (_) {
      promptAction.showToast({ message: text });
    }
  }

  private removeHistoryItem(item: HomeFeedItem): void {
    this.historyItems = BrowsingHistoryRepository.removeItem(this.context(), item.id);
    this.rebuildMergedList();
  }

  private portalKeyFromIndex(index: number): AppPortalKey {
    if (index >= 0 && index < APP_PORTAL_TABS.length) {
      return APP_PORTAL_TABS[index].key;
    }
    return APP_PORTAL_TABS[0].key;
  }

  private portalIndexFromKey(key: AppPortalKey): number {
    const idx = APP_PORTAL_TABS.findIndex((item: AppPortalOption) => item.key === key);
    return idx >= 0 ? idx : 0;
  }

  private resolveMaterialLevel(level: number): hdsMaterial.MaterialLevel {
    if (level === MATERIAL_LEVEL_EXQUISITE) {
      return hdsMaterial.MaterialLevel.EXQUISITE;
    }
    if (level === MATERIAL_LEVEL_GENTLE) {
      return hdsMaterial.MaterialLevel.GENTLE;
    }
    if (level === MATERIAL_LEVEL_SMOOTH) {
      return hdsMaterial.MaterialLevel.SMOOTH;
    }
    return hdsMaterial.MaterialLevel.ADAPTIVE;
  }

  private onTabChange(index: number): void {
    this.selectedPortalTab = this.portalKeyFromIndex(index);
    this.hdsTabsController.changeIndex(index);
    // 切换 Tab 时恢复底部沉浸光感栏（始终从底部重新出现）
    this.resetHomeBottomBar();
    this.showHomeAccountPanel = false;
    if (this.selectedPortalTab === 'home') {
      if (this.homeFeedGuestMode() || this.sessionSnapshot.loggedIn) {
        if (!this.homeHasLoaded) {
          this.loadHomeFirstPage();
        }
      } else {
        this.openLoginPage();
      }
    } else if (this.selectedPortalTab === 'follow') {
      if (!this.sessionSnapshot.loggedIn) {
        this.openLoginPage();
      } else if (!this.followHasLoaded()) {
        this.loadFollowFirstPage(this.followTab);
      }
    } else if (this.selectedPortalTab === 'hot' && !this.hotHasLoaded) {
      this.loadHotFirstPage();
    } else if (this.selectedPortalTab === 'daily' && this.dailySections.length === 0) {
      this.loadLatestDaily();
    }
  }

  @Builder
  private FloatingTab(label: string): void {
    Text(label)
      .fontSize(14)
      .fontWeight(this.selectedPortalTab === this.labelToTabKey(label) ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.selectedPortalTab === this.labelToTabKey(label) ? $r('app.color.tab_selected_text') : $r('app.color.text_secondary'))
  }

  private labelToTabKey(label: string): AppPortalKey {
    const found = APP_PORTAL_TABS.find((item: AppPortalOption) => item.title === label);
    return found !== undefined ? found.key : 'home';
  }

  private logout(): void {
    ZhihuSessionRepository.clear(this.context());
    this.showHomeAccountPanel = false;
    this.homeItems = [];
    this.homeError = '';
    this.homeNextUrl = '';
    this.homeHasLoaded = false;
    this.followRecommendItems = [];
    this.followRecommendError = '';
    this.followRecommendNextUrl = '';
    this.followRecommendHasLoaded = false;
    this.followDynamicItems = [];
    this.followDynamicError = '';
    this.followDynamicNextUrl = '';
    this.followDynamicHasLoaded = false;
    HomeFeedService.clearHomeSnapshot(this.context());
  }

  private loadHistoryItems(): void {
    this.historyItems = BrowsingHistoryRepository.load(this.context());
    this.rebuildMergedList();
  }

  private rebuildMergedList(): void {
    const seen = new Set<string>();
    const merged: HomeFeedItem[] = [];

    // 1. 先加入本地历史
    for (const item of this.historyItems) {
      const key = item.nativeTarget?.id ?? item.id;
      if (!seen.has(key)) {
        seen.add(key);
        merged.push(item);
      }
    }

    // 2. 追加云端历史（去重，云端条目在后但更高优先级）
    for (const item of this.cloudHistoryItems) {
      const key = item.nativeTarget?.id ?? item.id;
      if (!seen.has(key)) {
        seen.add(key);
        merged.push(item);
      }
    }

    this.mergedHistoryItems = merged;
  }

  private clearHistoryItems(): void {
    this.historyItems = BrowsingHistoryRepository.clear(this.context());
    this.cloudHistoryItems = [];
    this.cloudHistoryNextUrl = '';
    this.cloudHistoryIsEnd = true;
    this.cloudHistoryError = '';
    this.rebuildMergedList();
    // 尝试清除云端历史（静默）
    CloudHistoryService.clearHistory(this.context());
  }

  private async loadCloudHistory(): Promise<void> {
    if (this.cloudHistoryLoading) {
      return;
    }
    this.cloudHistoryLoading = true;
    this.cloudHistoryError = '';
    this.cloudHistoryNextUrl = '';
    this.cloudHistoryIsEnd = false;
    try {
      const page = await CloudHistoryService.fetchHistory(this.context());
      this.cloudHistoryItems = CloudHistoryService.mapToHomeFeedItems(page.data);
      this.cloudHistoryNextUrl = page.paging.next ?? '';
      this.cloudHistoryIsEnd = page.paging.isEnd;
      this.cloudHistoryError = '';
    } catch (error) {
      const message = error instanceof Error ? error.message : '加载失败';
      this.cloudHistoryError = message;
      this.cloudHistoryItems = [];
    } finally {
      this.cloudHistoryLoading = false;
      this.rebuildMergedList();
    }
  }

  private async loadMoreCloudHistory(): Promise<void> {
    if (this.cloudHistoryLoadingMore || this.cloudHistoryIsEnd || this.cloudHistoryNextUrl.length === 0) {
      return;
    }
    this.cloudHistoryLoadingMore = true;
    try {
      const page = await CloudHistoryService.fetchNextPage(this.context(), this.cloudHistoryNextUrl);
      const newItems = CloudHistoryService.mapToHomeFeedItems(page.data);
      this.cloudHistoryItems = [...this.cloudHistoryItems, ...newItems];
      this.cloudHistoryNextUrl = page.paging.next ?? '';
      this.cloudHistoryIsEnd = page.paging.isEnd;
    } catch (_) {
      // 静默
    } finally {
      this.cloudHistoryLoadingMore = false;
      this.rebuildMergedList();
    }
  }

  private async clearCloudHistoryItems(): Promise<void> {
    if (this.cloudHistoryLoading) {
      return;
    }
    this.cloudHistoryLoading = true;
    try {
      await CloudHistoryService.clearHistory(this.context());
      this.cloudHistoryItems = [];
      this.cloudHistoryNextUrl = '';
      this.cloudHistoryIsEnd = true;
      this.cloudHistoryError = '';
    } catch (_) {
      this.cloudHistoryError = '清除失败';
    } finally {
      this.cloudHistoryLoading = false;
    }
  }

  private followItems(): HomeFeedItem[] {
    const base = this.followTab === 'featured' ? this.followRecommendItems : this.followDynamicItems;
    return base.filter((item: HomeFeedItem) => this.passFollowFilter(item) && this.passHideUnfollowed(item));
  }

  // 关注流类型筛选（对齐安卓：赞同了 XX / 想法 / 文章 / 回答 四类开关）
  private passFollowFilter(item: HomeFeedItem): boolean {
    if (item.type === 'pin') {
      return this.followFilterPin;
    }
    if (item.type === 'article') {
      return this.followFilterArticle;
    }
    if (item.type === 'answer') {
      return this.followFilterAnswer;
    }
    if (this.isVoteupItem(item)) {
      return this.followFilterVoteup;
    }
    return true;
  }

  private isVoteupItem(item: HomeFeedItem): boolean {
    const verb = item.verb ?? '';
    if (verb.toUpperCase().includes('VOTEUP')) {
      return true;
    }
    return (item.actionText ?? '').includes('赞同');
  }

  // 「屏蔽未关注作者」：开关打开且明确判定为未关注（authorFollowing===false）时隐藏；状态未知则保留
  private passHideUnfollowed(item: HomeFeedItem): boolean {
    if (!this.followHideUnfollowed) {
      return true;
    }
    return item.authorFollowing !== false;
  }

  private loadFollowFilter(): void {
    const stored = FollowFilterRepository.load(this.context());
    this.followFilterVoteup = stored.voteup;
    this.followFilterPin = stored.pin;
    this.followFilterArticle = stored.article;
    this.followFilterAnswer = stored.answer;
    this.followHideUnfollowed = FollowFilterRepository.getHideUnfollowed(this.context());
  }

  private followLoading(): boolean {
    return this.followTab === 'featured' ? this.followRecommendLoading : this.followDynamicLoading;
  }

  private followLoadingMore(): boolean {
    return this.followTab === 'featured' ? this.followRecommendLoadingMore : this.followDynamicLoadingMore;
  }

  private followError(): string {
    return this.followTab === 'featured' ? this.followRecommendError : this.followDynamicError;
  }

  private followNextUrl(): string {
    return this.followTab === 'featured' ? this.followRecommendNextUrl : this.followDynamicNextUrl;
  }

  private followHasLoaded(tab?: FollowFeedTab): boolean {
    const selectedTab = tab ?? this.followTab;
    return selectedTab === 'featured' ? this.followRecommendHasLoaded : this.followDynamicHasLoaded;
  }

  // 推荐内容时登录 关闭 → 游客模式（不携带登录凭证）；开启但未登录 → 触发登录
  private homeFeedGuestMode(): boolean {
    return !FilterSettingsRepository.getBool(this.context(), FILTER_KEYS.recommendLogin, true);
  }

  private async loadHomeFirstPage(): Promise<void> {
    if (this.homeLoading) {
      return;
    }
    const ctx = this.context();
    const guest = this.homeFeedGuestMode();
    const autoRefresh = FilterSettingsRepository.getBool(ctx, FILTER_KEYS.autoRefresh, true);

    // 需要登录才能推荐且当前未登录 → 拉起登录页
    if (!guest && !this.sessionSnapshot.loggedIn) {
      this.openLoginPage();
      return;
    }

    // 关闭自动刷新：优先展示上次缓存（立即、无转圈），不联网；手动下拉才拉新
    if (!autoRefresh) {
      const cached = HomeFeedService.loadHomeSnapshot(ctx);
      if (cached.length > 0 && !this.homeHasLoaded) {
        this.homeItems = FeedFilterService.filterHomeFeed(ctx, cached);
        this.homeHasLoaded = true;
        this.homeError = '';
        return;
      }
    }

    await this.fetchHomeFirstPage(guest);
  }

  private async fetchHomeFirstPage(guest: boolean): Promise<void> {
    this.homeLoading = true;
    this.homeError = '';
    try {
      const ctx = this.context();
      const page = await HomeFeedService.loadFirstPage(ctx, { guest });
      FeedFilterService.recordRecommendCounts(ctx, page.items);
      this.homeItems = FeedFilterService.filterHomeFeed(ctx, page.items);
      this.homeNextUrl = page.paging.nextUrl;
      this.homeHasLoaded = true;
      HomeFeedService.saveHomeSnapshot(ctx, page.items);
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.homeError = `主页加载失败：${message}`;
    } finally {
      this.homeLoading = false;
    }
  }

  private async refreshHomePage(): Promise<void> {
    this.homeItems = [];
    this.homeError = '';
    this.homeNextUrl = '';
    this.homeHasLoaded = false;
    await this.fetchHomeFirstPage(this.homeFeedGuestMode());
  }

  private async loadMoreHome(): Promise<void> {
    if (this.homeLoadingMore || this.homeNextUrl.length === 0) {
      return;
    }
    this.homeLoadingMore = true;
    try {
      const page = await HomeFeedService.loadNextPage(this.context(), this.homeNextUrl);
      FeedFilterService.recordRecommendCounts(this.context(), page.items);
      const newItems = FeedFilterService.filterHomeFeed(this.context(), page.items);
      const existed = new Set<string>(this.homeItems.map((item: HomeFeedItem) => item.id));
      const merged = [...this.homeItems];
      newItems.forEach((item: HomeFeedItem) => {
        if (!existed.has(item.id)) {
          merged.push(item);
        }
      });
      this.homeItems = merged;
      this.homeNextUrl = page.paging.nextUrl;
      this.homeError = '';
      this.homeHasLoaded = true;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.homeError = `主页继续加载失败：${message}`;
    } finally {
      this.homeLoadingMore = false;
    }
  }

  private async loadHotFirstPage(): Promise<void> {
    if (this.hotLoading) {
      return;
    }
    this.hotLoading = true;
    this.hotError = '';
    try {
      const page = await HotListService.loadFirstPage(this.context());
      this.hotItems = page.items;
      this.hotNextUrl = page.paging.nextUrl;
      this.hotHasLoaded = true;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.hotError = `热榜加载失败：${message}`;
    } finally {
      this.hotLoading = false;
    }
  }

  private async refreshHotPage(): Promise<void> {
    this.hotHasLoaded = false;
    this.hotItems = [];
    this.hotNextUrl = '';
    await this.loadHotFirstPage();
  }

  private async refreshFollowPage(): Promise<void> {
    if (this.followTab === 'featured') {
      this.followRecommendItems = [];
      this.followRecommendNextUrl = '';
      this.followRecommendHasLoaded = false;
      this.followRecommendError = '';
      await this.loadFollowFirstPage('featured');
    } else {
      this.followDynamicItems = [];
      this.followDynamicNextUrl = '';
      this.followDynamicHasLoaded = false;
      this.followDynamicError = '';
      await this.loadFollowFirstPage('latest');
    }
  }

  private async refreshDailyPage(): Promise<void> {
    this.dailySections = [];
    this.nextDailyDate = '';
    this.dailyError = '';
    await this.loadLatestDaily();
  }

  // 统一刷新入口：根据当前 tab 调度对应的刷新方法
  private async refreshCurrentTab(): Promise<void> {
    try {
      if (this.selectedPortalTab === 'home') {
        await this.refreshHomePage();
      } else if (this.selectedPortalTab === 'hot') {
        await this.refreshHotPage();
      } else if (this.selectedPortalTab === 'follow') {
        await this.refreshFollowPage();
      } else if (this.selectedPortalTab === 'daily') {
        await this.refreshDailyPage();
      }
      // history 是本地缓存，不刷网络
    } catch (_) {
      // 刷新失败不阻断
    } finally {
      this.tabRefreshing = false;
    }
  }

  private async loadMoreHot(): Promise<void> {
    if (this.hotLoadingMore || this.hotNextUrl.length === 0) {
      return;
    }
    this.hotLoadingMore = true;
    try {
      const page = await HotListService.loadNextPage(this.context(), this.hotNextUrl);
      const existed = new Set<string>(this.hotItems.map((item: HomeFeedItem) => item.id));
      const merged = [...this.hotItems];
      page.items.forEach((item: HomeFeedItem) => {
        if (!existed.has(item.id)) {
          existed.add(item.id);
          merged.push(item);
        }
      });
      this.hotItems = merged;
      this.hotNextUrl = page.paging.nextUrl;
      this.hotError = '';
      this.hotHasLoaded = true;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.hotError = `热榜继续加载失败：${message}`;
    } finally {
      this.hotLoadingMore = false;
    }
  }

  private async loadLatestDaily(): Promise<void> {
    if (this.dailyLoading) {
      return;
    }

    this.dailyLoading = true;
    this.dailyError = '';
    try {
      const page: DailyStoriesPage = await DailyService.loadLatest();
      this.dailySections = [page];
      this.nextDailyDate = page.date;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.dailyError = `日报加载失败：${message}`;
    } finally {
      this.dailyLoading = false;
    }
  }

  private async loadMoreDaily(): Promise<void> {
    if (this.dailyLoadingMore || this.nextDailyDate.length === 0) {
      return;
    }

    this.dailyLoadingMore = true;
    try {
      const page: DailyStoriesPage = await DailyService.loadBefore(this.nextDailyDate);
      this.dailySections = [...this.dailySections, page];
      this.nextDailyDate = page.date;
      this.dailyError = '';
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.dailyError = `日报继续加载失败：${message}`;
    } finally {
      this.dailyLoadingMore = false;
    }
  }

  private handleContentScrollEdge(side: Edge): void {
    if (side !== Edge.Bottom) {
      return;
    }
    if (this.selectedPortalTab === 'home' && this.homeHasLoaded && this.homeNextUrl.length > 0) {
      this.loadMoreHome();
      return;
    }
    if (this.selectedPortalTab === 'follow' && this.followHasLoaded() && this.followNextUrl().length > 0) {
      this.loadMoreFollow();
      return;
    }
    if (this.selectedPortalTab === 'hot' && this.hotHasLoaded && this.hotNextUrl.length > 0) {
      this.loadMoreHot();
      return;
    }
    if (this.selectedPortalTab === 'daily' && this.dailySections.length > 0 && this.nextDailyDate.length > 0) {
      this.loadMoreDaily();
    }
  }

  // 主页底部沉浸光感栏：对齐安卓「跟手 + 滚动停止吸附最近端点」
  // 跟手：offset 随滚动增量钳制在 [0, hideDistance]（无迟滞，上滑必然减小→必然重现），配合 opacity 淡出
  private updateHomeBottomBarOnScroll(dy: number): void {
    if (Math.abs(dy) < 1) {
      return;
    }
    const barH = this.homeBottomBarHideDistance;
    this.homeBottomBarOffset = Math.min(barH, Math.max(0, this.homeBottomBarOffset + dy));
    this.hdsTabsController.setTabBarTranslate({ x: 0, y: this.homeBottomBarOffset });
    this.hdsTabsController.setTabBarOpacity(Math.max(0, 1 - this.homeBottomBarOffset / barH));
    this.scheduleHomeBarSnap();
  }

  private scheduleHomeBarSnap(): void {
    if (this.homeBarSnapTimer >= 0) {
      clearTimeout(this.homeBarSnapTimer);
    }
    this.homeBarSnapTimer = setTimeout(() => {
      this.snapHomeBottomBar();
      this.homeBarSnapTimer = -1;
    }, 120);
  }

  private snapHomeBottomBar(): void {
    const barH = this.homeBottomBarHideDistance;
    const target = this.homeBottomBarOffset > barH / 2 ? barH : 0;
    this.animateHomeBarTo(target);
  }

  private animateHomeBarTo(target: number): void {
    if (this.homeBarTweenTimer >= 0) {
      clearInterval(this.homeBarTweenTimer);
      this.homeBarTweenTimer = -1;
    }
    const start = this.homeBottomBarOffset;
    const dist = target - start;
    if (Math.abs(dist) < 1) {
      this.hdsTabsController.setTabBarTranslate({ x: 0, y: target });
      this.hdsTabsController.setTabBarOpacity(target >= this.homeBottomBarHideDistance ? 0 : 1);
      this.homeBottomBarOffset = target;
      return;
    }
    const duration = 160;
    const startTime = Date.now();
    this.homeBarTweenTimer = setInterval(() => {
      const t = Math.min(1, (Date.now() - startTime) / duration);
      const eased = 1 - Math.pow(1 - t, 3); // easeOutCubic
      this.homeBottomBarOffset = start + dist * eased;
      this.hdsTabsController.setTabBarTranslate({ x: 0, y: this.homeBottomBarOffset });
      this.hdsTabsController.setTabBarOpacity(Math.max(0, 1 - this.homeBottomBarOffset / this.homeBottomBarHideDistance));
      if (t >= 1) {
        clearInterval(this.homeBarTweenTimer);
        this.homeBarTweenTimer = -1;
      }
    }, 16);
  }

  /** 切 Tab / 回顶时复位底栏为完全显示 */
  private resetHomeBottomBar(): void {
    if (this.homeBarSnapTimer >= 0) {
      clearTimeout(this.homeBarSnapTimer);
      this.homeBarSnapTimer = -1;
    }
    if (this.homeBarTweenTimer >= 0) {
      clearInterval(this.homeBarTweenTimer);
      this.homeBarTweenTimer = -1;
    }
    this.homeBottomBarOffset = 0;
    this.hdsTabsController.setTabBarTranslate({ x: 0, y: 0 });
    this.hdsTabsController.setTabBarOpacity(1);
  }

  // ── 顶栏下滑隐藏 / 上滑恢复（镜像底栏，方向反向：dy>0 下滑→折叠） ──
  private updateTopBarOnScroll(dy: number): void {
    if (Math.abs(dy) < 1) {
      return;
    }
    const barH = this.topBarHideDistance;
    // dy > 0 = 手指/内容向下滑 → 顶栏向上收起（offset 增大）
    // dy < 0 = 手指/内容向上滑 → 顶栏向下展开（offset 减小）
    this.topBarOffsetY = Math.min(barH, Math.max(0, this.topBarOffsetY + dy));
    this.scheduleTopBarSnap();
  }

  private scheduleTopBarSnap(): void {
    if (this.topBarSnapTimer >= 0) {
      clearTimeout(this.topBarSnapTimer);
    }
    this.topBarSnapTimer = setTimeout(() => {
      this.snapTopBar();
      this.topBarSnapTimer = -1;
    }, 120);
  }

  private snapTopBar(): void {
    const barH = this.topBarHideDistance;
    const target = this.topBarOffsetY > barH / 2 ? barH : 0;
    this.animateTopBarTo(target);
  }

  private animateTopBarTo(target: number): void {
    if (this.topBarTweenTimer >= 0) {
      clearInterval(this.topBarTweenTimer);
      this.topBarTweenTimer = -1;
    }
    const start = this.topBarOffsetY;
    const dist = target - start;
    if (Math.abs(dist) < 1) {
      this.topBarOffsetY = target;
      return;
    }
    const duration = 180;
    const startTime = Date.now();
    this.topBarTweenTimer = setInterval(() => {
      const t = Math.min(1, (Date.now() - startTime) / duration);
      const eased = 1 - Math.pow(1 - t, 3); // easeOutCubic
      this.topBarOffsetY = start + dist * eased;
      if (t >= 1) {
        clearInterval(this.topBarTweenTimer);
        this.topBarTweenTimer = -1;
      }
    }, 16);
  }

  /** 切 Tab / 回顶时复位顶栏为完全展开 */
  private resetTopBar(): void {
    if (this.topBarSnapTimer >= 0) {
      clearTimeout(this.topBarSnapTimer);
      this.topBarSnapTimer = -1;
    }
    if (this.topBarTweenTimer >= 0) {
      clearInterval(this.topBarTweenTimer);
      this.topBarTweenTimer = -1;
    }
    this.topBarOffsetY = 0;
  }

  private topBarScrollInset(): number {
    const baseInset: number = (() => {
      if (this.selectedPortalTab === 'home') {
        return this.topSafeAreaVp + HOME_TOP_BAR_SCROLL_INSET;
      }
      if (this.selectedPortalTab === 'follow' && this.sessionSnapshot.loggedIn) {
        return this.topSafeAreaVp + FOLLOW_TOP_BAR_SCROLL_INSET;
      }
      return this.topSafeAreaVp + DEFAULT_TOP_BAR_SCROLL_INSET;
    })();
    // 顶栏折叠时同步收缩占位，内容填满空出区域
    return Math.max(this.topSafeAreaVp, baseInset - this.topBarOffsetY);
  }

  @Builder
  private TopBar(): void {
    if (this.selectedPortalTab === 'home') {
      Stack() {
        Stack() {
          Row() {
            Column()
              .width(196)
              .height(48)
              .borderRadius(24)
              .backgroundColor('#01FFFFFF')

            Blank()
              .layoutWeight(1)

            Column()
              .width(48)
              .height(48)
              .borderRadius(24)
              .backgroundColor('#01FFFFFF')
          }
          .width('100%')
          .padding({ left: 4, right: 4, top: 3, bottom: 3 })

          Row({ space: 12 }) {
            Row({ space: 10 }) {
              Image($r('app.media.ic_search'))
                .width(17)
                .height(17)
                .fillColor($r('app.color.text_secondary'))
                .renderMode(ImageRenderMode.Template)
            }
            .layoutWeight(1)
            .height(46)
            .padding({ left: 14, right: 14 })
            .backgroundColor('#66FFFFFF')
            .backgroundBlurStyle(BlurStyle.Thick)
            .border({
              width: 1,
              color: '#4DFFFFFF'
            })
            .borderRadius(27)
            .shadow({ radius: 18, color: '#1A2E6B9A', offsetX: 0, offsetY: 8 })
            .onClick(() => {
              this.openSearchPage();
            })

            Stack({ alignContent: Alignment.TopEnd }) {
              if (this.sessionSnapshot.avatarUrl.length > 0) {
                Image(this.sessionSnapshot.avatarUrl)
                  .width(36)
                  .height(36)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(18)
                  .clip(true)
              } else {
                Column() {
                  Text(this.sessionSnapshot.loggedIn ? this.sessionSnapshot.accountName.slice(0, 1) : '我')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.action_text'))
                }
                .width(36)
                .height(36)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .backgroundColor($r('app.color.action_background'))
                .borderRadius(18)
              }

              if (this.sessionSnapshot.loggedIn) {
                Column()
                  .width(8)
                  .height(8)
                  .backgroundColor('#FF5A5F')
                  .borderRadius(4)
                  .margin({ top: 1, right: 1 })
              }
            }
            .width(46)
            .height(46)
            .padding(5)
            .backgroundColor('#73FFFFFF')
            .backgroundBlurStyle(BlurStyle.Thick)
            .border({
              width: 1,
              color: '#52FFFFFF'
            })
            .borderRadius(23)
            .shadow({ radius: 18, color: '#1A2E6B9A', offsetX: 0, offsetY: 8 })
            .onClick(() => {
              this.showHomeAccountPanel = true;
            })
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      }
      .backgroundColor($r('app.color.glass_top_bar_background'))
      .border({
        width: {
          bottom: 1
        },
        color: $r('app.color.glass_top_bar_border')
      })
      .backdropBlur(36)
      .padding({ left: 16, right: 16, top: TOP_BAR_BASE_PADDING + this.topSafeAreaVp, bottom: 6 })
      .width('100%')
      .translate({ y: -this.topBarOffsetY })
      .opacity(this.topBarOffsetY > 0 ? Math.max(0, 1 - this.topBarOffsetY / this.topBarHideDistance) : 1)
    } else {
      Stack() {
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(this.portalTitle(this.selectedPortalTab))
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))

              Text(this.topBarSubtitle())
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            if (this.selectedPortalTab === 'follow' && this.sessionSnapshot.loggedIn) {
              this.FollowFilterButton()
            }
          }
          .width('100%')

          if (this.selectedPortalTab === 'follow' && this.sessionSnapshot.loggedIn) {
            Row({ space: 8 }) {
              ForEach(FOLLOW_FEED_TABS, (option: FollowFeedTabOption) => {
                this.FollowTabChip(option);
              }, (option: FollowFeedTabOption) => option.key)
            }
            .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      }
      .backgroundColor($r('app.color.glass_top_bar_background'))
      .border({
        width: {
          bottom: 1
        },
        color: $r('app.color.glass_top_bar_border')
      })
      .backdropBlur(32)
      .padding({ left: 16, right: 16, top: TOP_BAR_BASE_PADDING + this.topSafeAreaVp, bottom: 10 })
      .width('100%')
      .translate({ y: -this.topBarOffsetY })
      .opacity(this.topBarOffsetY > 0 ? Math.max(0, 1 - this.topBarOffsetY / this.topBarHideDistance) : 1)
    }
  }

  // 账号区右上角的小圆形图标按钮（二维码、退出登录）
  @Builder
  private AccountIconButton(icon: string, accessibilityLabel: string, action: () => void, color?: ResourceColor): void {
    Column() {
      Text(icon)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(color ?? $r('app.color.action_text'))
    }
    .width(40)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.action_background'))
    .borderRadius(20)
    .accessibilityText(accessibilityLabel)
    .onClick(() => {
      action();
    })
  }

  // 四宫格快捷入口按钮（收藏夹/关注订阅/通知/浏览历史）
  @Builder
  private QuickGridButton(label: string, action: () => void): void {
    Column({ space: 10 }) {
      // 圆形实心图标（接近安卓风格：浅蓝底 + 蓝色图标）
      Column() {
        Text(this.quickIconForLabel(label))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1976D2')
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('#E3F2FD')
      .borderRadius(20)

      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
    }
    .layoutWeight(1)
    .height(96)
    .padding({ top: 14, bottom: 12 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .borderRadius(16)
    .border({
      width: 1,
      color: $r('app.color.card_border')
    })
    .onClick(() => {
      action();
    })
  }

  private quickIconForLabel(label: string): string {
    if (label === '收藏夹') {
      return '★';
    }
    if (label === '关注订阅') {
      return '◉';
    }
    if (label === '通知') {
      return '♪';
    }
    if (label === '浏览历史') {
      return '↻';
    }
    return '•';
  }

  // 设置项左侧的圆形小图标（外观/推荐过滤/系统与更新）
  @Builder
  private SettingIcon(icon: string): void {
    Column() {
      Text(icon)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
    }
    .width(36)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(18)
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .border({
      width: 1,
      color: $r('app.color.card_border')
    })
  }

  @Builder
  private HomeAccountSheet(): void {
    Scroll() {
      Column({ space: 20 }) {
        // 标题文字已移除（用户要求）

        Column({ space: 14 }) {
          // 顶部个人信息行：左侧 头像+用户信息；右侧 二维码/退出登录 图标按钮
          Row({ space: 12 }) {
            if (this.sessionSnapshot.avatarUrl.length > 0) {
              Image(this.sessionSnapshot.avatarUrl)
                .width(54)
                .height(54)
                .objectFit(ImageFit.Cover)
                .borderRadius(27)
                .clip(true)
                .onClick(() => {
                  router.pushUrl({ url: 'pages/People' });
                })
            } else {
              Column() {
                Text(this.sessionSnapshot.loggedIn ? this.sessionSnapshot.accountName.slice(0, 1) : '我')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.action_text'))
              }
              .width(54)
              .height(54)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .backgroundColor($r('app.color.action_background'))
              .borderRadius(27)
              .onClick(() => {
                // 未登录点击头像 → 登录页；已登录 → 个人主页
                if (this.sessionSnapshot.loggedIn) {
                  router.pushUrl({ url: 'pages/People' });
                } else {
                  this.openLoginPage();
                }
              })
            }

            Column({ space: 4 }) {
              Text(this.sessionSnapshot.accountName)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))

              Text(this.sessionSnapshot.loggedIn ? `已保存 ${this.sessionSnapshot.cookieCount} 个登录 Cookie` : '尚未登录知乎账号')
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            // 右侧图标按钮：二维码（扫码登录）+ 退出登录
            Row({ space: 8 }) {
              this.AccountIconButton('⌗', '二维码', () => {
                if (this.sessionSnapshot.loggedIn) {
                  promptAction.showToast({ message: '请退出账号后使用二维码登录' });
                  return;
                }
                router.pushUrl({ url: 'pages/QrLogin' });
              })
              if (this.sessionSnapshot.loggedIn) {
                this.AccountIconButton('⎋', '退出登录', () => {
                  this.logout();
                }, $r('app.color.error_text'))
              }
            }
          }
          .width('100%')

          // 头像点击进入个人主页（见上方头像 onClick）
        }
        .width('100%')
        .padding(16)
        .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .borderRadius(24)
        .border({
          width: 1,
          color: $r('app.color.card_border')
        })

        // 四宫格快捷入口：收藏夹 / 关注订阅 / 通知 / 浏览历史
        Row({ space: 8 }) {
          this.QuickGridButton('收藏夹', () => {
            if (!this.sessionSnapshot.loggedIn) {
              this.showPendingSettingToast('请先登录后再查看收藏夹');
              return;
            }
            router.pushUrl({
              url: 'pages/CollectionList'
            });
          })
          this.QuickGridButton('关注订阅', () => {
            if (!this.sessionSnapshot.loggedIn) {
              this.showPendingSettingToast('请先登录后再查看关注订阅');
              return;
            }
            router.pushUrl({
              url: 'pages/People',
              params: { jumpTo: '关注订阅' }
            });
          })
          this.QuickGridButton('通知', () => {
            router.pushUrl({ url: 'pages/Notification' });
          })
          this.QuickGridButton('浏览历史', () => {
            this.showHistoryFromPanel();
          })
        }
        .width('100%')

        Column({ space: 12 }) {
          Text('快捷入口')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 4 })

          Column({ space: 2 }) {
            if (this.sessionSnapshot.loggedIn) {
              Row({ space: 12 }) {
                this.SettingIcon('👥')
                Column({ space: 4 }) {
                  Text('身份管理')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))

                  Text('管理主账号与马甲号，切换登录身份')
                    .fontSize(12)
                    .lineHeight(18)
                    .fontColor($r('app.color.text_secondary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text('打开')
                  .fontSize(12)
                  .fontColor($r('app.color.action_text'))
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 16, bottom: 16 })
              .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
              .border({
                width: 1,
                color: $r('app.color.card_border')
              })
              .borderRadius(20)
              .onClick(() => {
                this.openIdentityManagement();
              })
            }

            Row({ space: 12 }) {
              this.SettingIcon('◆')
              Column({ space: 4 }) {
                Text('外观与阅读体验')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))

                Text('主题与阅读体验入口（已支持黑暗模式）')
                  .fontSize(12)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text('打开')
                .fontSize(12)
                .fontColor($r('app.color.action_text'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
            .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({
              width: 1,
              color: $r('app.color.card_border')
            })
            .borderRadius(20)
            .onClick(() => {
              this.openAppearanceSettings();
            })

            Row({ space: 12 }) {
              this.SettingIcon('▼')
              Column({ space: 4 }) {
                Text('推荐系统与内容过滤')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))

                Text('推荐算法与内容过滤设置')
                  .fontSize(12)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text('打开')
                .fontSize(12)
                .fontColor($r('app.color.action_text'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
            .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({
              width: 1,
              color: $r('app.color.card_border')
            })
            .borderRadius(20)
            .onClick(() => {
              router.pushUrl({ url: 'pages/FilterSettings' });
            })

            Row({ space: 12 }) {
              this.SettingIcon('⚙')
              Column({ space: 4 }) {
                Text('系统与更新')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))

                Text('项目地址、更新策略与关于信息')
                  .fontSize(12)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text('打开')
                .fontSize(12)
                .fontColor($r('app.color.action_text'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
            .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({
              width: 1,
              color: $r('app.color.card_border')
            })
            .borderRadius(20)
            .onClick(() => {
              router.pushUrl({ url: 'pages/About' });
            })

          }
          .width('100%')
          .padding(6)
          .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
          .border({
            width: 1,
            color: $r('app.color.card_border')
          })
          .borderRadius(24)
        }
        .width('100%')

    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 8 })
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
  }

  private async loadFollowFirstPage(tab: FollowFeedTab): Promise<void> {
    if (!this.sessionSnapshot.loggedIn) {
      return;
    }
    if (tab === 'latest') {
      this.loadFollowRecentUsers();
    }
    if (tab === 'featured') {
      if (this.followRecommendLoading) {
        return;
      }
      this.followRecommendLoading = true;
      this.followRecommendError = '';
      try {
        const page = await FollowFeedService.loadFirstPage(this.context(), tab);
        this.followRecommendItems = page.items;
        this.followRecommendNextUrl = page.paging.nextUrl;
        this.followRecommendHasLoaded = true;
      } catch (error) {
        const message = error instanceof Error ? error.message : '未知错误';
        this.followRecommendError = `关注精选加载失败：${message}`;
      } finally {
        this.followRecommendLoading = false;
      }
      return;
    }

    if (this.followDynamicLoading) {
      return;
    }
    this.followDynamicLoading = true;
    this.followDynamicError = '';
    try {
      const page = await FollowFeedService.loadFirstPage(this.context(), tab);
      this.followDynamicItems = page.items;
      this.followDynamicNextUrl = page.paging.nextUrl;
      this.followDynamicHasLoaded = true;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.followDynamicError = `关注最新加载失败：${message}`;
    } finally {
      this.followDynamicLoading = false;
    }
  }

  private async loadFollowRecentUsers(): Promise<void> {
    if (this.followRecentLoading || this.followRecentUsers.length > 0) {
      return;
    }
    this.followRecentLoading = true;
    this.followRecentError = '';
    try {
      const users = await RecentMomentsService.loadFollowingUsers(this.context());
      this.followRecentUsers = users;
    } catch (error) {
      this.followRecentError = error instanceof Error ? error.message : '加载关注的人失败';
    } finally {
      this.followRecentLoading = false;
    }
  }

  private openPerson(urlToken: string): void {
    if (urlToken.length === 0) {
      return;
    }
    router.pushUrl({ url: 'pages/People', params: { urlToken } });
  }

  // 点击关注的人 → 底部弹层直接看其动态（回答 + 文章 + 想法），不进个人主页
  private async openUserContent(u: FollowingUserItem): Promise<void> {
    if (u.id.length === 0) {
      return;
    }
    this.userContentName = u.name;
    this.userContentUrlToken = u.urlToken;
    this.userContentAvatar = u.avatarUrl;
    this.userContentItems = [];
    this.userContentLoading = true;
    this.showUserContentSheet = true;
    try {
      const page = await PeopleService.loadActivities(this.context(), u.id);
      this.userContentItems = page.items;
    } catch (error) {
      promptAction.showToast({ message: error instanceof Error ? error.message : '加载内容失败' });
    } finally {
      this.userContentLoading = false;
    }
  }

  private async loadMoreFollow(): Promise<void> {
    const nextUrl = this.followNextUrl();
    if (this.followLoadingMore() || nextUrl.length === 0) {
      return;
    }

    if (this.followTab === 'featured') {
      this.followRecommendLoadingMore = true;
      try {
        const page = await FollowFeedService.loadNextPage(this.context(), nextUrl);
        const existed = new Set<string>(this.followRecommendItems.map((item: HomeFeedItem) => item.id));
        const merged = [...this.followRecommendItems];
        page.items.forEach((item: HomeFeedItem) => {
          if (!existed.has(item.id)) {
            merged.push(item);
          }
        });
        this.followRecommendItems = merged;
        this.followRecommendNextUrl = page.paging.nextUrl;
        this.followRecommendError = '';
        this.followRecommendHasLoaded = true;
      } catch (error) {
        const message = error instanceof Error ? error.message : '未知错误';
        this.followRecommendError = `关注精选继续加载失败：${message}`;
      } finally {
        this.followRecommendLoadingMore = false;
      }
      return;
    }

    this.followDynamicLoadingMore = true;
    try {
      const page = await FollowFeedService.loadNextPage(this.context(), nextUrl);
      const existed = new Set<string>(this.followDynamicItems.map((item: HomeFeedItem) => item.id));
      const merged = [...this.followDynamicItems];
      page.items.forEach((item: HomeFeedItem) => {
        if (!existed.has(item.id)) {
          merged.push(item);
        }
      });
      this.followDynamicItems = merged;
      this.followDynamicNextUrl = page.paging.nextUrl;
      this.followDynamicError = '';
      this.followDynamicHasLoaded = true;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.followDynamicError = `关注最新继续加载失败：${message}`;
    } finally {
      this.followDynamicLoadingMore = false;
    }
  }

  @Builder
  private ThemeModeOption(mode: AppearanceThemeMode, label: string): void {
    Text(label)
      .fontSize(12)
      .fontWeight(this.themeMode === mode ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.themeMode === mode ? $r('app.color.action_text') : $r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor(this.themeMode === mode ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .border({
        width: 1,
        color: this.themeMode === mode ? $r('app.color.tab_selected_border') : $r('app.color.card_border')
      })
      .borderRadius(14)
      .onClick(() => {
        this.setThemeMode(mode);
      })
  }

  @Builder
  private AmbientBlurOption(intensity: AmbientBlurIntensity, label: string): void {
    Text(label)
      .fontSize(12)
      .fontWeight(this.ambientBlur === intensity ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.ambientBlur === intensity ? $r('app.color.action_text') : $r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor(this.ambientBlur === intensity ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .border({
        width: 1,
        color: this.ambientBlur === intensity ? $r('app.color.tab_selected_border') : $r('app.color.card_border')
      })
      .borderRadius(14)
      .onClick(() => {
        this.setAmbientBlur(intensity);
      })
  }

  @Builder
  private MaterialLevelOption(level: number, label: string): void {
    Text(label)
      .fontSize(12)
      .fontWeight(this.materialLevel === level ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.materialLevel === level ? $r('app.color.action_text') : $r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor(this.materialLevel === level ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .border({
        width: 1,
        color: this.materialLevel === level ? $r('app.color.tab_selected_border') : $r('app.color.card_border')
      })
      .borderRadius(14)
      .onClick(() => {
        this.setMaterialLevel(level);
      })
  }

  @Builder
  private AppearanceSettingsSheet(): void {
    Scroll() {
      Column({ space: 18 }) {
        Column({ space: 6 }) {
          Text('外观与阅读体验')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Text('调整主题显示模式')
            .fontSize(13)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Column({ space: 2 }) {
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text('显示模式')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Row({ space: 6 }) {
              ForEach(THEME_MODE_OPTIONS, (option: ThemeModeOptionItem) => {
                this.ThemeModeOption(option.mode, option.label);
              }, (option: ThemeModeOptionItem) => option.mode)
            }
          }
.width('100%')
          .alignItems(VerticalAlign.Top)
          .padding({ left: 16, right: 16, top: 16, bottom: 16 })
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({
            width: 1,
            color: $r('app.color.card_border')
          })
          .borderRadius(20)
      }
      .width('100%')
      .padding(6)
      .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
      .border({
        width: 1,
        color: $r('app.color.card_border')
      })
      .borderRadius(24)

      // HDS 沉浸光感材质强度
      Column({ space: 2 }) {
        Column() {
          // 标题 + 副标题占满整行（不再和芯片挤在一起）
          Column({ space: 4 }) {
            Text('沉浸光感')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))

            Text('控制沉浸光感材质的渲染强度')
              .fontSize(12)
              .lineHeight(18)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // 芯片另起一行
          Row({ space: 6 }) {
            ForEach(MATERIAL_LEVEL_OPTIONS, (option: MaterialLevelOptionItem) => {
              this.MaterialLevelOption(option.level, option.label);
            }, (option: MaterialLevelOptionItem) => option.level.toString())
          }
          .margin({ top: 12 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .border({
          width: 1,
          color: $r('app.color.card_border')
        })
        .borderRadius(20)
      }
      .width('100%')
      .padding(6)
      .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
      .border({
        width: 1,
        color: $r('app.color.card_border')
      })
      .borderRadius(24)

        // 信息流与显示开关
        Column({ space: 2 }) {
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text('OLED 纯黑')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('卡片与背景使用纯黑 #000000，OLED 屏幕更省电、对比更强')
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.oledBlack })
              .selectedColor($r('app.color.action_text'))
              .onChange((v: boolean) => {
                this.oledBlack = v;
                AppearanceSettingsRepository.setOledBlack(getContext(this) as common.Context, v);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })

          Divider()
            .color($r('app.color.card_border'))
            .padding({ left: 16, right: 16 })

          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text('显示 Feed 缩略图')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.showThumbnail })
              .selectedColor($r('app.color.action_text'))
              .onChange((v: boolean) => {
                this.showThumbnail = v;
                AppearanceSettingsRepository.setShowThumbnail(getContext(this) as common.Context, v);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })

          Divider()
            .color($r('app.color.card_border'))
            .padding({ left: 16, right: 16 })

          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text('刷新悬浮按钮')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('在首页右下角显示悬浮刷新按钮')
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.showRefreshFab })
              .selectedColor($r('app.color.action_text'))
              .onChange((v: boolean) => {
                this.showRefreshFab = v;
                AppearanceSettingsRepository.setShowRefreshFab(getContext(this) as common.Context, v);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        }
        .width('100%')
        .padding(6)
        .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .border({
          width: 1,
          color: $r('app.color.card_border')
        })
        .borderRadius(24)

        // 阅读体验（字号 / 行高 / 段间距）
        Column({ space: 2 }) {
          SliderSettingRow({
            title: '正文字号',
            desc: '调整文章正文字号大小',
            prefKey: APPEARANCE_KEYS.readerFontScale,
            defValue: 100,
            minValue: 80,
            maxValue: 150,
            step: 1,
            divisor: 1,
            decimals: 0,
            suffix: '%',
            showDivider: true
          })
          SliderSettingRow({
            title: '行高',
            desc: '调整正文行与行之间的间距',
            prefKey: APPEARANCE_KEYS.readerLineHeight,
            defValue: 160,
            minValue: 120,
            maxValue: 200,
            step: 1,
            divisor: 100,
            decimals: 2,
            suffix: '',
            showDivider: true
          })
          SliderSettingRow({
            title: '段间距',
            desc: '调整正文段落之间的间距',
            prefKey: APPEARANCE_KEYS.readerParaSpacing,
            defValue: 100,
            minValue: 50,
            maxValue: 200,
            step: 1,
            divisor: 1,
            decimals: 0,
            suffix: '%',
            showDivider: false
          })
        }
        .width('100%')
        .padding(6)
        .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .border({
          width: 1,
          color: $r('app.color.card_border')
        })
        .borderRadius(24)

        Column()
          .height(this.bottomSafeAreaVp + 12)
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 12, bottom: 8 })
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
  }

  @Builder
  private DailySectionHeader(section: DailySection): void {
    Row() {
      Column()
        .layoutWeight(1)
        .height(1)
        .backgroundColor($r('app.color.card_border'))

      Text(this.dateLabel(section.date))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.action_text'))
        .margin({ left: 16, right: 16 })

      Column()
        .layoutWeight(1)
        .height(1)
        .backgroundColor($r('app.color.card_border'))
    }
    .alignItems(VerticalAlign.Center)
    .padding({ left: 20, right: 20, top: 8, bottom: 10 })
  }

  @Builder
  private DailyStoryCard(item: DailyStory): void {
    Row({ space: 12 }) {
      if (item.image !== undefined && item.image.length > 0) {
        Image(item.image)
          .width(104)
          .height(92)
          .objectFit(ImageFit.Cover)
          .borderRadius(8)
      }

      Column({ space: 12 }) {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .lineHeight(22)
          .fontColor($r('app.color.text_primary'))
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 6 }) {
          Column()
            .width(6)
            .height(6)
            .backgroundColor($r('app.color.text_secondary'))
            .borderRadius(3)

          Text(item.hint)
            .fontSize(12)
            .lineHeight(16)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.SpaceBetween)
      .layoutWeight(1)
      .constraintSize({
        minHeight: item.image !== undefined && item.image.length > 0 ? 92 : 100
      })
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding(12)
    .margin({ left: 16, right: 16, bottom: 12 })
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .border({
      width: 1,
      color: $r('app.color.card_border')
    })
    .borderRadius(12)
    .clip(true)
    .shadow({
      radius: 8,
      color: '#10000000',
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => {
      this.openDailyStory(item);
    })
  }

  @Builder
  private HomeFeedCard(item: HomeFeedItem, showBlockMenu: boolean = false): void {
    Column({ space: 12 }) {
      // 0. 动作行（蓝色 actionText + 相对时间，对齐安卓动态流）
      if (item.actionText.length > 0) {
        Row() {
          Text(item.actionText)
            .fontSize(13)
            .fontColor(this.themeMode === 'dark' ? '#6FA8FF' : '#175199')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (item.createdTime !== undefined && item.createdTime > 0) {
            Text(formatRelativeTime(item.createdTime))
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
              .flexShrink(1)
              .margin({ left: 12 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      // 1. 问题标题（置顶、加粗）+ 推荐次数角标（自适应宽圆角矩形描边，标题末尾，首次即显示，99+ 封顶）
      Row({ space: 6 }) {
        Text(item.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .lineHeight(26)
          .fontColor($r('app.color.text_primary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.showRecommendBadge && item.recommendCount !== undefined && item.recommendCount >= 1) {
          Text(item.recommendCount > 99 ? '99+' : `${item.recommendCount}`)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themeMode === 'dark' ? '#6FA8FF' : '#175199')
            .border({ width: 1, color: this.themeMode === 'dark' ? '#6FA8FF' : '#175199' })
            .borderRadius(11)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 2. 正文 / 回答摘要（中间，缩略图贴在右侧）
      Row({ space: 12 }) {
        Column({ space: 8 }) {
          if (item.summary.length > 0) {
            Text(item.summary)
              .fontSize(13)
              .lineHeight(20)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.showThumbnail && item.thumbnailUrl.length > 0) {
          Image(item.thumbnailUrl)
            .width(104)
            .height(104)
            .objectFit(ImageFit.Cover)
            .borderRadius(14)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 3. 底部操作栏：头像 + 作者名 + details(居中) + 三点菜单
      Row({ space: 8 }) {
        if (item.authorAvatarUrl.length > 0) {
          Image(item.authorAvatarUrl)
            .width(20)
            .height(20)
            .objectFit(ImageFit.Cover)
            .borderRadius(10)
            .clip(true)
        } else if (item.authorName.length > 0) {
          Column() {
            Text(item.authorName.slice(0, 1))
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.action_text'))
          }
          .width(20)
          .height(20)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(10)
        }

        Text(item.authorName.length > 0 ? item.authorName : '知乎推荐')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 110 })
          .flexShrink(1)
          .alignSelf(ItemAlign.Center)

        // details 占满中间剩余空间并居中；过长省略号；不再贴着 ⋮
        Text(item.details)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .flexShrink(1)
          .padding({ left: 8, right: 8 })

        if (showBlockMenu) {
          Column() {
            Text('⋮')
              .fontSize(18)
              .fontColor($r('app.color.text_secondary'))
          }
          .width(36)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .margin({ right: 12 })
          .bindMenu(this.buildBlockMenu(item, true))
        } else {
          Blank().width(36).height(1)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
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
    .shadow({
      radius: 12,
      color: '#10000000',
      offsetX: 0,
      offsetY: 3
    })
    .onClick(() => {
      this.openHomeFeedItem(item);
    })
  }

  @Builder
  private VideoFeedCard(item: HomeFeedItem, showBlockMenu: boolean = false): void {
    Column({ space: 12 }) {
      // 0. 动作行（蓝色 actionText + 相对时间，对齐安卓动态流）
      if (item.actionText.length > 0) {
        Row() {
          Text(item.actionText)
            .fontSize(13)
            .fontColor(this.themeMode === 'dark' ? '#6FA8FF' : '#175199')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (item.createdTime !== undefined && item.createdTime > 0) {
            Text(formatRelativeTime(item.createdTime))
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
              .flexShrink(1)
              .margin({ left: 12 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      // 标题 + 推荐次数角标（与 HomeFeedCard 同款，角标在标题末尾）
      Row({ space: 6 }) {
        Text(item.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .lineHeight(26)
          .fontColor($r('app.color.text_primary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.showRecommendBadge && item.recommendCount !== undefined && item.recommendCount >= 1) {
          Text(item.recommendCount > 99 ? '99+' : `${item.recommendCount}`)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themeMode === 'dark' ? '#6FA8FF' : '#175199')
            .border({ width: 1, color: this.themeMode === 'dark' ? '#6FA8FF' : '#175199' })
            .borderRadius(11)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row({ space: 12 }) {
        Column({ space: 8 }) {
          Text(item.details)
            .fontSize(13)
            .lineHeight(20)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.showThumbnail && item.thumbnailUrl.length > 0) {
          Stack({ alignContent: Alignment.Center }) {
            Image(item.thumbnailUrl)
              .width(104)
              .height(104)
              .objectFit(ImageFit.Cover)
              .borderRadius(14)
            Column() {
              Text('▶')
                .fontSize(26)
                .fontColor('#FFFFFF')
            }
            .width(44)
            .height(44)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor('#66000000')
            .borderRadius(22)
            if (item.durationText !== undefined && item.durationText.length > 0) {
              Text(item.durationText)
                .fontSize(11)
                .fontColor('#FFFFFF')
                .backgroundColor('#99000000')
                .borderRadius(4)
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .position({ right: 4, bottom: 4 })
            }
          }
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row({ space: 8 }) {
        if (item.authorAvatarUrl.length > 0) {
          Image(item.authorAvatarUrl)
            .width(20)
            .height(20)
            .objectFit(ImageFit.Cover)
            .borderRadius(10)
            .clip(true)
        } else if (item.authorName.length > 0) {
          Column() {
            Text(item.authorName.slice(0, 1))
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.action_text'))
          }
          .width(20)
          .height(20)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(10)
        }

        Text(item.authorName.length > 0 ? item.authorName : '知乎视频')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 110 })
          .flexShrink(1)
          .alignSelf(ItemAlign.Center)

        // details 占满中间剩余空间并居中；过长省略号；不再贴着 ⋮
        Text(item.details)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .flexShrink(1)
          .padding({ left: 8, right: 8 })

        if (showBlockMenu) {
          Column() {
            Text('⋮')
              .fontSize(18)
              .fontColor($r('app.color.text_secondary'))
          }
          .width(36)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .margin({ right: 12 })
          .bindMenu(this.buildBlockMenu(item, true))
        } else {
          Blank().width(36).height(1)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
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
    .shadow({
      radius: 12,
      color: '#10000000',
      offsetX: 0,
      offsetY: 3
    })
    .onClick(() => {
      this.openHomeFeedItem(item);
    })
  }

  // 卡片三点菜单（推荐页卡片挂；其余页传 false 不渲染菜单）
  private buildBlockMenu(item: HomeFeedItem, showBlockMenu: boolean): Array<BlockMenuItem> {
    if (!showBlockMenu) {
      return [];
    }
    const items: BlockMenuItem[] = [];
    items.push({
      value: '按关键词屏蔽',
      action: () => {
        this.keywordInput = '';
        this.keywordInputError = '';
        this.showKeywordSheet = true;
      }
    });
    items.push({
      value: '屏蔽用户',
      action: () => {
        if ((item.authorId ?? '').length === 0 && (item.authorUrlToken ?? '').length === 0 && (item.authorName ?? '').length === 0) {
          promptAction.showToast({ message: '无法获取作者信息' });
          return;
        }
        this.blockUser(item);
      }
    });
    if ((item.questionAuthorId ?? '').length > 0) {
      items.push({
        value: '屏蔽提问者',
        action: () => { this.blockQuestionAuthor(item); }
      });
    }
    // 按话题屏蔽：先点这一项，再在底部弹层里勾选具体话题（避免话题多时菜单被撑长）
    items.push({
      value: '按话题屏蔽',
      action: async () => {
        this.topicSheetItem = item;
        this.selectedTopicIds = [];
        // 路线 B：按需拉内容详情（answers/questions/articles/pins + include=topics）补全真实话题名
        await this.loadTopicNames(item);
        if (this.topicSheetTopics.length === 0) {
          promptAction.showToast({ message: '该内容没有可屏蔽的话题' });
          return;
        }
        this.showTopicSheet = true;
      }
    });
    return items;
  }

  // 按关键词屏蔽（来自底部弹层输入）
  private async confirmBlockKeyword(): Promise<void> {
    const kw = this.keywordInput.trim();
    if (kw.length === 0) {
      this.keywordInputError = '关键词不能为空';
      return;
    }
    const ctx = this.context();
    BlocklistRepository.addKeyword(ctx, { text: kw, isRegex: false, caseSensitive: false });
    promptAction.showToast({ message: `已屏蔽关键词：${kw}` });
    this.homeItems = FeedFilterService.filterHomeFeed(ctx, this.homeItems);
    BlockHistoryRepository.addRecord(ctx, {
      id: `kw_${kw}`,
      title: kw,
      authorName: '',
      reason: '关键词',
      url: '',
      time: Date.now()
    });
    this.showKeywordSheet = false;
  }

  // 屏蔽用户（含 urlToken 兜底）
  private async blockUser(item: HomeFeedItem): Promise<void> {
    const ctx = this.context();
    const authorId = item.authorId ?? '';
    const authorName = item.authorName ?? '';
    const authorToken = item.authorUrlToken ?? '';
    BlocklistRepository.addUser(ctx, {
      id: authorId,
      name: authorName,
      urlToken: authorToken
    });
    const label = authorName.length > 0 ? authorName : (authorToken.length > 0 ? authorToken : '该用户');
    promptAction.showToast({ message: `已屏蔽用户：${label}` });
    this.homeItems = FeedFilterService.filterHomeFeed(ctx, this.homeItems);
    BlockHistoryRepository.addRecord(ctx, {
      id: authorId.length > 0 ? `u_${authorId}` : `u_${label}`,
      title: label,
      authorName: label,
      reason: '用户',
      url: '',
      time: Date.now()
    });
  }

  // 屏蔽提问者
  private async blockQuestionAuthor(item: HomeFeedItem): Promise<void> {
    const ctx = this.context();
    const qaId = item.questionAuthorId ?? '';
    const qaName = item.questionAuthorName ?? '';
    BlocklistRepository.addQuestionAuthor(ctx, {
      id: qaId,
      name: qaName
    });
    const label = qaName.length > 0 ? qaName : qaId;
    promptAction.showToast({ message: `已屏蔽提问者：${label}` });
    this.homeItems = FeedFilterService.filterHomeFeed(ctx, this.homeItems);
    BlockHistoryRepository.addRecord(ctx, {
      id: qaId.length > 0 ? `qa_${qaId}` : `qa_${label}`,
      title: label,
      authorName: label,
      reason: '提问者',
      url: '',
      time: Date.now()
    });
  }

  // 批量屏蔽话题（来自底部弹层多选）
  private async confirmBlockTopics(): Promise<void> {
    const item = this.topicSheetItem;
    if (item === null || this.topicSheetTopics.length === 0) {
      this.showTopicSheet = false;
      return;
    }
    const ctx = this.context();
    // 从 topicSheetTopics（真实话题列表）中取勾选项，不用 item.topics（feed 的 bound_topic_ids 无名字）
    const selected = this.topicSheetTopics.filter((t: HomeFeedTopic) => this.selectedTopicIds.indexOf(t.id) >= 0);
    if (selected.length === 0) {
      promptAction.showToast({ message: '请至少选择一个话题' });
      return;
    }
    for (const topic of selected) {
      const name = topic.name.length > 0 ? topic.name : ('#' + topic.id);
      BlocklistRepository.addTopic(ctx, { id: topic.id, name });
      BlockHistoryRepository.addRecord(ctx, {
        id: `topic_${topic.id}`,
        title: name,
        authorName: name,
        reason: '话题',
        url: '',
        time: Date.now()
      });
    }
    promptAction.showToast({ message: `已屏蔽 ${selected.length} 个话题` });
    this.homeItems = FeedFilterService.filterHomeFeed(ctx, this.homeItems);
    this.showTopicSheet = false;
  }

  // 补全话题名：按需调内容详情 API（answers/questions/articles/pins + include=topics），把真实话题灌入 topicSheetTopics
  private async loadTopicNames(item: HomeFeedItem): Promise<void> {
    const ctx = this.context();
    try {
      const topics = await HomeFeedService.fetchItemTopics(ctx, item);
      const result: HomeFeedTopic[] = [];
      for (const t of topics) {
        result.push({ id: t.id, name: t.name });
      }
      this.topicSheetTopics = result;
      // 同步写回 item.topics（让过滤器能按真实 id 命中）
      if (item !== undefined && this.topicSheetTopics.length > 0) {
        item.topics = this.topicSheetTopics;
      }
    } catch (e) {
      // 详情接口失败时 topicSheetTopics 保持空，弹层显示"无话题"
    }
  }

  private updateTopicName(id: string, name: string): void {
    const copy: Record<string, string> = {};
    const keys: string[] = Object.keys(this.topicNameMap);
    for (let i = 0; i < keys.length; i++) {
      copy[keys[i]] = this.topicNameMap[keys[i]];
    }
    copy[id] = name;
    this.topicNameMap = copy;
  }

  @Builder
  private HomePage(): void {
    if (!this.sessionSnapshot.loggedIn) {
      Column({ space: 14 }) {
        Text('需要先登录知乎')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Text('主页推荐流依赖登录 Cookie 和签名请求。')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))

        Text('去登录')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.action_text'))
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(18)
          .onClick(() => {
            this.openLoginPage();
          })
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .padding({ top: 120, left: 30, right: 30 })
    } else if (this.homeLoading && !this.homeHasLoaded) {
      Column({ space: 10 }) {
        Text('正在加载主页...')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('正在从知乎推荐接口拉取首页内容')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .padding({ top: 120 })
    } else if (this.homeError.length > 0 && !this.homeHasLoaded) {
      Column({ space: 12 }) {
        Text(this.homeError)
          .fontSize(15)
          .fontColor($r('app.color.error_text'))

        Text('重新加载')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.action_text'))
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(18)
          .onClick(() => {
            this.loadHomeFirstPage();
          })
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .padding({ top: 120 })
    } else {
      Column() {
        ForEach(this.homeItems, (item: HomeFeedItem) => {
          if (item.type === 'zvideo') {
            this.VideoFeedCard(item, true);
          } else {
            this.HomeFeedCard(item, true);
          }
        }, (item: HomeFeedItem) => item.id)

        if (this.homeError.length > 0) {
          Text(this.homeError)
            .fontSize(12)
            .fontColor($r('app.color.error_text'))
            .padding({ left: 18, right: 18, top: 0, bottom: 10 })
        }

        Text(this.homeNextUrl.length === 0 ? '已经到底了' : (this.homeLoadingMore ? '正在加载更多...' : '加载更多'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(
            this.homeNextUrl.length === 0 || this.homeLoadingMore
              ? $r('app.color.text_tertiary')
              : $r('app.color.action_text')
          )
          .padding({ left: 18, right: 18, top: 12, bottom: 12 })
          .margin({ top: 4, bottom: 20 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(18)
          .enabled(this.homeNextUrl.length > 0 && !this.homeLoadingMore)
          .onClick(() => {
            this.loadMoreHome();
          })
      }
    }
  }

  @Builder
  private FollowTabChip(option: FollowFeedTabOption): void {
    Text(option.title)
      .fontSize(14)
      .fontWeight(this.followTab === option.key ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.followTab === option.key ? $r('app.color.tab_selected_text') : $r('app.color.text_secondary'))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 10, bottom: 10 })
      .backgroundColor(this.followTab === option.key ? $r('app.color.tab_selected_background') : '#00000000')
      .border({
        width: this.followTab === option.key ? 1 : 0,
        color: this.followTab === option.key ? $r('app.color.tab_selected_border') : '#00000000'
      })
      .borderRadius(16)
      .onClick(() => {
        this.followTab = option.key;
        if (option.key === 'latest') {
          this.loadFollowRecentUsers();
        }
        if (this.sessionSnapshot.loggedIn && !this.followHasLoaded(option.key)) {
          this.loadFollowFirstPage(option.key);
        }
      })
  }

  @Builder
  private FollowFilterButton(): void {
    Row({ space: 6 }) {
      Text('筛选')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .height(32)
    .padding({ left: 14, right: 14 })
    .backgroundColor($r('app.color.action_background'))
    .borderRadius(16)
    .alignSelf(ItemAlign.Center)
    .onClick(() => {
      this.showFollowFilterSheet = true;
    })
  }

  @Builder
  private FollowFilterSheet(): void {
    Column({ space: 0 }) {
      Text('关注流筛选')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: 20, top: 16, bottom: 12 })

      Row({ space: 12 }) {
        Text('赞同了 XX')
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.followFilterVoteup })
          .onChange((v: boolean) => {
            this.followFilterVoteup = v;
            FollowFilterRepository.set(this.context(), 'voteup', v);
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 14, bottom: 14 })
      .border({ width: { bottom: 1 }, color: $r('app.color.card_border') })

      Row({ space: 12 }) {
        Text('想法')
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.followFilterPin })
          .onChange((v: boolean) => {
            this.followFilterPin = v;
            FollowFilterRepository.set(this.context(), 'pin', v);
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 14, bottom: 14 })
      .border({ width: { bottom: 1 }, color: $r('app.color.card_border') })

      Row({ space: 12 }) {
        Text('文章')
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.followFilterArticle })
          .onChange((v: boolean) => {
            this.followFilterArticle = v;
            FollowFilterRepository.set(this.context(), 'article', v);
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 14, bottom: 14 })
      .border({ width: { bottom: 1 }, color: $r('app.color.card_border') })

      Row({ space: 12 }) {
        Text('回答')
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.followFilterAnswer })
          .onChange((v: boolean) => {
            this.followFilterAnswer = v;
            FollowFilterRepository.set(this.context(), 'answer', v);
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 14, bottom: 14 })
      .border({ width: { bottom: 1 }, color: $r('app.color.card_border') })

      Row({ space: 12 }) {
        Text('屏蔽未关注作者')
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.followHideUnfollowed })
          .onChange((v: boolean) => {
            this.followHideUnfollowed = v;
            FollowFilterRepository.setHideUnfollowed(this.context(), v);
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 14, bottom: 14 })
      .border({ width: { bottom: 1 }, color: $r('app.color.card_border') })

      Blank().layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .padding({ bottom: this.bottomSafeAreaVp })
  }

  // 点击关注的人 → 底部弹层展示其发布内容（回答/文章），不进个人主页
  @Builder
  private UserContentSheet(): void {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        if (this.userContentAvatar.length > 0) {
          Image(this.userContentAvatar)
            .width(36)
            .height(36)
            .objectFit(ImageFit.Cover)
            .borderRadius(18)
            .clip(true)
            .onClick(() => {
              if (this.userContentUrlToken.length > 0) {
                this.openPerson(this.userContentUrlToken);
              }
            })
        } else if (this.userContentName.length > 0) {
          Column() {
            Text(this.userContentName.slice(0, 1))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.action_text'))
          }
          .width(36)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(18)
          .onClick(() => {
            if (this.userContentUrlToken.length > 0) {
              this.openPerson(this.userContentUrlToken);
            }
          })
        }
        Text(this.userContentName)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => {
            if (this.userContentUrlToken.length > 0) {
              this.openPerson(this.userContentUrlToken);
            }
          })
        Text('✕')
          .fontSize(20)
          .fontColor($r('app.color.text_secondary'))
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .onClick(() => { this.showUserContentSheet = false; })
      }
      .width('100%')
      .padding({ left: 16, right: 12, top: 14, bottom: 12 })

      if (this.userContentLoading) {
        Column() {
          Text('加载中…')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ top: 40 })
      } else if (this.userContentItems.length === 0) {
        Column() {
          Text('暂无发布内容')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ top: 40 })
      } else {
        Scroll() {
          Column({ space: 12 }) {
            ForEach(this.userContentItems, (item: HomeFeedItem) => {
              if (item.type === 'zvideo') {
                this.VideoFeedCard(item, false);
              } else {
                this.HomeFeedCard(item, false);
              }
            }, (item: HomeFeedItem) => item.id)
          }
          .padding({ left: 4, right: 4, top: 4, bottom: 12 })
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
  }

  @Builder
  private HotFeedCard(item: HomeFeedItem, index: number): void {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(`${index + 1}`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(index < 3 ? $r('app.color.error_text') : $r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
      }
      .width(34)
      .padding({ top: 2 })
      .alignItems(HorizontalAlign.Center)

      Column({ space: 8 }) {
        Text(item.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .lineHeight(24)
          .fontColor($r('app.color.text_primary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (item.summary.length > 0) {
          Text(item.summary)
            .fontSize(13)
            .lineHeight(20)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Row({ space: 8 }) {
          Text(item.actionText.length > 0 ? item.actionText : '热榜')
            .fontSize(12)
            .fontColor($r('app.color.error_text'))

          if (item.details.length > 0) {
            Text(item.details)
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.showThumbnail && item.thumbnailUrl.length > 0) {
        Image(item.thumbnailUrl)
          .width(88)
          .height(66)
          .objectFit(ImageFit.Cover)
          .borderRadius(8)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .margin({ left: 16, right: 16, bottom: 10 })
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .border({
      width: 1,
      color: $r('app.color.card_border')
    })
    .borderRadius(12)
    .clip(true)
    .onClick(() => {
      this.openHomeFeedItem(item);
    })
  }

  @Builder
  private HotPage(): void {
    if (this.hotLoading && !this.hotHasLoaded) {
      Column({ space: 10 }) {
        Text('正在加载热榜...')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('正在从知乎热榜接口拉取热门内容')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .padding({ top: 120 })
    } else if (this.hotError.length > 0 && !this.hotHasLoaded) {
      Column({ space: 12 }) {
        Text(this.hotError)
          .fontSize(15)
          .fontColor($r('app.color.error_text'))
          .textAlign(TextAlign.Center)

        Text('重新加载')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.action_text'))
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(18)
          .onClick(() => {
            this.loadHotFirstPage();
          })
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .padding({ top: 120, left: 24, right: 24 })
    } else if (this.hotItems.length === 0) {
      Column({ space: 10 }) {
        Text('暂无热榜内容')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('可以稍后刷新。')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .padding({ top: 120 })
    } else {
      Column() {
        Row() {
          Column({ space: 2 }) {
            Text('热榜')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))

            Text('全站热门信息流')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Text('刷新')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.hotLoading ? $r('app.color.text_tertiary') : $r('app.color.action_text'))
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor($r('app.color.action_background'))
            .borderRadius(16)
            .enabled(!this.hotLoading)
            .onClick(() => {
              this.refreshHotPage();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 18, right: 18, top: 4, bottom: 12 })

        ForEach(this.hotItems, (item: HomeFeedItem, index: number) => {
          if (item.type === 'zvideo') {
            this.VideoFeedCard(item, false);
          } else {
            this.HotFeedCard(item, index);
          }
        }, (item: HomeFeedItem) => item.id)

        if (this.hotError.length > 0) {
          Text(this.hotError)
            .fontSize(12)
            .fontColor($r('app.color.error_text'))
            .padding({ left: 18, right: 18, top: 0, bottom: 10 })
        }

        Text(this.hotNextUrl.length === 0 ? '已经到底了' : (this.hotLoadingMore ? '正在加载更多...' : '加载更多'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(
            this.hotNextUrl.length === 0 || this.hotLoadingMore
              ? $r('app.color.text_tertiary')
              : $r('app.color.action_text')
          )
          .padding({ left: 18, right: 18, top: 12, bottom: 12 })
          .margin({ top: 4, bottom: 20 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(18)
          .enabled(this.hotNextUrl.length > 0 && !this.hotLoadingMore)
          .onClick(() => {
            this.loadMoreHot();
          })
      }
    }
  }

  @Builder
  private FollowPage(): void {
    if (!this.sessionSnapshot.loggedIn) {
      Column({ space: 14 }) {
        Text('需要先登录知乎')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Text('关注最新与精选依赖登录 Cookie 和签名请求。')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))

        Text('去登录')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.action_text'))
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(18)
          .onClick(() => {
            this.openLoginPage();
          })
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .padding({ top: 120, left: 30, right: 30 })
    } else {
      Column({ space: 12 }) {
        if (this.followLoading() && !this.followHasLoaded()) {
          Column({ space: 10 }) {
            Text('正在加载关注流...')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text(this.followTab === 'featured' ? '正在同步关注精选内容' : '正在同步关注最新')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .padding({ top: 96 })
        } else if (this.followError().length > 0 && !this.followHasLoaded()) {
          Column({ space: 12 }) {
            Text(this.followError())
              .fontSize(15)
              .fontColor($r('app.color.error_text'))
              .textAlign(TextAlign.Center)

            Text('重新加载')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.action_text'))
              .padding({ left: 18, right: 18, top: 10, bottom: 10 })
              .backgroundColor($r('app.color.action_background'))
              .borderRadius(18)
              .onClick(() => {
                this.loadFollowFirstPage(this.followTab);
              })
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .padding({ top: 96, left: 24, right: 24 })
        } else if (this.followItems().length === 0) {
          Column({ space: 10 }) {
            Text('暂无关注内容')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('可以稍后刷新，或切换另一个关注子页。')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .padding({ top: 96 })
        } else {
          Column() {
            if (this.followTab === 'latest') {
              // 我关注的人 横排（仅最新 tab，对齐安卓 FollowingUsersRow）
              if (this.followRecentLoading && this.followRecentUsers.length === 0) {
                Text('加载关注的人…')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .padding({ left: 16, top: 4, bottom: 8 })
              } else if (this.followRecentUsers.length > 0) {
                Scroll() {
                  Row({ space: 16 }) {
                    ForEach(this.followRecentUsers, (u: FollowingUserItem) => {
                      Column({ space: 4 }) {
                        Stack({ alignContent: Alignment.TopEnd }) {
                          Image(u.avatarUrl)
                            .width(56)
                            .height(56)
                            .objectFit(ImageFit.Cover)
                            .borderRadius(28)
                            .clip(true)
                          if (u.unreadCount > 0) {
                            Circle()
                              .width(12)
                              .height(12)
                              .fill('#FA5151')
                              .stroke('#FFFFFF')
                              .strokeWidth(2)
                          }
                        }
                        Text(u.name)
                          .fontSize(12)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width(60)
                          .textAlign(TextAlign.Center)
                      }
                      .onClick(() => {
                        if (u.urlToken.length > 0) {
                          this.openUserContent(u);
                        }
                      })
                    }, (u: FollowingUserItem) => u.id)
                  }
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
              }
            }
            ForEach(this.followItems(), (item: HomeFeedItem) => {
              if (item.type === 'zvideo') {
                this.VideoFeedCard(item, false);
              } else {
                this.HomeFeedCard(item, false);
              }
            }, (item: HomeFeedItem) => item.id)

            if (this.followError().length > 0) {
              Text(this.followError())
                .fontSize(12)
                .fontColor($r('app.color.error_text'))
                .padding({ left: 18, right: 18, top: 0, bottom: 10 })
            }

            Text(this.followNextUrl().length === 0 ? '已经到底了' : (this.followLoadingMore() ? '正在加载更多...' : '加载更多'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(
                this.followNextUrl().length === 0 || this.followLoadingMore()
                  ? $r('app.color.text_tertiary')
                  : $r('app.color.action_text')
              )
              .padding({ left: 18, right: 18, top: 12, bottom: 12 })
              .margin({ top: 4, bottom: 20 })
              .backgroundColor($r('app.color.action_background'))
              .borderRadius(18)
              .enabled(this.followNextUrl().length > 0 && !this.followLoadingMore())
              .onClick(() => {
                this.loadMoreFollow();
              })
          }
        }
      }
      .width('100%')
    }
  }

  @Builder
  private HistoryPage(): void {
    if (this.historyItems.length === 0) {
      Column({ space: 12 }) {
        Text('暂无最近浏览')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Text('从主页、关注或日报打开内容后，会在这里显示。')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .padding({ top: 120, left: 28, right: 28 })
    } else {
      Column({ space: 10 }) {
        Row() {
          Text('最近浏览')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Text('清空')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({ width: 1, color: $r('app.color.card_border') })
            .borderRadius(16)
            .onClick(() => {
              this.clearHistoryItems();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 18, right: 18, top: 4, bottom: 2 })

        ForEach(this.historyItems, (item: HomeFeedItem) => {
          this.HomeFeedCard(item, false);
        }, (item: HomeFeedItem) => item.id)

        Column()
          .height(20)
          .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private HistorySheet(): void {
    Column({ space: 8 }) {
      // ---- 标题行 ----
      Row() {
        Text('浏览历史')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        if (this.mergedHistoryItems.length > 0) {
          Text('清空')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({ width: 1, color: $r('app.color.card_border') })
            .borderRadius(16)
            .onClick(() => {
              this.clearHistoryItems();
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // ---- 内容区 ----
      if (this.mergedHistoryItems.length === 0 && !this.cloudHistoryLoading) {
        // 空状态
        Column({ space: 10 }) {
          Text('暂无浏览历史')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Text('从主页、关注或日报打开内容后，会在这里显示。')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .padding({ top: 60, left: 28, right: 28 })
      } else {
        // 历史条目列表
        ForEach(this.mergedHistoryItems, (item: HomeFeedItem) => {
          this.HistoryFeedCard(item);
        }, (item: HomeFeedItem) => item.id)

        // ---- 底部状态区 ----
        // 正在同步云端
        if (this.cloudHistoryLoading) {
          Row({ space: 6 }) {
            LoadingProgress()
              .width(14)
              .height(14)
            Text('正在同步云端数据...')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 12, bottom: 12 })
        }

        // 加载更多云端数据
        if (!this.cloudHistoryIsEnd && !this.cloudHistoryLoading) {
          Column() {
            if (this.cloudHistoryLoadingMore) {
              LoadingProgress()
                .width(20)
                .height(20)
                .margin({ top: 8, bottom: 8 })
            } else {
              Text('加载更多')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.action_text'))
                .padding({ left: 18, right: 18, top: 10, bottom: 10 })
                .backgroundColor($r('app.color.action_background'))
                .borderRadius(18)
                .onClick(() => {
                  this.loadMoreCloudHistory();
                })
            }
          }
          .alignItems(HorizontalAlign.Center)
          .width('100%')
          .padding({ top: 4 })
        }

        // 云端同步失败
        if (this.cloudHistoryError.length > 0 && !this.cloudHistoryLoading) {
          Row({ space: 6 }) {
            Text('云端同步失败')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))

            Text('重试')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.action_text'))
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor($r('app.color.action_background'))
              .borderRadius(12)
              .onClick(() => {
                this.loadCloudHistory();
              })
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8, bottom: 8 })
        }
      }

      Column()
        .height(24)
        .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 浏览历史专用的卡片（带 ⋮ 菜单）
   */
  @Builder
  private HistoryFeedCard(item: HomeFeedItem): void {
    Column({ space: 12 }) {
      // 标题
      Text(item.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .lineHeight(26)
        .fontColor($r('app.color.text_primary'))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      // 正文摘要
      if (item.summary.length > 0) {
        Text(item.summary)
          .fontSize(13)
          .lineHeight(20)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      // 底部操作栏：作者名 + 时间 + ⋮ 菜单
      Row({ space: 10 }) {
        Text(item.authorName.length > 0 ? item.authorName : '知乎推荐')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 140 })

        Blank().layoutWeight(1).height(1)

        Text(item.details)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)

        Blank().width(12).height(1)

        Text('⋮')
          .fontSize(18)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.showHistoryItemMenu(item);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
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
    .shadow({
      radius: 12,
      color: '#10000000',
      offsetX: 0,
      offsetY: 3
    })
    .onClick(() => {
      this.openHomeFeedItem(item);
    })
  }

  @Builder
  private DailyPage(): void {
    if (this.dailyLoading && this.dailySections.length === 0) {
      Column({ space: 10 }) {
        Text('正在加载日报...')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('正在从知乎日报接口拉取最新内容')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .padding({ top: 120 })
    } else if (this.dailyError.length > 0 && this.dailySections.length === 0) {
      Column({ space: 12 }) {
        Text(this.dailyError)
          .fontSize(15)
          .fontColor($r('app.color.error_text'))

        Text('重试')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.action_text'))
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(18)
          .onClick(() => {
            this.loadLatestDaily();
          })
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .padding({ top: 120 })
    } else {
      Column() {
        ForEach(this.dailySections, (section: DailySection, sectionIndex: number) => {
          Column() {
            this.DailySectionHeader(section)

            ForEach(section.stories, (story: DailyStory) => {
              this.DailyStoryCard(story)
            }, (story: DailyStory) => story.id)
          }
        }, (section: DailySection) => section.date)

        if (this.dailyError.length > 0) {
          Text(this.dailyError)
            .fontSize(12)
            .fontColor($r('app.color.error_text'))
            .padding({ left: 18, right: 18, top: 0, bottom: 10 })
        }

        Text(this.dailyLoadingMore ? '正在加载更多...' : '加载更多')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dailyLoadingMore ? $r('app.color.text_tertiary') : $r('app.color.action_text'))
          .padding({ left: 18, right: 18, top: 12, bottom: 12 })
          .margin({ top: 4, bottom: 20 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(18)
          .enabled(!this.dailyLoadingMore)
          .onClick(() => {
            this.loadMoreDaily();
          })
      }
    }
  }

  @Builder
  private PlaceholderPage(): void {
    Column({ space: 12 }) {
      Text(this.portalPlaceholder(this.selectedPortalTab))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Text('当前先接入主页和日报，这个入口后续再迁。')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .padding({ top: 120 })
  }

  @Builder
  private ContentArea(): void {
    if (this.selectedPortalTab === 'home') {
      this.HomePage();
    } else if (this.selectedPortalTab === 'follow') {
      this.FollowPage();
    } else if (this.selectedPortalTab === 'hot') {
      this.HotPage();
    } else if (this.selectedPortalTab === 'daily') {
      this.DailyPage();
    } else {
      this.PlaceholderPage();
    }
  }

  @Builder
  private PortalTab(item: AppPortalOption): void {
    Column() {
      Text(item.title)
        .fontSize(14)
        .fontWeight(this.selectedPortalTab === item.key ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.selectedPortalTab === item.key ? $r('app.color.tab_selected_text') : $r('app.color.text_secondary'))
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
    .height(44)
    .backgroundColor(this.selectedPortalTab === item.key ? $r('app.color.tab_selected_background') : '#00000000')
    .backgroundBlurStyle(this.selectedPortalTab === item.key ? BlurStyle.Thick : BlurStyle.Thin)
    .border({
      width: this.selectedPortalTab === item.key ? 1 : 0,
      color: this.selectedPortalTab === item.key ? $r('app.color.tab_selected_border') : '#00000000'
    })
    .borderRadius(18)
    .onClick(() => {
      this.selectedPortalTab = item.key;
      this.showHomeAccountPanel = false;
      this.resetTopBar(); // 切 tab 时重置顶栏为展开
      if (item.key === 'home') {
        if (!this.sessionSnapshot.loggedIn) {
          this.openLoginPage();
        } else if (!this.homeHasLoaded) {
          this.loadHomeFirstPage();
        }
      } else if (item.key === 'follow') {
        if (!this.sessionSnapshot.loggedIn) {
          this.openLoginPage();
        } else if (!this.followHasLoaded()) {
          this.loadFollowFirstPage(this.followTab);
        }
      } else if (item.key === 'hot') {
        if (!this.hotHasLoaded) {
          this.loadHotFirstPage();
        }
      } else if (item.key === 'daily' && this.dailySections.length === 0) {
        this.loadLatestDaily();
      }
    })
  }

  @Builder
  private BottomPortalBar(): void {
    Row({ space: 8 }) {
      ForEach(APP_PORTAL_TABS, (item: AppPortalOption) => {
        this.PortalTab(item)
      }, (item: AppPortalOption) => item.key)
    }
    .padding({ left: 10, right: 10, top: 10, bottom: 6 })
    .margin({ left: 16, right: 16, bottom: 0 })
    .backgroundColor('#80FFFFFF')
    .backgroundBlurStyle(this.ambientBlurStyle())
    .border({
      width: 1,
      color: $r('app.color.tab_bar_border')
    })
    .borderRadius(24)
    .shadow({
      radius: 18,
      color: '#10000000',
      offsetX: 0,
      offsetY: 8
    })
  }

  // ==================== HDS Tab 栏 Builder（沉浸光感材质） ====================

  @Builder
  private TabBarHome(): void {
    Column() {
      Row() {
        Text('主页')
          .fontSize(14)
          .fontWeight(this.selectedPortalTab === 'home' ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selectedPortalTab === 'home' ? '#FFFFFF' : $r('app.color.action_pill_icon'))
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: 18, right: 18, top: 6, bottom: 6 })
      .backgroundColor(this.selectedPortalTab === 'home' ? $r('app.color.action_text') : $r('app.color.action_pill_button_inactive'))
      .borderRadius(16)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .onClick(() => {
      // 再点当前已激活的 tab → 平滑回顶，不触发刷新
      if (this.selectedPortalTab === 'home') {
        this.resetTopBar();
        this.resetHomeBottomBar();
        this.homeScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      }
    })
  }

  @Builder
  private TabBarFollow(): void {
    Column() {
      Row() {
        Text('关注')
          .fontSize(14)
          .fontWeight(this.selectedPortalTab === 'follow' ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selectedPortalTab === 'follow' ? '#FFFFFF' : $r('app.color.action_pill_icon'))
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: 18, right: 18, top: 6, bottom: 6 })
      .backgroundColor(this.selectedPortalTab === 'follow' ? $r('app.color.action_text') : $r('app.color.action_pill_button_inactive'))
      .borderRadius(16)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .onClick(() => {
      if (this.selectedPortalTab === 'follow') {
        this.resetTopBar();
        this.resetHomeBottomBar();
        this.followScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      }
    })
  }

  @Builder
  private TabBarHot(): void {
    Column() {
      Row() {
        Text('热榜')
          .fontSize(14)
          .fontWeight(this.selectedPortalTab === 'hot' ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selectedPortalTab === 'hot' ? '#FFFFFF' : $r('app.color.action_pill_icon'))
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: 18, right: 18, top: 6, bottom: 6 })
      .backgroundColor(this.selectedPortalTab === 'hot' ? $r('app.color.action_text') : $r('app.color.action_pill_button_inactive'))
      .borderRadius(16)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .onClick(() => {
      if (this.selectedPortalTab === 'hot') {
        this.resetTopBar();
        this.resetHomeBottomBar();
        this.hotScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      }
    })
  }

  @Builder
  private TabBarDaily(): void {
    Column() {
      Row() {
        Text('日报')
          .fontSize(14)
          .fontWeight(this.selectedPortalTab === 'daily' ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selectedPortalTab === 'daily' ? '#FFFFFF' : $r('app.color.action_pill_icon'))
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: 18, right: 18, top: 6, bottom: 6 })
      .backgroundColor(this.selectedPortalTab === 'daily' ? $r('app.color.action_text') : $r('app.color.action_pill_button_inactive'))
      .borderRadius(16)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .onClick(() => {
      if (this.selectedPortalTab === 'daily') {
        this.resetTopBar();
        this.resetHomeBottomBar();
        this.dailyScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      }
    })
  }

  @Builder
  KeywordSheet() {
    Column({ space: 12 }) {
      Text('按关键词屏蔽')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      Text('包含该关键词的内容将从推荐页隐藏')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      TextInput({ placeholder: '输入要屏蔽的关键词', text: this.keywordInput })
        .width('100%')
        .onChange((value: string): void => {
          this.keywordInput = value;
          if (this.keywordInputError.length > 0) {
            this.keywordInputError = '';
          }
        })

      if (this.keywordInputError.length > 0) {
        Text(this.keywordInputError)
          .fontSize(12)
          .fontColor($r('app.color.error_text'))
          .width('100%')
          .textAlign(TextAlign.Start)
      }

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .onClick(() => {
            this.showKeywordSheet = false;
          })
        Button('确定')
          .layoutWeight(1)
          .onClick(() => {
            this.confirmBlockKeyword();
          })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .padding(20)
    .width('100%')
  }

  @Builder
  private TopicSheet() {
    Column({ space: 12 }) {
      Text('按话题屏蔽')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      if (this.topicSheetTopics.length > 0) {
        Text('选择要屏蔽的话题（可多选）')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Start)

        Scroll() {
          Column() {
            ForEach(this.topicSheetTopics, (topic: HomeFeedTopic) => {
              Row({ space: 10 }) {
                Text(topic.name.length > 0 ? topic.name : ('#' + topic.id))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                  .textAlign(TextAlign.Start)
                if (this.selectedTopicIds.indexOf(topic.id) >= 0) {
                  Text('✓')
                    .fontSize(16)
                    .fontColor($r('app.color.action_text'))
                }
              }
              .width('100%')
              .padding({ top: 12, bottom: 12 })
              .onClick(() => {
                if (this.selectedTopicIds.indexOf(topic.id) >= 0) {
                  this.selectedTopicIds = this.selectedTopicIds.filter((id: string) => id !== topic.id);
                } else {
                  this.selectedTopicIds = [...this.selectedTopicIds, topic.id];
                }
              })
            }, (topic: HomeFeedTopic) => topic.id)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 320 })
      } else {
        Text('该内容没有可屏蔽的话题')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Start)
      }

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .onClick(() => {
            this.showTopicSheet = false;
          })
        Button('确定')
          .layoutWeight(1)
          .onClick(() => {
            this.confirmBlockTopics();
          })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .padding(20)
    .width('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Stack({ alignContent: Alignment.Bottom }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Stack({ alignContent: Alignment.Top }) {
          HdsTabs({ controller: this.hdsTabsController }) {
            TabContent() {
              Column() {
                Column()
                  .width('100%')
                  .height(this.topBarScrollInset())

                Refresh({ refreshing: $$this.tabRefreshing }) {
                  Scroll(this.homeScroller) {
                    Column() {
                      this.HomePage()

                      Column()
                        .height(BOTTOM_PORTAL_BAR_CONTENT_INSET + this.bottomSafeAreaVp)
                        .width('100%')
                    }
                  }
                  .scrollBar(BarState.Off)
                  .edgeEffect(EdgeEffect.Spring)
                  .onWillScroll((_dx: number, dy: number, _state: ScrollState) => {
                    this.updateHomeBottomBarOnScroll(dy);
                    this.updateTopBarOnScroll(dy);
                  })
                  .onScrollStop(() => {
                    this.snapHomeBottomBar();
                    this.snapTopBar();
                  })
                  .onScrollEdge((side: Edge) => {
                    this.handleContentScrollEdge(side);
                  })
                  .width('100%')
                  .height('100%')
                }
                .onRefreshing(() => {
                  this.refreshCurrentTab();
                })
                .width('100%')
                .layoutWeight(1)
              }
              .width('100%')
              .height('100%')
            }
            .tabBar(this.TabBarHome)

            TabContent() {
              Column() {
                Column()
                  .width('100%')
                  .height(this.topBarScrollInset())

                Refresh({ refreshing: $$this.tabRefreshing }) {
                  Scroll(this.followScroller) {
                    Column() {
                      this.FollowPage()

                      Column()
                        .height(BOTTOM_PORTAL_BAR_CONTENT_INSET + this.bottomSafeAreaVp)
                        .width('100%')
                    }
                  }
                  .scrollBar(BarState.Off)
                  .edgeEffect(EdgeEffect.Spring)
                  .onWillScroll((_dx: number, dy: number, _state: ScrollState) => {
                    this.updateHomeBottomBarOnScroll(dy);
                    this.updateTopBarOnScroll(dy);
                  })
                  .onScrollStop(() => {
                    this.snapHomeBottomBar();
                    this.snapTopBar();
                  })
                  .onScrollEdge((side: Edge) => {
                    this.handleContentScrollEdge(side);
                  })
                  .width('100%')
                  .height('100%')
                }
                .onRefreshing(() => {
                  this.refreshCurrentTab();
                })
                .width('100%')
                .layoutWeight(1)
              }
              .width('100%')
              .height('100%')
            }
            .tabBar(this.TabBarFollow)

            TabContent() {
              Column() {
                Column()
                  .width('100%')
                  .height(this.topBarScrollInset())

                Refresh({ refreshing: $$this.tabRefreshing }) {
                  Scroll(this.hotScroller) {
                    Column() {
                      this.HotPage()

                      Column()
                        .height(BOTTOM_PORTAL_BAR_CONTENT_INSET + this.bottomSafeAreaVp)
                        .width('100%')
                    }
                  }
                  .scrollBar(BarState.Off)
                  .edgeEffect(EdgeEffect.Spring)
                  .onWillScroll((_dx: number, dy: number, _state: ScrollState) => {
                    this.updateHomeBottomBarOnScroll(dy);
                    this.updateTopBarOnScroll(dy);
                  })
                  .onScrollStop(() => {
                    this.snapHomeBottomBar();
                    this.snapTopBar();
                  })
                  .onScrollEdge((side: Edge) => {
                    this.handleContentScrollEdge(side);
                  })
                  .width('100%')
                  .height('100%')
                }
                .onRefreshing(() => {
                  this.refreshCurrentTab();
                })
                .width('100%')
                .layoutWeight(1)
              }
              .width('100%')
              .height('100%')
            }
            .tabBar(this.TabBarHot)

            TabContent() {
              Column() {
                Column()
                  .width('100%')
                  .height(this.topBarScrollInset())

                Refresh({ refreshing: $$this.tabRefreshing }) {
                  Scroll(this.dailyScroller) {
                    Column() {
                      this.DailyPage()

                      Column()
                        .height(BOTTOM_PORTAL_BAR_CONTENT_INSET + this.bottomSafeAreaVp)
                        .width('100%')
                    }
                  }
                  .scrollBar(BarState.Off)
                  .edgeEffect(EdgeEffect.Spring)
                  .onWillScroll((_dx: number, dy: number, _state: ScrollState) => {
                    this.updateHomeBottomBarOnScroll(dy);
                    this.updateTopBarOnScroll(dy);
                  })
                  .onScrollStop(() => {
                    this.snapHomeBottomBar();
                    this.snapTopBar();
                  })
                  .onScrollEdge((side: Edge) => {
                    this.handleContentScrollEdge(side);
                  })
                  .width('100%')
                  .height('100%')
                }
                .onRefreshing(() => {
                  this.refreshCurrentTab();
                })
                .width('100%')
                .layoutWeight(1)
              }
              .width('100%')
              .height('100%')
            }
            .tabBar(this.TabBarDaily)
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
              materialType: hdsMaterial.MaterialType.IMMERSIVE,
              materialLevel: this.resolveMaterialLevel(this.materialLevel)
            }
          })
          .onChange((index: number) => {
            this.onTabChange(index);
          })

          this.TopBar()
        }
        .width('100%')
        .height('100%')

        if (this.showRefreshFab && this.selectedPortalTab === 'home') {
          Button() {
            Image($r('app.media.ic_refresh'))
              .draggable(false)
              .width(24)
              .height(24)
              .renderMode(ImageRenderMode.Template)
              .fillColor($r('app.color.action_pill_icon'))
              .syncLoad(true)
          }
          .width(52)
          .height(52)
          .borderRadius(26)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .shadow({ radius: 12, color: '#20000000', offsetX: 0, offsetY: 4 })
          .position({ right: 16, bottom: BOTTOM_PORTAL_BAR_CONTENT_INSET + this.bottomSafeAreaVp + 16 })
          .onClick(() => {
            this.tabRefreshing = true;
            this.refreshCurrentTab();
          })
        }
        }
      .width('100%')
      .height('100%')
      .bindSheet($$this.showHomeAccountPanel, this.HomeAccountSheet(), {
      showClose: false,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      detents: [540, SheetSize.LARGE],
      backgroundColor: ThemeColors.feedBackground(this.oledBlack, this.isDark),
      onDisappear: () => {
        this.showHomeAccountPanel = false;
      }
    })

        Column()
          .width(1)
          .height(1)
          .bindSheet($$this.showKeywordSheet, this.KeywordSheet(), {
            showClose: false,
            dragBar: true,
            preferType: SheetType.BOTTOM,
            detents: [330],
            backgroundColor: ThemeColors.feedBackground(this.oledBlack, this.isDark),
            onDisappear: () => {
              this.showKeywordSheet = false;
            }
          })

        Column()
          .width(1)
          .height(1)
          .bindSheet($$this.showTopicSheet, this.TopicSheet(), {
            showClose: false,
            dragBar: true,
            preferType: SheetType.BOTTOM,
            detents: [360],
            backgroundColor: ThemeColors.feedBackground(this.oledBlack, this.isDark),
            onDisappear: () => {
              this.showTopicSheet = false;
            }
          })

        Column()
          .width(1)
          .height(1)
          .bindSheet($$this.showFollowFilterSheet, this.FollowFilterSheet(), {
            showClose: false,
            dragBar: true,
            preferType: SheetType.BOTTOM,
            detents: [360],
            backgroundColor: ThemeColors.feedBackground(this.oledBlack, this.isDark),
            onDisappear: () => {
              this.showFollowFilterSheet = false;
            }
          })

        Column()
          .width(1)
          .height(1)
          .bindSheet($$this.showUserContentSheet, this.UserContentSheet(), {
            showClose: false,
            dragBar: true,
            preferType: SheetType.BOTTOM,
            detents: [560],
            backgroundColor: ThemeColors.feedBackground(this.oledBlack, this.isDark),
            onDisappear: () => {
              this.showUserContentSheet = false;
            }
          })
    }
    .width('100%')
    .height('100%')
  }
}
