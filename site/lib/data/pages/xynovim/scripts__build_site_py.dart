import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/scripts/build-site.py',
  lines: [
    cm(r'#', '──────────────────────────────────────────'),
    cm(r'#', r'scripts/build-site.py'),
    cm(r'#', r'site/ plus the media it uses becomes _site/'),
    cm(r'#', r'standard library only, and it checks its own links'),
    cm(r'#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'assembles the GitHub Pages site; run by CI and by the site spec'),
    kv(r'language', r'Python 3, standard library only'),
    kv(r'size', r'258 lines, four commits (94ff2dc to b989c1f, 2026-10-16 to 2026-10-22)'),
    kv(r'usage', r'python3 scripts/build-site.py [--out _site] [--check]'),
    kv(r'output', r'pages, only the referenced media, sitemap.xml, .nojekyll'),
    ...sec(r'why this file exists'),
    ...para(r'#', r'The website is hand-written HTML in site/, with no framework and no build tool. It still needs a build step, and the docstring lists what it does. The pictures and videos live in docs/media where the README uses them (62 MB in the current checkout), and the script copies only the ones the pages reference. The numbers on the page (tests, spec files, skipped, failures, commit, date) must be the same as in the README and cannot be typed twice. A sitemap needs dates. And a broken link on a static site is silent until a reader meets it. build-site.py does these four things using only the Python standard library (its docstring says so).'),
    blank,
    ...code('python', r'scripts/build-site.py · lines 1-35', r'''
#!/usr/bin/env python3
"""Assemble the website: site/ + the referenced docs/media files -> _site/.

    python3 scripts/build-site.py [--out _site] [--check]

- copies site/ (without site/README.md) into the output directory;
- the pages are site/index.html and every site/**/index.html (the guides under
  site/guides/<slug>/); 404.html is not a page of the sitemap;
- copies ONLY the media files that those pages reference (src, href, poster,
  srcset, resolved against the page, landing in media/) from docs/media/ to
  <out>/media/ and fails when one is missing;
- substitutes the placeholders in the .html / .xml / .txt files, so the
  numbers cannot drift from the README: {{TESTS}} {{SPECS}} {{SKIPPED}}
  {{FAILED}} {{COMMIT}} {{DATE}};
- writes <out>/sitemap.xml from the pages, with lastmod from git (the last
  commit that touched the page's source; today's date without git history);
- writes <out>/.nojekyll;
- with --check, afterwards verifies every built page: every local
  href/src/poster/srcset target exists and every #anchor (also of another
  page) has its id.

Standard library only.
"""
import argparse
import datetime
import os
import re
import shutil
import subprocess
import sys
from html.parser import HTMLParser

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEXT_EXT = (".html", ".xml", ".txt")
BASE = "https://xynorash.github.io/xynovim/"
'''),
    ...para(r'#', r'The docstring doubles as the command-line help: argparse takes its description from the first line of it. Note one sentence: 404.html is not a page of the sitemap. That is not special-cased in the code. It follows from the definition of a page, which is any directory that holds an index.html, and 404.html is not one.'),
    blank,
    ...sec(r'reading references out of HTML'),
    ...code('python', r'scripts/build-site.py · lines 38-75', r'''
class Refs(HTMLParser):
    """Every local file reference of a page: src, href, poster, srcset."""

    def __init__(self):
        super().__init__()
        self.refs = []

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if not value:
                continue
            if name in ("src", "href", "poster"):
                self.refs.append(value)
            elif name == "srcset":
                self.refs.extend(part.split()[0] for part in value.split(",") if part.strip())


def is_external(ref):
    return bool(re.match(r"^(https?:|mailto:|data:|//)", ref))


def media_refs(html, page):
    """Names under docs/media that `page` (a path relative to site/) references."""
    p = Refs()
    p.feed(html)
    found = []
    pagedir = os.path.dirname(page)
    for ref in p.refs:
        ref = ref.split("#")[0].split("?")[0]
        if not ref or is_external(ref):
            continue
        parts = [x for x in ref.split("/") if x not in ("", ".", "..")]
        norm = os.path.normpath(os.path.join(pagedir, ref))
        if norm.startswith("media" + os.sep):
            found.append(norm[len("media" + os.sep):])
        elif parts and parts[0] == "media":
            sys.exit("build-site: media reference leaves docs/media: " + ref)
    return sorted(set(found))
'''),
    ...para(r'#', r'Refs is a small HTMLParser subclass that collects every src, href and poster value, and splits srcset on commas to keep the URL before the descriptor. It does not use a regular expression on the markup, so attributes in odd orders or with single quotes do not matter. is_external recognises http, https, mailto, data and protocol-relative links, and everything else is local.'),
    blank,
    ...para(r'#', r'media_refs resolves each local reference against the directory of the page that contains it, which is what a browser does. A guide in guides/slug/ writes ../../media/x.png and ends up as media/x.png; that part after media/ is the name to copy from docs/media. The last branch is the guard against escaping docs/media. It first appeared in 23a5114 (the website review fixes) in a simpler form, a check on the name after media/, and b989c1f rewrote it for page-relative paths: a reference whose first segment is media but that does not resolve under media/ stops the build with the message media reference leaves docs/media.'),
    blank,
    ...sec(r'checking the built output'),
    ...code('python', r'scripts/build-site.py · lines 78-129', r'''
class Ids(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if name == "id" and value:
                self.ids.add(value)


def resolve(out, page, ref):
    """The file a local reference of `page` points at (a directory means its index.html)."""
    path = ref.split("#")[0].split("?")[0]
    target = os.path.normpath(os.path.join(out, os.path.dirname(page), path)) if path else os.path.join(out, page)
    if os.path.isdir(target):
        target = os.path.join(target, "index.html")
    return target


def check(out, pages):
    """Fail on a dangling local reference or anchor in any built page."""
    ids = {}

    def ids_of(path):
        if path not in ids:
            i = Ids()
            with open(path, encoding="utf-8") as f:
                i.feed(f.read())
            ids[path] = i.ids
        return ids[path]

    bad = []
    total = 0
    for page in pages:
        with open(os.path.join(out, page), encoding="utf-8") as f:
            refs = Refs()
            refs.feed(f.read())
        for ref in refs.refs:
            total += 1
            if is_external(ref):
                continue
            target = resolve(out, page, ref)
            if not os.path.isfile(target):
                bad.append("%s -> %s" % (page, ref))
                continue
            frag = ref.split("#")[1] if "#" in ref else ""
            if frag and target.endswith(".html") and frag not in ids_of(target):
                bad.append("%s -> %s" % (page, ref))
    if bad:
        sys.exit("build-site: dangling references: " + ", ".join(sorted(set(bad))))
    print("build-site: %d references in %d pages checked, all resolve" % (total, len(pages)))
'''),
    ...para(r'#', r'check runs on the output directory and not on the sources, so it tests what readers will get, after substitution. For each page it parses the references again. External ones are skipped. A local one is resolved, with a directory meaning its index.html, and must be a file. If it has a fragment and points to an HTML file, the fragment must be an id in that file; ids are parsed once per file and cached. This reaches across pages: a guide that links to a section of the home page is checked against that page’s ids. All failures are collected and reported in one sorted, de-duplicated message, so a build with five bad links says five, not one.'),
    blank,
    ...sec(r'numbers that cannot drift'),
    ...code('python', r'scripts/build-site.py · lines 132-158', r'''
def readme_numbers():
    with open(os.path.join(ROOT, "README.md"), encoding="utf-8") as f:
        readme = f.read()
    m = re.search(r"badge/tests-(\d+)%20passing", readme)
    if not m:
        sys.exit("build-site: the tests badge of README.md was not found")
    tests = m.group(1)
    skipped = failed = None
    m = re.search(r"(\d+) skipped with a stated reason, (\d+) failing", readme)
    if m:
        skipped, failed = m.group(1), m.group(2)
    return tests, skipped, failed


def count_specs():
    d = os.path.join(ROOT, "tests")
    return str(len([n for n in os.listdir(d) if n.endswith("_spec.lua")]))


def commit():
    sha = os.environ.get("GITHUB_SHA", "").strip()
    if not sha:
        try:
            sha = subprocess.run(["git", "-C", ROOT, "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
        except (OSError, subprocess.CalledProcessError):
            sha = "unknown"
    return sha[:7]
'''),
    ...para(r'#', r'The README is the source of truth for the test count. The script reads the number out of the badge URL, badge/tests-N%20passing, and fails if that badge is not there. Skipped and failed come from the sentence N skipped with a stated reason, N failing, and are allowed to be missing: they stay None, which is an error only if a page actually uses the placeholder. The number of spec files comes from the tests directory itself. The commit is GITHUB_SHA in CI or git rev-parse HEAD locally, shortened to seven characters, and unknown when neither works.'),
    blank,
    ...para(r'#', r'The consequence is a design rule: the page says what the README says, because it is built from it. tests/site_spec.lua has a group of tests that compares the page to the README, including that the numbers are the README’s and the spec count is the directory’s.'),
    blank,
    ...sec(r'pages and the sitemap'),
    ...code('python', r'scripts/build-site.py · lines 161-188', r'''
def site_pages(src):
    """Paths (relative to site/, '/' separated) of every page: index.html and */index.html."""
    pages = []
    for dirpath, _, files in os.walk(src):
        if "index.html" in files:
            rel = os.path.relpath(os.path.join(dirpath, "index.html"), src)
            pages.append(rel.replace(os.sep, "/"))
    return sorted(pages, key=lambda p: (p != "index.html", p))


def lastmod(paths, today):
    """Date of the last commit that touched any of `paths` (relative to the repo root)."""
    try:
        r = subprocess.run(["git", "-C", ROOT, "log", "-1", "--format=%cs", "--"] + paths, capture_output=True, text=True, check=True)
        return r.stdout.strip() or today
    except (OSError, subprocess.CalledProcessError):
        return today


def write_sitemap(out, pages, today):
    lines = ['<?xml version="1.0" encoding="UTF-8"?>', '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    for page in pages:
        url = BASE + page[: -len("index.html")]
        sources = ["site/" + page] + (["README.md"] if page == "index.html" else [])
        lines += ["  <url>", "    <loc>%s</loc>" % url, "    <lastmod>%s</lastmod>" % lastmod(sources, today), "  </url>"]
    lines.append("</urlset>")
    with open(os.path.join(out, "sitemap.xml"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
'''),
    ...para(r'#', r'site_pages walks the source folder and collects every index.html, sorted with the home page first. The sitemap URL of a page is the base URL plus the path without the file name. lastmod is the date of the last commit that touched the page’s source (the home page also depends on README.md, since its numbers come from there), and today’s date when git is not available. Running without git history still gives a valid sitemap.'),
    blank,
    ...sec(r'main: the sequence'),
    ...code('python', r'scripts/build-site.py · lines 191-228', r'''
def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=os.path.join(ROOT, "_site"))
    ap.add_argument("--check", action="store_true", help="verify local references and anchors of the built page")
    args = ap.parse_args()
    out = os.path.abspath(args.out)
    src = os.path.join(ROOT, "site")
    media_src = os.path.join(ROOT, "docs", "media")

    pages = site_pages(src)
    if "index.html" not in pages:
        sys.exit("build-site: site/index.html is missing")
    wanted = set()
    for page in pages:
        with open(os.path.join(src, page), encoding="utf-8") as f:
            wanted.update(media_refs(f.read(), page))
    wanted = sorted(wanted)
    missing = [n for n in wanted if not os.path.isfile(os.path.join(media_src, n))]
    if missing:
        sys.exit("build-site: missing in docs/media: " + ", ".join(missing))

    today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    tests, skipped, failed = readme_numbers()
    subst = {
        "TESTS": tests,
        "SPECS": count_specs(),
        "SKIPPED": skipped,
        "FAILED": failed,
        "COMMIT": commit(),
        "DATE": today,
    }

    if os.path.isdir(out):
        shutil.rmtree(out)
    shutil.copytree(src, out, ignore=shutil.ignore_patterns("README.md"))
    os.makedirs(os.path.join(out, "media"))
    for name in wanted:
        shutil.copyfile(os.path.join(media_src, name), os.path.join(out, "media", name))
'''),
    ...para(r'#', r'main fails early. A missing site/index.html stops the build. The media each page needs is collected before anything is copied, and every missing file is reported at once. The output directory is deleted and recreated, so a stale file from an earlier build cannot be published. copytree ignores README.md, which is documentation for the folder and not part of the site.'),
    blank,
    ...code('python', r'scripts/build-site.py · lines 230-258', r'''
    for dirpath, _, files in os.walk(out):
        for fn in files:
            if not fn.endswith(TEXT_EXT):
                continue
            path = os.path.join(dirpath, fn)
            with open(path, encoding="utf-8") as f:
                text = f.read()
            for key, value in subst.items():
                token = "{{%s}}" % key
                if token in text:
                    if value is None:
                        sys.exit("build-site: %s is used in %s but the README does not state it" % (token, fn))
                    text = text.replace(token, value)
            left = re.findall(r"\{\{[A-Z]+\}\}", text)
            if left:
                sys.exit("build-site: unknown placeholder %s in %s" % (left[0], fn))
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)

    write_sitemap(out, pages, today)
    with open(os.path.join(out, ".nojekyll"), "w", encoding="utf-8"):
        pass
    if args.check:
        check(out, pages)
    print("build-site: %s (%d pages, %d media files, tests %s, specs %s, commit %s)" % (out, len(pages), len(wanted), tests, subst["SPECS"], subst["COMMIT"]))


if __name__ == "__main__":
    main()
'''),
    ...para(r'#', r'Every .html, .xml and .txt file in the output is searched for placeholders. A placeholder with no value is an error that names the file; a placeholder left over after substitution (found with a regular expression for double braces and capitals) is also an error. Files are written with newline set to LF, a change from 9641d08, because without it Python on Windows translates newlines to CRLF; the commit that added it is titled as LF output of the Python tools, part of the fixes from the first full Windows and macOS runs. The last steps write the sitemap and an empty .nojekyll (a marker file that tells GitHub Pages not to run Jekyll), then run check if asked, and print one summary line.'),
    blank,
    ...sec(r'how it is tested'),
    ...para(r'#', r'tests/site_spec.lua runs the script and asserts on the result: it succeeds and checks its own references; the required files exist, with .nojekyll and without the source README; only the referenced media is copied; the build fails on an unknown placeholder and on a missing media file; and it refuses a media reference that leaves docs/media. Other groups in the same spec check the built pages (head tags, structure, no external requests, Content Security Policy).'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt(r'#', r'no template engine', r'six placeholders written as double braces and a string replace. Less power, and nothing to learn or break.'),
    ...pt(r'#', r'checks in the builder', r'the same code that copies the files proves that their links work; CI runs it with --check.'),
    ...pt(r'#', r'fail on unknown placeholders', r'a typo like {{TEST}} is a build failure, not text on a live site.'),
    ...pt(r'#', r'dates from git', r'lastmod comes from the last commit that touched the page’s source, so it changes when the page does and not on every build.'),
    ...sec(r'history'),
    ...pt(r'#', r'94ff2dc 2026-10-16', r'added with site/, the deploy workflow and the specs.'),
    ...pt(r'#', r'23a5114 2026-10-16', r'website review fixes: the guard against media paths that leave docs/media.'),
    ...pt(r'#', r'9641d08 2026-10-16', r'first full Windows and macOS runs: written files use LF.'),
    ...pt(r'#', r'b989c1f 2026-10-22', r'technical SEO: several pages instead of one, the sitemap, page-relative media, check across pages.'),
  ],
);
