import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';

/**
 * 设计度量层（软尺寸）。
 *
 * 设计目标：所有字号 / 间距 / 圆角都不是写死的字面量，而是
 *   「官方基线 × 用户倍率」 算出来的值。
 *
 * - 基线：鸿蒙官方设计规范数值（与 base/element/float.json 保持一致，
 *   float.json 作为声明式默认真值，供静态引用与预览）。
 * - 倍率：fontScale（字号）/ spaceScale（间距密度），默认 1.0，
 *   持久化到 preferences（×100 整数存储，与阅读体验三项一致），
 *   运行期镜像到 AppStorage，页面用 @StorageProp 消费即可实时重排。
 *
 * 单位差异（关键）：
 * - 字号用 fp 字符串（如 '16fp'）：fp 会跟随系统字号设置放大，保留无障碍能力；
 *   再叠加 app 级 fontScale，两者相乘即为最终效果。
 * - 间距用 vp 数字：不受系统字号影响，只跟 spaceScale 走。
 *
 * 后续若要「任意调节」：改这两个倍率，或在 compute 里加单 token override，
 * 均不需要改动任何页面代码。
 */
const METRICS_PREFERENCES_FILE: string = 'zhihu_appearance';
export const FONT_SCALE_KEY: string = 'ui_font_scale';
export const SPACE_SCALE_KEY: string = 'ui_space_scale';
const DEFAULT_SCALE_RAW: number = 100;

/** 允许调节的区间（×100），避免极端值把布局撑坏 */
const MIN_SCALE_RAW: number = 85;
const MAX_SCALE_RAW: number = 130;

// —— 官方基线（与 base/element/float.json 数值一致，修改时请同步两边）——
const BASE_FONT_DISPLAY: number = 30;
const BASE_FONT_HEADING: number = 20;
const BASE_FONT_SUBTITLE: number = 16;
const BASE_FONT_BODY: number = 16;
const BASE_FONT_SECONDARY: number = 14;
const BASE_FONT_CAPTION: number = 12;
// 13 / 18 是现有界面高频字号（仅 10 个小页面就分别有 32 / 14 处），
// 不补 token 的话这部分只能继续硬写，故按「默认值 = 现状值」补齐，保证视觉零变化。
const BASE_FONT_META: number = 13;
const BASE_FONT_SUBHEAD: number = 18;
// 徽标(未读角标)与符号(‹ › 箭头、空状态图标)是两类专有度量，
// 原先散落为 10 / 22 / 26 / 28 四个值，统一各归一个档。
const BASE_FONT_BADGE: number = 10;
const BASE_FONT_SYMBOL: number = 24;
// 以下为界面中偶发出现的非标准字号（小辅助字 / 细微差异正文 / 卡片大标题等），
// 一并纳入软尺寸，保证全局缩放下视觉零变化。
const BASE_FONT_MINI: number = 11;
const BASE_FONT_BODY_SM: number = 15;
const BASE_FONT_BODY_LG: number = 17;
const BASE_FONT_TITLE: number = 22;
const BASE_FONT_LARGE_TITLE: number = 26;
const BASE_FONT_DISPLAY_LG: number = 28;

const BASE_SPACE_XS: number = 4;
const BASE_SPACE_SM: number = 8;
const BASE_SPACE_MD: number = 12;
const BASE_SPACE_LG: number = 24;
const BASE_CARD_PADDING: number = 16;
const BASE_CARD_RADIUS: number = 16;
const BASE_BUTTON_RADIUS: number = 20;
const BASE_PILL_RADIUS: number = 18;
const BASE_PAGE_PADDING: number = 20;

/** 页面用 @StorageProp('fontBody') 这样消费；键名在此集中声明 */
export const METRICS_KEYS = {
  fontDisplay: 'fontDisplay',
  fontHeading: 'fontHeading',
  fontSubtitle: 'fontSubtitle',
  fontBody: 'fontBody',
  fontSecondary: 'fontSecondary',
  fontCaption: 'fontCaption',
  fontMeta: 'fontMeta',
  fontSubhead: 'fontSubhead',
  fontBadge: 'fontBadge',
  fontSymbol: 'fontSymbol',
  fontMini: 'fontMini',
  fontBodySm: 'fontBodySm',
  fontBodyLg: 'fontBodyLg',
  fontTitle: 'fontTitle',
  fontLargeTitle: 'fontLargeTitle',
  fontDisplayLg: 'fontDisplayLg',
  spaceXs: 'spaceXs',
  spaceSm: 'spaceSm',
  spaceMd: 'spaceMd',
  spaceLg: 'spaceLg',
  cardPadding: 'cardPadding',
  cardRadius: 'cardRadius',
  buttonRadius: 'buttonRadius',
  pillRadius: 'pillRadius',
  pagePadding: 'pagePadding'
} as const;

