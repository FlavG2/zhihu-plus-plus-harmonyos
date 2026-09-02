import { router } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { FILTER_KEYS, FilterSettingsRepository, FilterMode } from '../services/FilterSettingsRepository';
import { NumberSettingRow, ModeSelectRow } from './FilterSettingRows';
import { ThemeColors } from '../services/ThemeColors';
import { PageHeader } from '../components/PageHeader';

// 卡片容器（与主设置页 SettingsCard 视觉一致）
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
struct QualityFilterSettingsPage {
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageLink('oledBlack') oledBlack: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;
  @State topBarHeight: number = 0;
  @StorageProp('fontCaption') private fontCaption: string = '12fp';
  @State unfollowedMode: FilterMode = 'off';
  @State followedMode: FilterMode = 'off';
  private ctx!: common.Context;

  aboutToAppear(): void {
    this.ctx = getContext(this) as common.Context;
    this.unfollowedMode = FilterSettingsRepository.getQualityMode(this.ctx, false);
    this.followedMode = FilterSettingsRepository.getQualityMode(this.ctx, true);
  }

  private onModeChange(followed: boolean, mode: FilterMode): void {
    FilterSettingsRepository.setQualityMode(this.ctx, followed, mode);
    if (followed) {
      this.followedMode = mode;
    } else {
      this.unfollowedMode = mode;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      PageHeader({ title: '质量过滤模式' })
        .zIndex(2)
        .onAreaChange((_old: Area, newValue: Area) => {
          if (newValue.height > 0) {
            this.topBarHeight = Number(newValue.height);
          }
        })
      Scroll() {
        Column({ space: 16 }) {
          Text('未关注 / 已关注 作者分别设置；「关闭」则该节完全不生效。阈值统一默认 0（不触发过滤）。')
            .fontSize(this.fontCaption)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 16, right: 16 })

          SettingsCard({ title: '质量阈值（未关注作者）' }) {
            ModeSelectRow({
              title: '模式',
              mode: this.unfollowedMode,
              onChange: (m: FilterMode) => this.onModeChange(false, m)
            })
            NumberSettingRow({
              title: '回答赞数阈值',
              desc: '赞数低于此值的回答将被过滤',
              prefKey: FILTER_KEYS.qualityVoteUnfollowed,
              defValue: 0,
              minValue: 0,
              maxValue: 9999,
              showDivider: true
            })
            NumberSettingRow({
              title: '视频粉丝阈值',
              desc: '作者粉丝低于此值的视频将被过滤',
              prefKey: FILTER_KEYS.qualityVideoFanUnfollowed,
              defValue: 0,
              minValue: 0,
              maxValue: 999999,
              showDivider: true
            })
            NumberSettingRow({
              title: '视频赞数阈值',
              desc: '赞数低于此值的视频将被过滤',
              prefKey: FILTER_KEYS.qualityVideoVoteUnfollowed,
              defValue: 0,
              minValue: 0,
              maxValue: 999999,
              showDivider: true
            })
            NumberSettingRow({
              title: '文章粉丝阈值',
              desc: '作者粉丝低于此值的文章将被过滤',
              prefKey: FILTER_KEYS.qualityArticleFanUnfollowed,
              defValue: 0,
              minValue: 0,
              maxValue: 999999,
              showDivider: true
            })
            NumberSettingRow({
              title: '文章赞数阈值',
              desc: '赞数低于此值的文章将被过滤',
              prefKey: FILTER_KEYS.qualityArticleVoteUnfollowed,
              defValue: 0,
              minValue: 0,
              maxValue: 999999,
              showDivider: true
            })
            NumberSettingRow({
              title: '问题回答数阈值',
              desc: '回答数低于此值且关注数不足的问题将被过滤',
              prefKey: FILTER_KEYS.qualityQuestionAnswerUnfollowed,
              defValue: 0,
              minValue: 0,
              maxValue: 99999,
              showDivider: true
            })
            NumberSettingRow({
              title: '问题关注数阈值',
              desc: '关注数低于此值且回答数不足的问题将被过滤',
              prefKey: FILTER_KEYS.qualityQuestionFollowerUnfollowed,
              defValue: 0,
              minValue: 0,
              maxValue: 999999,
              showDivider: false
            })
          }

          SettingsCard({ title: '质量阈值（已关注作者）' }) {
            ModeSelectRow({
              title: '模式',
              mode: this.followedMode,
              onChange: (m: FilterMode) => this.onModeChange(true, m)
            })
            NumberSettingRow({
              title: '回答赞数阈值',
              desc: '赞数低于此值的回答将被过滤',
              prefKey: FILTER_KEYS.qualityVoteFollowed,
              defValue: 0,
              minValue: 0,
              maxValue: 9999,
              showDivider: true
            })
            NumberSettingRow({
              title: '视频粉丝阈值',
              desc: '作者粉丝低于此值的视频将被过滤',
              prefKey: FILTER_KEYS.qualityVideoFanFollowed,
              defValue: 0,
              minValue: 0,
              maxValue: 999999,
              showDivider: true
            })
            NumberSettingRow({
              title: '视频赞数阈值',
              desc: '赞数低于此值的视频将被过滤',
              prefKey: FILTER_KEYS.qualityVideoVoteFollowed,
              defValue: 0,
              minValue: 0,
              maxValue: 999999,
              showDivider: true
            })
            NumberSettingRow({
              title: '文章粉丝阈值',
              desc: '作者粉丝低于此值的文章将被过滤',
              prefKey: FILTER_KEYS.qualityArticleFanFollowed,
              defValue: 0,
              minValue: 0,
              maxValue: 999999,
              showDivider: true
            })
            NumberSettingRow({
              title: '文章赞数阈值',
              desc: '赞数低于此值的文章将被过滤',
              prefKey: FILTER_KEYS.qualityArticleVoteFollowed,
              defValue: 0,
              minValue: 0,
              maxValue: 999999,
              showDivider: true
            })
            NumberSettingRow({
              title: '问题回答数阈值',
              desc: '回答数低于此值且关注数不足的问题将被过滤',
              prefKey: FILTER_KEYS.qualityQuestionAnswerFollowed,
              defValue: 0,
              minValue: 0,
              maxValue: 99999,
              showDivider: true
            })
            NumberSettingRow({
              title: '问题关注数阈值',
              desc: '关注数低于此值且回答数不足的问题将被过滤',
              prefKey: FILTER_KEYS.qualityQuestionFollowerFollowed,
              defValue: 0,
              minValue: 0,
              maxValue: 999999,
              showDivider: false
            })
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
