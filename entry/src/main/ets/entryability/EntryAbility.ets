import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { AppearanceSettingsRepository } from '../services/AppearanceSettingsRepository';

const DOMAIN = 0x0000;
const TAG = 'ZhihuPlusNext';
const TOP_SAFE_AREA_KEY = 'topSafeAreaVp';
const BOTTOM_SAFE_AREA_KEY = 'bottomSafeAreaVp';
const PENDING_DEEP_LINK_KEY = 'pendingDeepLink';

/**
 * 知乎图床（zhimg 严格节点）校验 User-Agent，ArkWeb 子资源 <img> 请求默认 UA 会被 403 裂图。
 * 关键：webview.WebviewController.setCustomUserAgent() 按 SDK 注释
 * "only takes effect in the current web context"，只作用于主文档、不传播到 <img> 子资源，
 * 因此它对详情页裂图无效。改用它按域名生效的 setUserAgentForHosts()（API 20+）：
 * 对该 host 发起的所有请求（含 <img> 子资源）都会带上指定 UA，从而绕过图床校验。
 * 这样无需预拉取 / 拦截 / base64 注入，页面保持干净 HTML，结构上不可能白屏。
 */
const ZHIHU_IMAGE_HOSTS: string[] = [
  'pic.zhimg.com',
  'pic1.zhimg.com',
  'pic2.zhimg.com',
  'pic3.zhimg.com',
  'pic4.zhimg.com',
  'picx.zhimg.com',
  'picx1.zhimg.com',
  'picx2.zhimg.com',
  'picx3.zhimg.com',
  'picx4.zhimg.com',
  'zhimg.com'
];

const MOBILE_UA =
  'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

function applyZhihuImageUserAgent(): void {
  try {
    webview.WebviewController.setUserAgentForHosts(MOBILE_UA, ZHIHU_IMAGE_HOSTS);
    hilog.info(DOMAIN, TAG, 'Zhihu image UA registered for %{public}d hosts.', ZHIHU_IMAGE_HOSTS.length);
  } catch (error) {
    hilog.error(DOMAIN, TAG, 'Failed to register zhihu image UA: %{public}s', JSON.stringify(error));
  }
}

function isZhihuLink(uri: string | undefined): string | undefined {
  if (!uri || uri.length === 0) {
    return undefined;
  }
  const normalized = uri.trim();
  if (/^https?:\/\/(?:www\.)?zhihu\.com\//i.test(normalized) ||
      /^zhihu:\/\//i.test(normalized)) {
    return normalized;
  }
  return undefined;
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 必须在任何 Web 组件创建之前注册，否则已发起的子资源请求拿不到该 UA。
    applyZhihuImageUserAgent();
    try {
      AppearanceSettingsRepository.load(this.context);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to set color mode: %{public}s', JSON.stringify(error));
    }
    hilog.info(DOMAIN, TAG, 'Ability created with want: %{public}s', JSON.stringify(want));
    hilog.info(DOMAIN, TAG, 'Launch param: %{public}s', JSON.stringify(launchParam));

    this.handleDeepLinkWant(want);
  }

  // 冷启动/热启动统一入口：把深链 URL 写入 AppStorage，交给 Index 页 popup 导航。
  private handleDeepLinkWant(want: Want): void {
    const link = isZhihuLink(want.uri);
    if (link !== undefined) {
      hilog.info(DOMAIN, TAG, 'Deep link captured: %{public}s', link);
      AppStorage.setOrCreate<string>(PENDING_DEEP_LINK_KEY, link);
    }
  }

  onNewWant(want: Want): void {
    hilog.info(DOMAIN, TAG, 'New want: %{public}s', JSON.stringify(want));
    this.handleDeepLinkWant(want);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    if (newConfig.colorMode !== undefined) {
      // 仅"跟随系统"模式需要根据系统新 colorMode 刷新 isDark。
      // 注意：绝不能调用 currentThemeMode/load/applyColorMode —— setColorMode 会再次触发本回调，导致无限递归栈溢出。
      if (AppearanceSettingsRepository.getThemeMode() === 'system') {
        const isDark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
        AppStorage.setOrCreate<boolean>('isDark', isDark);
      }
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      const updateSafeArea = (type: window.AvoidAreaType, area: window.AvoidArea): void => {
        if (type === window.AvoidAreaType.TYPE_SYSTEM) {
          AppStorage.setOrCreate<number>(TOP_SAFE_AREA_KEY, px2vp(area.topRect.height));
          return;
        }
        if (type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          AppStorage.setOrCreate<number>(BOTTOM_SAFE_AREA_KEY, px2vp(area.bottomRect.height));
        }
      };

      mainWindow.setWindowLayoutFullScreen(true)
        .then(() => {
          return mainWindow.setWindowSystemBarProperties({
            statusBarColor: '#00000000',
            navigationBarColor: '#00000000'
          });
        })
        .then(() => {
          updateSafeArea(window.AvoidAreaType.TYPE_SYSTEM, mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM));
          updateSafeArea(
            window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR,
            mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
          );
          mainWindow.on('avoidAreaChange', (data) => {
            updateSafeArea(data.type, data.area);
          });
          hilog.info(DOMAIN, TAG, 'Immersive window configured.');
        })
        .catch((error: Error) => {
          hilog.error(DOMAIN, TAG, 'Failed to configure immersive window: %{public}s', JSON.stringify(error));
        });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to access main window: %{public}s', JSON.stringify(error));
    }

    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content: %{public}s', JSON.stringify(error));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Main page loaded.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Window stage destroyed.');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability enters foreground.');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability enters background.');
  }
}
