/* GSAP motion for the existing archive cabinet. */
(function () {
  'use strict';
  if (!window.gsap) return;

  const gsap = window.gsap;
  const active = new Map();
  let enabled = false;

  function stop(key) {
    const context = active.get(key);
    if (context) {
      context.revert();
      active.delete(key);
    }
  }

  function reset() {
    for (const key of Array.from(active.keys())) stop(key);
  }

  // Each interaction owns a context so interruption restores its CSS state.
  function play(key, build) {
    stop(key);
    if (!enabled) return false;
    let timeline;
    const context = gsap.context(function () {
      timeline = gsap.timeline({ defaults: { ease: 'power2.out' } });
      build(timeline);
    });
    active.set(key, context);
    timeline.eventCallback('onComplete', function () {
      if (active.get(key) === context) stop(key);
    });
    return true;
  }

  const media = gsap.matchMedia();
  media.add('(prefers-reduced-motion: no-preference)', function () {
    enabled = true;
    document.documentElement.classList.add('archive-motion-ready');
    return function () {
      enabled = false;
      reset();
      document.documentElement.classList.remove('archive-motion-ready');
    };
  });

  window.ArchiveMotion = {
    reset: reset,
    stop: stop,

    drawer: function (section, open, instant) {
      const key = 'drawer-' + section.id;
      stop(key);
      if (instant) return;
      const handle = section.querySelector('.drawer-toggle .handle');
      const interior = section.querySelector('.drawer-inner > .interior');
      play(key, function (timeline) {
        if (handle) {
          timeline.to(handle, { y: 3, scaleY: 0.96, duration: 0.1 }, 0)
            .to(handle, { y: 0, scaleY: 1, duration: 0.3 }, 0.1);
        }
        if (interior && open) {
          timeline.fromTo(interior, { y: 20, opacity: 0.35 },
            { y: 0, opacity: 1, duration: 0.52 }, 0.06);
        }
        if (open && section.id === 'works') {
          timeline.fromTo(section.querySelectorAll('.file-label'),
            { x: -9, opacity: 0.4 },
            { x: 0, opacity: 1, stagger: 0.035, duration: 0.3 }, 0.18);
        }
      });
    },

    folder: function (front) {
      return play('folder', function (timeline) {
        const distance = matchMedia('(max-width: 700px)').matches ? 20 : 34;
        timeline.fromTo(front,
          { y: -distance, rotation: -4.5, scale: 0.985, opacity: 0.25 },
          { y: 0, rotation: -3, scale: 1, opacity: 1, duration: 0.48 });
        timeline.fromTo(front.querySelectorAll('.folder-projects li'),
          { y: 5, opacity: 0.4 },
          { y: 0, opacity: 1, duration: 0.24, stagger: 0.035 }, 0.17);
      });
    },

    peek: function (cue) {
      play('peek', function (timeline) {
        timeline.fromTo(cue, { y: 8, opacity: 0.45 },
          { y: 0, opacity: 1, duration: 0.28 });
      });
    },

    detail: function (root) {
      const summary = root.querySelector('.project-detail-summary');
      const media = root.querySelector('.detail-media-stack');
      play('detail', function (timeline) {
        if (summary) timeline.fromTo(summary, { y: 12, opacity: 0.55 },
          { y: 0, opacity: 1, duration: 0.34 }, 0);
        if (media) timeline.fromTo(media, { opacity: 0.65 },
          { opacity: 1, duration: 0.38 }, 0.05);
      });
    },

    gallery: function (visual) {
      play('gallery', function (timeline) {
        timeline.fromTo(visual, { opacity: 0.3, scale: 0.99 },
          { opacity: 1, scale: 1, duration: 0.25 });
      });
    },

    feed: function (paper) {
      play('paper', function (timeline) {
        timeline.fromTo(paper, { y: 48, rotation: -0.35 },
          { y: 14, rotation: -0.35, duration: 0.65, ease: 'power2.inOut' });
      });
    }
  };
})();
