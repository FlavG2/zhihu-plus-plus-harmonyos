import common from '@ohos.app.ability.common';
import { promptAction, router, LengthMetrics } from '@kit.ArkUI';
import { AppearanceThemeMode } from '../services/AppearanceSettingsRepository';
import { ThemeColors } from '../services/ThemeColors';
import {
  HomeFeedItem,
  SessionSnapshot,
  ZhihuCollection,
  DEFAULT_SESSION_SNAPSHOT
} from '../models/ZhihuModels';
import { ZhihuCommentableTarget, serializeZhihuContentTarget } from '../models/ZhihuContentModels';
import {
  PeopleService,
  ZhihuPeopleProfile,
  ZhihuPeopleSummary,
  ZhihuColumnSummary,
  ZhihuTopicSummary,
  ZhihuFollowedQuestionSummary,
  OfficialBadgeDetail
} from '../services/PeopleService';
import { ZhihuSessionRepository } from '../services/ZhihuSessionRepository';
import { BlocklistRepository, BlockedUser, BlockedQuestionAuthor } from '../services/BlocklistRepository';

export interface PeoplePageParams {
  readonly urlToken?: string;
  // 安卓对齐：账号面板「关注订阅」等入口通过 jumpTo='关注订阅' 直接定位到对应 tab
  readonly jumpTo?: string;
}

interface TabLoadState {
  readonly loaded: boolean;
  readonly loading: boolean;
  readonly loadingMore: boolean;
  readonly isEnd: boolean;
  readonly error: string;
  readonly nextUrl: string;
}

const DEFAULT_TAB_STATE: TabLoadState = {
  loaded: false,
  loading: false,
  loadingMore: false,
  isEnd: false,
  error: '',
  nextUrl: ''
};

function formatCounter(value: number, unit: string): string {
  if (value >= 10000) {
    return `${(value / 10000).toFixed(value >= 100000 ? 0 : 1)} 万${unit}`;
  }
  return `${value} ${unit}`;
}

function errMsg(error: Object): string {
  return error instanceof Error ? error.message : '未知错误';
}

@Entry
@Component
struct People {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageProp('bottomSafeAreaVp') private bottomSafeAreaVp: number = 0;
  @StorageProp('themeMode') private themeMode: AppearanceThemeMode = 'system';
  @StorageProp('sessionSnapshot') private sessionSnapshot: SessionSnapshot = DEFAULT_SESSION_SNAPSHOT;

  @State private urlToken: string = '';
  @State private identifier: string = '';
  @State private profile: ZhihuPeopleProfile | null = null;
  @State private profileLoading: boolean = false;
  @State private profileError: string = '';
  @State private isSelf: boolean = false;
  // 本地屏蔽态（来自 BlocklistRepository，对齐安卓 isUserBlocked / isQuestionAuthorBlocked）
  @State private blockedInRecommendations: boolean = false;
  @State private blockedAsQuestionAuthor: boolean = false;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;

  @State private selectedTab: number = 0;
  @State private answersSort: string = 'voteups';
  @State private articlesSort: string = 'created';
  @State private subTab: number = 0;

  // 各 tab 的分页状态（索引对应 tabTitles）
  @State private tabStates: TabLoadState[] = [
    DEFAULT_TAB_STATE, DEFAULT_TAB_STATE, DEFAULT_TAB_STATE, DEFAULT_TAB_STATE, DEFAULT_TAB_STATE,
    DEFAULT_TAB_STATE, DEFAULT_TAB_STATE, DEFAULT_TAB_STATE, DEFAULT_TAB_STATE, DEFAULT_TAB_STATE
  ];
  @State private subStates: TabLoadState[] = [DEFAULT_TAB_STATE, DEFAULT_TAB_STATE, DEFAULT_TAB_STATE, DEFAULT_TAB_STATE];

  // 各 tab 的数据
  @State private answers: HomeFeedItem[] = [];
  @State private articles: HomeFeedItem[] = [];
  @State private activities: HomeFeedItem[] = [];
  @State private questions: HomeFeedItem[] = [];
  @State private pins: HomeFeedItem[] = [];
  @State private collections: ZhihuCollection[] = [];
  @State private columns: ZhihuColumnSummary[] = [];
  @State private followers: ZhihuPeopleSummary[] = [];
  @State private following: ZhihuPeopleSummary[] = [];
  @State private subColumns: ZhihuColumnSummary[] = [];
  @State private subTopics: ZhihuTopicSummary[] = [];
  @State private subQuestions: ZhihuFollowedQuestionSummary[] = [];
  @State private subCollections: ZhihuCollection[] = [];

  // 个人卡片（头像+统计+操作按钮）随滚动折叠：到顶显示、下滚隐藏
  @State private profileHeaderVisible: boolean = true;

  private readonly tabTitles: string[] = ['回答', '文章', '动态', '收藏', '提问', '想法', '专栏', '粉丝', '关注', '关注订阅'];
  private readonly subTitles: string[] = ['我订阅的专栏', '关注的话题', '关注的问题', '关注的收藏夹'];
  private readonly peopleTabsController: TabsController = new TabsController();

  // 各 tab 列表各自的滚动控制器（用于读取绝对滚动偏移，判断个人卡片显隐）
  private readonly answersScroller: ListScroller = new ListScroller();
  private readonly articlesScroller: ListScroller = new ListScroller();
  private readonly activitiesScroller: ListScroller = new ListScroller();
  private readonly questionsScroller: ListScroller = new ListScroller();
  private readonly pinsScroller: ListScroller = new ListScroller();
  private readonly collectionsScroller: ListScroller = new ListScroller();
  private readonly columnsScroller: ListScroller = new ListScroller();
  private readonly followersScroller: ListScroller = new ListScroller();
  private readonly followingScroller: ListScroller = new ListScroller();
  private readonly subColumnsScroller: ListScroller = new ListScroller();
  private readonly subTopicsScroller: ListScroller = new ListScroller();
  private readonly subQuestionsScroller: ListScroller = new ListScroller();
  private readonly subCollectionsScroller: ListScroller = new ListScroller();

  aboutToAppear(): void {
    const params = router.getParams() as PeoplePageParams;
    const paramToken = params !== undefined && typeof params.urlToken === 'string' ? params.urlToken : '';
    const session = ZhihuSessionRepository.load(this.context() as common.Context);
    const selfToken = session.self?.urlToken ?? '';
    if (paramToken.length > 0) {
      this.urlToken = paramToken;
      this.identifier = paramToken;
    } else {
      this.urlToken = selfToken;
      this.identifier = selfToken;
    }
    // 安卓对齐：账号面板「关注订阅」等入口通过 jumpTo='关注订阅' 直接定位到对应 tab
    if (params !== undefined && typeof params.jumpTo === 'string' && params.jumpTo.length > 0) {
      const idx = this.tabTitles.indexOf(params.jumpTo);
      if (idx >= 0) {
        this.selectedTab = idx;
      }
    }
    // 自己主页可立即判定，避免首帧 isSelf 仍为 false 导致 tab 错位（loadProfile 会再次确认）
    this.isSelf = this.urlToken.length > 0 && this.urlToken === selfToken;
    this.loadProfile();
    if (this.identifier.length > 0) {
      this.ensureTabLoaded(this.selectedTab);
    }
  }

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  private showToast(message: string): void {
    promptAction.showToast({ message, duration: 1800 });
  }