export class DesignMetrics {
  private static fontScaleRaw: number = DEFAULT_SCALE_RAW;
  private static spaceScaleRaw: number = DEFAULT_SCALE_RAW;
  private static initialized: boolean = false;

  // 最近一次算出的派生值，供非 UI 场景（如 TS 逻辑）直接读取
  private static valueFontDisplay: string = BASE_FONT_DISPLAY + 'fp';
  private static valueFontHeading: string = BASE_FONT_HEADING + 'fp';
  private static valueFontSubtitle: string = BASE_FONT_SUBTITLE + 'fp';
  private static valueFontBody: string = BASE_FONT_BODY + 'fp';
  private static valueFontSecondary: string = BASE_FONT_SECONDARY + 'fp';
  private static valueFontCaption: string = BASE_FONT_CAPTION + 'fp';
  private static valueFontMeta: string = BASE_FONT_META + 'fp';
  private static valueFontSubhead: string = BASE_FONT_SUBHEAD + 'fp';
  private static valueFontBadge: string = BASE_FONT_BADGE + 'fp';
  private static valueFontSymbol: string = BASE_FONT_SYMBOL + 'fp';
  private static valueFontMini: string = BASE_FONT_MINI + 'fp';
  private static valueFontBodySm: string = BASE_FONT_BODY_SM + 'fp';
  private static valueFontBodyLg: string = BASE_FONT_BODY_LG + 'fp';
  private static valueFontTitle: string = BASE_FONT_TITLE + 'fp';
  private static valueFontLargeTitle: string = BASE_FONT_LARGE_TITLE + 'fp';
  private static valueFontDisplayLg: string = BASE_FONT_DISPLAY_LG + 'fp';
  private static valueSpaceXs: number = BASE_SPACE_XS;
  private static valueSpaceSm: number = BASE_SPACE_SM;
  private static valueSpaceMd: number = BASE_SPACE_MD;
  private static valueSpaceLg: number = BASE_SPACE_LG;
  private static valueCardPadding: number = BASE_CARD_PADDING;
  private static valueCardRadius: number = BASE_CARD_RADIUS;
  private static valueButtonRadius: number = BASE_BUTTON_RADIUS;
  private static valuePillRadius: number = BASE_PILL_RADIUS;
  private static valuePagePadding: number = BASE_PAGE_PADDING;

