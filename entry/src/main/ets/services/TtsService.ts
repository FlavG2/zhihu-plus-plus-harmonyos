/**
 * 文章朗读 TTS，使用鸿蒙原生 @kit.CoreSpeechKit（textToSpeech）。
 * 对照安卓 articleSpeechText / rememberArticleSpeechToggler：先把正文 HTML 剥成纯文本，
 * 按句号断句切成 ≤200 字 chunk（超长硬切），逐段 speak；每段 onComplete 后读下一段。
 */
import { textToSpeech } from '@kit.CoreSpeechKit';
import { stripHtmlToText } from '../utils/HtmlText';

export interface TtsCallbacks {
  onStateChange?: (speaking: boolean) => void;
  onError?: (message: string) => void;
}

/** 把长文本按句子边界切 chunk（对齐安卓「100 字分 chunk、按句号断句」，这里放宽到 200 字以减请求数） */
export function splitTtsChunks(text: string, maxLen: number = 200): string[] {
  if (text.length === 0) {
    return [];
  }
  const result: string[] = [];
  const rawParts = text.split(/([\n。！？!?；;])/);
  let current = '';
  const flush = (): void => {
    if (current.trim().length > 0) {
      result.push(current.trim());
    }
    current = '';
  };
  for (const part of rawParts) {
    if (part.length === 0) {
      continue;
    }
    if (current.length > 0 && current.length + part.length > maxLen) {
      flush();
    }
    if (part.length > maxLen) {
      let rest = part;
      while (rest.length > maxLen) {
        result.push(rest.slice(0, maxLen));
        rest = rest.slice(maxLen);
      }
      current = rest;
      continue;
    }
    current += part;
  }
  flush();
  return result.length > 0 ? result : [text];
}

export class TtsController {
  private engine?: textToSpeech.TextToSpeechEngine;
  private chunks: string[] = [];
  private index: number = 0;
  private speaking: boolean = false;
  private cancelled: boolean = false;
  private callbacks: TtsCallbacks = {};
  private readonly speakExtra: Record<string, Object> = {
    speed: 1,
    volume: 2,
    pitch: 1,
    languageContext: 'zh-CN',
    audioType: 'pcm',
    soundChannel: 3
  };

  get isSpeaking(): boolean {
    return this.speaking;
  }

  async start(context: object, articleTitle: string, contentHtml: string, callbacks: TtsCallbacks): Promise<void> {
    if (this.speaking) {
      return;
    }
    const plain = `${articleTitle}。${stripHtmlToText(contentHtml)}`;
    if (plain.trim().length === 0) {
      callbacks.onError?.('没有可朗读的内容');
      return;
    }
    this.chunks = splitTtsChunks(plain);
    this.index = 0;
    this.cancelled = false;
    this.speaking = true;
    this.callbacks = callbacks;
    callbacks.onStateChange?.(true);
    try {
      if (this.engine === undefined) {
        this.engine = await textToSpeech.createEngine({
          language: 'zh-CN',
          person: 0,
          online: 1,
          extraParams: { ...this.speakExtra }
        });
        this.engine.setListener({
          onStart: (_requestId: string) => {},
          onComplete: (_requestId: string) => this.onChunkComplete(),
          onStop: (_requestId: string) => {
            this.finish();
          },
          onError: (_requestId: string, _code: number, message: string) => {
            this.speaking = false;
            this.callbacks.onError?.(`朗读出错：${message}`);
            this.callbacks.onStateChange?.(false);
          }
        });
      }
      this.speakNext();
    } catch (e) {
      this.speaking = false;
      this.callbacks.onStateChange?.(false);
      this.callbacks.onError?.(e instanceof Error ? e.message : '朗读引擎初始化失败');
    }
  }

  private speakNext(): void {
    if (this.cancelled || this.index >= this.chunks.length) {
      this.finish();
      return;
    }
    const text = this.chunks[this.index];
    this.engine?.speak(text, {
      requestId: `zhihu_tts_${this.index}_${Date.now()}`,
      extraParams: { ...this.speakExtra }
    });
  }

  private onChunkComplete(): void {
    this.index += 1;
    if (this.cancelled) {
      this.finish();
      return;
    }
    if (this.index >= this.chunks.length) {
      this.finish();
      return;
    }
    this.speakNext();
  }

  private finish(): void {
    if (!this.speaking) {
      return;
    }
    this.speaking = false;
    this.callbacks.onStateChange?.(false);
  }

  stop(): void {
    this.cancelled = true;
    try {
      this.engine?.stop();
    } catch (_e) {
      // 忽略
    }
    this.speaking = false;
    this.callbacks.onStateChange?.(false);
  }

  shutdown(): void {
    this.stop();
    try {
      this.engine?.shutdown();
    } catch (_e) {
      // 忽略
    }
    this.engine = undefined;
  }
}
