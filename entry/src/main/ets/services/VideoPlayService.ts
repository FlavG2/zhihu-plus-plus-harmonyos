import common from '@ohos.app.ability.common';
import { ZhihuApi } from './ZhihuApi';

type JsonObject = Record<string, Object>;

/**
 * 画质选项条目。
 */
export interface QualityOption {
  readonly label: string;  // 显示名，如 "高清 HD"、"标清 SD"
  readonly quality: string; // 内部值，如 "HD"、"SD"
  readonly url: string;    // mp4 直链
}

/**
 * 视频播放服务（对齐安卓 zhihu-plus-plus 的 VideoPlayerActivity + fetchHighestQualityZhihuVideoUrl）
 *
 * play_info 精确请求格式（来自安卓源码反推 + 现有 ZSE-96 签名验证）：
 *   Endpoint: https://www.zhihu.com/api/v4/video/play_info?r={videoId}
 *   Method:   POST
 *   Headers:
 *     - x-zse-93 / x-zse-96 / x-requested-with : 由 ZhihuSignerBridge.buildSignedHeaders 提供（含签名）
 *     - x-xsrftoken                          : 由会话 cookie 提供（签名器自动附加）
 *     - x-app-za   : "OS=webplayer"  ← 不参与签名，但 play_info 强制需要
 *     - x-referer  : ""             ← 不参与签名，但 play_info 强制需要
 *   Body（必须是 JSON 字符串，且需与签名源逐字一致）：
 *     {"content_id":"...","content_type_str":"answer|article|video","video_id":"...","scene_code":"answer_detail_web","is_only_video":true}
 *   Response: { video_play: { playlist: { mp4: [ { quality: "1080p", url: "..." }, ... ] } } }
 *
 * 注意：body 会被 buildSignedHeaders 纳入签名源（[ZSE_93, path, d_c0, body].join('+')），
 *       因此 body 必须与安卓逐字一致（含键顺序、无多余空格、布尔值不写成字符串），
 *       否则签名校验失败返回 401/403。
 */
export class VideoPlayService {
  private static readonly PLAY_INFO_URL: string = 'https://www.zhihu.com/api/v4/video/play_info';

  private static readonly QUALITY_ORDER: string[] = ['HD', 'SD', 'LD'];

  /**
   * 从一条 mp4 条目里提取 url（兼容 url 是字符串或字符串数组的情况）。
   */
  private static extractUrl(entry: JsonObject): string | undefined {
    const urlField = entry['url'];
    if (typeof urlField === 'string' && urlField.length > 0) {
      return urlField;
    }
    if (Array.isArray(urlField)) {
      for (const item of urlField) {
        if (typeof item === 'string' && item.length > 0) {
          return item;
        }
      }
    }
    return undefined;
  }

  /** 最近一次 play_info 的原始响应 JSON 字符串（调试用，截断 3000 字符） */
  static lastRawResponse: string = '';

  /** 最近一次 play_info 请求的错误详情 */
  static lastError: string = '';

  /** 最近成功响应的完整 JsonObject（画质选择用） */
  static lastPlayInfo: JsonObject | null = null;

  /**
   * 从最近成功响应的 play_info 中提取所有可用画质选项。
   * 返回空数组表示无可用画质数据。
   */
  static getAvailableQualities(): QualityOption[] {
    const playInfo = VideoPlayService.lastPlayInfo;
    if (playInfo === null) {
      return [];
    }
    const videoPlay = playInfo['video_play'];
    if (!(videoPlay instanceof Object)) {
      return [];
    }
    const playlist = (videoPlay as JsonObject)['playlist'];
    if (!(playlist instanceof Object)) {
      return [];
    }
    const mp4List = (playlist as JsonObject)['mp4'];
    if (!Array.isArray(mp4List)) {
      return [];
    }
    const result: QualityOption[] = [];
    for (const entry of mp4List) {
      const obj = entry as JsonObject;
      const quality = obj['quality'];
      const name = obj['name'];       // 如 "480P"
      const label = obj['label'];     // 如 "标清480P"
      const url = VideoPlayService.extractUrl(obj);
      if (typeof quality === 'string' && quality.length > 0 && url !== undefined) {
        const displayLabel = typeof label === 'string' && label.length > 0 ? label : name;
        result.push({
          label: typeof displayLabel === 'string' ? displayLabel : quality,
          quality,
          url
        });
      }
    }
    return result;
  }

  /**
   * 从 play_info 响应里挑选最高可用码率的 mp4 直链（直译安卓 selectHighestQualityZhihuVideoUrl）。
   * 返回 undefined 表示没有可播放的地址。
   */
  static selectHighestQualityZhihuVideoUrl(playInfo: JsonObject): string | undefined {
    const videoPlay = playInfo['video_play'];
    if (!(videoPlay instanceof Object)) {
      return undefined;
    }
    const playlist = (videoPlay as JsonObject)['playlist'];
    if (!(playlist instanceof Object)) {
      return undefined;
    }
    const mp4List = (playlist as JsonObject)['mp4'];
    if (!Array.isArray(mp4List)) {
      return undefined;
    }
    for (const quality of VideoPlayService.QUALITY_ORDER) {
      const found = mp4List.find((entry: Object): boolean => {
        const obj = entry as JsonObject;
        return typeof obj['quality'] === 'string' && obj['quality'] === quality;
      });
      if (found !== undefined) {
        const url = VideoPlayService.extractUrl(found as JsonObject);
        if (url !== undefined && url.length > 0) {
          return url;
        }
      }
    }
    if (mp4List.length > 0) {
      const url = VideoPlayService.extractUrl(mp4List[0] as JsonObject);
      if (url !== undefined && url.length > 0) {
        return url;
      }
    }
    return undefined;
  }

  /**
   * 获取视频直链。
   * @param videoId     视频 ID（HTML 里 a.video-box[data-lens-id]）
   * @param contentId   所属内容 ID（回答/文章 ID；独立视频帖可用 videoId）
   * @param contentType 'answer' | 'article' | 'video'
   */
  static async getPlayUrl(
    context: common.Context,
    videoId: string,
    contentId: string,
    contentType: string = 'answer'
  ): Promise<string | undefined> {
    if (videoId.length === 0) {
      return undefined;
    }
    const url = `${VideoPlayService.PLAY_INFO_URL}?r=${videoId}`;
    // 必须与安卓逐字一致（键顺序、布尔值），否则签名失败
    const body = JSON.stringify({
      content_id: contentId.length > 0 ? contentId : videoId,
      content_type_str: contentType,
      video_id: videoId,
      scene_code: 'answer_detail_web',
      is_only_video: true
    });
    VideoPlayService.lastRawResponse = '';
    VideoPlayService.lastError = '';
    try {
      const resp = await ZhihuApi.postJson(context, url, {
        signed: true,
        body
      });
      if (resp === null) {
        VideoPlayService.lastRawResponse = '响应为 null（HTTP 非 2xx 或空 body）';
        VideoPlayService.lastPlayInfo = null;
        return undefined;
      }
      VideoPlayService.lastRawResponse = JSON.stringify(resp).slice(0, 3000);
      VideoPlayService.lastPlayInfo = resp;
      return VideoPlayService.selectHighestQualityZhihuVideoUrl(resp);
    } catch (e) {
      VideoPlayService.lastError = ((e as Error)?.message ?? String(e)).slice(0, 1000);
      VideoPlayService.lastRawResponse = '请求抛出异常: ' + VideoPlayService.lastError;
      VideoPlayService.lastPlayInfo = null;
      return undefined;
    }
  }
}
