import { ZhihuCommentableTarget } from '../models/ZhihuContentModels';

function trimQueryAndHash(url: string): string {
  const hashIndex = url.indexOf('#');
  const queryIndex = url.indexOf('?');
  let endIndex = url.length;
  if (hashIndex >= 0) {
    endIndex = Math.min(endIndex, hashIndex);
  }
  if (queryIndex >= 0) {
    endIndex = Math.min(endIndex, queryIndex);
  }
  return url.slice(0, endIndex);
}

function extractQueryParam(url: string, key: string): string {
  const qIndex = url.indexOf('?');
  if (qIndex < 0) {
    return '';
  }
  const query = url.slice(qIndex + 1);
  for (const p of query.split('&')) {
    const eq = p.indexOf('=');
    const k = eq >= 0 ? p.slice(0, eq) : p;
    if (k === key) {
      const raw = eq >= 0 ? p.slice(eq + 1) : '';
      try {
        return decodeURIComponent(raw);
      } catch (e) {
        return raw;
      }
    }
  }
  return '';
}

export function resolveZhihuContent(url: string): ZhihuCommentableTarget | undefined {
  const normalized = trimQueryAndHash(url.trim());
  if (normalized.length === 0) {
    return undefined;
  }

  // 通知评论/回复深链（真实 API 形态，对齐安卓 PR #606 的回复定位）：
  // https://www.zhihu.com/notifications/v3/timeline/{id}?type=comment&resource_type=answer&resource_id=...&reply_root_id=...&url=...
  // 锚点（根评论）藏在 reply_root_id；resource_type + resource_id 决定内容种类与 ID
  if (/^https?:\/\/(?:www\.)?zhihu\.com\/notifications\/v\d+\/timeline\/\d+$/i.test(normalized)) {
    const rt = extractQueryParam(url, 'resource_type').toLowerCase();
    const rid = extractQueryParam(url, 'resource_id');
    const anchor = extractQueryParam(url, 'reply_root_id') || extractQueryParam(url, 'reply_root_comment_id');
    if (rid.length > 0) {
      if (rt === 'answer') return { kind: 'answer', id: rid, anchorCommentId: anchor };
      if (rt === 'article') return { kind: 'article', id: rid, anchorCommentId: anchor };
      if (rt === 'question') return { kind: 'question', id: rid, anchorCommentId: anchor };
      if (rt === 'pin') return { kind: 'pin', id: rid, anchorCommentId: anchor };
      // resource_type 不是内容类型（如 follow）时不解析，让后续候选或 people 兜底
    }
  }

  // 通知评论定位：zhihu://comment/list/{type}/{id}?anchor_comment_id=X
  const listMatch = normalized.match(/^zhihu:\/\/comment\/list\/(answer|article|question|pin)\/(\d+)$/i);
  if (listMatch !== null) {
    const listType = listMatch[1].toLowerCase();
    const listId = listMatch[2];
    const anchorCommentId = extractQueryParam(url, 'anchor_comment_id');
    if (listType === 'answer') {
      return { kind: 'answer', id: listId, anchorCommentId };
    }
    if (listType === 'article') {
      return { kind: 'article', id: listId, anchorCommentId };
    }
    if (listType === 'question') {
      return { kind: 'question', id: listId, anchorCommentId };
    }
    return { kind: 'pin', id: listId, anchorCommentId };
  }

  // 同上，部分通知返回的是 https://www.zhihu.com/comment/list/... 形态，同样解析锚点
  const httpsListMatch = normalized.match(/^https?:\/\/(?:www\.)?zhihu\.com\/comment\/list\/(answer|article|question|pin)\/(\d+)$/i);
  if (httpsListMatch !== null) {
    const listType = httpsListMatch[1].toLowerCase();
    const listId = httpsListMatch[2];
    const anchorCommentId = extractQueryParam(url, 'anchor_comment_id');
    if (listType === 'answer') {
      return { kind: 'answer', id: listId, anchorCommentId };
    }
    if (listType === 'article') {
      return { kind: 'article', id: listId, anchorCommentId };
    }
    if (listType === 'question') {
      return { kind: 'question', id: listId, anchorCommentId };
    }
    return { kind: 'pin', id: listId, anchorCommentId };
  }

  let match = normalized.match(/^https?:\/\/(?:www\.)?zhihu\.com\/question\/(\d+)\/answer\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'answer',
      id: match[2],
      questionId: match[1]
    };
  }

  match = normalized.match(/^https?:\/\/(?:(?:www\.)?zhihu\.com\/api|api\.zhihu\.com)\/v\d+\/answers\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'answer',
      id: match[1]
    };
  }

  match = normalized.match(/^https?:\/\/api\.zhihu\.com\/answers\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'answer',
      id: match[1]
    };
  }

  match = normalized.match(/^https?:\/\/(?:www\.)?zhihu\.com\/answer\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'answer',
      id: match[1]
    };
  }

  match = normalized.match(/^https?:\/\/(?:(?:www\.)?zhihu\.com\/api|api\.zhihu\.com)\/v\d+\/articles\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'article',
      id: match[1]
    };
  }

  match = normalized.match(/^https?:\/\/api\.zhihu\.com\/articles\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'article',
      id: match[1]
    };
  }

  match = normalized.match(/^https?:\/\/zhuanlan\.zhihu\.com\/p\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'article',
      id: match[1]
    };
  }

  match = normalized.match(/^https?:\/\/(?:(?:www\.)?zhihu\.com\/api|api\.zhihu\.com)\/v\d+\/questions\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'question',
      id: match[1]
    };
  }

  match = normalized.match(/^https?:\/\/api\.zhihu\.com\/questions\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'question',
      id: match[1]
    };
  }

  match = normalized.match(/^https?:\/\/(?:www\.)?zhihu\.com\/question\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'question',
      id: match[1]
    };
  }

  match = normalized.match(/^https?:\/\/(?:(?:www\.)?zhihu\.com\/api|api\.zhihu\.com)\/v\d+\/pins\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'pin',
      id: match[1]
    };
  }

  match = normalized.match(/^https?:\/\/api\.zhihu\.com\/pins\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'pin',
      id: match[1]
    };
  }

  match = normalized.match(/^https?:\/\/(?:www\.)?zhihu\.com\/pin\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'pin',
      id: match[1]
    };
  }

  match = normalized.match(/^zhihu:\/\/answers\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'answer',
      id: match[1]
    };
  }

  match = normalized.match(/^zhihu:\/\/articles\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'article',
      id: match[1]
    };
  }

  match = normalized.match(/^zhihu:\/\/questions\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'question',
      id: match[1]
    };
  }

  match = normalized.match(/^zhihu:\/\/pin\/(\d+)$/i);
  if (match !== null) {
    return {
      kind: 'pin',
      id: match[1]
    };
  }

  // 私信会话（对齐安卓 NavDestination：https://www.zhihu.com/inbox/{peerId}?title=）
  // 安卓通知主页 data 项里私信会话的 targetLink 即此形态，解析后跳原生 PrivateMessage 页
  match = normalized.match(/^https?:\/\/(?:www\.)?zhihu\.com\/inbox\/([^/?#]+)/i);
  if (match !== null) {
    const name = extractQueryParam(normalized, 'title');
    return {
      kind: 'message',
      peerId: match[1],
      name: name,
      id: match[1],
      title: name
    };
  }

  return undefined;
}

// 通知时间线入口（对齐安卓 Notification.Entry）：
// https://www.zhihu.com/notifications/v3/timeline/entry/{entryName}?title=...
// 安卓将此映射为原生通知时间线页（而非 WebView）。官方账号消息 / 系统消息等走此形态。
export function resolveNotificationEntryUrl(url: string): { entryName: string; title: string } | undefined {
  const normalized = trimQueryAndHash(url.trim());
  const match = normalized.match(/^https?:\/\/(?:www\.)?zhihu\.com\/notifications\/v\d+\/timeline\/entry\/([^/?#]+)$/i);
  if (match === null) {
    return undefined;
  }
  const entryName = match[1];
  if (entryName.length === 0) {
    return undefined;
  }
  const title = extractQueryParam(url, 'title');
  return { entryName, title: title.length > 0 ? title : entryName };
}

// 话题深链：zhihu://topic/{id} 与 https://www.zhihu.com/topic/{id}
// 返回话题 id；由调用方路由到原生 Topic 页面（ZhihuCommentableTarget 不含 topic 类型）。
export function resolveZhihuTopic(url: string): string | undefined {
  const normalized = trimQueryAndHash(url.trim());
  if (normalized.length === 0) {
    return undefined;
  }
  const zhihuMatch = normalized.match(/^zhihu:\/\/topic\/(\d+)$/i);
  if (zhihuMatch !== null) {
    return zhihuMatch[1];
  }
  const httpsMatch = normalized.match(/^https?:\/\/(?:www\.)?zhihu\.com\/topic\/(\d+)$/i);
  if (httpsMatch !== null) {
    return httpsMatch[1];
  }
  return undefined;
}
