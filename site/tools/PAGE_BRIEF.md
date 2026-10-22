# Brief: write portfolio pages from real source files

Site: Flutter web app in ~/projects/xynorash/site, a Neovim-in-the-browser portfolio for Nash Tefison (Xynorash). Each project is a directory in the explorer tree; each PAGE explains ONE real file of the repo, at the same path. Pages are Dart files calling makePage(...).

## Read first
- Two finished pages for format and voice: lib/data/pages/xynorash-pwsh/install_ps1.dart (script) and lib/data/pages/xyno-scholar/README_md.dart (README).
- Helpers: lib/data/authoring.dart (cm, para, pt, sec, code, text, bullet, kv, makePage). para/pt/sec for code files (comment-prefixed prose); text/bullet for markdown pages.

## Layout and naming
- File: lib/data/pages/<project>/<slug>.dart with one top-level `final Buffer page = makePage('<project>/<real repo path>', lines: [...]);`, imports '../../../models/project.dart' and '../../authoring.dart'.
- Slug: '/' -> '__', then every other non-alphanumeric char -> '_'.
- Only a project's top-level README.md passes repo: '<repo name without owner>', summary:, fallbackStars: 0, fallbackPushed: 'YYYY-MM-DD'. No other page may carry repo/summary.

## Content rules (hard)
1. EVIDENCE ONLY. Read the real file and `git log -p --follow <file>` first. Never invent behaviour, numbers, dates or motives; if unclear, say what the code shows and stop. Don't trust READMEs/docs over code.
2. Excerpts: ...code('<lang>', r'<repo path> · lines A-B', r'''...''') with every non-blank line VERBATIM from that file (tabs stay tabs). A line of only `...` is allowed between non-adjacent lines.
3. Rich, inspiring, informative: 150-450 lines (READMEs 250+; tiny files 60-100). Banner (cm lines), kv header, then sec(...) sections: why the file exists, how it works (walk the excerpts), design decisions/trade-offs, edge cases and failure modes, how it is tested (name the real spec), history (real short hashes + dates). Explain the THINKING.
4. No Co-Authored-By / AI-assistance / model-name mentions in prose. Voice: Xynorash writing about their own project.
5. Skip binaries, lockfiles, images, LICENSE text.
6. Dart: no empty spans (use `blank`, never plain('')); r'''...''' for code; typographic apostrophe (’) in prose.

## Verify
`python3 -I tools/check_pages.py <repo_root> <project> <pages...>` (run from site/) then `dart analyze <pages...>` (PATH needs ~/sdk/flutter-sdk/bin). Fix every failure. Don't run flutter test/build, don't touch git, don't edit outside lib/data/pages/<your project>/. Finish with a short report: pages written, gaps, and bugs noticed in the source repo (file:line).
