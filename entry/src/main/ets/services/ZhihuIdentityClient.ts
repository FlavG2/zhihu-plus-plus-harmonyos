import common from '@ohos.app.ability.common';
import { ZhihuApi } from './ZhihuApi';
import { ZhihuSessionRepository } from './ZhihuSessionRepository';
import { ZhihuSessionData } from '../models/ZhihuModels';

// 对齐安卓 shared/account/ZhihuIdentityClient.kt
const ZHIHU_API_BASE_URL: string = 'https://api.zhihu.com';
const IDENTITY_ACCOUNT_LIST_PATH: string = '/people/account/list';
const CREATE_SUB_ACCOUNT_PATH: string = '/account/sub/register';
const SWITCH_ACCOUNT_PATH: string = '/account/switch';
const CURRENT_ACCOUNT_PATH: string = '/people/self';

// 安卓移动端身份接口专用 User-Agent（与安卓保持一致，否则接口可能拒绝）
const ZHIHU_ANDROID_IDENTITY_USER_AGENT: string =
  'com.zhihu.android/Futureve/11.2.0 Mozilla/5.0 (Linux; Android 12; sdk_gphone64_arm64 ' +
  'Build/SE1A.220630.001.A1; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 ' +
  'Chrome/57.0.1000.10 Mobile Safari/537.36';

export interface ZhihuIdentityAccount {
  readonly id: string;
  readonly urlToken: string;
  readonly name: string;
  readonly avatarUrl: string;
  readonly isActive: boolean;
  readonly canCreateSubAccount: boolean;
  readonly accountType: number;
  readonly subAccountControlStatus: number;
}

export interface ZhihuIdentityChangeResult {
  readonly account: ZhihuIdentityAccount;
  readonly session: ZhihuSessionData;
}

export class ZhihuIdentityClient {
  constructor(private readonly context: common.Context) {
  }

  private currentSession(): ZhihuSessionData {
    return ZhihuSessionRepository.load(this.context);
  }

  // 获取当前手机号下的账号列表（含主账号与马甲号）
  async listAccounts(): Promise<ZhihuIdentityAccount[]> {
    const session = this.currentSession();
    const body = await ZhihuApi.getJson(this.context, ZHIHU_API_BASE_URL + IDENTITY_ACCOUNT_LIST_PATH, {
      signed: false,
      allowUnauthorized: true,
      headers: buildIdentityHeaders(session)
    });
    if (body === null) {
      throw new Error('身份管理接口未授权，请重新登录后重试');
    }
    const data = Array.isArray(body['data']) ? (body['data'] as Array<object>) : [];
    return data.map((raw: object) => parseIdentityAccount(raw));
  }

  // 开通并初始化一个新马甲号
  async createSubAccount(): Promise<ZhihuIdentityChangeResult> {
    const session = this.currentSession();
    const body = await ZhihuApi.postJson(this.context, ZHIHU_API_BASE_URL + CREATE_SUB_ACCOUNT_PATH, {
      signed: false,
      allowUnauthorized: true,
      headers: buildIdentityHeaders(session)
    });
    if (body === null) {
      throw new Error('创建新账号失败：接口未授权，请重新登录后重试');
    }
    return this.applyIssuedToken(body, null);
  }

  // 切换到指定账号，并同步刷新当前账号状态
  async switchAccount(targetUserId: string): Promise<ZhihuIdentityChangeResult> {
    if (targetUserId.length === 0) {
      throw new Error('目标账号不能为空');
    }
    const session = this.currentSession();
    const body = await ZhihuApi.postJson(this.context, ZHIHU_API_BASE_URL + SWITCH_ACCOUNT_PATH, {
      signed: false,
      allowUnauthorized: true,
      headers: buildIdentityHeaders(session),
      body: JSON.stringify({ target_user_id: targetUserId })
    });
    if (body === null) {
      throw new Error('切换账号失败：接口未授权，请重新登录后重试');
    }
    return this.applyIssuedToken(body, targetUserId);
  }

