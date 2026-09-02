import { router } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { ThemeColors } from '../services/ThemeColors';
import { PageHeader } from '../components/PageHeader';

@Entry
@Component
struct LicensesPage {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;
  @StorageProp('fontSecondary') fontSecondary: string = '14fp';
  @StorageProp('fontMeta') fontMeta: string = '13fp';
  @StorageProp('fontCaption') fontCaption: string = '12fp';
  @State topBarHeight: number = 0;

  private readonly kits: string[] = [
    'ArkUI',
    'ArkWeb',
    'AbilityKit',
    'ArkData',
    'NetworkKit',
    'CoreFileKit',
    'ShareKit',
    'BasicServicesKit',
    'PerformanceAnalysisKit',
    'UIDesignKit'
  ];


  @Builder
  private SectionTitle(title: string): void {
    Text(title)
      .fontSize(this.fontSecondary)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
      .margin({ bottom: 8 })
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
      PageHeader({ title: '开源许可' })
        .zIndex(2)
        .onAreaChange((_old: Area, newValue: Area) => {
          if (newValue.height > 0) {
            this.topBarHeight = Number(newValue.height);
          }
        })

      Scroll() {
        Column({ space: 16 }) {
          // 区块一：本应用协议
          Column({ space: 8 }) {
            this.SectionTitle('本应用协议')
            Text('知乎++（鸿蒙版）基于 AGPL-3.0-only 协议。')
              .fontSize(this.fontMeta)
              .lineHeight(20)
              .fontColor($r('app.color.text_secondary'))
            Column({ space: 4 }) {
              Text('· 本项目：FlavG2/zhihu-plus-plus-harmonyos')
                .fontSize(this.fontMeta)
                .lineHeight(20)
                .fontColor($r('app.color.text_secondary'))
              Text('https://github.com/FlavG2/zhihu-plus-plus-harmonyos')
                .fontSize(this.fontMeta)
                .lineHeight(20)
                .fontColor($r('app.color.action_text'))
                .onClick(() => this.openExternal('https://github.com/FlavG2/zhihu-plus-plus-harmonyos'))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(16)

          // 区块二：上游致谢
          Column({ space: 8 }) {
            this.SectionTitle('上游致谢')
            Column({ space: 4 }) {
              Text('· 安卓原项目：zly2006/zhihu-plus-plus')
                .fontSize(this.fontMeta)
                .lineHeight(20)
                .fontColor($r('app.color.text_secondary'))
              Text('https://github.com/zly2006/zhihu-plus-plus')
                .fontSize(this.fontMeta)
                .lineHeight(20)
                .fontColor($r('app.color.action_text'))
                .onClick(() => this.openExternal('https://github.com/zly2006/zhihu-plus-plus'))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column({ space: 4 }) {
              Text('· 鸿蒙基底项目：xlwreally/zhihu-plus-plus-next')
                .fontSize(this.fontMeta)
                .lineHeight(20)
                .fontColor($r('app.color.text_secondary'))
              Text('https://github.com/xlwreally/zhihu-plus-plus-next (Commit 86db2b6)')
                .fontSize(this.fontMeta)
                .lineHeight(20)
                .fontColor($r('app.color.action_text'))
                .onClick(() => this.openExternal('https://github.com/xlwreally/zhihu-plus-plus-next'))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .margin({ top: 6 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(16)

          // 区块三：系统 Kit 清单
          Column({ space: 8 }) {
            this.SectionTitle('系统 Kit 清单')
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
              ForEach(this.kits, (kit: string) => {
                Text(kit)
                  .fontSize(this.fontCaption)
                  .fontColor($r('app.color.text_secondary'))
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .margin({ right: 8, bottom: 8 })
                  .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
                  .border({ width: 1, color: $r('app.color.card_border') })
                  .borderRadius(8)
              }, (kit: string) => kit)
            }
            .width('100%')
            Text('随 HarmonyOS 操作系统分发，非应用再分发。')
              .fontSize(this.fontCaption)
              .lineHeight(18)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(16)

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
