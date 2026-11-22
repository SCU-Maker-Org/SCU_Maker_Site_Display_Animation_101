/* ============================================================================
 *  播放控制器：横向换页、循环播放、进度条、暂停、全屏、键盘 / 滚轮 / 触摸
 * ========================================================================== */
(function () {
  'use strict';

  /* ---------------------------------------------- 时间模拟（?now=…，仅调试用） --
   *  index.html?now=2026-11-22T19:30  把“当前时间”固定成这个时刻，
   *  用来验证活动是否会在正确的时间段自动变成「正在进行中」。 */
  (function mockNow() {
    var v = new URLSearchParams(location.search).get('now');
    if (!v) return;
    var RealDate = Date;
    var fixed = new RealDate(v).getTime();
    if (isNaN(fixed)) return;
    window.__NOW__ = new RealDate(fixed);
    function FakeDate() {
      if (arguments.length === 0) return new RealDate(fixed);
      var args = Array.prototype.slice.call(arguments);
      return new (Function.prototype.bind.apply(RealDate, [null].concat(args)))();
    }
    FakeDate.prototype = RealDate.prototype;
    FakeDate.now = function () { return fixed; };
    FakeDate.parse = RealDate.parse;
    FakeDate.UTC = RealDate.UTC;
    window.Date = FakeDate;
  })();

  var C = window.CONFIG || {};
  var settings = C.settings || {};
  var posters = C.posters || [];

  var stage = document.getElementById('stage');
  var segmentsEl = document.getElementById('segments');
  var dotsEl = document.getElementById('dots');
  var curNoEl = document.getElementById('curNo');
  var totalNoEl = document.getElementById('totalNo');
  var nowTitleEl = document.getElementById('nowTitle');
  var brandLogoEl = document.getElementById('brandLogo');
  var brandEmblemEl = document.getElementById('brandEmblem');
  var clockEl = document.getElementById('clock');

  if (brandLogoEl && settings.logoImage) brandLogoEl.src = settings.logoImage;
  if (brandEmblemEl && settings.emblemImage) brandEmblemEl.src = settings.emblemImage;
  if (settings.brandBlue) document.documentElement.style.setProperty('--blue', settings.brandBlue);
  if (settings.brandGold) document.documentElement.style.setProperty('--gold', settings.brandGold);

  /* -------------------------------------------------------------------- 性能 --
   * 低配模式（Firefox / 老机器 / 软渲染 GPU 上会自动开启）：
   *   关闭大面积像素噪点、旋转光环、扩散环、发光阴影等耗 GPU 的效果，
   *   但保留视频、色块切换、Logo 落位，页面不会卡顿。
   *   - 强制关闭：index.html?lowfx=1
   *   - 强制开启：index.html?lowfx=0
   *   也可把 settings.lowfx 设为 true。 */
  (function detectLowFx() {
    var html = document.documentElement;
    var body = document.body;
    var force = new URLSearchParams(location.search).get('lowfx');
    var low = false;

    if (force === '1') low = true;
    else if (force === '0') low = false;
    else if (settings.lowfx === true) low = true;
    else {
      var ff = /firefox/i.test(navigator.userAgent);
      var cores = navigator.hardwareConcurrency || 4;
      var dpr = window.devicePixelRatio || 1;
      if (ff) {
        // Firefox：先用 <canvas> 读 GPU 渲染器，若有明确“软件渲染”信息则降级
        try {
          var c = document.createElement('canvas').getContext('webgl') ||
                  document.createElement('canvas').getContext('experimental-webgl');
          var dbg = c && c.getExtension('WEBGL_debug_renderer_info');
          var r = dbg ? String(c.getParameter(dbg.UNMASKED_RENDERER_WEBGL)) : '';
          if (/swiftshader|llvmpipe|software|basic/i.test(r)) low = true;
        } catch (e) { /* 忽略 */ }
      }
      // 低核数 / 高 DPI 也按低配处理
      if (cores <= 4 || dpr >= 1.75) low = true;
      html.setAttribute('data-firefox', ff ? '1' : '0');
    }

    body.classList.toggle('lowfx', low);
  })();


  var deck = {
    index: 0,
    slides: [],
    paused: false,
    startedAt: 0,
    remaining: 0,
    timer: 0,
    introCount: 0,
    started: false
  };

  /* ------------------------------------------------------------ 构建页面 -- */
  var intro = null;
  if (window.IntroSlide) {
    intro = window.IntroSlide({
      // 视频时长读出来后，回传整页时长，顺便更新进度条
      onDuration: function (ms) {
        if (!deck.slides.length) return;
        deck.slides[0].duration = ms;
        var seg = segmentsEl.children[0];
        if (seg) {
          seg.style.setProperty('--seg-dur', ms + 'ms');
          if (seg.classList.contains('active') && !deck.paused) {
            seg.classList.remove('active');
            void seg.offsetWidth;
            seg.classList.add('active');
          }
        }
        if (deck.started && deck.index === 0 && !deck.paused) schedule(ms);
      }
    });
    deck.slides.push(intro);
    stage.appendChild(intro.el);
  }

  // 每个活动生成两页：先中文、后英文（两页共用同一个活动序号）
  posters.forEach(function (p, actIndex) {
    ['zh', 'en'].forEach(function (lang) {
      var s = window.PosterSlide(p, actIndex, lang);
      deck.slides.push(s);
      stage.appendChild(s.el);
    });
  });

  deck.slides.forEach(function (s, i) {
    var seg = document.createElement('div');
    seg.className = 'seg';
    seg.style.setProperty('--seg-dur', (s.duration || 9000) + 'ms');
    seg.innerHTML = '<i></i>';
    segmentsEl.appendChild(seg);

    var dot = document.createElement('button');
    dot.className = 'dot';
    dot.type = 'button';
    dot.setAttribute('aria-label', '第 ' + (i + 1) + ' 页');
    dot.addEventListener('click', function () { go(i); });
    dotsEl.appendChild(dot);
  });

  if (totalNoEl) totalNoEl.textContent = String(deck.slides.length).padStart(2, '0');

  /* ------------------------------------------------------------ 播放逻辑 -- */
  function clearTimer() {
    clearTimeout(deck.timer);
    deck.timer = 0;
  }

  function schedule(ms) {
    clearTimer();
    if (deck.paused || settings.autoPlay === false) return;
    deck.startedAt = performance.now();
    deck.remaining = ms;
    deck.timer = setTimeout(function () {
      if (deck.index >= deck.slides.length - 1 && settings.loop === false) {
        deck.paused = true;
        document.body.classList.add('paused');
        return;
      }
      go(deck.index + 1, { auto: true });
    }, ms);
  }

  function go(raw, opts) {
    opts = opts || {};
    if (!deck.slides.length) return;

    var next = raw;
    var last = deck.slides.length - 1;

    if (next > last) {
      next = 0;
      if (settings.showIntroOnce && intro && deck.introCount > 0) next = Math.min(1, last);
    } else if (next < 0) {
      next = last;
    }

    if (next === deck.index && !opts.force) {
      restart();
      return;
    }

    var from = deck.slides[deck.index];
    var to = deck.slides[next];

    // 离开「正在进行中」的活动页 → 关掉该页额外的大面积动画（呼吸光晕等）
    if (from && from !== to && from.ongoing) document.body.classList.remove('ongoing-mode');

    if (from && from.el) {
      from.el.classList.remove('active');
      from.el.classList.add('past');
      if (from.stop) from.stop();
      if (from !== to) releaseIdleVideo();
    }

    deck.index = next;
    if (next === 0) deck.introCount++;
    deck.paused = false;
    document.body.classList.remove('paused');

    to.el.classList.remove('past', 'pre');
    void to.el.offsetWidth;              // 强制重排，让整页横移过渡重新开始
    to.el.classList.add('active');

    if (to.start) to.start();

    var segs = segmentsEl.children;
    var dots = dotsEl.children;
    for (var i = 0; i < segs.length; i++) {
      var on = i === deck.index;
      segs[i].classList.remove('active');
      segs[i].classList.toggle('done', i < deck.index);
      if (on) {
        void segs[i].offsetWidth;
        segs[i].classList.add('active');
      }
      if (dots[i]) dots[i].classList.toggle('active', on);
    }

    if (curNoEl) curNoEl.textContent = String(deck.index + 1).padStart(2, '0');
    if (nowTitleEl) nowTitleEl.textContent = to.title || '';
    syncOngoingMode();

    schedule(to.duration || 9000);
    deck.started = true;
  }

  function restart() {
    var s = deck.slides[deck.index];
    if (!s) return;
    if (s.start) s.start();
    schedule(s.duration || 9000);
  }

  // 进行中活动页的呼吸特效只在“当前页且未暂停”时运行
  function syncOngoingMode() {
    var s = deck.slides[deck.index];
    document.body.classList.toggle('ongoing-mode', !!(s && s.ongoing) && !deck.paused);
  }

  /* --------------------------------------------------------- 自动判定「进行中」 --
   * 进行中状态是按活动时间自动算出来的；展台可能连续开机好几天，
   * 所以要定期重算：跨过活动开始 / 结束的时刻后，徽标与特效会自动出现或消失。 */
  function refreshOngoing() {
    var changed = false;
    deck.slides.forEach(function (s) {
      if (!s.activity || typeof s.refreshOngoing !== 'function') return;
      var now = s.refreshOngoing();
      if (now !== s.ongoing) { s.ongoing = now; changed = true; }
    });
    if (changed) syncOngoingMode();
  }
  setInterval(refreshOngoing, 30000);
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) refreshOngoing();
  });

  function setPaused(p) {
    if (deck.paused === p) return;
    deck.paused = p;
    document.body.classList.toggle('paused', p);
    var s = deck.slides[deck.index];
    if (p) {
      if (deck.timer) {
        var elapsed = performance.now() - deck.startedAt;
        deck.remaining = Math.max(300, deck.remaining - elapsed);
      }
      clearTimer();
      if (s && s.pause) s.pause();
    } else {
      if (s && s.resume) s.resume();
      schedule(deck.remaining || (s && s.duration) || 9000);
    }
    syncOngoingMode();
  }

  function toggleFullscreen() {
    if (!document.fullscreenElement) {
      var p = document.documentElement.requestFullscreen && document.documentElement.requestFullscreen();
      if (p && p.catch) p.catch(function () { });
    } else if (document.exitFullscreen) {
      document.exitFullscreen();
    }
  }

  /* --------------------------------------------------------------- 交互 -- */
  document.getElementById('btnNext').addEventListener('click', function () { go(deck.index + 1); });
  document.getElementById('btnPrev').addEventListener('click', function () { go(deck.index - 1); });
  document.getElementById('btnToggle').addEventListener('click', function () { setPaused(!deck.paused); });
  document.getElementById('btnFull').addEventListener('click', toggleFullscreen);

  document.addEventListener('keydown', function (e) {
    var k = e.key;
    if (k === 'ArrowRight' || k === 'ArrowDown' || k === 'PageDown' || (k === ' ' && e.shiftKey)) {
      e.preventDefault(); go(deck.index + 1);
    } else if (k === 'ArrowLeft' || k === 'ArrowUp' || k === 'PageUp') {
      e.preventDefault(); go(deck.index - 1);
    } else if (k === ' ') {
      e.preventDefault(); setPaused(!deck.paused);
    } else if (k === 'f' || k === 'F') {
      toggleFullscreen();
    } else if (k === 'r' || k === 'R') {
      restart();
    } else if (k === 'Home') {
      go(0);
    } else if (k === 'End') {
      go(deck.slides.length - 1);
    } else if (k >= '1' && k <= '9') {
      var i = parseInt(k, 10) - 1;
      if (i < deck.slides.length) go(i);
    }
  });

  // 滚轮 / 触控板
  var wheelLock = 0;
  window.addEventListener('wheel', function (e) {
    var now = Date.now();
    if (now - wheelLock < 900) return;
    var d = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
    if (Math.abs(d) < 24) return;
    wheelLock = now;
    go(deck.index + (d > 0 ? 1 : -1));
  }, { passive: true });

  // 触摸滑动
  var touchX = 0, touchY = 0, touching = false;
  window.addEventListener('touchstart', function (e) {
    if (e.touches.length !== 1) return;
    touching = true;
    touchX = e.touches[0].clientX;
    touchY = e.touches[0].clientY;
  }, { passive: true });
  window.addEventListener('touchend', function (e) {
    if (!touching) return;
    touching = false;
    var t = e.changedTouches[0];
    var dx = t.clientX - touchX, dy = t.clientY - touchY;
    if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy)) go(deck.index + (dx < 0 ? 1 : -1));
  }, { passive: true });

  // 鼠标闲置隐藏光标
  var idleTimer = 0;
  function wake() {
    document.body.classList.remove('idle');
    clearTimeout(idleTimer);
    idleTimer = setTimeout(function () { document.body.classList.add('idle'); }, 2200);
  }
  ['mousemove', 'mousedown', 'touchstart', 'keydown'].forEach(function (ev) {
    window.addEventListener(ev, wake, { passive: true });
  });
  wake();

  // 时钟
  function tickClock() {
    if (!clockEl) return;
    var d = new Date();
    clockEl.textContent = String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
  }
  tickClock();
  setInterval(tickClock, 10000);

  // 离开开场页时释放视频解码器（只暂停，不销毁源：
  //  保存整段视频的缓冲/HTTP 缓存，下一轮循环播放不用重新下载）
  function releaseIdleVideo() {
    var v = document.querySelector('.intro-video');
    if (!v) return;
    try { v.pause(); } catch (e) { }
  }

  // 切到后台时暂停
  var wasPaused = false;
  document.addEventListener('visibilitychange', function () {
    if (document.hidden) {
      wasPaused = deck.paused;
      if (!wasPaused) setPaused(true);
    } else if (!wasPaused) {
      setPaused(false);
    }
  });

  /* ------------------------------------------- 调试参数（可选，不影响使用） -- */
  var qs = new URLSearchParams(location.search);
  var startSlide = parseInt(qs.get('slide') || '0', 10);
  var seek = parseInt(qs.get('seek') || '0', 10);
  var noAuto = qs.get('pause') === '1' || qs.get('autoplay') === '0';

  deck.slides.forEach(function (s) { s.el.classList.remove('active', 'past'); });

  if (startSlide > 0) {
    deck.index = Math.min(startSlide, deck.slides.length - 1);
    var target = deck.slides[deck.index];
    target.el.classList.add('active');
    if (target.start) target.start();
    if (curNoEl) curNoEl.textContent = String(deck.index + 1).padStart(2, '0');
    if (nowTitleEl) nowTitleEl.textContent = target.title || '';
    var sg = segmentsEl.children;
    for (var i = 0; i < sg.length; i++) {
      sg[i].classList.toggle('active', i === deck.index);
      sg[i].classList.toggle('done', i < deck.index);
    }
    Array.prototype.forEach.call(dotsEl.children, function (d, i) {
      d.classList.toggle('active', i === deck.index);
    });
    syncOngoingMode();
  } else {
    go(0, { force: true });
  }

  if (seek > 0 && intro && deck.index === 0) intro.seek(seek);

  if (noAuto) {
    clearTimer();
    deck.paused = true;
    document.body.classList.add('paused');
    var s0 = deck.slides[deck.index];
    if (s0 && s0.pause) s0.pause();
    syncOngoingMode();
  } else if (settings.fullscreenOnStart) {
    setTimeout(toggleFullscreen, 400);
  }

  window.__DECK__ = deck;
  window.__GO__ = go;
})();
