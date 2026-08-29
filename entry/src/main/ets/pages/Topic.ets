import common from '@ohos.app.ability.common';
import { promptAction, router } from '@kit.ArkUI';
import { AppearanceThemeMode } from '../services/AppearanceSettingsRepository';
import { ThemeColors } from '../services/ThemeColors';
import { DEFAULT_SESSION_SNAPSHOT, HomeFeedItem, SessionSnapshot, TopicDetail } from '../models/ZhihuModels';
import { TopicFeedTab, TopicIdeasSort, TopicService, TopicDiscussionSort } from '../services/TopicService';
import { openZhihuContentTarget } from '../services/ZhihuNavigation';

interface TopicPageParams {
  readonly topicId?: string;
  readonly topicName?: string;
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

@Entry
@Component
struct Topic {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageProp('bottomSafeAreaVp') private bottomSafeAreaVp: number = 0;
  @StorageProp('themeMode') private themeMode: AppearanceThemeMode = 'system';
  @StorageProp('sessionSnapshot') private sessionSnapshot: SessionSnapshot = DEFAULT_SESSION_SNAPSHOT;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;

  @State private topicId: string = '';
  @State private topicName: string = '';
  @State private detail: TopicDetail | null = null;
  @State private detailLoading: boolean = false;
  @State private detailError: string = '';

  @State private selectedTab: number = 0; // 0=讨论 1=想法 2=待回答
  @State private discussionSort: TopicDiscussionSort = 'essence';
  @State private ideasSort: TopicIdeasSort = 'hot';

  // 各 tab 分页状态（索引对应 0/1/2）
  @State private feedItems: HomeFeedItem[][] = [[], [], []];
  @State private feedNextUrl: string[] = ['', '', ''];
  @State private feedIsEnd: boolean[] = [false, false, false];
  @State private feedLoading: boolean[] = [false, false, false];
  @State private feedLoaded: boolean[] = [false, false, false];
  @State private feedError: string[] = ['', '', ''];

  @State private excerptExpanded: boolean = false;

  private readonly tabTitles: string[] = ['讨论', '想法', '待回答'];
  private readonly scroller: ListScroller = new ListScroller();

  aboutToAppear(): void {
    const rawParams = router.getParams();
    const empty: TopicPageParams = {};
    const params: TopicPageParams = rawParams !== undefined && rawParams !== null
      ? rawParams as TopicPageParams
      : empty;
    this.topicId = typeof params.topicId === 'string' ? params.topicId : '';
    this.topicName = typeof params.topicName === 'string' ? params.topicName : '';
    if (this.topicId.length > 0) {
      this.loadDetail();
      this.ensureTabLoaded(0);
    }
  }

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  private showToast(message: string): void {
    promptAction.showToast({ message, duration: 1800 });
  }

  // ---------- 详情 ----------
  private async loadDetail(): Promise<void> {
    if (this.topicId.length === 0) {
      return;
    }
    this.detailLoading = true;
    this.detailError = '';
    try {
      const d = await TopicService.getTopicDetail(this.context(), this.topicId);
      this.detail = d;
      if (d.name.length > 0) {
        this.topicName = d.name;
      }
    } catch (error) {
      this.detailError = `话题详情加载失败：${errMsg(error)}`;
    } finally {
      this.detailLoading = false;
    }
  }

  private patchDetail(patch: Partial<TopicDetail>): void {
    const base = this.detail;
    if (base === null) {
      return;
    }
    this.detail = {
      id: patch.id !== undefined ? patch.id : base.id,
      name: patch.name !== undefined ? patch.name : base.name,
      excerpt: patch.excerpt !== undefined ? patch.excerpt : base.excerpt,
      avatarUrl: patch.avatarUrl !== undefined ? patch.avatarUrl : base.avatarUrl,
      followersCount: patch.followersCount !== undefined ? patch.followersCount : base.followersCount,
      questionsCount: patch.questionsCount !== undefined ? patch.questionsCount : base.questionsCount,
      isFollowing: patch.isFollowing !== undefined ? patch.isFollowing : base.isFollowing,
      topicId: patch.topicId !== undefined ? patch.topicId : base.topicId,
      totalPv: patch.totalPv !== undefined ? patch.totalPv : base.totalPv,
      discussCount: patch.discussCount !== undefined ? patch.discussCount : base.discussCount
    };
  }

