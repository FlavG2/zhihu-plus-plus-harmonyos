import { router } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import {
  AppearanceSettingsRepository,
  APPEARANCE_KEYS,
  AppearanceThemeMode,
  MATERIAL_LEVEL_EXQUISITE,
  MATERIAL_LEVEL_GENTLE,
  MATERIAL_LEVEL_SMOOTH,
  MATERIAL_LEVEL_ADAPTIVE
} from '../services/AppearanceSettingsRepository';
import { ThemeColors } from '../services/ThemeColors';
import { SliderSettingRow } from './FilterSettingRows';

interface ThemeModeOptionItem {
  readonly mode: AppearanceThemeMode;
  readonly label: string;
}
interface MaterialLevelOptionItem {
  readonly level: number;
  readonly label: string;
}

// 与首页设置保持一致的选项（此处自包含，避免跨页依赖）
const THEME_MODE_OPTIONS: ThemeModeOptionItem[] = [
  { mode: 'light', label: '日间' },
  { mode: 'dark', label: '黑暗' },
  { mode: 'system', label: '跟随系统' }
];
const MATERIAL_LEVEL_OPTIONS: MaterialLevelOptionItem[] = [
  { level: MATERIAL_LEVEL_ADAPTIVE, label: '自适应' },
  { level: MATERIAL_LEVEL_SMOOTH, label: '平滑' },
  { level: MATERIAL_LEVEL_GENTLE, label: '柔和' },
  { level: MATERIAL_LEVEL_EXQUISITE, label: '精致' }
];

@Entry
@Component
struct AppearanceSettingsPage {
  @StorageProp('themeMode') private themeMode: AppearanceThemeMode = 'system';
  @StorageProp('materialLevel') private materialLevel: number = 10;
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;
  @StorageLink('showThumbnail') private showThumbnail: boolean = true;
  @StorageLink('showRefreshFab') private showRefreshFab: boolean = false;
  @StorageLink('lightCardWhite') private lightCardWhite: boolean = false;
  @StorageLink('showSearchHotSearch') private showSearchHotSearch: boolean = true;
  @StorageLink('showSearchHistory') private showSearchHistory: boolean = true;

  private context(): common.Context {
    return getContext(this) as common.Context;
  }

  private applyThemeMode(mode: AppearanceThemeMode): void {
    AppearanceSettingsRepository.setThemeMode(this.context(), mode);
  }

  private applyMaterialLevel(level: number): void {
    AppearanceSettingsRepository.setMaterialLevel(this.context(), level);
  }