  private tabState(index: number): TabLoadState {
    return this.tabStates[index] ?? DEFAULT_TAB_STATE;
  }

  private updateTabState(index: number, patch: Partial<TabLoadState>): void {
    const next = this.tabStates.slice();
    next[index] = this.mergeTabState(next[index], patch);
    this.tabStates = next;
  }

  private subState(index: number): TabLoadState {
    return this.subStates[index] ?? DEFAULT_TAB_STATE;
  }

  private updateSubState(index: number, patch: Partial<TabLoadState>): void {
    const next = this.subStates.slice();
    next[index] = this.mergeTabState(next[index], patch);
    this.subStates = next;
  }

  private mergeTabState(base: TabLoadState, patch: Partial<TabLoadState>): TabLoadState {
    return {
      loaded: patch.loaded !== undefined ? patch.loaded : base.loaded,
      loading: patch.loading !== undefined ? patch.loading : base.loading,
      loadingMore: patch.loadingMore !== undefined ? patch.loadingMore : base.loadingMore,
      isEnd: patch.isEnd !== undefined ? patch.isEnd : base.isEnd,
      error: patch.error !== undefined ? patch.error : base.error,
      nextUrl: patch.nextUrl !== undefined ? patch.nextUrl : base.nextUrl
    };
  }

  // ---------- 资料加载 ----------
  private async loadProfile(): Promise<void> {
    if (this.identifier.length === 0) {
      this.profileError = '请先登录后再查看个人主页';
      return;
    }
    this.profileLoading = true;
    this.profileError = '';
    try {
      const profile = await PeopleService.loadProfile(this.context(), this.identifier);
      this.profile = profile;
      if (profile.urlToken.length > 0) {
        this.urlToken = profile.urlToken;
        this.identifier = profile.urlToken;
      }
      const selfToken = ZhihuSessionRepository.load(this.context()).self?.urlToken ?? '';
      this.isSelf = profile.urlToken.length > 0 && profile.urlToken === selfToken;
      this.refreshLocalBlockStates();
    } catch (error) {
      this.profileError = `资料加载失败：${errMsg(error)}`;
    } finally {
      this.profileLoading = false;
    }
  }

  // 读取本地屏蔽态（推荐屏蔽 users / 提问者屏蔽 question authors），对齐安卓 PeopleScreen
  private refreshLocalBlockStates(): void {
    const id = this.profile?.id ?? '';
    this.blockedInRecommendations = BlocklistRepository.isUserBlocked(this.context(), id);
    this.blockedAsQuestionAuthor = BlocklistRepository.isQuestionAuthorBlocked(this.context(), id);
  }

  private doToggleRecommendationBlock(): void {
    const p = this.profile;
    if (p === null || p.id.length === 0 || this.isSelf) {
      return;
    }
    const user: BlockedUser = { id: p.id, name: p.name, urlToken: p.urlToken };
    this.blockedInRecommendations = BlocklistRepository.toggleUserBlock(this.context(), user);
  }

  private doToggleQuestionAuthorBlock(): void {
    const p = this.profile;
    if (p === null || p.id.length === 0 || this.isSelf) {
      return;
    }
    const qa: BlockedQuestionAuthor = { id: p.id, name: p.name };
    this.blockedAsQuestionAuthor = BlocklistRepository.toggleQuestionAuthorBlock(this.context(), qa);
  }

  // ---------- 各 tab 首屏 / 加载更多 ----------
  private ensureTabLoaded(index: number): void {
    if (index === 9) {
      this.ensureSubLoaded(this.subTab);
      return;
    }
    const st = this.tabState(index);
    if (!st.loaded && !st.loading) {
      this.loadTab(index, false);
    }
  }

  private ensureSubLoaded(index: number): void {
    const st = this.subState(index);
    if (!st.loaded && !st.loading) {
      this.loadSubTab(index, false);
    }
  }

  private loadTab(index: number, loadMore: boolean): void {
    switch (index) {
      case 0: this.loadAnswers(loadMore); break;
      case 1: this.loadArticles(loadMore); break;
      case 2: this.loadActivities(loadMore); break;
      case 3: this.loadCollections(loadMore); break;
      case 4: this.loadQuestions(loadMore); break;
      case 5: this.loadPins(loadMore); break;
      case 6: this.loadColumns(loadMore); break;
      case 7: this.loadFollowers(loadMore); break;
      case 8: this.loadFollowing(loadMore); break;
      case 9: this.loadSubTab(this.subTab, loadMore); break;
      default: break;
    }
  }

  private async loadAnswers(loadMore: boolean): Promise<void> {
    const st = this.tabState(0);
    if (!loadMore && st.loading) return;
    if (loadMore && (st.isEnd || st.loadingMore || st.nextUrl.length === 0)) return;
    this.updateTabState(0, { loading: !loadMore, loadingMore: loadMore });
    try {
      const page = await PeopleService.loadAnswers(this.context(), this.identifier, this.answersSort, loadMore ? st.nextUrl : undefined);
      this.answers = loadMore ? [...this.answers, ...page.items] : page.items;
      this.updateTabState(0, { loaded: true, loading: false, loadingMore: false, isEnd: page.isEnd, nextUrl: page.nextUrl, error: '' });
    } catch (error) {
      this.updateTabState(0, { loading: false, loadingMore: false, error: errMsg(error) });
    }
  }

  private async loadArticles(loadMore: boolean): Promise<void> {
    const st = this.tabState(1);
    if (!loadMore && st.loading) return;
    if (loadMore && (st.isEnd || st.loadingMore || st.nextUrl.length === 0)) return;
    this.updateTabState(1, { loading: !loadMore, loadingMore: loadMore });
    try {
      const page = await PeopleService.loadArticles(this.context(), this.identifier, this.articlesSort, loadMore ? st.nextUrl : undefined);
      this.articles = loadMore ? [...this.articles, ...page.items] : page.items;
      this.updateTabState(1, { loaded: true, loading: false, loadingMore: false, isEnd: page.isEnd, nextUrl: page.nextUrl, error: '' });
    } catch (error) {
      this.updateTabState(1, { loading: false, loadingMore: false, error: errMsg(error) });
    }
  }

  private async loadActivities(loadMore: boolean): Promise<void> {
    const st = this.tabState(2);
    if (!loadMore && st.loading) return;
    if (loadMore && (st.isEnd || st.loadingMore || st.nextUrl.length === 0)) return;
    this.updateTabState(2, { loading: !loadMore, loadingMore: loadMore });
    try {
      const page = await PeopleService.loadActivities(this.context(), this.identifier, loadMore ? st.nextUrl : undefined);
      this.activities = loadMore ? [...this.activities, ...page.items] : page.items;
      this.updateTabState(2, { loaded: true, loading: false, loadingMore: false, isEnd: page.isEnd, nextUrl: page.nextUrl, error: '' });
    } catch (error) {
      this.updateTabState(2, { loading: false, loadingMore: false, error: errMsg(error) });
    }
  }

  private async loadCollections(loadMore: boolean): Promise<void> {
    const st = this.tabState(3);
    if (!loadMore && st.loading) return;
    if (loadMore && (st.isEnd || st.loadingMore || st.nextUrl.length === 0)) return;
    this.updateTabState(3, { loading: !loadMore, loadingMore: loadMore });
    try {
      const page = await PeopleService.loadCollections(this.context(), this.identifier, loadMore ? st.nextUrl : undefined);
      this.collections = loadMore ? [...this.collections, ...page.items] : page.items;
      this.updateTabState(3, { loaded: true, loading: false, loadingMore: false, isEnd: page.isEnd, nextUrl: page.nextUrl, error: '' });
    } catch (error) {
      this.updateTabState(3, { loading: false, loadingMore: false, error: errMsg(error) });
    }
  }