  private async doToggleFollow(): Promise<void> {
    if (this.detail === null || this.topicId.length === 0) {
      return;
    }
    const target = !this.detail.isFollowing;
    // 乐观更新
    this.patchDetail({ isFollowing: target, followersCount: this.detail.followersCount + (target ? 1 : -1) });
    try {
      const result = await TopicService.toggleFollowTopic(this.context(), this.topicId, target);
      if (result.followerCount >= 0) {
        this.patchDetail({ isFollowing: result.isFollowing, followersCount: result.followerCount });
      } else {
        this.patchDetail({ isFollowing: result.isFollowing });
      }
    } catch (error) {
      // 失败回滚
      this.patchDetail({ isFollowing: !target, followersCount: this.detail.followersCount + (target ? -1 : 1) });
      this.showToast(`操作失败：${errMsg(error)}`);
    }
  }

  // ---------- Tab / Feed ----------
  private tabToFeedTab(index: number): TopicFeedTab {
    if (index === 1) return 'ideas';
    if (index === 2) return 'unanswered';
    return 'discussion';
  }

  private currentSort(index: number): string {
    if (index === 0) return this.discussionSort;
    if (index === 1) return this.ideasSort;
    return '';
  }

  private ensureTabLoaded(index: number): void {
    if (!this.feedLoaded[index] && !this.feedLoading[index]) {
      this.loadFeed(index, false);
    }
  }

  private async loadFeed(index: number, loadMore: boolean): Promise<void> {
    if (this.topicId.length === 0) {
      return;
    }
    if (!loadMore && this.feedLoading[index]) {
      return;
    }
    if (loadMore && (this.feedIsEnd[index] || this.feedLoading[index] || this.feedNextUrl[index].length === 0)) {
      return;
    }
    this.feedLoading[index] = true;
    try {
      const page = await TopicService.getTopicFeed(
        this.context(),
        this.topicId,
        this.tabToFeedTab(index),
        this.currentSort(index),
        loadMore ? this.feedNextUrl[index] : undefined
      );
      const merged = loadMore ? [...this.feedItems[index], ...page.items] : page.items;
      this.feedItems[index] = merged;
      this.feedNextUrl[index] = page.nextUrl;
      this.feedIsEnd[index] = page.isEnd;
      this.feedLoaded[index] = true;
      this.feedError[index] = '';
    } catch (error) {
      this.feedError[index] = errMsg(error);
    } finally {
      this.feedLoading[index] = false;
    }
  }

