import common from '@ohos.app.ability.common';
import { router } from '@kit.ArkUI';
import { VideoPlayService, QualityOption } from '../services/VideoPlayService';
import { ThemeColors } from '../services/ThemeColors';

const SPEED_OPTIONS: number[] = [0.5, 1.0, 1.25, 1.5, 2.0];

/**
 * 本地 VideoController 代理。
 * 当前 OpenHarmony SDK 的 @kit.ArkUI 未导出 VideoController（仅有 declare class），
 */
class LocalVideoController {
  start(): void {
    (this as Object as Record<string, (...args: Object[]) => void>)['start']?.();
  }

  pause(): void {
    (this as Object as Record<string, (...args: Object[]) => void>)['pause']?.();
  }

  stop(): void {
    (this as Object as Record<string, (...args: Object[]) => void>)['stop']?.();
  }

  setCurrentTime(value: number): void {
    (this as Object as Record<string, (...args: Object[]) => void>)['setCurrentTime']?.(value);
  }

  requestFullscreen(value: boolean): void {
    (this as Object as Record<string, (...args: Object[]) => void>)['requestFullscreen']?.(value);
  }

  exitFullscreen(): void {
    (this as Object as Record<string, (...args: Object[]) => void>)['exitFullscreen']?.();
  }
}

// 旋转模式
type RotateMode = 'auto' | 'portrait' | 'landscape';

