import common from '@ohos.app.ability.common';
import { promptAction, router } from '@kit.ArkUI';
import { serializeZhihuContentTarget, ZhihuCommentableTarget } from '../models/ZhihuContentModels';
import { DEFAULT_SESSION_SNAPSHOT, HomeFeedItem, SearchPeopleResult, SearchTopicResult, SessionSnapshot, TextHighlightSegment } from '../models/ZhihuModels';
import { BrowsingHistoryRepository } from '../services/BrowsingHistoryRepository';
import { CloudHistoryService } from '../services/CloudHistoryService';
import { HotSearchItem, SearchService } from '../services/SearchService';
import { ThemeColors } from '../services/ThemeColors';
import { ContentCard } from '../components/ContentCard';
import { resolveZhihuContent } from '../services/ZhihuContentResolver';
import { openZhihuContentTarget, openZhihuTopic } from '../services/ZhihuNavigation';
import { pasteboard } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';

const SEARCH_HISTORY_KEY: string = 'searchHistoryQueries';
const SEARCH_HISTORY_MAX_SIZE: number = 20;

interface SearchPageParams {
  query?: string;
  readonly scopeMemberHashId?: string;
  readonly scopeMemberName?: string;
}

@Entry
@Component
struct SearchPage {
  @StorageProp('cardPadding') private cardPadding: number = 16;
  @StorageProp('pillRadius') private pillRadius: number = 18;
  @StorageProp('cardRadius') private cardRadius: number = 16;
  @StorageProp('fontSubhead') private fontSubhead: string = '18fp';
  @StorageProp('fontBody') private fontBody: string = '16fp';
  @StorageProp('fontSecondary') private fontSecondary: string = '14fp';
  @StorageProp('fontMeta') private fontMeta: string = '13fp';
  @StorageProp('fontCaption') private fontCaption: string = '12fp';
  @StorageProp('fontSymbol') private fontSymbol: string = '24fp';
  @StorageProp('fontBodyLg') private fontBodyLg: string = '17fp';
  @StorageProp('fontTitle') private fontTitle: string = '22fp';
  @StorageProp('fontHeading') private fontHeading: string = '20fp';
  @StorageProp('spaceMd') private spaceMd: number = 12;
  @StorageProp('pagePadding') private pagePadding: number = 20;
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageProp('bottomSafeAreaVp') private bottomSafeAreaVp: number = 0;
  @StorageProp('sessionSnapshot') private sessionSnapshot: SessionSnapshot = DEFAULT_SESSION_SNAPSHOT;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;
  @State private queryInput: string = '';
  @State private searchQuery: string = '';
  @State private hotSearchItems: HotSearchItem[] = [];
  @State private hotSearchLoading: boolean = false;
  @State private hotSearchError: string = '';
  @State private resultItems: HomeFeedItem[] = [];
  @State private resultLoading: boolean = false;
  @State private resultLoadingMore: boolean = false;
  @State private resultError: string = '';
  @State private resultNextUrl: string = '';
  @State private hasSearched: boolean = false;
  @State private scopeMemberHashId: string = '';
  @State private scopeMemberName: string = '';
  @State private sortValue: string = ''; // '' | 'created_time' | 'upvoted_count'
  @State private contentType: 'all' | 'answer' | 'article' | 'question' = 'all';
  @State private timeValue: string = ''; // '' | 'a_day' | 'a_week' | 'a_month' | 'three_months' | 'half_a_year' | 'a_year'
  @State private showFilterBar: boolean = false;
  // 搜索历史（对照安卓 searchHistoryQueries，最多 20 条，去重置顶）
  @State private searchHistoryItems: string[] = [];
  @StorageLink('showSearchHistory') private showSearchHistory: boolean = true;
  @StorageLink('showSearchHotSearch') private showSearchHotSearch: boolean = true;
  @State private historyMenuExpanded: boolean = false;
  @State private historyExpanded: boolean = false;
  @State private refreshing: boolean = false;
  // 搜索分类 Tab（对齐安卓 SearchTab：全站 / 用户 / 话题）
  @State private searchTab: 'general' | 'people' | 'topic' = 'general';
  @State private peopleItems: SearchPeopleResult[] = [];
  @State private topicItems: SearchTopicResult[] = [];
  @State private peopleNextUrl: string = '';
  @State private topicNextUrl: string = '';
  @State private peopleIsEnd: boolean = false;
  @State private topicIsEnd: boolean = false;
  @State private peopleLoading: boolean = false;
  @State private topicLoading: boolean = false;
  @State private peopleLoadingMore: boolean = false;
  @State private topicLoadingMore: boolean = false;
  @State private peopleError: string = '';
  @State private topicError: string = '';

  async aboutToAppear(): Promise<void> {
    const rawParams = router.getParams();
    const emptyParams: SearchPageParams = {};
    const params: SearchPageParams = rawParams !== undefined && rawParams !== null
      ? rawParams as SearchPageParams
      : emptyParams;
    const initialQuery = typeof params.query === 'string' ? params.query.trim() : '';
    const scopeId = typeof params.scopeMemberHashId === 'string' ? params.scopeMemberHashId : '';
    const scopeName = typeof params.scopeMemberName === 'string' ? params.scopeMemberName : '';
    this.scopeMemberHashId = scopeId;
    this.scopeMemberName = scopeName;
    if (initialQuery.length > 0) {
      this.queryInput = initialQuery;
      this.submitSearch(initialQuery);
      return;
    }
    if (scopeId.length === 0) {
      this.loadHotSearch();
      await this.loadSearchHistory();
    }
  }

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  private applyContentType(type: 'all' | 'answer' | 'article' | 'question'): void {
    if (this.contentType === type) {
      return;
    }
    this.contentType = type;
    if (this.searchQuery.length > 0) {
      this.submitSearch(this.searchQuery);
    }
  }

