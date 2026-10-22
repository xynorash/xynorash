import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/site_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'site_spec.lua — a website tested like code, with no browser and no network'),
    cm('--', r'the build, head tags, CSP, structured data, contrast ratios, size budgets, the deploy workflow and every claim the pages make about the README'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for site/, scripts/build-site.py and .github/workflows/pages.yml'),
    kv(r'language', r'Lua spec, 1577 lines, 70 it() blocks, 13 describe() blocks'),
    kv(r'method', r'the site is built into a temp directory and read as text; links to github.com are not checked'),
    kv(r'needs', r'python3 for the build; node for one syntax check; actionlint and zizmor where installed'),
    kv(r'history', r'16 commits, 2026-10-16 to 2026-10-22'),
    ...sec(r'why this file exists'),
    ...para('--', r'The project has an official GitHub Pages site (commit 94ff2dc, 2026-10-16, "Website: official GitHub Pages site (site/, build script, deploy workflow, specs)"). A site that says things about the project (test counts, install commands, key names, platform status) can lie by going out of date. This spec is built to prevent that. It checks the quality of the HTML, but its more unusual job is to compare what the pages say with the README and with the running config. The header: everything is hermetic.'),
    ...code('lua', r'tests/site_spec.lua · lines 1-4', r'''
-- The website (site/, scripts/build-site.py, .github/workflows/pages.yml).
-- Everything is hermetic: the site is built into a temp directory and read as
-- text; no browser, no network (links to github.com are not checked here).
local H = require("xynotest.helpers")'''),
    ...sec(r'the build'),
    ...para('--', r'build-site.py is run for real into a temp directory and must succeed and print that all references resolve. A second test copies the script into a fake tree whose index.html references media that does not exist, and requires a non-zero exit naming none.png; the same for a placeholder it does not know ({{WHAT}}); another refuses a media reference that leaves docs/media. Only the referenced media is copied. Required files exist, with .nojekyll and no README of the source in the output.'),
    ...code('lua', r'tests/site_spec.lua · lines 116-122, 152-168', r'''
  it("scripts/build-site.py succeeds and checks its own references", function()
    if vim.fn.executable("python3") == 0 then
      skip("python3 is missing")
    end
    H.eq(0, built().code, built().out)
    H.match(built().out, "all resolve", true)
  end)
...
  it("fails on a placeholder it does not know and on a missing media file", function()
    local tmp = H.tmpdir() .. "/fake"
    vim.fn.mkdir(tmp .. "/scripts", "p")
    vim.fn.mkdir(tmp .. "/site", "p")
    vim.fn.mkdir(tmp .. "/docs/media", "p")
    vim.fn.mkdir(tmp .. "/tests", "p")
    vim.uv.fs_copyfile(repo .. "/scripts/build-site.py", tmp .. "/scripts/build-site.py")
    vim.uv.fs_copyfile(repo .. "/README.md", tmp .. "/README.md")
    vim.fn.writefile({ '<img src="media/none.png">' }, tmp .. "/site/index.html")
    local r = sh({ "python3", tmp .. "/scripts/build-site.py", "--out", tmp .. "/o" })
    H.not_ok(r.code == 0)
    H.match(r.out, "none.png", true)
    vim.fn.writefile({ "<p>{{WHAT}}</p>" }, tmp .. "/site/index.html")
    r = sh({ "python3", tmp .. "/scripts/build-site.py", "--out", tmp .. "/o" })
    H.not_ok(r.code == 0)
    H.match(r.out, "{{WHAT}}", true)
  end)'''),
    ...sec(r'head, CSP and no external requests'),
    ...para('--', r'Every page has lang, charset, viewport, one unique title of at most 60 characters, a description of 120 to 160 characters, its own canonical URL, Open Graph and Twitter tags with absolute https URLs on the canonical host, a 1200x630 card under 300 KB with alt text. The CSP meta tag is strict: it requires default-src, img-src, media-src, style-src and script-src all self, base-uri and form-action none, and no word unsafe. With that policy, a page cannot contain an inline script, style or event handler, and the tests check that none exists (the JSON-LD data block is the one exception allowed). Links make no external request: only github.com and nexte.st as ordinary a href links, and nothing is loaded from elsewhere.'),
    ...code('lua', r'tests/site_spec.lua · lines 236-245', r'''
  it("has a strict CSP meta tag", function()
    for _, file in ipairs({ "index.html", "404.html" }) do
      local csp = meta(read(out .. "/" .. file), "http-equiv", "Content-Security-Policy")
      H.ok(csp, file)
      for _, d in ipairs({ "default-src 'self'", "img-src 'self' data:", "media-src 'self'", "style-src 'self'", "script-src 'self'", "base-uri 'none'", "form-action 'none'" }) do
        H.match(csp, d, true, file .. ": " .. d)
      end
      H.no_match(csp, "unsafe", true)
    end
  end)'''),
    ...sec(r'the page says what the README says'),
    ...para('--', r'The most unusual block. The numbers of the page (spec files, checks passing, skipped with a stated reason, failing) are read from the README and the spec count from the tests directory. The test checks the README badge against its summary line, then counts tests/*_spec.lua files and compares, then requires the exact HTML fragments of the page. The install command on the page, in two places, must equal the README fenced block byte for byte after the HTML is unescaped. The test commands match the README. Every command and every key group named on the page exists in the README. Platform facts are the README facts, and the runs cited in the page are cited in the README. Acknowledgements are in the README and the footer as text only.'),
    ...code('lua', r'tests/site_spec.lua · lines 393-426', r'''
  it("the numbers are the README's and the spec count is the directory's", function()
    local html = page()
    local tests, specs, checks, skipped, failing = readme_numbers()
    H.ok(tests and specs, "README numbers")
    H.eq(tests, checks, "badge vs summary line in the README")
    local files = 0
    for _, n in ipairs(vim.fn.readdir(repo .. "/tests")) do
      if n:match("_spec%.lua$") then
        files = files + 1
      end
    end
    H.eq(files, tonumber(specs), "README spec files vs tests/*_spec.lua")
    for _, want in ipairs({
      { specs, "spec files" }, { tests, "checks passing" }, { skipped, "skipped with a stated reason" }, { failing, "failing" },
    }) do
      H.match(html, "<b>" .. want[1] .. "</b><span>" .. want[2] .. "</span>", true, want[2])
    end
    H.match(html, "tests <b>" .. tests .. " passing</b>", true)
    H.match(html, tests .. " passing checks across " .. files .. " spec files", true)
    H.no_match(html, "{{", true)
  end)

  it("the install command is the README's, byte for byte", function()
    local html = page()
    local block = readme:match("\n## Install\n.-\n```sh\n(.-)\n```")
    H.ok(block, "README install block")
    local function text_of(id)
      local inner = html:match('<code id="' .. id:gsub("%-", "%%-") .. '">(.-)</code>')
      H.ok(inner, id)
      return (inner:gsub("<[^>]+>", ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
    end
    H.eq(block, text_of("install-cmd"))
    H.eq(block, text_of("install-cmd-2"))
  end)'''),
    ...sec(r'the voice'),
    ...para('--', r'The public prose speaks as the owner. A test reads the README and every built page, lower-cases the text, removes the one allowed phrase (the author name, which is the Cargo.toml prompt of the egui flow), and requires that the phrases the author and author’s appear nowhere. This is a style rule enforced as a test (commit f7b8cf0, 2026-10-22, "Voice: first person, as Xynorash"). Another test requires that no competitor keyword appears in any head or card text, and that the guides contain no comparison with other products, matching the positioning commit 0247401 (a personal project inspired by JetBrains, not a competitor).'),
    ...code('lua', r'tests/site_spec.lua · lines 502-515', r'''
  it("the public prose speaks as the owner: no third-person 'the author' in the README or any page", function()
    built()
    -- "the author name" is the Cargo.toml authors prompt of the egui project work
    H.no_match(readme:lower():gsub("the author name", ""), "the author", true)
    H.no_match(readme:lower(), "author's", true)
    local pages = vim.fn.glob(out .. "/**/index.html", false, true)
    H.ok(#pages >= 7, "pages built")
    for _, f in ipairs(pages) do
      local t = read(f):lower():gsub("the author name", "")
      H.no_match(t, "the author", true, f)
      H.no_match(t, "author&rsquo;s", true, f)
      H.no_match(t, "author's", true, f)
    end
  end)'''),
    ...sec(r'structured data'),
    ...para('--', r'Every page has JSON-LD that is valid JSON with absolute URLs and no ratings, reviews or prices. The home page says WebSite and SoftwareSourceCode (Lua, Apache-2.0, the repository, the author); every inner page has a BreadcrumbList ending at its own canonical URL. The sitemap lists every page, with one url per page, a git-derived lastmod and the same host; there is one IndexNow key file at the root, named by 32 hex digits and containing exactly the key.'),
    ...sec(r'budgets, motion and contrast'),
    ...para('--', r'HTML under 80 KB, CSS under 40 KB, JS under 12 KB, and the initial load under 1.5 MB, counting the HTML, CSS, JS, favicon and every image that is not lazy. The JS file passes node --check. The CSS honours prefers-reduced-motion and prefers-color-scheme. The contrast test parses the colour variables of the dark palette and of the light override in the CSS, computes the WCAG relative luminance by hand, and requires 4.5:1 for every text colour (text, strong, muted, blue, green, orange, purple, yellow) on every surface (bg, panel, code-bg), in both schemes, plus the button text on the accent. The dark palette must equal the Island Dark values literally and every colour must be in lua/island/palette.lua, apart from five that the test lists as exceptions. So the site and the editor theme share one palette by test.'),
    ...code('lua', r'tests/site_spec.lua · lines 1110-1122, 1143-1188', r'''
  it("HTML < 80 KB, CSS < 40 KB, JS < 12 KB, initial load < 1.5 MB", function()
    built()
    H.ok(size(out .. "/index.html") < 80 * 1024, "html " .. size(out .. "/index.html"))
    H.ok(size(out .. "/assets/style.css") < 40 * 1024, "css")
    H.ok(size(out .. "/assets/app.js") < 12 * 1024, "js")
    local first = size(out .. "/index.html") + size(out .. "/assets/style.css") + size(out .. "/assets/app.js") + size(out .. "/assets/favicon.svg")
    for _, t in ipairs(find(page(), "img")) do
      if t.attrs.loading ~= "lazy" then
        first = first + size(out .. "/" .. t.attrs.src)
      end
    end
    H.ok(first < 1.5 * 1024 * 1024, "initial load " .. first)
  end)
...
  it("text colours reach WCAG AA (4.5:1) on every surface, dark and light", function()
    local css = read(repo .. "/site/assets/style.css")
    local function vars(block)
      local v = {}
      for k, hex in block:gmatch("%-%-([%w%-]+):%s*(#%x%x%x%x%x%x);") do
        v[k] = hex
      end
      return v
    end
    local function lum(hex)
      local c = {}
      for i = 1, 3 do
        local x = tonumber(hex:sub(2 * i, 2 * i + 1), 16) / 255
        c[i] = x <= 0.03928 and x / 12.92 or ((x + 0.055) / 1.055) ^ 2.4
      end
      return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
    end
    local function ratio(a, b)
      local la, lb = lum(a), lum(b)
      if la < lb then
        la, lb = lb, la
      end
      return (la + 0.05) / (lb + 0.05)
    end
    local dark = vars(css:match(":root%s*{(.-)}"))
    local light = vim.tbl_extend("force", dark, vars(css:match("prefers%-color%-scheme: light%)%s*{%s*:root%s*{(.-)}")))
    H.ok(dark.bg and light.bg and light.bg ~= dark.bg, "two palettes")
    for name, v in pairs({ dark = dark, light = light }) do
      for _, fg in ipairs({ "text", "strong", "muted", "blue", "green", "orange", "purple", "yellow" }) do
        for _, bg in ipairs({ "bg", "panel", "code-bg" }) do
          local r = ratio(v[fg], v[bg])
          H.ok(r >= 4.5, ("%s: %s on %s is %.2f"):format(name, fg, bg, r))
        end
      end
      H.ok(ratio(v["on-accent"], v.blue) >= 4.5, name .. ": button text")
    end
    -- the dark palette is Island Dark's
    H.eq({ "#1e1f22", "#2b2d30", "#bcbec4", "#9da0a8", "#56a8f5", "#6aab73", "#cf8e6d", "#c77dbb", "#f2c55c" },
      { dark.bg, dark.panel, dark.text, dark.muted, dark.blue, dark.green, dark.orange, dark.purple, dark.yellow })
    local palette = read(repo .. "/lua/island/palette.lua"):lower()
    for _, hex in pairs(dark) do
      if hex ~= "#ffffff" and hex ~= "#17181b" and hex ~= "#e6e8ec" and hex ~= "#4b5059" and hex ~= "#393b40" then
        H.match(palette, hex, true, hex .. " is in the Island Dark palette")
      end
    end
  end)'''),
    ...sec(r'the deploy workflow'),
    ...para('--', r'pages.yml is read as text and checked: it passes actionlint and zizmor, pins every action by full SHA and uses no third-party deploy action, reads by default and writes only in the publish job, never runs on pull requests, runs on push to main with paths filters and manual runs, only in this repository. The push test is the sharpest: of all the lines of the workflow with code, exactly one is a git push, and it targets HEAD:refs/heads/${branch} and uses http.extraheader for the token, so the token lives in one command and not in a remote URL or config. The workflow does not echo the token, does not git remote add, and the branch is gh-pages. The repo ignores _site/.'),
    ...code('lua', r'tests/site_spec.lua · lines 1249-1271', r'''
  it("only ever pushes to the branch gh-pages, with the token in a one-shot header", function()
    local pushes = 0
    for line in code_only:gmatch("[^\n]+") do
      if line:match("git .*push") then
        pushes = pushes + 1
        H.match(line, 'HEAD:refs/heads/${branch}', true)
        H.match(line, "http.extraheader", true)
      end
    end
    H.eq(1, pushes)
    H.match(workflow, "branch=gh-pages\n", true)
    H.no_match(workflow, "git remote add", true)
    H.no_match(workflow, "git config[^\n]*extraheader", false)
    H.no_match(workflow, "echo[^\n]*GITHUB_TOKEN", false)
    H.match(workflow, "GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}", true)
    H.match(workflow, "git init -q -b", true)
    H.match(workflow, "Deploy ${short} from main", true)
    H.match(workflow, "github-actions[bot]", true)
    H.match(workflow, "ls-remote", true)
    H.match(workflow, 'if [ "$after" != "$local_sha" ]', true)
    H.match(workflow, "scripts/build-site.py --out _site --check", true)
    H.match(workflow, "Deploy from a branch", true)
  end)'''),
    ...sec(r'the guides and the plugins page'),
    ...para('--', r'The guides are five or six pages, each with a unique h1, 600 to 1200 words and its own social card; the home page links all of them; each links home, two others, the repository docs and has the README install box; README and DETAILS sections they link to must exist, anchors included. A guide may only name :Commands and leader keys that exist in the running config (a test starts from the config and looks them up). The plugins page lists exactly nine plugins as SoftwareSourceCode of the author, MIT, Lua, 0.1.0; every link on it is the repository, release, LICENSE or issues URL; every install snippet is valid Lua and lists the plugin and everything it needs; and it states MIT for the plugins and Apache-2.0 for xynovim (commit 724c508).'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'94ff2dc, 23a5114 (2026-10-16)', r'the site and its review fixes.'),
    ...pt('--', r'196c8af, 7d2f382, 159a98c, 0247401, 0da94f4 (2026-10-22)', r'platforms, acknowledgements and positioning, and removal of a tool file.'),
    ...pt('--', r'b989c1f, 1578d94, 2a66abd (2026-10-22)', r'technical SEO, guides, IndexNow key. fd6f6b2 :: a site spec fix about the lazygit key.'),
    ...pt('--', r'09bc3ea, f7b8cf0, 536e5cc, 724c508, 764702c (2026-10-22)', r'positioning review, voice, licence line, plugin specs.'),
  ],
);
