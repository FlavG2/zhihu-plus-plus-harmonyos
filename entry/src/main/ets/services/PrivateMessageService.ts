import common from '@ohos.app.ability.common';
import { ZhihuApi } from './ZhihuApi';

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
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

/** 把私信 content/plugin.excerpt 里的 <a href="...">text</a> 解析为可点击段落 */
export function parseMessageContent(content: string): RichTextSegment[] {
  const segments: RichTextSegment[] = [];
  const pattern = /<a\s+[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi;
  let lastIndex = 0;
  let match: RegExpExecArray | null = pattern.exec(content);
  while (match !== null) {
    const before = content.slice(lastIndex, match.index);
    if (before.length > 0) {
      segments.push({ type: 'text', text: decodeHtmlEntities(before) });
    }
    const url = decodeHtmlEntities(match[1]);
    const text = decodeHtmlEntities(match[2]);
    segments.push({ type: 'link', text, url });
    lastIndex = pattern.lastIndex;
    match = pattern.exec(content);
  }
  const trailing = content.slice(lastIndex);
  if (trailing.length > 0) {
    segments.push({ type: 'text', text: decodeHtmlEntities(trailing) });
  }
  return segments;
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
}
