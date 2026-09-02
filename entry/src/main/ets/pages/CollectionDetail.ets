import common from '@ohos.app.ability.common';
import { router, promptAction } from '@kit.ArkUI';
import {
  HomeFeedItem,
  ZhihuCollection
} from '../models/ZhihuModels';
import {
  ZhihuCommentableTarget,
  serializeZhihuContentTarget
} from '../models/ZhihuContentModels';
import { resolveZhihuContent } from '../services/ZhihuContentResolver';
import { CollectionService } from '../services/CollectionService';
import { AppearanceThemeMode } from '../services/AppearanceSettingsRepository';
import { PageHeader } from '../components/PageHeader';
import { ThemeColors } from '../services/ThemeColors';
import {
  exportCollectionToZip,
  saveBinaryFile,
  CollectionExportProgress,
  CollectionExportResult
} from '../services/ExportService';

function formatCounter(value: number, unit: string): string {
  if (value >= 10000) {
    return `${(value / 10000).toFixed(value >= 100000 ? 0 : 1)} 万${unit}`;
  }
  return `${value} ${unit}`;
}

function formatTime(seconds: number): string {
  if (seconds <= 0) {
    return '';
  }
  const date = new Date(seconds * 1000);
  const y = date.getFullYear();
  const m = `${date.getMonth() + 1}`.padStart(2, '0');
  const d = `${date.getDate()}`.padStart(2, '0');
  return `${y}-${m}-${d}`;
}

interface CollectionDetailParams {
  collectionId?: string;
  title?: string;
}

@Entry
@Component
struct CollectionDetail {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageProp('bottomSafeAreaVp') private bottomSafeAreaVp: number = 0;
  @State topBarHeight: number = 0;
  @StorageProp('themeMode') private themeMode: AppearanceThemeMode = 'system';
  @State private collectionId: string = '';
  @State private pageTitle: string = '收藏夹';
  @State private collection?: ZhihuCollection = undefined;
  @State private items: HomeFeedItem[] = [];
  @State private nextUrl: string = '';
  @State private isEnd: boolean = false;
  @State private loading: boolean = false;
  @State private loadingMore: boolean = false;
  @State private error: string = '';

  // ===== 整夹导出 =====
  @State private exporting: boolean = false;
  @State private exportProgress: CollectionExportProgress = {
    total: 0, processed: 0, success: 0, skipped: 0, failed: 0, currentTitle: ''
  };
  @State private exportResult: CollectionExportResult | undefined = undefined;
  @State private exportZipPath: string = '';
  @State private showExportOptionsSheet: boolean = false;
  @State private exportIncludeImages: boolean = true;
  @State private showExportProgressSheet: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as CollectionDetailParams;
    this.collectionId = typeof params.collectionId === 'string' ? params.collectionId : '';
    this.pageTitle = typeof params.title === 'string' && params.title.length > 0 ? params.title : '收藏夹';
    if (this.collectionId.length > 0) {
      this.loadAll();
    } else {
      this.error = '缺少收藏夹标识';
    }
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

  // ===== 整夹导出 =====
  private onExportClicked(): void {
    if (this.items.length === 0) {
      this.showToast('收藏夹为空，暂无可导出内容');
      return;
    }
    this.showExportOptionsSheet = true;
  }

  private async startExport(includeImages: boolean): Promise<void> {
    if (this.exporting) {
      return;
    }
    this.showExportOptionsSheet = false;
    this.exporting = true;
    this.exportResult = undefined;
    this.exportZipPath = '';
    this.showExportProgressSheet = true;

    try {
      const result = await exportCollectionToZip(
        this.context(),
        this.pageTitle,
        this.items,
        includeImages,
        (progress: CollectionExportProgress) => {
          this.exportProgress = progress;
        }
      );
      this.exportResult = result;
      if (result.zipFilePath !== undefined) {
        this.exportZipPath = result.zipFilePath;
      }
      if (result.success === 0) {
        this.showToast('没有可导出的内容');
      }
    } catch (_e) {
      this.showToast('导出失败');
    } finally {
      this.exporting = false;
    }
  }

  private async onSaveAndShare(): Promise<void> {
    if (this.exportZipPath.length === 0 || this.exportResult === undefined) {
      return;
    }
    const fileName = `zhihu++_${this.pageTitle}_zip`;
    try {
      await saveBinaryFile(this.context(), this.exportZipPath, fileName);
      this.showExportProgressSheet = false;
      this.showToast('已保存');
    } catch (_e) {
      this.showToast('保存失败');
    }
  }

