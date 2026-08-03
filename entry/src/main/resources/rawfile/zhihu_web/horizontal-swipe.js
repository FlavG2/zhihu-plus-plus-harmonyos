(function () {
  if (window.__zhihuHswipeInstalled) {
    return;
  }
  window.__zhihuHswipeInstalled = true;

  function post(payload) {
    if (!window.zhihuBridge || typeof window.zhihuBridge.postMessage !== 'function') {
      return;
    }
    try {
      window.zhihuBridge.postMessage(JSON.stringify(payload));
    } catch (_) {
    }
  }

  var startX = 0;
  var startY = 0;
  var active = false;
  var decided = false;
  var horizontal = false;
  var DECIDE_THRESHOLD = 8;

  function onStart(e) {
    if (e.touches.length !== 1) {
      active = false;
      return;
    }
    active = true;
    decided = false;
    horizontal = false;
    startX = e.touches[0].clientX;
    startY = e.touches[0].clientY;
  }

  function onMove(e) {
    if (!active || e.touches.length !== 1) {
      return;
    }
    var x = e.touches[0].clientX;
    var y = e.touches[0].clientY;
    var dx = x - startX;
    var dy = y - startY;
    if (!decided) {
      if (Math.abs(dx) < DECIDE_THRESHOLD && Math.abs(dy) < DECIDE_THRESHOLD) {
        return;
      }
      decided = true;
      horizontal = Math.abs(dx) > Math.abs(dy);
      if (horizontal) {
        post({ type: 'hswipe', state: 'start', dx: 0 });
      }
    }
    if (horizontal) {
      // 横向滑动归我们控制，阻止浏览器做垂直滚动/回弹
      if (e.cancelable) {
        e.preventDefault();
      }
      post({ type: 'hswipe', state: 'move', dx: dx });
    }
  }

  function onEnd() {
    if (!active) {
      return;
    }
    active = false;
    if (horizontal) {
      post({ type: 'hswipe', state: 'end', dx: 0 });
    }
  }

  document.addEventListener('touchstart', onStart, { passive: true });
  document.addEventListener('touchmove', onMove, { passive: false });
  document.addEventListener('touchend', onEnd, { passive: true });
  document.addEventListener('touchcancel', onEnd, { passive: true });
})();