  private async loadQuestions(loadMore: boolean): Promise<void> {
    const st = this.tabState(4);
    if (!loadMore && st.loading) return;
    if (loadMore && (st.isEnd || st.loadingMore || st.nextUrl.length === 0)) return;
    this.updateTabState(4, { loading: !loadMore, loadingMore: loadMore });
    try {
      const page = await PeopleService.loadQuestions(this.context(), this.identifier, loadMore ? st.nextUrl : undefined);
      this.questions = loadMore ? [...this.questions, ...page.items] : page.items;
      this.updateTabState(4, { loaded: true, loading: false, loadingMore: false, isEnd: page.isEnd, nextUrl: page.nextUrl, error: '' });
    } catch (error) {
      this.updateTabState(4, { loading: false, loadingMore: false, error: errMsg(error) });
    }
  }

  private async loadPins(loadMore: boolean): Promise<void> {
    const st = this.tabState(5);
    if (!loadMore && st.loading) return;
    if (loadMore && (st.isEnd || st.loadingMore || st.nextUrl.length === 0)) return;
    this.updateTabState(5, { loading: !loadMore, loadingMore: loadMore });
    try {
      const page = await PeopleService.loadPins(this.context(), this.identifier, loadMore ? st.nextUrl : undefined);
      // 保底：确保想法 summary 无残留 HTML（mapContentTarget 已调 stripHtml，此处双重保险）
      // 注意：ArkTS 禁止对象展开，逐字段构造新对象
      const cleaned: HomeFeedItem[] = [];
      for (const it of page.items) {
        if (it.type === 'pin' && it.summary.length > 0) {
          const s = PeopleService.stripHtml(it.summary);
          cleaned.push({
            id: it.id, type: it.type, title: it.title, summary: s,
            details: it.details, authorName: it.authorName, authorHeadline: it.authorHeadline,
            authorAvatarUrl: it.authorAvatarUrl, thumbnailUrl: it.thumbnailUrl,
            targetUrl: it.targetUrl, nativeTarget: it.nativeTarget,
            actionText: it.actionText, verb: it.verb, createdTime: it.createdTime,
            voteCount: it.voteCount, commentCount: it.commentCount,
            authorFollowing: it.authorFollowing
          });
        } else {
          cleaned.push(it);
        }
      }
      this.pins = loadMore ? [...this.pins, ...cleaned] : cleaned;
      this.updateTabState(5, { loaded: true, loading: false, loadingMore: false, isEnd: page.isEnd, nextUrl: page.nextUrl, error: '' });
    } catch (error) {
      this.updateTabState(5, { loading: false, loadingMore: false, error: errMsg(error) });
    }
  }

  private async loadColumns(loadMore: boolean): Promise<void> {
    const st = this.tabState(6);
    if (!loadMore && st.loading) return;
    if (loadMore && (st.isEnd || st.loadingMore || st.nextUrl.length === 0)) return;
    this.updateTabState(6, { loading: !loadMore, loadingMore: loadMore });
    try {
      const page = await PeopleService.loadColumns(this.context(), this.identifier, loadMore ? st.nextUrl : undefined);
      this.columns = loadMore ? [...this.columns, ...page.items] : page.items;
      this.updateTabState(6, { loaded: true, loading: false, loadingMore: false, isEnd: page.isEnd, nextUrl: page.nextUrl, error: '' });
    } catch (error) {
      this.updateTabState(6, { loading: false, loadingMore: false, error: errMsg(error) });
    }
  }

  private async loadFollowers(loadMore: boolean): Promise<void> {
    const st = this.tabState(7);
    if (!loadMore && st.loading) return;
    if (loadMore && (st.isEnd || st.loadingMore || st.nextUrl.length === 0)) return;
    this.updateTabState(7, { loading: !loadMore, loadingMore: loadMore });
    try {
      const page = await PeopleService.loadFollowers(this.context(), this.profile !== null ? this.profile.id : this.identifier, loadMore ? st.nextUrl : undefined);
      this.followers = loadMore ? [...this.followers, ...page.items] : page.items;
      this.updateTabState(7, { loaded: true, loading: false, loadingMore: false, isEnd: page.isEnd, nextUrl: page.nextUrl, error: '' });
    } catch (error) {
      this.updateTabState(7, { loading: false, loadingMore: false, error: errMsg(error) });
    }
  }

  private async loadFollowing(loadMore: boolean): Promise<void> {
    const st = this.tabState(8);
    if (!loadMore && st.loading) return;
    if (loadMore && (st.isEnd || st.loadingMore || st.nextUrl.length === 0)) return;
    this.updateTabState(8, { loading: !loadMore, loadingMore: loadMore });
    try {
      const page = await PeopleService.loadFollowing(this.context(), this.identifier, loadMore ? st.nextUrl : undefined);
      this.following = loadMore ? [...this.following, ...page.items] : page.items;
      this.updateTabState(8, { loaded: true, loading: false, loadingMore: false, isEnd: page.isEnd, nextUrl: page.nextUrl, error: '' });
    } catch (error) {
      this.updateTabState(8, { loading: false, loadingMore: false, error: errMsg(error) });
    }
  }

  private loadSubTab(index: number, loadMore: boolean): void {
    switch (index) {
      case 0: this.loadSubColumns(loadMore); break;
      case 1: this.loadSubTopics(loadMore); break;
      case 2: this.loadSubQuestions(loadMore); break;
      case 3: this.loadSubCollections(loadMore); break;
      default: break;
    }
  }

  private async loadSubColumns(loadMore: boolean): Promise<void> {
    const st = this.subState(0);
    if (!loadMore && st.loading) return;
    if (loadMore && (st.isEnd || st.loadingMore || st.nextUrl.length === 0)) return;
    this.updateSubState(0, { loading: !loadMore, loadingMore: loadMore });
    try {
      const page = await PeopleService.loadFollowingColumns(this.context(), this.identifier, loadMore ? st.nextUrl : undefined);
      this.subColumns = loadMore ? [...this.subColumns, ...page.items] : page.items;
      this.updateSubState(0, { loaded: true, loading: false, loadingMore: false, isEnd: page.isEnd, nextUrl: page.nextUrl, error: '' });
    } catch (error) {
      this.updateSubState(0, { loading: false, loadingMore: false, error: errMsg(error) });
    }
  }

  private async loadSubTopics(loadMore: boolean): Promise<void> {
    const st = this.subState(1);
    if (!loadMore && st.loading) return;
    if (loadMore && (st.isEnd || st.loadingMore || st.nextUrl.length === 0)) return;
    this.updateSubState(1, { loading: !loadMore, loadingMore: loadMore });
    try {
      const page = await PeopleService.loadFollowingTopics(this.context(), this.identifier, loadMore ? st.nextUrl : undefined);
      this.subTopics = loadMore ? [...this.subTopics, ...page.items] : page.items;
      this.updateSubState(1, { loaded: true, loading: false, loadingMore: false, isEnd: page.isEnd, nextUrl: page.nextUrl, error: '' });
    } catch (error) {
      this.updateSubState(1, { loading: false, loadingMore: false, error: errMsg(error) });
    }
  }