  @Builder
  private Header(): void {
    Row() {
      Text('‹')
        .fontSize(28)
        .fontColor($r('app.color.text_primary'))
        .onClick(() => router.back({ url: '' }))
        .padding({ left: 16, right: 8 })
      Text('外观与阅读体验')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(56)
    .alignItems(VerticalAlign.Center)
    .padding({ top: this.topSafeAreaVp })
  }

  @Builder
  private ThemeModeOption(mode: AppearanceThemeMode, label: string): void {
    Text(label)
      .fontSize(12)
      .fontWeight(this.themeMode === mode ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.themeMode === mode ? $r('app.color.action_text') : $r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor(this.themeMode === mode ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .border({
        width: 1,
        color: this.themeMode === mode ? $r('app.color.tab_selected_border') : $r('app.color.card_border')
      })
      .borderRadius(14)
      .onClick(() => {
        this.applyThemeMode(mode);
      })
  }

  @Builder
  private MaterialLevelOption(level: number, label: string): void {
    Text(label)
      .fontSize(12)
      .fontWeight(this.materialLevel === level ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.materialLevel === level ? $r('app.color.action_text') : $r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor(this.materialLevel === level ? $r('app.color.action_background') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .border({
        width: 1,
        color: this.materialLevel === level ? $r('app.color.tab_selected_border') : $r('app.color.card_border')
      })
      .borderRadius(14)
      .onClick(() => {
        this.applyMaterialLevel(level);
      })
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          this.Header()

          // 沉浸光感（置顶，单独被外框包裹）
          Column({ space: 2 }) {
            Column() {
              Column({ space: 4 }) {
                Text('沉浸光感')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text('控制沉浸光感材质的渲染强度')
                  .fontSize(12)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)

              Row({ space: 6 }) {
                ForEach(MATERIAL_LEVEL_OPTIONS, (option: MaterialLevelOptionItem) => {
                  this.MaterialLevelOption(option.level, option.label);
                }, (option: MaterialLevelOptionItem) => option.level.toString())
              }
              .margin({ top: 12 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
            .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({ width: 1, color: $r('app.color.card_border') })
            .borderRadius(20)
          }
          .width('100%')
          .padding(6)
          .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(24)

          // 显示与颜色：显示模式 + OLED 纯黑 + 浅色模式卡片纯白（同一外框）
          Column({ space: 2 }) {
            Column() {
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text('显示模式')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Row({ space: 6 }) {
                  ForEach(THEME_MODE_OPTIONS, (option: ThemeModeOptionItem) => {
                    this.ThemeModeOption(option.mode, option.label);
                  }, (option: ThemeModeOptionItem) => option.mode)
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
              .padding({ top: 16, bottom: 4 })

              Divider()
                .color($r('app.color.card_border'))

              Row({ space: 8 }) {
                Column({ space: 4 }) {
                  Text('OLED 纯黑')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Text('卡片与背景使用纯黑 #000000，OLED 屏幕更省电、对比更强')
                    .fontSize(12)
                    .lineHeight(18)
                    .fontColor($r('app.color.text_secondary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Toggle({ type: ToggleType.Switch, isOn: this.oledBlack })
                  .selectedColor($r('app.color.action_text'))
                  .onChange((v: boolean) => {
                    this.oledBlack = v;
                    AppearanceSettingsRepository.setOledBlack(this.context(), v);
                  })
              }
              .width('100%')
              .padding({ top: 14, bottom: 14 })

              Divider()
                .color($r('app.color.card_border'))

              Row({ space: 8 }) {
                Column({ space: 4 }) {
                  Text('浅色模式卡片纯白')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Text('关闭时浅色模式卡片为淡蓝色，打开后改为纯白')
                    .fontSize(12)
                    .lineHeight(18)
                    .fontColor($r('app.color.text_secondary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Toggle({ type: ToggleType.Switch, isOn: this.lightCardWhite })
                  .selectedColor($r('app.color.action_text'))
                  .onChange((v: boolean) => {
                    this.lightCardWhite = v;
                    AppearanceSettingsRepository.setLightCardWhite(this.context(), v);
                  })
              }
              .width('100%')
              .padding({ top: 14, bottom: 14 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
            .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({ width: 1, color: $r('app.color.card_border') })
            .borderRadius(20)
          }
          .width('100%')
          .padding(6)
          .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(24)

          // 信息流控件：显示 Feed 缩略图 + 刷新悬浮按钮（同一外框）
          Column({ space: 2 }) {
            Column() {
              Row({ space: 8 }) {
                Column({ space: 4 }) {
                  Text('显示 Feed 缩略图')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Toggle({ type: ToggleType.Switch, isOn: this.showThumbnail })
                  .selectedColor($r('app.color.action_text'))
                  .onChange((v: boolean) => {
                    this.showThumbnail = v;
                    AppearanceSettingsRepository.setShowThumbnail(this.context(), v);
                  })
              }
              .width('100%')
              .padding({ top: 14, bottom: 14 })

              Divider()
                .color($r('app.color.card_border'))

              Row({ space: 8 }) {
                Column({ space: 4 }) {
                  Text('刷新悬浮按钮')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Text('在首页右下角显示悬浮刷新按钮')
                    .fontSize(12)
                    .lineHeight(18)
                    .fontColor($r('app.color.text_secondary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Toggle({ type: ToggleType.Switch, isOn: this.showRefreshFab })
                  .selectedColor($r('app.color.action_text'))
                  .onChange((v: boolean) => {
                    this.showRefreshFab = v;
                    AppearanceSettingsRepository.setShowRefreshFab(this.context(), v);
                  })
              }
              .width('100%')
              .padding({ top: 14, bottom: 14 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
            .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({ width: 1, color: $r('app.color.card_border') })
            .borderRadius(20)
          }
          .width('100%')
          .padding(6)
          .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(24)

          // 搜索界面开关
            Column({ space: 2 }) {
              Row({ space: 8 }) {
                Column({ space: 4 }) {
                  Text('搜索界面显示热搜')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Text('在搜索界面空白时显示知乎热搜关键词')
                    .fontSize(12)
                    .lineHeight(18)
                    .fontColor($r('app.color.text_secondary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Toggle({ type: ToggleType.Switch, isOn: this.showSearchHotSearch })
                  .selectedColor($r('app.color.action_text'))
                  .onChange((v: boolean) => {
                    this.showSearchHotSearch = v;
                    AppearanceSettingsRepository.setShowSearchHotSearch(this.context(), v);
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })

              Divider()
                .color($r('app.color.card_border'))
                .padding({ left: 16, right: 16 })

              Row({ space: 8 }) {
                Column({ space: 4 }) {
                  Text('记录并显示搜索历史')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Text('搜索后保存关键词，可在搜索页点击再次搜索')
                    .fontSize(12)
                    .lineHeight(18)
                    .fontColor($r('app.color.text_secondary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Toggle({ type: ToggleType.Switch, isOn: this.showSearchHistory })
                  .selectedColor($r('app.color.action_text'))
                  .onChange((v: boolean) => {
                    this.showSearchHistory = v;
                    AppearanceSettingsRepository.setShowSearchHistory(this.context(), v);
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            }
            .width('100%')
            .padding(6)
            .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
            .border({ width: 1, color: $r('app.color.card_border') })
            .borderRadius(24)

          // 阅读体验（字号 / 行高 / 段间距）
          Column({ space: 2 }) {
            SliderSettingRow({
              title: '正文字号',
              desc: '调整文章正文字号大小',
              prefKey: APPEARANCE_KEYS.readerFontScale,
              defValue: 100,
              minValue: 80,
              maxValue: 150,
              step: 1,
              divisor: 1,
              decimals: 0,
              suffix: '%',
              showDivider: true
            })
            SliderSettingRow({
              title: '行高',
              desc: '调整正文行与行之间的间距',
              prefKey: APPEARANCE_KEYS.readerLineHeight,
              defValue: 160,
              minValue: 120,
              maxValue: 200,
              step: 1,
              divisor: 100,
              decimals: 2,
              suffix: '',
              showDivider: true
            })
            SliderSettingRow({
              title: '段间距',
              desc: '调整正文段落之间的间距',
              prefKey: APPEARANCE_KEYS.readerParaSpacing,
              defValue: 100,
              minValue: 50,
              maxValue: 200,
              step: 1,
              divisor: 1,
              decimals: 0,
              suffix: '%',
              showDivider: false
            })
          }
          .width('100%')
          .padding(6)
          .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
          .border({ width: 1, color: $r('app.color.card_border') })
          .borderRadius(24)

          Column()
            .height(20)
            .width('100%')
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 12, bottom: 8 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.On)
      .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.feedBackground(this.oledBlack, this.isDark))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
