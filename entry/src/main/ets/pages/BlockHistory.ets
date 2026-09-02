import { router } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { BlockHistoryRepository, BlockedFeedRecord } from '../services/BlockHistoryRepository';
import { ThemeColors } from '../services/ThemeColors';
import { PageHeader } from '../components/PageHeader';

@Entry
@Component
struct BlockHistoryPage {
  @State records: BlockedFeedRecord[] = [];
  @State topBarHeight: number = 0;
  @StorageLink('oledBlack') oledBlack: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageProp('fontBodySm') fontBodySm: string = '15fp';
  @StorageProp('fontCaption') fontCaption: string = '12fp';

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  aboutToAppear(): void {
    this.records = BlockHistoryRepository.getRecords(this.context());
  }


  private formatTime(time: number): string {
    const d = new Date(time);
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getMonth() + 1}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      PageHeader({ title: '屏蔽记录' })
        .zIndex(2)
        .onAreaChange((_old: Area, newValue: Area) => {
          if (newValue.height > 0) {
            this.topBarHeight = Number(newValue.height);
          }
        })
      if (this.records.length === 0) {
        Column() {
          Text('暂无屏蔽记录')
            .fontSize(this.fontBodySm)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.topBarHeight })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column({ space: 12 }) {
            ForEach(this.records, (rec: BlockedFeedRecord) => {
              Column({ space: 6 }) {
                Row() {
                  Text(rec.title)
                    .fontSize(this.fontBodySm)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(rec.reason)
                    .fontSize(this.fontCaption)
                    .fontColor($r('app.color.action_text'))
                    .padding({ left: 8 })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                Text(this.formatTime(rec.time))
                  .fontSize(this.fontCaption)
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
        .width('100%')
        .height('100%')
        .padding({ top: this.topBarHeight })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
