import common from '@ohos.app.ability.common';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { AppearanceThemeMode } from '../services/AppearanceSettingsRepository';
import { ThemeColors } from '../services/ThemeColors';
import { htmlToDataUrl } from '../utils/ZhihuHtml';
import {
  buildThemeScript,
  loadZhihuWebScripts,
  ReaderStyle,
  resolveZhihuThemeMode,
  ZhihuRichWebEvent,
  ZhihuSegmentTapInfo,
  ZhihuWebScript,
  ZhihuWebBridgeHost
} from '../utils/ZhihuWebBridge';

@Component
export struct ZhihuRichWeb {
  @Prop @Watch('onHtmlChanged') html: string = '';
  @Prop @Watch('onSourceUrlChanged') sourceUrl: string = '';
  @Prop title: string = '';
  @Prop @Watch('onThemeModeChanged') themeMode: AppearanceThemeMode = 'system';
  @StorageLink('readerFontScale') @Watch('onReaderStyleChanged') readerFontScale: number = 1.0;
  @StorageLink('readerLineHeight') @Watch('onReaderStyleChanged') readerLineHeight: number = 1.72;
  @StorageLink('readerParaSpacing') @Watch('onReaderStyleChanged') readerParaSpacing: number = 1.0;
  @Prop heightCssPx: number = 320;
  @Prop fillHeight: boolean = false;

  @StorageLink('oledBlack') oledBlack: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;

  onLinkTap?: (url: string, text: string) => void;
  onImageTap?: (url: string) => void;
  onImageMenu?: (url: string) => void;
  onCopyMath?: (latex: string) => void;
  onVideoTap?: (videoId: string) => void;
  onContentHeightChange?: (heightPx: number) => void;
  onScrollChange?: (topPx: number) => void;
  onSummaryBoundsChange?: (bottomPx: number) => void;
  onHorizontalSwipe?: (state: string, dx: number) => void;
  onSegmentTap?: (seg: ZhihuSegmentTapInfo) => void;

  private readonly controller: webview.WebviewController = new webview.WebviewController();
  private readonly bridgeHost: ZhihuWebBridgeHost = new ZhihuWebBridgeHost((event: ZhihuRichWebEvent) => {
    this.handleBridgeEvent(event);
  });
  private scripts: Array<ZhihuWebScript> = [];
  private contentLoaded: boolean = false;
  @State private pageUrl: string = 'about:blank';

  aboutToAppear(): void {
    this.scripts = loadZhihuWebScripts(this.context());
    // 将主题（含 OLED 覆盖）与阅读体验变量一并注入文档结束脚本，确保每次加载都可靠生效，
    // 不再仅依赖 runJavaScript（设置面板覆盖页面时易静默失败）。实时变更仍由 applyTheme 兜底。
    const resolvedThemeMode = resolveZhihuThemeMode(this.context(), this.themeMode);
    const reader: ReaderStyle = {
      fontScale: this.readerFontScale,
      lineHeight: this.readerLineHeight,
      paraSpacing: this.readerParaSpacing
    };
    this.scripts.push({
      script: buildThemeScript(resolvedThemeMode, this.oledBlack, reader),
      scriptRules: []
    });
    this.updatePageUrl();
  }

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  private handleBridgeEvent(event: ZhihuRichWebEvent): void {
    if (event.type === 'link') {
      this.onLinkTap?.(event.url, event.text);
      return;
    }
    if (event.type === 'image') {
      this.onImageTap?.(event.url);
      return;
    }
    if (event.type === 'imageMenu') {
      this.onImageMenu?.(event.url);
      return;
    }
    if (event.type === 'copyMath') {
      this.onCopyMath?.(event.latex);
      return;
    }
    if (event.type === 'segment') {
      this.onSegmentTap?.(event as ZhihuSegmentTapInfo);
      return;
    }
    if (event.type === 'video') {
      this.onVideoTap?.(event.videoId);
      return;
    }
    if (event.type === 'scroll') {
      this.onScrollChange?.(event.top);
      return;
    }
    if (event.type === 'summaryH') {
      this.onSummaryBoundsChange?.(event.bottom);
      return;
    }
    if (event.type === 'hswipe') {
      this.onHorizontalSwipe?.(event.state, event.dx);
      return;
    }
    if (event.type === 'height') {
      // nothing special needed
    }
    this.onContentHeightChange?.(event.height);
  }

  private updatePageUrl(): void {
    const html = this.html.trim();
    this.pageUrl = html.length > 0 ? htmlToDataUrl(html) : 'about:blank';
    this.contentLoaded = false;
  }

  private applyTheme(): void {
    if (!this.contentLoaded) {
      return;
    }
    const resolvedThemeMode = resolveZhihuThemeMode(this.context(), this.themeMode);
    const reader: ReaderStyle = {
      fontScale: this.readerFontScale,
      lineHeight: this.readerLineHeight,
      paraSpacing: this.readerParaSpacing
    };
    this.controller.runJavaScript(buildThemeScript(resolvedThemeMode, this.oledBlack, reader)).catch(() => {
    });
  }

  private onHtmlChanged(): void {
    this.updatePageUrl();
  }

  private onSourceUrlChanged(): void {
    this.updatePageUrl();
  }

  private onThemeModeChanged(): void {
    this.applyTheme();
  }

  private onReaderStyleChanged(): void {
    this.applyTheme();
  }

  build() {
    Web({
      src: this.pageUrl,
      controller: this.controller,
      renderMode: RenderMode.ASYNC_RENDER
    })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(true)
      .imageAccess(true)
      .mixedMode(MixedMode.Compatible)
      .overScrollMode(OverScrollMode.NEVER)
      .javaScriptProxy({
        object: this.bridgeHost,
        name: 'zhihuBridge',
        methodList: ['postMessage'],
        controller: this.controller
      })
      .runJavaScriptOnDocumentEnd(this.scripts.map((item: ZhihuWebScript): ScriptItem => {
        return {
          script: item.script,
          scriptRules: item.scriptRules
        };
      }))
      .onPageEnd(() => {
        this.contentLoaded = true;
        this.applyTheme();
      })
      // 纯诊断：仅记录子资源 HTTP 错误（不改变、不拦截请求），用于确认图床是否仍返回 403。
      .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
        hilog.error(0x0000, 'ZhihuImg', 'httpErr code=%{public}d url=%{public}s',
          event.response.getResponseCode(), event.request.getRequestUrl());
      })
      .width('100%')
      .backgroundColor(ThemeColors.articleBackground(this.oledBlack, this.isDark))
      .layoutMode(this.fillHeight ? WebLayoutMode.NONE : WebLayoutMode.FIT_CONTENT)
      .layoutWeight(this.fillHeight ? 1 : 0)
      .height(this.fillHeight ? '100%' : 'auto')
  }
}
