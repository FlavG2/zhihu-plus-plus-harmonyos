/**
 * 总结本文（SSE 流式），对齐安卓 ZhidaSummary.kt + ArticleViewModel.requestAiSummary。
 *
 * 走 https://www.zhihu.com/ai_ingress/stream/completion，签名 + x-xsrftoken，Accept: text/event-stream。
 * 由于 ZhihuApi 的 requestJson 是非流式（expectDataType: STRING、一次性返回），这里直接用 http.createHttp()
 * 挂 dataReceive 按行解析 SSE 帧：event: answer（delta=true 增量 merge）/ error / end，跳过 [DONE]。
 * 返回取消函数，调用即中断流。
 */
import common from '@ohos.app.ability.common';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { ZhihuSessionRepository } from './ZhihuSessionRepository';
import { ZhihuSignerBridge } from './ZhihuSignerBridge';
import { DEFAULT_USER_AGENT } from '../models/ZhihuModels';

export interface SummaryOptions {
  readonly contentId: string;
  readonly contentType: 'answer' | 'article';
  readonly title: string;
}

export interface SummaryCallbacks {
  onStart?: () => void;
  onDelta?: (fullText: string) => void;
  onError?: (message: string) => void;
  onDone?: () => void;
}

const SUMMARY_URL = 'https://www.zhihu.com/ai_ingress/stream/completion';

function encodeAttachmentValue(contentId: string, contentType: string): string {
  const type = contentType.toLowerCase() === 'article' ? 'ARTICLE' : 'ANSWER';
  const source = `${contentId}|::|${type}`;
  const bytes = new util.TextEncoder().encode(source);
  return new util.Base64Helper().encodeToStringSync(bytes);
}

function mergeChunk(current: string, chunk: string): string {
  if (!chunk.trim()) {
    return current;
  }
  if (!current.trim()) {
    return chunk;
  }
  if (chunk.startsWith(current)) {
    return chunk;
  }
  if (current.endsWith(chunk)) {
    return current;
  }
  return current + chunk;
}

function normalizePayload(
  event: string | null,
  joined: string
): { event: string; data: Object } | null {
  const trimmed = joined.trim();
  if (trimmed.length === 0 || trimmed === '[DONE]' || trimmed === 'DONE') {
    return null;
  }
  let element: Object | null = null;
  try {
    element = JSON.parse(trimmed) as Object;
  } catch (_e) {
    if (event !== null && event !== undefined) {
      return { event, data: { raw: trimmed } };
    }
    return null;
  }
  if (element !== null && typeof element === 'object' && !Array.isArray(element)) {
    const obj = element as Record<string, Object>;
    if ('event' in obj || 'data' in obj) {
      const ev = typeof obj['event'] === 'string' ? (obj['event'] as string) : event;
      let inner: Object = obj['data'] ?? {};
      if (typeof inner === 'string') {
        try {
          inner = JSON.parse(inner as string);
        } catch (_e) {
          // 保留原始字符串
        }
      }
      if (ev !== null && ev !== undefined) {
        return { event: ev, data: inner };
      }
      return null;
    }
    if (event !== null && event !== undefined) {
      return { event, data: obj };
    }
  } else if (event !== null && event !== undefined) {
    return { event, data: element ?? {} };
  }
  return null;
}

function parseSummaryError(text: string): string | null {
  const trimmed = (text ?? '').trim();
  if (!trimmed) {
    return null;
  }
  try {
    const obj = JSON.parse(trimmed) as Record<string, Object>;
    const errObj = obj['error'] as Record<string, Object> | undefined;
    const msg =
      (typeof obj['message'] === 'string' ? (obj['message'] as string) : '') ||
      (errObj !== undefined && typeof errObj['message'] === 'string' ? (errObj['message'] as string) : '') ||
      (typeof obj['error'] === 'string' ? (obj['error'] as string) : '');
    return msg || null;
  } catch (_e) {
    return null;
  }
}

