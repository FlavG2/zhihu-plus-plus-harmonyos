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

  /**
   * 悬浮胶囊（评论输入栏等）底色：刻意比页面 / 卡片底色亮一档，制造「浮起」层级。
   * - 浅色：纯白 #FFFFFF（页面底色 #F1F3F5，明显更白）
   * - 深色非 OLED：#242A33（比卡片 #18212B 亮，浮于深蓝灰页面之上）
   * - 深色 OLED：#1A1F26（比纯黑页面 #000000 明显浮起）
   * 配合半透明描边 + 投影使用，悬浮感最强。
   */
  static floatBarBackground(oledBlack: boolean, isDark: boolean): ResourceColor {
    // B 方案：半透明 + 磨砂（backgroundBlurStyle）实现沉浸式玻璃浮层。
    // 透明度保持较高（0.85），确保「明显浮起」的层次不被稀释；磨砂感由组件上的 backgroundBlurStyle 提供。
    if (!isDark) {
      return 'rgba(255, 255, 255, 0.85)';
    }
    return oledBlack ? 'rgba(26, 31, 38, 0.85)' : 'rgba(36, 42, 51, 0.85)';
  }

  /** 底栏 / 启动窗底色：OLED 下纯黑（与顶栏等结构面统一），非 OLED 回落资源色 */
  static chromeBackground(oledBlack: boolean, isDark: boolean): ResourceColor {
    return (oledBlack && isDark) ? OLED_BLACK : $r('app.color.tab_bar_background');
  }

  /**
   * 窗口底色（字符串，供 setWindowBackgroundColor 使用）：消除深色模式下路由跳转的「闪白」。
   * - 浅色模式：回落 page_background 浅蓝 #F5F7FB
   * - 深色非 OLED：深蓝灰 #0F141A
   * - 深色 OLED：纯黑 #000000
   * 注意：setWindowBackgroundColor 只吃字符串，不能传 Resource，故这里直接返回十六进制。
   */
  static windowBackground(oledBlack: boolean, isDark: boolean): string {
    if (!isDark) {
      return '#F1F3F5';
    }
    return oledBlack ? OLED_BLACK : OLED_FEED_BG;
  }

  /**
   * 通用 OLED 黑覆盖：深色 + OLED 开时返回纯黑 #000000，否则回落传入的原色（保留各自浅/深色值）。
   * 用于此前未走 OLED 的结构面——顶栏 / 操作栏 / 药丸 / 输入框，统一覆盖范围；
   * feed 页底间隙例外，由 feedBackground 单独保留 #0F141A（保持卡片层次）。
   * 调用示例：ThemeColors.oledBlack(this.oledBlack, this.isDark, $r('app.color.action_background'))
   */
  static oledBlack(oledBlack: boolean, isDark: boolean, fallback: ResourceColor): ResourceColor {
    return (oledBlack && isDark) ? OLED_BLACK : fallback;
  }
}
