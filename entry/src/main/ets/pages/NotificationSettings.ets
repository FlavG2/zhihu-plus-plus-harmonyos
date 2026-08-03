import { router } from '@kit.ArkUI';
import { ThemeColors } from '../services/ThemeColors';

@Entry
@Component
struct NotificationSettings {
  @StorageLink('oledBlack') oledBlack: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(26)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            router.back({ url: '' });
          })
          .padding({ left: 8, right: 4 })

        Text('通知设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 8, right: 8, top: this.topSafeAreaVp + 12, bottom: 12 })

      Column() {
        Text('通知设置')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Text('通知分类、未读角标、自动标记已读等开关将在此处提供（开发中）。')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8 })
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .borderRadius(16)
      .margin({ left: 16, right: 16, top: 8 })

      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
  }
}
