import { router } from '@kit.ArkUI';
import { FILTER_KEYS } from '../services/FilterSettingsRepository';
import { NumberSettingRow } from './FilterSettingRows';
import { ThemeColors } from '../services/ThemeColors';

// 卡片容器（与主设置页 SettingsCard 视觉一致）
@Component
struct SettingsCard {
  title: string = '';
  @BuilderParam content: () => void;
  @StorageLink('oledBlack') oledBlack: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;

  build() {
    Column({ space: 0 }) {
      Text(this.title)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 16, top: 12, bottom: 6 })
      Column({ space: 0 }) {
        this.content();
      }
      .width('100%')
      .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .border({ width: 1, color: $r('app.color.card_border') })
      .borderRadius(20)
    }
    .width('100%')
  }
}

@Entry
@Component
struct QualityFilterSettingsPage {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageLink('oledBlack') oledBlack: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;

  @Builder Header(title: string) {
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
    .padding({ top: this.topSafeAreaVp })
  }

  build() {
    Column() {
      this.Header('质量过滤规则')
      Scroll() {
        Column({ space: 16 }) {
          Text('总开关位于「推荐系统与内容过滤」；关闭后以下阈值均不生效。')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 16, right: 16 })

          SettingsCard({ title: '阈值设置' }) {
            NumberSettingRow({
              title: '回答赞数阈值',
              desc: '赞数低于此值的回答将被过滤（未关注作者）',
              prefKey: FILTER_KEYS.qualityVote,
              defValue: 10,
              minValue: 0,
              maxValue: 9999,
              showDivider: true
            })
            NumberSettingRow({
              title: '视频粉丝阈值',
              desc: '作者粉丝低于此值的视频将被过滤（未关注作者）',
              prefKey: FILTER_KEYS.qualityVideoFan,
              defValue: 50,
              minValue: 0,
              maxValue: 999999,
              showDivider: true
            })
            NumberSettingRow({
              title: '视频赞数阈值',
              desc: '赞数低于此值的视频将被过滤（未关注作者）',
              prefKey: FILTER_KEYS.qualityVideoVote,
              defValue: 20,
              minValue: 0,
              maxValue: 999999,
              showDivider: true
            })
            NumberSettingRow({
              title: '文章粉丝阈值',
              desc: '作者粉丝低于此值的文章将被过滤（未关注作者）',
              prefKey: FILTER_KEYS.qualityArticleFan,
              defValue: 50,
              minValue: 0,
              maxValue: 999999,
              showDivider: true
            })
            NumberSettingRow({
              title: '文章赞数阈值',
              desc: '赞数低于此值的文章将被过滤（未关注作者）',
              prefKey: FILTER_KEYS.qualityArticleVote,
              defValue: 20,
              minValue: 0,
              maxValue: 999999,
              showDivider: true
            })
            NumberSettingRow({
              title: '问题回答数阈值',
              desc: '回答数低于此值且关注数不足的问题将被过滤',
              prefKey: FILTER_KEYS.qualityQuestionAnswer,
              defValue: 5,
              minValue: 0,
              maxValue: 99999,
              showDivider: true
            })
            NumberSettingRow({
              title: '问题关注数阈值',
              desc: '关注数低于此值且回答数不足的问题将被过滤',
              prefKey: FILTER_KEYS.qualityQuestionFollower,
              defValue: 50,
              minValue: 0,
              maxValue: 999999,
              showDivider: false
            })
          }
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 32 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
