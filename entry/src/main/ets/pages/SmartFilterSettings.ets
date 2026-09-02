import { router, promptAction } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import { FILTER_KEYS, FilterSettingsRepository, FilterMode } from '../services/FilterSettingsRepository';
import { NumberSettingRow, BoolSettingRow, ModeSelectRow } from './FilterSettingRows';
import { ThemeColors } from '../services/ThemeColors';
import { PageHeader } from '../components/PageHeader';

@Component
struct SettingsCard {
  title: string = '';
  @BuilderParam content: () => void;
  @StorageLink('oledBlack') oledBlack: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageProp('fontMeta') fontMeta: string = '13fp';

  build() {
    Column({ space: 0 }) {
      Text(this.title)
        .fontSize(this.fontMeta)
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
  @State topBarHeight: number = 0;
  @StorageProp('fontMeta') fontMeta: string = '13fp';
  @StorageProp('fontCaption') fontCaption: string = '12fp';
  @State unfollowedMode: FilterMode = 'off';
  @State followedMode: FilterMode = 'off';
  private ctx!: common.Context;

  aboutToAppear(): void {
    this.ctx = getContext(this) as common.Context;
    this.unfollowedMode = FilterSettingsRepository.getSmartMode(this.ctx, false);
    this.followedMode = FilterSettingsRepository.getSmartMode(this.ctx, true);
  }

  private onModeChange(followed: boolean, mode: FilterMode): void {
    FilterSettingsRepository.setSmartMode(this.ctx, followed, mode);
    if (followed) {
      this.followedMode = mode;
    } else {
      this.unfollowedMode = mode;
    }
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
    Stack({ alignContent: Alignment.Top }) {
      PageHeader({ title: '推荐次数过滤' })
        .zIndex(2)
        .onAreaChange((_old: Area, newValue: Area) => {
          if (newValue.height > 0) {
            this.topBarHeight = Number(newValue.height);
          }
        })
      Scroll() {
        Column({ space: 16 }) {
          SettingsCard({ title: '推荐次数标记' }) {
            BoolSettingRow({
              title: '显示推荐次数角标',
              desc: '在卡片标题末尾标注该内容被推荐的次数',
              prefKey: FILTER_KEYS.showRecommendBadge,
              defValue: true,
              showDivider: false
            })
          }

          SettingsCard({ title: '规则（未关注作者）' }) {
            ModeSelectRow({
              title: '模式',
              mode: this.unfollowedMode,
              onChange: (m: FilterMode) => this.onModeChange(false, m)
            })
            NumberSettingRow({
              title: '展示达 N 次后屏蔽',
              desc: '未关注作者的内容展示 N 次后自动屏蔽',
              prefKey: FILTER_KEYS.smartViewThresholdUnfollowed,
              defValue: 2,
              minValue: 1,
              maxValue: 99,
              showDivider: true
            })
            BoolSettingRow({
              title: '过滤低质推广内容',
              desc: '含“小时前 / 分钟前 / 浏览”等字样',
              prefKey: FILTER_KEYS.smartLowQualityUnfollowed,
              defValue: true,
              showDivider: false
            })
          }

          SettingsCard({ title: '规则（已关注作者）' }) {
            ModeSelectRow({
              title: '模式',
              mode: this.followedMode,
              onChange: (m: FilterMode) => this.onModeChange(true, m)
            })
            NumberSettingRow({
              title: '展示达 N 次后屏蔽',
              desc: '已关注作者的内容展示 N 次后自动屏蔽',
              prefKey: FILTER_KEYS.smartViewThresholdFollowed,
              defValue: 2,
              minValue: 1,
              maxValue: 99,
              showDivider: true
            })
            BoolSettingRow({
              title: '过滤低质推广内容',
              desc: '含“小时前 / 分钟前 / 浏览”等字样',
              prefKey: FILTER_KEYS.smartLowQualityFollowed,
              defValue: true,
              showDivider: false
            })
          }

          SettingsCard({ title: '记录管理' }) {
            NumberSettingRow({
              title: '记录过期天数',
              desc: '浏览记录超过此天数自动清理（清理后重新推送、计数归 1）',
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
      .width('100%')
      .height('100%')
      .padding({ top: this.topBarHeight })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
