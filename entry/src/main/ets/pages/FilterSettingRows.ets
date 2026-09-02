import common from '@ohos.app.ability.common';
import { FilterSettingsRepository, FILTER_KEYS, FilterMode } from '../services/FilterSettingsRepository';
import { AppearanceSettingsRepository } from '../services/AppearanceSettingsRepository';
import { ThemeColors } from '../services/ThemeColors';

// 过滤模式选择行：关闭 / 遮罩 / 隐藏 三段胶囊按钮。纯展示组件，
// 由父页面负责读取初始 mode 与持久化（onChange 回调）。质量 / 智能共 4 节复用。
@Component
export struct ModeSelectRow {
  @Prop title: string = '模式';
  @Prop mode: FilterMode = 'off';
  onChange: (mode: FilterMode) => void = () => {};
  @StorageLink('oledBlack') oledBlack: boolean = false;
  @StorageLink('isDark') isDark: boolean = false;
  @StorageProp('fontSecondary') private fontSecondary: string = '14fp';
  @StorageProp('fontMeta') private fontMeta: string = '13fp';
  @StorageProp('fontCaption') private fontCaption: string = '12fp';

  @Builder
  modeButton(value: FilterMode, label: string) {
    Button(label, { type: ButtonType.Capsule })
      .layoutWeight(1)
      .height(40)
      .backgroundColor(this.mode === value ? $r('app.color.brand_blue') : ThemeColors.cardBackground(this.oledBlack, this.isDark))
      .fontColor(this.mode === value ? '#FFFFFF' : $r('app.color.text_primary'))
      .fontSize(this.fontSecondary)
      .onClick(() => {
        this.onChange(value);
      })
  }

  build() {
    Column({ space: 4 }) {
      Text(this.title)
        .fontSize(this.fontSecondary)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 16, right: 16, top: 14 })
      Row({ space: 8 }) {
        this.modeButton('off', '关闭')
        this.modeButton('rules', '遮罩')
        this.modeButton('hide', '隐藏')
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 14 })
    }
    .width('100%')
  }
}

// 数值设置行：标题（+描述）+ 右侧数字输入框，改动即持久化
@Component
export struct NumberSettingRow {
  @Prop title: string = '';
  @Prop desc: string = '';
  @Prop prefKey: string = '';
  @Prop defValue: number = 0;
  @Prop minValue: number = 0;
  @Prop maxValue: number = 999999;
  @Prop showDivider: boolean = false;
  @State input: string = '';
  @StorageProp('fontSecondary') private fontSecondary: string = '14fp';
  @StorageProp('fontCaption') private fontCaption: string = '12fp';
  @StorageProp('fontMeta') private fontMeta: string = '13fp';
  private ctx!: common.Context;

