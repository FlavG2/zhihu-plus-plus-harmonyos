import common from '@ohos.app.ability.common';
import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { ZhihuAuthService } from '../services/ZhihuAuthService';

const LOGIN_URL: string = 'https://www.zhihu.com/signin';

function parseCookieString(rawCookie: string): Record<string, string> {
  const cookies: Record<string, string> = {};
  rawCookie.split(';').forEach((segment: string) => {
    const trimmed = segment.trim();
    if (trimmed.length === 0) {
      return;
    }
    const separatorIndex = trimmed.indexOf('=');
    if (separatorIndex <= 0) {
      return;
    }
    const name = trimmed.slice(0, separatorIndex).trim();
    const value = trimmed.slice(separatorIndex + 1).trim();
    if (name.length > 0) {
      cookies[name] = value;
    }
  });
  return cookies;
}

@Entry
@Component
struct Login {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @State private verifying: boolean = false;
  @State private loginError: string = '';
  private readonly webController: webview.WebviewController = new webview.WebviewController();

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  private async tryCompleteLogin(): Promise<void> {
    if (this.verifying) {
      return;
    }
    this.verifying = true;
    try {
      const rawCookie = await webview.WebCookieManager.fetchCookie('https://www.zhihu.com');
      const cookies = parseCookieString(rawCookie);
      if ((cookies.z_c0 ?? '').length === 0 && (cookies.d_c0 ?? '').length === 0) {
        return;
      }
      const verified = await ZhihuAuthService.verifyLogin(this.context(), cookies);
      if (verified) {
        router.back({ url: '' });
        return;
      }
      this.loginError = '登录信息尚未准备好，请完成知乎登录后返回。';
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.loginError = `登录校验失败：${message}`;
    } finally {
      this.verifying = false;
    }
  }

  build() {
    Column() {
      Row() {
        Text('返回')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.action_text'))
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(16)
          .onClick(() => {
            router.back({ url: '' });
          })

        Column({ space: 2 }) {
          Text('登录知乎')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Text(this.verifying ? '正在校验登录状态' : '完成登录后会自动返回主页')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.topSafeAreaVp + 16, bottom: 12 })
      .backgroundColor($r('app.color.glass_top_bar_background'))
      .border({
        width: {
          bottom: 1
        },
        color: $r('app.color.glass_top_bar_border')
      })
      .backdropBlur(24)

      if (this.loginError.length > 0) {
        Text(this.loginError)
          .fontSize(12)
          .fontColor($r('app.color.error_text'))
          .padding({ left: 20, right: 20, bottom: 10 })
      }

      Web({ src: LOGIN_URL, controller: this.webController })
        .layoutWeight(1)
        .width('100%')
        .onPageEnd(() => {
          this.tryCompleteLogin();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
