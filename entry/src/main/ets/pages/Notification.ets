import { router, promptAction } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { NotificationService, NOTIFICATION_CATEGORIES } from '../services/NotificationService';
import { ZhihuNotification, ZhihuNotificationCategory } from '../models/ZhihuNotificationModels';
import { resolveZhihuContent } from '../services/ZhihuContentResolver';
import { serializeZhihuContentTarget, ZhihuCommentableTarget } from '../models/ZhihuContentModels';
import { ThemeColors } from '../services/ThemeColors';

@Entry
@Component
struct NotificationPage {
  @State private categories: ZhihuNotificationCategory[] = NOTIFICATION_CATEGORIES;
  @State private selectedCategory: number = 0;
  @State private items: ZhihuNotification[] = [];
  @State private nextUrl: string = '';
  @State private isEnd: boolean = false;
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private markingRead: boolean = false;
  @State private unreadCounts: Record<string, number> = {};
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  aboutToAppear(): void {
    this.loadCategory(0, true);
    this.refreshUnreadCounts();
  }

  private get totalUnread(): number {
    return Object.values(this.unreadCounts).reduce((acc, n) => acc + n, 0);
  }

  private async refreshUnreadCounts(): Promise<void> {
    try {
      this.unreadCounts = await NotificationService.loadUnreadCounts(this.context());
    } catch (e) {
      // 忽略，保持 UI 稳定
    }
  }

