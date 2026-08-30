(function () {
  if (window.__zhihuClickListenerInstalled) {
    return;
  }
  window.__zhihuClickListenerInstalled = true;

  function post(payload) {
    if (!window.zhihuBridge || typeof window.zhihuBridge.postMessage !== 'function') {
      return;
    }
    try {
      window.zhihuBridge.postMessage(JSON.stringify(payload));
    } catch (_) {
    }
  }

  function absoluteImageUrl(element) {
    if (!element) {
      return '';
    }
    return element.currentSrc || element.src || element.getAttribute('data-original') || element.getAttribute('src') || '';
  }

  document.addEventListener('click', function (event) {
    var target = event.target;
    if (!(target instanceof Element)) {
      return;
    }

    // 知乎视频优先：a.video-box[data-lens-id]（必须先于 img 检查，因为封面图在 video-box 内部）
    var videoBox = target.closest('a.video-box');
    if (videoBox instanceof HTMLAnchorElement) {
      var lensId = videoBox.getAttribute('data-lens-id') || '';
      if (lensId) {
        event.preventDefault();
        post({ type: 'video', videoId: lensId });
        return;
      }
    }
    var videoEl = target.closest('video');
    if (videoEl instanceof HTMLVideoElement) {
      var vLens = videoEl.getAttribute('data-lens-id') || '';
      if (vLens) {
        event.preventDefault();
        post({ type: 'video', videoId: vLens });
        return;
      }
    }

    var image = target.closest('img');
    if (image instanceof HTMLImageElement) {
      if (image.getAttribute('data-zhihu-ignore-image-click') === 'true') {
        return;
      }
      var imageUrl = absoluteImageUrl(image);
      if (imageUrl) {
        event.preventDefault();
        post({ type: 'image', url: imageUrl });
      }
      return;
    }

    // 划线片段：命中 span.highlight-wrap 优先于普通链接（高亮句可能包在 <a> 内，先拦截）
    var seg = target.closest('span.highlight-wrap');
    if (seg instanceof HTMLElement) {
      var ds = seg.dataset;
      var segIds = [];
      try {
        segIds = JSON.parse(ds.highlightSegIds || '[]');
      } catch (_) {
        segIds = [];
      }
      post({
        type: 'segment',
        id: ds.highlightId || '',
        likeCount: Number(ds.highlightLikeCount) || 0,
        commentCount: Number(ds.highlightCommentCount) || 0,
        isLike: ds.highlightIsLike === 'true',
        displayText: (seg.textContent || '').trim(),
        contentId: ds.highlightContentId || '',
        contentType: ds.highlightContentType || '',
        paragraphId: ds.highlightPid || '',
        startOffset: Number(ds.highlightStartOffset) || 0,
        endOffset: Number(ds.highlightEndOffset) || 0,
        segIds: segIds
      });
      return;
    }

    var anchor = target.closest('a');
    if (!(anchor instanceof HTMLAnchorElement)) {
      return;
    }
    var href = anchor.getAttribute('href') || '';
    if (!href || href.charAt(0) === '#') {
      return;
    }
    event.preventDefault();
    post({
      type: 'link',
      url: anchor.href,
      text: (anchor.textContent || '').trim()
    });
  }, true);
})();
