import { router } from '@kit.ArkUI';
import { bundleManager } from '@kit.AbilityKit';
import common from '@ohos.app.ability.common';
import { ThemeColors } from '../services/ThemeColors';
import { PageHeader } from '../components/PageHeader';
import { APP_VERSION_NAME } from '../generated/BuildInfo';

@Entry
@Component
struct AboutPage {
  // 软尺寸：由 DesignMetrics 按「官方基线 × 用户倍率」算出后写入 AppStorage，
  // 默认值与迁移前完全一致，故视觉零变化；用户调整字号/密度后本页自动重排。
  @StorageProp('fontSymbol') private fontSymbol: string = '24fp';
  @StorageProp('fontCaption') private fontCaption: string = '12fp';
  @StorageProp('fontMeta') private fontMeta: string = '13fp';
  @StorageProp('fontSecondary') private fontSecondary: string = '14fp';
  @StorageProp('fontBody') private fontBody: string = '16fp';
  @StorageProp('fontSubhead') private fontSubhead: string = '18fp';
  @StorageProp('fontHeading') private fontHeading: string = '20fp';
  @StorageProp('cardRadius') private cardRadius: number = 16;
  @StorageProp('cardPadding') private cardPadding: number = 16;

  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;
  @State private topBarHeight: number = 0;
  // 运行时从已安装包读取版本号（单一真源 app.json5）；读取失败回退编译期常量
  private appVersionName: string = APP_VERSION_NAME;

  aboutToAppear(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );
      const v = info.versionName;
      if (v !== undefined && v.length > 0) {
        this.appVersionName = v;
      }
    } catch (_) {
      // 读取失败则保留编译期常量 APP_VERSION_NAME
    }
  }

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


  build() {
    Stack({ alignContent: Alignment.Top }) {
      PageHeader({ title: '系统与更新' })
        .zIndex(2)
        .onAreaChange((_old: Area, newValue: Area) => {
          if (newValue.height > 0) {
            this.topBarHeight = Number(newValue.height);
          }
        })

      Scroll() {
        Column({ space: 12 }) {
          // App 信息卡
          Row({ space: 12 }) {
            Column() {
              Text('知')
                .fontSize(this.fontSubhead)
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
                .fontSize(this.fontBody)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(`版本号: ${this.appVersionName}`)
                .fontSize(this.fontMeta)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(this.cardPadding)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(this.cardRadius)

          // GitHub 项目地址
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text('GitHub 项目地址')
                .fontSize(this.fontBody)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('https://github.com/FlavG2/zhihu-plus-plus-harmonyos')
                .fontSize(this.fontMeta)
                .fontColor($r('app.color.action_text'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text('›')
              .fontSize(this.fontHeading)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .padding(this.cardPadding)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(this.cardRadius)
          .onClick(() => {
            this.openExternal('https://github.com/FlavG2/zhihu-plus-plus-harmonyos');
          })

          // 项目协议（不跳转）
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text('项目协议')
                .fontSize(this.fontBody)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('AGPL-3.0-only')
                .fontSize(this.fontMeta)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text('›')
              .fontSize(this.fontHeading)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .padding(this.cardPadding)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(this.cardRadius)

          // 开源许可
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text('开源许可')
                .fontSize(this.fontBody)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('查看第三方组件与系统 Kit 许可')
                .fontSize(this.fontMeta)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text('›')
              .fontSize(this.fontHeading)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .padding(this.cardPadding)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(this.cardRadius)
          .onClick(() => {
            this.openLicenses();
          })

          // AI 声明
          Column({ space: 4 }) {
            Text('AI 声明')
              .fontSize(this.fontSecondary)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text('本项目由 FlavG2 指挥 WorkBuddy、CodeX 等工具去进行移植，代码全部由工具完成，本人不参与写代码。')
              .fontSize(this.fontMeta)
              .lineHeight(20)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(this.cardPadding)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(this.cardRadius)

          // 底部免责声明
          Text('本软件仅供学习交流使用，应用内内容由知乎网站提供，著作权归其对应作者所有。')
            .fontSize(this.fontCaption)
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
      .width('100%')
      .height('100%')
      .padding({ top: this.topBarHeight })
      .scrollBar(BarState.On)
      .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
