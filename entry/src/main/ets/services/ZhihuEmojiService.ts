import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import { escapeHtml, stripCommentImageLinks, stripHtmlToText } from '../utils/ZhihuHtml';
import { ZhihuApi } from './ZhihuApi';

type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];

interface JsonObject {
  [key: string]: JsonValue;
}

interface CommentEmojiFallbackRule {
  readonly keywords: string[];
  readonly emoji: string;
}

interface NativeEmojiCandidate {
  readonly emoji: string;
  readonly labels: string[];
}

export interface ZhihuEmojiItem {
  token: string;
  emoji: string;
}

export interface ZhihuEmojiSticker {
  placeholder: string;
  dataUrl: string;
}

export interface EmojiPickerItem {
  readonly token: string;
  readonly dataUrl?: string;
  readonly fallback?: string;
}

/** 评论正文的结构化分段：纯文本 / 超链接 / 知乎贴纸图（内联渲染用）。 */
export interface CommentContentSegment {
  readonly kind: 'text' | 'link' | 'emoji';
  readonly text?: string;       // text / link 显示文字；emoji 段可省略
  readonly url?: string;        // link 跳转地址
  readonly dataUrl?: string;    // emoji 贴纸图（base64 data URI）
  readonly alt?: string;        // emoji 占位符 token 名
}

const EMOJI_API_URL: string = 'https://www.zhihu.com/api/v4/sticker-groups/1114161698310770688';
const EMOJI_PREFERENCES_FILE: string = 'zhihu_emoji';
const EMOJI_CACHE_KEY: string = 'emoji_mapping';
const EMOJI_CACHE_VERSION_KEY: string = 'emoji_cache_version';
const EMOJI_CACHE_ORDER_KEY: string = 'emoji_cache_order';
const CURRENT_EMOJI_CACHE_VERSION: string = '1';

const COMMENT_EMOJI_EXACT: Record<string, string> = {
  '感谢': '🙏',
  '哇': '😮',
  '打招呼': '👋',
  '握手': '🤝',
  '知乎益蜂': '🙂',
  '百分百赞': '💯',
  '为爱发乎': '🥰',
  '脑爆': '🤯',
  '暗中学习': '🤓',
  '匿了': '🫥',
  '谢邀': '🙋',
  '赞同': '👍',
  '蹲': '🧎',
  '爱': '😍',
  '害羞': '☺️',
  '好奇': '🤔',
  '思考': '🤔',
  '酷': '😎',
  '大笑': '😄',
  '微笑': '🙂',
  '捂脸': '🤦',
  '捂嘴': '🤭',
  '飙泪笑': '😂',
  '耶': '✌️',
  '可怜': '🥺',
  '惊喜': '🎉',
  '流泪': '😢',
  '大哭': '😭',
  '生气': '😠',
  '惊讶': '😲',
  '调皮': '😜',
  '衰': '😞',
  '发呆': '😶',
  '机智': '😏',
  '嘘': '🤫',
  '尴尬': '😅',
  '小情绪': '🥲',
  '为难': '😬',
  '吃瓜': '🍉',
  '语塞': '😶',
  '看看你': '🫣',
  '撇嘴': '😒',
  '魔性笑': '😁',
  '潜水': '🤿',
  '口罩': '😷',
  '开心': '😄',
  '滑稽': '😏',
  '笑哭': '😂',
  '白眼': '🙄',
  '红心': '❤️',
  '柠檬': '🍋',
  '拜托': '🥺',
  '赞': '👍',
  '发火': '🔥',
  '不抬杠': '🙌',
  '种草': '🌱'
};

