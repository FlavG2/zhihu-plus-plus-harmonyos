import { router, promptAction } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { NotificationService } from '../services/NotificationService';
import { ZhihuNotification } from '../models/ZhihuNotificationModels';
import { resolveZhihuContent, resolveNotificationEntryUrl } from '../services/ZhihuContentResolver';
import { serializeZhihuContentTarget, ZhihuCommentableTarget } from '../models/ZhihuContentModels';
import { ThemeColors } from '../services/ThemeColors';
import { FilterSettingsRepository } from '../services/FilterSettingsRepository';
import { PageHeader } from '../components/PageHeader';

interface NotificationTimelineParams {
  readonly entryName?: string;
  readonly title?: string;
}

@Entry
@Component
struct NotificationTimelinePage {
  // 软尺寸：由 DesignMetrics 按「官方基线 × 用户倍率」算出后写入 AppStorage，
  // 默认值与迁移前完全一致，故视觉零变化；用户调整字号/密度后本页自动重排。
  @StorageProp('fontSymbol') private fontSymbol: string = '24fp';
  @StorageProp('fontCaption') private fontCaption: string = '12fp';
  @StorageProp('fontMeta') private fontMeta: string = '13fp';
  @StorageProp('fontSecondary') private fontSecondary: string = '14fp';
  @StorageProp('fontBody') private fontBody: string = '16fp';
  @StorageProp('fontSubhead') private fontSubhead: string = '18fp';
  @StorageProp('cardRadius') private cardRadius: number = 16;
  @StorageProp('spaceMd') private spaceMd: number = 12;
  @StorageProp('cardPadding') private cardPadding: number = 16;

  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;

  @State private entryName: string = '';
  @State private title: string = '';
  @State private items: ZhihuNotification[] = [];
  @State private nextUrl: string = '';
  @State private isEnd: boolean = false;
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private markingRead: boolean = false;
  @State private topBarHeight: number = 0;

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  aboutToAppear(): void {
    const rawParams = router.getParams();
    const empty: NotificationTimelineParams = {};
    const params: NotificationTimelineParams = rawParams !== undefined && rawParams !== null
      ? rawParams as NotificationTimelineParams
      : empty;
    this.entryName = typeof params.entryName === 'string' ? params.entryName : 'comment';
    this.title = typeof params.title === 'string' ? params.title : '通知';
    this.loadTimeline(true);
  }

  onPageShow(): void {
    // 从消息详情/文章页返回时重新拉取列表，让已读状态及时刷新
    if (!this.loading) {
      this.loadTimeline(true);
    }
  }

