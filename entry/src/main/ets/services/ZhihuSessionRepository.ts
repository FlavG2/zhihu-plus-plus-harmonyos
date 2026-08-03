import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import { webview } from '@kit.ArkWeb';
import {
  createDefaultSessionData,
  DEFAULT_SESSION_SNAPSHOT,
  SessionSnapshot,
  ZhihuAccountProfile,
  ZhihuSessionData
} from '../models/ZhihuModels';

const SESSION_PREFERENCES_FILE: string = 'zhihu_session';
const SESSION_DATA_KEY: string = 'session_data';
const SESSION_SNAPSHOT_KEY: string = 'sessionSnapshot';
const SESSION_EPOCH_KEY: string = 'sessionEpoch';

export class ZhihuSessionRepository {
  private static initialized: boolean = false;
  private static cache: ZhihuSessionData = createDefaultSessionData();

  private static preferences(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, {
      name: SESSION_PREFERENCES_FILE
    });
  }

  private static updateAppStorage(snapshot: SessionSnapshot): SessionSnapshot {
    if (!AppStorage.set<SessionSnapshot>(SESSION_SNAPSHOT_KEY, snapshot)) {
      AppStorage.setOrCreate<SessionSnapshot>(SESSION_SNAPSHOT_KEY, snapshot);
    }
    return snapshot;
  }

  private static buildSnapshot(data: ZhihuSessionData): SessionSnapshot {
    const profile = data.self;
    const accountName = profile?.name ?? data.username;
    return {
      accountName: accountName.length > 0 ? accountName : DEFAULT_SESSION_SNAPSHOT.accountName,
      avatarUrl: profile?.avatarUrl ?? '',
      loggedIn: data.login,
      cookieCount: Object.keys(data.cookies).length,
      hasSigningBridge: true
    };
  }

  private static sanitizeProfile(raw: Object | undefined): ZhihuAccountProfile | undefined {
    if (raw === undefined || raw === null) {
      return undefined;
    }
    const objectValue = raw as Record<string, Object>;
    const name = typeof objectValue.name === 'string' ? objectValue.name : '';
    if (name.length === 0) {
      return undefined;
    }
    return {
      id: `${objectValue.id ?? ''}`,
      name,
      headline: typeof objectValue.headline === 'string' ? objectValue.headline : '',
      avatarUrl: typeof objectValue.avatarUrl === 'string' ? objectValue.avatarUrl : '',
      urlToken: typeof objectValue.urlToken === 'string' ? objectValue.urlToken : '',
      userType: typeof objectValue.userType === 'string' ? objectValue.userType : ''
    };
  }

  private static sanitizeCookies(raw: Object | undefined): Record<string, string> {
    if (raw === undefined || raw === null || typeof raw !== 'object') {
      return {};
    }
    const cookies: Record<string, string> = {};
    Object.entries(raw as Record<string, Object>).forEach(([key, value]: [string, Object]) => {
      if (typeof value === 'string' && value.length > 0) {
        cookies[key] = value;
      }
    });
    return cookies;
  }

  private static sanitizeSession(raw: Object | undefined): ZhihuSessionData {
    if (raw === undefined || raw === null || typeof raw !== 'object') {
      return createDefaultSessionData();
    }
    const defaults = createDefaultSessionData();
    const objectValue = raw as Record<string, Object>;
    return {
      login: objectValue.login === true,
      username: typeof objectValue.username === 'string' ? objectValue.username : '',
      cookies: this.sanitizeCookies(objectValue.cookies),
      userAgent: typeof objectValue.userAgent === 'string' && objectValue.userAgent.length > 0
        ? objectValue.userAgent
        : defaults.userAgent,
      self: this.sanitizeProfile(objectValue.self),
      mobileAccessToken: typeof objectValue.mobileAccessToken === 'string' && objectValue.mobileAccessToken.length > 0
        ? objectValue.mobileAccessToken
        : '',
      mobileRefreshToken: typeof objectValue.mobileRefreshToken === 'string' && objectValue.mobileRefreshToken.length > 0
        ? objectValue.mobileRefreshToken
        : '',
      mobileTokenType: typeof objectValue.mobileTokenType === 'string' && objectValue.mobileTokenType.length > 0
        ? objectValue.mobileTokenType
        : '',
      mobileTokenExpiresAt: typeof objectValue.mobileTokenExpiresAt === 'number' ? objectValue.mobileTokenExpiresAt : 0
    };
  }

  static load(context: common.Context): ZhihuSessionData {
    if (!this.initialized) {
      const store = this.preferences(context);
      const encoded = store.getSync(SESSION_DATA_KEY, '') as string;
      if (typeof encoded === 'string' && encoded.length > 0) {
        try {
          this.cache = this.sanitizeSession(JSON.parse(encoded) as Object);
        } catch (_) {
          this.cache = createDefaultSessionData();
        }
      } else {
        this.cache = createDefaultSessionData();
      }
      this.initialized = true;
    }
    this.updateAppStorage(this.buildSnapshot(this.cache));
    return this.cache;
  }

  static snapshot(context?: common.Context): SessionSnapshot {
    if (context !== undefined) {
      this.load(context);
    }
    return this.buildSnapshot(this.cache);
  }

  static save(context: common.Context, data: ZhihuSessionData): SessionSnapshot {
    const sanitized = this.sanitizeSession(data as Object);
    this.cache = sanitized;
    this.initialized = true;
    const store = this.preferences(context);
    store.putSync(SESSION_DATA_KEY, JSON.stringify(sanitized));
    store.flushSync();
    this.bumpEpoch();
    return this.updateAppStorage(this.buildSnapshot(sanitized));
  }

  // 会话版本自增：切换/创建马甲号后用于通知首页清除身份相关缓存并重载（对齐安卓 reloadApplication 整页重启）
  private static bumpEpoch(): void {
    const epoch = (AppStorage.get<number>(SESSION_EPOCH_KEY) ?? 0) + 1;
    if (!AppStorage.set<number>(SESSION_EPOCH_KEY, epoch)) {
      AppStorage.setOrCreate<number>(SESSION_EPOCH_KEY, epoch);
    }
  }

  static mergeCookies(context: common.Context, cookies: Record<string, string>): SessionSnapshot {
    const current = this.load(context);
    const nextCookies: Record<string, string> = { ...current.cookies };
    Object.entries(cookies).forEach(([key, value]: [string, string]) => {
      if (key === 'z_c0' && value.length === 0) {
        return;
      }
      if (value.length > 0) {
        nextCookies[key] = value;
      }
    });
    return this.save(context, {
      ...current,
      cookies: nextCookies
    });
  }

  static clear(context: common.Context): SessionSnapshot {
    this.cache = createDefaultSessionData();
    this.initialized = true;
    const store = this.preferences(context);
    store.putSync(SESSION_DATA_KEY, JSON.stringify(this.cache));
    store.flushSync();
    try {
      webview.WebCookieManager.clearAllCookiesSync();
      webview.WebCookieManager.saveCookieSync();
    } catch (_) {
    }
    this.bumpEpoch();
    return this.updateAppStorage(DEFAULT_SESSION_SNAPSHOT);
  }

  static cookieHeader(context: common.Context): string {
    const data = this.load(context);
    return Object.entries(data.cookies)
      .map(([key, value]: [string, string]) => `${key}=${value}`)
      .join('; ');
  }
}
