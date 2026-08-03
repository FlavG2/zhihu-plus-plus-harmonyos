import common from '@ohos.app.ability.common';
import { ZhihuApi } from './ZhihuApi';
import { ZhihuNotification, ZhihuNotificationPage, ZhihuNotificationCategory } from '../models/ZhihuNotificationModels';
import { stripHtmlToText } from '../utils/ZhihuHtml';

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

const MOBILE_NOTIFICATION_ENTRY_BASE_URL = 'https://api.zhihu.com/notifications/v3/timeline/entry';
const MOBILE_NOTIFICATION_MESSAGE_URL = 'https://api.zhihu.com/notifications/v3/message/v3?limit=20';

// 对齐安卓 MobileNotificationCategory：评论转发@ / 赞同喜欢 / 收藏了我 / 关注订阅
export const NOTIFICATION_CATEGORIES: ZhihuNotificationCategory[] = [
  { key: 'comment', title: '评论转发@', icon: $r('app.media.ic_comment') },
  { key: 'like', title: '赞同喜欢', icon: $r('app.media.ic_agree') },
  { key: 'favlist_me', title: '收藏了我', icon: $r('app.media.ic_bookmark') },
  { key: 'follow', title: '关注订阅', icon: $r('app.media.nav_follow') }
];

// 安卓 detailTitle -> category key 映射，用于未读数概览
const DETAIL_TITLE_TO_KEY: Record<string, string> = {
  '评论转发@': 'comment',
  '赞同喜欢': 'like',
  '收藏了我': 'favlist_me',
  '关注订阅': 'follow'
};

export class NotificationService {
  static async loadNotifications(context: common.Context, categoryKey: string, nextUrl?: string): Promise<ZhihuNotificationPage> {
    const url = nextUrl !== undefined && nextUrl.length > 0
      ? nextUrl
      : `${MOBILE_NOTIFICATION_ENTRY_BASE_URL}/${categoryKey}?limit=20`;
    const payload = (await ZhihuApi.getJson(context, url, { signed: true })) as JsonObject | null;
    if (payload === null) {
      return { items: [], nextUrl: '', isEnd: true };
    }
    const data = Array.isArray(payload.data) ? (payload.data as JsonValue[]) : [];
    const items: ZhihuNotification[] = data
      .filter((d): d is JsonObject => d !== null && typeof d === 'object' && !Array.isArray(d))
      .map((raw) => NotificationService.mapNotification(raw));
    const paging = asObj(payload.paging as JsonValue);
    let nextUrlResult = '';
    let isEnd = true;
    if (paging !== undefined) {
      nextUrlResult = str(paging.next);
      isEnd = typeof paging.is_end === 'boolean' ? paging.is_end : nextUrlResult.length === 0;
    }
    return { items, nextUrl: nextUrlResult, isEnd };
  }

  // 未读消息概览（安卓 updateUnreadCounts）
  static async loadUnreadCounts(context: common.Context): Promise<Record<string, number>> {
    const result: Record<string, number> = {};
    try {
      const payload = (await ZhihuApi.getJson(context, MOBILE_NOTIFICATION_MESSAGE_URL, { signed: true })) as JsonObject | null;
      const head = payload !== null ? (Array.isArray(payload.head) ? (payload.head as JsonValue[]) : []) : [];
      for (const entry of head) {
        const e = asObj(entry);
        if (e === undefined) {
          continue;
        }
        const title = str(e.detail_title);
        const key = DETAIL_TITLE_TO_KEY[title];
        if (key !== undefined) {
          result[key] = num(e.unread_count);
        }
      }
    } catch (e) {
      // 忽略，保持 UI 稳定
    }
    return result;
  }

