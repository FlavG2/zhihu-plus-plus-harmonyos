import common from '@ohos.app.ability.common';
import { util } from '@kit.ArkTS';
import { ZhihuAuthService } from './ZhihuAuthService';
import { ZhihuSessionRepository } from './ZhihuSessionRepository';

interface DebugSessionPayload {
  enabled?: boolean;
  cookies?: Record<string, string>;
}

export class LocalDebugSessionService {
  private static readonly RAWFILE_PATH: string = 'debug/local_debug_session.json';
  private static readonly decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
  private static lastAppliedSignature: string = '';

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

  private static readPayload(context: common.Context): DebugSessionPayload | undefined {
    try {
      const content = context.resourceManager.getRawFileContentSync(this.RAWFILE_PATH);
      const text = this.decoder.decodeWithStream(content);
      const payload = JSON.parse(text) as DebugSessionPayload;
      return {
        enabled: payload.enabled === true,
        cookies: this.sanitizeCookies(payload.cookies as Object | undefined)
      };
    } catch (_) {
      return undefined;
    }
  }

  private static cookieSignature(cookies: Record<string, string>): string {
    return Object.entries(cookies)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, value]) => `${key}=${value}`)
      .join(';');
  }

  static async applyIfPresent(context: common.Context): Promise<boolean> {
    const payload = this.readPayload(context);
    if (payload === undefined || payload.enabled !== true) {
      return false;
    }

    const cookies = payload.cookies ?? {};
    if (Object.keys(cookies).length === 0) {
      return false;
    }

    const signature = this.cookieSignature(cookies);
    const currentSignature = this.cookieSignature(ZhihuSessionRepository.load(context).cookies);
    if (signature.length === 0 || signature === this.lastAppliedSignature || signature === currentSignature) {
      return false;
    }

    const verified = await ZhihuAuthService.verifyLogin(context, cookies);
    if (verified) {
      this.lastAppliedSignature = signature;
    }
    return verified;
  }
}
