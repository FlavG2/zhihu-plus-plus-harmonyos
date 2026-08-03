import common from '@ohos.app.ability.common';
import { http } from '@kit.NetworkKit';
import { DEFAULT_USER_AGENT } from '../models/ZhihuModels';
import { ZhihuSessionRepository } from './ZhihuSessionRepository';
import { ZhihuSignerBridge } from './ZhihuSignerBridge';

type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];

interface JsonObject {
  [key: string]: JsonValue;
}

interface RequestOptions {
  readonly method?: http.RequestMethod;
  readonly signed?: boolean;
  readonly headers?: Record<string, string>;
  readonly body?: string;
  readonly cookies?: Record<string, string>;
  readonly allowUnauthorized?: boolean;
}

export class ZhihuApi {
  private static readonly DEFAULT_HEADERS: Record<string, string> = {
    'Accept': 'application/json, text/plain, */*',
    'Content-Type': 'application/json',
    'Referer': 'https://www.zhihu.com/',
    'User-Agent': DEFAULT_USER_AGENT
  };

  private static serializeCookies(cookies: Record<string, string>): string {
    return Object.entries(cookies)
      .map(([key, value]: [string, string]) => `${key}=${value}`)
      .join('; ');
  }

  private static updateSessionCookiesFromHeaders(context: common.Context, header: Object): void {
    const rawHeaders = header as Record<string, Object>;
    const matchedKey = Object.keys(rawHeaders).find((item: string) => item.toLowerCase() === 'set-cookie');
    if (matchedKey === undefined) {
      return;
    }

    const headerValue = rawHeaders[matchedKey];
    const setCookies = Array.isArray(headerValue) ? headerValue : [headerValue];
    const parsedCookies: Record<string, string> = {};
    setCookies.forEach((item: Object) => {
      if (typeof item !== 'string' || item.length === 0) {
        return;
      }
      const firstSegment = item.split(';')[0];
      const equalsIndex = firstSegment.indexOf('=');
      if (equalsIndex <= 0) {
        return;
      }
      const name = firstSegment.slice(0, equalsIndex).trim();
      const value = firstSegment.slice(equalsIndex + 1).trim();
      if (name.length > 0) {
        parsedCookies[name] = value;
      }
    });

    if (Object.keys(parsedCookies).length > 0) {
      ZhihuSessionRepository.mergeCookies(context, parsedCookies);
    }
  }

  private static async requestJson(url: string, options?: RequestOptions): Promise<JsonObject | null>;
  private static async requestJson(
    context: common.Context,
    url: string,
    options?: RequestOptions
  ): Promise<JsonObject | null>;
  private static async requestJson(
    contextOrUrl: common.Context | string,
    urlOrOptions?: string | RequestOptions,
    maybeOptions: RequestOptions = {}
  ): Promise<JsonObject | null> {
    const hasContext = typeof contextOrUrl !== 'string';
    const context = hasContext ? contextOrUrl as common.Context : undefined;
    const url = hasContext ? urlOrOptions as string : contextOrUrl;
    const options = hasContext ? maybeOptions : (urlOrOptions as RequestOptions | undefined) ?? {};
    const client = http.createHttp();
    try {
      if (options.signed === true && context === undefined) {
        throw new Error('签名请求缺少上下文');
      }
      const sessionCookies = context !== undefined ? ZhihuSessionRepository.load(context).cookies : {};
      const cookieMap = options.cookies ?? sessionCookies;
      const cookieHeader = this.serializeCookies(cookieMap);
      const signedHeaders = options.signed === true && context !== undefined
        ? ZhihuSignerBridge.buildSignedHeaders(context, url, options.body)
        : {};
      const requestHeaders: Record<string, string> = {
        ...this.DEFAULT_HEADERS,
        ...signedHeaders,
        ...(options.headers ?? {})
      };
      if (cookieHeader.length > 0) {
        requestHeaders.Cookie = cookieHeader;
      }

      const result = await client.request(url, {
        method: options.method ?? http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 10000,
        header: requestHeaders,
        extraData: options.body
      });

      if (context !== undefined) {
        this.updateSessionCookiesFromHeaders(context, result.header);
      }
      if (result.responseCode === 401) {
        if (options.allowUnauthorized === true) {
          return null;
        }
        if (context !== undefined) {
          ZhihuSessionRepository.clear(context);
        }
        throw new Error('登录已过期，请重新登录');
      }
      if (result.responseCode < 200 || result.responseCode >= 300) {
        // [埋点] 把响应体也带进错误，让所有错误界面的 e.message 直接显示真实原因（含 403 的 body），便于真机排查
        let body = '';
        try {
          body = typeof result.result === 'string' ? result.result : JSON.stringify(result.result);
        } catch (_e) {
          body = String(result.result);
        }
        if (body.length > 600) {
          body = body.slice(0, 600) + '…';
        }
        throw new Error(`HTTP ${result.responseCode}: ${body}`);
      }

      const payload = typeof result.result === 'string' ? result.result : JSON.stringify(result.result ?? null);
      if (payload.length === 0) {
        return null;
      }
      return JSON.parse(payload) as JsonObject;
    } finally {
      client.destroy();
    }
  }

  static async getJson(url: string, options?: RequestOptions): Promise<JsonObject | null>;
  static async getJson(context: common.Context, url: string, options?: RequestOptions): Promise<JsonObject | null>;
  static async getJson(
    contextOrUrl: common.Context | string,
    urlOrOptions?: string | RequestOptions,
    maybeOptions: RequestOptions = {}
  ): Promise<JsonObject | null> {
    const hasContext = typeof contextOrUrl !== 'string';
    if (hasContext) {
      return this.requestJson(contextOrUrl as common.Context, urlOrOptions as string, maybeOptions);
    }
    return this.requestJson(contextOrUrl, urlOrOptions as RequestOptions | undefined);
  }

  static async postJson(context: common.Context, url: string, options: RequestOptions = {}): Promise<JsonObject | null> {
    return this.requestJson(context, url, {
      ...options,
      method: http.RequestMethod.POST
    });
  }

  static async putJson(context: common.Context, url: string, options: RequestOptions = {}): Promise<JsonObject | null> {
    return this.requestJson(context, url, {
      ...options,
      method: http.RequestMethod.PUT
    });
  }

  static async deleteJson(context: common.Context, url: string, options: RequestOptions = {}): Promise<JsonObject | null> {
    return this.requestJson(context, url, {
      ...options,
      method: http.RequestMethod.DELETE
    });
  }
}
