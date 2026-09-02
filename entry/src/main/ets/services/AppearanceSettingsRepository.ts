import common from '@ohos.app.ability.common';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const APPEARANCE_PREFERENCES_FILE: string = 'zhihu_appearance';
const THEME_MODE_KEY: string = 'theme_mode';
const THEME_MODE_STORAGE_KEY: string = 'themeMode';
const AMBIENT_BLUR_KEY: string = 'ambient_blur';
const AMBIENT_BLUR_STORAGE_KEY: string = 'ambientBlur';
const MATERIAL_LEVEL_KEY: string = 'material_level';
const MATERIAL_LEVEL_STORAGE_KEY: string = 'materialLevel';

// OLED 纯黑 / 信息流开关 / 阅读体验（字号、行高、段间距均以整数存储，使用时再除以 100）
const OLED_BLACK_KEY: string = 'oled_black';
const OLED_BLACK_STORAGE_KEY: string = 'oledBlack';
const SHOW_THUMBNAIL_KEY: string = 'show_thumbnail';
const SHOW_THUMBNAIL_STORAGE_KEY: string = 'showThumbnail';
const SHOW_REFRESH_FAB_KEY: string = 'show_refresh_fab';
const SHOW_REFRESH_FAB_STORAGE_KEY: string = 'showRefreshFab';
// 回答页「跳转下一个回答」可拖动按钮（对齐安卓 buttonSkipAnswer / autoHideSkipAnswerButton，默认开）
const BUTTON_SKIP_ANSWER_KEY: string = 'button_skip_answer';
const BUTTON_SKIP_ANSWER_STORAGE_KEY: string = 'buttonSkipAnswer';
const AUTO_HIDE_SKIP_ANSWER_KEY: string = 'auto_hide_skip_answer_button';
const AUTO_HIDE_SKIP_ANSWER_STORAGE_KEY: string = 'autoHideSkipAnswerButton';
const AUTO_HIDE_REFRESH_FAB_KEY: string = 'auto_hide_refresh_fab';
const AUTO_HIDE_REFRESH_FAB_STORAGE_KEY: string = 'autoHideRefreshFab';
const LIGHT_CARD_WHITE_KEY: string = 'light_card_white';
const LIGHT_CARD_WHITE_STORAGE_KEY: string = 'lightCardWhite';
// 实验开关：沉浸光感顶栏（uiMaterial / @kit.ArkUI，仅鸿蒙7+/API26+ 支持，不支持时自动回退到原玻璃顶栏）
const ENABLE_HDS_TOP_BAR_KEY: string = 'enable_hds_top_bar';
const ENABLE_HDS_TOP_BAR_STORAGE_KEY: string = 'enableHdsTopBar';
// 搜索界面：热搜显示开关 / 搜索历史记录开关（key 与安卓 SettingsStore 完全一致，便于跨平台同步）
const SHOW_SEARCH_HOT_SEARCH_KEY: string = 'showSearchHotSearch';
const SHOW_SEARCH_HOT_SEARCH_STORAGE_KEY: string = 'showSearchHotSearch';
const SHOW_SEARCH_HISTORY_KEY: string = 'showSearchHistory';
const SHOW_SEARCH_HISTORY_STORAGE_KEY: string = 'showSearchHistory';
const READER_FONT_SCALE_KEY: string = 'reader_font_scale';
const READER_LINE_HEIGHT_KEY: string = 'reader_line_height';
const READER_PARA_SPACING_KEY: string = 'reader_para_spacing';
const READER_FONT_SCALE_STORAGE_KEY: string = 'readerFontScale';
const READER_LINE_HEIGHT_STORAGE_KEY: string = 'readerLineHeight';
const READER_PARA_SPACING_STORAGE_KEY: string = 'readerParaSpacing';
const IS_DARK_STORAGE_KEY: string = 'isDark';

export type AppearanceThemeMode = 'light' | 'dark' | 'system';
const DEFAULT_THEME_MODE: AppearanceThemeMode = 'system';

// 沉浸光感强度：关闭 / 自适应（系统默认）/ 标准 / 浓郁
export type AmbientBlurIntensity = 'off' | 'adaptive' | 'standard' | 'rich';
const DEFAULT_AMBIENT_BLUR: AmbientBlurIntensity = 'adaptive';

