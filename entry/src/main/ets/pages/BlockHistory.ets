import { router } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { BlockHistoryRepository, BlockedFeedRecord } from '../services/BlockHistoryRepository';
import { ThemeColors } from '../services/ThemeColors';

@Entry
@Component
struct BlockHistoryPage {
  @State records: BlockedFeedRecord[] = [];
  @StorageLink('oledBlack') oledBlack: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  aboutToAppear(): void {
    this.records = BlockHistoryRepository.getRecords(this.context());
  }

  @Builder
  Header(title: string) {
    Row() {
      Text('‹')
        .fontSize(28)
        .fontColor($r('app.color.text_primary'))
        .onClick(() => router.back({ url: '' }))
        .padding({ left: 16, right: 8 })
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(56)
    .alignItems(VerticalAlign.Center)
  }

  private formatTime(time: number): string {
    const d = new Date(time);
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getMonth() + 1}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  build() {
    Column() {
      this.Header('屏蔽记录')
      if (this.records.length === 0) {
        Column() {
          Text('暂无屏蔽记录')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column({ space: 12 }) {
            ForEach(this.records, (rec: BlockedFeedRecord) => {
              Column({ space: 6 }) {
                Row() {
                  Text(rec.title)
                    .fontSize(15)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(rec.reason)
                    .fontSize(12)
                    .fontColor($r('app.color.action_text'))
                    .padding({ left: 8 })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                Text(this.formatTime(rec.time))
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
              .border({ width: 1, color: $r('app.color.card_border') })
              .borderRadius(16)
            }, (rec: BlockedFeedRecord) => rec.id)
          }
          .padding({ left: 16, right: 16, top: 8, bottom: 32 })
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
  }
}
