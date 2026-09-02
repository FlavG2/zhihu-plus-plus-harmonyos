import { ZhihuCommentableTarget } from './ZhihuContentModels';

export interface ZhihuAccountProfile {
  readonly id: string;
  readonly name: string;
  readonly headline: string;
  readonly avatarUrl: string;
  readonly urlToken: string;
  readonly userType: string;
}

export interface ZhihuSessionData {
  readonly login: boolean;
  readonly username: string;
  readonly cookies: Record<string, string>;
  readonly userAgent: string;
  readonly self?: ZhihuAccountProfile;
  // 马甲号/身份管理：移动端 API 凭证（切换/创建账号后由服务器签发，见 ZhihuIdentityClient）
  readonly mobileAccessToken?: string;
  readonly mobileRefreshToken?: string;
  readonly mobileTokenType?: string;
  readonly mobileTokenExpiresAt?: number;
}

export interface SessionSnapshot {
  readonly accountName: string;
  readonly avatarUrl: string;
  readonly loggedIn: boolean;
  readonly cookieCount: number;
  readonly hasSigningBridge: boolean;
}

export interface TextHighlightSegment {
  readonly text: string;
  readonly highlighted: boolean;
}

export interface HomeFeedTopic {
  readonly id: string;
  readonly name: string;
}

export interface HomeFeedItem {
  readonly id: string;
  readonly type: 'answer' | 'article' | 'question' | 'pin' | 'zvideo' | 'message';
  readonly title: string;
  readonly summary: string;
  readonly details: string;
  readonly authorName: string;
  readonly authorHeadline: string;
  readonly authorAvatarUrl: string;
  readonly thumbnailUrl: string;
  readonly targetUrl: string;
  readonly nativeTarget?: ZhihuCommentableTarget;
  readonly actionText: string;
  // 活动动词（如 VOTEUP/ANSWER/ARTICLE/CREATE_PIN），用于「赞同了 XX / 想法 / 文章 / 回答」筛选
  readonly verb?: string;
  // 发布时间（epoch 秒，来自 rawFeed.created_time 或 target.created_time），用于卡片「X 前」相对时间
  readonly createdTime?: number;
  readonly voteCount: number;
  readonly commentCount: number;
  readonly titleHighlightSegments?: TextHighlightSegment[];
  readonly summaryHighlightSegments?: TextHighlightSegment[];
  // 视频帖（zvideo）专用字段
  readonly videoId?: string;
  readonly contentId?: string;
  readonly contentType?: string;
  readonly durationText?: string;
  readonly playCountText?: string;
  // 屏蔽功能所需字段（对齐安卓 FilterableContent，用于精确过滤）
  readonly authorId?: string;
  readonly authorUrlToken?: string;
  readonly questionAuthorId?: string;
  readonly questionAuthorName?: string;
  topics?: Array<HomeFeedTopic>;
  // 盐选付费标记（对齐安卓 raw.paidInfo，非空表示盐选会员付费内容）
  readonly paidInfo?: object;
  // 作者是否已关注（对齐安卓 target.author.is_following，用于质量过滤「已关注作者豁免」/「过滤已关注用户内容」）
  readonly authorFollowing?: boolean;
  // 作者粉丝数（对齐安卓 author.follower_count，用于视频/文章质量过滤的粉丝阈值）
  readonly authorFollowerCount?: number;
  // 问题自身关注数（对齐安卓 question.follower_count，仅 question 类型；用于问题质量过滤的关注阈值）
  readonly questionFollowerCount?: number;
  // 推荐次数（客户端本地统计：同一内容被推荐出现的次数，用于卡片「第 N 次推荐」标记；运行时由计数层赋值，故非 readonly）
  recommendCount?: number;
  // 质量过滤「屏蔽规则」模式下被打标的原因文案（如「规则：回答；赞数 < 10，未关注作者」）；存在时渲染「已屏蔽」占位卡
  blockReason?: string;
}

export interface HomeFeedPaging {
  readonly isEnd: boolean;
  readonly nextUrl: string;
}

export interface HomeFeedPage {
  readonly items: HomeFeedItem[];
  readonly paging: HomeFeedPaging;
}

// 收藏夹（对齐安卓 Collection 数据类）：列表/收藏夹内容/内容收藏状态共用
export interface ZhihuCollection {
  readonly id: string;
  readonly title: string;
  readonly description: string;
  readonly isFavorited: boolean;
  readonly isPublic: boolean;
  readonly itemCount: number;
  readonly likeCount: number;
  readonly commentCount: number;
  readonly viewCount: number;
  readonly updatedTime: number;
  readonly isDefault: boolean;
}

// 收藏夹列表/内容分页结果
export interface CollectionPage {
  readonly items: ZhihuCollection[];
  readonly nextUrl: string;
  readonly isEnd: boolean;
}

export const DEFAULT_USER_AGENT: string =
  'Mozilla/5.0 (X11; U; Linux x86_64; en-US) AppleWebKit/540.0 (KHTML, like Gecko) Ubuntu/10.10 Chrome/9.1.0.0 Safari/540.0';

export const DEFAULT_SESSION_SNAPSHOT: SessionSnapshot = {
  accountName: '未登录',
  avatarUrl: '',
  loggedIn: false,
  cookieCount: 0,
  hasSigningBridge: true
};

export function createDefaultSessionData(): ZhihuSessionData {
  return {
    login: false,
    username: '',
    cookies: {},
    userAgent: DEFAULT_USER_AGENT
  };
}

// 话题详情（对齐安卓 TopicScreen.TopicDetail：api/v5.1/topics/{id} 返回值）
export interface TopicDetail {
  readonly id: string;
  readonly name: string;
  readonly excerpt: string;
  readonly avatarUrl: string;
  readonly followersCount: number;
  readonly questionsCount: number;
  readonly isFollowing: boolean;
  readonly topicId: string;
  readonly totalPv: number;
  readonly discussCount: number;
}

// 搜索「话题」分类结果（对齐安卓 SearchEntity.Topic / TopicSearchObject）
export interface SearchTopicResult {
  readonly id: string;
  readonly name: string;
  readonly avatarUrl: string;
  readonly excerpt: string;
  readonly visitCount: number;
  readonly discussCount: number;
  readonly isFollowing: boolean;
}

// 搜索「用户」分类结果（对齐安卓 SearchEntity.Person / DataHolder.People）
export interface SearchPeopleResult {
  readonly id: string;
  readonly name: string;
  readonly avatarUrl: string;
  readonly headline: string;
  readonly followerCount: number;
  readonly urlToken: string;
}
