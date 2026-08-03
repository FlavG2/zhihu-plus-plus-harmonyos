/**
 * 轻量 HTML 文本工具：去标签取纯文本（TTS/兜底）、HTML→Markdown（复制 Markdown）、URL 规整、文件名清洗。
 * 对照安卓 ArticleExportCommonUtils.kt / articleSpeechText 的知乎标签集固定子集实现。
 */

/** 把协议相对 / 相对地址规整为可访问的绝对地址 */
export function normalizeUrl(url: string): string {
  if (!url) {
    return url;
  }
  if (url.startsWith('//')) {
    return `https:${url}`;
  }
  if (url.startsWith('/')) {
    return `https://www.zhihu.com${url}`;
  }
  return url;
}

const NAMED_ENTITIES: Record<string, string> = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&apos;': "'",
  '&nbsp;': ' ',
  '&hellip;': '…',
  '&mdash;': '—',
  '&ndash;': '–',
  '&ldquo;': '“',
  '&rdquo;': '”',
  '&lsquo;': '‘',
  '&rsquo;': '’'
};

export function decodeHtmlEntities(text: string): string {
  if (!text) {
    return '';
  }
  let result = text.replace(/&#(\d+);/g, (_m: string, code: string) => {
    const value = Number(code);
    return isNaN(value) ? _m : String.fromCodePoint(value);
  });
  result = result.replace(/&#x([0-9a-fA-F]+);/g, (_m: string, code: string) => {
    const value = parseInt(code, 16);
    return isNaN(value) ? _m : String.fromCodePoint(value);
  });
  for (const [entity, char] of Object.entries(NAMED_ENTITIES)) {
    result = result.split(entity).join(char);
  }
  return result;
}

function stripTags(html: string): string {
  return html.replace(/<[^>]+>/g, '');
}

/** 去除 script/style/noscript，<br>、块级结束标签转换行，再剥标签、解码实体、压缩空白 */
export function stripHtmlToText(html: string): string {
  if (!html) {
    return '';
  }
  let s = html;
  s = s.replace(/<script[\s\S]*?<\/script>/gi, ' ');
  s = s.replace(/<style[\s\S]*?<\/style>/gi, ' ');
  s = s.replace(/<noscript[\s\S]*?<\/noscript>/gi, ' ');
  s = s.replace(/<\s*(br|\/p|\/div|\/li|\/h[1-6]|blockquote|\/blockquote)\s*>/gi, '\n');
  s = s.replace(/<[^>]+>/g, '');
  s = decodeHtmlEntities(s);
  s = s.replace(/[ \t]+/g, ' ');
  s = s.replace(/\n{3,}/g, '\n\n');
  return s.trim();
}

/** 轻量 HTML→Markdown 转换（知乎正文常见标签子集） */
export function htmlToMarkdown(html: string): string {
  if (!html) {
    return '';
  }
  let s = html;
  s = s.replace(/<script[\s\S]*?<\/script>/gi, '');
  s = s.replace(/<style[\s\S]*?<\/style>/gi, '');
  s = s.replace(/<noscript[\s\S]*?<\/noscript>/gi, '');

  // 图片：![alt](url)
  s = s.replace(/<img\b[^>]*?>/gi, (tag: string) => {
    const srcMatch = tag.match(/\bsrc="([^"]*)"/i) ?? tag.match(/\bdata-src="([^"]*)"/i);
    const altMatch = tag.match(/\balt="([^"]*)"/i);
    const src = srcMatch ? normalizeUrl(srcMatch[1]) : '';
    const alt = altMatch ? altMatch[1] : '';
    if (!src) {
      return '';
    }
    return ` ![](${src}) `;
  });

  // 链接：[text](url)
  s = s.replace(/<a\b[^>]*\bhref="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi, (_m: string, href: string, inner: string) => {
    return `[${stripTags(inner)}](${normalizeUrl(href)})`;
  });

  // 加粗 / 斜体
  s = s.replace(/<(strong|b)\b[^>]*>([\s\S]*?)<\/\1>/gi, '**$2**');
  s = s.replace(/<(em|i)\b[^>]*>([\s\S]*?)<\/\1>/gi, '*$2*');

  // 行内代码
  s = s.replace(/<code\b[^>]*>([\s\S]*?)<\/code>/gi, '`$1`');

  // 标题
  s = s.replace(/<h1\b[^>]*>([\s\S]*?)<\/h1>/gi, '\n# $1\n');
  s = s.replace(/<h2\b[^>]*>([\s\S]*?)<\/h2>/gi, '\n## $1\n');
  s = s.replace(/<h3\b[^>]*>([\s\S]*?)<\/h3>/gi, '\n### $1\n');
  s = s.replace(/<h4\b[^>]*>([\s\S]*?)<\/h4>/gi, '\n#### $1\n');
  s = s.replace(/<h5\b[^>]*>([\s\S]*?)<\/h5>/gi, '\n##### $1\n');
  s = s.replace(/<h6\b[^>]*>([\s\S]*?)<\/h6>/gi, '\n###### $1\n');

  // 引用块
  s = s.replace(/<blockquote\b[^>]*>([\s\S]*?)<\/blockquote>/gi, (_m: string, inner: string) => {
    const lines = stripHtmlToText(inner).split('\n');
    return '\n' + lines.map((line: string) => `> ${line}`).join('\n') + '\n';
  });

  // 列表项
  s = s.replace(/<li\b[^>]*>([\s\S]*?)<\/li>/gi, (_m: string, inner: string) => {
    return `\n- ${stripHtmlToText(inner)}`;
  });

  // 段落 / 换行
  s = s.replace(/<\s*\/\s*p\b[^>]*>/gi, '');
  s = s.replace(/<\s*p\b[^>]*>/gi, '\n\n');
  s = s.replace(/<br\s*\/?>/gi, '\n');

  // 剩余标签
  s = s.replace(/<[^>]+>/g, '');
  s = decodeHtmlEntities(s);
  s = s.replace(/[ \t]+/g, ' ');
  s = s.replace(/\n{3,}/g, '\n\n');
  return s.trim();
}

/** 清洗文件名中的非法字符（对齐安卓 sanitizeArticleExportFileNamePart） */
export function sanitizeFileName(text: string): string {
  return text
    .trim()
    .replace(/\s+/g, '_')
    .replace(/[\\/:*?"<>|]/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_+|_+$/g, '');
}