const COMMENT_EMOJI_FALLBACK_RULES: CommentEmojiFallbackRule[] = [
  { keywords: ['笑', '乐', '开心', '高兴', '嘿嘿', '哈哈'], emoji: '😄' },
  { keywords: ['哭', '泪', '委屈', '难过'], emoji: '😢' },
  { keywords: ['大哭', '爆哭'], emoji: '😭' },
  { keywords: ['爱', '喜欢', '心动'], emoji: '😍' },
  { keywords: ['心', '爱心'], emoji: '❤️' },
  { keywords: ['赞', '点赞', '棒', '牛'], emoji: '👍' },
  { keywords: ['惊', '震惊', '惊呆', '哇'], emoji: '😮' },
  { keywords: ['怒', '气', '火大', '抓狂'], emoji: '😠' },
  { keywords: ['汗', '尬', '无语'], emoji: '😅' },
  { keywords: ['思考', '想', '问号', '疑惑', '好奇'], emoji: '🤔' },
  { keywords: ['酷', '帅'], emoji: '😎' },
  { keywords: ['羞', '脸红'], emoji: '☺️' },
  { keywords: ['捂脸'], emoji: '🤦' },
  { keywords: ['捂嘴'], emoji: '🤭' },
  { keywords: ['嘘', '安静'], emoji: '🤫' },
  { keywords: ['拜托', '求', '求求'], emoji: '🥺' },
  { keywords: ['爱你', '亲亲'], emoji: '😘' },
  { keywords: ['机智', '得意'], emoji: '😏' },
  { keywords: ['白眼', '嫌弃'], emoji: '🙄' },
  { keywords: ['吃瓜'], emoji: '🍉' },
  { keywords: ['柠檬', '酸'], emoji: '🍋' },
  { keywords: ['火'], emoji: '🔥' },
  { keywords: ['学习', '看书'], emoji: '🤓' },
  { keywords: ['潜水'], emoji: '🤿' },
  { keywords: ['口罩', '生病'], emoji: '😷' },
  { keywords: ['握手'], emoji: '🤝' },
  { keywords: ['招呼'], emoji: '👋' },
  { keywords: ['耶', '胜利'], emoji: '✌️' },
  { keywords: ['草', '种草'], emoji: '🌱' },
  { keywords: ['爆炸', '脑爆'], emoji: '🤯' }
];

const NATIVE_EMOJI_CANDIDATES: NativeEmojiCandidate[] = [
  { emoji: '🙂', labels: ['微笑', '笑', '开心', '友好', '礼貌'] },
  { emoji: '😄', labels: ['大笑', '开心', '高兴', '哈哈', '笑开了'] },
  { emoji: '😂', labels: ['笑哭', '飙泪笑', '爆笑', '笑到流泪'] },
  { emoji: '😢', labels: ['流泪', '伤心', '委屈', '难过'] },
  { emoji: '😭', labels: ['大哭', '爆哭', '崩溃', '痛哭'] },
  { emoji: '😠', labels: ['生气', '愤怒', '火大', '恼火'] },
  { emoji: '😮', labels: ['惊讶', '震惊', '哇', '吃惊'] },
  { emoji: '😎', labels: ['酷', '帅', '潇洒'] },
  { emoji: '🤔', labels: ['思考', '好奇', '疑惑', '问号', '想想'] },
  { emoji: '😍', labels: ['爱', '喜欢', '心动', '迷恋'] },
  { emoji: '😘', labels: ['亲亲', '爱你', '飞吻'] },
  { emoji: '❤️', labels: ['红心', '爱心', '喜欢', '热爱'] },
  { emoji: '👍', labels: ['赞', '点赞', '赞同', '棒', '厉害'] },
  { emoji: '🙏', labels: ['感谢', '拜托', '谢谢', '求求'] },
  { emoji: '👋', labels: ['打招呼', '招手', '挥手', '你好'] },
  { emoji: '🤝', labels: ['握手', '合作', '和解'] },
  { emoji: '🤦', labels: ['捂脸', '无奈', '服了'] },
  { emoji: '🤭', labels: ['捂嘴', '偷笑', '憋笑'] },
  { emoji: '🤫', labels: ['嘘', '安静', '别说话'] },
  { emoji: '🥺', labels: ['可怜', '拜托', '委屈', '求你了'] },
  { emoji: '😏', labels: ['机智', '得意', '滑稽', '小聪明'] },
  { emoji: '🙄', labels: ['白眼', '嫌弃', '无语'] },
  { emoji: '😅', labels: ['尴尬', '冒汗', '汗颜'] },
  { emoji: '☺️', labels: ['害羞', '脸红', '羞涩'] },
  { emoji: '😬', labels: ['为难', '勉强', '僵住'] },
  { emoji: '😶', labels: ['发呆', '语塞', '沉默'] },
  { emoji: '🤯', labels: ['脑爆', '爆炸', '震撼'] },
  { emoji: '🤓', labels: ['学习', '知识', '认真', '学霸'] },
  { emoji: '😷', labels: ['口罩', '生病', '防护'] },
  { emoji: '🍉', labels: ['吃瓜', '围观', '看戏'] },
  { emoji: '🍋', labels: ['柠檬', '酸', '吃醋'] },
  { emoji: '🔥', labels: ['发火', '火', '上头', '燃'] },
  { emoji: '🌱', labels: ['种草', '草', '安利', '生长'] },
  { emoji: '✌️', labels: ['耶', '胜利', '比耶'] },
  { emoji: '🤿', labels: ['潜水', '下潜', '潜了'] },
  { emoji: '🫣', labels: ['看看你', '偷看', '不敢看'] },
  { emoji: '😜', labels: ['调皮', '吐舌', '皮一下'] },
  { emoji: '😒', labels: ['撇嘴', '不屑', '嫌弃'] },
  { emoji: '😁', labels: ['魔性笑', '咧嘴', '傻笑'] },
  { emoji: '🫥', labels: ['匿了', '隐身', '消失'] },
  { emoji: '💯', labels: ['百分百赞', '满分', '一百分'] },
  { emoji: '🙋', labels: ['谢邀', '我来', '举手'] },
  { emoji: '🥰', labels: ['为爱发乎', '甜蜜', '恋爱'] }
];

