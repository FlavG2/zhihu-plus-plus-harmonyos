import { router, promptAction } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import {
  PrivateMessageService,
  ZhihuPrivateMessage,
  ZhihuMessageAuthor,
  RichTextSegment,
  parseMessageContent
} from '../services/PrivateMessageService';
import { ThemeColors } from '../services/ThemeColors';
import { resolveZhihuContent } from '../services/ZhihuContentResolver';
import { openZhihuContentTarget } from '../services/ZhihuNavigation';

@Entry
@Component
struct PrivateMessagePage {
  @State private peerId: string = '';
  @State private peerName: string = '';
  @State private peerAvatar: string = '';
  @State private messages: ZhihuPrivateMessage[] = [];
  @State private nextUrl: string = '';
  @State private isEnd: boolean = false;
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private draft: string = '';
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    this.peerId = typeof params['peerId'] === 'string' ? (params['peerId'] as string) : '';
    this.peerName = typeof params['name'] === 'string' ? (params['name'] as string) : '';
    this.peerAvatar = typeof params['avatarUrl'] === 'string' ? (params['avatarUrl'] as string) : '';
    if (this.peerId.length === 0) {
      this.error = '缺少会话参数';
      return;
    }
    this.loadMessages(true);
  }

  private async loadMessages(reset: boolean): Promise<void> {
    if (this.loading || (reset === false && this.isEnd)) {
      return;
    }
    this.loading = true;
    this.error = '';
    try {
      const page = await PrivateMessageService.loadMessages(
        this.context(),
        this.peerId,
        reset ? undefined : this.nextUrl
      );
      // 倒序展示：服务器返回最新在前，UI 倒序使旧消息在上、新消息在下（对齐安卓 reverseLayout）
      const incoming = page.data.slice().reverse();
      if (reset) {
        this.messages = incoming;
      } else {
        this.messages = this.messages.concat(incoming);
      }
      this.nextUrl = page.paging.next;
      this.isEnd = page.paging.isEnd;
      // 首次拉取对方资料（昵称/头像兜底）
      if (reset && this.peerName.length === 0 || this.peerAvatar.length === 0) {
        const peer: ZhihuMessageAuthor | undefined = await PrivateMessageService.loadPeer(this.context(), this.peerId);
        if (peer !== undefined) {
          if (this.peerName.length === 0) {
            this.peerName = peer.name;
          }
          if (this.peerAvatar.length === 0) {
            this.peerAvatar = peer.avatarUrl;
          }
        }
      }
    } catch (e) {
      this.error = e instanceof Error ? e.message : '加载失败';
    } finally {
      this.loading = false;
    }
  }

  private parseContent(msg: ZhihuPrivateMessage): RichTextSegment[] {
    const raw = (msg.plugin !== undefined && msg.plugin.excerpt.length > 0)
      ? msg.plugin.excerpt
      : msg.content;
    if (raw.length === 0) {
      return [{ type: 'text', text: '暂不支持显示这条消息' }];
    }
    return parseMessageContent(raw);
  }

  private handleLinkClick(url: string): void {
    if (url.length === 0) {
      return;
    }
    const target = resolveZhihuContent(url);
    if (target !== undefined) {
      openZhihuContentTarget(target, '', url);
      return;
    }
    // 非知乎可解析链接：用 WebView 兜底打开
    router.pushUrl({ url: 'pages/WebContent', params: { url } }).catch(() => {});
  }

  private formatTime(epochSeconds: number): string {
    if (epochSeconds <= 0) {
      return '';
    }
    const date = new Date(epochSeconds * 1000);
    const now = new Date();
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    const hm = `${pad(date.getHours())}:${pad(date.getMinutes())}`;
    const sameDay = date.getFullYear() === now.getFullYear() &&
      date.getMonth() === now.getMonth() &&
      date.getDate() === now.getDate();
    if (sameDay) {
      return hm;
    }
    return `${date.getMonth() + 1}/${date.getDate()} ${hm}`;
  }

  private isIncoming(msg: ZhihuPrivateMessage): boolean {
    return msg.sender !== undefined &&
      (msg.sender.id === this.peerId || msg.sender.urlToken === this.peerId);
  }

  build() {
    Column() {
      // 顶栏（对齐安卓 CenterAlignedTopAppBar：对方头像 + 昵称）
      Row() {
        Image(this.peerAvatar.length > 0 ? this.peerAvatar : $r('app.media.nav_follow'))
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor($r('app.color.action_background'))
          .objectFit(ImageFit.Cover)
          .onClick(() => {
            if (this.peerAvatar.length > 0) {
              // 占位：点击头像可跳转对方主页（后续补充）
            }
          })
        Text(this.peerName.length > 0 ? this.peerName : '私信')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
          .layoutWeight(1)
        Image($r('app.media.arrow_back'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            router.back();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor(ThemeColors.chromeBackground(this.oledBlack, this.isDark))

      // 消息列表（倒序，最新在底部）
      if (this.error.length > 0) {
        Column() {
          Text(this.error)
            .fontSize(14)
            .fontColor($r('app.color.error_text'))
            .onClick(() => {
              this.loadMessages(true);
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.messages.length === 0 && !this.loading) {
        Column() {
          Text('暂无消息')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ListItem() {
            if (this.loading && this.messages.length > 0) {
              Text('加载中...')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(12)
            }
          }
          ForEach(this.messages, (msg: ZhihuPrivateMessage) => {
            ListItem() {
              this.MessageBubble(msg);
            }
          }, (msg: ZhihuPrivateMessage) => msg.stableId)
        }
        .width('100%')
        .layoutWeight(1)
        .onReachStart(() => {
          this.loadMessages(false);
        })
      }

      // 底部输入栏（只读阶段：禁用发送，仅占位）
      Row() {
        TextInput({ text: this.draft, placeholder: '发私信（暂不支持发送）' })
          .width('100%')
          .height(40)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .padding({ left: 12, right: 12 })
          .enabled(false)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor(ThemeColors.chromeBackground(this.oledBlack, this.isDark))
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topSafeAreaVp })
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
  }

  // 消息气泡（对齐安卓 PrivateMessageBubble）
  @Builder
  private MessageBubble(msg: ZhihuPrivateMessage) {
    Row() {
      if (this.isIncoming(msg)) {
        Image(msg.sender !== undefined && msg.sender.avatarUrl.length > 0
          ? msg.sender.avatarUrl : $r('app.media.nav_follow'))
          .width(34)
          .height(34)
          .borderRadius(17)
          .backgroundColor($r('app.color.action_background'))
          .objectFit(ImageFit.Cover)
          .margin({ right: 8 })
      }
      Column() {
        this.MessageContent(this.parseContent(msg), this.isIncoming(msg))
        Text(this.formatTime(msg.createdTime))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 2, left: 4 })
      }
      .alignItems(this.isIncoming(msg) ? HorizontalAlign.Start : HorizontalAlign.End)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 5, bottom: 5 })
    .justifyContent(this.isIncoming(msg) ? FlexAlign.Start : FlexAlign.End)
  }

  // 消息正文富文本：把 content 里的 <a href> 解析为可点击蓝链
  @Builder
  private MessageContent(segments: RichTextSegment[], incoming: boolean) {
    Text() {
      ForEach(segments, (seg: RichTextSegment) => {
        if (seg.type === 'link') {
          Span(seg.text)
            .fontColor($r('app.color.action_text'))
            .decoration({ type: TextDecorationType.Underline })
            .onClick(() => {
              this.handleLinkClick(seg.url ?? '');
            })
        } else {
          Span(seg.text)
        }
      }, (seg: RichTextSegment, index: number) => `${index}-${seg.text.length}`)
    }
    .fontSize(16)
    .fontColor(incoming ? $r('app.color.text_primary') : '#FFFFFF')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(incoming
      ? $r('app.color.card_background')
      : $r('app.color.action_background'))
    .borderRadius(16)
    .constraintSize({ maxWidth: '78%' })
  }
}