  private static store(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, {
      name: METRICS_PREFERENCES_FILE
    });
  }

  private static clampRaw(raw: number): number {
    if (raw < MIN_SCALE_RAW) {
      return MIN_SCALE_RAW;
    }
    if (raw > MAX_SCALE_RAW) {
      return MAX_SCALE_RAW;
    }
    return raw;
  }

  /** 字号基线 × 倍率 → fp 字符串，最多保留 1 位小数 */
  private static toFp(base: number, scale: number): string {
    const rounded: number = Math.round(base * scale * 10) / 10;
    return rounded + 'fp';
  }

  /** 间距基线 × 倍率 → vp 数字，最多保留 1 位小数 */
  private static toVp(base: number, scale: number): number {
    return Math.round(base * scale * 10) / 10;
  }

  private static putString(key: string, value: string): void {
    if (!AppStorage.set<string>(key, value)) {
      AppStorage.setOrCreate<string>(key, value);
    }
  }

  private static putNumber(key: string, value: number): void {
    if (!AppStorage.set<number>(key, value)) {
      AppStorage.setOrCreate<number>(key, value);
    }
  }

  /** 依据当前倍率重算全部派生值并写入 AppStorage（触发 @StorageProp 页面重排） */
  private static compute(): void {
    const fontScale: number = DesignMetrics.fontScaleRaw / 100;
    const spaceScale: number = DesignMetrics.spaceScaleRaw / 100;

    DesignMetrics.valueFontDisplay = DesignMetrics.toFp(BASE_FONT_DISPLAY, fontScale);
    DesignMetrics.valueFontHeading = DesignMetrics.toFp(BASE_FONT_HEADING, fontScale);
    DesignMetrics.valueFontSubtitle = DesignMetrics.toFp(BASE_FONT_SUBTITLE, fontScale);
    DesignMetrics.valueFontBody = DesignMetrics.toFp(BASE_FONT_BODY, fontScale);
    DesignMetrics.valueFontSecondary = DesignMetrics.toFp(BASE_FONT_SECONDARY, fontScale);
    DesignMetrics.valueFontCaption = DesignMetrics.toFp(BASE_FONT_CAPTION, fontScale);
    DesignMetrics.valueFontMeta = DesignMetrics.toFp(BASE_FONT_META, fontScale);
    DesignMetrics.valueFontSubhead = DesignMetrics.toFp(BASE_FONT_SUBHEAD, fontScale);
    DesignMetrics.valueFontBadge = DesignMetrics.toFp(BASE_FONT_BADGE, fontScale);
    DesignMetrics.valueFontSymbol = DesignMetrics.toFp(BASE_FONT_SYMBOL, fontScale);
    DesignMetrics.valueFontMini = DesignMetrics.toFp(BASE_FONT_MINI, fontScale);
    DesignMetrics.valueFontBodySm = DesignMetrics.toFp(BASE_FONT_BODY_SM, fontScale);
    DesignMetrics.valueFontBodyLg = DesignMetrics.toFp(BASE_FONT_BODY_LG, fontScale);
    DesignMetrics.valueFontTitle = DesignMetrics.toFp(BASE_FONT_TITLE, fontScale);
    DesignMetrics.valueFontLargeTitle = DesignMetrics.toFp(BASE_FONT_LARGE_TITLE, fontScale);
    DesignMetrics.valueFontDisplayLg = DesignMetrics.toFp(BASE_FONT_DISPLAY_LG, fontScale);

    DesignMetrics.valueSpaceXs = DesignMetrics.toVp(BASE_SPACE_XS, spaceScale);
    DesignMetrics.valueSpaceSm = DesignMetrics.toVp(BASE_SPACE_SM, spaceScale);
    DesignMetrics.valueSpaceMd = DesignMetrics.toVp(BASE_SPACE_MD, spaceScale);
    DesignMetrics.valueSpaceLg = DesignMetrics.toVp(BASE_SPACE_LG, spaceScale);
    DesignMetrics.valueCardPadding = DesignMetrics.toVp(BASE_CARD_PADDING, spaceScale);
    DesignMetrics.valueCardRadius = DesignMetrics.toVp(BASE_CARD_RADIUS, spaceScale);
    DesignMetrics.valueButtonRadius = DesignMetrics.toVp(BASE_BUTTON_RADIUS, spaceScale);
    DesignMetrics.valuePillRadius = DesignMetrics.toVp(BASE_PILL_RADIUS, spaceScale);
    DesignMetrics.valuePagePadding = DesignMetrics.toVp(BASE_PAGE_PADDING, spaceScale);

    DesignMetrics.putString(METRICS_KEYS.fontDisplay, DesignMetrics.valueFontDisplay);
    DesignMetrics.putString(METRICS_KEYS.fontHeading, DesignMetrics.valueFontHeading);
    DesignMetrics.putString(METRICS_KEYS.fontSubtitle, DesignMetrics.valueFontSubtitle);
    DesignMetrics.putString(METRICS_KEYS.fontBody, DesignMetrics.valueFontBody);
    DesignMetrics.putString(METRICS_KEYS.fontSecondary, DesignMetrics.valueFontSecondary);
    DesignMetrics.putString(METRICS_KEYS.fontCaption, DesignMetrics.valueFontCaption);
    DesignMetrics.putString(METRICS_KEYS.fontMeta, DesignMetrics.valueFontMeta);
    DesignMetrics.putString(METRICS_KEYS.fontSubhead, DesignMetrics.valueFontSubhead);
    DesignMetrics.putString(METRICS_KEYS.fontBadge, DesignMetrics.valueFontBadge);
    DesignMetrics.putString(METRICS_KEYS.fontSymbol, DesignMetrics.valueFontSymbol);
    DesignMetrics.putString(METRICS_KEYS.fontMini, DesignMetrics.valueFontMini);
    DesignMetrics.putString(METRICS_KEYS.fontBodySm, DesignMetrics.valueFontBodySm);
    DesignMetrics.putString(METRICS_KEYS.fontBodyLg, DesignMetrics.valueFontBodyLg);
    DesignMetrics.putString(METRICS_KEYS.fontTitle, DesignMetrics.valueFontTitle);
    DesignMetrics.putString(METRICS_KEYS.fontLargeTitle, DesignMetrics.valueFontLargeTitle);
    DesignMetrics.putString(METRICS_KEYS.fontDisplayLg, DesignMetrics.valueFontDisplayLg);

    DesignMetrics.putNumber(METRICS_KEYS.spaceXs, DesignMetrics.valueSpaceXs);
    DesignMetrics.putNumber(METRICS_KEYS.spaceSm, DesignMetrics.valueSpaceSm);
    DesignMetrics.putNumber(METRICS_KEYS.spaceMd, DesignMetrics.valueSpaceMd);
    DesignMetrics.putNumber(METRICS_KEYS.spaceLg, DesignMetrics.valueSpaceLg);
    DesignMetrics.putNumber(METRICS_KEYS.cardPadding, DesignMetrics.valueCardPadding);
    DesignMetrics.putNumber(METRICS_KEYS.cardRadius, DesignMetrics.valueCardRadius);
    DesignMetrics.putNumber(METRICS_KEYS.buttonRadius, DesignMetrics.valueButtonRadius);
    DesignMetrics.putNumber(METRICS_KEYS.pillRadius, DesignMetrics.valuePillRadius);
    DesignMetrics.putNumber(METRICS_KEYS.pagePadding, DesignMetrics.valuePagePadding);
  }

  /** 应用启动时调用一次，之后 setFontScale/setSpaceScale 会自动重算 */
  static load(context: common.Context): void {
    if (!DesignMetrics.initialized) {
      const store = DesignMetrics.store(context);
      DesignMetrics.fontScaleRaw = DesignMetrics.clampRaw((store.getSync(FONT_SCALE_KEY, DEFAULT_SCALE_RAW)) as number);
      DesignMetrics.spaceScaleRaw = DesignMetrics.clampRaw((store.getSync(SPACE_SCALE_KEY, DEFAULT_SCALE_RAW)) as number);
      DesignMetrics.initialized = true;
    }
    DesignMetrics.compute();
  }

  static getFontScale(context?: common.Context): number {
    if (context !== undefined) {
      DesignMetrics.load(context);
    }
    return DesignMetrics.fontScaleRaw / 100;
  }

  static setFontScale(context: common.Context, scale: number): void {
    const raw: number = DesignMetrics.clampRaw(Math.round(scale * 100));
    DesignMetrics.fontScaleRaw = raw;
    DesignMetrics.initialized = true;
    const store = DesignMetrics.store(context);
    store.putSync(FONT_SCALE_KEY, raw);
    store.flushSync();
    DesignMetrics.compute();
  }

  static getSpaceScale(context?: common.Context): number {
    if (context !== undefined) {
      DesignMetrics.load(context);
    }
    return DesignMetrics.spaceScaleRaw / 100;
  }

  static setSpaceScale(context: common.Context, scale: number): void {
    const raw: number = DesignMetrics.clampRaw(Math.round(scale * 100));
    DesignMetrics.spaceScaleRaw = raw;
    DesignMetrics.initialized = true;
    const store = DesignMetrics.store(context);
    store.putSync(SPACE_SCALE_KEY, raw);
    store.flushSync();
    DesignMetrics.compute();
  }

  // —— 非响应式读取（TS 逻辑场景；UI 请用 @StorageProp + METRICS_KEYS）——
  static fontDisplay(): string {
    return DesignMetrics.valueFontDisplay;
  }

  static fontHeading(): string {
    return DesignMetrics.valueFontHeading;
  }

  static fontSubtitle(): string {
    return DesignMetrics.valueFontSubtitle;
  }

  static fontBody(): string {
    return DesignMetrics.valueFontBody;
  }

  static fontSecondary(): string {
    return DesignMetrics.valueFontSecondary;
  }

  static fontCaption(): string {
    return DesignMetrics.valueFontCaption;
  }

  static fontMeta(): string {
    return DesignMetrics.valueFontMeta;
  }

  static fontSubhead(): string {
    return DesignMetrics.valueFontSubhead;
  }

  static fontBadge(): string {
    return DesignMetrics.valueFontBadge;
  }

  static fontSymbol(): string {
    return DesignMetrics.valueFontSymbol;
  }

  static fontMini(): string {
    return DesignMetrics.valueFontMini;
  }

  static fontBodySm(): string {
    return DesignMetrics.valueFontBodySm;
  }

  static fontBodyLg(): string {
    return DesignMetrics.valueFontBodyLg;
  }

  static fontTitle(): string {
    return DesignMetrics.valueFontTitle;
  }

  static fontLargeTitle(): string {
    return DesignMetrics.valueFontLargeTitle;
  }

  static fontDisplayLg(): string {
    return DesignMetrics.valueFontDisplayLg;
  }

  static spaceXs(): number {
    return DesignMetrics.valueSpaceXs;
  }

  static spaceSm(): number {
    return DesignMetrics.valueSpaceSm;
  }

  static spaceMd(): number {
    return DesignMetrics.valueSpaceMd;
  }

  static spaceLg(): number {
    return DesignMetrics.valueSpaceLg;
  }

  static cardPadding(): number {
    return DesignMetrics.valueCardPadding;
  }

  static cardRadius(): number {
    return DesignMetrics.valueCardRadius;
  }

  static buttonRadius(): number {
    return DesignMetrics.valueButtonRadius;
  }

  static pillRadius(): number {
    return DesignMetrics.valuePillRadius;
  }

  static pagePadding(): number {
    return DesignMetrics.valuePagePadding;
  }
}
