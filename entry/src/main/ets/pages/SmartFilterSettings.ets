import { router, promptAction } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import { FILTER_KEYS } from '../services/FilterSettingsRepository';
import { NumberSettingRow, BoolSettingRow } from './FilterSettingRows';
import { ThemeColors } from '../services/ThemeColors';

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
struct SmartFilterSettingsPage {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageLink('oledBlack') oledBlack: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;
  private ctx!: common.Context;

  aboutToAppear(): void {
    this.ctx = getContext(this) as common.Context;
  }

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

  private clearViewRecords(): void {
    try {
      const store = preferences.getPreferencesSync(this.ctx, { name: 'zhihu_filter' });
      store.deleteSync(FILTER_KEYS.smartViewRecords);
      store.flushSync();
    } catch (_e) {
      // 忽略
    }
    promptAction.showToast({ message: '已清除浏览记录', duration: 2000 });
  }

  build() {
    Column() {
      this.Header('智能内容过滤')
      Scroll() {
        Column({ space: 16 }) {
          Text('总开关位于「推荐系统与内容过滤」；关闭后以下设置均不生效。')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 16, right: 16 })

          SettingsCard({ title: '规则' }) {
            NumberSettingRow({
              title: '展示达 N 次后屏蔽',
              desc: '未关注作者的内容展示 N 次后自动屏蔽',
              prefKey: FILTER_KEYS.smartViewThreshold,
              defValue: 2,
              minValue: 1,
              maxValue: 99,
              showDivider: true
            })
            BoolSettingRow({
              title: '过滤低质推广内容',
              desc: '含“小时前 / 分钟前 / 浏览”等字样',
              prefKey: FILTER_KEYS.smartLowQuality,
              defValue: true,
              showDivider: false
            })
          }

          SettingsCard({ title: '推荐次数标记' }) {
            BoolSettingRow({
              title: '显示推荐次数角标',
              desc: '在卡片标题末尾标注该内容被推荐的次数',
              prefKey: FILTER_KEYS.showRecommendBadge,
              defValue: true,
              showDivider: false
            })
          }

          SettingsCard({ title: '记录管理' }) {
            NumberSettingRow({
              title: '记录过期天数',
              desc: '浏览记录超过此天数自动清理',
              prefKey: FILTER_KEYS.smartExpireDays,
              defValue: 7,
              minValue: 1,
              maxValue: 365,
              showDivider: true
            })
            NumberSettingRow({
              title: '最大记录条数',
              desc: '记录超过此数量时全量清理',
              prefKey: FILTER_KEYS.smartMaxRecords,
              defValue: 10000,
              minValue: 1,
              maxValue: 999999,
              showDivider: false
            })

            Column({ space: 0 }) {
              Button('清除浏览记录')
                .width('100%')
                .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
                .fontColor('#D85A30')
                .onClick(() => this.clearViewRecords())
              Divider()
                .color($r('app.color.card_border'))
                .padding({ left: 16, right: 16, top: 12 })
            }
            .padding({ left: 16, right: 16, top: 12, bottom: 4 })
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
