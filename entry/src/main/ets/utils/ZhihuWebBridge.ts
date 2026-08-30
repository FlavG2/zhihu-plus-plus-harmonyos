import common from '@ohos.app.ability.common';
import { util } from '@kit.ArkTS';
import { AppearanceThemeMode } from '../services/AppearanceSettingsRepository';

export interface ZhihuWebScript {
  readonly script: string;
  readonly scriptRules: Array<string>;
}

export type ZhihuRichWebEvent =
  | {
    readonly type: 'link';
    readonly url: string;
    readonly text: string;
  }
  | {
    readonly type: 'image';
    readonly url: string;
  }
  | {
    readonly type: 'imageMenu';
    readonly url: string;
  }
  | {
    readonly type: 'copyMath';
    readonly latex: string;
  }
  | {
    readonly type: 'height';
    readonly height: number;
  }
  | {
    readonly type: 'scroll';
    readonly top: number;
  }
  | {
    readonly type: 'hswipe';
    readonly state: string;
    readonly dx: number;
  }
  | {
    readonly type: 'summaryH';
    readonly bottom: number;
  }
  | {
    readonly type: 'video';
    readonly videoId: string;
  }
  | {
    readonly type: 'segment';
    readonly id: string;
    readonly likeCount: number;
    readonly commentCount: number;
    readonly isLike: boolean;
    readonly displayText: string;
    readonly contentId: string;
    readonly contentType: string;
    readonly paragraphId: string;
    readonly startOffset: number;
    readonly endOffset: number;
    readonly segIds: string[];
  };

/** 划线片段点击透传的结构（与 ZhihuRichWebEvent 的 'segment' 变体一致，但不带 type 便于 UI 层持有） */
export interface ZhihuSegmentTapInfo {
  readonly id: string;
  readonly likeCount: number;
  readonly commentCount: number;
  readonly isLike: boolean;
  readonly displayText: string;
  readonly contentId: string;
  readonly contentType: string;
  readonly paragraphId: string;
  readonly startOffset: number;
  readonly endOffset: number;
  readonly segIds: string[];
}

const RAWFILE_SCRIPT_PATHS: string[] = [
  'zhihu_web/click-listener.js',
  'zhihu_web/segment-highlight.js',
  'zhihu_web/math-copy.js',
  'zhihu_web/footnotes.js',
  'zhihu_web/content-height.js',
  'zhihu_web/scroll-tracker.js',
  'zhihu_web/horizontal-swipe.js'
];

const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });

function stringValue(value: Object | undefined): string {
  return typeof value === 'string' ? value.trim() : '';
}

function numberValue(value: Object | undefined): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function scriptItem(context: common.Context, path: string): ZhihuWebScript {
  const content = context.resourceManager.getRawFileContentSync(path);
  return {
    script: decoder.decodeWithStream(content),
    scriptRules: ['*']
  };
}

export function loadZhihuWebScripts(context: common.Context): ZhihuWebScript[] {
  const scripts: ZhihuWebScript[] = [];
  RAWFILE_SCRIPT_PATHS.forEach((path: string) => {
    try {
      scripts.push(scriptItem(context, path));
    } catch (_) {
    }
  });
  return scripts;
}

export function normalizeZhihuThemeMode(themeMode: AppearanceThemeMode): 'light' | 'dark' | 'system' {
  if (themeMode === 'light' || themeMode === 'dark') {
    return themeMode;
  }
  return 'system';
}

export function resolveZhihuThemeMode(context: common.Context, themeMode: AppearanceThemeMode): 'light' | 'dark' {
  const normalized = normalizeZhihuThemeMode(themeMode);
  if (normalized !== 'system') {
    return normalized;
  }
  try {
    const configuration = context.resourceManager.getConfigurationSync();
    // resourceManager.ColorMode.DARK 的值为 0，故与 0 比较即判定深色
    return configuration.colorMode === 0 ? 'dark' : 'light';
  } catch (_) {
    return 'light';
  }
}

export interface ReaderStyle {
  readonly fontScale: number;
  readonly lineHeight: number;
  readonly paraSpacing: number;
}