  private openContent(item: HomeFeedItem): void {
    if (item.nativeTarget !== undefined) {
      openZhihuContentTarget(item.nativeTarget, item.title, item.targetUrl);
      return;
    }
    this.showToast('暂不支持打开该内容');
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

  @Builder
  private Footer(): void {
    if (this.feedLoading[this.selectedTab] && !this.feedLoaded[this.selectedTab]) {
      Text('正在加载…')
        .fontSize(13).fontColor($r('app.color.text_secondary'))
        .width('100%').textAlign(TextAlign.Center).padding({ top: 24, bottom: 24 })
        .onClick(() => {})
    } else if (this.feedError[this.selectedTab].length > 0 && this.feedItems[this.selectedTab].length === 0) {
      Column({ space: 12 }) {
        Text(this.feedError[this.selectedTab]).fontSize(14).fontColor($r('app.color.error_text')).textAlign(TextAlign.Center)
        Text('重新加载')
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.action_text'))
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.action_background')).borderRadius(18)
          .onClick(() => { this.loadFeed(this.selectedTab, false); })
      }
      .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 40, bottom: 40 })
    } else if (this.feedItems[this.selectedTab].length === 0 && this.feedLoaded[this.selectedTab]) {
      Text('这里还没有内容')
        .fontSize(14).fontColor($r('app.color.text_secondary'))
        .width('100%').textAlign(TextAlign.Center).padding({ top: 40, bottom: 40 })
    } else if (this.feedLoading[this.selectedTab]) {
      Text('正在加载更多…')
        .fontSize(12).fontColor($r('app.color.text_secondary'))
        .width('100%').textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
    } else if (this.feedIsEnd[this.selectedTab]) {
      Text('没有更多了')
        .fontSize(12).fontColor($r('app.color.text_tertiary'))
        .width('100%').textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
    } else {
      Text('加载更多')
        .fontSize(12).fontColor($r('app.color.action_text'))
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
        .borderRadius(16).border({ width: 1, color: $r('app.color.card_border') })
        .onClick(() => { this.loadFeed(this.selectedTab, true); })
        .margin({ top: 8, bottom: 8 })
    }
  }

  @Builder
  private FeedList(): void {
    List({ space: 12, scroller: this.scroller }) {
      if (this.selectedTab === 0 && this.detail !== null) {
        ListItem() { this.SortBar(); }
      }
      if (this.selectedTab === 1) {
        ListItem() { this.SortBar(); }
      }
      ForEach(this.feedItems[this.selectedTab], (item: HomeFeedItem) => {
        ListItem() { this.FeedCard(item); }
      }, (item: HomeFeedItem) => item.id)
      ListItem() { this.Footer(); }
    }
    .width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    .onReachEnd(() => { this.loadFeed(this.selectedTab, true); })
    .padding({ left: 16, right: 16, top: 12 })
  }

  // 排序条（讨论：精华/最热/最新；想法：最热/最新）
  @Builder
  private SortBar(): void {
    Row({ space: 8 }) {
      if (this.selectedTab === 0) {
        this.SortChip('精华', this.discussionSort === 'essence', () => { this.discussionSort = 'essence'; this.loadFeed(0, false); })
        this.SortChip('最热', this.discussionSort === 'hot', () => { this.discussionSort = 'hot'; this.loadFeed(0, false); })
        this.SortChip('最新', this.discussionSort === 'timeline', () => { this.discussionSort = 'timeline'; this.loadFeed(0, false); })
      } else {
        this.SortChip('最热', this.ideasSort === 'hot', () => { this.ideasSort = 'hot'; this.loadFeed(1, false); })
        this.SortChip('最新', this.ideasSort === 'latest', () => { this.ideasSort = 'latest'; this.loadFeed(1, false); })
      }
    }
    .width('100%').padding({ left: 4, right: 4, top: 4, bottom: 4 })
  }

