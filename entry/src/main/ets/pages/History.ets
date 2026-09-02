import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import common from '@ohos.app.ability.common';
import { BrowsingHistoryRepository } from '../services/BrowsingHistoryRepository';
import { CloudHistoryService } from '../services/CloudHistoryService';
import { resolveZhihuContent } from '../services/ZhihuContentResolver';
import { serializeZhihuContentTarget, ZhihuCommentableTarget } from '../models/ZhihuContentModels';
import { HomeFeedItem } from '../models/ZhihuModels';
import { ThemeColors } from '../services/ThemeColors';
import { PageHeader } from '../components/PageHeader';

@Entry
@Component
struct HistoryPage {
  @State private historyItems: HomeFeedItem[] = [];
  @State private mergedHistoryItems: HomeFeedItem[] = [];
  @State private cloudHistoryItems: HomeFeedItem[] = [];
  @State private cloudHistoryLoading: boolean = false;
  @State private cloudHistoryLoadingMore: boolean = false;
  @State private cloudHistoryNextUrl: string = '';
  @State private cloudHistoryIsEnd: boolean = false;
  @State private cloudHistoryError: string = '';
  @State private refreshing: boolean = false;
  @State private currentTab: 'cloud' | 'local' = 'cloud';
  @State private showClearConfirm: boolean = false;
  @StorageLink('oledBlack') oledBlack: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @State topBarHeight: number = 0;

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  aboutToAppear(): void {
    this.loadHistoryItems();
    this.loadCloudHistory();
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

    // 2. 追加云端历史（去重）
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
    if (this.currentTab === 'cloud') {
      // 仅清空云端：下推服务器并清空云端数组，不动本地
      this.cloudHistoryItems = [];
      this.cloudHistoryNextUrl = '';
      this.cloudHistoryIsEnd = true;
      this.cloudHistoryError = '';
      CloudHistoryService.clearHistory(this.context());
    } else {
      // 仅清空本地：不动云端
      this.historyItems = BrowsingHistoryRepository.clear(this.context());
    }
    this.rebuildMergedList();
  }