export function buildThemeScript(
  themeMode: 'light' | 'dark',
  oledBlack: boolean = false,
  reader: ReaderStyle = { fontScale: 1, lineHeight: 1.72, paraSpacing: 1 }
): string {
  // OLED 黑开启且处于深色时，把文章 Web 正文底色与卡片底色也翻成纯黑
  const oledOverride = (oledBlack && themeMode === 'dark')
    ? `document.documentElement.style.setProperty('--page-bg', '#000000');`
      + `document.documentElement.style.setProperty('--card-bg', '#000000');`
    : '';
  // 阅读体验：字号 / 行高 / 段间距以 CSS 变量注入，HTML 侧消费并带默认值
  const readerVars = `
    document.documentElement.style.setProperty('--reader-font-scale', '${reader.fontScale}');
    document.documentElement.style.setProperty('--reader-line-height', '${reader.lineHeight}');
    document.documentElement.style.setProperty('--reader-para-spacing', '${reader.paraSpacing}');
  `;
  return `
    (function () {
      document.documentElement.setAttribute('data-ark-theme', '${themeMode}');
      ${readerVars}
      ${oledOverride}
    })();
  `;
}

export class ZhihuWebBridgeHost {
  constructor(private readonly onEvent: (event: ZhihuRichWebEvent) => void) {
  }

  postMessage(payload: string): void {
    const event = parseBridgeEvent(payload);
    if (event !== undefined) {
      this.onEvent(event);
    }
  }
}

function parseBridgeEvent(payload: string): ZhihuRichWebEvent | undefined {
  if (payload.length === 0) {
    return undefined;
  }

  try {
    const parsed = JSON.parse(payload) as Record<string, Object>;
    const type = stringValue(parsed.type);
    if (type === 'link') {
      const url = stringValue(parsed.url);
      if (url.length === 0) {
        return undefined;
      }
      return {
        type: 'link',
        url,
        text: stringValue(parsed.text)
      };
    }
    if (type === 'image') {
      const url = stringValue(parsed.url);
      if (url.length === 0) {
        return undefined;
      }
      return {
        type: 'image',
        url
      };
    }
    if (type === 'imageMenu') {
      const url = stringValue(parsed.url);
      if (url.length === 0) {
        return undefined;
      }
      return {
        type: 'imageMenu',
        url
      };
    }
    if (type === 'copyMath') {
      const latex = stringValue(parsed.latex);
      if (latex.length === 0) {
        return undefined;
      }
      return {
        type: 'copyMath',
        latex
      };
    }
    if (type === 'height') {
      const height = numberValue(parsed.height);
      if (!Number.isFinite(height) || height <= 0 || height > 200000) {
        return undefined;
      }
      return {
        type: 'height',
        height
      };
    }
    if (type === 'scroll') {
      const top = numberValue(parsed.top);
      if (!Number.isFinite(top) || top < 0 || top > 100000) {
        return undefined;
      }
      return {
        type: 'scroll',
        top
      };
    }
    if (type === 'hswipe') {
      const state = stringValue(parsed.state);
      if (state !== 'start' && state !== 'move' && state !== 'end') {
        return undefined;
      }
      return {
        type: 'hswipe',
        state,
        dx: numberValue(parsed.dx)
      };
    }
    if (type === 'summaryH') {
      const bottom = numberValue(parsed.bottom);
      if (!Number.isFinite(bottom) || bottom < 0 || bottom > 100000) {
        return undefined;
      }
      return {
        type: 'summaryH',
        bottom
      };
    }
    if (type === 'video') {
      const videoId = stringValue(parsed.videoId);
      if (videoId.length === 0) {
        return undefined;
      }
      return {
        type: 'video',
        videoId
      };
    }
    if (type === 'segment') {
      const rawSegIds = parsed.segIds;
      const segIds: string[] = Array.isArray(rawSegIds)
        ? rawSegIds.filter((x: Object): boolean => typeof x === 'string').map((x: Object): string => `${x}`)
        : [];
      return {
        type: 'segment',
        id: stringValue(parsed.id),
        likeCount: numberValue(parsed.likeCount),
        commentCount: numberValue(parsed.commentCount),
        isLike: stringValue(parsed.isLike) === 'true',
        displayText: stringValue(parsed.displayText),
        contentId: stringValue(parsed.contentId),
        contentType: stringValue(parsed.contentType),
        paragraphId: stringValue(parsed.paragraphId),
        startOffset: numberValue(parsed.startOffset),
        endOffset: numberValue(parsed.endOffset),
        segIds
      };
    }
  } catch (_) {
    return undefined;
  }
  return undefined;
}
