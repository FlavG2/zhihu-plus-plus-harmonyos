(function () {
  if (window.__zhihuMathCopyInstalled) {
    return;
  }
  window.__zhihuMathCopyInstalled = true;

  function post(payload) {
    if (!window.zhihuBridge || typeof window.zhihuBridge.postMessage !== 'function') {
      return;
    }
    try {
      window.zhihuBridge.postMessage(JSON.stringify(payload));
    } catch (_) {
    }
  }

  // 长按图片 → 弹出菜单（查看/保存/分享）
  var longPressTimer = null;
  var longPressImg = null;

  document.addEventListener('touchstart', function (event) {
    if (longPressTimer) {
      clearTimeout(longPressTimer);
      longPressTimer = null;
    }
    longPressImg = null;

    var target = event.target;
    if (!(target instanceof Element)) {
      return;
    }

    // 视频 → 跳过
    if (target.closest('a.video-box, video')) {
      return;
    }

    var img = target.closest('img');
    if (img) {
      // 公式图片（eeimg=1 或 zhihu.com/equation）→ 跳过，不弹菜单
      if (img.getAttribute('eeimg') === '1' || (img.src && img.src.indexOf('zhihu.com/equation') !== -1)) {
        return;
      }
      longPressImg = img;
      longPressTimer = setTimeout(function () {
        if (longPressImg) {
          var url = longPressImg.currentSrc || longPressImg.src
            || longPressImg.getAttribute('data-original') || longPressImg.getAttribute('src') || '';
          if (url) {
            event.preventDefault();
            post({ type: 'imageMenu', url: url });
          }
        }
        longPressTimer = null;
        longPressImg = null;
      }, 500);
    }
  }, true);

  document.addEventListener('touchend', function () {
    if (longPressTimer) {
      clearTimeout(longPressTimer);
      longPressTimer = null;
    }
    longPressImg = null;
  }, true);

  document.addEventListener('touchmove', function () {
    if (longPressTimer) {
      clearTimeout(longPressTimer);
      longPressTimer = null;
    }
    longPressImg = null;
  }, true);
})();
