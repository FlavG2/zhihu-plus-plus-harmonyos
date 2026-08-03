const OLED_BLACK: string = '#000000';
const OLED_FEED_BG: string = '#0F141A';

/**
 * OLED 黑主题颜色解析层。
 *
 * 方案 B（用户确认）：
 * - 文章页（article）：真实黑色主体，页面底色翻成纯黑 #000000；
 * - 首页 / 问题页（feed）：卡片是绝对主体，卡片翻成纯黑 #000000，页面底色保留深蓝灰 #0F141A 作间隙；
 * - 仅在 `oledBlack && isDark` 时覆盖，其余情况回落到资源色（与原行为一致）。
 *
 * 每个页面把自身的 @StorageLink `oledBlack` / `isDark` 透传进来，
 * 这样开关变化会触发组件重渲染、重新走这里取值。
 */
export class ThemeColors {
  /**
   * 全局卡片底色（feed / 问题 / 回答 / 文章 / 想法 共用）：
   * - OLED 且深色：纯黑 #000000
   * - 浅色模式：由开关 `lightCardWhite` 决定，默认浅蓝（#F5F8FF），打开后纯白（#FFFFFF）
   * - 深色非 OLED：回落资源色
   */
  static cardBackground(oledBlack: boolean, isDark: boolean): ResourceColor {
    if (oledBlack && isDark) {
      return OLED_BLACK;
    }
    if (!isDark) {
      const white: boolean = AppStorage.get('lightCardWhite') as boolean;
      return white ? $r('app.color.card_background') : $r('app.color.answer_card_background');
    }
    return $r('app.color.card_background');
  }

  /** 首页 / 问题页根底色：OLED 下保留深蓝灰 #0F141A（与深色模式原值一致） */
  static feedBackground(oledBlack: boolean, isDark: boolean): ResourceColor {
    return (oledBlack && isDark) ? OLED_FEED_BG : $r('app.color.page_background');
  }

  /** 文章页根底色：OLED 下纯黑 */
  static articleBackground(oledBlack: boolean, isDark: boolean): ResourceColor {
    return (oledBlack && isDark) ? OLED_BLACK : $r('app.color.page_background');
  }

  /** 底栏 / 启动窗底色：OLED 下保留深蓝灰，与 feed 间隙同色 */
  static chromeBackground(oledBlack: boolean, isDark: boolean): ResourceColor {
    return (oledBlack && isDark) ? OLED_FEED_BG : $r('app.color.tab_bar_background');
  }
}