  private applySort(sort: string): void {
    if (this.sortValue === sort) {
      return;
    }
    this.sortValue = sort;
    if (this.searchQuery.length > 0) {
      this.submitSearch(this.searchQuery);
    }
  }

  private applyTime(time: string): void {
    if (this.timeValue === time) {
      return;
    }
    this.timeValue = time;
    if (this.searchQuery.length > 0) {
      this.submitSearch(this.searchQuery);
    }
  }

  private showToast(message: string): void {
    promptAction.showToast({
      message,
      duration: 1800
    });
  }

  private async loadHotSearch(): Promise<void> {
    if (this.hotSearchLoading) {
      return;
    }
    this.hotSearchLoading = true;
    this.hotSearchError = '';
    try {
      this.hotSearchItems = await SearchService.loadHotSearch();
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.hotSearchError = `热搜加载失败：${message}`;
    } finally {
      this.hotSearchLoading = false;
    }
  }

  private apiContentType(): string {
    // 问题无服务端 vertical 参数，走客户端过滤，故传空
    return this.contentType === 'question' ? '' : (this.contentType === 'all' ? '' : this.contentType);
  }

  private applyQuestionFilter(items: HomeFeedItem[]): HomeFeedItem[] {
    if (this.contentType !== 'question') {
      return items;
    }
    return items.filter((item: HomeFeedItem) => item.type === 'question');
  }

  private async submitSearch(query?: string): Promise<void> {
    const nextQuery = (query ?? this.queryInput).trim();
    if (nextQuery.length === 0) {
      this.showToast('请输入搜索内容');
      return;
    }
    if (!this.sessionSnapshot.loggedIn) {
      this.showToast('登录后可使用知乎搜索');
    }
    this.queryInput = nextQuery;
    this.searchQuery = nextQuery;
    // 记录搜索历史（仅非成员搜索且开启历史开关时）
    if (this.scopeMemberHashId.length === 0 && this.showSearchHistory && this.searchTab === 'general') {
      await this.addSearchHistory(nextQuery);
    }
    this.hasSearched = true;
    if (this.searchTab === 'people') {
      await this.doSearchPeople(false);
    } else if (this.searchTab === 'topic') {
      await this.doSearchTopics(false);
    } else {
      await this.doSearchGeneral();
    }
  }

  private async doSearchGeneral(): Promise<void> {
    this.resultItems = [];
    this.resultNextUrl = '';
    this.resultError = '';
    this.resultLoading = true;
    try {
      const page = await SearchService.searchFirstPage(
        this.context(),
        this.searchQuery,
        this.scopeMemberHashId,
        this.sortValue,
        this.apiContentType(),
        this.timeValue
      );
      this.resultItems = this.applyQuestionFilter(page.items);
      this.resultNextUrl = page.paging.nextUrl;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.resultError = `搜索失败：${message}`;
    } finally {
      this.resultLoading = false;
    }
  }

  private async doSearchPeople(loadMore: boolean): Promise<void> {
    if (!loadMore && this.peopleLoading) {
      return;
    }
    if (loadMore && (this.peopleIsEnd || this.peopleLoadingMore || this.peopleNextUrl.length === 0)) {
      return;
    }
    this.peopleLoading = !loadMore;
    this.peopleLoadingMore = loadMore;
    try {
      const page = await SearchService.searchPeople(this.context(), this.searchQuery, loadMore ? this.peopleNextUrl : undefined);
      this.peopleItems = loadMore ? [...this.peopleItems, ...page.items] : page.items;
      this.peopleNextUrl = page.nextUrl;
      this.peopleIsEnd = page.isEnd;
      this.peopleError = '';
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.peopleError = `用户搜索失败：${message}`;
    } finally {
      this.peopleLoading = false;
      this.peopleLoadingMore = false;
    }
  }

  private async doSearchTopics(loadMore: boolean): Promise<void> {
    if (!loadMore && this.topicLoading) {
      return;
    }
    if (loadMore && (this.topicIsEnd || this.topicLoadingMore || this.topicNextUrl.length === 0)) {
      return;
    }
    this.topicLoading = !loadMore;
    this.topicLoadingMore = loadMore;
    try {
      const page = await SearchService.searchTopics(this.context(), this.searchQuery, loadMore ? this.topicNextUrl : undefined);
      this.topicItems = loadMore ? [...this.topicItems, ...page.items] : page.items;
      this.topicNextUrl = page.nextUrl;
      this.topicIsEnd = page.isEnd;
      this.topicError = '';
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.topicError = `话题搜索失败：${message}`;
    } finally {
      this.topicLoading = false;
      this.topicLoadingMore = false;
    }
  }

  private async pullToRefresh(): Promise<void> {
    this.refreshing = true;
    try {
      if (this.hasSearched) {
        await this.submitSearch(this.searchQuery);
      } else {
        await this.loadHotSearch();
      }
    } catch (_) {
      // 静默
    } finally {
      this.refreshing = false;
    }
  }

  private async loadMoreResults(): Promise<void> {
    if (this.resultLoadingMore || this.resultNextUrl.length === 0) {
      return;
    }
    this.resultLoadingMore = true;
    try {
      const page = await SearchService.searchNextPage(this.context(), this.resultNextUrl);
      const existed = new Set<string>(this.resultItems.map((item: HomeFeedItem) => item.id));
      const merged = [...this.resultItems];
      this.applyQuestionFilter(page.items).forEach((item: HomeFeedItem) => {
        if (!existed.has(item.id)) {
          existed.add(item.id);
          merged.push(item);
        }
      });
      this.resultItems = merged;
      this.resultNextUrl = page.paging.nextUrl;
      this.resultError = '';
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.resultError = `继续加载失败：${message}`;
    } finally {
      this.resultLoadingMore = false;
    }
  }

