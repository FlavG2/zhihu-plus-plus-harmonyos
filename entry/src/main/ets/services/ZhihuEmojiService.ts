import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import { escapeHtml } from '../utils/ZhihuHtml';
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

const EMOJI_API_URL: string = 'https://www.zhihu.com/api/v4/sticker-groups/1114161698310770688';
const EMOJI_PREFERENCES_FILE: string = 'zhihu_emoji';
const EMOJI_CACHE_KEY: string = 'emoji_mapping';
const EMOJI_CACHE_VERSION_KEY: string = 'emoji_cache_version';
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

  private static sanitizeStickerMapping(raw: Object | undefined): Record<string, string> {
    if (raw === undefined || raw === null || typeof raw !== 'object') {
      return {};
    }
    const mapping: Record<string, string> = {};
    Object.entries(raw as Record<string, Object>).forEach(([placeholder, dataUrl]: [string, Object]) => {
      if (typeof dataUrl === 'string' && placeholder.trim().length > 0 && dataUrl.startsWith('data:image/')) {
        mapping[placeholder.trim()] = dataUrl;
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
      return Object.keys(this.stickerMapping).length > 0;
    } catch (_) {
      this.stickerMapping = {};
      return false;
    }
  }

  private static saveToCache(context: common.Context, mapping: Record<string, string>): void {
    const store = this.preferences(context);
    store.putSync(EMOJI_CACHE_KEY, JSON.stringify(mapping));
    store.putSync(EMOJI_CACHE_VERSION_KEY, CURRENT_EMOJI_CACHE_VERSION);
    store.flushSync();
  }

  private static async downloadStickerMapping(): Promise<Record<string, string>> {
    const payload = await ZhihuApi.getJson(EMOJI_API_URL);
    if (payload === null) {
      return {};
    }
    const stickers = this.arrayValue(this.objectValue(payload.data).stickers);
    const mapping: Record<string, string> = {};
    stickers.forEach((item: JsonValue) => {
      const sticker = this.objectValue(item);
      const placeholder = this.stringValue(sticker.placeholder).trim();
      const dataUrl = this.stringValue(sticker.static_image_url);
      if (placeholder.length > 0 && dataUrl.startsWith('data:image/')) {
        mapping[placeholder] = dataUrl;
      }
    });
    return mapping;
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
      const mapping = await this.downloadStickerMapping();
      this.stickerMapping = mapping;
      if (Object.keys(mapping).length > 0) {
        this.saveToCache(context, mapping);
      }
    } catch (_) {
      if (!this.loadFromCache(context, true)) {
        this.stickerMapping = {};
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
}
