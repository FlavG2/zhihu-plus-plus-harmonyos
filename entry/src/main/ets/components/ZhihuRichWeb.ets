import common from '@ohos.app.ability.common';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { AppearanceThemeMode } from '../services/AppearanceSettingsRepository';
import { ThemeColors } from '../services/ThemeColors';
import { htmlToDataUrl, injectStyleIntoHtml } from '../utils/ZhihuHtml';
import {
  buildReaderVarsStyle,
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
      // 规则置为通配：空规则存在「脚本压根没被注入」的风险，那才是老 BUG 一直修不掉的原因。
      // 首帧正确性现已改由 updatePageUrl 内联的 <style> 保证，这里只作兜底与实时调节。
      scriptRules: ['*']
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
    if (html.length === 0) {
      this.pageUrl = 'about:blank';
      this.contentLoaded = false;
      return;
    }
    // 关键：把阅读体验变量直接写进 HTML 的 <style>，随文档一起解析，首帧即生效。
    // 这比任何「渲染后再用脚本改值」的方案都可靠——文档解析时变量就已就位，
    // 不存在「先按默认值渲染、随后被改值重排」的窗口，彻底消除跳动。
    // 这里取的是实时值（而不是 aboutToAppear 时的快照），故每次 html 更新都会重算。
    const reader: ReaderStyle = {
      fontScale: this.readerFontScale,
      lineHeight: this.readerLineHeight,
      paraSpacing: this.readerParaSpacing
    };
    const style = buildReaderVarsStyle(
      resolveZhihuThemeMode(this.context(), this.themeMode),
      this.oledBlack,
      reader
    );
    this.pageUrl = htmlToDataUrl(injectStyleIntoHtml(html, style));
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
      // 注入时机很关键。
      // documentEnd = 「页面加载完成、DOM 已渲染之后」：首帧先按 CSS 默认值
      // (--reader-font-scale 默认 1) 渲染，脚本随后改成真值触发重排，
      // 表现为每次进文章「先原字号、一秒内跳成设定字号」的老 BUG。
      // headEnd = head 解析完、body 尚未渲染时执行：此时 documentElement 已存在，
      // 设完 CSS 变量再渲染 body，首帧字号即正确，无闪烁。
      .runJavaScriptOnHeadEnd(this.scripts.map((item: ZhihuWebScript): ScriptItem => {
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