  private static mapNotification(raw: JsonObject): ZhihuNotification {
    const content = asObj(raw.content as JsonValue);
    const head = asObj(raw.head as JsonValue);
    const author = head !== undefined ? asObj(head.author as JsonValue) : undefined;
    const target = asObj(raw.target as JsonValue);
    const targetSource = asObj(raw.target_source as JsonValue);

    // 头像回退链：head.avatar_url -> author.avatar_url -> target.avatar_url -> content.sub_icon
    const avatarUrl: string =
      (head !== undefined ? str(head.avatar_url) : '') ||
      (author !== undefined ? str(author.avatar_url) : '') ||
      (target !== undefined ? str(target.avatar_url) : '') ||
      (content !== undefined ? str(content.sub_icon) : '') ||
      '';

    // 标题：content.title -> detail_title -> target.name -> "通知"
    const title = content !== undefined ? str(content.title) : '';
    const detailTitle = str(raw.detail_title);
    const targetName = target !== undefined ? str(target.name) : '';
    const displayTitle = title.length > 0 ? title : (detailTitle.length > 0 ? detailTitle : (targetName.length > 0 ? targetName : '通知'));

    // subtitle：content.sub_title，并以"："结尾规则（评论了/赞同了/喜欢了）
    let subtitle = content !== undefined ? str(content.sub_title) : '';
    if (
      subtitle.length > 0 &&
      !subtitle.endsWith('：') &&
      (subtitle.startsWith('评论了') || subtitle.startsWith('赞同了') || subtitle.startsWith('喜欢了'))
    ) {
      subtitle = `${subtitle}：`;
    }

    // 正文：喜欢了你的评论 用 sub_text，否则用 text
    let body = '';
    if (content !== undefined) {
      const rawSubTitle = str(content.sub_title);
      const rawText = rawSubTitle === '喜欢了你的评论' ? str(content.sub_text) : str(content.text);
      body = stripHtmlToText(rawText);
    }

    // 引用卡片：target_source.text + sub_text（换行拼接）
    const sourceText = [
      targetSource !== undefined ? str(targetSource.text) : '',
      targetSource !== undefined ? str(targetSource.sub_text) : ''
    ]
      .filter((t) => t.length > 0)
      .join('\n');
    const sourceLink = targetSource !== undefined ? str(targetSource.target_link ?? targetSource.targetLink) : '';

    // 候选链接链（对齐安卓 navDestination()）：content / content.sub / target_source / head
    // 真实 API 对 target_link/targetLink 命名不确定，snake/camel 两种都读，避免取到空值
    const contentTargetLink = content !== undefined ? str(content.target_link ?? content.targetLink) : '';
    const subTargetLink = content !== undefined ? str(content.sub_target_link ?? content.subTargetLink) : '';
    const targetSourceTargetLink = targetSource !== undefined
      ? str(targetSource.target_link ?? targetSource.targetLink)
      : '';
    const headTargetLink = head !== undefined ? str(head.target_link ?? head.targetLink) : '';

    // 对齐安卓通知锚点（PR #606 回复定位）：目标评论 C 与所属内容信息藏在 extra_action 里，
    // 而非常规 target_link（后者对第三方客户端只会降级成 www timeline、仅含 reply_root_id=A）。
    // 注意层级：C 的 id / resource_type 在 extra_action.data 内；内容 id（answer 等）在 extra_action.resource_id 顶层。
    // 据此合成 zhihu://comment/list/{type}/{id}?anchor_comment_id=C，复用已有解析→消费管线：
    // consumeAnchorComment 经 loadCommentDetail(C) 取 replyRootCommentId=A，自动置顶根评论 A 并展开楼中楼、置顶 C。
    const extraAction = asObj(raw.extra_action as JsonValue);
    const extraData = extraAction !== undefined ? asObj(extraAction.data as JsonValue) : undefined;
    let anchorTargetLink = '';
    if (extraData !== undefined) {
      const cid = num(extraData.id);
      const rt = str(extraData.resource_type).toLowerCase();
      // 关键：resource_id 在 extra_action 顶层（与 data 平级），不在 extra_action.data 里
      const rid = str(extraAction.resource_id);
      if (cid > 0 && rid.length > 0 &&
          (rt === 'answer' || rt === 'article' || rt === 'question' || rt === 'pin')) {
        anchorTargetLink = `zhihu://comment/list/${rt}/${rid}?anchor_comment_id=${cid}`;
      }
    }

    // 主跳转链接：取候选链第一个非空（向后兼容）
    const targetLink: string = contentTargetLink || subTargetLink || targetSourceTargetLink || headTargetLink || '';

    return {
      id: str(raw.id),
      isRead: raw.is_read === true,
      createdTime: num(raw.created ?? raw.created_time),
      avatarUrl,
      title: displayTitle,
      subtitle,
      body,
      sourceText,
      sourceLink,
      targetLink,
      contentTargetLink,
      subTargetLink,
      targetSourceTargetLink,
      headTargetLink,
      anchorTargetLink,
      targetType: target !== undefined ? str(target.type) : '',
      targetId: target !== undefined ? str(target.id) : ''
    };
  }

  // 一键已读（安卓 readAllUrl：v3/timeline/entry/{entryName}/actions/readall）
  static async markAllRead(context: common.Context, categoryKey: string): Promise<void> {
    const url = `${MOBILE_NOTIFICATION_ENTRY_BASE_URL}/${categoryKey}/actions/readall`;
    await ZhihuApi.postJson(context, url, { signed: true });
  }
}