  private async loadCloudHistory(): Promise<void> {
    if (this.cloudHistoryLoading) {
      this.refreshing = false;
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
      this.refreshing = false;
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

  // 刷新：先把本地历史上传到云端，再强制下拉云端最新数据
  private async refreshAll(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    try {
      const uploadable = this.historyItems.filter((it) => it.nativeTarget !== undefined);
      await Promise.allSettled(
        uploadable.map((it) => CloudHistoryService.reportViaTarget(this.context(), it.nativeTarget!))
      );
      await this.loadCloudHistory();
    } catch (_) {
      // 静默
    } finally {
      this.refreshing = false;
    }
  }

  // 下拉刷新（按当前 Tab 分发）
  private onHistoryRefresh(): void {
    this.refreshing = true;
    if (this.currentTab === 'cloud') {
      this.loadCloudHistory();
    } else {
      this.loadHistoryItems();
      this.refreshing = false;
    }
  }

  private get historyHint(): string {
    return this.currentTab === 'cloud'
      ? '云端记录来自知乎服务器（按当前账号）。清空与删除该条都会同步到云端。'
      : '本地记录仅存于本机、不随账号变化。清空与删除只影响本地。';
  }

  @Builder
  private HeaderTitleContent(): void {
    Row() {
      Text('历史')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .margin({ right: 10 })

      Row({ space: 0 }) {
        Text('云端')
          .fontSize(13)
          .fontWeight(this.currentTab === 'cloud' ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.currentTab === 'cloud' ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius({ topLeft: 12, bottomLeft: 12 })
          .backgroundColor(this.currentTab === 'cloud'
            ? (this.isDark ? '#1AFFFFFF' : '#0D000000')
            : Color.Transparent)
          .onClick(() => {
            this.currentTab = 'cloud';
          })
        Text('本地')
          .fontSize(13)
          .fontWeight(this.currentTab === 'local' ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.currentTab === 'local' ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius({ topRight: 12, bottomRight: 12 })
          .backgroundColor(this.currentTab === 'local'
            ? (this.isDark ? '#1AFFFFFF' : '#0D000000')
            : Color.Transparent)
          .onClick(() => {
            this.currentTab = 'local';
          })
      }
      .backgroundColor(this.isDark ? '#0DFFFFFF' : '#08000000')
      .borderRadius(12)
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private HistoryListContent(): void {
    if (this.currentTab === 'cloud') {
      if (this.cloudHistoryItems.length === 0 && !this.cloudHistoryLoading) {
        Column({ space: 10 }) {
          Text('暂无云端浏览历史')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text('登录账号后在知乎的浏览记录会显示在这里。')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .padding({ top: 60, left: 28, right: 28 })
      } else {
        ForEach(this.cloudHistoryItems, (item: HomeFeedItem) => {
          this.HistoryFeedCard(item);
        }, (item: HomeFeedItem) => item.id)

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
    } else {
      if (this.historyItems.length === 0) {
        Column({ space: 10 }) {
          Text('暂无本地浏览历史')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text('在本机打开过的链接和内容会记录在本地，不会随账号变化。')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .padding({ top: 60, left: 28, right: 28 })
      } else {
        ForEach(this.historyItems, (item: HomeFeedItem) => {
          this.HistoryFeedCard(item);
        }, (item: HomeFeedItem) => item.id)
      }
    }
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
    if (this.currentTab === 'cloud') {
      // 从云端数组移除，并下推服务器真正删除（对齐安卓 batch_del）
      this.cloudHistoryItems = this.cloudHistoryItems.filter((it) => it.id !== item.id);
      if (item.nativeTarget !== undefined) {
        CloudHistoryService.deleteHistoryItem(
          this.context(),
          item.nativeTarget.id,
          item.nativeTarget.kind
        );
      }
    } else {
      // 本地：仅删除本机记录
      this.historyItems = BrowsingHistoryRepository.removeItem(this.context(), item.id);
    }
    this.rebuildMergedList();
  }

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
    .padding(14)
    .margin({ bottom: 12 })
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

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // ===== 内容层：Refresh 直接占满 Stack，首元素是顶栏让位占位条，
      // 滚动时内容钻到顶栏底下，PageHeader 的 backdropBlur 才能糊到东西 =====
      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column({ space: 8 }) {
            // 顶部让位占位（同通知页写法）：高度 = 顶栏实测高
            Column()
              .width('100%')
              .height(this.topBarHeight)

            // 提示行（跟随滚动）
            Text(this.historyHint)
              .fontSize(12)
              .lineHeight(18)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            this.HistoryListContent()

            Column()
              .height(24)
              .width('100%')
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 24, right: 24, top: 8, bottom: 8 })
        }
        .height('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .onRefreshing(() => {
        this.onHistoryRefresh();
      })

      // ===== 浮层顶栏：[‹] 历史  [云端|本地居中]  (刷新)(清空) =====
      PageHeader({
        titleSlot: () => {
          this.HeaderTitleContent()
        },
        rightButtons: [
          {
            icon: $r('sys.symbol.arrow_clockwise'),
            action: () => {
              if (!this.refreshing) {
                if (this.currentTab === 'cloud') {
                  this.refreshAll();
                } else {
                  this.loadHistoryItems();
                  this.refreshing = false;
                }
              }
            }
          },
          {
            icon: $r('sys.symbol.trash'),
            action: () => {
              const hasItems = this.currentTab === 'cloud'
                ? this.cloudHistoryItems.length > 0
                : this.historyItems.length > 0;
              if (hasItems) {
                this.showClearConfirm = true;
              }
            }
          }
        ]
      })
      .zIndex(2)
      .onAreaChange((_old: Area, newValue: Area) => {
        if (newValue.height > 0 && Number(newValue.height) !== this.topBarHeight) {
          this.topBarHeight = Number(newValue.height);
        }
      })

      // ===== 清空确认弹窗 =====
      if (this.showClearConfirm) {
        Column() {
          Column({ space: 16 }) {
            Text(this.currentTab === 'cloud' ? '清空云端浏览记录' : '清空本地浏览记录')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .textAlign(TextAlign.Start)
            Text(this.currentTab === 'cloud'
              ? '确定要清空所有云端浏览记录吗？此操作不可恢复，将同步删除知乎服务器上的记录。'
              : '确定要清空所有本地浏览记录吗？此操作不可恢复。')
              .fontSize(14)
              .lineHeight(20)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
                .fontColor($r('app.color.text_primary'))
                .onClick(() => {
                  this.showClearConfirm = false;
                })
              Button('确认清空')
                .layoutWeight(1)
                .backgroundColor($r('app.color.action_text'))
                .fontColor('#FFFFFFFF')
                .onClick(() => {
                  this.showClearConfirm = false;
                  this.clearHistoryItems();
                })
            }
            .width('100%')
            .margin({ top: 18 })
          }
          .width('86%')
          .padding(20)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(16)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showClearConfirm = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
