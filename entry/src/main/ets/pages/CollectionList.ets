import common from '@ohos.app.ability.common';
import { router, promptAction } from '@kit.ArkUI';
import { AppearanceThemeMode } from '../services/AppearanceSettingsRepository';
import { CollectionService } from '../services/CollectionService';
import { ZhihuCollection, ZhihuSessionData, SessionSnapshot, DEFAULT_SESSION_SNAPSHOT } from '../models/ZhihuModels';
import { ZhihuSessionRepository } from '../services/ZhihuSessionRepository';
import { ThemeColors } from '../services/ThemeColors';

function formatCounter(value: number, unit: string): string {
  if (value >= 10000) {
    return `${(value / 10000).toFixed(value >= 100000 ? 0 : 1)} 万${unit}`;
  }
  return `${value} ${unit}`;
}

@Entry
@Component
struct CollectionList {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageProp('bottomSafeAreaVp') private bottomSafeAreaVp: number = 0;
  @StorageProp('themeMode') private themeMode: AppearanceThemeMode = 'system';
  @StorageProp('sessionSnapshot') private sessionSnapshot: SessionSnapshot = DEFAULT_SESSION_SNAPSHOT;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;
  @State private collections: ZhihuCollection[] = [];
  @State private nextUrl: string = '';
  @State private isEnd: boolean = false;
  @State private loading: boolean = false;
  @State private loadingMore: boolean = false;
  @State private error: string = '';
  @State private urlToken: string = '';
  @State private showCreateDialog: boolean = false;
  @State private newCollectionTitle: string = '';
  @State private newCollectionDesc: string = '';
  @State private newCollectionPublic: boolean = false;
  @State private creatingCollection: boolean = false;

  aboutToAppear(): void {
    const data: ZhihuSessionData = ZhihuSessionRepository.load(this.context() as common.Context);
    this.urlToken = data.self?.urlToken ?? '';
    if (this.urlToken.length > 0) {
      this.loadFirstPage();
    } else {
      this.error = '请先登录后再查看收藏夹';
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

  private async loadFirstPage(): Promise<void> {
    if (this.loading || this.urlToken.length === 0) {
      return;
    }
    this.loading = true;
    this.error = '';
    try {
      const page = await CollectionService.loadUserCollections(this.context(), this.urlToken);
      this.collections = page.items;
      this.nextUrl = page.nextUrl;
      this.isEnd = page.isEnd;
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
      const page = await CollectionService.loadUserCollections(this.context(), this.urlToken, this.nextUrl);
      this.collections = [...this.collections, ...page.items];
      this.nextUrl = page.nextUrl;
      this.isEnd = page.isEnd;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.showToast(`加载失败：${message}`);
    } finally {
      this.loadingMore = false;
    }
  }

  private openCollection(collection: ZhihuCollection): void {
    if (collection.id.length === 0) {
      return;
    }
    router.pushUrl({
      url: 'pages/CollectionDetail',
      params: {
        collectionId: collection.id,
        title: collection.title
      }
    });
  }

  private async submitNewCollection(): Promise<void> {
    const title = this.newCollectionTitle.trim();
    if (title.length === 0 || this.creatingCollection) {
      return;
    }
    this.creatingCollection = true;
    try {
      await CollectionService.createCollection(
        this.context(),
        title,
        this.newCollectionDesc.trim(),
        this.newCollectionPublic
      );
      this.newCollectionTitle = '';
      this.newCollectionDesc = '';
      this.newCollectionPublic = false;
      this.showCreateDialog = false;
      this.showToast('收藏夹已创建');
      // 重新加载列表并把新建项置顶
      this.collections = [];
      this.nextUrl = '';
      this.isEnd = false;
      await this.loadFirstPage();
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.showToast(`创建失败：${message}`);
    } finally {
      this.creatingCollection = false;
    }
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

      Text('我的收藏夹')
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

  @Builder
  private CollectionCard(collection: ZhihuCollection): void {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(collection.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (collection.description.length > 0) {
          Text(collection.description)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Row({ space: 12 }) {
          Text(formatCounter(collection.itemCount, ' 篇内容'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))

          if (collection.likeCount > 0) {
            Text(formatCounter(collection.likeCount, ' 赞同'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.card_border') })
    .onClick(() => {
      this.openCollection(collection);
    })
  }

  @Builder
  private ListFooter(): void {
    if (this.loading && this.collections.length === 0) {
      Text('正在加载收藏夹…')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 24, bottom: 24 })
    } else if (this.error.length > 0 && this.collections.length === 0) {
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
            this.loadFirstPage();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 40, bottom: 40 })
    } else if (this.collections.length === 0) {
      Text('还没有收藏夹')
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
      Text('没有更多收藏夹了')
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
        .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
        .borderRadius(16)
        .border({ width: 1, color: $r('app.color.card_border') })
        .onClick(() => {
          this.loadMore();
        })
        .margin({ top: 8, bottom: 8 })
    }
  }

  @Builder
  private CreateCollectionDialog(): void {
    if (this.showCreateDialog) {
      Column() {
      Column({ space: 0 }) {
        Row({ space: 8 }) {
          Text('新建收藏夹')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Text('取消')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .onClick(() => {
              this.showCreateDialog = false;
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
          .borderRadius(12)
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
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.card_border') })
          .padding({ left: 14, right: 14 })
          .margin({ bottom: 12 })
          .onChange((value: string) => {
            this.newCollectionDesc = value;
          })

        Row({ space: 10 }) {
          Text('公开收藏夹')
            .fontSize(14)
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
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.newCollectionTitle.trim().length === 0 || this.creatingCollection
            ? $r('app.color.text_tertiary')
            : $r('app.color.action_text'))
          .padding({ left: 16, right: 16, top: 11, bottom: 11 })
          .backgroundColor(this.newCollectionTitle.trim().length === 0
            ? ThemeColors.articleBackground(this.oledBlack, this.isDark)
            : $r('app.color.action_background'))
          .borderRadius(20)
          .border({ width: 1, color: $r('app.color.card_border') })
          .alignSelf(ItemAlign.End)
          .enabled(this.newCollectionTitle.trim().length > 0 && !this.creatingCollection)
          .onClick(() => {
            this.submitNewCollection();
          })
      }
      .width('86%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .borderRadius(16)
      .border({ width: 1, color: $r('app.color.card_border') })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showCreateDialog = false;
    })
    }
  }

  build() {
    Stack() {
      Column() {
        this.TopBar()

        List({ space: 12 }) {
        ForEach(this.collections, (collection: ZhihuCollection) => {
          ListItem() {
            this.CollectionCard(collection);
          }
        }, (collection: ZhihuCollection) => collection.id)

        ListItem() {
          this.ListFooter();
        }
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onReachEnd(() => {
        this.loadMore();
      })
      .padding({ left: 16, right: 16, top: 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 右下角创建收藏夹按钮（安卓方形 + 居中加号）
      if (this.urlToken.length > 0) {
        Column() {
          Text('＋')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFFFF')
        }
        .width(52)
        .height(52)
        .borderRadius(14)
        .align(Alignment.Center)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.action_text'))
        .shadow({ radius: 8, color: '#20000000', offsetY: 2 })
        .position({ right: 20, bottom: this.bottomSafeAreaVp + 24 })
        .onClick(() => {
          this.showCreateDialog = true;
        })
      }

      this.CreateCollectionDialog()
    }
    .width('100%')
    .height('100%')
  }
}
