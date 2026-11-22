/* ============================================================================
 *  SCU Maker · 开场页
 * ---------------------------------------------------------------------------
 *  ① 0.0s   Logo 色块硬切（米白 / 院徽蓝 / 夜黑 / 院徽金 / 川大红 / 优雅灰）
 *  ② 播放「动画.mp4」（muted 自动播放，铺满画面）
 *  ③ 视频结束 → 闪白 → 真实 Logo 落位 + 标题 + 打字机
 *  ④ Logo 停留 10 秒后自动翻到下一页
 *
 *  视频时长自动读取：整页停留 = 色块 + 视频 + 10s，换视频不用改时间。
 * ========================================================================== */
(function () {
  'use strict';

  var DEFAULT_CUTS = [
    { bg: '#f7f4ec', logo: 'black', ghost: 'SCU MAKER', ms: 520 },
    { bg: '#4667ad', logo: 'white', ghost: 'MAKER', ms: 500 },
    { bg: '#0a0f22', logo: 'white', ghost: 'SCU MAKER', ms: 500 },
    { bg: '#f7bd00', logo: 'black', ghost: 'MAKER', ms: 500 },
    { bg: '#b1281c', logo: 'white', ghost: 'SICHUAN', ms: 460 },
    { bg: '#9a9ea6', logo: 'white', ghost: 'MAKER', ms: 460 },
    { bg: '#f7f4ec', logo: 'black', ghost: 'SCU MAKER', ms: 520 }
  ];

  var HOLD_AFTER_LOGO = 10000;   // Logo 落位后停留 10 秒

  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
  function smooth(e0, e1, x) { return clamp((x - e0) / (e1 - e0), 0, 1); }
  function easeInOutCubic(t) { t = clamp(t, 0, 1); return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; }
  function easeInOutSine(t) { return -(Math.cos(Math.PI * clamp(t, 0, 1)) - 1) / 2; }

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function titleHTML(str) {
    var parts = String(str || 'SCU Maker').split(' ');
    if (parts.length < 2) return esc(str);
    return esc(parts.slice(0, -1).join(' ')) + ' <em>' + esc(parts[parts.length - 1]) + '</em>';
  }

  /* ========================================================================== */
  function IntroSlide(hook) {
    hook = hook || {};
    var cfg = window.CONFIG || {};
    var I = cfg.intro || {};
    var settings = cfg.settings || {};
    var cuts = (I.cuts && I.cuts.length) ? I.cuts : DEFAULT_CUTS;
    var lines = (I.lines && I.lines.length) ? I.lines : [{ text: 'SCU Maker' }];

    var cutEnd = cuts.reduce(function (a, c) { return a + (c.ms || 500); }, 0);

    var el = document.createElement('section');
    el.className = 'slide intro-slide';
    el.setAttribute('aria-label', '开场：SCU Maker');

    el.innerHTML =
      '<div class="intro-stage">' +
        '<div class="blackout"></div>' +
        '<div class="bg-paper"></div>' +
        '<div class="paper-grid"></div>' +
        '<div class="paper-noise"></div>' +
        '<video class="intro-video" muted playsinline webkit-playsinline preload="auto" autoplay poster="' + esc(I.poster || 'assets/动画_poster.jpg') + '">' +
          '<source src="' + esc(I.video || 'assets/动画_web.mp4') + '" type="video/mp4">' +
          (I.videoFallback ? '<source src="' + esc(I.videoFallback) + '" type="video/mp4">' : '') +
        '</video>' +
        '<div class="artboard">' +
          '<div class="intro-halo"></div>' +
          '<div class="logo-final"><img alt="SCU Maker logo" src="' + esc(settings.logoImage || "SCU Maker's Logo.png") + '"></div>' +
          '<div class="intro-copy">' +
            '<div class="intro-kicker">' + esc(I.kicker || 'Sichuan University · College of Computer Science') + '</div>' +
            '<h1 class="intro-title">' + titleHTML(I.mainTitle || 'SCU Maker') + '</h1>' +
            '<p class="intro-sub">' + esc(I.subTitle || '') + '</p>' +
            '<div class="intro-type"><span class="tw"></span><span class="caret"></span></div>' +
          '</div>' +
          '<div class="flash"></div>' +
        '</div>' +
        '<div class="cut-seq">' +
          '<div class="cut-bg"><div class="ghost"></div></div>' +
          '<div class="cut-logo"><img alt="" src="' + esc(settings.logoImage || "SCU Maker's Logo.png") + '"></div>' +
        '</div>' +
      '</div>';

    var video = el.querySelector('.intro-video');
    var cutBg = el.querySelector('.cut-bg');
    var cutGhost = el.querySelector('.cut-bg .ghost');
    var cutLogo = el.querySelector('.cut-logo');
    var flashEl = el.querySelector('.flash');
    var blackoutEl = el.querySelector('.blackout');
    var twEl = el.querySelector('.tw');

    /* ---- 时间轴（视频时长读出来后自动重算） ---- */
    var videoDur = 0;
    var T = { videoStart: cutEnd - 150, flash: 0, after: 0, copy: 0 };
    var duration = cutEnd + 15100 + HOLD_AFTER_LOGO;

    var BLACK_IN = 1500;               // 压黑时长（从视频结束前 1.5s 开始，缓慢渐暗）
    var BLACK_OUT = 1200;              // 黑场退去时长（cubic 缓入缓出）
    var BLACK_HOLD = 260;              // 全黑停留

    function computeTimeline() {
      var vd = videoDur > 0 ? videoDur : 15100;
      T.videoStart = cutEnd - 150;
      T.videoEnd = T.videoStart + vd;
      T.blackIn = T.videoEnd - BLACK_IN;            // 压黑从视频最后 1.5s 就开始（与视频尾巴重叠）
      T.blackFull = T.videoEnd;                     // 视频播完时正好全黑
      T.logo = T.blackFull + 120;                   // 全黑时 Logo 已就位，随后随黑场退去一起显现
      T.outStart = T.blackFull + BLACK_HOLD;        // 全黑稍作停留后开始渐退
      T.outEnd = T.outStart + BLACK_OUT;            // 完全露出纸面 + Logo
      T.after = T.outStart + 260;                   // 文案/打字机开始
      T.copy = T.after + 160;
      duration = T.outEnd + HOLD_AFTER_LOGO;
      if (hook.onDuration) hook.onDuration(duration);
    }
    computeTimeline();

    function onMeta() {
      videoMeta = true;
      if (isFinite(video.duration) && video.duration > 0.2) {
        videoDur = video.duration * 1000;
        computeTimeline();
        if (running) draw(t);
      }
    }
    video.addEventListener('loadedmetadata', onMeta);
    video.addEventListener('loadeddata', onMeta);
    video.addEventListener('canplay', onMeta);
    // 超时兜底：3.5 秒还读不到元数据就当视频不可用，直接走“只有 Logo”的路径
    setTimeout(function () {
      if (!videoMeta) {
        videoDur = 1200;
        computeTimeline();
      }
    }, 3500);
    video.addEventListener('error', function () {
      // 视频加载失败时缩短这一段，至少 Logo 还能正常出现
      videoDur = 1500;
      computeTimeline();
    });

    var t = 0, raf = 0, last = 0, running = false, after = false;
    var lastTw = '';
    var curCut = -1;
    var cutDone = false;
    var videoOn = false;
    var videoFrozen = false;
    var videoWatch = null;

    /* ---- Logo 色块硬切 ---- */
    function applyCut(i) {
      var c = cuts[i];
      if (!c) return;
      cutBg.style.setProperty('--cut-bg', c.bg);
      cutBg.style.setProperty('--cut-ink', c.logo === 'white' ? '#ffffff' : 'rgba(11,18,48,0.9)');
      cutGhost.textContent = c.ghost || '';
      cutLogo.classList.toggle('white', c.logo === 'white');
      document.body.dataset.theme = (c.logo === 'white') ? 'dark' : 'light';
    }
    function cutAt(now) {
      var acc = 0;
      for (var i = 0; i < cuts.length; i++) {
        acc += cuts[i].ms || 500;
        if (now < acc) return i;
      }
      return cuts.length - 1;
    }

    /* ---- 打字机 ---- */
    function typewriter(now) {
      if (now < T.after + 260) return '';
      var segs = lines.map(function (ln) {
        var text = ln.text || '';
        return { text: text, type: Math.max(420, text.length * 48), hold: 1600, del: Math.max(220, text.length * 26), gap: 280 };
      });
      var total = segs.reduce(function (a, s) { return a + s.type + s.hold + s.del + s.gap; }, 0);
      var c = (now - (T.after + 260)) % total;
      if (c < 0) c += total;
      for (var i = 0; i < segs.length; i++) {
        var s = segs[i];
        if (c < s.type) {
          var n = Math.ceil(s.text.length * clamp(c / s.type, 0, 1));
          return n > 0 ? s.text.slice(0, n) : '';
        }
        c -= s.type;
        if (c < s.hold) return s.text;
        c -= s.hold;
        if (c < s.del) {
          var m = Math.ceil(s.text.length * clamp(1 - c / s.del, 0, 1));
          return m > 0 ? s.text.slice(0, m) : '';
        }
        c -= s.del;
        if (c < s.gap) return '';
        c -= s.gap;
      }
      return '';
    }

    /* ---- 视频控制 ----
     * 策略：进入第一页就把整段视频全部缓存进内存（preload=auto + 自动播放一遍），
     *      循环播放时不再重新请求网络；板子上即使网络慢，也只是第一次多等一会儿。
     * 降级：元数据到了才显示视频，否则显示静态封面；视频停住超过 1.2s 自动放弃。 */
    var videoMeta = false;
    function primeVideo() {
      // 让浏览器立刻开始下载并解码首帧
      try { video.preload = 'auto'; } catch (e) { }
      var p = video.play();
      if (p && p.catch) p.catch(function () { });
      // 预播几百毫秒后停下，不影响时间轴
      setTimeout(function () {
        if (!videoOn) { try { video.pause(); video.currentTime = 0; } catch (e) { } }
      }, 600);
    }
    function playVideo(now) {
      if (videoOn) return;
      videoOn = true;
      try {
        // 整段视频已在内存里，直接对齐时间轴（seek 只需解码，无需重新下载）
        video.currentTime = Math.max(0, (now - T.videoStart) / 1000);
        var p = video.play();
        if (p && p.catch) p.catch(function () { });
      } catch (e) { /* 自动播放被拦截时静默 */ }
    }
    function stopVideo() {
      if (!videoOn) return;
      videoOn = false;
      el.classList.remove('video-on');
      try { video.pause(); } catch (e) { }
    }
    // 视频可播放（有尺寸）才显示，避免播不出来时整块黑屏
    function canShowVideo() {
      return videoMeta && video.videoWidth > 0 && video.readyState >= 2;
    }

    /* ---- 主绘制 ---- */
    function draw(now) {
      // 色块快切
      if (now < cutEnd - 120) {
        var ci = cutAt(now);
        if (ci !== curCut) { applyCut(ci); curCut = ci; }
      } else if (!cutDone) {
        cutDone = true;
        el.classList.add('cut-done');
        document.body.classList.remove('montage');
        document.body.dataset.theme = 'light';
      }

      // 视频开始 / 结束（能播才显示，否则保持纸面背景，不会黑屏）
      if (now >= T.videoStart && now < T.videoEnd) {
        playVideo(now);
        var showVideo = canShowVideo() && !videoFrozen;
        el.classList.toggle('video-on', showVideo);
      } else {
        stopVideo();
      }

      // Firefox 上若视频一直没进帧（currentTime 不前进），就放弃视频，避免整页卡死
      if (videoOn && !videoFrozen) {
        if (!videoWatch) { videoWatch = { t: now, ct: -1 }; }
        if (now - videoWatch.t > 1200) {
          if (Math.abs(video.currentTime - videoWatch.ct) < 0.05 && video.currentTime < 0.05) {
            videoFrozen = true;
            stopVideo();
            el.classList.remove('video-on');
          }
          videoWatch = { t: now, ct: video.currentTime };
        }
      }

      // 黑场过渡：压黑 → Logo 落位 → 慢慢亮起
      var ba = 0;
      if (now >= T.blackIn && now < T.blackFull) {
        ba = easeInOutSine((now - T.blackIn) / (T.blackFull - T.blackIn));
      } else if (now >= T.blackFull && now < T.outStart) {
        ba = 1;
      } else if (now >= T.outStart && now < T.outEnd) {
        ba = 1 - easeInOutCubic((now - T.outStart) / (T.outEnd - T.outStart));
      }
      blackoutEl.style.opacity = ba.toFixed(3);
      flashEl.style.opacity = '0';

      // Logo 落位（在黑场最暗时完成）
      if (!after && now >= T.logo) {
        after = true;
        el.classList.add('after');
        document.body.dataset.theme = 'light';
      }

      // 打字机
      if (now >= T.after) {
        var txt = typewriter(now);
        if (txt !== lastTw) { twEl.textContent = txt; lastTw = txt; }
      }
    }

    function frame(ts) {
      if (!running) return;
      if (!last) last = ts;
      var dt = ts - last;
      last = ts;
      if (dt > 120) dt = 120;
      t += dt;
      draw(t);
      raf = requestAnimationFrame(frame);
    }

    var api = {
      el: el,
      duration: duration,
      title: (I.mainTitle || 'SCU Maker'),
      start: function (seek) {
        t = seek || 0;
        last = 0;
        after = false;
        cutDone = false;
        curCut = -1;
        videoOn = false;
        videoFrozen = false;
        videoWatch = null;
        lastTw = '';
        twEl.textContent = '';
        flashEl.style.opacity = '0';
        blackoutEl.style.opacity = '0';
        el.classList.remove('after', 'cut-done', 'video-on');
        try { video.pause(); video.currentTime = 0; } catch (e) { }
        try { video.preload = 'auto'; } catch (e) { }
        document.body.classList.add('montage', 'intro-mode');
        document.body.dataset.theme = 'light';
        running = true;
        draw(t);
        cancelAnimationFrame(raf);
        raf = requestAnimationFrame(frame);
      },
      stop: function () {
        running = false;
        cancelAnimationFrame(raf);
        // 保留 after / cut-done，避免切页瞬间闪回色块层
        stopVideo();
        flashEl.style.opacity = '0';
        document.body.classList.remove('montage', 'intro-mode');
        document.body.dataset.theme = 'light';
      },
      pause: function () {
        running = false;
        cancelAnimationFrame(raf);
        if (videoOn) { try { video.pause(); } catch (e) { } }
      },
      resume: function () {
        if (running) return;
        running = true;
        last = 0;
        if (videoOn) { try { video.play().catch(function () { }); } catch (e) { } }
        raf = requestAnimationFrame(frame);
      },
      seek: function (ms) {
        t = ms;
        if (ms >= T.videoStart && ms < T.videoEnd) {
          el.classList.add('video-on');
          videoOn = true;
          try { video.currentTime = clamp((ms - T.videoStart) / 1000, 0, 15); } catch (e) { }
        }
        draw(t);
      }
    };

    if (hook.onDuration) hook.onDuration(duration);

    // 首次进入即全量缓存视频（4~5MB），后续循环不再走网络
    primeVideo();

    draw(0);
    return api;
  }

  window.IntroSlide = IntroSlide;
})();
