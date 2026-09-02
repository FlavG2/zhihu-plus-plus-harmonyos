import { ThemeColors } from '../services/ThemeColors';
import { PageHeader } from '../components/PageHeader';
import { SettingsCard, BoolSettingRow } from './FilterSettingRows';

@Entry
@Component
struct NotificationSettings {
  @StorageLink('oledBlack') oledBlack: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;
  @State topBarHeight: number = 0;

  build() {
    Stack({ alignContent: Alignment.Top }) {
      PageHeader({ title: '通知设置' })
        .zIndex(2)
        .onAreaChange((_old: Area, newValue: Area) => {
          if (newValue.height > 0) {
            this.topBarHeight = Number(newValue.height);
          }
        })

      Scroll() {
        Column({ space: 16 }) {
          // 说明条：小字提示部分设置暂无效果（与下一个卡片的间距由 Column.space=16 承担）
          Row() {
            SymbolGlyph($r('sys.symbol.info_circle'))
              .fontSize(12)
              .fontColor([$r('app.color.text_secondary')])
              .margin({ right: 6 })
            Text('部分设置在当前版本暂无效果（仅预留配置入口）')
              .fontSize(12)
              .lineHeight(18)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 20, right: 20 })

          // 通用
          SettingsCard({ title: '通用' }) {
            Column({ space: 0 }) {
              BoolSettingRow({
                title: '接收新消息通知',
                desc: '关闭后将不再接收任何通知推送',
                prefKey: 'notif_master',
                defValue: true,
                showDivider: true
              })
              BoolSettingRow({
                title: '通知栏显示消息详情',
                desc: '关闭后通知栏仅显示「收到一条新消息」',
                prefKey: 'notif_show_detail',
                defValue: true,
                showDivider: true
              })
              BoolSettingRow({
                title: '自动标记已读',
                desc: '打开通知后自动将其标记为已读',
                prefKey: 'notif_auto_read',
                defValue: false,
                showDivider: false
              })
            }
            .width('100%')
          }

          // 通知分类（对齐安卓 4 分类：评论转发@ / 赞同喜欢 / 收藏了我 / 关注订阅）
          SettingsCard({ title: '通知分类' }) {
            Column({ space: 0 }) {
              BoolSettingRow({
                title: '评论转发@',
                desc: '有人评论、回复或 @ 你时通知',
                prefKey: 'notif_cat_comment',
                defValue: true,
                showDivider: true
              })
              BoolSettingRow({
                title: '赞同喜欢',
                desc: '你的内容被赞同或喜欢时通知',
                prefKey: 'notif_cat_like',
                defValue: true,
                showDivider: true
              })
              BoolSettingRow({
                title: '收藏了我',
                desc: '你的内容被收藏时通知',
                prefKey: 'notif_cat_favlist_me',
                defValue: true,
                showDivider: true
              })
              BoolSettingRow({
                title: '关注订阅',
                desc: '有人关注你或订阅话题更新时通知',
                prefKey: 'notif_cat_follow',
                defValue: true,
                showDivider: false
              })
            }
            .width('100%')
          }

          // 提醒方式
          SettingsCard({ title: '提醒方式' }) {
            Column({ space: 0 }) {
              BoolSettingRow({
                title: '声音',
                desc: '通知到达时播放提示音',
                prefKey: 'notif_sound',
                defValue: true,
                showDivider: true
              })
              BoolSettingRow({
                title: '振动',
                desc: '通知到达时振动提醒',
                prefKey: 'notif_vibrate',
                defValue: true,
                showDivider: true
              })
              BoolSettingRow({
                title: '静默勿扰',
                desc: '开启后通知仅写入收件箱，不弹窗不响铃',
                prefKey: 'notif_dnd',
                defValue: false,
                showDivider: false
              })
            }
            .width('100%')
          }
        }
        .width('100%')
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
