import common from '@ohos.app.ability.common';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ZhihuApi } from './ZhihuApi';
import { encryptMessageBody } from './ZhihuMessageBodyEncryptor';

type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];
interface JsonObject {
  [key: string]: JsonValue;
}

function asObj(value: JsonValue | undefined): JsonObject | undefined {
  if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
    return value as JsonObject;
  }
  return undefined;
}

function asArr(value: JsonValue | undefined): JsonValue[] {
  return Array.isArray(value) ? value : [];
}

function str(value: JsonValue | undefined): string {
  if (typeof value === 'string') return value;
  if (typeof value === 'number') return `${value}`;
  if (typeof value === 'boolean') return `${value}`;
  return '';
}

function num(value: JsonValue | undefined): number {
  if (typeof value === 'number') return value;
  if (typeof value === 'string' && value.length > 0) {
    const n = Number(value);
    return Number.isNaN(n) ? 0 : n;
  }
  return 0;
}

// 富文本段落：私信 content 常带 HTML <a> 链接，需解析为原生 Span
export interface RichTextSegment {
  readonly type: 'text' | 'link';
  readonly text: string;
  readonly url?: string;
}

function decodeHtmlEntities(input: string): string {
  return input
    .replace(/&nbsp;/gi, ' ')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&amp;/gi, '&');
}

// 把含有限 HTML 标签的私信片段转为带换行的纯文本：剥标签、<br>/块级闭合换换行、解实体。
// 对齐安卓 Ksoup.parseBodyFragment().text() 的效果（知乎私信接口返回的是 HTML 片段）。
function htmlToPlainText(html: string): string {
  return decodeHtmlEntities(
    html
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/(p|div|li|h1|h2|h3|h4|h5|h6|tr)>/gi, '\n')
      .replace(/<hr\s*\/?>/gi, '\n')
      .replace(/<[^>]+>/g, '')
  )
    .replace(/\r/g, '')
    .replace(/\n{3,}/g, '\n\n');
}