// HDS 沉浸光感材质强度：0=EXQUISITE 精致 / 1=GENTLE 柔和 / 2=SMOOTH 平滑 / 10=ADAPTIVE 自适应
export const MATERIAL_LEVEL_EXQUISITE: number = 0;
export const MATERIAL_LEVEL_GENTLE: number = 1;
export const MATERIAL_LEVEL_SMOOTH: number = 2;
export const MATERIAL_LEVEL_ADAPTIVE: number = 10;
export const DEFAULT_MATERIAL_LEVEL: number = MATERIAL_LEVEL_ADAPTIVE;

export class AppearanceSettingsRepository {
  private static initialized: boolean = false;
  private static themeMode: AppearanceThemeMode = DEFAULT_THEME_MODE;
  private static ambientBlur: AmbientBlurIntensity = DEFAULT_AMBIENT_BLUR;
  private static materialLevel: number = DEFAULT_MATERIAL_LEVEL;
  private static oledBlack: boolean = false;
  private static showThumbnail: boolean = true;
  private static showRefreshFab: boolean = false;
  private static autoHideRefreshFab: boolean = false;
  private static buttonSkipAnswer: boolean = true;
  private static autoHideSkipAnswerButton: boolean = true;
  private static lightCardWhite: boolean = false;
  private static enableHdsTopBar: boolean = false;
  private static showSearchHotSearch: boolean = true;
  private static showSearchHistory: boolean = true;
  private static readerFontScale: number = 100;
  private static readerLineHeight: number = 160;
  private static readerParaSpacing: number = 100;

