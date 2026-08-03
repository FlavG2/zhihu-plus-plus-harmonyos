(function () {
  if (window.__zhihuContentHeightInstalled) {
    return;
  }
  window.__zhihuContentHeightInstalled = true;

  function post(payload) {
    if (!window.zhihuBridge || typeof window.zhihuBridge.postMessage !== 'function') {
      return;
    }
    try {
      window.zhihuBridge.postMessage(JSON.stringify(payload));
    } catch (_) {
    }
  }

  function measureHeight() {
    var root = document.getElementById('zhihu-body-root');
    var content = document.getElementById('zhihu-body-content');
    var sentinel = document.getElementById('zhihu-body-sentinel');
    var body = document.body;
    if (root && content) {
      var rootRect = root.getBoundingClientRect ? root.getBoundingClientRect() : { top: 0, height: 0 };
      var contentRect = content.getBoundingClientRect ? content.getBoundingClientRect() : { height: 0 };
      var style = window.getComputedStyle ? window.getComputedStyle(root) : null;
      var paddingTop = style ? parseFloat(style.paddingTop || '0') : 0;
      var paddingBottom = style ? parseFloat(style.paddingBottom || '0') : 0;
      var contentBottom = 0;

      if (sentinel && sentinel.getBoundingClientRect) {
        var sentinelRect = sentinel.getBoundingClientRect();
        contentBottom = sentinelRect.top - rootRect.top;
      }

      if (contentBottom > 0) {
        return Math.round(contentBottom + paddingBottom + 1);
      }
      return Math.max(
        Math.round(paddingTop + contentRect.height + paddingBottom + 1),
        Math.round(content.offsetHeight + paddingTop + paddingBottom)
      );
    }
    if (!body) {
      return 0;
    }
    return Math.max(
      body.scrollHeight,
      body.offsetHeight
    );
  }

  var lastHeight = 0;
  function reportHeight() {
    var nextHeight = Math.round(measureHeight());
    if (!nextHeight || nextHeight === lastHeight) {
      return;
    }
    lastHeight = nextHeight;
    post({
      type: 'height',
      height: nextHeight
    });
  }

  document.addEventListener('DOMContentLoaded', reportHeight);
  window.addEventListener('load', reportHeight);
  window.addEventListener('resize', reportHeight);
  window.setTimeout(reportHeight, 60);
  window.setTimeout(reportHeight, 260);
  window.setTimeout(reportHeight, 900);

  var observer = new ResizeObserver(reportHeight);
  var root = document.getElementById('zhihu-body-root');
  var content = document.getElementById('zhihu-body-content');
  if (content) {
    observer.observe(content);
  } else if (root) {
    observer.observe(root);
  } else if (document.body) {
    observer.observe(document.body);
  }

  Array.prototype.forEach.call(document.images || [], function (image) {
    if (!(image instanceof HTMLImageElement)) {
      return;
    }
    if (image.complete) {
      return;
    }
    image.addEventListener('load', reportHeight);
    image.addEventListener('error', reportHeight);
  });
})();