export class ZhihuEmojiService {
  private static initialized: boolean = false;
  private static stickerMapping: Record<string, string> = {};
  private static stickerList: ZhihuEmojiSticker[] = [];

  private static stringValue(value: JsonValue | undefined): string {
    return typeof value === 'string' ? value : '';
  }

  private static objectValue(value: JsonValue | undefined): JsonObject {
    return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as JsonObject : {};
  }

  private static arrayValue(value: JsonValue | undefined): JsonValue[] {
    return Array.isArray(value) ? value : [];
  }

  private static preferences(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, {
      name: EMOJI_PREFERENCES_FILE
    });
  }

  /** 归一化占位符：去掉知乎 API 返回的占位符自带的方括号（如 "[哇]" -> "哇"）。 */
  private static normalizePlaceholder(raw: string): string {
    const trimmed = raw.trim();
    const m = /^\[(.+)\]$/.exec(trimmed);
    return (m ? m[1] : trimmed).trim();
  }

  private static sanitizeStickerMapping(raw: Object | undefined): Record<string, string> {
    if (raw === undefined || raw === null || typeof raw !== 'object') {
      return {};
    }
    const mapping: Record<string, string> = {};
    Object.entries(raw as Record<string, Object>).forEach(([placeholder, dataUrl]: [string, Object]) => {
      if (typeof dataUrl === 'string' && dataUrl.startsWith('data:image/')) {
        const key = this.normalizePlaceholder(placeholder);
        if (key.length > 0) {
          mapping[key] = dataUrl;
        }
      }
    });
    return mapping;
  }

  private static loadFromCache(context: common.Context, ignoreVersion: boolean = false): boolean {
    const store = this.preferences(context);
    const version = store.getSync(EMOJI_CACHE_VERSION_KEY, '') as string;
    const encoded = store.getSync(EMOJI_CACHE_KEY, '') as string;
    if ((!ignoreVersion && version !== CURRENT_EMOJI_CACHE_VERSION) || typeof encoded !== 'string' || encoded.length === 0) {
      return false;
    }
    try {
      this.stickerMapping = this.sanitizeStickerMapping(JSON.parse(encoded) as Object);
      const orderRaw = store.getSync(EMOJI_CACHE_ORDER_KEY, '[]') as string;
      const order = JSON.parse(orderRaw) as string[];
      this.stickerList = order
        .map((p: string) => this.normalizePlaceholder(p))
        .filter((p: string) => typeof this.stickerMapping[p] === 'string')
        .map((p: string) => ({ placeholder: p, dataUrl: this.stickerMapping[p] }));
      return this.stickerList.length > 0;
    } catch (_) {
      this.stickerMapping = {};
      this.stickerList = [];
      return false;
    }
  }

  private static saveToCache(context: common.Context, mapping: Record<string, string>, list: ZhihuEmojiSticker[]): void {
    const store = this.preferences(context);
    store.putSync(EMOJI_CACHE_KEY, JSON.stringify(mapping));
    store.putSync(EMOJI_CACHE_ORDER_KEY, JSON.stringify(list.map((i: ZhihuEmojiSticker) => i.placeholder)));
    store.putSync(EMOJI_CACHE_VERSION_KEY, CURRENT_EMOJI_CACHE_VERSION);
    store.flushSync();
  }

  private static async downloadStickerMapping(): Promise<ZhihuEmojiSticker[]> {
    const payload = await ZhihuApi.getJson(EMOJI_API_URL);
    if (payload === null) {
      return [];
    }
    const stickers = this.arrayValue(this.objectValue(payload.data).stickers);
    const mapping: Record<string, string> = {};
    const list: ZhihuEmojiSticker[] = [];
    stickers.forEach((item: JsonValue) => {
      const sticker = this.objectValue(item);
      const placeholder = this.normalizePlaceholder(this.stringValue(sticker.placeholder));
      const dataUrl = this.stringValue(sticker.static_image_url);
      if (placeholder.length > 0 && dataUrl.startsWith('data:image/')) {
        mapping[placeholder] = dataUrl;
        list.push({ placeholder, dataUrl });
      }
    });
    this.stickerMapping = mapping;
    return list;
  }

  private static nativeEmojiMatchScore(token: string, candidate: NativeEmojiCandidate): number {
    let score = 0;
    candidate.labels.forEach((label: string) => {
      if (token === label) {
        score += 100;
        return;
      }
      if (token.includes(label)) {
        score += 20 + label.length * 3;
        return;
      }
      if (label.includes(token)) {
        score += 12 + token.length * 2;
        return;
      }
      let overlap = 0;
      token.split('').forEach((char: string) => {
        if (label.includes(char)) {
          overlap += 1;
        }
      });
      score += overlap;
    });
    return score;
  }

  private static findClosestNativeEmoji(token: string): string | undefined {
    let bestEmoji: string | undefined = undefined;
    let bestScore = 0;
    NATIVE_EMOJI_CANDIDATES.forEach((candidate: NativeEmojiCandidate) => {
      const score = this.nativeEmojiMatchScore(token, candidate);
      if (score > bestScore) {
        bestScore = score;
        bestEmoji = candidate.emoji;
      }
    });
    return bestScore >= 4 ? bestEmoji : undefined;
  }

  private static resolveNativeEmoji(token: string): string | undefined {
    const exact = COMMENT_EMOJI_EXACT[token];
    if (typeof exact === 'string') {
      return exact;
    }
    const closest = this.findClosestNativeEmoji(token);
    if (typeof closest === 'string') {
      return closest;
    }
    const fallback = COMMENT_EMOJI_FALLBACK_RULES.find((rule: CommentEmojiFallbackRule) => {
      return rule.keywords.some((keyword: string) => token.includes(keyword));
    });
    return fallback?.emoji;
  }

  private static replacePlainTextSegment(text: string, preferSticker: boolean): string {
    return text.replace(/\[([^\[\]]+)\]/g, (match: string, token: string): string => {
      const normalized = token.trim();
      if (normalized.length === 0) {
        return match;
      }
      const stickerDataUrl = preferSticker ? this.stickerMapping[normalized] : undefined;
      if (typeof stickerDataUrl === 'string' && stickerDataUrl.length > 0) {
        const safeToken = escapeHtml(normalized);
        return `<img class="zhihu-emoji" src="${escapeHtml(stickerDataUrl)}" alt="${safeToken}" title="${safeToken}">`;
      }
      return this.resolveNativeEmoji(normalized) ?? match;
    });
  }

  static async initialize(context: common.Context): Promise<void> {
    if (this.initialized) {
      return;
    }
    if (this.loadFromCache(context)) {
      this.initialized = true;
      return;
    }
    try {
      const list = await this.downloadStickerMapping();
      this.stickerList = list;
      if (list.length > 0) {
        const mapping: Record<string, string> = {};
        list.forEach((i: ZhihuEmojiSticker) => { mapping[i.placeholder] = i.dataUrl; });
        this.saveToCache(context, mapping, list);
      }
    } catch (_) {
      if (!this.loadFromCache(context, true)) {
        this.stickerMapping = {};
        this.stickerList = [];
      }
    } finally {
      this.initialized = true;
    }
  }

  static replaceText(text: string): string {
    return this.replacePlainTextSegment(text, false);
  }

  static replaceHtml(html: string): string {
    if (html.length === 0) {
      return html;
    }
    return html
      .split(/(<[^>]+>)/g)
      .map((segment: string) => segment.startsWith('<') ? segment : this.replacePlainTextSegment(segment, true))
      .join('');
  }

  static getEmojiList(): ZhihuEmojiItem[] {
    return Object.entries(COMMENT_EMOJI_EXACT).map(([token, emoji]: [string, string]) => ({ token, emoji }));
  }

  static getStickerList(): ZhihuEmojiSticker[] {
    return this.stickerList;
  }

  static isStickerReady(): boolean {
    return this.stickerList.length > 0;
  }

  /** 评论输入框表情选择器的数据源：贴纸就绪返回知乎贴纸图，否则降级到 Unicode 静态表。 */
  static getEmojiPickerItems(): EmojiPickerItem[] {
    if (this.stickerList.length > 0) {
      return this.stickerList.map((s: ZhihuEmojiSticker) => ({ token: s.placeholder, dataUrl: s.dataUrl }));
    }
    return Object.entries(COMMENT_EMOJI_EXACT).map(([token, emoji]: [string, string]) => ({ token, fallback: emoji }));
  }

  /**
   * 解析评论正文 HTML 为结构化分段，供 ArkUI 以 Text{Span / ImageSpan} 内联渲染。
   * 关键修复：贴纸 `[token]` 命中 stickerMapping 时输出 emoji 段（ImageSpan 渲染贴纸图），
   * 否则降级到 Unicode 表情；不再像旧 replaceText(preferSticker=false) 那样原样输出 [token]。
   */
  static parseCommentContent(html: string): CommentContentSegment[] {
    const segments: CommentContentSegment[] = [];
    if (typeof html !== 'string' || html.length === 0) {
      return segments;
    }
    const cleaned = stripCommentImageLinks(html);
    const linkRegex = /<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
    let lastIndex = 0;
    let match: RegExpExecArray | null;
    while ((match = linkRegex.exec(cleaned)) !== null) {
      if (match.index > lastIndex) {
        this.appendPlainSegments(segments, cleaned.substring(lastIndex, match.index));
      }
      const linkUrl = match[1];
      const linkText = this.tokenTextToPlain(stripHtmlToText(match[2]));
      if (linkText.length > 0) {
        segments.push({ kind: 'link', text: linkText, url: linkUrl });
      }
      lastIndex = linkRegex.lastIndex;
    }
    if (lastIndex < cleaned.length) {
      this.appendPlainSegments(segments, cleaned.substring(lastIndex));
    }
    return segments;
  }

  private static tokenTextToPlain(text: string): string {
    return text.replace(/\[([^\[\]]+)\]/g, (_m: string, token: string): string => {
      const normalized = token.trim();
      if (normalized.length === 0) {
        return _m;
      }
      const dataUrl = this.stickerMapping[normalized];
      if (typeof dataUrl === 'string' && dataUrl.length > 0) {
        return normalized;
      }
      return this.resolveNativeEmoji(normalized) ?? normalized;
    });
  }

  private static appendPlainSegments(segments: CommentContentSegment[], htmlFragment: string): void {
    const plain = stripHtmlToText(htmlFragment);
    if (plain.length === 0) {
      return;
    }
    const tokenRegex = /\[([^\[\]]+)\]/g;
    let lastIndex = 0;
    let match: RegExpExecArray | null;
    while ((match = tokenRegex.exec(plain)) !== null) {
      if (match.index > lastIndex) {
        const piece = plain.substring(lastIndex, match.index);
        if (piece.length > 0) {
          segments.push({ kind: 'text', text: piece });
        }
      }
      const token = match[1].trim();
      if (token.length > 0) {
        const dataUrl = this.stickerMapping[token];
        if (typeof dataUrl === 'string' && dataUrl.length > 0) {
          segments.push({ kind: 'emoji', dataUrl, alt: token });
        } else {
          const fallback = this.resolveNativeEmoji(token) ?? token;
          segments.push({ kind: 'text', text: fallback });
        }
      }
      lastIndex = tokenRegex.lastIndex;
    }
    if (lastIndex < plain.length) {
      const tail = plain.substring(lastIndex);
      if (tail.length > 0) {
        segments.push({ kind: 'text', text: tail });
      }
    }
  }
}