  // 服务器签发新 token + cookie 后，用新凭证请求 /people/self 完整初始化会话并保存
  private async applyIssuedToken(rawBody: object, expectedAccountId: string | null): Promise<ZhihuIdentityChangeResult> {
    const body = rawBody as Record<string, object>;
    const accessToken = readString(body['access_token']);
    if (accessToken.length === 0) {
      throw new Error('服务器未返回新账号凭证');
    }
    const cookieMap = body['cookie'] as Record<string, Object> | undefined;
    const zc0 = cookieMap !== undefined ? readString(cookieMap['z_c0']) : '';
    if (zc0.length === 0) {
      throw new Error('服务器未返回新账号 Cookie');
    }

    const oldSession = this.currentSession();
    const newCookies: Record<string, string> = { ...oldSession.cookies };
    if (cookieMap !== undefined) {
      Object.entries(cookieMap).forEach(([key, value]: [string, Object]) => {
        if (typeof value === 'string' && value.length > 0) {
          newCookies[key] = value;
        }
      });
    }

    const tokenType: string = readString(body['token_type']) || 'bearer';
    const refreshToken: string = readString(body['refresh_token']);
    const expiresAt: number = typeof body['expires_at'] === 'number' ? (body['expires_at'] as number) : 0;

    // 用新 token 初始化会话：请求 /people/self
    const tempSession: ZhihuSessionData = {
      ...oldSession,
      mobileAccessToken: accessToken,
      mobileTokenType: tokenType
    };
    const profileBody = await ZhihuApi.getJson(this.context, ZHIHU_API_BASE_URL + CURRENT_ACCOUNT_PATH, {
      signed: false,
      allowUnauthorized: true,
      headers: buildIdentityHeaders(tempSession)
    });
    if (profileBody === null) {
      throw new Error('初始化新账号失败：无法获取账号资料');
    }
    const profile = parseIdentityProfile(profileBody);
    if (profile.id.length === 0 || profile.name.length === 0) {
      throw new Error('服务器返回的账号资料不完整');
    }
    if (expectedAccountId !== null && profile.id !== expectedAccountId) {
      throw new Error('服务器返回的账号与目标账号不一致');
    }

    const nextSession: ZhihuSessionData = {
      ...oldSession,
      login: true,
      username: profile.name,
      cookies: newCookies,
      self: {
        id: profile.id,
        name: profile.name,
        headline: '',
        avatarUrl: profile.avatarUrl,
        urlToken: profile.urlToken,
        userType: profile.userType
      },
      mobileAccessToken: accessToken,
      mobileRefreshToken: refreshToken,
      mobileTokenType: tokenType,
      mobileTokenExpiresAt: expiresAt
    };
    ZhihuSessionRepository.save(this.context, nextSession);

    const account: ZhihuIdentityAccount = {
      id: profile.id,
      urlToken: profile.urlToken,
      name: profile.name,
      avatarUrl: profile.avatarUrl,
      isActive: true,
      canCreateSubAccount: profile.canCreateSubAccount,
      accountType: profile.accountType,
      subAccountControlStatus: profile.subAccountControlStatus
    };
    return { account, session: nextSession };
  }
}

// 对齐安卓 applyIdentityHeaders：仅当存在移动端 token 时才带 Authorization 头（首次调用仅靠 z_c0 cookie 鉴权）
function buildIdentityHeaders(session: ZhihuSessionData): Record<string, string> {
  const headers: Record<string, string> = {
    'Accept': 'application/json',
    'User-Agent': ZHIHU_ANDROID_IDENTITY_USER_AGENT,
    'x-api-version': '3.0.93',
    'x-app-version': '11.2.0',
    'x-app-build': 'release',
    'x-app-bundleid': 'com.zhihu.android',
    'x-app-flavor': 'zhihuwap64',
    'x-app-za':
      'OS=Android&Release=12&Model=sdk_gphone64_arm64&VersionName=11.2.0&VersionCode=40210&' +
      'Product=com.zhihu.android&Width=1440&Height=2952&Installer=Market&DeviceType=AndroidPhone&Brand=google',
    'x-network-type': 'WiFi',
    'x-zse-93': '101_1_1.0',
    'Referer': 'https://api.zhihu.com/'
  };
  const token = session.mobileAccessToken;
  if (typeof token === 'string' && token.length > 0) {
    const tokenType = (typeof session.mobileTokenType === 'string' && session.mobileTokenType.length > 0)
      ? session.mobileTokenType
      : 'bearer';
    headers['Authorization'] = `${tokenType} ${token}`;
  }
  return headers;
}

function readString(value: object | undefined): string {
  return typeof value === 'string' ? value : '';
}

function readBool(value: unknown): boolean {
  return value === true;
}

function parseIdentityAccount(raw: object): ZhihuIdentityAccount {
  const obj = raw as Record<string, object>;
  return {
    id: readString(obj['id']),
    urlToken: readString(obj['url_token']),
    name: readString(obj['name']),
    avatarUrl: readString(obj['avatar_url']),
    isActive: readBool(obj['is_active']),
    canCreateSubAccount: readBool(obj['can_create_sub_account']),
    accountType: typeof obj['account_type'] === 'number' ? (obj['account_type'] as number) : 0,
    subAccountControlStatus: typeof obj['sub_account_control_status'] === 'number'
      ? (obj['sub_account_control_status'] as number)
      : 0
  };
}

function parseIdentityProfile(raw: object): {
  id: string;
  name: string;
  urlToken: string;
  userType: string;
  avatarUrl: string;
  canCreateSubAccount: boolean;
  accountType: number;
  subAccountControlStatus: number;
} {
  const obj = raw as Record<string, object>;
  return {
    id: readString(obj['id']),
    name: readString(obj['name']),
    urlToken: readString(obj['url_token']),
    userType: readString(obj['user_type']),
    avatarUrl: readString(obj['avatar_url']),
    canCreateSubAccount: readBool(obj['can_create_sub_account']),
    accountType: typeof obj['account_type'] === 'number' ? (obj['account_type'] as number) : 0,
    subAccountControlStatus: typeof obj['sub_account_control_status'] === 'number'
      ? (obj['sub_account_control_status'] as number)
      : 0
  };
}
