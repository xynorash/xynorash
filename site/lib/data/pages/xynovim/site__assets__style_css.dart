import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/site/assets/style.css',
  lines: [
    cm(r'//', '──────────────────────────────────────────'),
    cm(r'//', r'site/assets/style.css'),
    cm(r'//', r'565 lines of CSS for every page of the site'),
    cm(r'//', r'two palettes, system fonts, no JavaScript needed for the layout'),
    cm(r'//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the only stylesheet of the website'),
    kv(r'language', r'plain CSS (custom properties, grid, clamp, :has, no preprocessor)'),
    kv(r'size', r'565 lines, four commits (94ff2dc, 23a5114, 1578d94, e6ad339)'),
    kv(r'palette', r'Island Dark by default, a deliberate light palette under prefers-color-scheme: light'),
    ...sec(r'why this file exists'),
    ...para(r'//', r'The site has one stylesheet for the home page, the plugins page, the guides and (with a few rules) the 404 page. It does without a framework: the design lives in about two dozen custom properties on :root, the layout adapts with grid, clamp and a few media queries, and the file honours prefers-color-scheme, prefers-reduced-motion and print. The Content Security Policy says style-src self, so there is no style attribute and no style element anywhere on the site, and every rule is in this file.'),
    blank,
    ...code('css', r'site/assets/style.css · lines 1-26', r'''
/* xynovim website. Island Dark palette (lua/island/palette.lua), system fonts only. */

:root {
  color-scheme: dark;
  --bg: #1e1f22;
  --bg-glass: rgba(30, 31, 34, 0.9);
  --panel: #2b2d30;
  --code-bg: #17181b;
  --border: #393b40;
  --border-strong: #4b5059;
  --text: #bcbec4;
  --strong: #e6e8ec;
  --muted: #9da0a8;
  --blue: #56a8f5;
  --green: #6aab73;
  --orange: #cf8e6d;
  --purple: #c77dbb;
  --yellow: #f2c55c;
  --on-accent: #1e1f22;
  --glow-a: rgba(86, 168, 245, 0.14);
  --glow-b: rgba(199, 125, 187, 0.1);
  --shadow: 0 18px 50px -12px rgba(0, 0, 0, 0.65), 0 2px 8px rgba(0, 0, 0, 0.4);
  --mono: "JetBrains Mono", "JetBrainsMono Nerd Font", "Fira Code", "Cascadia Code", "SF Mono", ui-monospace, Menlo, Consolas, "DejaVu Sans Mono", monospace;
  --sans: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  --gutter: clamp(16px, 4vw, 32px);
  --radius: 12px;
'''),
    ...para(r'//', r'The first line says where the colours come from: the Island Dark palette of lua/island/palette.lua, the same palette as the editor theme, (its own comment says so). The blue (#56a8f5), green (#6aab73), orange, purple and yellow are values from that scheme. Fonts are system fonts only (the font stacks end in generic families), with JetBrains Mono and a few other monospace fonts first for code, if the visitor has them installed. No font file is ever downloaded.'),
    blank,
    ...sec(r'the light palette is not an inversion'),
    ...code('css', r'site/assets/style.css · lines 28-49', r'''

@media (prefers-color-scheme: light) {
  :root {
    color-scheme: light;
    --bg: #f6f7f9;
    --bg-glass: rgba(246, 247, 249, 0.92);
    --panel: #ffffff;
    --code-bg: #eceff4;
    --border: #d3d7de;
    --border-strong: #aab0ba;
    --text: #2b2d30;
    --strong: #14151a;
    --muted: #565a63;
    --blue: #1858b8;
    --green: #26683a;
    --orange: #94461a;
    --purple: #86307e;
    --yellow: #7a5200;
    --on-accent: #ffffff;
    --glow-a: rgba(24, 88, 184, 0.1);
    --glow-b: rgba(134, 48, 126, 0.07);
    --shadow: 0 18px 44px -14px rgba(30, 40, 70, 0.28), 0 2px 6px rgba(30, 40, 70, 0.12);
'''),
    ...para(r'//', r'The dark palette is the default, and light is a second set of the same variable names under prefers-color-scheme: light. It is a separately chosen set, not the dark values flipped. The accents are darker (the blue becomes #1858b8, the green #26683a, the yellow #7a5200), on-accent flips from dark to white, and the shadows and glows are rewritten for a light ground. The file does not state the reason; tests/site_spec.lua has a test that text colours reach WCAG AA (4.5:1) on every surface, dark and light. The README calls this a deliberate light palette. Because the page uses the variables everywhere, nothing else has to know which mode it is in.'),
    blank,
    ...sec(r'base rules'),
    ...code('css', r'site/assets/style.css · lines 51-98', r'''
}

*, *::before, *::after { box-sizing: border-box; }

html {
  -webkit-text-size-adjust: 100%;
  text-size-adjust: 100%;
  scroll-padding-top: 76px;
}

@media (prefers-reduced-motion: no-preference) {
  html { scroll-behavior: smooth; }
}

body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
  font: 1rem/1.65 var(--sans);
  overflow-wrap: break-word;
}

img, video, svg { max-width: 100%; }
img, video { display: block; height: auto; }

a { color: var(--blue); text-underline-offset: 0.18em; }
a:hover { text-decoration-thickness: 2px; }

:focus-visible {
  outline: 3px solid var(--yellow);
  outline-offset: 2px;
  border-radius: 4px;
}

h1, h2, h3, h4 {
  font-family: var(--mono);
  color: var(--strong);
  line-height: 1.2;
  margin: 0 0 0.5em;
  letter-spacing: -0.01em;
}

p { margin: 0 0 1em; max-width: 70ch; }

code, kbd, pre { font-family: var(--mono); }
code, kbd {
  background: var(--code-bg);
  border: 1px solid var(--border);
'''),
    ...para(r'//', r'The base layer is short. Motion is conditional: smooth scrolling only for visitors with no reduced-motion preference. scroll-padding-top of 76 pixels keeps an anchor from hiding under the sticky header. The body line-height is 1.65 and long words break anywhere they need to, so no line can push the page sideways. Paragraphs are capped at 70 characters wide. Inline code is a pill: boxed, inline-block and allowed to break anywhere, so a long path inside a table cell wraps instead of overflowing. The focus ring is a 3 pixel outline in the yellow variable, set once on :focus-visible, so it follows the palette. The container, wrap, is min(100% minus two gutters, 1180px), with a gutter that clamps between 16 and 32 pixels.'),
    blank,
    ...sec(r'header and the menu with no script'),
    ...code('css', r'site/assets/style.css · lines 134-174', r'''
/* header and nav */
.site-header {
  position: sticky;
  top: 0;
  z-index: 50;
  background: var(--bg-glass);
  -webkit-backdrop-filter: blur(12px);
  backdrop-filter: blur(12px);
  border-bottom: 1px solid var(--border);
}

.bar { display: flex; align-items: center; gap: 12px; min-height: 60px; position: relative; }

.brand {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  font: 700 1.1rem var(--mono);
  color: var(--strong);
  text-decoration: none;
  margin-right: auto;
}
.brand img { width: 28px; height: 28px; border-radius: 7px; }

.nav-toggle {
  position: absolute;
  opacity: 0;
  width: 1px;
  height: 1px;
  margin: 0;
  pointer-events: none;
}
.nav-burger {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 42px;
  height: 42px;
  border: 1px solid var(--border-strong);
  border-radius: 10px;
  color: var(--strong);
'''),
    ...para(r'//', r'The header is sticky with a translucent background and a blur, with a border below it. The menu is the interesting part. A hidden checkbox (opacity 0, one pixel, not display none, so it stays focusable), a label shaped as a burger button and a nav element that is display none until the checkbox is checked, using the sibling combinator. A focus ring appears on the burger when the checkbox is focused by keyboard. The state machine of the menu is therefore the browser’s own checkbox, and the page works with scripts disabled. app.js only closes it after a choice and on Escape.'),
    blank,
    ...code('css', r'site/assets/style.css · lines 225-235', r'''
@media (min-width: 980px) {
  .nav-burger { display: none; }
  #site-nav { display: block; position: static; background: none; border: 0; box-shadow: none; padding: 0; }
  #site-nav ul { display: flex; gap: 2px; }
  #site-nav a { padding: 8px 10px; font-size: 0.85rem; }
  .brand { margin-right: 0; }
  .bar { gap: 20px; }
  .bar > .btn { margin-left: auto; }
  .brand { margin-right: auto; }
}
'''),
    ...para(r'//', r'From 980 pixels wide, the burger is hidden and the same nav is shown as a row. There is one redundancy here, visible in the source: the brand has margin-right 0 at line 230 and margin-right auto again at line 233, so the second rule cancels the first. The behaviour is the one of the second rule; the first line is dead.'),
    blank,
    ...sec(r'cards, plugins and the dependency diagram'),
    ...code('css', r'site/assets/style.css · lines 528-556', r'''
/* plugins: cards, dependency diagram, badges */
.plugins { display: grid; gap: 16px; grid-template-columns: repeat(auto-fit, minmax(min(100%, 340px), 1fr)); list-style: none; padding: 0; margin: 0 0 32px; }
.plugin { background: var(--panel); border: 1px solid var(--border); border-radius: var(--radius); padding: 20px; margin: 0; min-width: 0; display: flex; flex-direction: column; }
.plugin h4 { font-size: 1.05rem; margin-bottom: 0.4em; }
.plugin h4 a { color: var(--blue); }
.plugin p { margin: 0 0 10px; font-size: 0.93rem; }
.plugin .block { margin: 0 0 12px; }
.plugin .plug-links { margin: auto 0 0; display: flex; flex-wrap: wrap; gap: 6px 16px; }
.plug-needs b { color: var(--strong); }
.badge { display: inline-block; font: 600 0.75rem var(--mono); color: var(--green); border: 1px solid var(--border-strong); border-radius: 999px; padding: 2px 10px; }
.block pre.lua { white-space: pre-wrap; overflow-wrap: anywhere; tab-size: 2; font-size: 0.78rem; line-height: 1.55; }
.dep { margin: 0 0 32px; display: grid; gap: 16px; grid-template-columns: minmax(0, 2.4fr) minmax(0, 1fr); align-items: start; }
.dep figcaption { grid-column: 1 / -1; font-size: 0.9rem; color: var(--muted); max-width: 90ch; }
.dep-stack, .dep-solo { background: var(--panel); border: 1px solid var(--border); border-radius: var(--radius); padding: 14px; margin: 0; list-style: none; }
.dep-stack { display: grid; gap: 8px; grid-template-columns: repeat(3, minmax(0, 1fr)); grid-template-areas: ". crates macros" "new imports imports" "rust rust rust"; }
.dg { margin: 0; padding: 10px 12px; background: var(--code-bg); border: 1px solid var(--border-strong); border-radius: 8px; min-width: 0; }
.dg a { display: block; font: 700 0.85rem var(--mono); color: var(--blue); overflow-wrap: anywhere; }
.dg span { display: block; font-size: 0.78rem; color: var(--muted); }
.dg-rust { grid-area: rust; border-color: var(--green); }
.dg-new { grid-area: new; }
.dg-imports { grid-area: imports; }
.dg-crates { grid-area: crates; }
.dg-macros { grid-area: macros; }
.dep-solo p { margin: 0 0 8px; font-size: 0.9rem; }
.dep-solo b { color: var(--strong); }
.dep-solo ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; }
.dep-solo li { margin: 0; font: 600 0.85rem var(--mono); }
.plugin-table td:first-child { width: 20%; overflow-wrap: anywhere; }
.inspired { font-style: italic; }
'''),
    ...para(r'//', r'The plugins page is built from three kinds of parts. The cards are an auto-fit grid, minmax of min(100%, 340px) and one fraction, so the number of columns follows the width without a media query. The badge is a pill with the border colour. The dependency diagram is a CSS grid with named areas: the stack has crates and macros on one row, new and imports on the next, and rust spanning the whole bottom row, so the picture of which plugin needs which is drawn with boxes and no image. The mobile rule at 760 pixels changes the area template to a single column, in the order crates, macros, imports, new, rust.'),
    blank,
    ...code('css', r'site/assets/style.css · lines 557-565', r'''
@media (max-width: 760px) {
  .dep { grid-template-columns: minmax(0, 1fr); }
  .dep-stack { grid-template-columns: minmax(0, 1fr); grid-template-areas: "crates" "macros" "imports" "new" "rust"; }
}
@media (max-width: 600px) {
  .plugin-table td[data-label]::before { content: attr(data-label) ": "; font: 600 0.72rem var(--mono); color: var(--muted); text-transform: uppercase; letter-spacing: 0.05em; }
  .plugin-table td:first-child::before { content: none; }
  .plugin-table td:first-child { width: auto; font-weight: 700; overflow-wrap: normal; }
}
'''),
    ...para(r'//', r'At 600 pixels, table cells on the plugins page get a data-label prefix by CSS attr(), so on a phone each cell announces its column in its own text. This is the same idea as the general table rule below.'),
    blank,
    ...sec(r'tables on a phone'),
    ...code('css', r'site/assets/style.css · lines 436-445', r'''
/* tables */
table { width: 100%; border-collapse: collapse; table-layout: fixed; background: var(--panel); border: 1px solid var(--border); border-radius: var(--radius); overflow: hidden; }
th, td { text-align: left; vertical-align: top; padding: 12px 14px; border-bottom: 1px solid var(--border); font-size: 0.93rem; }
th { font: 600 0.78rem var(--mono); color: var(--muted); text-transform: uppercase; letter-spacing: 0.06em; background: var(--code-bg); }
tr:last-child td { border-bottom: 0; }
td:first-child, th:first-child { width: 28%; }
td code { white-space: normal; }
td code + code { margin-left: 2px; }

.chips { list-style: none; padding: 0; margin: 0; display: flex; flex-wrap: wrap; gap: 8px; }
'''),
    ...code('css', r'site/assets/style.css · lines 476-495', r'''
/* responsive */
@media (max-width: 960px) {
  .hero-grid, .feature, .subfeature, .two { grid-template-columns: minmax(0, 1fr); }
}

@media (max-width: 600px) {
  .shots, .shots:has(> :nth-child(3):last-child) { grid-template-columns: minmax(0, 1fr); }
  table, thead, tbody, tr, th, td { display: block; }
  thead { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); }
  tr { border-bottom: 1px solid var(--border); padding: 10px 0; }
  tr:last-child { border-bottom: 0; }
  td { border: 0; padding: 4px 14px; }
  td:first-child { width: auto; }
  .swatches { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}

@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { animation: none !important; transition: none !important; }
}
'''),
    ...para(r'//', r'Tables are fixed-layout with rounded borders and an uppercase small header. Under 600 pixels every table element becomes a block, the header row is clipped to one pixel with clip-path (hidden visually but still in the accessibility tree) and the rows become stacked boxes. This is how the command tables of the guides stay readable on a phone without a horizontal scroll bar. Two other rules in the same block respect the visitor: animation and transition are off for reduced motion, and printing hides the header, the skip link and the copy buttons.'),
    blank,
    ...sec(r'guides'),
    ...code('css', r'site/assets/style.css · lines 507-527', r'''
/* guide pages (site/guides/<slug>/index.html) */
.prose { padding-block: clamp(28px, 5vw, 64px) clamp(40px, 7vw, 88px); }
.prose-body { max-width: 76ch; }
.prose h1 { font-size: clamp(1.8rem, 1.3rem + 2.2vw, 2.8rem); margin-bottom: 0.6em; }
.prose h2 { font-size: clamp(1.3rem, 1.1rem + 0.9vw, 1.7rem); margin-top: 2.2em; }
.prose h3 { font-size: 1.1rem; margin-top: 1.6em; }
.prose p, .prose li { max-width: 76ch; }
.prose .lead { margin-bottom: 1.4em; }
.prose figure.term { margin: 1.6em 0; }
.prose table { margin: 1.2em 0; }
.crumbs { list-style: none; padding: 0; margin: 0 0 20px; display: flex; flex-wrap: wrap; gap: 4px 8px; font-size: 0.9rem; color: var(--muted); }
.crumbs li { margin: 0; }
.crumbs li + li::before { content: "/"; margin-right: 8px; color: var(--muted); }
.crumbs a { color: var(--blue); }
.related { display: grid; gap: 12px; grid-template-columns: repeat(auto-fit, minmax(min(100%, 240px), 1fr)); list-style: none; padding: 0; margin: 1em 0 0; }
.related li { margin: 0; }
.related a { display: block; height: 100%; padding: 14px 16px; background: var(--panel); border: 1px solid var(--border); border-radius: var(--radius); text-decoration: none; color: var(--text); }
.related a:hover { border-color: var(--blue); }
.related b { display: block; font: 700 0.95rem var(--mono); color: var(--blue); margin-bottom: 4px; }
.guide-links { margin-top: 2em; }
'''),
    ...para(r'//', r'The guide pages share the shell and add the prose rules: a 76-character measure, fluid heading sizes with clamp, breadcrumbs made from an ordered list with a slash drawn by CSS, and a related-guides grid of cards. The hidden class vh at line 474 is the one app.js uses for its live region and its copy fallback.'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt(r'//', r'variables and nothing else', r'every colour is a variable; adding a theme is another block of values.'),
    ...pt(r'//', r'fluid, not breakpoints', r'clamp, min and auto-fit do most of the responsive work; media queries remain only for the structural changes at 600, 760, 960 and 980 pixels.'),
    ...pt(r'//', r'accessible by default', r'focus rings, a skip link, a reduced-motion block, a print block, hidden-but-readable table headers.'),
    ...pt(r'//', r'one file', r'a single request, and a file that a CSP can name; the cost is 565 lines in which everything is at one level.'),
    ...sec(r'history'),
    ...pt(r'//', r'94ff2dc 2026-10-16', r'the first stylesheet with the official site.'),
    ...pt(r'//', r'23a5114 2026-10-16', r'website review fixes: order properties removed from the nav rules (one line deleted from the burger rules, one from the button rule, one trimmed from the 980 pixel nav rule).'),
    ...pt(r'//', r'1578d94 2026-10-22', r'guides: the prose, breadcrumb and related-card rules.'),
    ...pt(r'//', r'e6ad339 2026-10-22', r'the plugins page: cards, dependency diagram, badges and the responsive table labels.'),
  ],
);
