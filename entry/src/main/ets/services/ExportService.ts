/**
 * 导出文章：HTML（图片内联 base64）、带评论导出、复制 Markdown。
 * 对照安卓 ArticleExportCommonUtils.kt / article_export_template.html。
 * HTML 模板直接内联为常量（避免 rawfile 资源管线）；图片下载转 base64 内联，失败则保留原链接。
 */
import common from '@ohos.app.ability.common';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { pasteboard, zlib } from '@kit.BasicServicesKit';
import { escapeHtml } from '../utils/ZhihuHtml';
import { normalizeUrl, sanitizeFileName, htmlToMarkdown } from '../utils/HtmlText';
import { ZhihuCommentItem } from '../models/ZhihuContentModels';
import { formatTimestamp } from '../utils/Time';
import { ArticleDetailService } from './ArticleDetailService';
import { HomeFeedItem } from '../models/ZhihuModels';

export interface ArticleExportMeta {
  readonly title: string;
  readonly authorName: string;
  readonly authorBio: string;
  readonly authorAvatarSrc: string;
  readonly voteUpCount: number;
  readonly commentCount: number;
  readonly contentHtml: string;
  readonly createdEpochSeconds: number;
  readonly updatedEpochSeconds: number;
  readonly contentId: string;
  readonly contentType: 'answer' | 'article' | 'pin';
}

