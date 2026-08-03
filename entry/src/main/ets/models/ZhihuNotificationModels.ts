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
}

export interface ZhihuNotificationPage {
  readonly items: ZhihuNotification[];
  readonly nextUrl: string;
  readonly isEnd: boolean;
}

export interface ZhihuNotificationCategory {
  readonly key: string;
  readonly title: string;
  readonly icon: Resource;
}
