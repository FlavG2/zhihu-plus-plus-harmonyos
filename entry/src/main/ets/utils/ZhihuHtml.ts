function replaceBreaks(html: string): string {
  return html
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n\n')
    .replace(/<\/div>/gi, '\n')
    .replace(/<\/li>/gi, '\n');
}

function protocolizeUrl(url: string): string {
  if (url.startsWith('//')) {
    return `https:${url}`;
  }
  return url;
}

/**
 * 知乎正文里部分图片 URL 带 veImageX 处理参数（形如
 * /50/v2-xxxx~resize:720:q75_720w.jpg），该格式在 CDN 上**无论带不带 UA 都返回 404**；
 * 还原成标准宽度后缀（_720w.jpg）才返回 200。
 * curl 实测（2026-08-30，带移动端 UA）：
 *   /50/v2-xxx~resize:720:q75_720w.jpg -> 404 (image/x-empty)
 *   /50/v2-xxx_720w.jpg                -> 200 (image/jpeg)
 *   /v2-xxx.jpg                        -> 200 (image/jpeg)
 * 故剥离 `~resize:<宽>:q<质量>` 处理参数段，保留后面的标准宽度后缀。
 */
function normalizeImageUrl(url: string): string {
  // 注意：捕获组已包含前导下划线（_720w.jpg），替换串不可再补下划线，否则会出现 __720w.jpg 再次 404。
  return url.replace(/~resize:[^/]*?(_\d+w\.(?:jpg|jpeg|png|gif|webp))/gi, '$1');
}

/** 格式化计数（万单位），用于摘要卡片 */
function fmtCounter(value: number, unit: string): string {
  if (value >= 10000) {
    return `${(value / 10000).toFixed(value >= 100000 ? 0 : 1)} 万${unit}`;
  }
  return `${value} ${unit}`;
}

/** 格式化时间戳（秒）为可读日期 */
function fmtTime(seconds: number): string {
  if (seconds <= 0) return '';
  const d = new Date(seconds * 1000);
  const y = d.getFullYear();
  const M = `${d.getMonth() + 1}`.padStart(2, '0');
  const D = `${d.getDate()}`.padStart(2, '0');
  const h = `${d.getHours()}`.padStart(2, '0');
  const m = `${d.getMinutes()}`.padStart(2, '0');
  return `${y}-${M}-${D} ${h}:${m}`;
}

function firstImageCandidate(attributes: string): string {
  const candidates = [
    /(?:data-actualsrc|data-original|data-src|data-lazy-src|data-default-watermark-src|data-fullsrc)=["']([^"']+)["']/i,
    /(?:src)=["']([^"']+)["']/i
  ];
  for (const pattern of candidates) {
    const match = attributes.match(pattern);
    if (match !== null && typeof match[1] === 'string') {
      const candidate = normalizeImageUrl(protocolizeUrl(match[1].trim()));
      if (candidate.length > 0
        && candidate !== 'about:blank'
        && !candidate.startsWith('data:image/gif;base64,R0lGOD')
        && !candidate.startsWith('data:image/svg+xml')) {
        return candidate;
      }
    }
  }
  return '';
}

export function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&nbsp;/gi, ' ')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, '\'')
    .replace(/&amp;/gi, '&');
}

export function stripHtmlToText(html: string): string {
  return decodeHtmlEntities(replaceBreaks(html).replace(/<[^>]+>/g, ''))
    .replace(/\r/g, '')
    .replace(/\n{3,}/g, '\n\n')
    .replace(/[ \t]+\n/g, '\n')
    .trim();
}

