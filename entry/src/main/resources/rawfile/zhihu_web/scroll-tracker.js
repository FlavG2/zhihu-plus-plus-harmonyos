(function () {
  if (window.__zhihuScrollTrackerInstalled) {
    return;
  }
  window.__zhihuScrollTrackerInstalled = true;

  function post(payload) {
    if (!window.zhihuBridge || typeof window.zhihuBridge.postMessage !== 'function') {
      return;
    }
    try {
      window.zhihuBridge.postMessage(JSON.stringify(payload));
    } catch (_) {
    }
  }

  var lastY = -1;
  function reportScroll() {
    var y = window.scrollY || window.pageYOffset || 0;
    // 仅在变化超过阈值时上报，降低 ArkUI 重渲染频率
    if (Math.abs(y - lastY) < 4) {
      return;
    }
    lastY = y;
    post({ type: 'scroll', top: y });
  }

  // 测量摘要卡片底部位置（scrollTop 超过该值时卡片完全滚出视野，正文开始）
  // 用文档坐标（scrollY + rect.bottom），与 scroll 事件上报的 scrollY 同一坐标系
  function reportSummaryBounds() {
    var card = document.querySelector('.zhihu-summary-card');
    if (!card) {
      return;
    }
    var rect = card.getBoundingClientRect();
    var bottom = (window.scrollY || window.pageYOffset || 0) + rect.bottom;
    post({ type: 'summaryH', bottom: Math.round(bottom) });
  }

  window.addEventListener('scroll', function () {
    reportScroll();
    // 仅在卡片还在视野附近时持续重新测量，保证底部位置随布局稳定收敛
    var y = window.scrollY || window.pageYOffset || 0;
    if (y < 800) {
      reportSummaryBounds();
    }
  }, { passive: true });

  // 页面加载后多次测量：字体/图片可能延迟改变卡片高度，需等布局稳定
  function scheduleMeasurements() {
    reportScroll();
    reportSummaryBounds();
  }
  window.setTimeout(scheduleMeasurements, 100);
  window.setTimeout(scheduleMeasurements, 400);
  window.setTimeout(scheduleMeasurements, 900);
  window.setTimeout(scheduleMeasurements, 1800);
  if (document.readyState === 'complete') {
    scheduleMeasurements();
  } else {
    window.addEventListener('load', scheduleMeasurements);
  }
})();
