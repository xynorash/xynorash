import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/site/guides/neovim-cargo-workspaces/index.html',
  lines: [
    cm(r'<!--', '──────────────────────────────────────────'),
    cm(r'<!--', r'site/guides/neovim-cargo-workspaces/index.html'),
    cm(r'<!--', r'one of six guides, written to be found and to be true'),
    cm(r'<!--', r'the head does the search work, the body documents real commands'),
    cm(r'<!--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'guide page: Cargo workspaces, features and crates from Neovim'),
    kv(r'language', r'hand-written HTML, no template engine, one inline JSON-LD block'),
    kv(r'size', r'187 lines, four commits (1578d94, 536e5cc, 724c508, e6ad339, all 2026-10-22)'),
    kv(r'url', r'https://xynorash.github.io/xynovim/guides/neovim-cargo-workspaces/'),
    kv(r'built by', r'scripts/build-site.py (the footer placeholders for commit and date are filled there)'),
    ...sec(r'why this file exists'),
    ...para(r'<!--', r'The lead of the guide describes its audience: someone who wants to add a dependency, pick its features or start a workspace without leaving the editor. It is separate from the README, which is written for people already in the repository. This guide is one of six, each about one job: diagnostics, debugging, tests and coverage, cargo workspaces, a git safety net and the Island Dark theme. Each is a separate page with its own address, title, description and share card, and each documents what the configuration really does. The spec enforces that last part: every command and key the guides name must exist in the running configuration.'),
    blank,
    ...sec(r'the head carries the metadata'),
    ...code('html', r'site/guides/neovim-cargo-workspaces/index.html · lines 1-13', r'''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'self'; img-src 'self' data:; media-src 'self'; style-src 'self'; script-src 'self'; base-uri 'none'; form-action 'none'">
<title>Cargo workspaces, features and crates in Neovim | xynovim</title>
<meta name="description" content="Create Rust binaries, libraries and workspaces, add crates with their features and fix missing derive features from Neovim: :CrateAdd, :CrateFeatures and more.">
<meta name="color-scheme" content="dark light">
<meta name="theme-color" content="#1e1f22" media="(prefers-color-scheme: dark)">
<meta name="theme-color" content="#f6f7f9" media="(prefers-color-scheme: light)">
<link rel="canonical" href="https://xynorash.github.io/xynovim/guides/neovim-cargo-workspaces/">
<link rel="icon" href="../../assets/favicon.svg" type="image/svg+xml">
'''),
    ...para(r'<!--', r'The page is a complete document with a language and a viewport. The first policy is the Content Security Policy as a meta tag: default-src self, images from self and data, media from self, styles and scripts only from self, no base element and no form action. The policy lists only self as a source, which backs the footer’s statement that the site makes no external requests. The title is the headline plus the site name, under the 60 characters the spec allows; the description is the sentence that appears under it in search results, between 120 and 160 characters by the spec. The meta tags for colour scheme and theme colour are given once for dark and once for light, matching the stylesheet’s two palettes.'),
    blank,
    ...code('html', r'site/guides/neovim-cargo-workspaces/index.html · lines 12-28', r'''
<link rel="canonical" href="https://xynorash.github.io/xynovim/guides/neovim-cargo-workspaces/">
<link rel="icon" href="../../assets/favicon.svg" type="image/svg+xml">
<meta property="og:type" content="article">
<meta property="og:site_name" content="xynovim">
<meta property="og:locale" content="en">
<meta property="og:title" content="Cargo workspaces, features and crates in Neovim | xynovim">
<meta property="og:description" content="Create Rust binaries, libraries and workspaces, add crates with their features and fix missing derive features from Neovim: :CrateAdd, :CrateFeatures and more.">
<meta property="og:url" content="https://xynorash.github.io/xynovim/guides/neovim-cargo-workspaces/">
<meta property="og:image" content="https://xynorash.github.io/xynovim/assets/og/neovim-cargo-workspaces.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="xynovim guide: Cargo workspaces, features and crates in Neovim, a new workspace tree with a member crate">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Cargo workspaces, features and crates in Neovim | xynovim">
<meta name="twitter:description" content="Create Rust binaries, libraries and workspaces, add crates with their features and fix missing derive features from Neovim: :CrateAdd, :CrateFeatures and more.">
<meta name="twitter:image" content="https://xynorash.github.io/xynovim/assets/og/neovim-cargo-workspaces.png">
<meta name="twitter:image:alt" content="xynovim guide: Cargo workspaces, features and crates in Neovim, a new workspace tree with a member crate">
'''),
    ...para(r'<!--', r'The canonical link names the clean URL with a trailing slash, and the Open Graph and Twitter blocks repeat title and description, give an absolute image URL (the generated card for this guide, 1200 by 630) and alt text for it. The spec requires absolute URLs on the canonical host, a card under 300 KB and alt text. They are the tags a link preview is built from.'),
    blank,
    ...sec(r'structured data'),
    ...code('html', r'site/guides/neovim-cargo-workspaces/index.html · lines 30-75', r'''
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "TechArticle",
      "@id": "https://xynorash.github.io/xynovim/guides/neovim-cargo-workspaces/#article",
      "headline": "Cargo workspaces, features and dependencies in Neovim",
      "description": "Create Rust binaries, libraries and workspaces, add crates with their features and fix missing derive features from Neovim: :CrateAdd, :CrateFeatures and more.",
      "url": "https://xynorash.github.io/xynovim/guides/neovim-cargo-workspaces/",
      "mainEntityOfPage": "https://xynorash.github.io/xynovim/guides/neovim-cargo-workspaces/",
      "inLanguage": "en",
      "image": "https://xynorash.github.io/xynovim/assets/og/neovim-cargo-workspaces.png",
      "author": {
        "@id": "https://github.com/xynorash"
      },
      "isPartOf": {
        "@id": "https://xynorash.github.io/xynovim/#website"
      }
    },
    {
      "@type": "BreadcrumbList",
      "itemListElement": [
        {
          "@type": "ListItem",
          "position": 1,
          "name": "xynovim",
          "item": "https://xynorash.github.io/xynovim/"
        },
        {
          "@type": "ListItem",
          "position": 2,
          "name": "Workspaces, features, crates",
          "item": "https://xynorash.github.io/xynovim/guides/neovim-cargo-workspaces/"
        }
      ]
    },
    {
      "@type": "Person",
      "@id": "https://github.com/xynorash",
      "name": "Xynorash",
      "url": "https://github.com/xynorash"
    }
  ]
}
</script>
'''),
    ...para(r'<!--', r'One JSON-LD block, which is not an executable script and so passes the policy, says the same things for machines. A TechArticle with the headline, description, address and image, a breadcrumb of two items (the site, then this guide) whose last item is the page’s own canonical address, and a Person for the author, linked by identifier. The spec checks that the data is valid JSON with absolute URLs, no ratings, reviews or prices, and that every inner page has a breadcrumb that ends at its own canonical URL. The headline in the data differs a little from the title tag (dependencies against crates); each is written for its place.'),
    blank,
    ...code('html', r'site/guides/neovim-cargo-workspaces/index.html · lines 76-77', r'''
<script src="../../assets/app.js" defer></script>
</head>
'''),
    ...para(r'<!--', r'The one script of the page is the shared app.js, loaded with defer, with a path relative to the page: ../../assets/. Relative paths are the rule for all pages except 404.html, and the site README’s preview recipe serves the built site under /xynovim/.'),
    blank,
    ...sec(r'the shell'),
    ...code('html', r'site/guides/neovim-cargo-workspaces/index.html · lines 78-103', r'''
<body id="top">
<svg width="0" height="0" hidden aria-hidden="true" focusable="false">
  <symbol id="i-copy" viewBox="0 0 24 24"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V6a2 2 0 0 1 2-2h8"/></symbol>
  <symbol id="i-tick" viewBox="0 0 24 24"><path d="m5 12 5 5 9-10"/></symbol>
  <symbol id="i-menu" viewBox="0 0 24 24"><path d="M4 7h16M4 12h16M4 17h16"/></symbol>
  <symbol id="i-branch" viewBox="0 0 24 24"><circle cx="6" cy="5" r="2"/><circle cx="6" cy="19" r="2"/><circle cx="18" cy="8" r="2"/><path d="M6 7v10M18 10c0 5-8 3-12 7"/></symbol>
</svg>
<a class="skip" href="#main">Skip to the content</a>
<header class="site-header">
  <div class="wrap bar">
    <a class="brand" href="../../"><img src="../../assets/favicon.svg" width="28" height="28" alt="">xynovim</a>
    <input type="checkbox" id="nav-toggle" class="nav-toggle" aria-label="Show the menu">
    <label for="nav-toggle" class="nav-burger" aria-hidden="true"><svg class="icon" aria-hidden="true" focusable="false"><use href="#i-menu"></use></svg></label>
    <nav id="site-nav" aria-label="Sections">
      <ul>
        <li><a href="../../#why">Why</a></li>
        <li><a href="../../#tour">Tour</a></li>
        <li><a href="../../plugins/">Plugins</a></li>
        <li><a href="../../#guides">Guides</a></li>
        <li><a href="../../#install">Install</a></li>
        <li><a href="../../#docs">Docs</a></li>
      </ul>
    </nav>
    <a class="btn" href="https://github.com/xynorash/xynovim"><svg class="icon" aria-hidden="true" focusable="false"><use href="#i-branch"></use></svg>GitHub</a>
  </div>
</header>
'''),
    ...para(r'<!--', r'The body begins with an inline SVG sprite: four symbols (copy, tick, menu, branch) defined once and referenced by use elements, so there are no icon files and no requests. A skip link comes first in the tab order. The header repeats the navigation of the home page with links to the sections of the home page (../../#why) and to the plugins page. The menu is the checkbox pattern from the stylesheet, so it works without script. The brand image has an empty alt because the text beside it names the link.'),
    blank,
    ...sec(r'the article'),
    ...code('html', r'site/guides/neovim-cargo-workspaces/index.html · lines 105-112', r'''
<main id="main">
<article class="prose">
  <div class="wrap">
    <div class="prose-body">
    <nav aria-label="Breadcrumb"><ol class="crumbs"><li><a href="../../">xynovim</a></li><li><a href="../../#guides">Guides</a></li><li aria-current="page">Workspaces, features, crates</li></ol></nav>
    <p class="kicker">xynovim guide</p>
    <h1>Cargo workspaces, features and dependencies in Neovim</h1>
    <p class="lead">Adding a dependency, picking its features and starting a workspace are chores that usually mean a terminal, a browser tab for crates.io and a manual edit of Cargo.toml. This guide covers the commands of xynovim, a personal Neovim configuration for Rust, that do these inside the editor: new projects and workspaces, <code>:CrateAdd</code> with feature selection, <code>:CrateFeatures</code>, the code action that enables a missing derive feature, and the feature set that rust-analyzer and clippy share.</p>
'''),
    ...para(r'<!--', r'The main element contains one article. A breadcrumb (an ordered list inside a nav with a label) comes first, then a kicker, then the one h1, then a lead paragraph that says what the guide covers and, importantly, what xynovim is: a personal Neovim configuration for Rust. The lead names five concrete things: new projects and workspaces, :CrateAdd with feature selection, :CrateFeatures, the code action that enables a missing derive feature, and the feature set shared by rust-analyzer and clippy. The following sections take them in that order, with ids that match the sections of the outline: new, add, features, context, deps, limits and try.'),
    blank,
    ...code('html', r'site/guides/neovim-cargo-workspaces/index.html · lines 113-113', r'''
<figure class="term"><a href="../../media/15-rust-new-workspace-tree.png"><img src="../../media/15-rust-new-workspace-tree.png" width="1440" height="820" alt="a new Cargo workspace in Neovim: the file tree with crates, the member and the root Cargo.toml" loading="lazy" decoding="async"></a><figcaption>Recorded from the real configuration on the demo crate.</figcaption></figure>
'''),
    ...para(r'<!--', r'Each screenshot is a figure with a link to the full-size file, explicit width and height (1440 by 820, so the browser reserves the space and the page does not jump), a descriptive alt text, lazy loading and async decoding, and a caption. Every image is a file that the home page or the README also uses, which the spec requires, and the build copies only the media that the pages reference.'),
    blank,
    ...sec(r'the content is checked against the product'),
    ...code('html', r'site/guides/neovim-cargo-workspaces/index.html · lines 114-125', r'''
<h2 id="new">New projects and workspaces</h2>
<p>Three dashboard entries and four commands create projects. They all run cargo underneath, asynchronously, and remove whatever they created if cargo fails.</p>
<table>
<thead><tr><th>Dashboard</th><th>Command</th><th>What it creates</th></tr></thead>
<tbody>
<tr><td><code>b</code></td><td><code>:RustNewBin [name]</code></td><td><code>cargo new --bin --vcs git</code>, then opens <code>src/main.rs</code></td></tr>
<tr><td><code>i</code></td><td><code>:RustNewLib [name]</code></td><td>the same with <code>src/lib.rs</code>; a hyphenated name shows its Rust identifier</td></tr>
<tr><td><code>w</code></td><td><code>:RustNewWorkspace [name]</code></td><td>a workspace with a first member</td></tr>
<tr><td></td><td><code>:RustNewMember [name]</code></td><td>adds a binary or library to the workspace of the current buffer</td></tr>
</tbody>
</table>
<p>Cargo has no one-step workspace command, so xynovim builds it: a root <code>Cargo.toml</code> with <code>[workspace]</code>, <code>resolver = "3"</code> (or <code>"2"</code> for editions before 2024), <code>members = ["crates/*"]</code>, <code>[workspace.package]</code> and an empty <code>[workspace.dependencies]</code>, and a first member under <code>crates/</code> that inherits <code>version.workspace</code> and <code>edition.workspace</code>. The edition is whatever your installed cargo writes into a new project, read once per session, never hard-coded. The <code>crates/*</code> glob picks up later members without editing the manifest. <code>:RustNewMember</code> refuses outside a workspace with a <code>members</code> list and refuses a name that collides with an existing member.</p>
'''),
    ...para(r'<!--', r'The first section is a table of three dashboard keys and four commands. Under it a paragraph explains what cargo does not do: Cargo has no one-step workspace command, so xynovim builds one, and the paragraph lists the manifest it writes. The wording is specific, with the resolver value depending on the edition, the glob that picks up later members, and the two refusals of :RustNewMember. These statements are checkable and the test suite checks that each command named on the page exists in the running configuration, as well as each leader key.'),
    blank,
    ...code('html', r'site/guides/neovim-cargo-workspaces/index.html · lines 129-130, 133-138', r'''
<h2 id="add">Adding a crate with its features</h2>
<p><code>&lt;leader&gt;rA</code> or <code>:CrateAdd [query]</code> searches crates.io and shows version, downloads and the features of the chosen release with their descriptions. You pick features and the target: the package that holds the file, <code>--dev</code> or <code>--build</code>, and <code>workspace.dependencies</code> entries are used when they exist. Then it runs <code>cargo add</code>. Writing a path such as <code>uuid::Uuid::new_v4()</code> for a crate that is not a dependency yet gives a hint and a code action, "Add crate uuid", that does the same and then offers the import.</p>
...
<h2 id="features">Exploring and fixing features</h2>
<ul>
<li><code>:CrateFeatures [crate]</code> is a feature explorer: which features are on or off, what each one unlocks, the default set, an "unused?" hint, and toggling in <code>Cargo.toml</code>.</li>
<li><code>&lt;leader&gt;rG</code>, or the code action "Enable feature derive of serde", fixes <code>cannot find derive macro Serialize</code>: the feature is found in the crate's own source and <code>Cargo.toml</code> is edited.</li>
<li><code>&lt;leader&gt;rI</code> or <code>:ImportName</code> imports a name with the candidates ranked and the reasons shown, and remembers your choice per project.</li>
</ul>
'''),
    ...para(r'<!--', r'The sections on adding a crate and on exploring features follow. The page names the command, the key and what happens next (cargo add), and one list gives the three ways of fixing a missing feature. The text avoids comparison with other products; a spec test enforces a personal voice with no such comparison.'),
    blank,
    ...sec(r'honest limits and the ending'),
    ...code('html', r'site/guides/neovim-cargo-workspaces/index.html · lines 147-161', r'''
<h2 id="limits">Limits</h2>
<ul>
<li>Project creation depends on cargo's own naming rules and on a network for crates.io and the egui template; the egui flow uses a cached copy offline.</li>
<li>The unknown-crate hint is deliberately conservative: a file with a glob import from a dependency gets no hint.</li>
<li>New Rust and egui project creation is not demonstrated on Windows or macOS.</li>
</ul>

<h2 id="try">Try it</h2>
<p>Install the configuration, open the dashboard and press <code>w</code> to create a workspace, then use <code>&lt;leader&gt;rA</code> inside a member to add a crate.</p>
    <div class="install-box" id="hero-install">
      <div class="label"><span>Install</span></div>
      <pre data-copy><code id="install-cmd"><span class="ln">git clone https://github.com/xynorash/xynovim ~/.config/nvim</span>   <span class="cmt"># or ln -s &lt;checkout&gt; ~/.config/nvim</span>
<span class="ln">~/.config/nvim/scripts/bootstrap.sh</span></code></pre>
    </div>
    <p>xynovim is a personal project: <a href="../../">the home page</a> has the tour, the install details and the platform status.</p>
'''),
    ...para(r'<!--', r'The page has a section called Limits. It says plainly that project creation depends on cargo’s naming rules and on the network, that the unknown-crate hint is conservative, and that creating Rust and egui projects is not demonstrated on Windows or macOS. The last limit matches the platform notes of the README. The last section reuses the install box of the home page with the same two commands, which the spec compares byte for byte with the README’s. The data-copy attribute on the pre element is what app.js looks for to add its copy button. The last paragraph points to the home page for the tour and the platform status.'),
    blank,
    ...sec(r'links out and the footer'),
    ...code('html', r'site/guides/neovim-cargo-workspaces/index.html · lines 163-187', r'''
    <h2 id="related">Related guides</h2>
    <ul class="related">
<li><a href="../neovim-rust-diagnostics/"><b>Rust diagnostics</b>Instant Rust diagnostics in Neovim with rust-analyzer and clippy</a></li>
<li><a href="../neovim-rust-tests-coverage/"><b>Tests and coverage</b>Running Rust tests with coverage in Neovim</a></li>
<li><a href="../neovim-git-local-history/"><b>Git safety net</b>A git safety net for Neovim: Local History, lazygit and diffview</a></li>
    </ul>

    <h2 id="source">In the repository</h2>
    <ul class="guide-links">
<li><a href="https://github.com/xynorash/xynovim/blob/main/README.md#macros-and-dependencies">README: Macros and dependencies</a></li>
<li><a href="https://github.com/xynorash/xynovim/blob/main/README.md#new-rust-projects">README: New Rust projects</a></li>
    </ul>
    </div>
  </div>
</article>
</main>

<footer class="site-footer">
  <div class="wrap">
    <p>xynovim is an independent personal project, inspired by JetBrains&rsquo; tools and not affiliated with or endorsed by JetBrains. See the <a href="../../#thanks">acknowledgements</a>. It is licensed under <a href="https://github.com/xynorash/xynovim/blob/main/LICENSE">Apache-2.0</a>; the source is at <a href="https://github.com/xynorash/xynovim">github.com/xynorash/xynovim</a>.</p>
    <p>Built from commit <a href="https://github.com/xynorash/xynovim/commit/{{COMMIT}}"><code>{{COMMIT}}</code></a> on {{DATE}}. This site makes no external requests: no CDN, no web fonts, no analytics.</p>
  </div>
</footer>
</body>
</html>
'''),
    ...para(r'<!--', r'Related guides are a list of three links with bold titles and one line each, styled as cards. A section named In the repository links to the README anchors the guide is based on, and the spec checks that those sections and anchors exist. The footer states what the project is, an independent personal project inspired by JetBrains tools and not affiliated with them, names the licence (Apache-2.0, since 724c508 on 2026-10-22, when the project’s own licence was fixed while the plugins use MIT) and links to the source. The last paragraph shows the build placeholders: the commit and the date, filled in by scripts/build-site.py from GITHUB_SHA and today’s date. They are the only text in the file that is not literal.'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt(r'<!--', r'static HTML, no generator', r'six guides share a shell by copying it. The cost is that a change to the header means editing every page; the spec for structure and the well-formedness check catch the copies that drift.'),
    ...pt(r'<!--', r'metadata for each page', r'title, description, canonical, share card, breadcrumb and article data are all different per page, so each guide is a separate page with its own address.'),
    ...pt(r'<!--', r'facts from the product', r'the guide names commands and keys, and the spec runs them against the configuration; a renamed command fails the spec instead of leaving a stale command on the page.'),
    ...pt(r'<!--', r'no scripts for content', r'the content, menu and images work without JavaScript.'),
    ...sec(r'history'),
    ...pt(r'<!--', r'1578d94 2026-10-22', r'guides: the page is added with the other five.'),
    ...pt(r'<!--', r'536e5cc 2026-10-22', r'voice review fixes: the public prose speaks as the owner.'),
    ...pt(r'<!--', r'724c508 2026-10-22', r'the licence line in the footer: xynovim itself stays under Apache-2.0, MIT is for the xyno-* plugins.'),
    ...pt(r'<!--', r'e6ad339 2026-10-22', r'the plugins page: the navigation gains a Plugins entry.'),
  ],
);
