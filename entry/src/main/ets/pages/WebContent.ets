import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import common from '@ohos.app.ability.common';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import fileUri from '@ohos.file.fileuri';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import { pasteboard } from '@kit.BasicServicesKit';

interface WebContentParams {
  title?: string;
  url?: string;
}

function isImageUrl(url: string): boolean {
  return /\.(jpg|jpeg|png|gif|webp|bmp)(\?|#|$)/i.test(url);
}

@Entry
@Component
struct WebContent {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageProp('bottomSafeAreaVp') private bottomSafeAreaVp: number = 0;
  private readonly webController: webview.WebviewController = new webview.WebviewController();
  @State private pageTitle: string = '内容';
  @State private pageUrl: string = '';
  @State private isImage: boolean = false;
  @State private showLinkMenu: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as WebContentParams;
    this.pageTitle = typeof params.title === 'string' && params.title.length > 0 ? params.title : '内容';
    this.pageUrl = typeof params.url === 'string' ? params.url : '';
    this.isImage = isImageUrl(this.pageUrl);
  }

  /** 保存到图库（复用 Article.ets 的 createAsset 逻辑） */
  private async saveImageToGallery(): Promise<void> {
    const url = this.pageUrl;
    if (url.length === 0) {
      return;
    }
    this.showToast('正在下载图片…');
    try {
      const httpReq = http.createHttp();
      const resp = await httpReq.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      httpReq.destroy();
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        this.showToast('图片下载失败');
        return;
      }
      const imageData = resp.result as ArrayBuffer;
      if (imageData.byteLength === 0) {
        this.showToast('图片为空');
        return;
      }
      const ext = url.includes('.png') ? 'png' : 'jpg';
      const helper = photoAccessHelper.getPhotoAccessHelper(getContext(this));
      const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, ext);
      const file = await fileIo.open(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      await fileIo.write(file.fd, imageData);
      fileIo.closeSync(file);
      this.showToast('已保存到图库');
    } catch (e) {
      console.error('[WebContentSave] 保存异常:', (e as Error)?.message ?? String(e));
      this.showToast('保存失败');
    }
  }

  /** 下载并分享图片文件 */
  private async shareImageFile(): Promise<void> {
    const url = this.pageUrl;
    if (url.length === 0) {
      return;
    }
    this.showToast('正在准备分享…');
    try {
      const httpReq = http.createHttp();
      const resp = await httpReq.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      httpReq.destroy();
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        this.showToast('图片下载失败');
        return;
      }
      const imageData = resp.result as ArrayBuffer;
      const ext = url.includes('.png') ? 'png' : 'jpg';
      const tmpPath = `${getContext(this).cacheDir}/zhihu_share_${Date.now()}.${ext}`;
      const file = fileIo.openSync(tmpPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, imageData);
      fileIo.closeSync(file.fd);

      const uri = fileUri.getUriFromPath(tmpPath);
      const utdType = ext === 'png' ? utd.UniformDataType.PNG : utd.UniformDataType.JPEG;
      const shareData = new systemShare.SharedData({
        utd: utdType,
        uri: uri,
        title: '分享图片'
      });
      const ctx = getContext(this) as common.UIAbilityContext;
      const controller = new systemShare.ShareController(shareData);
      await controller.show(ctx, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
    } catch (e) {
      console.error('[WebContentShare] 分享异常:', (e as Error)?.message ?? String(e));
      this.showToast('分享失败');
    }
  }

  private showToast(msg: string): void {
    promptAction.showToast({ message: msg, duration: 2000 });
  }

  private copyLink(): void {
    try {
      const pb = pasteboard.getSystemPasteboard();
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.pageUrl);
      pb.setData(data);
      this.showToast('链接已复制');
    } catch (e) {
      this.showToast('复制失败');
    }
  }

  private openInBrowser(): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.startAbility({ action: 'ohos.want.action.viewData', uri: this.pageUrl });
    } catch (e) {
      this.showToast('打开失败');
    }
  }

  build() {
    Column() {
      // 顶部栏
      Row() {
        Text('返回')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.action_text'))
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.action_background'))
          .borderRadius(16)
          .onClick(() => { router.back({ url: '' }); })

        Text(this.pageTitle)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 12 })

        if (!this.isImage) {
          Text('⋯')
            .fontSize(22)
            .fontColor($r('app.color.action_text'))
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .onClick(() => { this.showLinkMenu = !this.showLinkMenu; })
            .bindMenu(this.showLinkMenu, [
              { value: '复制链接', action: () => { this.showLinkMenu = false; this.copyLink(); } },
              { value: '在网页中打开', action: () => { this.showLinkMenu = false; this.openInBrowser(); } }
            ])
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.topSafeAreaVp + 16, bottom: 12 })
      .backgroundColor($r('app.color.glass_top_bar_background'))
      .border({ width: { bottom: 1 }, color: $r('app.color.glass_top_bar_border') })
      .backdropBlur(24)

      // 内容区
      if (this.pageUrl.length > 0) {
        Stack() {
          // 统一用 WebView（图片也用它，支持双指缩放）
          Web({ src: this.pageUrl, controller: this.webController })
            .width('100%')
            .layoutWeight(1)

          // 图片模式下：底部浮动操作按钮
          if (this.isImage) {
            Row({ space: 16 }) {
              // 保存到图库
              Row({ space: 4 }) {
                Text('💾')
                  .fontSize(16)
                Text('保存')
                  .fontSize(14)
                  .fontColor('#FFFFFF')
              }
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .backgroundColor('rgba(0,0,0,0.55)')
              .borderRadius(20)
              .onClick(() => { this.saveImageToGallery(); })

              // 分享图片文件
              Row({ space: 4 }) {
                Text('📤')
                  .fontSize(16)
                Text('分享')
                  .fontSize(14)
                  .fontColor('#FFFFFF')
              }
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .backgroundColor('rgba(0,0,0,0.55)')
              .borderRadius(20)
              .onClick(() => { this.shareImageFile(); })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .position({ bottom: this.bottomSafeAreaVp + 16 })
          }
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Column({ space: 10 }) {
          Text('缺少内容地址')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text('当前页面没有可打开的链接。')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