  @Builder
  private ExportOptionsSheet(): void {
    Column({ space: 16 }) {
      Text('选择导出内容')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Row() {
        Text('包含图片（勾选后图片将下载并内联到 HTML）')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.exportIncludeImages })
          .onChange((isOn: boolean) => {
            this.exportIncludeImages = isOn;
          })
      }
      .width('100%')

      Button('开始导出')
        .width('100%')
        .height(44)
        .type(ButtonType.Capsule)
        .backgroundColor($r('app.color.action_text'))
        .fontColor('#FFFFFFFF')
        .onClick(() => {
          this.startExport(this.exportIncludeImages);
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 24 })
  }

  @Builder
  private ExportProgressSheet(): void {
    Column({ space: 16 }) {
      Progress({
        value: this.exportProgress.total > 0
          ? Math.round((this.exportProgress.processed / this.exportProgress.total) * 100)
          : 0,
        total: 100,
        type: ProgressType.Linear
      })
      .width('100%')

      Text(this.exporting
        ? `处理中 ${this.exportProgress.processed}/${this.exportProgress.total} · 成功 ${this.exportProgress.success} · 失败 ${this.exportProgress.failed}`
        : `完成：成功 ${this.exportResult?.success ?? 0}，跳过 ${this.exportResult?.skipped ?? 0}，失败 ${this.exportResult?.failed ?? 0}`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      if (this.exportProgress.currentTitle.length > 0 && this.exporting) {
        Text(this.exportProgress.currentTitle)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Row({ space: 12 }) {
        if (!this.exporting && this.exportZipPath.length > 0) {
          Button('保存到本地')
            .layoutWeight(1)
            .height(40)
            .type(ButtonType.Capsule)
            .backgroundColor($r('app.color.action_text'))
            .fontColor('#FFFFFFFF')
            .onClick(() => {
              this.onSaveAndShare();
            })
        }
        Button(this.exporting ? '后台运行' : '完成')
          .layoutWeight(1)
          .height(40)
          .type(ButtonType.Capsule)
          .backgroundColor(ThemeColors.cardBackground(false, false))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.showExportProgressSheet = false;
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 24 })
  }

  private async loadAll(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      const info = await CollectionService.loadCollectionInfo(this.context(), this.collectionId);
      if (info !== undefined) {
        this.collection = info;
        this.pageTitle = info.title.length > 0 ? info.title : this.pageTitle;
      }
      const page = await CollectionService.loadCollectionItems(this.context(), this.collectionId);
      this.items = page.items;
      this.nextUrl = page.paging.nextUrl;
      this.isEnd = page.paging.isEnd;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.error = `收藏夹加载失败：${message}`;
    } finally {
      this.loading = false;
    }
  }

  private async loadMore(): Promise<void> {
    if (this.loadingMore || this.isEnd || this.nextUrl.length === 0) {
      return;
    }
    this.loadingMore = true;
    try {
      const page = await CollectionService.loadCollectionItems(this.context(), this.collectionId, this.nextUrl);
      this.items = [...this.items, ...page.items];
      this.nextUrl = page.paging.nextUrl;
      this.isEnd = page.paging.isEnd;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.showToast(`加载失败：${message}`);
    } finally {
      this.loadingMore = false;
    }
  }

  private openItem(item: HomeFeedItem): void {
    if (item.nativeTarget !== undefined) {
      this.openNativeArticle(item.nativeTarget, item.title, item.targetUrl);
      return;
    }
    const resolved = resolveZhihuContent(item.targetUrl);
    if (resolved !== undefined) {
      this.openNativeArticle(resolved, item.title, item.targetUrl);
      return;
    }
    router.pushUrl({
      url: 'pages/WebContent',
      params: { title: item.title, url: item.targetUrl }
    });
  }

  private openNativeArticle(
    target: ZhihuCommentableTarget,
    fallbackTitle: string,
    fallbackUrl: string
  ): void {
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

      Text(this.pageTitle)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topSafeAreaVp + 12, bottom: 12 })
    .backgroundColor($r('app.color.glass_top_bar_background'))
    .border({
      width: { bottom: 1 },
      color: $r('app.color.glass_top_bar_border')
    })
    .backdropBlur(24)
  }

  private collectionStatsText(): string {
    if (this.collection === undefined) {
      return '';
    }
    const parts: string[] = [];
    if (this.collection.itemCount > 0) {
      parts.push(`${formatCounter(this.collection.itemCount, ' 条收藏')}`);
    }
    if (this.collection.likeCount > 0) {
      parts.push(`${formatCounter(this.collection.likeCount, ' 个赞同')}`);
    }
    if (this.collection.commentCount > 0) {
      parts.push(`${formatCounter(this.collection.commentCount, ' 条评论')}`);
    }
    const updated = formatTime(this.collection.updatedTime);
    if (updated.length > 0) {
      parts.push(`${updated} 更新`);
    }
    return parts.join(' · ');
  }

  @Builder
  private StatsHeader(): void {
    if (this.collectionStatsText().length > 0) {
      Text(this.collectionStatsText())
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 12 })
    }
  }

  @Builder
  private FeedCard(item: HomeFeedItem): void {
    Row({ space: 12 }) {
      Column({ space: 6 }) {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (item.authorName.length > 0) {
          Text(`${item.authorName}${item.authorHeadline.length > 0 ? ' · ' + item.authorHeadline : ''}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        if (item.summary.length > 0) {
          Text(item.summary)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .lineHeight(21)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Row({ space: 12 }) {
          if (item.voteCount > 0) {
            Text(formatCounter(item.voteCount, ' 赞同'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          if (item.commentCount > 0) {
            Text(formatCounter(item.commentCount, ' 评论'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (item.thumbnailUrl.length > 0) {
        Image(item.thumbnailUrl)
          .width(96)
          .height(72)
          .objectFit(ImageFit.Cover)
          .borderRadius(10)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.card_border') })
    .onClick(() => {
      this.openItem(item);
    })
  }

  @Builder
  private ListFooter(): void {
    if (this.loading && this.items.length === 0) {
      Text('正在加载内容…')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 24, bottom: 24 })
    } else if (this.error.length > 0 && this.items.length === 0) {
      Column({ space: 12 }) {
        Text(this.error)
          .fontSize(14)
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
            this.loadAll();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 40, bottom: 40 })
    } else if (this.items.length === 0) {
      Text('这个收藏夹还是空的')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 40, bottom: 40 })
    } else if (this.loadingMore) {
      Text('正在加载更多…')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 16, bottom: 16 })
    } else if (this.isEnd) {
      Text('没有更多内容了')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 16, bottom: 16 })
    } else {
      Text('加载更多')
        .fontSize(12)
        .fontColor($r('app.color.action_text'))
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.page_background'))
        .borderRadius(16)
        .border({ width: 1, color: $r('app.color.card_border') })
        .onClick(() => {
          this.loadMore();
        })
        .margin({ top: 8, bottom: 8 })
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // ===== 背景内容层：List 直接放 Stack，包含 StatsHeader 当第一个 ListItem =====
      List({ space: 12 }) {
        // 顶部让位占位（同通知页写法）：滚动时内容钻到顶栏底下，模糊生效
        ListItem() {
          Column()
            .width('100%')
            .height(this.topBarHeight)
        }

        // StatsHeader 放在 List 里，跟随滑动
        if (this.collectionStatsText().length > 0) {
          ListItem() {
            Text(this.collectionStatsText())
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ left: 16, right: 16, top: 8, bottom: 4 })
          }
        }

        ForEach(this.items, (item: HomeFeedItem) => {
          ListItem() {
            this.FeedCard(item);
          }
        }, (item: HomeFeedItem) => item.id)

        ListItem() {
          this.ListFooter();
        }
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onReachEnd(() => {
        this.loadMore();
      })
      .padding({ left: 16, right: 16, bottom: this.bottomSafeAreaVp + 16 })

      // ===== 浮层顶栏（showBack 默认 true 自带返回键，右侧只放导出） =====
      PageHeader({
        title: this.pageTitle,
        rightButtons: [
          {
            icon: $r('sys.symbol.square_and_arrow_down'),
            action: () => { this.onExportClicked(); }
          }
        ]
      })
      .zIndex(2)
      .onAreaChange((_old: Area, newValue: Area) => {
        if (newValue.height > 0 && Number(newValue.height) !== this.topBarHeight) {
          this.topBarHeight = Number(newValue.height);
        }
      })

      // ===== 导出选项 Sheet =====
      Column() {}
        .width(1)
        .height(1)
        .bindSheet($$this.showExportOptionsSheet, this.ExportOptionsSheet(), {
          showClose: true,
          dragBar: true,
          preferType: SheetType.BOTTOM
        })

      // ===== 导出进度 Sheet =====
      Column() {}
        .width(1)
        .height(1)
        .bindSheet($$this.showExportProgressSheet, this.ExportProgressSheet(), {
          showClose: true,
          dragBar: true,
          preferType: SheetType.BOTTOM
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(false, false))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
