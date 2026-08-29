export interface ZhihuNotification {
  readonly id: string;
  readonly isRead: boolean;
  readonly createdTime: number;
  readonly avatarUrl: string;
  readonly title: string;
  readonly subtitle: string;
  readonly body: string;
  readonly sourceText: string;
  readonly sourceLink: string;
  readonly targetLink: string;
  // 对齐安卓 navDestination() 的候选链接链：content / content.sub / target_source / head
  readonly contentTargetLink: string;
  readonly subTargetLink: string;
  readonly targetSourceTargetLink: string;
  readonly headTargetLink: string;
  // 由 extra_action.data 合成的通知锚点深链：zhihu://comment/list/{type}/{id}?anchor_comment_id=C
  // （目标评论 C 的真实 id 来自 extra_action.data.id，对第三方客户端 target_link 只会降级成 www timeline，故不从链接取）
  readonly anchorTargetLink: string;
  readonly targetType: string;
  readonly targetId: string;
  // 来源级未读数（安卓 MobileNotificationTimelineItem.unreadCount），用于来源会话角标
  readonly unreadCount: number;
}

// 邀请回答入口（安卓 MobileNotificationColumnHead，来自 message 概览接口 column_head 第一项）
export interface ZhihuNotificationInvitation {
  readonly id: string;
  readonly title: string;
  readonly text: string;
  readonly targetLink: string;
  readonly avatarUrl: string;
  readonly unreadCount: number;
}

export interface ZhihuNotificationPage {
  readonly items: ZhihuNotification[];
  readonly nextUrl: string;
  readonly isEnd: boolean;
  // 邀请回答入口（column_head 首项），无则 undefined
  readonly invitation?: ZhihuNotificationInvitation;
}

// 通知主页概览（安卓 MobileNotificationMessageOverview，来自 /notifications/v3/message/v3）
// 含分类未读数、邀请回答入口、来源会话列表
export interface ZhihuNotificationOverview {
  readonly items: ZhihuNotification[];
  readonly nextUrl: string;
  readonly isEnd: boolean;
  readonly invitation?: ZhihuNotificationInvitation;
  // 分类未读数（安卓 head 数组 map）
  readonly unreadCounts: Record<string, number>;
}

export interface ZhihuNotificationCategory {
  readonly key: string;
  readonly title: string;
  readonly icon: Resource;
}
