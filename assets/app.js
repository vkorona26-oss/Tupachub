// Tupachub — copy button, toast, footer year. No dependencies.
(function () {
  'use strict';

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

  var year = document.getElementById('year');
  if (year) year.textContent = String(new Date().getFullYear());
})();