  private static preferences(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, {
      name: APPEARANCE_PREFERENCES_FILE
    });
  }

  private static updateAppStorage(themeMode: AppearanceThemeMode): void {
    if (!AppStorage.set<AppearanceThemeMode>(THEME_MODE_STORAGE_KEY, themeMode)) {
      AppStorage.setOrCreate<AppearanceThemeMode>(THEME_MODE_STORAGE_KEY, themeMode);
    }
  }

  private static updateAmbientAppStorage(value: AmbientBlurIntensity): void {
    if (!AppStorage.set<AmbientBlurIntensity>(AMBIENT_BLUR_STORAGE_KEY, value)) {
      AppStorage.setOrCreate<AmbientBlurIntensity>(AMBIENT_BLUR_STORAGE_KEY, value);
    }
  }

  private static updateMaterialAppStorage(value: number): void {
    if (!AppStorage.set<number>(MATERIAL_LEVEL_STORAGE_KEY, value)) {
      AppStorage.setOrCreate<number>(MATERIAL_LEVEL_STORAGE_KEY, value);
    }
  }

  private static updateOledBlackAppStorage(value: boolean): void {
    if (!AppStorage.set<boolean>(OLED_BLACK_STORAGE_KEY, value)) {
      AppStorage.setOrCreate<boolean>(OLED_BLACK_STORAGE_KEY, value);
    }
  }

  private static updateShowThumbnailAppStorage(value: boolean): void {
    if (!AppStorage.set<boolean>(SHOW_THUMBNAIL_STORAGE_KEY, value)) {
      AppStorage.setOrCreate<boolean>(SHOW_THUMBNAIL_STORAGE_KEY, value);
    }
  }

  private static updateShowRefreshFabAppStorage(value: boolean): void {
    if (!AppStorage.set<boolean>(SHOW_REFRESH_FAB_STORAGE_KEY, value)) {
      AppStorage.setOrCreate<boolean>(SHOW_REFRESH_FAB_STORAGE_KEY, value);
    }
  }

  private static updateButtonSkipAnswerAppStorage(value: boolean): void {
    if (!AppStorage.set<boolean>(BUTTON_SKIP_ANSWER_STORAGE_KEY, value)) {
      AppStorage.setOrCreate<boolean>(BUTTON_SKIP_ANSWER_STORAGE_KEY, value);
    }
  }

  private static updateAutoHideSkipAnswerAppStorage(value: boolean): void {
    if (!AppStorage.set<boolean>(AUTO_HIDE_SKIP_ANSWER_STORAGE_KEY, value)) {
      AppStorage.setOrCreate<boolean>(AUTO_HIDE_SKIP_ANSWER_STORAGE_KEY, value);
    }
  }

  private static updateAutoHideRefreshFabAppStorage(value: boolean): void {
    if (!AppStorage.set<boolean>(AUTO_HIDE_REFRESH_FAB_STORAGE_KEY, value)) {
      AppStorage.setOrCreate<boolean>(AUTO_HIDE_REFRESH_FAB_STORAGE_KEY, value);
    }
  }

  private static updateLightCardWhiteAppStorage(value: boolean): void {
    if (!AppStorage.set<boolean>(LIGHT_CARD_WHITE_STORAGE_KEY, value)) {
      AppStorage.setOrCreate<boolean>(LIGHT_CARD_WHITE_STORAGE_KEY, value);
    }
  }

  private static updateEnableHdsTopBarAppStorage(value: boolean): void {
    if (!AppStorage.set<boolean>(ENABLE_HDS_TOP_BAR_STORAGE_KEY, value)) {
      AppStorage.setOrCreate<boolean>(ENABLE_HDS_TOP_BAR_STORAGE_KEY, value);
    }
  }

  private static updateShowSearchHotSearchAppStorage(value: boolean): void {
    if (!AppStorage.set<boolean>(SHOW_SEARCH_HOT_SEARCH_STORAGE_KEY, value)) {
      AppStorage.setOrCreate<boolean>(SHOW_SEARCH_HOT_SEARCH_STORAGE_KEY, value);
    }
  }

  private static updateShowSearchHistoryAppStorage(value: boolean): void {
    if (!AppStorage.set<boolean>(SHOW_SEARCH_HISTORY_STORAGE_KEY, value)) {
      AppStorage.setOrCreate<boolean>(SHOW_SEARCH_HISTORY_STORAGE_KEY, value);
    }
  }

  // 阅读体验（字号/行高/段间距）以整数存储，暴露给 UI 时除以 100 得到真实倍率
  private static updateReaderAppStorage(key: string, rawValue: number): void {
    let storageKey: string = '';
    if (key === READER_FONT_SCALE_KEY) {
      storageKey = READER_FONT_SCALE_STORAGE_KEY;
    } else if (key === READER_LINE_HEIGHT_KEY) {
      storageKey = READER_LINE_HEIGHT_STORAGE_KEY;
    } else if (key === READER_PARA_SPACING_KEY) {
      storageKey = READER_PARA_SPACING_STORAGE_KEY;
    } else {
      return;
    }
    const divided: number = rawValue / 100;
    if (!AppStorage.set<number>(storageKey, divided)) {
      AppStorage.setOrCreate<number>(storageKey, divided);
    }
  }

  private static updateIsDarkAppStorage(context: common.Context, themeMode: AppearanceThemeMode): void {
    const isDark = AppearanceSettingsRepository.computeIsDark(context, themeMode);
    if (!AppStorage.set<boolean>(IS_DARK_STORAGE_KEY, isDark)) {
      AppStorage.setOrCreate<boolean>(IS_DARK_STORAGE_KEY, isDark);
    }
  }

  /**
   * 计算当前是否为深色模式（避免与 ZhihuWebBridge 形成循环依赖，这里内联一份同逻辑）。
   * 注意：resolveZhihuThemeMode 中 `colorMode === 0` 判定为深色，与此保持一致。
   */
  private static computeIsDark(context: common.Context, themeMode: AppearanceThemeMode): boolean {
    if (themeMode === 'dark') {
      return true;
    }
    if (themeMode === 'light') {
      return false;
    }
    try {
      const configuration = context.resourceManager.getConfigurationSync();
      // resourceManager.ColorMode.DARK 的值为 0，故与 0 比较即判定深色
      return configuration.colorMode === 0;
    } catch (_) {
      return false;
    }
  }

  private static normalizeThemeMode(raw: Object | string): AppearanceThemeMode {
    if (typeof raw === 'string' && (raw === 'light' || raw === 'dark' || raw === 'system')) {
      return raw as AppearanceThemeMode;
    }
    return DEFAULT_THEME_MODE;
  }

  private static normalizeAmbientBlur(raw: Object | string): AmbientBlurIntensity {
    if (typeof raw === 'string'
      && (raw === 'off' || raw === 'adaptive' || raw === 'standard' || raw === 'rich')) {
      return raw as AmbientBlurIntensity;
    }
    return DEFAULT_AMBIENT_BLUR;
  }

  private static applyColorMode(context: common.Context, themeMode: AppearanceThemeMode): void {
    let mode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (themeMode === 'light') {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else if (themeMode === 'dark') {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    context.getApplicationContext().setColorMode(mode);
  }

  static load(context: common.Context): AppearanceThemeMode {
    if (!this.initialized) {
      const store = this.preferences(context);
      this.themeMode = this.normalizeThemeMode(store.getSync(THEME_MODE_KEY, DEFAULT_THEME_MODE));
      this.ambientBlur = this.normalizeAmbientBlur(store.getSync(AMBIENT_BLUR_KEY, DEFAULT_AMBIENT_BLUR));
      this.materialLevel = (store.getSync(MATERIAL_LEVEL_KEY, DEFAULT_MATERIAL_LEVEL)) as number;
      this.oledBlack = (store.getSync(OLED_BLACK_KEY, false)) as boolean;
      this.showThumbnail = (store.getSync(SHOW_THUMBNAIL_KEY, true)) as boolean;
      this.showRefreshFab = (store.getSync(SHOW_REFRESH_FAB_KEY, false)) as boolean;
      this.autoHideRefreshFab = (store.getSync(AUTO_HIDE_REFRESH_FAB_KEY, false)) as boolean;
      this.buttonSkipAnswer = (store.getSync(BUTTON_SKIP_ANSWER_KEY, true)) as boolean;
      this.autoHideSkipAnswerButton = (store.getSync(AUTO_HIDE_SKIP_ANSWER_KEY, true)) as boolean;
      this.lightCardWhite = (store.getSync(LIGHT_CARD_WHITE_KEY, false)) as boolean;
      this.enableHdsTopBar = (store.getSync(ENABLE_HDS_TOP_BAR_KEY, false)) as boolean;
      this.showSearchHotSearch = (store.getSync(SHOW_SEARCH_HOT_SEARCH_KEY, true)) as boolean;
      this.showSearchHistory = (store.getSync(SHOW_SEARCH_HISTORY_KEY, true)) as boolean;
      this.readerFontScale = (store.getSync(READER_FONT_SCALE_KEY, 100)) as number;
      this.readerLineHeight = (store.getSync(READER_LINE_HEIGHT_KEY, 160)) as number;
      this.readerParaSpacing = (store.getSync(READER_PARA_SPACING_KEY, 100)) as number;
      this.updateReaderAppStorage(READER_FONT_SCALE_KEY, this.readerFontScale);
      this.updateReaderAppStorage(READER_LINE_HEIGHT_KEY, this.readerLineHeight);
      this.updateReaderAppStorage(READER_PARA_SPACING_KEY, this.readerParaSpacing);
      this.initialized = true;
    }
    this.updateAppStorage(this.themeMode);
    this.updateAmbientAppStorage(this.ambientBlur);
    this.updateMaterialAppStorage(this.materialLevel);
    this.updateOledBlackAppStorage(this.oledBlack);
    this.updateShowThumbnailAppStorage(this.showThumbnail);
    this.updateShowRefreshFabAppStorage(this.showRefreshFab);
    this.updateAutoHideRefreshFabAppStorage(this.autoHideRefreshFab);
    this.updateButtonSkipAnswerAppStorage(this.buttonSkipAnswer);
    this.updateAutoHideSkipAnswerAppStorage(this.autoHideSkipAnswerButton);
    this.updateLightCardWhiteAppStorage(this.lightCardWhite);
    this.updateEnableHdsTopBarAppStorage(this.enableHdsTopBar);
    this.updateShowSearchHotSearchAppStorage(this.showSearchHotSearch);
    this.updateShowSearchHistoryAppStorage(this.showSearchHistory);
    this.applyColorMode(context, this.themeMode);
    this.updateIsDarkAppStorage(context, this.themeMode);
    return this.themeMode;
  }

  static currentThemeMode(context?: common.Context): AppearanceThemeMode {
    if (context !== undefined) {
      this.load(context);
    }
    return this.themeMode;
  }

  // 仅读取已加载的主题模式，绝不触发 load/applyColorMode/setColorMode。
  // 供 onConfigurationUpdate 等会被 setColorMode 回调触发的路径使用，避免无限递归栈溢出。
  static getThemeMode(): AppearanceThemeMode {
    return this.themeMode;
  }

  static currentAmbientBlur(context?: common.Context): AmbientBlurIntensity {
    if (context !== undefined) {
      this.load(context);
    }
    return this.ambientBlur;
  }

  static setThemeMode(context: common.Context, themeMode: AppearanceThemeMode): AppearanceThemeMode {
    this.themeMode = this.normalizeThemeMode(themeMode);
    this.initialized = true;
    const store = this.preferences(context);
    store.putSync(THEME_MODE_KEY, this.themeMode);
    store.flushSync();
    this.updateAppStorage(this.themeMode);
    this.applyColorMode(context, this.themeMode);
    this.updateIsDarkAppStorage(context, this.themeMode);
    return this.themeMode;
  }

  static setAmbientBlur(context: common.Context, intensity: AmbientBlurIntensity): AmbientBlurIntensity {
    this.ambientBlur = this.normalizeAmbientBlur(intensity);
    this.initialized = true;
    const store = this.preferences(context);
    store.putSync(AMBIENT_BLUR_KEY, this.ambientBlur);
    store.flushSync();
    this.updateAmbientAppStorage(this.ambientBlur);
    return this.ambientBlur;
  }

  static setMaterialLevel(context: common.Context, level: number): number {
    const clamped = level === MATERIAL_LEVEL_EXQUISITE || level === MATERIAL_LEVEL_GENTLE
      || level === MATERIAL_LEVEL_SMOOTH ? level : MATERIAL_LEVEL_ADAPTIVE;
    this.materialLevel = clamped;
    this.initialized = true;
    const store = this.preferences(context);
    store.putSync(MATERIAL_LEVEL_KEY, clamped);
    store.flushSync();
    this.updateMaterialAppStorage(clamped);
    return clamped;
  }

  static currentMaterialLevel(context?: common.Context): number {
    if (context !== undefined) {
      this.load(context);
    }
    return this.materialLevel;
  }

  // ===== OLED 黑 / 信息流开关 =====
  static getOledBlack(context: common.Context): boolean {
    this.load(context);
    return this.oledBlack;
  }

  static setOledBlack(context: common.Context, value: boolean): boolean {
    this.oledBlack = value;
    this.initialized = true;
    const store = this.preferences(context);
    store.putSync(OLED_BLACK_KEY, value);
    store.flushSync();
    this.updateOledBlackAppStorage(value);
    return value;
  }

  static getShowThumbnail(context: common.Context): boolean {
    this.load(context);
    return this.showThumbnail;
  }

  static setShowThumbnail(context: common.Context, value: boolean): boolean {
    this.showThumbnail = value;
    this.initialized = true;
    const store = this.preferences(context);
    store.putSync(SHOW_THUMBNAIL_KEY, value);
    store.flushSync();
    this.updateShowThumbnailAppStorage(value);
    return value;
  }

  static getShowRefreshFab(context: common.Context): boolean {
    this.load(context);
    return this.showRefreshFab;
  }

  static setShowRefreshFab(context: common.Context, value: boolean): boolean {
    this.showRefreshFab = value;
    this.initialized = true;
    const store = this.preferences(context);
    store.putSync(SHOW_REFRESH_FAB_KEY, value);
    store.flushSync();
    this.updateShowRefreshFabAppStorage(value);
    return value;
  }

  static getAutoHideRefreshFab(context: common.Context): boolean {
    this.load(context);
    return this.autoHideRefreshFab;
  }

  static setAutoHideRefreshFab(context: common.Context, value: boolean): boolean {
    this.autoHideRefreshFab = value;
    this.initialized = true;
    const store = this.preferences(context);
    store.putSync(AUTO_HIDE_REFRESH_FAB_KEY, value);
    store.flushSync();
    this.updateAutoHideRefreshFabAppStorage(value);
    return value;
  }

  static getButtonSkipAnswer(context: common.Context): boolean {
    this.load(context);
    return this.buttonSkipAnswer;
  }

  static setButtonSkipAnswer(context: common.Context, value: boolean): boolean {
    this.buttonSkipAnswer = value;
    this.initialized = true;
    const store = this.preferences(context);
    store.putSync(BUTTON_SKIP_ANSWER_KEY, value);
    store.flushSync();
    this.updateButtonSkipAnswerAppStorage(value);
    return value;
  }

  static getAutoHideSkipAnswerButton(context: common.Context): boolean {
    this.load(context);
    return this.autoHideSkipAnswerButton;
  }

  static setAutoHideSkipAnswerButton(context: common.Context, value: boolean): boolean {
    this.autoHideSkipAnswerButton = value;
    this.initialized = true;
    const store = this.preferences(context);
    store.putSync(AUTO_HIDE_SKIP_ANSWER_KEY, value);
    store.flushSync();
    this.updateAutoHideSkipAnswerAppStorage(value);
    return value;
  }

  static getLightCardWhite(context: common.Context): boolean {
    this.load(context);
    return this.lightCardWhite;
  }

  static setLightCardWhite(context: common.Context, value: boolean): boolean {
    this.lightCardWhite = value;
    this.initialized = true;
    const store = this.preferences(context);
    store.putSync(LIGHT_CARD_WHITE_KEY, value);
    store.flushSync();
    this.updateLightCardWhiteAppStorage(value);
    return value;
  }

  // ===== 实验开关：沉浸光感顶栏（uiMaterial，仅鸿蒙7+/API26+，不支持自动回退） =====
  static getEnableHdsTopBar(context: common.Context): boolean {
    this.load(context);
    return this.enableHdsTopBar;
  }

  static setEnableHdsTopBar(context: common.Context, value: boolean): boolean {
    this.enableHdsTopBar = value;
    this.initialized = true;
    const store = this.preferences(context);
    store.putSync(ENABLE_HDS_TOP_BAR_KEY, value);
    store.flushSync();
    this.updateEnableHdsTopBarAppStorage(value);
    return value;
  }

  // ===== 搜索界面：热搜显示 / 搜索历史记录 =====
  static getShowSearchHotSearch(context: common.Context): boolean {
    this.load(context);
    return this.showSearchHotSearch;
  }

  static setShowSearchHotSearch(context: common.Context, value: boolean): boolean {
    this.showSearchHotSearch = value;
    this.initialized = true;
    const store = this.preferences(context);
    store.putSync(SHOW_SEARCH_HOT_SEARCH_KEY, value);
    store.flushSync();
    this.updateShowSearchHotSearchAppStorage(value);
    return value;
  }

  static getShowSearchHistory(context: common.Context): boolean {
    this.load(context);
    return this.showSearchHistory;
  }

  static setShowSearchHistory(context: common.Context, value: boolean): boolean {
    this.showSearchHistory = value;
    this.initialized = true;
    const store = this.preferences(context);
    store.putSync(SHOW_SEARCH_HISTORY_KEY, value);
    store.flushSync();
    this.updateShowSearchHistoryAppStorage(value);
    return value;
  }

  // ===== 阅读体验（整数存储，使用时 /100）=====
  static getReaderFontScale(context: common.Context): number {
    this.load(context);
    return this.readerFontScale / 100;
  }

  static setReaderFontScale(context: common.Context, scale: number): void {
    const stored = Math.round(scale * 100);
    this.readerFontScale = stored;
    this.initialized = true;
    this.preferences(context).putSync(READER_FONT_SCALE_KEY, stored);
    this.preferences(context).flushSync();
  }

  static getReaderLineHeight(context: common.Context): number {
    this.load(context);
    return this.readerLineHeight / 100;
  }

  static setReaderLineHeight(context: common.Context, lineHeight: number): void {
    const stored = Math.round(lineHeight * 100);
    this.readerLineHeight = stored;
    this.initialized = true;
    this.preferences(context).putSync(READER_LINE_HEIGHT_KEY, stored);
    this.preferences(context).flushSync();
  }

  static getReaderParaSpacing(context: common.Context): number {
    this.load(context);
    return this.readerParaSpacing / 100;
  }

  static setReaderParaSpacing(context: common.Context, spacing: number): void {
    const stored = Math.round(spacing * 100);
    this.readerParaSpacing = stored;
    this.initialized = true;
    this.preferences(context).putSync(READER_PARA_SPACING_KEY, stored);
    this.preferences(context).flushSync();
  }

  // ===== 通用整数存取（供滑块等设置行使用）=====
  static getInt(context: common.Context, key: string, defValue: number): number {
    this.load(context);
    return (this.preferences(context).getSync(key, defValue)) as number;
  }

  static setInt(context: common.Context, key: string, value: number): void {
    this.preferences(context).putSync(key, value);
    this.preferences(context).flushSync();
    this.updateReaderAppStorage(key, value);
  }
}

/** 供设置界面直接引用持久化键 */
export const APPEARANCE_KEYS = {
  oledBlack: OLED_BLACK_KEY,
  showThumbnail: SHOW_THUMBNAIL_KEY,
  showRefreshFab: SHOW_REFRESH_FAB_KEY,
  autoHideRefreshFab: AUTO_HIDE_REFRESH_FAB_KEY,
  buttonSkipAnswer: BUTTON_SKIP_ANSWER_KEY,
  autoHideSkipAnswerButton: AUTO_HIDE_SKIP_ANSWER_KEY,
  lightCardWhite: LIGHT_CARD_WHITE_KEY,
  enableHdsTopBar: ENABLE_HDS_TOP_BAR_KEY,
  readerFontScale: READER_FONT_SCALE_KEY,
  readerLineHeight: READER_LINE_HEIGHT_KEY,
  readerParaSpacing: READER_PARA_SPACING_KEY
} as const;