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
import { ZhihuMaterial } from '../services/ZhihuMaterial';
import { DesignMetrics, FONT_SCALE_KEY, SPACE_SCALE_KEY } from '../services/DesignMetrics';
import EntryAbility from '../entryability/EntryAbility';
import { PageHeader } from '../components/PageHeader';
import { SliderSettingRow, SettingsCard } from './FilterSettingRows';

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
  // 软尺寸：由 DesignMetrics 按「官方基线 × 用户倍率」算出后写入 AppStorage，
  // 默认值与迁移前完全一致，故视觉零变化；用户调整字号/密度后本页自动重排。
  @StorageProp('fontSymbol') private fontSymbol: string = '24fp';
  @StorageProp('fontCaption') private fontCaption: string = '12fp';
  @StorageProp('fontBody') private fontBody: string = '16fp';
  @StorageProp('fontSubhead') private fontSubhead: string = '18fp';
  @StorageProp('buttonRadius') private buttonRadius: number = 20;
  @StorageProp('spaceMd') private spaceMd: number = 12;
  @StorageProp('spaceLg') private spaceLg: number = 24;
  @StorageProp('pagePadding') private pagePadding: number = 20;

  @StorageProp('themeMode') private themeMode: AppearanceThemeMode = 'system';
  @StorageProp('materialLevel') private materialLevel: number = 10;
  @StorageProp('topSafeAreaVp') private topSafeAreaVp: number = 0;
  @StorageLink('oledBlack') private oledBlack: boolean = false;
  @StorageLink('isDark') private isDark: boolean = false;
  @StorageLink('showThumbnail') private showThumbnail: boolean = true;
  @StorageLink('showRefreshFab') private showRefreshFab: boolean = false;
  @StorageLink('autoHideRefreshFab') private autoHideRefreshFab: boolean = false;
  @StorageLink('buttonSkipAnswer') private buttonSkipAnswer: boolean = false;
  @StorageLink('autoHideSkipAnswerButton') private autoHideSkipAnswerButton: boolean = false;
  @StorageLink('lightCardWhite') private lightCardWhite: boolean = false;
  @StorageLink('enableHdsTopBar') private enableHdsTopBar: boolean = false;
  @State private topBarHeight: number = 0;
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
  private ThemeModeOption(mode: AppearanceThemeMode, label: string): void {
    Text(label)
      .fontSize(this.fontCaption)
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
      .fontSize(this.fontCaption)
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
    Stack({ alignContent: Alignment.Top }) {
      PageHeader({ title: '外观与阅读体验' })
        .zIndex(2)
        .onAreaChange((_old: Area, newValue: Area) => {
          if (newValue.height > 0) {
            this.topBarHeight = Number(newValue.height);
          }
        })

      Scroll() {
        Column({ space: 16 }) {
        // 沉浸光感
        SettingsCard({ title: '沉浸光感' }) {
          Column({ space: 4 }) {
            Text('控制沉浸光感材质的渲染强度')
              .fontSize(this.fontCaption)
              .lineHeight(18)
              .fontColor($r('app.color.text_secondary'))
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(MATERIAL_LEVEL_OPTIONS, (option: MaterialLevelOptionItem) => {
                this.MaterialLevelOption(option.level, option.label);
              }, (option: MaterialLevelOptionItem) => option.level.toString())
            }
            .margin({ top: 12 })
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 16, bottom: 16 })

          Divider()
            .color($r('app.color.card_border'))
            .padding({ left: 16, right: 16 })

          // 实验开关：沉浸光感顶栏（uiMaterial，对齐 PiliPlus 鸿蒙版）
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text('沉浸光感顶栏（实验）')
                .fontSize(this.fontBody)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(`使用鸿蒙沉浸光感材质渲染顶栏。仅鸿蒙7及以上支持，不支持则自动回退。当前设备：${ZhihuMaterial.uiImmersiveDescribe()}`)
                .fontSize(this.fontCaption)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.enableHdsTopBar })
              .selectedColor($r('app.color.brand_blue'))
              .onChange((v: boolean) => {
                this.enableHdsTopBar = v;
                AppearanceSettingsRepository.setEnableHdsTopBar(this.context(), v);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        }

        // 显示与颜色
        SettingsCard({ title: '显示与颜色' }) {
          Column({ space: 8 }) {
            Text('显示模式')
              .fontSize(this.fontBody)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(THEME_MODE_OPTIONS, (option: ThemeModeOptionItem) => {
                this.ThemeModeOption(option.mode, option.label);
              }, (option: ThemeModeOptionItem) => option.mode)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 16, bottom: 16 })

          Divider()
            .color($r('app.color.card_border'))
            .padding({ left: 16, right: 16 })

          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text('OLED 纯黑')
                .fontSize(this.fontBody)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('卡片与背景使用纯黑 #000000，OLED 屏幕更省电、对比更强')
                .fontSize(this.fontCaption)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.oledBlack })
              .selectedColor($r('app.color.brand_blue'))
              .onChange((v: boolean) => {
                this.oledBlack = v;
                AppearanceSettingsRepository.setOledBlack(this.context(), v);
                EntryAbility.applyWindowBackground();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })

          Divider()
            .color($r('app.color.card_border'))
            .padding({ left: 16, right: 16 })

          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text('浅色模式卡片纯白')
                .fontSize(this.fontBody)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('关闭时浅色模式卡片为淡蓝色，打开后改为纯白')
                .fontSize(this.fontCaption)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.lightCardWhite })
              .selectedColor($r('app.color.brand_blue'))
              .onChange((v: boolean) => {
                this.lightCardWhite = v;
                AppearanceSettingsRepository.setLightCardWhite(this.context(), v);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        }

        // 信息流控件
        SettingsCard({ title: '信息流控件' }) {
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text('显示 Feed 缩略图')
                .fontSize(this.fontBody)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.showThumbnail })
              .selectedColor($r('app.color.brand_blue'))
              .onChange((v: boolean) => {
                this.showThumbnail = v;
                AppearanceSettingsRepository.setShowThumbnail(this.context(), v);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })

          Divider()
            .color($r('app.color.card_border'))
            .padding({ left: 16, right: 16 })

          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text('刷新悬浮按钮')
                .fontSize(this.fontBody)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('在首页右下角显示悬浮刷新按钮')
                .fontSize(this.fontCaption)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.showRefreshFab })
              .selectedColor($r('app.color.brand_blue'))
              .onChange((v: boolean) => {
                this.showRefreshFab = v;
                AppearanceSettingsRepository.setShowRefreshFab(this.context(), v);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })

          if (this.showRefreshFab) {
            Row({ space: 8 }) {
              Column({ space: 4 }) {
                Text('滚动时自动隐藏刷新按钮')
                  .fontSize(this.fontBody)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text('上划时淡出「刷新」按钮，下划/置顶时淡入显示')
                  .fontSize(this.fontCaption)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Toggle({ type: ToggleType.Switch, isOn: this.autoHideRefreshFab })
                .selectedColor($r('app.color.brand_blue'))
                .onChange((v: boolean) => {
                  this.autoHideRefreshFab = v;
                  AppearanceSettingsRepository.setAutoHideRefreshFab(this.context(), v);
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })

            Divider()
              .color($r('app.color.card_border'))
              .padding({ left: 16, right: 16 })
          }

          Divider()
            .color($r('app.color.card_border'))
            .padding({ left: 16, right: 16 })

          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text('跳转下一个回答')
                .fontSize(this.fontBody)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('在回答页面显示快速跳转按钮')
                .fontSize(this.fontCaption)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.buttonSkipAnswer })
              .selectedColor($r('app.color.brand_blue'))
              .onChange((v: boolean) => {
                this.buttonSkipAnswer = v;
                AppearanceSettingsRepository.setButtonSkipAnswer(this.context(), v);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })

          if (this.buttonSkipAnswer) {
            Row({ space: 8 }) {
              Column({ space: 4 }) {
                Text('滚动时自动隐藏跳转按钮')
                  .fontSize(this.fontBody)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text('上划时淡出「下一个回答」按钮，下划时淡入显示')
                  .fontSize(this.fontCaption)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Toggle({ type: ToggleType.Switch, isOn: this.autoHideSkipAnswerButton })
                .selectedColor($r('app.color.brand_blue'))
                .onChange((v: boolean) => {
                  this.autoHideSkipAnswerButton = v;
                  AppearanceSettingsRepository.setAutoHideSkipAnswerButton(this.context(), v);
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          }
        }

        // 搜索界面
        SettingsCard({ title: '搜索界面' }) {
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text('搜索界面显示热搜')
                .fontSize(this.fontBody)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('在搜索界面空白时显示知乎热搜关键词')
                .fontSize(this.fontCaption)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.showSearchHotSearch })
              .selectedColor($r('app.color.brand_blue'))
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
                .fontSize(this.fontBody)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('搜索后保存关键词，可在搜索页点击再次搜索')
                .fontSize(this.fontCaption)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.showSearchHistory })
              .selectedColor($r('app.color.brand_blue'))
              .onChange((v: boolean) => {
                this.showSearchHistory = v;
                AppearanceSettingsRepository.setShowSearchHistory(this.context(), v);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        }

        // 界面缩放（作用于整个 App 的 UI 字号与间距密度，调用 DesignMetrics.set*Scale 实时重排）
        SettingsCard({ title: '界面缩放' }) {
          Column() {
            SliderSettingRow({
              title: '界面字号',
              desc: '调整整个 App 的界面字号大小',
              prefKey: FONT_SCALE_KEY,
              defValue: 100,
              minValue: 85,
              maxValue: 130,
              step: 1,
              divisor: 1,
              decimals: 0,
              suffix: '%',
              showDivider: true,
              onChange: (v: number) => {
                DesignMetrics.setFontScale(this.context(), v / 100);
              },
              onReset: () => {
                DesignMetrics.setFontScale(this.context(), 1);
              }
            })
            SliderSettingRow({
              title: '界面密度',
              desc: '调整整个 App 的间距与布局密度',
              prefKey: SPACE_SCALE_KEY,
              defValue: 100,
              minValue: 85,
              maxValue: 130,
              step: 1,
              divisor: 1,
              decimals: 0,
              suffix: '%',
              showDivider: false,
              onChange: (v: number) => {
                DesignMetrics.setSpaceScale(this.context(), v / 100);
              },
              onReset: () => {
                DesignMetrics.setSpaceScale(this.context(), 1);
              }
            })
          }
          .width('100%')
        }

        // 阅读体验
        SettingsCard({ title: '阅读体验' }) {
          Column() {
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
              divisor: 1,
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