  private async loadSubQuestions(loadMore: boolean): Promise<void> {
    const st = this.subState(2);
    if (!loadMore && st.loading) return;
    if (loadMore && (st.isEnd || st.loadingMore || st.nextUrl.length === 0)) return;
    this.updateSubState(2, { loading: !loadMore, loadingMore: loadMore });
    try {
      const page = await PeopleService.loadFollowingQuestions(this.context(), this.identifier, loadMore ? st.nextUrl : undefined);
      this.subQuestions = loadMore ? [...this.subQuestions, ...page.items] : page.items;
      this.updateSubState(2, { loaded: true, loading: false, loadingMore: false, isEnd: page.isEnd, nextUrl: page.nextUrl, error: '' });
    } catch (error) {
      this.updateSubState(2, { loading: false, loadingMore: false, error: errMsg(error) });
    }
  }

  private async loadSubCollections(loadMore: boolean): Promise<void> {
    const st = this.subState(3);
    if (!loadMore && st.loading) return;
    if (loadMore && (st.isEnd || st.loadingMore || st.nextUrl.length === 0)) return;
    this.updateSubState(3, { loading: !loadMore, loadingMore: loadMore });
    try {
      const page = await PeopleService.loadFollowingCollections(this.context(), this.identifier, loadMore ? st.nextUrl : undefined);
      this.subCollections = loadMore ? [...this.subCollections, ...page.items] : page.items;
      this.updateSubState(3, { loaded: true, loading: false, loadingMore: false, isEnd: page.isEnd, nextUrl: page.nextUrl, error: '' });
    } catch (error) {
      this.updateSubState(3, { loading: false, loadingMore: false, error: errMsg(error) });
    }
  }

  // ---------- 关注 / 拉黑 ----------
  private patchProfile(patch: Partial<ZhihuPeopleProfile>): void {
    const base = this.profile;
    if (base === null) return;
    this.profile = {
      id: patch.id !== undefined ? patch.id : base.id,
      name: patch.name !== undefined ? patch.name : base.name,
      headline: patch.headline !== undefined ? patch.headline : base.headline,
      avatarUrl: patch.avatarUrl !== undefined ? patch.avatarUrl : base.avatarUrl,
      urlToken: patch.urlToken !== undefined ? patch.urlToken : base.urlToken,
      followerCount: patch.followerCount !== undefined ? patch.followerCount : base.followerCount,
      followingCount: patch.followingCount !== undefined ? patch.followingCount : base.followingCount,
      answerCount: patch.answerCount !== undefined ? patch.answerCount : base.answerCount,
      articleCount: patch.articleCount !== undefined ? patch.articleCount : base.articleCount,
      isFollowing: patch.isFollowing !== undefined ? patch.isFollowing : base.isFollowing,
      isBlocking: patch.isBlocking !== undefined ? patch.isBlocking : base.isBlocking,
      officialBadgeTitle: patch.officialBadgeTitle !== undefined ? patch.officialBadgeTitle : base.officialBadgeTitle,
      officialBadgeIcon: patch.officialBadgeIcon !== undefined ? patch.officialBadgeIcon : base.officialBadgeIcon,
      officialBadgeDetails: patch.officialBadgeDetails !== undefined ? patch.officialBadgeDetails : base.officialBadgeDetails,
      githubSocial: patch.githubSocial !== undefined ? patch.githubSocial : base.githubSocial
    };
  }

  private async doToggleFollow(): Promise<void> {
    if (this.profile === null || this.profile.urlToken.length === 0) return;
    if (this.isSelf) {
      this.showToast('无法关注自己');
      return;
    }
    const target = !this.profile.isFollowing;
    try {
      const result = await PeopleService.toggleFollow(this.context(), this.profile.urlToken, target);
      this.patchProfile({ isFollowing: result.isFollowing, followerCount: result.followerCount });
    } catch (error) {
      this.showToast(`操作失败：${errMsg(error)}`);
    }
  }

  private async doToggleBlock(): Promise<void> {
    if (this.profile === null || this.profile.urlToken.length === 0) return;
    if (this.isSelf) {
      this.showToast('无法拉黑自己');
      return;
    }
    const target = !this.profile.isBlocking;
    try {
      const result = await PeopleService.toggleBlock(this.context(), this.profile.urlToken, target);
      this.patchProfile({ isBlocking: result.isBlocking });
    } catch (error) {
      this.showToast(`操作失败：${errMsg(error)}`);
    }
  }

  // ---------- 跳转 ----------
  private openWeb(title: string, url: string): void {
    if (url.length === 0) {
      return;
    }
    router.pushUrl({ url: 'pages/WebContent', params: { title, url } });
  }

  private openNative(target: ZhihuCommentableTarget, title: string, fallbackUrl: string): void {
    if (target.kind === 'question') {
      router.pushUrl({ url: 'pages/Question', params: { questionId: target.id, title: target.title ?? '' } });
      return;
    }
    if (target.kind === 'pin') {
      router.pushUrl({ url: 'pages/Pin', params: { pinId: target.id, fallbackUrl: fallbackUrl } });
      return;
    }
    router.pushUrl({
      url: 'pages/Article',
      params: { target: serializeZhihuContentTarget(target), fallbackTitle: title, fallbackUrl }
    });
  }

  private openContent(item: HomeFeedItem): void {
    if (item.nativeTarget !== undefined) {
      this.openNative(item.nativeTarget, item.title, item.targetUrl);
      return;
    }
    this.openWeb(item.title, item.targetUrl);
  }

  private openCollection(collection: ZhihuCollection): void {
    if (collection.id.length === 0) {
      return;
    }
    router.pushUrl({ url: 'pages/CollectionDetail', params: { collectionId: collection.id, title: collection.title } });
  }

  private openColumn(column: ZhihuColumnSummary): void {
    // 强制使用网页端地址，API 返回的 url 是接口内链会导致展示 JSON 乱码
    this.openWeb(column.title, `https://zhuanlan.zhihu.com/${column.id}`);
  }

  private openPerson(summary: ZhihuPeopleSummary): void {
    const token = summary.urlToken.length > 0 ? summary.urlToken : summary.id;
    router.pushUrl({ url: 'pages/People', params: { urlToken: token } });
  }

  private openTopic(topic: ZhihuTopicSummary): void {
    this.openWeb(topic.name, `https://www.zhihu.com/topic/${topic.id}`);
  }

  private openFollowedQuestion(item: ZhihuFollowedQuestionSummary): void {
    router.pushUrl({ url: 'pages/Question', params: { questionId: item.id, title: item.title } });
  }