export function startSummary(
  context: common.Context,
  options: SummaryOptions,
  callbacks: SummaryCallbacks
): () => void {
  const request = http.createHttp();
  let currentEvent: string | null = null;
  let dataLines: string[] = [];
  let fullText = '';
  let finished = false;
  let seenAnswer = false;
  const decoder = new util.TextDecoder('utf-8');
  let accBytes = new Uint8Array(0);
  let decodedLen = 0;
  let lineTail = '';

  const flushFrame = (): void => {
    if (dataLines.length === 0) {
      return;
    }
    const joined = dataLines.join('\n');
    const payload = normalizePayload(currentEvent, joined);
    dataLines = [];
    if (payload === null) {
      return;
    }
    const ev = String(payload.event).toLowerCase();
    const data = payload.data as Record<string, Object>;
    if (ev === 'answer') {
      const summary = typeof data['summary'] === 'string' ? (data['summary'] as string) : '';
      const delta = data['delta'] === true;
      if (!summary) {
        return;
      }
      seenAnswer = true;
      fullText = delta ? mergeChunk(fullText, summary) : summary;
      console.info(`[Summary] answer帧: delta=${delta}, summary前80="${summary.slice(0, 80)}", 累计长度=${fullText.length}`);
      callbacks.onDelta?.(fullText);
    } else if (ev === 'error') {
      const errorObj = (data['error'] as Record<string, Object> | undefined) ?? undefined;
      const message =
        (typeof data['message'] === 'string' ? (data['message'] as string) : '') ||
        (errorObj !== undefined && typeof errorObj['message'] === 'string'
          ? (errorObj['message'] as string)
          : '') ||
        '总结失败';
      finished = true;
      callbacks.onError?.(message);
    } else if (ev === 'end') {
      finished = true;
    }
  };

  const processLine = (line: string): void => {
    const l = line.replace(/\r$/, '');
    console.info(`[Summary] 行解析: ${l.slice(0, 240)}`);
    if (l.startsWith('event:')) {
      currentEvent = l.slice(l.indexOf(':') + 1).trim();
    } else if (l.startsWith('data:')) {
      dataLines.push(l.slice(l.indexOf(':') + 1).trim());
    } else if (l.trim().length === 0) {
      flushFrame();
      currentEvent = null;
    }
    // 以 ':' 开头的 SSE 注释行忽略
  };

  // 兜底：当流式 dataReceive 未触发、整包内容落在 response.result 时，直接按 SSE 文本解析
  const parseFullSse = (text: string): void => {
    const parts = text.split('\n');
    for (const p of parts) {
      processLine(p);
    }
    if (dataLines.length > 0) {
      flushFrame();
      currentEvent = null;
    }
  };

  request.on('dataReceive', (data: ArrayBuffer) => {
    try {
      const incoming = new Uint8Array(data);
      console.info(`[Summary] dataReceive 收到字节=${data.byteLength}`);
      const merged = new Uint8Array(accBytes.length + incoming.length);
      merged.set(accBytes, 0);
      merged.set(incoming, accBytes.length);
      accBytes = merged;
      // 始终解码完整累计字节，避免多字节字符被分片导致乱码
      const full = decoder.decodeToString(accBytes);
      const fresh = full.slice(decodedLen);
      decodedLen = full.length;
      lineTail += fresh;
      let idx: number;
      while ((idx = lineTail.indexOf('\n')) >= 0) {
        const line = lineTail.slice(0, idx);
        lineTail = lineTail.slice(idx + 1);
        processLine(line);
      }
    } catch (_e) {
      // 单包解码失败忽略，等待后续数据
    }
  });

  const cookies = ZhihuSessionRepository.load(context).cookies;
  const cookieHeader = Object.entries(cookies)
    .map(([k, v]: [string, string]) => `${k}=${v}`)
    .join('; ');
  const body = JSON.stringify({
    quiz_type: 'QT_CHAT',
    attachments: [
      {
        type: 'DOC',
        value: encodeAttachmentValue(options.contentId, options.contentType),
        title: options.title
      }
    ],
    message_source_type: 'text',
    session_id: '',
    zhida_source: 'one_tap_summary',
    content_id: options.contentId,
    content_type: options.contentType,
    message_content: '这篇内容讲了什么'
  });
  const signed = ZhihuSignerBridge.buildSignedHeaders(context, SUMMARY_URL, body);
  const headers: Record<string, string> = {
    Accept: 'text/event-stream',
    'Content-Type': 'application/json',
    Referer: 'https://www.zhihu.com/',
    'User-Agent': DEFAULT_USER_AGENT,
    ...signed
  };
  if (cookieHeader.length > 0) {
    headers['Cookie'] = cookieHeader;
  }

  callbacks.onStart?.();

  console.info(`[Summary] 发起请求 url=${SUMMARY_URL}`);
  console.info(`[Summary] body长度=${body.length}, 含Cookie=${cookieHeader.length > 0}, 含x-zse-93=${!!headers['x-zse-93']}, 含x-xsrftoken=${!!headers['x-xsrftoken']}, 含Referer=${!!headers['Referer']}`);
  console.info(`[Summary] header键集合=${JSON.stringify(Object.keys(headers))}`);

  request
    .request(SUMMARY_URL, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: body,
      usingCache: false,
      connectTimeout: 10000,
      readTimeout: 60000
    })
    .then((response) => {
      const code: number = (response as { responseCode?: number }).responseCode ?? 0;
      const resultStr: string = typeof (response as { result?: Object }).result === 'string'
        ? ((response as { result?: Object }).result as string)
        : '';
      console.info(`[Summary] 响应码=${code}, result前500="${resultStr.slice(0, 500)}"`);
      if (code >= 400) {
        finished = true;
        const msg = parseSummaryError(resultStr) ?? `总结请求失败（HTTP ${code}）`;
        console.error(`[Summary] 失败: HTTP ${code}`);
        callbacks.onError?.(msg);
        return;
      }
      // 兜底：dataReceive 未触发但 result 有内容时，按 SSE 文本解析（鸿蒙 http 有时会缓冲整包）
      if (accBytes.length === 0 && fullText.length === 0 && lineTail.length === 0 && resultStr.length > 0) {
        console.info(`[Summary] 兜底解析 response.result（dataReceive 未触发），长度=${resultStr.length}`);
        parseFullSse(resultStr);
      } else if (lineTail.length > 0) {
        processLine(lineTail);
        lineTail = '';
        flushFrame();
      }
      if (!finished) {
        finished = true;
        if (!seenAnswer || fullText.trim().length === 0) {
          console.error(`[Summary] 失败: seenAnswer=${seenAnswer}, fullText长度=${fullText.length}`);
          callbacks.onError?.('未返回可显示的总结内容');
        } else {
          callbacks.onDone?.();
        }
      } else {
        callbacks.onDone?.();
      }
    })
    .catch((err: Error) => {
      if (finished) {
        return;
      }
      finished = true;
      console.error(`[Summary] 请求异常: ${err?.message ?? String(err)}`);
      callbacks.onError?.(err?.message ?? '总结请求失败');
    });

  return () => {
    finished = true;
    try {
      request.destroy();
    } catch (_e) {
      // 忽略
    }
  };
}