  private clearSearch(): void {
    this.queryInput = '';
    this.searchQuery = '';
    this.resultItems = [];
    this.resultNextUrl = '';
    this.resultError = '';
    this.hasSearched = false;
    if (this.hotSearchItems.length === 0) {
      this.loadHotSearch();
    }
  }

  // ===== 搜索历史（对照安卓 SEARCH_HISTORY_KEY / saveSearchHistory）=====
  // 改用异步 preferences API，避免同步 API 在真机上偶发写入失败导致历史不记录。
  private async loadSearchHistory(): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context(), { name: 'zhihu_search_history' });
      const raw = await store.get(SEARCH_HISTORY_KEY, '') as string;
      if (typeof raw === 'string' && raw.length > 0) {
        const parsed = JSON.parse(raw) as string[];
        if (Array.isArray(parsed)) {
          this.searchHistoryItems = parsed.filter((item: string) => typeof item === 'string');
        }
      }
    } catch (e) {
      console.error('[Search] loadSearchHistory failed:', e);
      this.searchHistoryItems = [];
    }
  }

  private async saveSearchHistory(): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context(), { name: 'zhihu_search_history' });
      const payload = JSON.stringify(this.searchHistoryItems);
      await store.put(SEARCH_HISTORY_KEY, payload);
      await store.flush();
    } catch (e) {
      console.error('[Search] saveSearchHistory failed:', e);
    }
  }

  private async addSearchHistory(query: string): Promise<void> {
    const trimmed = query.trim();
    if (trimmed.length === 0) {
      return;
    }
    const items = this.searchHistoryItems.filter((item: string) => item !== trimmed);
    items.unshift(trimmed);
    while (items.length > SEARCH_HISTORY_MAX_SIZE) {
      items.pop();
    }
    this.searchHistoryItems = items;
    await this.saveSearchHistory();
  }

  private clearSearchHistory(): void {
    this.searchHistoryItems = [];
    this.saveSearchHistory();
  }

  private openAppearanceSettings(): void {
    router.pushUrl({ url: 'pages/AppearanceSettings' });
  }

  // 粘贴/剪贴板图标统一入口：能解析的知乎链接直接跳转，否则填入搜索框。
  private handlePastedText(text: string): void {
    if (this.tryOpenZhihuLink(text)) {
      return;
    }
    this.queryInput = text;
  }

  private async pasteFromClipboard(): Promise<void> {
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      const pasteData = await systemPasteboard.getData();
      if (!pasteData) {
        return;
      }
      const text = pasteData.getPrimaryText() || '';
      if (text.length === 0) {
        return;
      }
      if (this.tryOpenZhihuLink(text)) {
        return;
      }
      this.queryInput = text;
    } catch (error) {
      promptAction.showToast({ message: '读取剪贴板失败' });
    }
  }

  private tryOpenZhihuLink(text: string): boolean {
    const link = this.extractFirstZhihuLink(text);
    if (!link) {
      return false;
    }
    const target = resolveZhihuContent(link);
    if (!target) {
      return false;
    }
    openZhihuContentTarget(target);
    return true;
  }

  private extractFirstZhihuLink(text: string): string | undefined {
    const regex = /https?:\/\/[-a-zA-Z0-9@:%_+.~#?&/=]+/g;
    let match: RegExpExecArray | null = regex.exec(text);
    while (match !== null) {
      const url = match[0];
      if (/^https?:\/\/(?:www\.)?zhihu\.com\//i.test(url) || /^zhihu:\/\//i.test(url)) {
        return url;
      }
      match = regex.exec(text);
    }
    return undefined;
  }

  private openWebContent(title: string, url: string, recordHistory: boolean = false): void {
    if (url.length === 0) {
      return;
    }
    if (recordHistory) {
      BrowsingHistoryRepository.recordWeb(this.context(), title, url);
    }
    router.pushUrl({
      url: 'pages/WebContent',
      params: { title, url }
    });
  }

  private openNativeArticle(target: ZhihuCommentableTarget, fallbackTitle: string, fallbackUrl: string): void {
    BrowsingHistoryRepository.recordContent(this.context(), target, fallbackTitle, fallbackUrl);
    // 上报云端历史
    CloudHistoryService.reportViaTarget(this.context(), target);
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
    router.pushUrl({
      url: 'pages/Article',
      params: {
        target: serializeZhihuContentTarget(target),
        fallbackTitle,
        fallbackUrl
      }
    });
  }

  private openResultItem(item: HomeFeedItem): void {
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

  private handleScrollEdge(side: Edge): void {
    if (side !== Edge.Bottom || !this.hasSearched) {
      return;
    }
    if (this.searchTab === 'people' && this.peopleItems.length > 0 && this.peopleNextUrl.length > 0) {
      this.doSearchPeople(true);
    } else if (this.searchTab === 'topic' && this.topicItems.length > 0 && this.topicNextUrl.length > 0) {
      this.doSearchTopics(true);
    } else if (this.searchTab === 'general' && this.resultItems.length > 0 && this.resultNextUrl.length > 0) {
      this.loadMoreResults();
    }
  }

  @Builder
  private HighlightText(
    text: string,
    segments: TextHighlightSegment[] | undefined,
    fontSize: number,
    lineHeight: number,
    normalColor: ResourceColor,
    highlightedColor: ResourceColor,
    normalWeight: FontWeight,
    highlightedWeight: FontWeight,
    maxLines: number
  ): void {
    Text() {
      if (segments !== undefined && segments.length > 0) {
        ForEach(segments, (segment: TextHighlightSegment, index: number) => {
          Span(segment.text)
            .fontColor(segment.highlighted ? highlightedColor : normalColor)
            .fontWeight(segment.highlighted ? highlightedWeight : normalWeight)
        }, (segment: TextHighlightSegment, index: number) => `${index}:${segment.highlighted ? 'h' : 'n'}:${segment.text}`)
      } else {
        Span(text)
          .fontColor(normalColor)
          .fontWeight(normalWeight)
      }
    }
    .fontSize(fontSize)
    .lineHeight(lineHeight)
    .maxLines(maxLines)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  private SearchTitleSlot(): void {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(this.fontBodyLg)
        .fontColor([$r('app.color.text_secondary')])

      TextInput({ text: this.queryInput, placeholder: this.scopeMemberHashId.length > 0 ? '搜索 TA 的创作' : '搜索内容' })
        .layoutWeight(1)
        .height(40)
        .fontSize(this.fontBody)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor('#00000000')
        .padding({ left: 0, right: 0 })
        .enterKeyType(EnterKeyType.Search)
        .onChange((value: string) => {
          this.queryInput = value;
        })
        .onSubmit(() => {
          this.submitSearch();
        })
        .onPaste((text: string) => {
          this.handlePastedText(text);
        })

      if (this.queryInput.length > 0) {
        Text('×')
          .fontSize(this.fontBody)
          .fontColor($r('app.color.text_secondary'))
          .width(20)
          .height(20)
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.card_border'))
          .borderRadius(10)
          .onClick(() => {
            this.clearSearch();
          })
      } else {
        SymbolGlyph($r('sys.symbol.doc'))
          .fontSize(this.fontBodyLg)
          .fontColor([$r('app.color.text_secondary')])
          .onClick(() => {
            this.pasteFromClipboard();
          })
      }
    }
    .layoutWeight(1)
    .height(42)
    .padding({ left: 14, right: 10 })
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .border({ width: 1, color: $r('app.color.card_border') })
    .borderRadius(22)
  }

  @Builder
  private SearchActions(): void {
    Text(this.hasSearched && this.searchTab === 'general' ? '筛选' : '搜索')
      .fontSize(this.fontSecondary)
      .fontWeight(FontWeight.Medium)
      .fontColor(
        this.hasSearched && this.searchTab === 'general'
          ? (this.showFilterBar ? $r('app.color.action_text') : $r('app.color.text_primary'))
          : (this.queryInput.trim().length > 0 ? $r('app.color.action_text') : $r('app.color.text_tertiary'))
      )
      .padding({ left: 6, right: 6, top: 9, bottom: 9 })
      .enabled(this.hasSearched && this.searchTab === 'general' ? true : this.queryInput.trim().length > 0)
      .onClick(() => {
        if (this.hasSearched && this.searchTab === 'general') {
          this.showFilterBar = !this.showFilterBar;
        } else {
          this.submitSearch();
        }
      })
  }

  // 自绘顶栏：圆形返回键（与 PageHeader 同款光效）+ 搜索框（titleSlot）+ 搜索/筛选（actions）。
  // 不通过 PageHeader 的 @BuilderParam 传参，避免跨组件 builder 的 this 绑定在运行时崩溃（此前点击首页搜索闪退的根因）。
  @Builder
  private SearchHeader(): void {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(this.fontSymbol)
          .fontColor([$r('app.color.text_primary')])
      }
      .type(ButtonType.Circle)
      .backgroundColor(this.isDark ? '#1AFFFFFF' : '#0D000000')
      .stateEffect(true)
      .width(36)
      .height(36)
      .margin({ left: 8, right: 4 })
      .onClick(() => {
        router.back({ url: '' });
      })

      this.SearchTitleSlot();
      this.SearchActions();
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      top: this.topSafeAreaVp + this.spaceMd,
      bottom: this.spaceMd,
      right: this.pagePadding
    })
    .backgroundColor(ThemeColors.oledBlack(this.oledBlack, this.isDark, $r('app.color.glass_top_bar_background')))
  }

  // 搜索历史 / 热搜卡片底色：OLED 黑下纯黑 #000000，浅色下固定浅蓝（不受 lightCardWhite 影响）。
  private suggestionCardBg(): ResourceColor {
    if (this.oledBlack && this.isDark) {
      return '#000000';
    }
    if (!this.isDark) {
      return $r('app.color.answer_card_background');
    }
    return $r('app.color.card_background');
  }

  @Builder
  private HotSearchList(): void {
    Column() {
      Row() {
        Text('热搜')
          .fontSize(this.fontSubhead)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Text(this.hotSearchLoading ? '刷新中' : '刷新')
          .fontSize(this.fontMeta)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.hotSearchLoading ? $r('app.color.text_tertiary') : $r('app.color.action_text'))
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(this.cardRadius)
          .enabled(!this.hotSearchLoading)
          .onClick(() => {
            this.loadHotSearch();
          })
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
      .padding({ left: 18, right: 18, top: 16, bottom: 4 })

      if (this.hotSearchError.length > 0) {
        Text(this.hotSearchError)
          .fontSize(this.fontMeta)
          .fontColor($r('app.color.error_text'))
          .padding({ left: 18, right: 18, top: 0, bottom: 8 })
      }

      if (this.hotSearchLoading && this.hotSearchItems.length === 0) {
        Text('正在加载知乎热搜...')
          .fontSize(this.fontSecondary)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 18, right: 18, top: 20, bottom: 20 })
      } else if (this.hotSearchItems.length === 0) {
        Text('请输入搜索内容')
          .fontSize(this.fontSecondary)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 18, right: 18, top: 20, bottom: 20 })
      } else {
        ForEach(this.hotSearchItems, (item: HotSearchItem, index: number) => {
          Column() {
            Row({ space: 12 }) {
              Text(`${index + 1}`)
                .fontSize(this.fontSecondary)
                .fontWeight(FontWeight.Bold)
                .fontColor(index < 3 ? $r('app.color.error_text') : $r('app.color.text_tertiary'))
                .width(28)
                .textAlign(TextAlign.Center)

              Text(item.query)
                .fontSize(this.fontBody)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)

              if (item.hotShow.length > 0) {
                Text(item.hotShow)
                  .fontSize(this.fontCaption)
                  .fontColor($r('app.color.text_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .flexShrink(0)
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding({ left: 18, right: 18, top: 12, bottom: 12 })

            if (index < this.hotSearchItems.length - 1) {
              Divider()
                .strokeWidth(0.5)
                .color($r('app.color.card_border'))
                .padding({ left: 18, right: 18 })
            }
          }
          .width('100%')
          .onClick(() => {
            this.submitSearch(item.query);
          })
        }, (item: HotSearchItem) => item.query)
      }
    }
    .width('100%')
    .backgroundColor(this.suggestionCardBg())
    .border({ width: 1, color: $r('app.color.card_border') })
    .borderRadius(this.cardRadius)
    .margin({ left: 16, right: 16, bottom: 12 })
  }

  // 空查询时的建议区：搜索历史（可选）+ 热搜（可选），对齐安卓 SearchScreen 布局。
  // 历史 / 热搜各自包成一个大卡片，与华为浏览器一致。
  @Builder
  private SearchSuggestions(): void {
    Column() {
      if ((this.showSearchHistory && this.searchHistoryItems.length > 0)
        || (this.showSearchHotSearch && this.hotSearchItems.length > 0)) {
        if (this.showSearchHistory && this.searchHistoryItems.length > 0) {
          // 搜索历史：单个大卡片
          Column() {
            Row() {
              Text('搜索历史')
                .fontSize(this.fontSubhead)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .alignSelf(ItemAlign.Center)

              if (this.searchHistoryItems.length > 6) {
                SymbolGlyph(this.historyExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
                  .fontSize(this.fontTitle)
                  .fontColor([$r('app.color.text_secondary')])
                  .margin({ right: 12 })
                  .onClick(() => {
                    this.historyExpanded = !this.historyExpanded;
                  })
              }

              SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                .fontSize(this.fontHeading)
                .fontColor([$r('app.color.text_secondary')])
                .onClick(() => {
                  this.historyMenuExpanded = !this.historyMenuExpanded;
                })
                .bindMenu(this.historyMenuExpanded, [
                  {
                    value: '清空搜索历史',
                    action: () => {
                      this.historyMenuExpanded = false;
                      this.clearSearchHistory();
                    }
                  },
                  {
                    value: '前往设置关闭搜索历史',
                    action: () => {
                      this.historyMenuExpanded = false;
                      this.openAppearanceSettings();
                    }
                  }
                ])
            }
            .alignItems(VerticalAlign.Center)
            .width('100%')
            .padding({ left: 18, right: 18, top: 16, bottom: 4 })

            Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
              ForEach(this.searchHistoryItems.slice(0, this.historyExpanded ? 18 : 6), (query: string) => {
                Column() {
                  Row({ space: 8 }) {
                    SymbolGlyph($r('sys.symbol.magnifyingglass'))
                      .fontSize(this.fontBody)
                      .fontColor([$r('app.color.text_secondary')])

                    Text(query)
                      .fontSize(this.fontBody)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                  .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                  .onClick(() => {
                    this.submitSearch(query);
                  })
                }
                .width('50%')
                .padding({ left: 4, right: 4, bottom: 8 })
              }, (query: string) => query)
            }
            .width('100%')
          }
          .width('100%')
          .backgroundColor(this.suggestionCardBg())
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(this.cardRadius)
          .margin({ left: 16, right: 16, bottom: 12 })
        }

        if (this.showSearchHotSearch) {
          this.HotSearchList();
        }
      } else if (this.showSearchHistory) {
        Column({ space: 8 }) {
          Text(this.scopeMemberHashId.length > 0
            ? '输入关键词搜索 TA 的创作'
            : '暂无搜索历史，输入关键词搜索后会保存在这里')
            .fontSize(this.fontSecondary)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 80, left: 24, right: 24 })
      } else {
        Text('请输入搜索内容')
          .fontSize(this.fontSecondary)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 18, right: 18, top: 20, bottom: 20 })
      }
    }
    .width('100%')
    .padding({ top: 12 })
  }

  @Builder
  private ResultCard(item: HomeFeedItem): void {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        if (item.authorAvatarUrl.length > 0) {
          Image(item.authorAvatarUrl)
            .width(36)
            .height(36)
            .objectFit(ImageFit.Cover)
            .borderRadius(this.pillRadius)
            .clip(true)
        } else {
          Column() {
            Text(item.authorName.length > 0 ? item.authorName.slice(0, 1) : '知')
              .fontSize(this.fontMeta)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.action_text'))
          }
          .width(36)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(this.pillRadius)
        }

        Column({ space: 2 }) {
          Text(item.authorName.length > 0 ? item.authorName : '知乎搜索')
            .fontSize(this.fontMeta)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))

          Text(item.authorHeadline.length > 0 ? item.authorHeadline : item.actionText)
            .fontSize(this.fontCaption)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }

      Row({ space: 12 }) {
        Column({ space: 8 }) {
          this.HighlightText(
            item.title,
            item.titleHighlightSegments,
            17,
            24,
            $r('app.color.text_primary'),
            $r('app.color.action_text'),
            FontWeight.Bold,
            FontWeight.Bold,
            3
          )

          if (item.summary.length > 0) {
            this.HighlightText(
              item.summary,
              item.summaryHighlightSegments,
              13,
              20,
              $r('app.color.text_secondary'),
              $r('app.color.action_text'),
              FontWeight.Regular,
              FontWeight.Medium,
              3
            )
          }

          Text(item.details)
            .fontSize(this.fontCaption)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (item.thumbnailUrl.length > 0) {
          Image(item.thumbnailUrl)
            .width(92)
            .height(92)
            .objectFit(ImageFit.Cover)
            .borderRadius(this.cardRadius)
        }
      }
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .padding(this.cardPadding)
    .margin({ left: 16, right: 16, bottom: 12 })
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .border({ width: 1, color: $r('app.color.card_border') })
    .borderRadius(this.cardRadius)
    .clip(true)
    .shadow({
      radius: 10,
      color: '#10000000',
      offsetX: 0,
      offsetY: 3
    })
    .onClick(() => {
      this.openResultItem(item);
    })
  }

  @Builder
  private ResultsList(): void {
    Column() {
      if (this.resultLoading && this.resultItems.length === 0) {
        Column({ space: 10 }) {
          Text('正在搜索...')
            .fontSize(this.fontSubhead)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text('正在从知乎搜索接口拉取内容')
            .fontSize(this.fontMeta)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .padding({ top: 96 })
      } else if (this.resultError.length > 0 && this.resultItems.length === 0) {
        Column({ space: 12 }) {
          Text(this.resultError)
            .fontSize(this.fontBody)
            .fontColor($r('app.color.error_text'))
            .textAlign(TextAlign.Center)

          Text('重新搜索')
            .fontSize(this.fontSecondary)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.action_text'))
            .padding({ left: 18, right: 18, top: 10, bottom: 10 })
            .backgroundColor($r('app.color.action_background'))
            .borderRadius(this.pillRadius)
            .onClick(() => {
              this.submitSearch(this.searchQuery);
            })
        }
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .padding({ top: 96, left: 24, right: 24 })
      } else if (this.resultItems.length === 0) {
        Text('暂无搜索结果')
          .fontSize(this.fontBody)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 96 })
      } else {
        ForEach(this.resultItems, (item: HomeFeedItem) => {
          this.ResultCard(item);
        }, (item: HomeFeedItem) => item.id)

        if (this.resultError.length > 0) {
          Text(this.resultError)
            .fontSize(this.fontCaption)
            .fontColor($r('app.color.error_text'))
            .padding({ left: 18, right: 18, top: 0, bottom: 10 })
        }

        Text(this.resultNextUrl.length === 0 ? '已经到底了' : (this.resultLoadingMore ? '正在加载更多...' : '加载更多'))
          .fontSize(this.fontSecondary)
          .fontWeight(FontWeight.Medium)
          .fontColor(
            this.resultNextUrl.length === 0 || this.resultLoadingMore
              ? $r('app.color.text_tertiary')
              : $r('app.color.action_text')
          )
          .padding({ left: 18, right: 18, top: 12, bottom: 12 })
          .margin({ top: 4, bottom: 20 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(this.pillRadius)
          .enabled(this.resultNextUrl.length > 0 && !this.resultLoadingMore)
          .onClick(() => {
            this.loadMoreResults();
          })
      }
    }
    .width('100%')
  }

  @Builder
  private FilterChip(label: string, selected: boolean, onClick: () => void): void {
    Text(label)
      .fontSize(this.fontMeta)
      .fontColor(selected ? $r('app.color.action_text') : $r('app.color.text_secondary'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(selected ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .borderRadius(4)
      .onClick(onClick)
  }

  @Builder
  private FilterBar(): void {
    Scroll() {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          if (this.contentType === 'all') {
            this.FilterChip('不限类型', true, () => { this.applyContentType('all'); })
          } else {
            this.FilterChip('不限类型', false, () => { this.applyContentType('all'); })
          }
          if (this.contentType === 'answer') {
            this.FilterChip('只看回答', true, () => { this.applyContentType('answer'); })
          } else {
            this.FilterChip('只看回答', false, () => { this.applyContentType('answer'); })
          }
          if (this.contentType === 'article') {
            this.FilterChip('只看文章', true, () => { this.applyContentType('article'); })
          } else {
            this.FilterChip('只看文章', false, () => { this.applyContentType('article'); })
          }
          if (this.contentType === 'question') {
            this.FilterChip('只看问题', true, () => { this.applyContentType('question'); })
          } else {
            this.FilterChip('只看问题', false, () => { this.applyContentType('question'); })
          }
        }
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        .height(34)

        Row({ space: 8 }) {
          if (this.sortValue === '') {
            this.FilterChip('综合排序', true, () => { this.applySort(''); })
          } else {
            this.FilterChip('综合排序', false, () => { this.applySort(''); })
          }
          if (this.sortValue === 'upvoted_count') {
            this.FilterChip('最多赞同', true, () => { this.applySort('upvoted_count'); })
          } else {
            this.FilterChip('最多赞同', false, () => { this.applySort('upvoted_count'); })
          }
          if (this.sortValue === 'created_time') {
            this.FilterChip('最新发布', true, () => { this.applySort('created_time'); })
          } else {
            this.FilterChip('最新发布', false, () => { this.applySort('created_time'); })
          }
        }
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        .height(34)

        Row({ space: 8 }) {
          if (this.timeValue === '') {
            this.FilterChip('不限时间', true, () => { this.applyTime(''); })
          } else {
            this.FilterChip('不限时间', false, () => { this.applyTime(''); })
          }
          if (this.timeValue === 'a_day') {
            this.FilterChip('一天内', true, () => { this.applyTime('a_day'); })
          } else {
            this.FilterChip('一天内', false, () => { this.applyTime('a_day'); })
          }
          if (this.timeValue === 'a_week') {
            this.FilterChip('一周内', true, () => { this.applyTime('a_week'); })
          } else {
            this.FilterChip('一周内', false, () => { this.applyTime('a_week'); })
          }
          if (this.timeValue === 'a_month') {
            this.FilterChip('一月内', true, () => { this.applyTime('a_month'); })
          } else {
            this.FilterChip('一月内', false, () => { this.applyTime('a_month'); })
          }
          if (this.timeValue === 'three_months') {
            this.FilterChip('三月内', true, () => { this.applyTime('three_months'); })
          } else {
            this.FilterChip('三月内', false, () => { this.applyTime('three_months'); })
          }
          if (this.timeValue === 'half_a_year') {
            this.FilterChip('半年内', true, () => { this.applyTime('half_a_year'); })
          } else {
            this.FilterChip('半年内', false, () => { this.applyTime('half_a_year'); })
          }
          if (this.timeValue === 'a_year') {
            this.FilterChip('一年内', true, () => { this.applyTime('a_year'); })
          } else {
            this.FilterChip('一年内', false, () => { this.applyTime('a_year'); })
          }
        }
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        .height(34)
      }
      .alignItems(HorizontalAlign.Start)
      .width('auto')
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
  }

  // ===== 搜索分类 Tab（全站 / 用户 / 话题）=====
  private onSearchTabChanged(tab: 'general' | 'people' | 'topic'): void {
    if (this.searchTab === tab) {
      return;
    }
    this.searchTab = tab;
    if (this.queryInput.trim().length > 0) {
      this.submitSearch(this.queryInput.trim());
    } else {
      this.resultItems = [];
      this.peopleItems = [];
      this.topicItems = [];
      this.resultNextUrl = '';
      this.peopleNextUrl = '';
      this.topicNextUrl = '';
      this.resultError = '';
      this.peopleError = '';
      this.topicError = '';
      this.resultLoading = false;
      this.peopleLoading = false;
      this.topicLoading = false;
      this.hasSearched = false;
    }
  }

  @Builder
  private SearchTabBar(): void {
    Row({ space: 8 }) {
      Text('全站')
        .fontSize(this.fontBody)
        .fontWeight(this.searchTab === 'general' ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.searchTab === 'general' ? $r('app.color.action_text') : $r('app.color.text_secondary'))
        .padding({ left: 18, right: 18, top: 8, bottom: 8 })
        .backgroundColor(this.searchTab === 'general' ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .borderRadius(this.pillRadius)
        .onClick(() => { this.onSearchTabChanged('general'); })

      Text('用户')
        .fontSize(this.fontBody)
        .fontWeight(this.searchTab === 'people' ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.searchTab === 'people' ? $r('app.color.action_text') : $r('app.color.text_secondary'))
        .padding({ left: 18, right: 18, top: 8, bottom: 8 })
        .backgroundColor(this.searchTab === 'people' ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .borderRadius(this.pillRadius)
        .onClick(() => { this.onSearchTabChanged('people'); })

      Text('话题')
        .fontSize(this.fontBody)
        .fontWeight(this.searchTab === 'topic' ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.searchTab === 'topic' ? $r('app.color.action_text') : $r('app.color.text_secondary'))
        .padding({ left: 18, right: 18, top: 8, bottom: 8 })
        .backgroundColor(this.searchTab === 'topic' ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .borderRadius(this.pillRadius)
        .onClick(() => { this.onSearchTabChanged('topic'); })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  private PersonResultCard(person: SearchPeopleResult): void {
    ContentCard({ onTap: () => {
      const token = person.urlToken.length > 0 ? person.urlToken : person.id;
      router.pushUrl({ url: 'pages/People', params: { urlToken: token } });
    } }) {
      Row({ space: 12 }) {
      if (person.avatarUrl.length > 0) {
        Image(person.avatarUrl)
          .width(44).height(44).objectFit(ImageFit.Cover).borderRadius(22).clip(true)
      } else {
        Column() {
          Text(person.name.slice(0, 1))
            .fontSize(this.fontBody).fontWeight(FontWeight.Bold).fontColor($r('app.color.action_text'))
        }
        .width(44).height(44).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .backgroundColor($r('app.color.action_background')).borderRadius(22)
      }

      Column({ space: 4 }) {
        Text(person.name)
          .fontSize(this.fontBody).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (person.headline.length > 0) {
          Text(person.headline)
            .fontSize(this.fontMeta).fontColor($r('app.color.text_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Text(`${person.followerCount} 粉丝`)
          .fontSize(this.fontCaption).fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
      .width('100%')
    }
  }

  @Builder
  private TopicResultCard(topic: SearchTopicResult): void {
    ContentCard({ onTap: () => { openZhihuTopic(topic.id, topic.name); } }) {
      Row({ space: 12 }) {
      if (topic.avatarUrl.length > 0) {
        Image(topic.avatarUrl)
          .width(44).height(44).objectFit(ImageFit.Cover).borderRadius(22).clip(true)
      } else {
        Column() {
          Text(topic.name.slice(0, 1))
            .fontSize(this.fontBody).fontWeight(FontWeight.Bold).fontColor($r('app.color.action_text'))
        }
        .width(44).height(44).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .backgroundColor($r('app.color.action_background')).borderRadius(22)
      }

      Column({ space: 4 }) {
        Text(topic.name)
          .fontSize(this.fontBody).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (topic.excerpt.length > 0) {
          Text(topic.excerpt)
            .fontSize(this.fontMeta).fontColor($r('app.color.text_secondary'))
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Text(`${topic.discussCount} 讨论 · ${topic.visitCount} 浏览`)
          .fontSize(this.fontCaption).fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
      .width('100%')
    }
  }

  @Builder
  private PeopleResultsList(): void {
    Column() {
      if (this.peopleLoading && this.peopleItems.length === 0) {
        Text('正在搜索用户...')
          .fontSize(this.fontBody).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_secondary'))
          .width('100%').textAlign(TextAlign.Center).padding({ top: 96 })
      } else if (this.peopleError.length > 0 && this.peopleItems.length === 0) {
        Column({ space: 12 }) {
          Text(this.peopleError).fontSize(this.fontBody).fontColor($r('app.color.error_text')).textAlign(TextAlign.Center)
          Text('重新搜索')
            .fontSize(this.fontSecondary).fontWeight(FontWeight.Medium).fontColor($r('app.color.action_text'))
            .padding({ left: 18, right: 18, top: 10, bottom: 10 })
            .backgroundColor($r('app.color.action_background')).borderRadius(this.pillRadius)
            .onClick(() => { this.doSearchPeople(false); })
        }
        .alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
        .width('100%').padding({ top: 96, left: 24, right: 24 })
      } else if (this.peopleItems.length === 0) {
        Text('未找到相关用户')
          .fontSize(this.fontBody).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_secondary'))
          .width('100%').textAlign(TextAlign.Center).padding({ top: 96 })
      } else {
        ForEach(this.peopleItems, (p: SearchPeopleResult) => {
          this.PersonResultCard(p);
        }, (p: SearchPeopleResult) => p.id)
        if (this.peopleError.length > 0) {
          Text(this.peopleError)
            .fontSize(this.fontCaption).fontColor($r('app.color.error_text'))
            .padding({ left: 18, right: 18, top: 0, bottom: 10 })
        }
        Text(this.peopleNextUrl.length === 0 ? '已经到底了' : (this.peopleLoadingMore ? '正在加载更多...' : '加载更多'))
          .fontSize(this.fontSecondary).fontWeight(FontWeight.Medium)
          .fontColor(
            this.peopleNextUrl.length === 0 || this.peopleLoadingMore
              ? $r('app.color.text_tertiary')
              : $r('app.color.action_text')
          )
          .padding({ left: 18, right: 18, top: 12, bottom: 12 })
          .margin({ top: 4, bottom: 20 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(this.pillRadius)
          .enabled(this.peopleNextUrl.length > 0 && !this.peopleLoadingMore)
          .onClick(() => { this.doSearchPeople(true); })
      }
    }
    .width('100%')
  }

  @Builder
  private TopicResultsList(): void {
    Column() {
      if (this.topicLoading && this.topicItems.length === 0) {
        Text('正在搜索话题...')
          .fontSize(this.fontBody).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_secondary'))
          .width('100%').textAlign(TextAlign.Center).padding({ top: 96 })
      } else if (this.topicError.length > 0 && this.topicItems.length === 0) {
        Column({ space: 12 }) {
          Text(this.topicError).fontSize(this.fontBody).fontColor($r('app.color.error_text')).textAlign(TextAlign.Center)
          Text('重新搜索')
            .fontSize(this.fontSecondary).fontWeight(FontWeight.Medium).fontColor($r('app.color.action_text'))
            .padding({ left: 18, right: 18, top: 10, bottom: 10 })
            .backgroundColor($r('app.color.action_background')).borderRadius(this.pillRadius)
            .onClick(() => { this.doSearchTopics(false); })
        }
        .alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
        .width('100%').padding({ top: 96, left: 24, right: 24 })
      } else if (this.topicItems.length === 0) {
        Text('未找到相关话题')
          .fontSize(this.fontBody).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_secondary'))
          .width('100%').textAlign(TextAlign.Center).padding({ top: 96 })
      } else {
        ForEach(this.topicItems, (t: SearchTopicResult) => {
          this.TopicResultCard(t);
        }, (t: SearchTopicResult) => t.id)
        if (this.topicError.length > 0) {
          Text(this.topicError)
            .fontSize(this.fontCaption).fontColor($r('app.color.error_text'))
            .padding({ left: 18, right: 18, top: 0, bottom: 10 })
        }
        Text(this.topicNextUrl.length === 0 ? '已经到底了' : (this.topicLoadingMore ? '正在加载更多...' : '加载更多'))
          .fontSize(this.fontSecondary).fontWeight(FontWeight.Medium)
          .fontColor(
            this.topicNextUrl.length === 0 || this.topicLoadingMore
              ? $r('app.color.text_tertiary')
              : $r('app.color.action_text')
          )
          .padding({ left: 18, right: 18, top: 12, bottom: 12 })
          .margin({ top: 4, bottom: 20 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(this.pillRadius)
          .enabled(this.topicNextUrl.length > 0 && !this.topicLoadingMore)
          .onClick(() => { this.doSearchTopics(true); })
      }
    }
    .width('100%')
  }

  build() {
    Column() {
      this.SearchHeader()

      if (this.hasSearched) {
        this.SearchTabBar();
      }

      if (this.hasSearched && this.searchTab === 'general' && this.showFilterBar) {
        this.FilterBar();
      }

      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column() {
            if (this.searchTab === 'people' && this.hasSearched) {
              this.PeopleResultsList();
            } else if (this.searchTab === 'topic' && this.hasSearched) {
              this.TopicResultsList();
            } else if (this.hasSearched) {
              this.ResultsList();
            } else if (this.scopeMemberHashId.length > 0) {
              Column({ space: 8 }) {
                Text('输入关键词，查找 TA 的回答、文章、想法等')
                  .fontSize(this.fontSecondary)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 80, left: 24, right: 24 })
            } else {
              this.SearchSuggestions();
            }

            Column()
              .width('100%')
              .height(this.bottomSafeAreaVp + 24)
          }
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .onScrollEdge((side: Edge) => {
          this.handleScrollEdge(side);
        })
        .width('100%')
        .layoutWeight(1)
      }
      .onRefreshing(() => {
        this.pullToRefresh();
      })
      .width('100%')
      .layoutWeight(1)

    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