  // ---------- 通用 Feed 卡片 ----------
  @Builder
  private FeedCard(item: HomeFeedItem): void {
    Column({ space: 10 }) {
      if (item.title.length > 0) {
        Text(item.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .lineHeight(24)
          .fontColor($r('app.color.text_primary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      if (item.summary.length > 0) {
        Text(item.summary)
          .fontSize(13)
          .lineHeight(20)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      Row({ space: 10 }) {
        Text(item.details)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .alignSelf(ItemAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .border({ width: 1, color: $r('app.color.card_border') })
    .borderRadius(18)
    .onClick(() => {
      this.openContent(item);
    })
  }

  // ---------- Footer（各 tab 复用，读取对应 tabState）----------
  @Builder
  private Footer(stateIndex: number): void {
    if (this.tabState(stateIndex).loading && !this.tabState(stateIndex).loaded) {
      Text('正在加载…')
        .fontSize(13).fontColor($r('app.color.text_secondary'))
        .width('100%').textAlign(TextAlign.Center).padding({ top: 24, bottom: 24 })
        .onClick(() => {})
    } else if (this.tabState(stateIndex).error.length > 0 && this.feedCountFor(stateIndex) === 0) {
      Column({ space: 12 }) {
        Text(this.tabState(stateIndex).error).fontSize(14).fontColor($r('app.color.error_text')).textAlign(TextAlign.Center)
        Text('重新加载')
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.action_text'))
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.action_background')).borderRadius(18)
          .onClick(() => { this.loadTab(stateIndex, false); })
      }
      .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 40, bottom: 40 })
    } else if (this.feedCountFor(stateIndex) === 0 && this.tabState(stateIndex).loaded) {
      Text('这里还没有内容')
        .fontSize(14).fontColor($r('app.color.text_secondary'))
        .width('100%').textAlign(TextAlign.Center).padding({ top: 40, bottom: 40 })
    } else if (this.tabState(stateIndex).loadingMore) {
      Text('正在加载更多…')
        .fontSize(12).fontColor($r('app.color.text_secondary'))
        .width('100%').textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
    } else if (this.tabState(stateIndex).isEnd) {
      Text('没有更多了')
        .fontSize(12).fontColor($r('app.color.text_tertiary'))
        .width('100%').textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
    } else {
      Text('加载更多')
        .fontSize(12).fontColor($r('app.color.action_text'))
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
        .borderRadius(16).border({ width: 1, color: $r('app.color.card_border') })
        .onClick(() => { this.loadTab(stateIndex, true); })
        .margin({ top: 8, bottom: 8 })
    }
  }

  private feedCountFor(index: number): number {
    switch (index) {
      case 0: return this.answers.length;
      case 1: return this.articles.length;
      case 2: return this.activities.length;
      case 3: return this.collections.length;
      case 4: return this.questions.length;
      case 5: return this.pins.length;
      case 6: return this.columns.length;
      case 7: return this.followers.length;
      case 8: return this.following.length;
      default: return 0;
    }
  }

  // ---------- 各 tab 列表（无参 Builder，读取对应 @State）----------
  @Builder
  private AnswersList(): void {
    List({ space: 12, scroller: this.answersScroller }) {
      ListItem() { this.AnswersSortBar(); }
      ForEach(this.answers, (item: HomeFeedItem) => {
        ListItem() { this.FeedCard(item); }
      }, (item: HomeFeedItem) => item.id)
      ListItem() { this.Footer(0); }
    }
    .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onScroll(this.makeProfileScrollHandler(this.answersScroller))
      .onReachEnd(() => { this.loadAnswers(true); })
    .padding({ left: 16, right: 16, top: 12 })
  }

  @Builder
  private ArticlesList(): void {
    List({ space: 12, scroller: this.articlesScroller }) {
      ListItem() { this.ArticlesSortBar(); }
      ForEach(this.articles, (item: HomeFeedItem) => {
        ListItem() { this.FeedCard(item); }
      }, (item: HomeFeedItem) => item.id)
      ListItem() { this.Footer(1); }
    }
    .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onScroll(this.makeProfileScrollHandler(this.articlesScroller))
      .onReachEnd(() => { this.loadArticles(true); })
    .padding({ left: 16, right: 16, top: 12 })
  }

  @Builder
  private ActivitiesList(): void {
    List({ space: 12, scroller: this.activitiesScroller }) {
      ForEach(this.activities, (item: HomeFeedItem) => {
        ListItem() { this.FeedCard(item); }
      }, (item: HomeFeedItem) => item.id)
      ListItem() { this.Footer(2); }
    }
    .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onScroll(this.makeProfileScrollHandler(this.activitiesScroller))
      .onReachEnd(() => { this.loadActivities(true); })
    .padding({ left: 16, right: 16, top: 12 })
  }

  @Builder
  private QuestionsList(): void {
    List({ space: 12, scroller: this.questionsScroller }) {
      ForEach(this.questions, (item: HomeFeedItem) => {
        ListItem() { this.FeedCard(item); }
      }, (item: HomeFeedItem) => item.id)
      ListItem() { this.Footer(4); }
    }
    .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onScroll(this.makeProfileScrollHandler(this.questionsScroller))
      .onReachEnd(() => { this.loadQuestions(true); })
    .padding({ left: 16, right: 16, top: 12 })
  }

  @Builder
  private PinsList(): void {
    List({ space: 12, scroller: this.pinsScroller }) {
      ForEach(this.pins, (item: HomeFeedItem) => {
        ListItem() { this.FeedCard(item); }
      }, (item: HomeFeedItem) => item.id)
      ListItem() { this.Footer(5); }
    }
    .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onScroll(this.makeProfileScrollHandler(this.pinsScroller))
      .onReachEnd(() => { this.loadPins(true); })
    .padding({ left: 16, right: 16, top: 12 })
  }

  @Builder
  private CollectionsList(): void {
    List({ space: 12, scroller: this.collectionsScroller }) {
      ForEach(this.collections, (c: ZhihuCollection) => {
        ListItem() { this.CollectionCard(c); }
      }, (c: ZhihuCollection) => c.id)
      ListItem() { this.Footer(3); }
    }
    .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onScroll(this.makeProfileScrollHandler(this.collectionsScroller))
      .onReachEnd(() => { this.loadCollections(true); })
    .padding({ left: 16, right: 16, top: 12 })
  }

  @Builder
  private ColumnsList(): void {
    List({ space: 12, scroller: this.columnsScroller }) {
      ForEach(this.columns, (c: ZhihuColumnSummary) => {
        ListItem() { this.ColumnCard(c); }
      }, (c: ZhihuColumnSummary) => c.id)
      ListItem() { this.Footer(6); }
    }
    .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onScroll(this.makeProfileScrollHandler(this.columnsScroller))
      .onReachEnd(() => { this.loadColumns(true); })
    .padding({ left: 16, right: 16, top: 12 })
  }

  @Builder
  private FollowersList(): void {
    List({ space: 12, scroller: this.followersScroller }) {
      ForEach(this.followers, (p: ZhihuPeopleSummary) => {
        ListItem() { this.PersonCard(p); }
      }, (p: ZhihuPeopleSummary) => p.id)
      ListItem() { this.Footer(7); }
    }
    .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onScroll(this.makeProfileScrollHandler(this.followersScroller))
      .onReachEnd(() => { this.loadFollowers(true); })
    .padding({ left: 16, right: 16, top: 12 })
  }

  @Builder
  private FollowingList(): void {
    List({ space: 12, scroller: this.followingScroller }) {
      ForEach(this.following, (p: ZhihuPeopleSummary) => {
        ListItem() { this.PersonCard(p); }
      }, (p: ZhihuPeopleSummary) => p.id)
      ListItem() { this.Footer(8); }
    }
    .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onScroll(this.makeProfileScrollHandler(this.followingScroller))
      .onReachEnd(() => { this.loadFollowing(true); })
    .padding({ left: 16, right: 16, top: 12 })
  }

  // ---------- 收藏夹 / 专栏 / 人物 卡片 ----------
  @Builder
  private CollectionCard(collection: ZhihuCollection): void {
    Column({ space: 4 }) {
      Text(collection.title)
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (collection.description.length > 0) {
        Text(collection.description)
          .fontSize(13).fontColor($r('app.color.text_secondary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Row({ space: 12 }) {
        Text(formatCounter(collection.itemCount, ' 篇内容')).fontSize(12).fontColor($r('app.color.text_secondary'))
        if (collection.likeCount > 0) {
          Text(formatCounter(collection.likeCount, ' 赞同')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }
      }
      .width('100%').alignItems(VerticalAlign.Center)
    }
    .width('100%').padding(16).backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .borderRadius(16).border({ width: 1, color: $r('app.color.card_border') })
    .onClick(() => { this.openCollection(collection); })
  }

  @Builder
  private ColumnCard(column: ZhihuColumnSummary): void {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(column.title)
          .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (column.description.length > 0) {
          Text(column.description)
            .fontSize(13).fontColor($r('app.color.text_secondary'))
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Text(`${formatCounter(column.articlesCount, ' 文章')} · ${formatCounter(column.followerCount, ' 关注')}`)
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%').padding(16).backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .borderRadius(16).border({ width: 1, color: $r('app.color.card_border') })
    .onClick(() => { this.openColumn(column); })
  }

  @Builder
  private PersonCard(person: ZhihuPeopleSummary): void {
    Row({ space: 12 }) {
      if (person.avatarUrl.length > 0) {
        Image(person.avatarUrl)
          .width(48).height(48).objectFit(ImageFit.Cover).borderRadius(24).clip(true)
      } else {
        Column() {
          Text(person.name.slice(0, 1))
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.action_text'))
        }
        .width(48).height(48).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .backgroundColor($r('app.color.action_background')).borderRadius(24)
      }

      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(person.name)
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          if (person.officialBadgeTitle.length > 0) {
            Text(person.officialBadgeTitle)
              .fontSize(11).fontColor($r('app.color.action_text'))
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .backgroundColor($r('app.color.action_background')).borderRadius(10)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%').alignItems(VerticalAlign.Center)

        if (person.headline.length > 0) {
          Text(person.headline)
            .fontSize(13).fontColor($r('app.color.text_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Row({ space: 14 }) {
          Text(`${person.answerCount} 回答`).fontSize(12).fontColor($r('app.color.text_secondary'))
          Text(`${person.articleCount} 文章`).fontSize(12).fontColor($r('app.color.text_secondary'))
          Text(`${person.followerCount} 粉丝`).fontSize(12).fontColor($r('app.color.text_secondary'))
        }
        .width('100%').padding({ top: 2 })
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)

      Text('查看')
        .fontSize(13).fontColor($r('app.color.action_text'))
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.action_background')).borderRadius(16)
        .onClick(() => { this.openPerson(person); })
    }
    .width('100%').padding(16).backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .borderRadius(16).border({ width: 1, color: $r('app.color.card_border') })
    .onClick(() => { this.openPerson(person); })
  }

  // ---------- 关注订阅子页 ----------
  @Builder
  private SubscriptionsContent(): void {
    Column() {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.subTitles, (title: string, index: number) => {
            Text(title)
              .fontSize(13)
              .fontColor(this.subTab === index ? $r('app.color.action_text') : $r('app.color.text_secondary'))
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .backgroundColor(this.subTab === index ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
              .borderRadius(16)
              .onClick(() => {
                this.subTab = index;
                this.ensureSubLoaded(index);
              })
          }, (title: string, index: number) => `${index}-${title}`)
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

      if (this.subTab === 0) {
        this.SubColumnsList()
      } else if (this.subTab === 1) {
        this.SubTopicsList()
      } else if (this.subTab === 2) {
        this.SubQuestionsList()
      } else {
        this.SubCollectionsList()
      }
    }
    .width('100%').height('100%')
  }

  @Builder
  private SubColumnsList(): void {
    List({ space: 12, scroller: this.subColumnsScroller }) {
      ForEach(this.subColumns, (c: ZhihuColumnSummary) => {
        ListItem() { this.ColumnCard(c); }
      }, (c: ZhihuColumnSummary) => c.id)
      ListItem() { this.SubFooter(0); }
    }
    .width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onScroll(this.makeProfileScrollHandler(this.subColumnsScroller))
      .onReachEnd(() => { this.loadSubColumns(true); })
    .padding({ left: 16, right: 16, top: 12 })
  }

  @Builder
  private SubTopicsList(): void {
    List({ space: 12, scroller: this.subTopicsScroller }) {
      ForEach(this.subTopics, (t: ZhihuTopicSummary) => {
        ListItem() { this.TopicCard(t); }
      }, (t: ZhihuTopicSummary) => t.id)
      ListItem() { this.SubFooter(1); }
    }
    .width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onScroll(this.makeProfileScrollHandler(this.subTopicsScroller))
      .onReachEnd(() => { this.loadSubTopics(true); })
    .padding({ left: 16, right: 16, top: 12 })
  }

  @Builder
  private SubQuestionsList(): void {
    List({ space: 12, scroller: this.subQuestionsScroller }) {
      ForEach(this.subQuestions, (q: ZhihuFollowedQuestionSummary) => {
        ListItem() { this.FollowedQuestionCard(q); }
      }, (q: ZhihuFollowedQuestionSummary) => q.id)
      ListItem() { this.SubFooter(2); }
    }
    .width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onScroll(this.makeProfileScrollHandler(this.subQuestionsScroller))
      .onReachEnd(() => { this.loadSubQuestions(true); })
    .padding({ left: 16, right: 16, top: 12 })
  }

  @Builder
  private SubCollectionsList(): void {
    List({ space: 12, scroller: this.subCollectionsScroller }) {
      ForEach(this.subCollections, (c: ZhihuCollection) => {
        ListItem() { this.CollectionCard(c); }
      }, (c: ZhihuCollection) => c.id)
      ListItem() { this.SubFooter(3); }
    }
    .width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onScroll(this.makeProfileScrollHandler(this.subCollectionsScroller))
      .onReachEnd(() => { this.loadSubCollections(true); })
    .padding({ left: 16, right: 16, top: 12 })
  }

  @Builder
  private TopicCard(topic: ZhihuTopicSummary): void {
    Row({ space: 12 }) {
      if (topic.avatarUrl.length > 0) {
        Image(topic.avatarUrl).width(40).height(40).objectFit(ImageFit.Cover).borderRadius(20).clip(true)
      }
      Text(topic.name)
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%').padding(16).backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .borderRadius(16).border({ width: 1, color: $r('app.color.card_border') })
    .onClick(() => { this.openTopic(topic); })
  }

  @Builder
  private FollowedQuestionCard(question: ZhihuFollowedQuestionSummary): void {
    Text(question.title)
      .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%').padding(16).backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .borderRadius(16).border({ width: 1, color: $r('app.color.card_border') })
      .onClick(() => { this.openFollowedQuestion(question); })
  }

  @Builder
  private SubFooter(stateIndex: number): void {
    if (this.subState(stateIndex).loading && !this.subState(stateIndex).loaded) {
      Text('正在加载…').fontSize(13).fontColor($r('app.color.text_secondary'))
        .width('100%').textAlign(TextAlign.Center).padding({ top: 24, bottom: 24 })
    } else if (this.subState(stateIndex).error.length > 0 && this.subItemCount(stateIndex) === 0) {
      Column({ space: 12 }) {
        Text(this.subState(stateIndex).error).fontSize(14).fontColor($r('app.color.error_text')).textAlign(TextAlign.Center)
        Text('重新加载')
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.action_text'))
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.action_background')).borderRadius(18)
          .onClick(() => { this.loadSubTab(stateIndex, false); })
      }
      .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 40, bottom: 40 })
    } else if (this.subItemCount(stateIndex) === 0 && this.subState(stateIndex).loaded) {
      Text('这里还没有内容')
        .fontSize(14).fontColor($r('app.color.text_secondary'))
        .width('100%').textAlign(TextAlign.Center).padding({ top: 40, bottom: 40 })
    } else if (this.subState(stateIndex).loadingMore) {
      Text('正在加载更多…').fontSize(12).fontColor($r('app.color.text_secondary'))
        .width('100%').textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
    } else if (this.subState(stateIndex).isEnd) {
      Text('没有更多了').fontSize(12).fontColor($r('app.color.text_tertiary'))
        .width('100%').textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
    } else {
      Text('加载更多')
        .fontSize(12).fontColor($r('app.color.action_text'))
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
        .borderRadius(16).border({ width: 1, color: $r('app.color.card_border') })
        .onClick(() => { this.loadSubTab(stateIndex, true); })
        .margin({ top: 8, bottom: 8 })
    }
  }

  private subItemCount(index: number): number {
    switch (index) {
      case 0: return this.subColumns.length;
      case 1: return this.subTopics.length;
      case 2: return this.subQuestions.length;
      case 3: return this.subCollections.length;
      default: return 0;
    }
  }

  // ---------- 资料头部 ----------
  @Builder
  private ProfileHeader(): void {
    if (this.profileLoading) {
      Text('正在加载个人资料…')
        .fontSize(14).fontColor($r('app.color.text_secondary'))
        .width('100%').textAlign(TextAlign.Center).padding({ top: 40, bottom: 40 })
    } else if (this.profileError.length > 0) {
      Column({ space: 12 }) {
        Text(this.profileError).fontSize(14).fontColor($r('app.color.error_text')).textAlign(TextAlign.Center)
        Text('重新加载')
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.action_text'))
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.action_background')).borderRadius(18)
          .onClick(() => { this.loadProfile(); })
      }
      .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 40, bottom: 40 })
    } else if (this.profile !== null) {
      this.ProfileBody(this.profile)
    }
  }

  @Builder
  private ProfileBody(profile: ZhihuPeopleProfile): void {
    Column({ space: 12 }) {
      Row({ space: 16 }) {
        if (profile.avatarUrl.length > 0) {
          Image(profile.avatarUrl)
            .width(80).height(80).objectFit(ImageFit.Cover).borderRadius(40).clip(true)
        } else {
          Column() {
            Text(profile.name.slice(0, 1))
              .fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.action_text'))
          }
          .width(80).height(80).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.action_background')).borderRadius(40)
        }

        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text(profile.name)
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            if (profile.officialBadgeTitle.length > 0) {
              Text(profile.officialBadgeTitle)
                .fontSize(11).fontColor($r('app.color.action_text'))
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .backgroundColor($r('app.color.action_background')).borderRadius(10)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width('100%').alignItems(VerticalAlign.Center)

          if (profile.headline.length > 0) {
            Text(profile.headline)
              .fontSize(13).fontColor($r('app.color.text_secondary'))
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          ForEach(profile.officialBadgeDetails, (badge: OfficialBadgeDetail) => {
            Row({ space: 6 }) {
              if (badge.iconUrl.length > 0) {
                Image(badge.iconUrl).width(16).height(16).objectFit(ImageFit.Contain)
              }
              Text(`${badge.title}：${badge.description}`)
                .fontSize(12).fontColor($r('app.color.text_secondary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            }
            .width('100%').alignItems(VerticalAlign.Center)
          }, (badge: OfficialBadgeDetail) => badge.title + badge.description)

          if (profile.githubSocial !== undefined) {
            Row({ space: 4 }) {
              if (profile.githubSocial.iconUrl.length > 0) {
                Image(profile.githubSocial.iconUrl).width(16).height(16).objectFit(ImageFit.Contain)
              }
              Text(profile.githubSocial.title)
                .fontSize(12).fontColor($r('app.color.text_secondary')).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              Text(`· ${profile.githubSocial.starCount} stars`)
                .fontSize(12).fontColor($r('app.color.text_secondary')).maxLines(1)
            }
            .width('100%').alignItems(VerticalAlign.Center)
            .onClick(() => { this.openWeb(profile.githubSocial!.title, profile.githubSocial!.profileUrl); })
          }
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)

        // 右上角：搜索 TA 的创作（对齐安卓，而非全站搜索）
        Image($r('app.media.ic_search'))
          .width(22).height(22).renderMode(ImageRenderMode.Template)
          .fillColor($r('app.color.text_secondary')).syncLoad(true)
          .onClick(() => {
            router.pushUrl({
              url: 'pages/Search',
              params: { scopeMemberHashId: profile.id, scopeMemberName: profile.name }
            });
          })
      }
      .width('100%').alignItems(VerticalAlign.Top)

      // 统计行
      Row({ space: 8 }) {
        this.StatItem('回答', profile.answerCount, 0)
        this.StatItem('文章', profile.articleCount, 1)
        this.StatItem('粉丝', profile.followerCount, 7)
        this.StatItem('关注', profile.followingCount, 8)
      }
      .width('100%')
      .padding({ top: 8 })

      // 操作按钮（仅查看他人时显示：关注 / 拉黑 / 屏蔽推荐 / 屏蔽提问者）
      if (!this.isSelf) {
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(10) } }) {
          // 关注：蓝胶囊=可关注，灰胶囊=已关注（中性，明确区分）
          Text(profile.isFollowing ? '已关注' : '关注')
            .fontSize(14)
            .fontColor(profile.isFollowing ? $r('app.color.text_secondary') : $r('app.color.action_text'))
            .padding({ left: 18, right: 18, top: 8, bottom: 8 })
            .backgroundColor(profile.isFollowing ? ThemeColors.cardBackground(this.oledBlack, this.isDark) : $r('app.color.action_background'))
            .border({ width: 1, color: profile.isFollowing ? $r('app.color.card_border') : $r('app.color.action_background') })
            .borderRadius(18)
            .onClick(() => { this.doToggleFollow(); })
          // 拉黑：红=已拉黑，灰描边=未拉黑
          Text(profile.isBlocking ? '已拉黑' : '拉黑')
            .fontSize(14)
            .fontColor(profile.isBlocking ? '#E24B4A' : $r('app.color.text_secondary'))
            .padding({ left: 18, right: 18, top: 8, bottom: 8 })
            .backgroundColor(profile.isBlocking ? '#FCEBEB' : ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({ width: 1, color: profile.isBlocking ? '#E24B4A' : $r('app.color.card_border') })
            .borderRadius(18)
            .onClick(() => { this.doToggleBlock(); })
          // 屏蔽推荐（本地，对齐安卓 isUserBlocked）
          Text(this.blockedInRecommendations ? '取消屏蔽推荐' : '屏蔽推荐')
            .fontSize(14)
            .fontColor(this.blockedInRecommendations ? '#E24B4A' : $r('app.color.text_secondary'))
            .padding({ left: 18, right: 18, top: 8, bottom: 8 })
            .backgroundColor(this.blockedInRecommendations ? '#FCEBEB' : ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({ width: 1, color: this.blockedInRecommendations ? '#E24B4A' : $r('app.color.card_border') })
            .borderRadius(18)
            .onClick(() => { this.doToggleRecommendationBlock(); })
          // 屏蔽提问者（本地，对齐安卓 isQuestionAuthorBlocked）
          Text(this.blockedAsQuestionAuthor ? '取消屏蔽提问者' : '屏蔽提问者')
            .fontSize(14)
            .fontColor(this.blockedAsQuestionAuthor ? '#E24B4A' : $r('app.color.text_secondary'))
            .padding({ left: 18, right: 18, top: 8, bottom: 8 })
            .backgroundColor(this.blockedAsQuestionAuthor ? '#FCEBEB' : ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({ width: 1, color: this.blockedAsQuestionAuthor ? '#E24B4A' : $r('app.color.card_border') })
            .borderRadius(18)
            .onClick(() => { this.doToggleQuestionAuthorBlock(); })
        }
        .width('100%').padding({ top: 4 })
      }
    }
    .width('100%').padding(16).backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .borderRadius(16).border({ width: 1, color: $r('app.color.card_border') })
  }

  @Builder
  private StatItem(label: string, value: number, tabIndex: number): void {
    Column({ space: 2 }) {
      Text(`${value}`)
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Text(label)
        .fontSize(12).fontColor($r('app.color.text_secondary'))
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
    .onClick(() => {
      this.selectedTab = tabIndex;
      this.peopleTabsController.changeIndex(this.logicalToTabsIndex(tabIndex));
      this.ensureTabLoaded(tabIndex);
    })
  }

  // ---------- 排序条（回答 / 文章，置于列表顶部，跟随内容滚动，对齐安卓布局）----------
  @Builder
  private AnswersSortBar(): void {
    Row({ space: 8 }) {
      Text('按热度')
        .fontSize(13)
        .fontColor(this.answersSort === 'voteups' ? $r('app.color.action_text') : $r('app.color.text_secondary'))
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor(this.answersSort === 'voteups' ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .borderRadius(16)
        .onClick(() => { this.answersSort = 'voteups'; this.loadAnswers(false); })
      Text('按时间')
        .fontSize(13)
        .fontColor(this.answersSort === 'created' ? $r('app.color.action_text') : $r('app.color.text_secondary'))
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor(this.answersSort === 'created' ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .borderRadius(16)
        .onClick(() => { this.answersSort = 'created'; this.loadAnswers(false); })
    }
    .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 4 })
  }

  @Builder
  private ArticlesSortBar(): void {
    Row({ space: 8 }) {
      Text('按热度')
        .fontSize(13)
        .fontColor(this.articlesSort === 'voteups' ? $r('app.color.action_text') : $r('app.color.text_secondary'))
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor(this.articlesSort === 'voteups' ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .borderRadius(16)
        .onClick(() => { this.articlesSort = 'voteups'; this.loadArticles(false); })
      Text('按时间')
        .fontSize(13)
        .fontColor(this.articlesSort === 'created' ? $r('app.color.action_text') : $r('app.color.text_secondary'))
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor(this.articlesSort === 'created' ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .borderRadius(16)
        .onClick(() => { this.articlesSort = 'created'; this.loadArticles(false); })
    }
    .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 4 })
  }

  build() {
    Column() {
      // 个人卡片（头像/统计/按钮）：折叠时高度归零而非 Visibility.None，避免 Tabs 布局受影响
      Column() {
        this.ProfileHeader()
      }
      .padding({ left: 16, right: 16, top: this.topSafeAreaVp + 12 })
      .height(this.profileHeaderVisible ? 'auto' : 0)
      .clip(true)

      Tabs({ controller: this.peopleTabsController, barPosition: BarPosition.Start, index: this.logicalToTabsIndex(this.selectedTab) }) {
        ForEach(this.visibleTabIndices(), (logical: number) => {
          TabContent() {
            this.TabContentBody(logical)
          }.tabBar(this.TabLabel(logical))
        }, (logical: number) => `${logical}`)
      }
      .barMode(BarMode.Scrollable)
      .width('100%')
      .layoutWeight(1)
      .onChange((index: number) => {
        const logical = this.tabsIndexToLogical(index);
        this.selectedTab = logical;
        this.ensureTabLoaded(logical);
        // 切换 tab 后按新列表当前滚动位置复位个人卡片显隐
        const y: number = this.scrollerForTab(logical).currentOffset().yOffset;
        this.profileHeaderVisible = y <= 8;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private visibleTabIndices(): number[] {
    return this.isSelf
      ? [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
      : [0, 1, 2, 4, 5, 6, 7, 8];
  }

  private tabsIndexToLogical(index: number): number {
    const v = this.visibleTabIndices();
    return index >= 0 && index < v.length ? v[index] : index;
  }

  private logicalToTabsIndex(logical: number): number {
    const idx = this.visibleTabIndices().indexOf(logical);
    return idx >= 0 ? idx : 0;
  }

  // 列表滚动回调：用 ListScroller 绝对偏移判断（onScroll 的参数是每帧增量，不能用于阈值判断）
  // 到顶附近（yOffset<=8）显示个人卡片；下滚即隐藏；中间上滚不触发（只有回到顶部才重现）
  private makeProfileScrollHandler(scroller: ListScroller): (offset: number, state: ScrollState) => void {
    return (_delta: number, _state: ScrollState): void => {
      const y: number = scroller.currentOffset().yOffset;
      const shouldShow: boolean = y <= 8;
      if (shouldShow !== this.profileHeaderVisible) {
        this.profileHeaderVisible = shouldShow;
      }
    };
  }

  // logical tab → 对应列表的 ListScroller（用于读取绝对滚动偏移）
  private scrollerForTab(logical: number): ListScroller {
    switch (logical) {
      case 0: return this.answersScroller;
      case 1: return this.articlesScroller;
      case 2: return this.activitiesScroller;
      case 3: return this.collectionsScroller;
      case 4: return this.questionsScroller;
      case 5: return this.pinsScroller;
      case 6: return this.columnsScroller;
      case 7: return this.followersScroller;
      case 8: return this.followingScroller;
      case 9:
        switch (this.subTab) {
          case 0: return this.subColumnsScroller;
          case 1: return this.subTopicsScroller;
          case 2: return this.subQuestionsScroller;
          default: return this.subCollectionsScroller;
        }
      default: return this.answersScroller;
    }
  }

  @Builder
  private TabContentBody(logical: number): void {
    if (logical === 0) { this.AnswersList(); }
    else if (logical === 1) { this.ArticlesList(); }
    else if (logical === 2) { this.ActivitiesList(); }
    else if (logical === 3) { this.CollectionsList(); }
    else if (logical === 4) { this.QuestionsList(); }
    else if (logical === 5) { this.PinsList(); }
    else if (logical === 6) { this.ColumnsList(); }
    else if (logical === 7) { this.FollowersList(); }
    else if (logical === 8) { this.FollowingList(); }
    else if (logical === 9) { this.SubscriptionsContent(); }
  }

  @Builder
  private TabLabel(index: number): void {
    Text(this.tabTitles[index])
      .fontSize(15)
      .fontWeight(this.selectedTab === index ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.selectedTab === index ? $r('app.color.action_text') : $r('app.color.text_secondary'))
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
  }
}
