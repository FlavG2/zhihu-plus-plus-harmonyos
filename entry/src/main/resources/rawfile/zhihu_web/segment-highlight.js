/**
 * 划线片段（句子/段落高亮）注入。
 * 读取 <script type="application/json" id="zhihu-segment-data"> 中的段落/标记数据，
 * 在对应 <p data-pid="..."> 内按字符偏移把命中文本包进 <span class="highlight-wrap">。
 * 对齐安卓 SegmentHighlightUtils.applySegmentInfosToHtml：用真实 DOM 树做文本节点偏移映射，
 * 正确处理 <b>/<strong> 等内联标签与 HTML 实体，避免 ArkTS 侧无 HTML 解析器导致的偏移错位。
 */
(function () {
  function splitTextAt(root, absOffset) {
    if (absOffset <= 0) {
      return;
    }
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    var off = 0;
    var n;
    while ((n = walker.nextNode())) {
      var len = n.nodeValue.length;
      if (absOffset > off && absOffset < off + len) {
        n.splitText(absOffset - off);
        return;
      }
      off += len;
    }
  }

  function wrapRange(root, start, end, className, dataAttrs) {
    if (end <= start) {
      return;
    }
    splitTextAt(root, start);
    splitTextAt(root, end);
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    var toWrap = [];
    var off = 0;
    var n;
    while ((n = walker.nextNode())) {
      var len = n.nodeValue.length;
      if (off >= start && off + len <= end) {
        toWrap.push(n);
      }
      off += len;
    }
    toWrap.forEach(function (tn) {
      var span = document.createElement('span');
      span.className = className;
      Object.keys(dataAttrs).forEach(function (k) {
        span.setAttribute(k, dataAttrs[k]);
      });
      tn.parentNode.insertBefore(span, tn);
      span.appendChild(tn);
    });
  }

  function apply() {
    var el = document.getElementById('zhihu-segment-data');
    if (!el) {
      return;
    }
    var data;
    try {
      data = JSON.parse(el.textContent);
    } catch (e) {
      return;
    }
    if (!data || data.allow !== true || !Array.isArray(data.paragraphs)) {
      return;
    }
    data.paragraphs.forEach(function (p) {
      if (!p || !p.pid) {
        return;
      }
      var pid = String(p.pid).replace(/"/g, '\\"');
      var node = document.querySelector('p[data-pid="' + pid + '"]');
      if (!node) {
        return;
      }
      var marks = Array.isArray(p.marks) ? p.marks : [];
      marks.forEach(function (mark) {
        var meta = mark.segInfo || mark.masterSegInfo || {};
        var hasComments = (meta.commentCount || 0) > 0;
        var className = 'highlight-wrap other' + (hasComments ? ' has-comments' : '');
        var segIds = Array.isArray(meta.segIds) ? meta.segIds : [];
        var dataAttrs = {
          'data-highlight-id': segIds[0] || '',
          'data-highlight-seg-ids': JSON.stringify(segIds),
          'data-highlight-like-count': String(meta.likeCount || 0),
          'data-highlight-comment-count': String(meta.commentCount || 0),
          'data-highlight-my-comment-count': String(meta.myCommentCount || 0),
          'data-highlight-is-like': meta.isLike ? 'true' : 'false',
          'data-highlight-is-span': meta.isSpan ? 'true' : 'false',
          'data-highlight-pid': String(p.pid),
          'data-highlight-start-offset': String(mark.startIndex),
          'data-highlight-end-offset': String(mark.endIndex),
          'data-highlight-source-url': data.sourceUrl || '',
          'data-highlight-content-id': data.contentId || '',
          'data-highlight-content-type': data.contentType || ''
        };
        wrapRange(node, mark.startIndex, mark.endIndex, className, dataAttrs);
      });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', apply);
  } else {
    apply();
  }
})();