const EXPORT_TEMPLATE: string = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        :root { color-scheme: light; }
        * { box-sizing: border-box; }
        html, body {
            margin: 0; padding: 0; background: #f5f7fb; color: #0f172a;
            font-family: 'PingFang SC', 'Helvetica Neue', STHeiti, 'Microsoft Yahei', sans-serif;
        }
        body { padding: 20px 16px 32px; }
        .page {
            width: 100%; max-width: 720px; margin: 0 auto; padding: 28px 20px 36px;
            border-radius: 24px; background: #ffffff; box-shadow: 0 18px 60px rgba(15, 23, 42, 0.08);
        }
        .title { margin: 0 0 24px; font-size: 30px; line-height: 1.35; font-weight: 700; }
        .author-card { display: flex; align-items: center; gap: 14px; padding-bottom: 20px; border-bottom: 1px solid #e2e8f0; }
        .author-avatar { width: 56px; height: 56px; border-radius: 999px; object-fit: cover; flex: 0 0 auto; background: #e2e8f0; }
        .author-avatar-placeholder { border: 1px solid #cbd5e1; }
        .author-name { font-size: 17px; font-weight: 600; line-height: 1.3; }
        .author-bio { margin-top: 6px; font-size: 13px; line-height: 1.5; color: #64748b; }
        .stats { display: flex; flex-wrap: wrap; gap: 12px; margin: 20px 0 26px; }
        .stat-chip {
            display: inline-flex; align-items: center; gap: 8px; min-height: 40px; padding: 10px 14px;
            border-radius: 999px; background: #eff6ff; color: #1d4ed8; font-size: 15px; font-weight: 700; line-height: 1;
        }
        .stat-chip-value { color: #1e3a8a; letter-spacing: 0.01em; }
        .content { font-size: 18px; line-height: 1.9; color: #1e293b; }
        .content p, .content li, .content blockquote { margin: 0 0 1em; }
        .content img { display: block; max-width: 100%; height: auto; margin: 16px auto; background: #fff; }
        .content figure { margin: 18px 0; }
        .content pre, .content code { white-space: pre-wrap; word-break: break-word; }
        .content a { color: #2563eb; word-break: break-all; }
        .comments-title { margin: 36px 0 18px; font-size: 22px; font-weight: 700; }
        .comment { margin-bottom: 16px; padding: 16px; border-radius: 16px; background: #f8fafc; border-left: 4px solid #2563eb; }
        .comment-author { margin-bottom: 6px; color: #1d4ed8; font-weight: 600; }
        .comment-content { color: #334155; line-height: 1.7; }
        .comment-content p { margin: 0 0 0.75em; }
        .comment-content p:last-child { margin-bottom: 0; }
        .comment-image { display: block; width: auto; max-width: min(100%, 240px); max-height: 240px; margin-top: 10px; border-radius: 12px; background: #e2e8f0; }
        .comment-time { margin-top: 8px; font-size: 12px; color: #64748b; }
        .export-footer { margin-top: 32px; padding-top: 20px; border-top: 1px solid #e2e8f0; }
        .export-footer-line { font-size: 13px; line-height: 1.6; color: #64748b; }
        .export-credit-brand { color: #66ccff; font-weight: 700; }
        .export-credit { margin: 8px 0 0; font-size: 12px; line-height: 1.6; color: #94a3b8; word-break: break-all; }
        .is-hidden { display: none !important; }
        @page { margin: 12mm 10mm; }
        @media print {
            html, body { background: #ffffff; }
            body { padding: 0; }
            .page { max-width: none; margin: 0; padding: 0; border-radius: 0; background: #ffffff; box-shadow: none; }
            .title, .author-card, .stats, .content figure, .content img, .comment, .export-footer { break-inside: avoid; page-break-inside: avoid; }
        }
    </style>
</head>
<body>
    <main class="page">
        <h1 class="title">{{title}}</h1>
        <section class="author-card">
            {{authorAvatar}}
            <div>
                <div class="author-name">{{authorName}}</div>
                {{authorBio}}
            </div>
        </section>
        <section class="stats">
            <div class="stat-chip"><span class="stat-chip-value">{{voteCount}}</span></div>
            <div class="stat-chip"><span class="stat-chip-value">{{commentCount}}</span></div>
        </section>
        <article class="content RichContent-inner">
            {{bodyHtml}}
        </article>
        {{extraSections}}
        <footer class="export-footer">
            <div class="export-footer-line">{{exportedDate}}</div>
            <div class="export-footer-line">{{publishedDate}}</div>
            <div class="{{editedDateClass}}">{{editedDate}}</div>
            <p class="{{appAttributionClass}}">
                本回答使用<span class="export-credit-brand">知乎++</span>导出，这是一个完全开源的去广告免费知乎第三方客户端，请点个star吧！（GitHub地址：{{githubUrl}}）
            </p>
        </footer>
    </main>
</body>
</html>`;

const GITHUB_URL = 'https://github.com/zly2006/zhihu-plus-plus';

function formatDate(epochMillis: number): string {
  const d = new Date(epochMillis);
  const p = (n: number): string => n.toString().padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

function formatTimestampForFile(epochMillis: number): string {
  const d = new Date(epochMillis);
  const p = (n: number): string => n.toString().padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

function escapeAttr(text: string): string {
  return escapeHtml(text);
}

function prepareBodyHtml(contentHtml: string): string {
  let s = contentHtml;
  s = s.replace(/<noscript[\s\S]*?<\/noscript>/gi, '');
  // 规整图片/链接地址为绝对地址，去掉懒加载属性
  s = s.replace(/<img\b[^>]*>/gi, (tag: string) => {
    let t = tag;
    const srcMatch = t.match(/\bsrc="([^"]*)"/i) ?? t.match(/\bdata-src="([^"]*)"/i);
    if (srcMatch) {
      const norm = normalizeUrl(srcMatch[1]);
      if (/\bsrc="/i.test(t)) {
        t = t.replace(/\bsrc="[^"]*"/i, `src="${norm}"`);
      } else {
        t = t.replace(/\bdata-src="[^"]*"/i, `src="${norm}"`);
      }
    }
    t = t.replace(/\sclass="[^"]*lazy[^"]*"/i, '');
    t = t.replace(/\bsrcset="[^"]*"/i, '');
    t = t.replace(/\bsizes="[^"]*"/i, '');
    t = t.replace(/\bloading="[^"]*"/i, 'loading="eager"');
    return t;
  });
  s = s.replace(/<a\b[^>]*\bhref="\/\/[^"]*"/gi, (tag: string) => tag.replace(/href="\/\//i, 'href="https://'));
  return s;
}

function renderTemplate(
  meta: ArticleExportMeta,
  bodyHtml: string,
  extraSectionsHtml: string,
  includeAppAttribution: boolean = true
): string {
  const exportedEpoch = Date.now();
  const authorAvatarHtml = meta.authorAvatarSrc
    ? `<img class="author-avatar" src="${escapeAttr(normalizeUrl(meta.authorAvatarSrc))}" alt="作者头像" />`
    : `<div class="author-avatar author-avatar-placeholder"></div>`;
  const authorBioHtml = meta.authorBio
    ? `<div class="author-bio">${escapeAttr(meta.authorBio)}</div>`
    : '';

  const publishedDate =
    meta.createdEpochSeconds > 0 ? `发布日期：${formatDate(meta.createdEpochSeconds * 1000)}` : '';
  const editedDate =
    meta.updatedEpochSeconds > 0 && meta.updatedEpochSeconds !== meta.createdEpochSeconds
      ? `编辑日期：${formatDate(meta.updatedEpochSeconds * 1000)}`
      : '';

  const placeholders: Record<string, string> = {
    '{{title}}': escapeAttr(meta.title),
    '{{authorAvatar}}': authorAvatarHtml,
    '{{authorName}}': escapeAttr(meta.authorName),
    '{{authorBio}}': authorBioHtml,
    '{{voteCount}}': meta.voteUpCount.toString(),
    '{{commentCount}}': meta.commentCount.toString(),
    '{{bodyHtml}}': bodyHtml,
    '{{extraSections}}': extraSectionsHtml,
    '{{exportedDate}}': `导出日期：${formatDate(exportedEpoch)}`,
    '{{publishedDate}}': publishedDate,
    '{{editedDate}}': editedDate,
    '{{editedDateClass}}': editedDate ? 'export-footer-line' : 'export-footer-line is-hidden',
    '{{appAttributionClass}}': includeAppAttribution ? 'export-credit' : 'export-credit is-hidden',
    '{{githubUrl}}': GITHUB_URL
  };
  let html = EXPORT_TEMPLATE;
  for (const [key, value] of Object.entries(placeholders)) {
    html = html.split(key).join(value);
  }
  return html;
}

export function buildCommentsHtml(comments: ZhihuCommentItem[], requestedCount?: number): string {
  if (comments.length === 0) {
    return '';
  }
  const titleSuffix =
    requestedCount && requestedCount > 0 ? ` (前 ${Math.min(requestedCount, comments.length)} 条)` : '';
  const items = comments
    .map((comment: ZhihuCommentItem) => {
      const imageHtml = comment.previewImageUrl
        ? `<img class="comment-image" src="${escapeAttr(normalizeUrl(comment.previewImageUrl))}" alt="评论图片" />`
        : '';
      const timeText = formatTimestamp(new Date(comment.createdTime * 1000));
      return `<div class="comment">
    <div class="comment-author">${escapeAttr(comment.author.name)}</div>
    <div class="comment-content">${comment.contentHtml}</div>
    ${imageHtml}
    <div class="comment-time">${escapeAttr(timeText)}</div>
</div>`;
    })
    .join('\n');
  return `<div class='comments-title'>热门评论${titleSuffix}</div>\n${items}`;
}

function guessImageMime(contentTypeHeader: string | undefined, url: string, bytes: Uint8Array): string {
  const ct = contentTypeHeader ? contentTypeHeader.split(';')[0]?.trim() : undefined;
  if (ct && ct.startsWith('image/')) {
    return ct;
  }
  const ext = url.split('?')[0].split('#')[0].split('.').pop()?.toLowerCase() ?? '';
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'bmp':
      return 'image/bmp';
    case 'svg':
      return 'image/svg+xml';
    case 'avif':
      return 'image/avif';
    default:
      break;
  }
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) {
    return 'image/png';
  }
  return 'image/jpeg';
}

async function fetchImageDataUrl(url: string): Promise<string> {
  const client = http.createHttp();
  try {
    const res = await client.request(normalizeUrl(url), {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    });
    if (res.responseCode < 200 || res.responseCode >= 300) {
      return url;
    }
    const buf = res.result as ArrayBuffer;
    const bytes = new Uint8Array(buf);
    if (bytes.length === 0) {
      return url;
    }
    const headerObj = (res.header ?? {}) as Record<string, Object>;
    const contentTypeHeader =
      (typeof headerObj['Content-Type'] === 'string'
        ? (headerObj['Content-Type'] as string)
        : typeof headerObj['content-type'] === 'string'
          ? (headerObj['content-type'] as string)
          : undefined);
    const mime = guessImageMime(contentTypeHeader, url, bytes);
    return `data:${mime};base64,${new util.Base64Helper().encodeToStringSync(bytes)}`;
  } catch (_e) {
    return url;
  } finally {
    client.destroy();
  }
}

async function inlineImages(html: string): Promise<string> {
  const imgRegex = /<img\b[^>]*?>/gi;
  const urls: string[] = [];
  let match: RegExpExecArray | null = imgRegex.exec(html);
  while (match !== null) {
    const tag = match[0];
    const srcMatch = tag.match(/\bsrc="([^"]*)"/i) ?? tag.match(/\bdata-src="([^"]*)"/i);
    const src = srcMatch ? (srcMatch[1] ?? '') : '';
    urls.push(src ? normalizeUrl(src) : '');
    match = imgRegex.exec(html);
  }
  if (urls.length === 0) {
    return html;
  }
  const dataUrls = await Promise.all(urls.map((u: string) => (u ? fetchImageDataUrl(u) : '')));
  let idx = 0;
  return html.replace(/<img\b[^>]*?>/gi, (tag: string) => {
    const dataUrl = dataUrls[idx++];
    if (!dataUrl) {
      return tag;
    }
    if (/\bsrc="/i.test(tag)) {
      return tag.replace(/\bsrc="[^"]*"/i, `src="${dataUrl}"`).replace(/\bdata-src="[^"]*"/i, '');
    }
    return tag.replace(/\bdata-src="[^"]*"/i, `src="${dataUrl}"`);
  });
}

export interface BuildExportOptions {
  readonly includeComments?: boolean;
  readonly commentsHtml?: string;
  readonly includeImages?: boolean;
  /** 是否在导出底部加入「知乎++开源项目说明」，默认 true（对齐安卓默认勾选） */
  readonly includeAppAttribution?: boolean;
}

export async function buildExportHtml(meta: ArticleExportMeta, options: BuildExportOptions): Promise<string> {
  const bodyHtml = prepareBodyHtml(meta.contentHtml);
  const extraSections = options.includeComments && options.commentsHtml ? options.commentsHtml : '';
  const includeAppAttribution = options.includeAppAttribution !== false;
  const html = renderTemplate(meta, bodyHtml, extraSections, includeAppAttribution);
  if (options.includeImages === false) {
    return html;
  }
  return inlineImages(html);
}

export interface MarkdownExportOptions {
  readonly commentsHtml?: string;
  readonly includeAppAttribution?: boolean;
}

export function buildExportMarkdown(meta: ArticleExportMeta, options?: MarkdownExportOptions): string {
  const lines: string[] = [];
  lines.push(`# ${meta.title}`);
  lines.push('');
  lines.push(`**${meta.authorName}**${meta.authorBio ? ` · ${meta.authorBio}` : ''}`);
  lines.push('');
  lines.push(`👍 ${meta.voteUpCount}　💬 ${meta.commentCount}`);
  lines.push('');
  lines.push(htmlToMarkdown(meta.contentHtml));
  lines.push('');
  lines.push(`---`);
  lines.push(`> 导出日期：${formatDate(Date.now())}`);
  if (meta.createdEpochSeconds > 0) {
    lines.push(`> 发布日期：${formatDate(meta.createdEpochSeconds * 1000)}`);
  }
  if (options?.commentsHtml) {
    lines.push('');
    lines.push(`## 精选评论`);
    lines.push('');
    // 评论块为 HTML，Markdown 视图（支持内联 HTML）可正常渲染
    lines.push(options.commentsHtml);
  }
  if (options?.includeAppAttribution !== false) {
    lines.push('');
    lines.push(`> 使用知乎++（https://github.com/zly2006/zhihu-plus-plus）导出`);
  }
  return lines.join('\n');
}

export function buildExportFileName(meta: ArticleExportMeta, extension: string): string {
  const safeTitle = sanitizeFileName(meta.title) || '无标题';
  const safeAuthor = sanitizeFileName(meta.authorName) || '匿名作者';
  const typeLabel = meta.contentType === 'article' ? '文章' : meta.contentType === 'pin' ? '想法' : '回答';
  const ext = extension.trim().replace(/^\./, '');
  return `zhihu++_${safeTitle}_${safeAuthor}的${typeLabel}_${meta.contentType}_${meta.contentId}_${formatTimestampForFile(Date.now())}.${ext}`;
}

export async function saveTextFile(
  context: common.Context,
  text: string,
  fileName: string
): Promise<boolean> {
  try {
    const documentPicker = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    const uris = await documentPicker.save(options);
    if (!uris || uris.length === 0) {
      return false;
    }
    const uri = uris[0];
    const file = fileIo.openSync(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, text);
    } finally {
      fileIo.closeSync(file);
    }
    return true;
  } catch (_e) {
    return false;
  }
}

export async function copyText(text: string): Promise<void> {
  const pb = pasteboard.getSystemPasteboard();
  pb.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
}

// ============================================================================
// 收藏夹整夹导出 HTML（对齐安卓 CollectionContentViewModel.exportAllToHtmlZip）
// 每个回答/文章各生成一个 HTML（复用 buildExportHtml 同款模板），再整文件夹压成 .zip。
// 非 answer/article 的条目计为 skipped（对齐安卓只导出回答/文章）。
// ============================================================================

export interface CollectionExportProgress {
  readonly total: number;
  readonly processed: number;
  readonly success: number;
  readonly skipped: number;
  readonly failed: number;
  readonly currentTitle: string;
}

export interface CollectionExportResult {
  readonly total: number;
  readonly success: number;
  readonly skipped: number;
  readonly failed: number;
  readonly zipFilePath?: string;
}

/**
 * 把整夹收藏导出为 .zip（内含每个回答/文章一份 HTML）。
 * @param includeImages true=图片下载并 base64 内联（更慢），false=保留原始链接
 */
export async function exportCollectionToZip(
  context: common.Context,
  collectionTitle: string,
  items: HomeFeedItem[],
  includeImages: boolean,
  onProgress: (progress: CollectionExportProgress) => void
): Promise<CollectionExportResult> {
  const cacheDir: string = context.cacheDir;
  const safeTitle = sanitizeFileName(collectionTitle) || 'collection';
  const timestamp = Date.now();
  const stagingDir = `${cacheDir}/collection_export_${safeTitle}_${timestamp}`;
  fileIo.mkdirSync(stagingDir);

  let processed = 0;
  let success = 0;
  let skipped = 0;
  let failed = 0;
  const total = items.length;

  const emit = (currentTitle: string = '') => {
    onProgress({ total, processed, success, skipped, failed, currentTitle });
  };
  emit();

  for (const item of items) {
    if (item.type !== 'answer' && item.type !== 'article') {
      skipped++;
      processed++;
      emit();
      continue;
    }
    if (item.nativeTarget === undefined) {
      skipped++;
      processed++;
      emit();
      continue;
    }
    try {
      emit(item.title);
      const detail = await ArticleDetailService.loadDetail(context, item.nativeTarget);
      const meta: ArticleExportMeta = {
        title: detail.title,
        authorName: detail.author?.name ?? '匿名用户',
        authorBio: detail.author?.headline ?? '',
        authorAvatarSrc: detail.author?.avatarUrl ?? '',
        voteUpCount: detail.voteCount,
        commentCount: detail.commentCount,
        contentHtml: detail.htmlContent,
        createdEpochSeconds: detail.createdTime,
        updatedEpochSeconds: detail.updatedTime,
        contentId: detail.target.id,
        contentType: detail.target.kind === 'article' ? 'article' : 'answer'
      };
      const html = await buildExportHtml(meta, {
        includeImages,
        includeAppAttribution: true
      });
      const fileName = buildExportFileName(meta, 'html');
      const filePath = `${stagingDir}/${fileName}`;
      const file = fileIo.openSync(
        filePath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      try {
        fileIo.writeSync(file.fd, html);
      } finally {
        fileIo.closeSync(file);
      }
      success++;
    } catch (_e) {
      failed++;
    } finally {
      processed++;
      emit();
    }
  }

  let zipFilePath: string | undefined = undefined;
  if (success > 0) {
    zipFilePath = `${cacheDir}/zhihu++_${safeTitle}_${formatTimestampForFile(timestamp)}.zip`;
    await zlib.compressFile(stagingDir, zipFilePath, {});
  }
  return { total, success, skipped, failed, zipFilePath };
}

/**
 * 把沙箱内的二进制文件（如导出的 .zip）通过 DocumentViewPicker 另存到用户指定位置。
 */
export async function saveBinaryFile(
  context: common.Context,
  sourcePath: string,
  fileName: string
): Promise<boolean> {
  try {
    const documentPicker = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    const uris = await documentPicker.save(options);
    if (!uris || uris.length === 0) {
      return false;
    }
    const uri = uris[0];
    const srcFile = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = fileIo.statSync(sourcePath);
      const buf = new ArrayBuffer(stat.size);
      fileIo.readSync(srcFile.fd, buf);
      const dstFile = fileIo.openSync(
        uri,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      try {
        fileIo.writeSync(dstFile.fd, buf);
      } finally {
        fileIo.closeSync(dstFile);
      }
    } finally {
      fileIo.closeSync(srcFile);
    }
    return true;
  } catch (_e) {
    return false;
  }
}
