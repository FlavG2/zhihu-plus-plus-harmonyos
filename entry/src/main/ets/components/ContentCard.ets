import { ThemeColors } from '../services/ThemeColors';

/**
 * 统一内容卡片。
 *
 * 要点（吸收鸿蒙官方/参考项目的通用做法，用咱们自己的命名落地）：
 * 1. 用 Button(type: Normal, stateEffect: true) 作为外层容器 —— 免费拿到统一的按压态，
 *    不用每个页面自己写点击高亮，全 app 手感一致。
 * 2. 内边距 / 圆角走 DesignMetrics 的软尺寸（@StorageProp 消费），
 *    用户在设置里调整密度后这里会跟着变，无需改代码。
 * 3. 背景色走 ThemeColors.cardBackground，自动适配深色 / OLED 纯黑。
 *
 * 注：@StorageProp 的键名需与 DesignMetrics.METRICS_KEYS 中的值一致
 * （装饰器参数用字符串字面量，确保编译期可解析）。
 */
@Component
export struct ContentCard {
  @BuilderParam content: () => void = this.emptyContent;
  @StorageProp('cardPadding') cardPadding: number = 16;
  @StorageProp('cardRadius') cardRadius: number = 16;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('oledBlack') oledBlack: boolean = false;
  onTap: () => void = () => {
  };

  @Builder
  emptyContent() {
    Column() {
    }
  }

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column() {
        this.content();
      }
      .width('100%')
    }
    .width('100%')
    .padding(this.cardPadding)
    .border({ width: 1, color: $r('app.color.card_border'), radius: this.cardRadius })
    .backgroundColor(ThemeColors.cardBackground(this.oledBlack, this.isDark))
    .onClick(() => {
      this.onTap();
    })
  }
}