  aboutToAppear(): void {
    this.ctx = getContext(this) as common.Context;
    this.input = String(FilterSettingsRepository.getInt(this.ctx, this.prefKey, this.defValue));
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(this.title)
            .fontSize(this.fontSecondary)
            .fontColor($r('app.color.text_primary'))
          if (this.desc.length > 0) {
            Text(this.desc)
              .fontSize(this.fontCaption)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        TextInput({ text: this.input, placeholder: String(this.defValue) })
          .type(InputType.Number)
          .width(64)
          .padding({ left: 8, right: 8 })
          .textAlign(TextAlign.End)
          .onChange((v: string) => {
            this.input = v;
            let n = parseInt(v, 10);
            if (!Number.isFinite(n)) {
              return;
            }
            if (n < this.minValue) {
              n = this.minValue;
            }
            if (n > this.maxValue) {
              n = this.maxValue;
              this.input = String(n);
            }
            FilterSettingsRepository.setInt(this.ctx, this.prefKey, n);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })

      if (this.showDivider) {
        Divider()
          .color($r('app.color.card_border'))
          .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
  }
}

// 布尔设置行：标题（+描述）+ 右侧开关，改动即持久化
@Component
export struct BoolSettingRow {
  @Prop title: string = '';
  @Prop desc: string = '';
  @Prop prefKey: string = '';
  @Prop defValue: boolean = true;
  @Prop showDivider: boolean = false;
  @State on: boolean = true;
  @StorageProp('fontSecondary') private fontSecondary: string = '14fp';
  @StorageProp('fontCaption') private fontCaption: string = '12fp';
  @StorageProp('fontMeta') private fontMeta: string = '13fp';
  private ctx!: common.Context;

  aboutToAppear(): void {
    this.ctx = getContext(this) as common.Context;
    this.on = FilterSettingsRepository.getBool(this.ctx, this.prefKey, this.defValue);
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(this.title)
            .fontSize(this.fontSecondary)
            .fontColor($r('app.color.text_primary'))
          if (this.desc.length > 0) {
            Text(this.desc)
              .fontSize(this.fontCaption)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.on })
          .selectedColor($r('app.color.action_text'))
          .onChange((v: boolean) => {
            this.on = v;
            FilterSettingsRepository.setBool(this.ctx, this.prefKey, v);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })

      if (this.showDivider) {
        Divider()
          .color($r('app.color.card_border'))
          .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
  }
}

// 滑块设置行：标题（+描述）+ 右侧实时值 + 底部滑块，改动即持久化（整数存储）
@Component
export struct SliderSettingRow {
  @Prop title: string = '';
  @Prop desc: string = '';
  @Prop prefKey: string = '';
  @Prop defValue: number = 100;
  @Prop minValue: number = 0;
  @Prop maxValue: number = 200;
  @Prop step: number = 1;
  @Prop divisor: number = 1;
  @Prop decimals: number = 0;
  @Prop suffix: string = '';
  @Prop showDivider: boolean = false;
  onChange: (value: number) => void = () => {};
  onReset: () => void = () => {};
  @State value: number = 100;
  @StorageProp('fontSecondary') private fontSecondary: string = '14fp';
  @StorageProp('fontCaption') private fontCaption: string = '12fp';
  @StorageProp('fontMeta') private fontMeta: string = '13fp';
  private ctx!: common.Context;

  aboutToAppear(): void {
    this.ctx = getContext(this) as common.Context;
    this.value = AppearanceSettingsRepository.getInt(this.ctx, this.prefKey, this.defValue);
  }

  private handleReset(): void {
    this.value = this.defValue;
    AppearanceSettingsRepository.setInt(this.ctx, this.prefKey, this.defValue);
    this.onReset?.();
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(this.title)
            .fontSize(this.fontSecondary)
            .fontColor($r('app.color.text_primary'))
          if (this.desc.length > 0) {
            Text(this.desc)
              .fontSize(this.fontCaption)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: 12 }) {
          Text(this.formatValue())
            .fontSize(this.fontMeta)
            .fontColor($r('app.color.action_text'))

          Text('重置')
            .fontSize(this.fontMeta)
            .fontColor($r('app.color.action_text'))
            .onClick(() => {
              this.handleReset();
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 6 })

      Slider({
        value: this.value,
        min: this.minValue,
        max: this.maxValue,
        step: this.step,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .padding({ left: 16, right: 16 })
        .blockColor($r('app.color.action_text'))
        .trackColor($r('app.color.card_border'))
        .selectedColor($r('app.color.action_text'))
        .onChange((v: number) => {
          this.value = v;
          AppearanceSettingsRepository.setInt(this.ctx, this.prefKey, v);
          this.onChange?.(v);
        })

      if (this.showDivider) {
        Divider()
          .color($r('app.color.card_border'))
          .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
  }

  private formatValue(): string {
    const real = this.value / this.divisor;
    return `${real.toFixed(this.decimals)}${this.suffix}`;
  }
}

// 通用卡片容器：小灰标题 + 圆角白卡，作为各设置分组的外层
@Component
export struct SettingsCard {
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
