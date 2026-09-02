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
import { ZhihuEmojiService, EmojiPickerItem } from '../services/ZhihuEmojiService';
import { PageHeader } from '../components/PageHeader';

@Entry
@Component
struct PrivateMessagePage {
  // 软尺寸：由 DesignMetrics 按「官方基线 × 用户倍率」算出后写入 AppStorage，
  // 默认值与迁移前完全一致，故视觉零变化；用户调整字号/密度后本页自动重排。
  @StorageProp('fontCaption') private fontCaption: string = '12fp';
  @StorageProp('fontMeta') private fontMeta: string = '13fp';
  @StorageProp('fontSecondary') private fontSecondary: string = '14fp';
  @StorageProp('fontBody') private fontBody: string = '16fp';
  @StorageProp('cardRadius') private cardRadius: number = 16;
  @StorageProp('buttonRadius') private buttonRadius: number = 20;
  @StorageProp('spaceMd') private spaceMd: number = 12;
  @StorageProp('fontSymbol') private fontSymbol: string = '24fp';
  @StorageProp('fontLargeTitle') private fontLargeTitle: string = '26fp';
  @StorageProp('fontDisplayLg') private fontDisplayLg: string = '28fp';

  @State private peerId: string = '';
  @State private peerName: string = '';
  @State private peerAvatar: string = '';
  // 是否「官方账号助手」会话：该会话最新消息置顶（其余会话最新置底），对齐知乎官方客户端
  @State private isOfficialPeer: boolean = false;
  @State private listVisible: boolean = false;
  @State private messages: ZhihuPrivateMessage[] = [];
  @State private nextUrl: string = '';
  @State private isEnd: boolean = false;
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private draft: string = '';
  @State private sending: boolean = false;
  @State private showEmojiPanel: boolean = false;
  @State private emojiItems: EmojiPickerItem[] = [];
  @State private emojiCols: number = 7;
  @State private draftCaret: number = 0;
  private inputController: TextInputController = new TextInputController();
  private listScroller: ListScroller = new ListScroller();
  @StorageProp('bottomSafeAreaVp') private bottomSafeAreaVp: number = 0;
  @State topBarHeight: number = 0;
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
    // 官方账号助手会话：按昵称识别（导航仅传 peerId/name/avatarUrl，模型无官方标识字段）
    this.isOfficialPeer = (this.peerName === '官方账号助手');
    if (this.peerId.length === 0) {
      this.error = '缺少会话参数';
      return;
    }
    this.loadMessages(true);
    // 确保知乎表情数据就绪，用于表情选择器渲染原版贴纸图（对齐评论页逻辑）
    ZhihuEmojiService.initialize(this.context())
      .then(() => { this.emojiItems = ZhihuEmojiService.getEmojiPickerItems(); })
      .catch(() => {});
  }

  // 发送私信：调服务层加密并 POST，成功后把服务端返回的消息插入列表末尾（倒序展示即显示最底部）
  private async handleSend(): Promise<void> {
    const text = this.draft.trim();
    if (text.length === 0 || this.sending) {
      return;
    }
    this.sending = true;
    try {
      const msg = await PrivateMessageService.sendMessage(this.context(), this.peerId, text);
      // 官方账号助手会话最新置顶 → 新消息插到顶部；普通会话最新置底 → 插到底部
      this.messages = this.isOfficialPeer
        ? [msg].concat(this.messages)
        : this.messages.concat([msg]);
      // 普通会话发送后定位到最新（底部）；官方账号助手置顶插入，无需滚动
      if (!this.isOfficialPeer) {
        setTimeout(() => {
          if (this.messages.length > 0) {
            this.listScroller.scrollToIndex(this.messages.length - 1, false, ScrollAlign.END);
          }
        }, 0);
      }
      this.draft = '';
      this.draftCaret = 0;
    } catch (e) {
      promptAction.showToast({
        message: e instanceof Error ? e.message : '发送失败'
      });
    } finally {
      this.sending = false;
    }
  }

  private emojiColumnsTemplate(): string {
    return Array(this.emojiCols).fill('1fr').join(' ');
  }

  // 表情面板：对齐评论页 EmojiPanel，单一草稿 + 光标插入（B 方案）
  @Builder
  private EmojiPanel(): void {
    Grid() {
      ForEach(this.emojiItems, (item: EmojiPickerItem) => {
        GridItem() {
          if (item.dataUrl !== undefined) {
            Image(item.dataUrl)
              .width(30)
              .height(30)
              .objectFit(ImageFit.Contain)
          } else {
            Text(item.fallback ?? '')
              .fontSize(this.fontSymbol)
              .textAlign(TextAlign.Center)
              .width('100%')
              .height('100%')
              .maxLines(1)
          }
        }
        .width('100%')
        .aspectRatio(1)
        .onClick(() => {
          const draft = this.draft;
          const caret = this.draftCaret;
          const insert = `[${item.token}]`;
          const safeCaret = caret >= 0 && caret <= draft.length ? caret : draft.length;
          const next = draft.slice(0, safeCaret) + insert + draft.slice(safeCaret);
          const newCaret = safeCaret + insert.length;
          this.draft = next;
          this.draftCaret = newCaret;
          this.inputController.caretPosition(newCaret);
        })
      }, (item: EmojiPickerItem) => item.token)
    }
    .columnsTemplate(this.emojiColumnsTemplate())
    .columnsGap(8)
    .rowsGap(8)
    .onAreaChange((_old: Area, newValue: Area) => {
      const w = Number(newValue.width);
      if (w > 0) {
        const cols = Math.max(4, Math.floor((w + 8) / (48 + 8)));
        if (cols !== this.emojiCols) {
          this.emojiCols = cols;
        }
      }
    })
    .padding({ left: 12, right: 12, top: 12, bottom: this.bottomSafeAreaVp + 12 })
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
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
      // 排序规则（对齐知乎官方客户端）：
      //   普通会话 → 按时间升序，最新在底部；官方账号助手 → 按时间降序，最新在顶部。
      // 翻页方向：普通会话更早的消息在前（顶部），官方账号助手更早的消息在后（底部）。
      const incoming = this.isOfficialPeer
        ? page.data.slice().sort((a, b) => b.createdTime - a.createdTime)
        : page.data.slice().sort((a, b) => a.createdTime - b.createdTime);
      if (reset) {
        this.messages = incoming;
        // 普通会话最新在底部：首次加载后瞬时滚到底，滚完再显示，避免首帧露出最旧消息
        if (!this.isOfficialPeer) {
          setTimeout(() => {
            if (this.messages.length > 0) {
              this.listScroller.scrollToIndex(this.messages.length - 1, false, ScrollAlign.END);
            }
            this.listVisible = true;
          }, 0);
        } else {
          // 官方账号助手最新在顶部（索引 0），无需滚动，直接显示
          this.listVisible = true;
        }
      } else if (this.isOfficialPeer) {
        this.messages = this.messages.concat(incoming);
      } else {
        this.messages = incoming.concat(this.messages);
      }
      this.nextUrl = page.paging.next;
      this.isEnd = page.paging.isEnd;
      // 首次拉取对方资料（昵称/头像兜底）
      if (reset && this.peerName.length === 0 || this.peerAvatar.length === 0) {
        const peer: ZhihuMessageAuthor | undefined = await PrivateMessageService.loadPeer(this.context(), this.peerId);
        if (peer !== undefined) {
          if (this.peerName.length === 0) {
            this.peerName = peer.name;
            //  nickname 兜底到 API 后再次判定是否官方账号助手
            this.isOfficialPeer = (peer.name === '官方账号助手');
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
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    // 对齐安卓私信时间戳：MM-DD HH:mm
    return `${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
  }

  private isIncoming(msg: ZhihuPrivateMessage): boolean {
    return msg.sender !== undefined &&
      (msg.sender.id === this.peerId || msg.sender.urlToken === this.peerId);
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      PageHeader({ title: this.peerName.length > 0 ? this.peerName : '私信' })
        .zIndex(2)
        .onAreaChange((_old: Area, newValue: Area) => {
          if (newValue.height > 0) {
            this.topBarHeight = Number(newValue.height);
          }
        })

      Column() {
      // 消息列表（倒序，最新在底部）
      if (this.error.length > 0) {
        Column() {
          Text(this.error)
            .fontSize(this.fontSecondary)
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
            .fontSize(this.fontSecondary)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ scroller: this.listScroller, space: 0 }) {
          ListItem() {
            if (this.loading && this.messages.length > 0) {
              Text('加载中...')
                .fontSize(this.fontMeta)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(this.spaceMd)
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
        .visibility(this.listVisible ? Visibility.Visible : Visibility.Hidden)
        .onReachStart(() => {
          this.loadMessages(false);
        })
      }

      // 底部输入栏（对齐评论玻璃胶囊：输入区 + 表情(暂未开放) + 纸飞机发送，统一沉浸胶囊）
      Row() {
        Row({ space: 8 }) {
          TextInput({ controller: this.inputController, text: this.draft, placeholder: '发私信' })
            .layoutWeight(1)
            .height(40)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .padding({ left: 6, right: 6 })
            .onChange((value: string) => {
              this.draft = value;
            })
            .onTextSelectionChange((_start: number, end: number) => {
              this.draftCaret = end;
            })
            .onFocus(() => {
              this.showEmojiPanel = false;
            })

          // 表情功能暂未开放（真机验证私信无法渲染表情，先封掉）
          SymbolGlyph($r('sys.symbol.face_smiling'))
            .fontSize(this.fontLargeTitle)
            .fontColor([$r('app.color.text_secondary')])
            .margin({ left: 8, right: 4 })
            .onClick(() => {
              promptAction.showToast({ message: '表情功能暂未开放' });
            })

          // 发送
          SymbolGlyph($r('sys.symbol.paperplane'))
            .fontSize(this.fontDisplayLg)
            .fontColor([this.draft.trim().length > 0
              ? $r('app.color.action_background')
              : $r('app.color.text_tertiary')])
            .margin({ left: 4, right: 8 })
            .enabled(this.draft.trim().length > 0 && !this.sending)
            .onClick(() => {
              this.handleSend();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 8, top: 5, bottom: 5 })
        .backgroundColor(ThemeColors.floatBarBackground(this.oledBlack, this.isDark))
        .backgroundBlurStyle(BlurStyle.Thin)
        .border({
          width: 1,
          color: this.isDark ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.06)',
          radius: this.buttonRadius * 2
        })
        .shadow(this.isDark
          ? { radius: 10, color: 'rgba(0,0,0,0.45)', offsetX: 0, offsetY: -2 }
          : { radius: 8, color: 'rgba(0,0,0,0.08)', offsetX: 0, offsetY: -1 })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 8, bottom: 8 + this.bottomSafeAreaVp })
      .backgroundColor(Color.Transparent)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.topBarHeight })

      // 表情面板已封禁（私信无法渲染 [token]，不再渲染）
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
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
          .fontSize(this.fontCaption)
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
    .fontSize(this.fontBody)
    .fontColor(incoming ? $r('app.color.text_primary') : '#FFFFFF')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(incoming
      ? $r('app.color.card_background')
      : $r('app.color.action_background'))
    .borderRadius(this.cardRadius)
    .constraintSize({ maxWidth: '78%' })
  }
}