  private async loadCategory(index: number, reset: boolean): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.error = '';
    try {
      const category = this.categories[index];
      const page = await NotificationService.loadNotifications(this.context(), category.key, reset ? undefined : this.nextUrl);
      if (reset) {
        this.items = page.items;
      } else {
        this.items = this.items.concat(page.items);
      }
      this.nextUrl = page.nextUrl;
      this.isEnd = page.isEnd;
    } catch (e) {
      this.error = e instanceof Error ? e.message : '加载失败';
    } finally {
      this.loading = false;
    }
  }

  private onCategoryChange(index: number): void {
    if (index === this.selectedCategory) {
      return;
    }
    this.selectedCategory = index;
    this.nextUrl = '';
    this.isEnd = false;
    this.loadCategory(index, true);
  }

  private loadMore(): void {
    if (this.isEnd || this.loading || this.nextUrl.length === 0) {
      return;
    }
    this.loadCategory(this.selectedCategory, false);
  }

  private async markAllRead(): Promise<void> {
    if (this.markingRead) {
      return;
    }
    this.markingRead = true;
    try {
      const category = this.categories[this.selectedCategory];
      await NotificationService.markAllRead(this.context(), category.key);
      this.items = this.items.map<ZhihuNotification>((it) => ({
        id: it.id,
        isRead: true,
        createdTime: it.createdTime,
        avatarUrl: it.avatarUrl,
        title: it.title,
        subtitle: it.subtitle,
        body: it.body,
        sourceText: it.sourceText,
        sourceLink: it.sourceLink,
        targetLink: it.targetLink,
        anchorTargetLink: it.anchorTargetLink,
        contentTargetLink: it.contentTargetLink,
        subTargetLink: it.subTargetLink,
        targetSourceTargetLink: it.targetSourceTargetLink,
        headTargetLink: it.headTargetLink,
        targetType: it.targetType,
        targetId: it.targetId
      }));
      const updated: Record<string, number> = {};
      for (const k of Object.keys(this.unreadCounts)) {
        updated[k] = this.unreadCounts[k];
      }
      updated[category.key] = 0;
      this.unreadCounts = updated;
    } catch (e) {
      // 忽略错误，保持 UI 稳定
    } finally {
      this.markingRead = false;
    }
  }

  private openNotification(item: ZhihuNotification): void {
    // 对齐安卓 navDestination()：依次尝试候选链接；
    // 真实 API 评论深链为 notifications/v3/timeline/...（resource_type/resource_id/reply_root_id），
    // 由 resolveZhihuContent 解析出内容与锚点；people 主页链接仅作最低优先级兜底
    const candidates = [
      item.anchorTargetLink,
      item.contentTargetLink,
      item.subTargetLink,
      item.targetSourceTargetLink,
      item.headTargetLink
    ].filter((l) => l.length > 0);

    let resolvedTarget: ZhihuCommentableTarget | undefined = undefined;
    let resolvedAnchor = '';
    let peopleUrlToken = '';
    for (const link of candidates) {
      // people 主页链接仅记录，不 break、不覆盖已解析的内容目标（最低优先级兜底）
      const peopleMatch = link.match(/^https?:\/\/(?:www\.)?zhihu\.com\/people\/([^/?#]+)/i);
      if (peopleMatch !== null) {
        if (peopleUrlToken.length === 0) {
          peopleUrlToken = peopleMatch[1];
        }
        continue;
      }
      const t = resolveZhihuContent(link);
      if (t !== undefined) {
        if (resolvedTarget === undefined) {
          resolvedTarget = t;
          resolvedAnchor = t.anchorCommentId ?? '';
        } else if ((t.anchorCommentId ?? '').length > 0 && resolvedAnchor.length === 0) {
          // 升级到携带锚点的候选（comment/list 或 notifications/v3/timeline 深链）
          resolvedTarget = t;
          resolvedAnchor = t.anchorCommentId ?? '';
        }
      }
    }

    // 优先级：内容目标（含锚点） > people 主页 > 兜底（toast + 网页）
    if (resolvedTarget === undefined && peopleUrlToken.length > 0) {
      router.pushUrl({ url: 'pages/People', params: { urlToken: peopleUrlToken } });
      return;
    }
    if (resolvedTarget === undefined) {
      if (candidates.length > 0) {
        const raw = candidates[0];
        promptAction.showToast({
          message: `未识别通知链接: ${raw.length > 48 ? raw.slice(0, 48) + '…' : raw}`
        });
        router.pushUrl({ url: 'pages/WebContent', params: { url: raw } });
      }
      return;
    }

    // 锚点：通知 item 的 extra_action.data 里含目标评论 C 的真实 id（resource_type/resource_id 为所属内容），
    // 已合成 zhihu://comment/list/{type}/{id}?anchor_comment_id=C 作为首个候选，被 resolveZhihuContent 解析出
    // anchorCommentId=C。内容页 consumeAnchorComment 经 loadCommentDetail(C) 取 replyRootCommentId=A，
    // 自动置顶根评论 A 并展开其回复层、把目标回复 C 置顶，与安卓一致。
    const anchorCommentId = resolvedAnchor;
    const fallbackUrl = candidates[0];
    if (resolvedTarget.kind === 'question') {
      router.pushUrl({
        url: 'pages/Question',
        params: {
          questionId: resolvedTarget.id,
          title: (resolvedTarget.title ?? '').length > 0 ? resolvedTarget.title : item.title,
          anchorCommentId
        }
      });
      return;
    }
    if (resolvedTarget.kind === 'pin') {
      router.pushUrl({
        url: 'pages/Pin',
        params: {
          pinId: resolvedTarget.id,
          fallbackUrl,
          anchorCommentId
        }
      });
      return;
    }
    router.pushUrl({
      url: 'pages/Article',
        params: {
          target: serializeZhihuContentTarget(resolvedTarget),
          fallbackTitle: item.title,
          fallbackUrl,
          anchorCommentId
        }
    });
  }

  private formatTime(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const diff = Math.floor(Date.now() / 1000) - ts;
    if (diff < 60) {
      return '刚刚';
    }
    if (diff < 3600) {
      return `${Math.floor(diff / 60)} 分钟前`;
    }
    if (diff < 86400) {
      return `${Math.floor(diff / 3600)} 小时前`;
    }
    if (diff < 86400 * 7) {
      return `${Math.floor(diff / 86400)} 天前`;
    }
    const d = new Date(ts * 1000);
    return `${d.getMonth() + 1}-${d.getDate()}`;
  }

  private formatUnread(count: number): string {
    return count > 99 ? '99+' : `${count}`;
  }

  build() {
    Column() {
      // ---- 顶部标题栏：[‹] 消息 ............ [全部已读] [设置] ----
      Row() {
        Text('‹')
          .fontSize(26)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            router.back({ url: '' });
          })
          .padding({ left: 8, right: 4 })

        Text('消息')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        if (this.totalUnread > 0) {
          Text(this.markingRead ? '已读中...' : '全部已读')
            .fontSize(14)
            .fontColor($r('app.color.action_text'))
            .onClick(() => this.markAllRead())
            .padding({ left: 8, right: 8 })
        }

        Text('设置')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            router.pushUrl({ url: 'pages/NotificationSettings' });
          })
          .padding({ left: 8, right: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 8, right: 8, top: this.topSafeAreaVp + 12, bottom: 12 })

      // ---- 分类图标栏（4 个，对齐安卓 NotificationCategoryRow）----
      Row() {
        ForEach(this.categories, (cat: ZhihuNotificationCategory, idx: number) => {
          this.CategoryButton(cat, idx);
        }, (cat: ZhihuNotificationCategory) => cat.key)
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: 12 })
      .justifyContent(FlexAlign.SpaceEvenly)

      Divider()
        .color($r('app.color.card_border'))
        .width('100%')

      // ---- 列表 ----
      if (this.error.length > 0) {
        Column() {
          Text(this.error)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Button('重试')
            .margin({ top: 12 })
            .onClick(() => this.loadCategory(this.selectedCategory, true))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.items, (item: ZhihuNotification) => {
            ListItem() {
              this.NotificationCard(item);
            }
            .onClick(() => this.openNotification(item))
          }, (item: ZhihuNotification) => item.id)

          if (this.loading) {
            ListItem() {
              Row() {
                Text('加载中...')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding(16)
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .onReachEnd(() => this.loadMore())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
  }

  @Builder
  private CategoryButton(cat: ZhihuNotificationCategory, idx: number) {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column() {
          Image(cat.icon)
            .width(28)
            .height(28)
            .renderMode(ImageRenderMode.Template)
            .fillColor(idx === this.selectedCategory ? $r('app.color.action_text') : $r('app.color.text_primary'))
        }
        .width(48)
        .height(48)
        .borderRadius(24)
        .backgroundColor(idx === this.selectedCategory ? $r('app.color.tab_selected_background') : Color.Transparent)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        if (this.unreadOf(cat.key) > 0) {
          Text(this.formatUnread(this.unreadOf(cat.key)))
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .backgroundColor('#ff4d4f')
            .borderRadius(8)
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .margin({ top: -4, right: -4 })
        }
      }
      .width(56)
      .height(56)

      Text(cat.title)
        .fontSize(12)
        .fontColor(idx === this.selectedCategory ? $r('app.color.action_text') : $r('app.color.text_primary'))
        .margin({ top: 6 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => this.onCategoryChange(idx))
  }

  private unreadOf(key: string): number {
    const v = this.unreadCounts[key];
    return v !== undefined ? v : 0;
  }

  @Builder
  private NotificationCard(item: ZhihuNotification) {
    Column() {
      Row() {
        if (!item.isRead) {
          Circle()
            .width(6)
            .height(6)
            .fill('#ff4d4f')
            .margin({ top: 10, right: 4 })
        } else {
          Blank()
            .width(10)
        }

        if (item.avatarUrl.length > 0) {
          Image(item.avatarUrl)
            .width(44)
            .height(44)
            .borderRadius(22)
            .syncLoad(true)
            .margin({ right: 12 })
        }

        Column() {
          Text(item.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (item.subtitle.length > 0) {
            Text(item.subtitle)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 3 })
          }

          if (item.body.length > 0) {
            Text(item.body)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 4 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.formatTime(item.createdTime))
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (item.sourceText.length > 0) {
        Text(item.sourceText)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding(12)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .borderRadius(8)
          .margin({ top: 10, left: 16, right: 16 })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }
}
