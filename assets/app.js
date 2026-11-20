// Tupachub — copy button, reveal, pointer spotlight, nav state. No dependencies.
(function () {
  'use strict';

  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------- copy ---------- */
  var line = document.getElementById('script-line');
  var script = line ? line.textContent.trim() : '';
  var toastEl = document.getElementById('toast');
  var toastTimer = null;

  function toast(message) {
    if (!toastEl) return;
    toastEl.textContent = message;
    toastEl.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      toastEl.classList.remove('show');
    }, 1600);
  }

  function legacyCopy(text) {
    var area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.top = '-1000px';
    document.body.appendChild(area);
    area.select();
    var ok = false;
    try {
      ok = document.execCommand('copy');
    } catch (err) {
      ok = false;
    }
    document.body.removeChild(area);
    return ok;
  }

  function copyScript(button) {
    var done = function (ok) {
      toast(ok ? 'script copied' : 'press Ctrl+C to copy');
      if (!ok || !button) return;
      var label = button.querySelector('span');
      if (!label) return;
      var original = label.textContent;
      label.textContent = 'Copied';
      setTimeout(function () {
        label.textContent = original;
      }, 1400);
    };

    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(script).then(function () {
        done(true);
      }, function () {
        done(legacyCopy(script));
      });
      return;
    }
    done(legacyCopy(script));
  }

  var buttons = document.querySelectorAll('[data-copy-script]');
  for (var i = 0; i < buttons.length; i++) {
    buttons[i].addEventListener('click', function () {
      copyScript(this);
    });
  }

  /* ---------- nav border on scroll ---------- */
  var nav = document.querySelector('.nav');
  if (nav) {
    var onScroll = function () {
      nav.classList.toggle('scrolled', window.scrollY > 8);
    };
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
  }

  /* ---------- reveal on scroll ---------- */
  if (!reduceMotion && 'IntersectionObserver' in window) {
    var targets = [];
    var sections = document.querySelectorAll('.section');
    for (var s = 0; s < sections.length; s++) {
      var head = sections[s].querySelectorAll('.eyebrow, h2');
      for (var h = 0; h < head.length; h++) targets.push(head[h]);
      var cards = sections[s].querySelectorAll('.card, .feat, .timeline li, .note');
      for (var c = 0; c < cards.length; c++) targets.push(cards[c]);
    }
    for (var t = 0; t < targets.length; t++) {
      targets[t].setAttribute('data-reveal', '');
      targets[t].style.transitionDelay = ((t % 6) * 45) + 'ms';
    }

    var io = new IntersectionObserver(function (entries) {
      for (var e = 0; e < entries.length; e++) {
        if (entries[e].isIntersecting) {
          entries[e].target.classList.add('in');
          io.unobserve(entries[e].target);
        }
      }
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });

    for (var k = 0; k < targets.length; k++) io.observe(targets[k]);
  }

  /* ---------- pointer spotlight on cards ---------- */
  if (!reduceMotion && window.matchMedia('(hover: hover)').matches) {
    var cardsAll = document.querySelectorAll('.card, .feat');
    var bind = function (card) {
      card.addEventListener('pointermove', function (event) {
        var rect = card.getBoundingClientRect();
        card.style.setProperty('--mx', (event.clientX - rect.left) + 'px');
        card.style.setProperty('--my', (event.clientY - rect.top) + 'px');
      });
    };
    for (var n = 0; n < cardsAll.length; n++) bind(cardsAll[n]);
  }

  /* ---------- footer year ---------- */
  var year = document.getElementById('year');
  if (year) year.textContent = String(new Date().getFullYear());
})();
