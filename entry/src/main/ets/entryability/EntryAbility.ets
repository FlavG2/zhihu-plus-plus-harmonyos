import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppearanceSettingsRepository } from '../services/AppearanceSettingsRepository';

const DOMAIN = 0x0000;
const TAG = 'ZhihuPlusNext';
const TOP_SAFE_AREA_KEY = 'topSafeAreaVp';
const BOTTOM_SAFE_AREA_KEY = 'bottomSafeAreaVp';
const PENDING_DEEP_LINK_KEY = 'pendingDeepLink';

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