  private async loadTimeline(reset: boolean): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.error = '';
    try {
      const page = await NotificationService.loadNotifications(
        this.context(),
        this.entryName,
        reset ? undefined : this.nextUrl
      );
      // 对齐安卓：通知时间线直接用服务端返回顺序（不在客户端重排）
      const sorted = page.items.slice();
      if (reset) {
        this.items = sorted;
      } else {
        this.items = this.items.concat(sorted);
      }
      this.nextUrl = page.nextUrl;
      this.isEnd = page.isEnd;
      // 对齐安卓 NotificationTimelineViewModel：进入分类且已开启「自动标记已读」时，
      // 调对应 entry 的 actions/readall，把该分类标记为已读（仅在首次进入时触发）
      if (reset && FilterSettingsRepository.getBool(this.context(), 'notif_auto_read', false)) {
        try {
          await NotificationService.markAllRead(this.context(), this.entryName);
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
            contentTargetLink: it.contentTargetLink,
            subTargetLink: it.subTargetLink,
            targetSourceTargetLink: it.targetSourceTargetLink,
            headTargetLink: it.headTargetLink,
            anchorTargetLink: it.anchorTargetLink,
            targetType: it.targetType,
            targetId: it.targetId,
            unreadCount: 0
          }));
        } catch (e) {
          // 静默失败，保持 UI 稳定
        }
      }
    } catch (e) {
      this.error = e instanceof Error ? e.message : '加载失败';
    } finally {
      this.loading = false;
    }
  }

  private loadMore(): void {
    if (this.isEnd || this.loading || this.nextUrl.length === 0) {
      return;
    }
    this.loadTimeline(false);
  }

  private async markAllRead(): Promise<void> {
    if (this.markingRead) {
      return;
    }
    this.markingRead = true;
    try {
      await NotificationService.markAllRead(this.context(), this.entryName);
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
        contentTargetLink: it.contentTargetLink,
        subTargetLink: it.subTargetLink,
        targetSourceTargetLink: it.targetSourceTargetLink,
        headTargetLink: it.headTargetLink,
        anchorTargetLink: it.anchorTargetLink,
        targetType: it.targetType,
        targetId: it.targetId,
        unreadCount: 0
      }));
    } catch (e) {
      // 忽略错误，保持 UI 稳定
    } finally {
      this.markingRead = false;
    }
  }

  private openNotification(item: ZhihuNotification): void {
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
          resolvedTarget = t;
          resolvedAnchor = t.anchorCommentId ?? '';
        }
      }
    }

    if (resolvedTarget === undefined && peopleUrlToken.length > 0) {
      router.pushUrl({ url: 'pages/People', params: { urlToken: peopleUrlToken } });
      return;
    }
    if (resolvedTarget === undefined) {
      if (candidates.length > 0) {
        // 通知时间线入口（官方账号消息 / 系统消息等）：原生跳动，不进 WebView
        const entryUrl = candidates.find((l) => resolveNotificationEntryUrl(l) !== undefined);
        if (entryUrl !== undefined) {
          const entry = resolveNotificationEntryUrl(entryUrl)!;
          router.pushUrl({
            url: 'pages/NotificationTimeline',
            params: { entryName: entry.entryName, title: entry.title }
          });
          return;
        }
        // 系统消息 / 未识别通知：不跳转网页，提示暂不支持
        promptAction.showToast({ message: '暂不支持此消息' });
      }
      return;
    }

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
        params: { pinId: resolvedTarget.id, fallbackUrl, anchorCommentId }
      });
      return;
    }
    if (resolvedTarget.kind === 'message') {
      router.pushUrl({
        url: 'pages/PrivateMessage',
        params: {
          peerId: resolvedTarget.peerId,
          name: resolvedTarget.name ?? '',
          avatarUrl: item.avatarUrl
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

  // 邀请回答项：点击问题卡片跳问题页；点击「写回答/查看回答」跳写作页或回答页
  private openInvitationQuestion(item: ZhihuNotification): void {
    const link = item.targetLink.length > 0 ? item.targetLink
      : item.contentTargetLink.length > 0 ? item.contentTargetLink
      : item.headTargetLink;
    if (link.length > 0) {
      const t = resolveZhihuContent(link);
      if (t !== undefined) {
        this.openTarget(t, item.title, link);
        return;
      }
    }
    if (item.targetId.length > 0) {
      router.pushUrl({ url: 'pages/Question', params: { questionId: item.targetId, title: item.title } });
    }
  }

  private openTarget(target: ZhihuCommentableTarget, title: string, fallbackUrl: string): void {
    if (target.kind === 'question') {
      router.pushUrl({ url: 'pages/Question', params: { questionId: target.id, title, anchorCommentId: target.anchorCommentId ?? '' } });
      return;
    }
    if (target.kind === 'pin') {
      router.pushUrl({ url: 'pages/Pin', params: { pinId: target.id, fallbackUrl, anchorCommentId: target.anchorCommentId ?? '' } });
      return;
    }
    router.pushUrl({
      url: 'pages/Article',
      params: { target: serializeZhihuContentTarget(target), fallbackTitle: title, fallbackUrl, anchorCommentId: target.anchorCommentId ?? '' }
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

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // ---- 浮层顶栏：PageHeader（自带返回键 + 玻璃模糊背景）----
      PageHeader({
        title: this.title,
        rightButtons: this.items.some((it) => !it.isRead)
          ? [
              {
                icon: $r('sys.symbol.checkmark_circle'),
                action: () => {
                  this.markAllRead();
                }
              }
            ]
          : []
      })
      .zIndex(2)
      .onAreaChange((_old: Area, newValue: Area) => {
        if (newValue.height > 0 && Number(newValue.height) !== this.topBarHeight) {
          this.topBarHeight = Number(newValue.height);
        }
      })

      // ---- 列表 ----
      if (this.error.length > 0) {
        Column() {
          Text(this.error)
            .fontSize(this.fontSecondary)
            .fontColor($r('app.color.text_secondary'))
          Button('重试')
            .margin({ top: 12 })
            .onClick(() => this.loadTimeline(true))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          // 顶部让位占位：滚动时内容钻到顶栏底下，模糊生效
          ListItem() {
            Column()
              .width('100%')
              .height(this.topBarHeight)
          }

          ForEach(this.items, (item: ZhihuNotification) => {
            ListItem() {
              if (this.entryName === 'invite') {
                this.InvitationAnswerItem(item);
              } else {
                this.NotificationCard(item);
              }
            }
            .onClick(() => {
              if (this.entryName === 'invite') {
                this.openInvitationQuestion(item);
              } else {
                this.openNotification(item);
              }
            })
          }, (item: ZhihuNotification) => item.id)

          if (this.loading) {
            ListItem() {
              Row() {
                Text('加载中...')
                  .fontSize(this.fontMeta)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding(this.cardPadding)
            }
          }
        }
        .width('100%')
        .height('100%')
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => this.loadMore())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }

  // 分类详情项（对齐安卓 NotificationItemView）：左红点 + 头像 + 名字 + 动作 + 时间 + 来源卡片
  @Builder
  private NotificationCard(item: ZhihuNotification) {
    Column() {
      Row() {
        if (!item.isRead) {
          Circle()
            .width(6)
            .height(6)
            .fill('#ff4d4f')
            .margin({ top: 10, right: 6 })
        } else {
          Blank()
            .width(12)
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
          Row() {
            Text(item.title)
              .fontSize(this.fontBody)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            Text(this.formatTime(item.createdTime))
              .fontSize(this.fontCaption)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ left: 8 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          if (item.subtitle.length > 0) {
            Text(item.subtitle)
              .fontSize(this.fontMeta)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 3 })
          }

          if (item.body.length > 0) {
            Text(item.body)
              .fontSize(this.fontMeta)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 4 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 来源卡片（被评论/点赞的内容）：标题 + 统计
      if (item.sourceText.length > 0) {
        Column() {
          Text(item.sourceText)
            .fontSize(this.fontMeta)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (item.sourceLink.length > 0) {
            Text('查看内容')
              .fontSize(this.fontCaption)
              .fontColor($r('app.color.action_text'))
              .margin({ top: 6 })
          }
        }
        .width('100%')
        .padding(this.spaceMd)
        .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .borderRadius(8)
        .margin({ top: 10, left: 18, right: 16 })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 4, top: 12, bottom: 12 })
  }

  // 邀请回答项（对齐安卓 InvitationAnswerItem）：头像 + 名字 + 时间 + 问题卡片 + 写回答按钮
  @Builder
  private InvitationAnswerItem(item: ZhihuNotification) {
    Column() {
      Row() {
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
            .fontSize(this.fontBody)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Row() {
            if (item.subtitle.length > 0) {
              Text(item.subtitle)
                .fontSize(this.fontMeta)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }

            Text(this.formatTime(item.createdTime))
              .fontSize(this.fontCaption)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ left: 8 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 问题卡片
      if (item.sourceText.length > 0) {
        Column() {
          Text(item.sourceText)
            .fontSize(this.fontBody)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Row() {
            Text('写回答')
              .fontSize(this.fontMeta)
              .fontColor($r('app.color.action_text'))
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.action_background'))
              .borderRadius(this.cardRadius)
              .margin({ top: 10 })
          }
          .width('100%')
        }
        .width('100%')
        .padding(14)
        .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
        .borderRadius(14)
        .margin({ top: 10, left: 16, right: 16 })
        .onClick(() => {
          this.openInvitationQuestion(item);
        })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 4, top: 12, bottom: 12 })
  }
}
