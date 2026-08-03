import common from '@ohos.app.ability.common';
import { ZhihuApi } from './ZhihuApi';
import { ZhihuSessionRepository } from './ZhihuSessionRepository';

// 对齐安卓版 shared/login/QrLogin.kt 的知乎扫码登录流程
const QRCODE_URL: string = 'https://www.zhihu.com/api/v3/account/api/login/qrcode';
const SIGNIN_URL: string = 'https://www.zhihu.com/signin';
const UDID_URL: string = 'https://www.zhihu.com/udid';
const CAPTCHA_V2_URL: string = 'https://www.zhihu.com/api/v3/oauth/captcha/v2?type=captcha_sign_in';
const DESKTOP_USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';
const ORIGIN: string = 'https://www.zhihu.com';
const DEFAULT_DEADLINE_MILLIS: number = 120_000;
const POLL_INTERVAL_MS: number = 500;
const REQUEST_TIMEOUT_MS: number = 10_000;

interface QrCodeData {
  readonly token: string;
  readonly link: string;
  readonly expiresAt: number;
}

interface QrScanInfo {
  readonly status: number;
  readonly cookie: string;
  readonly cookies: string;
  readonly zC0: string;
  readonly userId: string;
  readonly accessToken: string;
  readonly success: boolean;
  readonly loggedIn: boolean;
  readonly loginStatus: string;
  readonly errorCode: number;
  readonly errorMessage: string;
  readonly errorNeedLogin: boolean;
}

interface QrLoginHeaders {
  readonly ua: string;
  readonly origin: string;
  readonly referer: string;
  readonly accept: string;
  readonly isPolling: boolean;
}

export interface QrLoginCallbacks {
  readonly onScanned: () => void;
  readonly onExpired: () => void;
  readonly onRiskControl: (message: string, redirect: string) => void;
}

