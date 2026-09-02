import common from '@ohos.app.ability.common';
import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { ZhihuAuthService } from '../services/ZhihuAuthService';
import { PageHeader } from '../components/PageHeader';

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
  @StorageProp('fontCaption') private fontCaption: string = '12fp';
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
      // 单行标题（副标题历史上有 @BuilderParam 跨组件崩溃隐患，这里只留一行）
      PageHeader({ title: '登录知乎' })

      if (this.loginError.length > 0) {
        Text(this.loginError)
          .fontSize(this.fontCaption)
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