/** 把私信 content/plugin.excerpt 解析为可点击段落（对齐安卓 Ksoup：纯文本 + 蓝链） */
export function parseMessageContent(content: string): RichTextSegment[] {
  const rawSegments: RichTextSegment[] = [];
  const pattern = /<a\s+[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi;
  let lastIndex = 0;
  let match: RegExpExecArray | null = pattern.exec(content);
  while (match !== null) {
    // 链接前的文本片段：剥标签 + 换行 + 解实体（保留 <br> 转成的换行）
    const before = htmlToPlainText(content.slice(lastIndex, match.index));
    if (before.length > 0) {
      rawSegments.push({ type: 'text', text: before });
    }
    const url = decodeHtmlEntities(match[1]);
    // 链接文字内部可能含 <br>/<strong> 等，同样走纯文本处理
    const linkText = htmlToPlainText(match[2]);
    if (linkText.length > 0) {
      rawSegments.push({ type: 'link', text: linkText, url });
    }
    lastIndex = pattern.lastIndex;
    match = pattern.exec(content);
  }
  const trailing = htmlToPlainText(content.slice(lastIndex));
  if (trailing.length > 0) {
    rawSegments.push({ type: 'text', text: trailing });
  }

  // 合并相邻纯文本段落，并裁掉首尾多余换行，避免气泡内出现空行
  const merged: RichTextSegment[] = [];
  for (const seg of rawSegments) {
    if (seg.type === 'text') {
      const text = seg.text.replace(/\n{3,}/g, '\n\n');
      if (text.length === 0) {
        continue;
      }
      const last = merged[merged.length - 1];
      if (last !== undefined && last.type === 'text') {
        merged[merged.length - 1] = { type: 'text', text: last.text + text };
      } else {
        merged.push({ type: 'text', text });
      }
    } else {
      merged.push(seg);
    }
  }
  if (merged.length > 0 && merged[0].type === 'text') {
    merged[0] = { type: 'text', text: merged[0].text.replace(/^\n+/, '') };
  }
  if (merged.length > 0) {
    const last = merged[merged.length - 1];
    if (last.type === 'text') {
      merged[merged.length - 1] = { type: 'text', text: last.text.replace(/\n+$/, '') };
    }
  }
  return merged.filter((s) => s.text.length > 0);
}

// 对齐安卓 ZhihuPrivateMessagePlugin
export interface ZhihuPrivateMessagePlugin {
  readonly pluginType: string;
  readonly pluginContent: string;
  readonly excerpt: string;
}

// 对齐安卓 MobileNotificationAuthor（消息发送/接收方）
export interface ZhihuMessageAuthor {
  readonly id: string;
  readonly name: string;
  readonly avatarUrl: string;
  readonly urlToken: string;
}

// 对齐安卓 ZhihuPrivateMessage
export interface ZhihuPrivateMessage {
  readonly id: string;
  readonly type: string;
  readonly contentType: number;
  readonly content: string;
  readonly createdTime: number;
  readonly sender: ZhihuMessageAuthor | undefined;
  readonly receiver: ZhihuMessageAuthor | undefined;
  readonly plugin: ZhihuPrivateMessagePlugin | undefined;
  readonly stableId: string;
}

export interface ZhihuPrivateMessagePage {
  readonly data: ZhihuPrivateMessage[];
  readonly paging: { isEnd: boolean; next: string };
}

const MOBILE_PRIVATE_MESSAGE_URL = 'https://api.zhihu.com/messages';
const MOBILE_PRIVATE_MESSAGE_USER_URL = 'https://api.zhihu.com/messages/user';

export class PrivateMessageService {
  // 拉消息列表（对齐安卓 initialUrl：messages?limit=20&sender_id={peerId}）
  static async loadMessages(
    context: common.Context,
    peerId: string,
    nextUrl?: string
  ): Promise<ZhihuPrivateMessagePage> {
    const url = nextUrl && nextUrl.length > 0
      ? nextUrl.replace('http://', 'https://')
      : `${MOBILE_PRIVATE_MESSAGE_URL}?limit=20&sender_id=${peerId}`;
    const payload = (await ZhihuApi.getJson(context, url, { signed: false })) as JsonObject | null;
    if (payload === null) {
      return { data: [], paging: { isEnd: true, next: '' } };
    }
    const rawData = asArr(payload.data);
    const data: ZhihuPrivateMessage[] = rawData
      .map((it) => PrivateMessageService.mapMessage(asObj(it)))
      .filter((m): m is ZhihuPrivateMessage => m !== undefined);
    const paging = asObj(payload.paging);
    const next = str(paging?.next);
    const isEnd = paging !== undefined ? (paging.is_end === true || paging.isEnd === true || next.length === 0) : true;
    return { data, paging: { isEnd, next } };
  }

  // 拉对方资料（对齐安卓 MOBILE_PRIVATE_MESSAGE_USER_URL/{peerId}）
  static async loadPeer(context: common.Context, peerId: string): Promise<ZhihuMessageAuthor | undefined> {
    const url = `${MOBILE_PRIVATE_MESSAGE_USER_URL}/${peerId}`;
    const payload = (await ZhihuApi.getJson(context, url, { signed: false })) as JsonObject | null;
    if (payload === null) {
      return undefined;
    }
    return PrivateMessageService.mapAuthor(payload);
  }

  private static mapAuthor(o: JsonObject | undefined): ZhihuMessageAuthor | undefined {
    if (o === undefined) {
      return undefined;
    }
    return {
      id: str(o.id),
      name: str(o.name),
      avatarUrl: str(o.avatar_url),
      urlToken: str(o.url_token)
    };
  }

  private static mapMessage(o: JsonObject | undefined): ZhihuPrivateMessage | undefined {
    if (o === undefined) {
      return undefined;
    }
    const sender = PrivateMessageService.mapAuthor(asObj(o.sender));
    const receiver = PrivateMessageService.mapAuthor(asObj(o.receiver));
    const pluginRaw = asObj(o.plugin);
    const plugin: ZhihuPrivateMessagePlugin | undefined = pluginRaw !== undefined ? {
      pluginType: str(pluginRaw.plugin_type),
      pluginContent: str(pluginRaw.plugin_content),
      excerpt: str(pluginRaw.excerpt)
    } : undefined;
    const id = str(o.id);
    const createdTime = num(o.created_time);
    const stableId = id.length > 0
      ? id
      : `${createdTime}-${sender?.id ?? ''}-${receiver?.id ?? ''}`;
    return {
      id,
      type: str(o.type),
      contentType: num(o.content_type),
      content: str(o.content),
      createdTime,
      sender,
      receiver,
      plugin,
      stableId
    };
  }

  // 发送私信（对齐安卓 NotificationViewModel.sendMessage）
  static async sendMessage(
    context: common.Context,
    peerId: string,
    content: string
  ): Promise<ZhihuPrivateMessage> {
    if (content.trim().length === 0) {
      throw new Error('消息内容不能为空');
    }
    // 表单字段与安卓 Parameters.formUrlEncode 保持一致，content 需 URL 编码
    const form =
      `receiver_id=${peerId}` +
      `&content=${encodeURIComponent(content)}` +
      `&content_type=0` +
      `&source_type=message_list`;
    const body = encryptMessageBody(form);
    hilog.info(0x0001, 'ZhihuPM', 'sendMessage form=%{public}s', form);
    hilog.info(0x0001, 'ZhihuPM', 'sendMessage body len=%{public}d body=%{public}s', body.length, body);
    // 私信发送走安卓 mobileHomeFeedHttpClient 同款标识，否则会被 openresty WAF 403。
    // 不需要 URL 签名（signed:false），仅带 body 加密头 x-zse-93:101_1_1.0。
    const payload = (await ZhihuApi.postJson(context, MOBILE_PRIVATE_MESSAGE_URL, {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'x-zse-93': '101_1_1.0',
        'User-Agent': 'com.zhihu.android/Futureve/10.61.0 Mozilla/5.0 (Linux; Android 12; sdk_gphone64_arm64 Build/SE1A.220630.001.A1; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/57.0.1000.10 Mobile Safari/537.36',
        'x-api-version': '3.1.8',
        'x-app-version': '10.61.0',
        'x-app-za': 'OS=Android&Release=12&Model=sdk_gphone64_arm64&VersionName=10.61.0&VersionCode=26107&Product=com.zhihu.android&Width=1440&Height=2952&Installer=%E7%81%B0%E5%BA%A6&DeviceType=AndroidPhone&Brand=google'
      },
      body,
      signed: false
    })) as JsonObject | null;
    const msg = PrivateMessageService.mapMessage(payload ?? undefined);
    if (msg === undefined) {
      throw new Error('发送失败：响应解析为空');
    }
    return msg;
  }
}
