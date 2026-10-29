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

(() => {
  'use strict';
  const viewer = document.getElementById('capture-viewer');
  if (!viewer || typeof viewer.showModal !== 'function') return;
  const image = document.getElementById('capture-viewer-image');
  const title = document.getElementById('capture-viewer-title');
  let source;
  document.querySelectorAll('a.capture-open').forEach(link => {
    link.addEventListener('click', event => {
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      source = link;
      image.src = link.href;
      image.alt = link.querySelector('img').alt;
      title.textContent = link.closest('figure')?.querySelector('figcaption')?.textContent || 'App preview';
      viewer.showModal();
    });
  });
  viewer.addEventListener('close', () => source?.focus({preventScroll:true}));
  viewer.addEventListener('click', event => {
    if (event.target !== viewer) return;
    const bounds = viewer.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) viewer.close();
  });
})();