  @Builder
  private SortChip(label: string, selected: boolean, onClick: () => void): void {
    Text(label)
      .fontSize(13)
      .fontColor(selected ? $r('app.color.action_text') : $r('app.color.text_secondary'))
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(selected ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .borderRadius(16)
      .onClick(onClick)
  }

  // ---------- 顶栏（固定，不跟随下滑）----------
  @Builder
  private TopBar(): void {
    Row({ space: 12 }) {
      Image($r('app.media.arrow_back'))
        .width(22).height(22)
        .fillColor($r('app.color.text_primary'))
        .renderMode(ImageRenderMode.Template)
        .onClick(() => { router.back({ url: '' }); })

      Text(this.topicName.length > 0 ? this.topicName : '话题')
        .fontSize(18).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (this.detail !== null) {
        Text(this.detail.isFollowing ? '已关注' : '关注')
          .fontSize(14)
          .fontColor(this.detail.isFollowing ? $r('app.color.text_secondary') : $r('app.color.action_text'))
          .padding({ left: 18, right: 18, top: 8, bottom: 8 })
          .backgroundColor(this.detail.isFollowing ? ThemeColors.cardBackground(this.oledBlack, this.isDark) : $r('app.color.action_background'))
          .border({ width: 1, color: this.detail.isFollowing ? $r('app.color.card_border') : $r('app.color.action_background') })
          .borderRadius(18)
          .onClick(() => { this.doToggleFollow(); })
      }
    }
    .width('100%')
    .height(56)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16 })
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
  }

  // ---------- 详情卡片（头像 + 统计 + 简介）----------
  @Builder
  private DetailBody(): void {
    Column({ space: 12 }) {
      if (this.detail !== null) {
        Row({ space: 12 }) {
          if (this.detail.avatarUrl.length > 0) {
            Image(this.detail.avatarUrl)
              .width(56).height(56).objectFit(ImageFit.Cover).borderRadius(28).clip(true)
          } else {
            Column() {
              Text(this.detail.name.slice(0, 1))
                .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.action_text'))
            }
            .width(56).height(56).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
            .backgroundColor($r('app.color.action_background')).borderRadius(28)
          }

          Column({ space: 4 }) {
            Text(this.detail.name)
              .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.detail.excerpt.length > 0) {
              Text(this.detail.excerpt)
                .fontSize(13).fontColor($r('app.color.text_secondary'))
                .maxLines(this.excerptExpanded ? 10 : 2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick(() => { this.excerptExpanded = !this.excerptExpanded; })
            }
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
        }
        .width('100%').alignItems(VerticalAlign.Top)

        // 统计行
        Row({ space: 8 }) {
          this.StatItem('关注者', this.detail.followersCount)
          this.StatItem('问题', this.detail.questionsCount)
          this.StatItem('讨论', this.detail.discussCount)
          this.StatItem('浏览', this.detail.totalPv)
        }
        .width('100%').padding({ top: 4 })
      } else if (this.detailLoading) {
        Text('正在加载话题信息…')
          .fontSize(14).fontColor($r('app.color.text_secondary'))
          .width('100%').textAlign(TextAlign.Center).padding({ top: 20, bottom: 20 })
      } else if (this.detailError.length > 0) {
        Column({ space: 12 }) {
          Text(this.detailError).fontSize(14).fontColor($r('app.color.error_text')).textAlign(TextAlign.Center)
          Text('重新加载')
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.action_text'))
            .padding({ left: 18, right: 18, top: 10, bottom: 10 })
            .backgroundColor($r('app.color.action_background')).borderRadius(18)
            .onClick(() => { this.loadDetail(); })
        }
        .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 40, bottom: 40 })
      }
    }
    .width('100%').padding(16).backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .borderRadius(16).border({ width: 1, color: $r('app.color.card_border') })
    .margin({ left: 16, right: 16 })
  }

  @Builder
  private StatItem(label: string, value: number): void {
    Column({ space: 2 }) {
      Text(`${value}`)
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Text(label)
        .fontSize(12).fontColor($r('app.color.text_secondary'))
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
  }

  // ---------- 分段 Tab ----------
  @Builder
  private TabBar(): void {
    Row({ space: 8 }) {
      ForEach(this.tabTitles, (title: string, index: number) => {
        Text(title)
          .fontSize(15)
          .fontWeight(this.selectedTab === index ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.selectedTab === index ? $r('app.color.action_text') : $r('app.color.text_secondary'))
          .padding({ left: 18, right: 18, top: 10, bottom: 10 })
          .backgroundColor(this.selectedTab === index ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .borderRadius(18)
          .onClick(() => {
            this.selectedTab = index;
            this.ensureTabLoaded(index);
          })
      }, (title: string, index: number) => `${index}-${title}`)
    }
    .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      this.TopBar()
      if (this.topicId.length > 0) {
        this.DetailBody()
      }
      this.TabBar()
      if (this.topicId.length > 0) {
        this.FeedList()
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topSafeAreaVp })
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