function loginHeaders(referer: string, isPolling: boolean, context?: common.Context): Record<string, string> {
  const headers: Record<string, string> = {
    'User-Agent': DESKTOP_USER_AGENT,
    'Origin': ORIGIN,
    'Referer': referer,
    'x-requested-with': 'fetch',
    'content-type': 'application/json;charset=UTF-8',
    'Accept': isPolling ? '*/*' : 'application/json, text/plain, */*'
  };
  // 对齐安卓 createZhihuLoginHeaders：把会话里的 _xsrf 写成 x-xsrf-token 请求头（CSRF 防护，缺了易被 403）
  if (context !== undefined) {
    const xsrf = ZhihuSessionRepository.load(context).cookies['_xsrf'];
    if (xsrf !== undefined && xsrf.length > 0) {
      headers['x-xsrf-token'] = xsrf;
    }
  }
  if (isPolling) {
    headers['sec-fetch-dest'] = 'empty';
    headers['sec-fetch-mode'] = 'cors';
    headers['sec-fetch-site'] = 'same-origin';
  }
  return headers;
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

// 预取登录上下文（对齐安卓 prefetchQrLoginContext）：访问登录页/udid/captcha 以便服务端下发会话 Cookie
export async function prefetchQrLoginContext(context: common.Context): Promise<void> {
  try {
    await ZhihuApi.getJson(context, SIGNIN_URL, {
      signed: false,
      headers: loginHeaders(SIGNIN_URL, false, context),
      allowUnauthorized: true
    });
  } catch (_e) {
  }
  try {
    await ZhihuApi.postJson(context, UDID_URL, {
      signed: false,
      body: '{}',
      headers: loginHeaders(SIGNIN_URL, false, context)
    });
  } catch (_e) {
  }
  try {
    await ZhihuApi.getJson(context, CAPTCHA_V2_URL, {
      signed: false,
      headers: loginHeaders(SIGNIN_URL, false, context),
      allowUnauthorized: true
    });
  } catch (_e) {
  }
}

export async function requestQrCode(context: common.Context): Promise<QrCodeData> {
  const data = await ZhihuApi.postJson(context, QRCODE_URL, {
    signed: false,
    body: '{}',
    headers: loginHeaders(SIGNIN_URL, false, context),
    allowUnauthorized: true
  });
  if (data === null) {
    throw new Error('二维码获取失败：空响应');
  }
  const token = typeof data.token === 'string' ? (data.token as string) : (data.qrcode_token as string ?? '');
  const link = typeof data.link === 'string' ? (data.link as string) : '';
  const expiresAt = typeof data.expires_at === 'number' ? (data.expires_at as number) : 0;
  if (token.length === 0 || link.length === 0) {
    throw new Error('二维码获取失败：未返回 token 或链接');
  }
  return { token, link, expiresAt };
}

function readString(value: object | undefined): string {
  return typeof value === 'string' ? value : '';
}

function readNumber(value: object | undefined): number {
  return typeof value === 'number' ? value : 0;
}

function readBoolean(value: object | undefined): boolean {
  return typeof value === 'boolean' ? value : false;
}

function parseScanInfo(raw: object): QrScanInfo {
  const obj = raw as Record<string, object>;
  const errorObj = (obj.error ?? {}) as Record<string, object>;
  return {
    status: readNumber(obj.status),
    cookie: readString(obj.cookie),
    cookies: readString(obj.cookies),
    zC0: readString(obj.z_c0) || readString(obj.zC0),
    userId: readString(obj.user_id) || readString(obj.userId),
    accessToken: readString(obj.access_token) || readString(obj.accessToken),
    success: readBoolean(obj.success),
    loggedIn: readBoolean(obj.logged_in) || readBoolean(obj.loggedIn),
    loginStatus: (readString(obj.login_status) || readString(obj.loginStatus)).toUpperCase(),
    errorCode: readNumber(errorObj.code),
    errorMessage: readString(errorObj.message) || readString(errorObj.msg),
    errorNeedLogin: readBoolean(errorObj.need_login) || readBoolean(errorObj.needLogin)
  };
}

const SKIP_COOKIE_ATTRIBUTES: Set<string> = new Set<string>([
  'DOMAIN', 'PATH', 'EXPIRES', 'MAX-AGE', 'HTTPONLY', 'SECURE', 'SAMESITE'
]);

function parseCookieAssignments(rawCookie: string): Record<string, string> {
  const result: Record<string, string> = {};
  rawCookie.split(';').forEach((item: string) => {
    const trimmed = item.trim();
    const separatorIndex = trimmed.indexOf('=');
    if (separatorIndex <= 0) {
      return;
    }
    const name = trimmed.slice(0, separatorIndex).trim().toUpperCase();
    if (name.length === 0 || SKIP_COOKIE_ATTRIBUTES.has(name)) {
      return;
    }
    const value = trimmed.slice(separatorIndex + 1).trim();
    if (value.length === 0) {
      return;
    }
    result[name] = value;
  });
  return result;
}

function isQrLoginSuccessful(info: QrScanInfo): boolean {
  if (info.userId.length > 0 || info.accessToken.length > 0 || info.success || info.loggedIn) {
    return true;
  }
  return info.loginStatus in new Set<string>(['CONFIRMED', 'LOGIN_SUCCESS', 'SUCCESS', 'OK', 'LOGGED_IN']);
}

function isQrLoginExpired(info: QrScanInfo): boolean {
  if (info.status === 2) {
    return true;
  }
  return info.loginStatus in new Set<string>(['EXPIRED', 'QR_CODE_EXPIRED', 'LOGIN_EXPIRED']);
}

function isRiskControlResponse(statusCode: number, info: QrScanInfo): boolean {
  return statusCode === 403 && (info.errorCode === 40352 || info.errorNeedLogin);
}

function normalizeDeadline(expiresAt: number): number {
  const now = Date.now();
  if (expiresAt <= 0) {
    return now + DEFAULT_DEADLINE_MILLIS;
  }
  if (expiresAt < 10_000_000_000) {
    // 秒级时间戳或 TTL（秒）
    if (expiresAt <= 86_400) {
      return now + expiresAt * 1000;
    }
    return now + expiresAt * 1000;
  }
  return expiresAt;
}

// 轮询扫码状态。成功返回合并后的 Cookie 表；超时/过期/取消/风控返回 null。
export async function pollQrCodeLogin(
  context: common.Context,
  token: string,
  expiresAt: number,
  callbacks: QrLoginCallbacks,
  isCancelled: () => boolean
): Promise<Record<string, string> | null> {
  const deadline = normalizeDeadline(expiresAt);
  const scanUrl = `${QRCODE_URL}/${token}/scan_info`;

  while (Date.now() <= deadline) {
    if (isCancelled()) {
      return null;
    }
    try {
      const data = await ZhihuApi.getJson(context, scanUrl, {
        signed: true,
        headers: loginHeaders(SIGNIN_URL, true, context),
        allowUnauthorized: true
      });
      if (data === null) {
        await delay(POLL_INTERVAL_MS);
        continue;
      }
      const info = parseScanInfo(data);

      if (isRiskControlResponse(403, info)) {
        callbacks.onRiskControl(
          info.errorMessage.length > 0 ? info.errorMessage : '知乎限制了当前网络环境的登录请求，请先完成网络环境验证。',
          ORIGIN + '/account/risk_control/'
        );
        return null;
      }

      if (info.status === 1) {
        callbacks.onScanned();
      }

      if (isQrLoginExpired(info)) {
        callbacks.onExpired();
        return null;
      }

      if (isQrLoginSuccessful(info)) {
        const merged: Record<string, string> = { ...ZhihuSessionRepository.load(context).cookies };
        const rawCookie = [info.cookie, info.cookies].filter((item: string) => item.length > 0).join(';');
        Object.assign(merged, parseCookieAssignments(rawCookie));
        if (info.zC0.length > 0) {
          merged['z_c0'] = info.zC0;
        }
        if (merged['z_c0'] !== undefined || info.userId.length > 0 || info.accessToken.length > 0) {
          return merged;
        }
      }
    } catch (_e) {
      // 临时网络抖动时继续轮询
    }
    await delay(POLL_INTERVAL_MS);
  }
  return null;
}