export function extractFirstImageUrl(html: string): string {
  // 兼容 <a href="..." class="comment_img"> 和 <img src="...">
  const anchorMatch = html.match(/<(?:a|img)[^>]+(?:href|src)=["']([^"']+)/i);
  if (anchorMatch !== null && typeof anchorMatch[1] === 'string') {
    return protocolizeUrl(anchorMatch[1]);
  }
  return '';
}

/** 从 HTML 中移除图片链接标签（防止 "查看图片" 等文字残留在纯文本中） */
export function stripCommentImageLinks(html: string): string {
  return html.replace(/<a[^>]+class=["'](?:comment_img|comment_gif|comment_sticker)[^>]*>[^<]*<\/a>/gi, '');
}

export function htmlToDataUrl(html: string): string {
  return `data:text/html;charset=utf-8,${encodeURIComponent(html)}`;
}

/**
 * 把一段 <style> 注入 HTML：优先插到 <head> 之后，没有 head 则置于文档开头。
 * 用途：把阅读体验 CSS 变量随文档一起交给 WebView 解析，首帧即生效，
 * 避免「渲染完再由脚本改值」造成的字号跳动。
 */
export function injectStyleIntoHtml(html: string, style: string): string {
  const headMatch = html.match(/<head\b[^>]*>/i);
  if (headMatch !== null && headMatch.index !== undefined) {
    const end: number = headMatch.index + headMatch[0].length;
    return html.substring(0, end) + style + html.substring(end);
  }
  return style + html;
}

export function normalizeRichContentHtml(html: string): string {
  if (html.trim().length === 0) {
    return html;
  }

  const normalizedLinks = html.replace(
    /\b(src|href|poster)=["']\/\/([^"']+)["']/gi,
    (_match: string, attribute: string, path: string): string => {
      return `${attribute}="https://${path}"`;
    }
  );

  return normalizedLinks.replace(/<img\b([^>]*)>/gi, (match: string, attributes: string): string => {
    const normalizedSrc = firstImageCandidate(attributes);
    let nextAttributes = attributes
      .replace(/\sloading=["'][^"']*["']/gi, '')
      .replace(/\ssrc=["'][^"']*["']/gi, '');
    if (normalizedSrc.length > 0) {
      nextAttributes += ` src="${escapeHtml(normalizedSrc)}"`;
    }
    return `<img${nextAttributes}>`;
  });
}

export function paragraphizeText(text: string): string {
  if (text.trim().length === 0) {
    return '';
  }
  return text
    .split(/\n{2,}/)
    .map((paragraph: string) => `<p>${escapeHtml(paragraph).replace(/\n/g, '<br/>')}</p>`)
    .join('');
}

export interface ArticleSummaryData {
  questionId: string;
  questionTitle: string;
  authorName: string;
  authorAvatar: string;
  authorHeadline: string;
  authorUrlToken: string;
  voteCount: number;
  canVote: boolean;
  commentCount: number;
  updatedTime: number;
  createdTime: number;
  ipInfo: string;
}

export function buildArticleHtmlDocument(
  title: string,
  contentHtml: string,
  sourceUrl: string,
  initialThemeMode: 'light' | 'dark' = 'light',
  summary?: ArticleSummaryData,
  topSafeAreaVp: number = 0,
  paddingBottomVp: number = 100,
  minHeightVh: number = 100,
  headerHtml?: string,
  segmentJson?: string
): string {
  const safeTitle = escapeHtml(title);
  const safeSourceUrl = escapeHtml(sourceUrl);
  const safeThemeMode = initialThemeMode === 'dark' ? 'dark' : 'light';

  // 摘要卡片 HTML（注入到正文前方，随内容一起滚动，不遮挡）
  const summaryHtml: string = (summary !== undefined) ? `
    <div class="zhihu-summary-card">
      <h1 class="zhihu-summary-title"><a href="zhihu://openQuestion?id=${encodeURIComponent(summary.questionId)}" style="color:inherit;text-decoration:none">${escapeHtml(summary.questionTitle.length > 0 ? summary.questionTitle : title)}</a></h1>
      <div class="zhihu-summary-author">
        ${(summary.authorAvatar.length > 0)
    ? `<a href="zhihu://openPerson?urlToken=${encodeURIComponent(summary.authorUrlToken)}"><img class="zhihu-summary-avatar" src="${escapeHtml(summary.authorAvatar)}" alt="" referrerpolicy="no-referrer" data-zhihu-ignore-image-click="true" /></a>`
    : `<a href="zhihu://openPerson?urlToken=${encodeURIComponent(summary.authorUrlToken)}"><span class="zhihu-summary-avatar zhihu-summary-avatar-fallback">${escapeHtml(summary.authorName.slice(0, 1) || '知')}</span></a>`}
        <div style="flex:1;min-width:0">
          <a href="zhihu://openPerson?urlToken=${encodeURIComponent(summary.authorUrlToken)}" style="color:inherit;text-decoration:none"><p class="zhihu-summary-author-name">${escapeHtml(summary.authorName)}</p></a>
          ${summary.authorHeadline.length > 0
    ? `<p class="zhihu-summary-author-headline">${escapeHtml(summary.authorHeadline)}</p>`
    : ''}
        </div>
      </div>
      <div class="zhihu-summary-meta">
        <span>${fmtCounter(summary.voteCount, summary.canVote ? '赞同' : '喜欢')}</span>
        <span>${fmtCounter(summary.commentCount, '评论')}</span>
        <span>${fmtTime(summary.updatedTime || summary.createdTime)}</span>
        ${summary.ipInfo.length > 0 ? `<span>${escapeHtml(summary.ipInfo)}</span>` : ''}
      </div>
    </div>
  ` : '';

  return `<!DOCTYPE html>
<html lang="zh-CN" data-ark-theme="${safeThemeMode}">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
    <base href="${safeSourceUrl}">
    <title>${safeTitle}</title>
    <style>
      :root {
        color-scheme: light dark;
        --page-bg: #f5f7fb;
        --card-bg: #ffffff;
        --text-primary: #111827;
        --text-secondary: #475467;
        --border: #e5ecf3;
        --link: #1d4ed8;
        --blockquote-bg: #f8fafc;
        --code-bg: #eff4fb;
        --target-ring: rgba(29, 78, 216, 0.16);
        --accent-soft: rgba(29, 78, 216, 0.10);
      }
      * {
        box-sizing: border-box;
      }
      html {
        height: 100%;
        background: var(--page-bg);
        touch-action: pan-y;
        overscroll-behavior-x: none;
      }
      body {
        margin: 0;
        padding: 0;
        min-height: 100%;
        background: var(--page-bg);
        color: var(--text-primary);
        font-family: "Noto Serif SC", "Source Han Serif SC", serif;
        line-height: 1.72;
        touch-action: pan-y;
      }
      #zhihu-body-root {
        background: var(--page-bg);
        margin: 0;
        padding: ${topSafeAreaVp > 0 ? topSafeAreaVp + 'px 18px ' + paddingBottomVp + 'px' : '18px 18px ' + paddingBottomVp + 'px'};
        min-height: ${minHeightVh}vh;
        overflow: hidden;
      }
      .zhihu-answer-end {
        margin: 24px 4px 12px;
        padding-top: 18px;
        border-top: 1px solid var(--border);
        text-align: center;
        font-size: 13px;
        color: var(--text-secondary);
        letter-spacing: 1px;
      }
      .zhihu-summary-card {
        margin-bottom: 18px;
        padding-bottom: 18px;
        border-bottom: 1px solid var(--border);
      }
      .zhihu-summary-title {
        margin: 0;
        font-size: 28px;
        line-height: 1.35;
        font-weight: 700;
        padding-right: 40px;
      }
      .zhihu-summary-badge {
        display: inline-flex;
        margin-top: 8px;
        padding: 2px 10px;
        border-radius: 999px;
        background: var(--accent-soft);
        color: var(--link);
        font-size: 12px;
      }
      .zhihu-summary-author {
        display: flex;
        align-items: center;
        gap: 12px;
        margin-top: 18px;
      }
      .zhihu-summary-avatar {
        width: 44px;
        height: 44px;
        border-radius: 999px;
        object-fit: cover;
        flex: 0 0 auto;
        pointer-events: none;
      }
      .zhihu-summary-avatar-fallback {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        background: var(--accent-soft);
        color: var(--link);
        font-weight: 700;
      }
      .zhihu-summary-author-name {
        margin: 0;
        font-size: 15px;
        font-weight: 600;
      }
      .zhihu-summary-author-headline {
        margin: 2px 0 0;
        font-size: 12px;
        line-height: 1.5;
        color: var(--text-secondary);
      }
      .zhihu-summary-meta {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
        margin-top: 16px;
        font-size: 12px;
        color: var(--text-secondary);
      }
      #zhihu-body-content {
        display: block;
        margin: 0;
        padding: 0;
        /* 阅读体验：字号 / 行高由设置页注入的 CSS 变量驱动，带默认值 */
        font-size: calc(17px * var(--reader-font-scale, 1));
        line-height: var(--reader-line-height, 1.72);
      }
      #zhihu-body-content h1,
      #zhihu-body-content h2,
      #zhihu-body-content h3,
      #zhihu-body-content h4 {
        font-size: calc(1.25em * var(--reader-font-scale, 1));
        line-height: var(--reader-line-height, 1.72);
      }
      #zhihu-body-content p {
        margin-top: 0;
        margin-bottom: calc(1em * var(--reader-para-spacing, 1));
      }
      #zhihu-body-content > :first-child {
        margin-top: 0;
      }
      #zhihu-body-content > :last-child {
        margin-bottom: 0;
      }
      /* 隐藏正文里 Zhihu 服务端带的赞同/评论时间/IP 元数据（避免与 ActionBar / SummaryCard 顶部重复） */
      .ContentItem-meta,
      .RichText .RichText-AuthorInfo,
      [class*="voteup"],
      [class*="meta-item"] {
        display: none !important;
      }
      #zhihu-body-sentinel {
        display: block;
        width: 100%;
        height: 1px;
        margin: 0;
        padding: 0;
        opacity: 0;
        pointer-events: none;
      }
      #zhihu-body-root > :first-child {
        margin-top: 0;
      }
      #zhihu-body-root > :last-child {
        margin-bottom: 0;
      }
      img, video {
        max-width: 100%;
        height: auto;
        border-radius: 14px;
      }
      img.zhihu-emoji {
        width: 1.35em;
        height: 1.35em;
        max-width: none;
        display: inline-block;
        margin: 0 0.04em;
        vertical-align: -0.24em;
        border-radius: 0;
      }
      pre, code {
        white-space: pre-wrap;
        word-break: break-word;
      }
      blockquote {
        margin: 16px 0;
        padding: 10px 14px;
        border-left: 3px solid var(--border);
        background: var(--blockquote-bg);
        color: var(--text-secondary);
      }
      pre {
        overflow-x: auto;
        padding: 12px 14px;
        border-radius: 14px;
        background: var(--blockquote-bg);
      }
      a {
        color: var(--link);
        text-decoration: none;
      }
      /* 划线片段：正文里的虚线下划线句子；有评论时用橙色虚线对齐安卓/知乎原版 */
      .highlight-wrap {
        border-bottom: 1px dashed var(--text-secondary);
        cursor: pointer;
        border-radius: 2px;
      }
      .highlight-wrap.has-comments {
        border-bottom-color: #ff7d00;
      }
      code {
        padding: 0.08em 0.28em;
        border-radius: 6px;
        background: var(--code-bg);
      }
      pre code {
        padding: 0;
        border-radius: 0;
        background: transparent;
      }
      /* 公式（MathJax / KaTeX）跟随主题色，避免深色模式下黑字看不清。
         用 !important 是因为 MathJax 常把 color:#000 写成内联 style，普通选择器压不过；
         用 inherit 则自动跟随 body 的 --text-primary，主题切换零成本。 */
      mjx-container,
      mjx-container *,
      .MathJax,
      .MathJax_Display,
      .MathJax_Inline,
      .katex,
      .katex *,
      [data-math],
      .math-formula {
        color: inherit !important;
      }
      table {
        width: 100%;
        border-collapse: collapse;
      }
      th, td {
        border: 1px solid var(--border);
        padding: 8px;
      }
      .zhihu-footnote-target {
        animation: zhihu-footnote-flash 1.25s ease;
        box-shadow: 0 0 0 10px var(--target-ring);
      }
      @keyframes zhihu-footnote-flash {
        0% {
          box-shadow: 0 0 0 0 var(--target-ring);
        }
        100% {
          box-shadow: 0 0 0 10px rgba(0, 0, 0, 0);
        }
      }
      html[data-ark-theme="dark"] {
        --page-bg: #0f141a;
        --card-bg: #18212b;
        --text-primary: #f3f7fd;
        --text-secondary: #a4b0bf;
        --border: #243242;
        --link: #a9c7ff;
        --blockquote-bg: #111a22;
        --code-bg: #111a22;
        --target-ring: rgba(169, 199, 255, 0.2);
        --accent-soft: rgba(169, 199, 255, 0.14);
      }
      html[data-ark-theme="light"] {
        --page-bg: #f5f7fb;
        --card-bg: #ffffff;
        --text-primary: #111827;
        --text-secondary: #475467;
        --border: #e5ecf3;
        --link: #1d4ed8;
        --blockquote-bg: #f8fafc;
        --code-bg: #eff4fb;
        --target-ring: rgba(29, 78, 216, 0.16);
        --accent-soft: rgba(29, 78, 216, 0.10);
      }
      @media (prefers-color-scheme: dark) {
        html:not([data-ark-theme]) {
          --page-bg: #0f141a;
          --card-bg: #18212b;
          --text-primary: #f3f7fd;
          --text-secondary: #a4b0bf;
          --border: #243242;
          --link: #a9c7ff;
          --blockquote-bg: #111a22;
          --code-bg: #111a22;
          --target-ring: rgba(169, 199, 255, 0.2);
          --accent-soft: rgba(169, 199, 255, 0.14);
        }
      }
    </style>
  </head>
  <body data-source-url="${safeSourceUrl}">
    <article id="zhihu-body-root" data-zhihu-body="true">${(headerHtml !== undefined && headerHtml.length > 0) ? headerHtml : summaryHtml}<div id="zhihu-body-content">${contentHtml}</div>      <div class="zhihu-answer-end" role="separator">—— 已到底部 ——</div><div id="zhihu-body-sentinel" aria-hidden="true"></div></article>
${(segmentJson !== undefined && segmentJson.length > 0) ? `\n    <script type="application/json" id="zhihu-segment-data">${segmentJson.replace(/<\/script/gi, '<\\/script')}</script>` : ''}
  </body>
</html>`;
}

/** 想法页作者卡片 HTML：注入正文前方，与正文同属一个 DOM 树，随 WebView 一起滚动/隐藏 */
export function buildPinSummaryHtml(pin: {
  author: { name: string; avatarUrl: string; headline: string; urlToken: string };
  likeCount: number;
  commentCount: number;
  createdTime: number;
  updatedTime: number;
}): string {
  const a = pin.author;
  const time = fmtTime(pin.updatedTime || pin.createdTime);
  const avatar = a.avatarUrl.length > 0
    ? `<a href="zhihu://openPerson?urlToken=${encodeURIComponent(a.urlToken)}"><img class="zhihu-summary-avatar" src="${escapeHtml(a.avatarUrl)}" alt="" referrerpolicy="no-referrer" data-zhihu-ignore-image-click="true" /></a>`
    : `<a href="zhihu://openPerson?urlToken=${encodeURIComponent(a.urlToken)}"><span class="zhihu-summary-avatar zhihu-summary-avatar-fallback">${escapeHtml(a.name.slice(0, 1) || '知')}</span></a>`;
  return `
    <div class="zhihu-summary-card">
      <div class="zhihu-summary-author">
        ${avatar}
        <div style="flex:1;min-width:0">
          <a href="zhihu://openPerson?urlToken=${encodeURIComponent(a.urlToken)}" style="color:inherit;text-decoration:none"><p class="zhihu-summary-author-name">${escapeHtml(a.name)}</p></a>
          ${a.headline.length > 0 ? `<p class="zhihu-summary-author-headline">${escapeHtml(a.headline)}</p>` : ''}
        </div>
      </div>
      <div class="zhihu-summary-meta">
        <span>${fmtCounter(pin.likeCount, '赞同')}</span>
        <span>${fmtCounter(pin.commentCount, '评论')}</span>
        ${time.length > 0 ? `<span>${escapeHtml(time)}</span>` : ''}
      </div>
    </div>
  `;
}
