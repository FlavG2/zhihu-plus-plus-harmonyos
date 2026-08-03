import common from '@ohos.app.ability.common';
import { DEFAULT_USER_AGENT, ZhihuAccountProfile, ZhihuSessionData } from '../models/ZhihuModels';
import { ZhihuApi } from './ZhihuApi';
import { ZhihuSessionRepository } from './ZhihuSessionRepository';

type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];

interface JsonObject {
  [key: string]: JsonValue;
}

export class ZhihuAuthService {
  private static readonly ME_URL: string = 'https://www.zhihu.com/api/v4/me';

  private static mapProfile(payload: JsonObject): ZhihuAccountProfile {
    return {
      id: `${payload.id ?? ''}`,
      name: typeof payload.name === 'string' ? payload.name : '知乎用户',
      headline: typeof payload.headline === 'string' ? payload.headline : '',
      avatarUrl: typeof payload.avatar_url === 'string' ? payload.avatar_url : '',
      urlToken: typeof payload.url_token === 'string' ? payload.url_token : '',
      userType: typeof payload.user_type === 'string' ? payload.user_type : ''
    };
  }

  static async verifyLogin(context: common.Context, cookies: Record<string, string>): Promise<boolean> {
    const payload = await ZhihuApi.getJson(context, this.ME_URL, {
      signed: false,
      cookies,
      allowUnauthorized: true
    });
    if (payload === null) {
      return false;
    }

    const profile = this.mapProfile(payload as JsonObject);
    const session: ZhihuSessionData = {
      login: true,
      username: profile.name,
      cookies,
      userAgent: DEFAULT_USER_AGENT,
      self: profile
    };
    ZhihuSessionRepository.save(context, session);
    return true;
  }
}
