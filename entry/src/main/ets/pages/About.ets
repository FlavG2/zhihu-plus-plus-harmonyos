import { router } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { ThemeColors } from '../services/ThemeColors';
import { APP_VERSION_NAME } from '../generated/BuildInfo';

@Entry
@Component
struct AboutPage {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;

  private openLicenses(): void {
    router.pushUrl({ url: 'pages/Licenses' });
  }

  /** 用系统浏览器打开外部链接 */
  private openExternal(url: string): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.startAbility({
        action: 'ohos.want.action.viewData',
        uri: url
      });
    } catch (_) {
      // 系统浏览器不可用时静默忽略
    }
  }

  @Builder
  private Header(): void {
    Row() {
      Text('‹')
        .fontSize(28)
        .fontColor($r('app.color.text_primary'))
        .onClick(() => router.back())
        .padding({ left: 16, right: 8 })
      Text('系统与更新')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(56)
    .alignItems(VerticalAlign.Center)
    .padding({ top: this.topSafeAreaVp })
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }

  build() {
    Column() {
      this.Header()

      Scroll() {
        Column({ space: 12 }) {
          // App 信息卡
          Row({ space: 12 }) {
            Column() {
              Text('知')
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFFFF')
            }
            .width(44)
            .height(44)
            .borderRadius(12)
            .backgroundColor($r('app.color.action_text'))
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)

            Column({ space: 4 }) {
              Text('知乎++')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(`版本号: ${APP_VERSION_NAME}`)
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(16)

          // GitHub 项目地址
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text('GitHub 项目地址')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('https://github.com/FlavG2/zhihu-plus-plus-harmonyos')
                .fontSize(13)
                .fontColor($r('app.color.action_text'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text('›')
              .fontSize(20)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .padding(16)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(16)
          .onClick(() => {
            this.openExternal('https://github.com/FlavG2/zhihu-plus-plus-harmonyos');
          })

          // 项目协议（不跳转）
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text('项目协议')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('AGPL-3.0-only')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text('›')
              .fontSize(20)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .padding(16)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(16)

          // 开源许可
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text('开源许可')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('查看第三方组件与系统 Kit 许可')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text('›')
              .fontSize(20)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .padding(16)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(16)
          .onClick(() => {
            this.openLicenses();
          })

          // AI 声明
          Column({ space: 4 }) {
            Text('AI 声明')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text('本项目由 FlavG2 指挥 WorkBuddy、CodeX 等工具去进行移植，代码全部由工具完成，本人不参与写代码。')
              .fontSize(13)
              .lineHeight(20)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(16)

          // 底部免责声明
          Text('本软件仅供学习交流使用，应用内内容由知乎网站提供，著作权归其对应作者所有。')
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .padding({ left: 4, right: 4, bottom: 8 })

          Column()
            .height(20)
            .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.On)
      .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
