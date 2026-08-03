import common from '@ohos.app.ability.common';
import { FilterSettingsRepository, FILTER_KEYS } from '../services/FilterSettingsRepository';
import { AppearanceSettingsRepository } from '../services/AppearanceSettingsRepository';

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
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          if (this.desc.length > 0) {
            Text(this.desc)
              .fontSize(12)
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
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          if (this.desc.length > 0) {
            Text(this.desc)
              .fontSize(12)
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
  @State value: number = 100;
  private ctx!: common.Context;

  aboutToAppear(): void {
    this.ctx = getContext(this) as common.Context;
    this.value = AppearanceSettingsRepository.getInt(this.ctx, this.prefKey, this.defValue);
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(this.title)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          if (this.desc.length > 0) {
            Text(this.desc)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.formatValue())
          .fontSize(13)
          .fontColor($r('app.color.action_text'))
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
