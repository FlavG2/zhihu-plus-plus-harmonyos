import { router, promptAction } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { NotificationService } from '../services/NotificationService';
import { ZhihuNotification } from '../models/ZhihuNotificationModels';
import { resolveZhihuContent, resolveNotificationEntryUrl } from '../services/ZhihuContentResolver';
import { serializeZhihuContentTarget, ZhihuCommentableTarget } from '../models/ZhihuContentModels';
import { ThemeColors } from '../services/ThemeColors';

interface NotificationTimelineParams {
  readonly entryName?: string;
  readonly title?: string;
}

@Entry
@Component
struct NotificationTimelinePage {
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
    Column() {
      // ---- 顶栏 ----
      Row() {
        Text('‹')
          .fontSize(26)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            router.back({ url: '' });
          })
          .padding({ left: 8, right: 4 })

        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        if (this.items.some((it) => !it.isRead)) {
          Text(this.markingRead ? '已读中...' : '全部已读')
            .fontSize(14)
            .fontColor($r('app.color.action_text'))
            .onClick(() => this.markAllRead())
            .padding({ left: 8, right: 8 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 8, right: 8, top: this.topSafeAreaVp + 12, bottom: 12 })

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
            .onClick(() => this.loadTimeline(true))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
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
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            Text(this.formatTime(item.createdTime))
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ left: 8 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

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
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 来源卡片（被评论/点赞的内容）：标题 + 统计
      if (item.sourceText.length > 0) {
        Column() {
          Text(item.sourceText)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (item.sourceLink.length > 0) {
            Text('查看内容')
              .fontSize(12)
              .fontColor($r('app.color.action_text'))
              .margin({ top: 6 })
          }
        }
        .width('100%')
        .padding(12)
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
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Row() {
            if (item.subtitle.length > 0) {
              Text(item.subtitle)
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }

            Text(this.formatTime(item.createdTime))
              .fontSize(12)
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
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Row() {
            Text('写回答')
              .fontSize(13)
              .fontColor($r('app.color.action_text'))
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.action_background'))
              .borderRadius(16)
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
