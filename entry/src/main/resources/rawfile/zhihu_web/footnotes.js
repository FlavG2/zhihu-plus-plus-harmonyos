(function () {
  if (window.__zhihuFootnotesInstalled) {
    return;
  }
  window.__zhihuFootnotesInstalled = true;

  function highlightTarget(target) {
    if (!(target instanceof Element)) {
      return;
    }
    target.classList.remove('zhihu-footnote-target');
    void target.offsetWidth;
    target.classList.add('zhihu-footnote-target');
    window.setTimeout(function () {
      target.classList.remove('zhihu-footnote-target');
    }, 1400);
  }

  document.addEventListener('click', function (event) {
    var trigger = event.target;
    if (!(trigger instanceof Element)) {
      return;
    }
    var anchor = trigger.closest('a[href^="#"]');
    if (!(anchor instanceof HTMLAnchorElement)) {
      return;
    }
    var hash = anchor.getAttribute('href') || '';
    if (hash.length <= 1) {
      return;
    }
    var target = document.querySelector(hash);
    if (!(target instanceof Element)) {
      return;
    }
    event.preventDefault();
    target.scrollIntoView({
      behavior: 'smooth',
      block: 'center'
    });
    highlightTarget(target);
  }, true);
})();