@Entry
@Component
struct VideoPlayerPage {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageProp('bottomSafeAreaVp') private bottomSafeAreaVp: number = 0;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;
  @StorageProp('fontMeta') fontMeta: string = '13fp';
  @StorageProp('fontBody') fontBody: string = '16fp';
  @StorageProp('fontBodySm') fontBodySm: string = '15fp';
  @StorageProp('fontSecondary') fontSecondary: string = '14fp';
  @State private videoSrc: string = '';
  @State private loading: boolean = true;
  @State private errorMsg: string = '';
  @State private currentSpeed: number = 1.0;
  @State private qualities: QualityOption[] = [];
  @State private currentQuality: number = 0;
  @State private showSpeedMenu: boolean = false;
  @State private showQualityMenu: boolean = false;
  @State private rotateMode: RotateMode = 'auto';
  private controller: LocalVideoController = new LocalVideoController();
  private videoId: string = '';
  private contentId: string = '';
  private contentType: string = '';
  private title: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    const str = (key: string): string => {
      const v = params[key];
      return typeof v === 'string' ? v : '';
    };
    this.videoId = str('videoId');
    this.contentId = str('contentId');
    this.contentType = str('contentType') || 'answer';
    this.title = str('title');
    this.loadVideo();
  }

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  private async loadVideo(): Promise<void> {
    if (this.videoId.length === 0) {
      this.loading = false;
      this.errorMsg = '缺少视频 ID';
      return;
    }
    this.loading = true;
    this.errorMsg = '';
    try {
      const url = await VideoPlayService.getPlayUrl(
        this.context(),
        this.videoId,
        this.contentId,
        this.contentType
      );
      if (url !== undefined && url.length > 0) {
        this.videoSrc = url;
        this.qualities = VideoPlayService.getAvailableQualities();
      } else {
        const raw = VideoPlayService.lastRawResponse;
        const err = VideoPlayService.lastError;
        this.errorMsg = '获取视频地址失败';
        if (err.length > 0) {
          this.errorMsg += '\n错误: ' + err;
        } else if (raw.length > 0) {
          this.errorMsg += '\n响应: ' + raw;
        } else {
          this.errorMsg += '（接口返回空或签名被拒）';
        }
      }
    } catch (e) {
      this.errorMsg = '获取视频失败：' + ((e as Error)?.message ?? String(e));
      const raw = VideoPlayService.lastRawResponse;
      if (raw.length > 0) {
        this.errorMsg += '\n响应: ' + raw;
      }
    }
    this.loading = false;
  }

  private onBack(): void {
    router.back({ url: '' });
  }

  private changeSpeed(rate: number): void {
    this.currentSpeed = rate;
    this.showSpeedMenu = false;
  }

  private selectQuality(index: number): void {
    if (index >= 0 && index < this.qualities.length) {
      this.currentQuality = index;
      this.videoSrc = this.qualities[index].url;
    }
    this.showQualityMenu = false;
  }

  private toggleSpeedMenu(): void {
    this.showSpeedMenu = !this.showSpeedMenu;
    this.showQualityMenu = false;
  }

  private toggleQualityMenu(): void {
    this.showQualityMenu = !this.showQualityMenu;
    this.showSpeedMenu = false;
  }

  private cycleRotate(): void {
    // 三态循环：auto → portrait → landscape → auto
    if (this.rotateMode === 'auto') {
      this.rotateMode = 'portrait';
    } else if (this.rotateMode === 'portrait') {
      this.rotateMode = 'landscape';
    } else {
      this.rotateMode = 'auto';
    }
  }

  private qualityLabel(): string {
    return this.qualities.length > 0 ? this.qualities[this.currentQuality].label : '自动';
  }

  private rotateLabel(): string {
    if (this.rotateMode === 'auto') return '🔄';
    if (this.rotateMode === 'portrait') return '🔒';
    return '⤴';
  }

  // 单个浮层按钮（倍速 / 画质 / 旋转）
  @Builder
  private FloatingButton(label: string, isActive: boolean, onTap: () => void): void {
    Stack() {
      Text(label)
        .fontSize(this.fontMeta)
        .fontWeight(FontWeight.Bold)
        .fontColor(isActive ? '#FFFFFF' : $r('app.color.text_primary'))
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(isActive ? $r('app.color.action_text') : ThemeColors.oledBlack(this.oledBlack, this.isDark, $r('app.color.action_pill_button_inactive')))
        .border({
          width: 1,
          color: isActive ? $r('app.color.action_text') : $r('app.color.card_border')
        })
        .borderRadius(16)
        .onClick(() => onTap())
    }
  }

  build() {
    Column() {
      // 顶部栏（避开状态栏）
      Row() {
        Text('‹ 返回')
          .fontSize(this.fontBody)
          .fontColor($r('app.color.action_text'))
          .onClick(() => this.onBack())
        if (this.title.length > 0) {
          Text(this.title)
            .fontSize(this.fontBodySm)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: 12 })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 + this.topSafeAreaVp, bottom: 8 })

      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
          Text('正在获取视频…')
            .fontSize(this.fontMeta)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.videoSrc.length > 0) {
        Stack({ alignContent: Alignment.TopStart }) {
          // Video 层（高度扣除底部小白条安全距离）
          Video({
            src: this.videoSrc,
            currentProgressRate: this.currentSpeed,
            controller: this.controller as Object as never
          })
            .width('100%')
            .height('100%')
            .controls(true)
            .autoPlay(true)
            .loop(false)
            .objectFit(ImageFit.Contain)
            .onError(() => {
              this.errorMsg = '视频播放失败，可能是编码不支持或网络问题';
              this.videoSrc = '';
            })

          // 顶部操作层：倍速 + 画质 + 旋转（点击弹出对应菜单）
          Row({ space: 8 }) {
            this.FloatingButton(`${this.currentSpeed}x`, this.showSpeedMenu, () => this.toggleSpeedMenu())
            if (this.qualities.length > 1) {
              this.FloatingButton(this.qualityLabel(), this.showQualityMenu, () => this.toggleQualityMenu())
            }
            this.FloatingButton(this.rotateLabel(), false, () => this.cycleRotate())
            Blank()
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })
          .zIndex(20)

          // 倍速弹出菜单（紧贴顶部按钮下方）
          if (this.showSpeedMenu) {
            Column() {
              ForEach(SPEED_OPTIONS, (rate: number) => {
                Text(rate === 1.0 ? '1.0x' : `${rate}x`)
                  .fontSize(this.fontMeta)
                  .fontColor(this.currentSpeed === rate ? '#FFFFFF' : $r('app.color.text_primary'))
                  .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                  .backgroundColor(this.currentSpeed === rate ? $r('app.color.action_text') : 'rgba(0,0,0,0)')
                  .borderRadius(10)
                  .onClick(() => this.changeSpeed(rate))
                  .width('100%')
              }, (rate: number) => rate.toString())
            }
            .width(120)
            .padding(8)
            .backgroundColor('rgba(0,0,0,0.55)')
            .borderRadius(12)
            .position({ top: 48, left: 16 })
            .zIndex(30)
          }

          // 画质弹出菜单
          if (this.showQualityMenu) {
            Column() {
              ForEach(this.qualities, (opt: QualityOption, index: number) => {
                Text(opt.label)
                  .fontSize(this.fontMeta)
                  .fontColor(this.currentQuality === index ? '#FFFFFF' : $r('app.color.text_primary'))
                  .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                  .backgroundColor(this.currentQuality === index ? $r('app.color.action_text') : 'rgba(0,0,0,0)')
                  .borderRadius(10)
                  .onClick(() => this.selectQuality(index))
                  .width('100%')
              }, (opt: QualityOption) => opt.quality)
            }
            .width(140)
            .padding(8)
            .backgroundColor('rgba(0,0,0,0.55)')
            .borderRadius(12)
            .position({ top: 48, left: 116 })  // 紧贴第二个按钮下方
            .zIndex(30)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ bottom: this.bottomSafeAreaVp })
      } else {
        Column() {
          Text(this.errorMsg.length > 0 ? this.errorMsg : '无法播放该视频')
            .fontSize(this.fontSecondary)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
          Button('重试')
            .margin({ top: 16 })
            .onClick(() => this.loadVideo())
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 24, right: 24 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}