(() => {
  'use strict';
  document.addEventListener('keydown', () => { document.documentElement.dataset.keyboard = ''; });
  document.addEventListener('pointerdown', () => { delete document.documentElement.dataset.keyboard; });
  // Content is visible by default and remains available when JS is absent.
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  if (!reduced.matches && 'IntersectionObserver' in window) {
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return;
        entry.target.dataset.reveal = 'visible';
        observer.unobserve(entry.target);
      });
    }, {threshold:0.12});
    document.querySelectorAll('.reveal').forEach(element => {
      element.dataset.reveal = 'pending';
      observer.observe(element);
    });
    reduced.addEventListener('change', () => {
      if (!reduced.matches) return;
      observer.disconnect();
      document.querySelectorAll('[data-reveal]').forEach(element => delete element.dataset.reveal);
    });
  }
})();
