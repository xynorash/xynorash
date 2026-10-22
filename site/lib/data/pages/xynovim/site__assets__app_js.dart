import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/site/assets/app.js',
  lines: [
    cm(r'//', '──────────────────────────────────────────'),
    cm(r'//', r'site/assets/app.js'),
    cm(r'//', r'four small enhancements, 138 lines'),
    cm(r'//', r'copy buttons, a menu that closes, a scroll-spy, videos that play while visible'),
    cm(r'//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the only script of the website'),
    kv(r'language', r'browser JavaScript, ES5 style (var, function, no modules), one IIFE'),
    kv(r'size', r'138 lines, one commit (94ff2dc, 2026-10-16)'),
    kv(r'loaded by', r'every page, with defer, from assets/app.js'),
    kv(r'rule', r'the page is complete without it; each feature degrades to plain HTML'),
    ...sec(r'why this file exists'),
    ...para(r'//', r'The site promises no frameworks, no external requests and no inline script. The Content Security Policy in the head of every page says script-src self, so a script has to be a file of the site, and the first line of this one states its place: progressive enhancement only, the page is complete without this file. Everything it adds is a convenience for people with JavaScript. A reader without it still gets all the content, working links and the same install command, selectable by hand.'),
    blank,
    ...code('js', r'site/assets/app.js · lines 1-6', r'''
/* Progressive enhancement only: the page is complete without this file. */
(function () {
  "use strict";

  var reduced = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var saveData = navigator.connection && navigator.connection.saveData;
'''),
    ...para(r'//', r'The two flags at the top are used later. reduced is true when the visitor asked for reduced motion in the operating system. saveData reads the Network Information API where it exists, so a person on a data-saving connection is respected. Both guards are written defensively (matchMedia and navigator.connection may not exist), and a missing feature means the flag is falsy, not an error.'),
    blank,
    ...sec(r'copy buttons'),
    ...code('js', r'site/assets/app.js · lines 8-25', r'''
  /* copy buttons on every <pre data-copy> */
  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text);
    }
    return new Promise(function (resolve, reject) {
      var ta = document.createElement("textarea");
      ta.value = text;
      ta.setAttribute("readonly", "");
      ta.className = "vh";
      document.body.appendChild(ta);
      ta.select();
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (err) { ok = false; }
      document.body.removeChild(ta);
      ok ? resolve() : reject(new Error("copy failed"));
    });
  }
'''),
    ...para(r'//', r'Every pre element with a data-copy attribute gets a copy button. copyText prefers the asynchronous Clipboard API, which is only available in a secure context. Otherwise it falls back to the old route: a read-only textarea with the class vh (visually hidden, defined in style.css), selected, with document.execCommand copy inside a try, removed again. It returns a Promise either way, so the caller has one code path.'),
    blank,
    ...code('js', r'site/assets/app.js · lines 27-31', r'''
  var live = document.createElement("div");
  live.className = "vh";
  live.setAttribute("role", "status");
  live.setAttribute("aria-live", "polite");
  document.body.appendChild(live);
'''),
    ...para(r'//', r'A single live region, a status div with aria-live polite and the same hidden class, is added to the body. The button states are announced through it, not by changing the button’s label alone. This is for screen reader users.'),
    blank,
    ...code('js', r'site/assets/app.js · lines 33-63', r'''
  Array.prototype.forEach.call(document.querySelectorAll("pre[data-copy]"), function (pre) {
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "copy";
    btn.innerHTML = '<svg class="icon" aria-hidden="true" focusable="false"><use href="#i-copy"></use></svg><span>Copy</span>';
    var label = btn.querySelector("span");
    var use = btn.querySelector("use");
    var timer = 0;
    btn.addEventListener("click", function () {
      copyText(pre.textContent.replace(/\s+$/, "")).then(function () {
        label.textContent = "Copied";
        use.setAttribute("href", "#i-tick");
        btn.setAttribute("data-state", "done");
        live.textContent = "Copied to the clipboard";
      }, function () {
        label.textContent = "Press Ctrl+C";
        live.textContent = "Copy failed: select the text and copy it by hand";
        var sel = window.getSelection();
        var range = document.createRange();
        range.selectNodeContents(pre);
        sel.removeAllRanges();
        sel.addRange(range);
      });
      window.clearTimeout(timer);
      timer = window.setTimeout(function () {
        label.textContent = "Copy";
        use.setAttribute("href", "#i-copy");
        btn.removeAttribute("data-state");
        live.textContent = "";
      }, 2200);
    });
'''),
    ...para(r'//', r'The button is built with innerHTML from a constant string that contains an SVG use element pointing at a symbol defined in the page (i-copy and i-tick), which keeps the icons inline and the policy happy. On a click, the text of the block is copied with trailing whitespace trimmed. On success the label changes to Copied, the icon to a tick, the button gets data-state done for the CSS and the live region speaks. On failure the label says Press Ctrl+C, the whole block is selected so that the shortcut works, and the live region tells the reader to copy by hand. A single timer, cleared on each click, restores the button after 2.2 seconds, so repeated clicks cannot leave it stuck.'),
    blank,
    ...code('js', r'site/assets/app.js · lines 64-72', r'''
    var box = pre.parentNode;
    if (box.classList.contains("install-box")) {
      box.querySelector(".label").appendChild(btn);
    } else {
      btn.className = "copy copy-float";
      box.classList.add("has-copy");
      box.appendChild(btn);
    }
  });
'''),
    ...para(r'//', r'Where the button goes depends on the box. The install box has a label row and the button joins it. Any other block gets a floating button, copy-float, and the box gets has-copy so that the CSS can leave room above the code. The prompt dollar sign in front of install commands is drawn by CSS (a before pseudo-element on the ln class, not selectable), so the copied text is only the command, with no prompt.'),
    blank,
    ...sec(r'the menu'),
    ...code('js', r'site/assets/app.js · lines 74-84', r'''
  /* the CSS-only menu closes after a choice */
  var toggle = document.getElementById("nav-toggle");
  var nav = document.getElementById("site-nav");
  if (toggle && nav) {
    nav.addEventListener("click", function (ev) {
      if (ev.target.closest && ev.target.closest("a")) { toggle.checked = false; }
    });
    document.addEventListener("keydown", function (ev) {
      if (ev.key === "Escape" && toggle.checked) { toggle.checked = false; toggle.focus(); }
    });
  }
'''),
    ...para(r'//', r'On narrow screens the navigation is a CSS-only menu: a checkbox, a label shaped as a burger and a nav shown when the checkbox is checked. This works without any script. The script adds two things on top: a click on a link inside the nav unticks the box so that the menu closes after a choice (needed because the link goes to an anchor on the same page), and Escape closes the menu and returns focus to the checkbox. Both are guarded by the existence of the two elements, so the same file serves pages with a different shell.'),
    blank,
    ...sec(r'the scroll-spy'),
    ...code('js', r'site/assets/app.js · lines 86-110', r'''
  /* active section in the nav */
  if ("IntersectionObserver" in window && nav) {
    var links = {};
    Array.prototype.forEach.call(nav.querySelectorAll('a[href^="#"]'), function (a) {
      links[a.getAttribute("href").slice(1)] = a;
    });
    var visible = {};
    var order = Object.keys(links);
    var update = function () {
      var current = null;
      order.forEach(function (id) { if (visible[id]) { current = id; } });
      order.forEach(function (id) {
        if (id === current) { links[id].setAttribute("aria-current", "true"); }
        else { links[id].removeAttribute("aria-current"); }
      });
    };
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) { visible[en.target.id] = en.isIntersecting; });
      update();
    }, { rootMargin: "-30% 0px -60% 0px" });
    order.forEach(function (id) {
      var sec = document.getElementById(id);
      if (sec) { spy.observe(sec); }
    });
  }
'''),
    ...para(r'//', r'The nav marks the section being read with aria-current. The script collects the nav links whose href begins with a hash and maps ids to links. An IntersectionObserver watches each section, and the rootMargin is minus 30 percent at the top and minus 60 percent at the bottom, which shrinks the observed area to a band across the upper-middle of the viewport. A section counts as current when it crosses that band. update picks the last visible section in document order, so if two sections are in the band the lower one wins, and sets aria-current on its link only. The CSS gives #site-nav a[aria-current] the blue colour and the code background. Guide pages, whose nav links are not same-page hashes, simply get an empty map and nothing happens.'),
    blank,
    ...sec(r'videos that play only while visible'),
    ...code('js', r'site/assets/app.js · lines 112-137', r'''
  /* recordings: load and play only while on screen, never with reduced motion */
  var videos = Array.prototype.slice.call(document.querySelectorAll("video"));
  if (videos.length && "IntersectionObserver" in window && !reduced && !saveData) {
    var paused = new WeakSet(); /* videos the visitor stopped by hand */
    var byScript = new WeakSet();
    videos.forEach(function (v) {
      v.addEventListener("pause", function () {
        if (byScript.has(v)) { byScript.delete(v); } else if (!v.ended) { paused.add(v); }
      });
    });
    var player = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        var v = en.target;
        if (en.isIntersecting) {
          if (!paused.has(v)) {
            var p = v.play();
            if (p && p.catch) { p.catch(function () {}); }
          }
        } else if (!v.paused) {
          byScript.add(v);
          v.pause();
        }
      });
    }, { threshold: 0.6 });
    videos.forEach(function (v) { player.observe(v); });
  }
'''),
    ...para(r'//', r'The recordings on the home page are videos with a poster and preload none. The script plays one only while at least 60 percent of it is on screen, and pauses it when it leaves. The whole block is skipped when there are no videos, when IntersectionObserver is missing, when reduced motion is on or when save-data is set; the videos then wait for a click on their native controls.'),
    blank,
    ...para(r'//', r'There is a subtle part. A pause event fires both when the script pauses a video and when the visitor does. Two weak sets tell them apart. Before the script calls pause it adds the video to byScript; the pause handler removes it from byScript and ignores the event. A pause that is not from the script, and that does not come from the video ending, puts the video in paused, and from then on the observer does not start it again when it scrolls back. A person who stopped a recording by hand keeps it stopped. WeakSet means no manual cleanup. The play call returns a promise that can reject (the browser may refuse autoplay), and the rejection is swallowed with an empty catch so it does not show up as an error.'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt(r'//', r'ES5 and an IIFE', r'var and function style, wrapped in one function so nothing leaks into the global scope, and no build step for the script. The cost is more verbose code than modern syntax.'),
    ...pt(r'//', r'strict mode', r'the third line turns on use strict.'),
    ...pt(r'//', r'guard, then act', r'every feature checks that its elements and APIs exist. The same file loads on the home page, the plugins page and the guides, which have different shells.'),
    ...pt(r'//', r'no tracking, no dependencies', r'consistent with the promise in the footer.'),
    ...sec(r'how it is checked'),
    ...para(r'//', r'tests/site_spec.lua has a test named works without JavaScript: the menu is a CSS checkbox and the copy buttons are added by the script, and a check that no page has an inline script, style or event handler. The CSP test asserts that script-src does not allow inline code. A further test runs node --check on assets/app.js (skipped when node is missing), so the suite checks that the file parses; nothing in it runs the script’s behaviour in a browser.'),
    blank,
    ...sec(r'history'),
    ...pt(r'//', r'94ff2dc 2026-10-16', r'the only commit. The file arrived with the site and has not changed since, even though the site grew from one page to a home page, a plugins page and six guides.'),
  ],
);
