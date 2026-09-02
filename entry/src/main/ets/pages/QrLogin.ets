import common from '@ohos.app.ability.common';
import { router, promptAction } from '@kit.ArkUI';
import { ZhihuAuthService } from '../services/ZhihuAuthService';
import {
  prefetchQrLoginContext,
  requestQrCode,
  pollQrCodeLogin
} from '../services/QrLoginService';
import { PageHeader } from '../components/PageHeader';

@Entry
@Component
struct QrLogin {
  @StorageProp('fontMeta') private fontMeta: string = '13fp';
  @StorageProp('fontSecondary') private fontSecondary: string = '14fp';
  @State private qrLink: string = '';
  @State private statusText: string = '正在获取二维码…';
  @State private isWorking: boolean = true;
  @State private riskControlMessage: string = '';
  private runId: number = 0;

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  aboutToAppear(): void {
    this.start();
  }

  aboutToDisappear(): void {
    this.runId += 1;
  }

  private async start(): Promise<void> {
    const myRunId = ++this.runId;
    this.qrLink = '';
    this.isWorking = true;
    this.riskControlMessage = '';
    this.statusText = '正在获取二维码…';
    try {
      await prefetchQrLoginContext(this.context());
      if (this.runId !== myRunId) {
        return;
      }
      const qr = await requestQrCode(this.context());
      if (this.runId !== myRunId) {
        return;
      }
      this.qrLink = qr.link;
      this.statusText = '请使用知乎 App 扫码登录';
      const cookies = await pollQrCodeLogin(
        this.context(),
        qr.token,
        qr.expiresAt,
        {
          onScanned: () => {
            if (this.runId === myRunId) {
              this.statusText = '请在知乎 App 上确认登录';
            }
          },
          onExpired: () => {
            if (this.runId === myRunId) {
              this.statusText = '二维码已过期，请刷新后重试';
              this.isWorking = false;
            }
          },
          onRiskControl: (message: string) => {
            if (this.runId === myRunId) {
              this.riskControlMessage = message;
              this.statusText = message;
              this.isWorking = false;
            }
          }
        },
        () => this.runId !== myRunId
      );
      if (this.runId !== myRunId) {
        return;
      }
      if (cookies === null) {
        if (this.riskControlMessage.length === 0 && this.isWorking) {
          this.statusText = '二维码已过期，请刷新后重试';
          this.isWorking = false;
        }
        return;
      }
      this.statusText = '正在验证登录…';
      const ok = await ZhihuAuthService.verifyLogin(this.context(), cookies);
      if (this.runId !== myRunId) {
        return;
      }
      if (ok) {
        this.statusText = '登录成功';
        promptAction.showToast({ message: '登录成功', duration: 1500 });
        setTimeout(() => {
          router.back({ url: '' });
        }, 600);
        return;
      }
      this.statusText = '登录验证失败，请刷新后重试';
      this.isWorking = false;
    } catch (e) {
      if (this.runId !== myRunId) {
        return;
      }
      const message = e instanceof Error ? e.message : '未知错误';
      this.statusText = `二维码获取失败：${message}`;
      this.isWorking = false;
    }
  }

  build() {
    Column() {
      // 单行标题（副标题历史上有 @BuilderParam 跨组件崩溃隐患，这里只留一行）
      PageHeader({ title: '扫码登录' })

      Column({ space: 20 }) {
        if (this.riskControlMessage.length > 0) {
          Text(this.riskControlMessage)
            .fontSize(this.fontMeta)
            .fontColor($r('app.color.error_text'))
            .textAlign(TextAlign.Center)
            .padding({ left: 24, right: 24 })
        } else if (this.qrLink.length > 0) {
          QRCode(this.qrLink)
            .width(240)
            .height(240)
            .margin({ top: 24 })
            .color(Color.Black)
            .backgroundColor(Color.White)
        } else {
          LoadingProgress()
            .width(48)
            .height(48)
            .margin({ top: 24 })
            .color($r('app.color.action_text'))
        }

        Text(this.statusText)
          .fontSize(this.fontSecondary)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24 })

        Button('刷新二维码')
          .fontSize(this.fontSecondary)
          .backgroundColor($r('app.color.action_background'))
          .fontColor($r('app.color.action_text'))
          .onClick(() => {
            this.start();
          })
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
