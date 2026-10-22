import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/gitsigns.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'gitsigns.lua — signs for files git does not know yet'),
    cm('--', r'attach_to_untracked = true'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'gitsigns option override'),
    kv(r'language', r'Lua, a lazy.nvim plugin spec'),
    kv(r'size', r'6 lines, 1 commit (0494b52, 2026-10-12)'),
    kv(r'touches', r'opts.attach_to_untracked of lewis6991/gitsigns.nvim'),
    ...sec(r'why this file exists'),
    ...para('--',
        r'gitsigns draws the added / changed / removed marks in the sign column. By default it '
        r'attaches only to files git already tracks. That is a reasonable default for a mature '
        r'repository and a poor one for the first minutes of a new project, which is exactly when '
        r'this editor is used for Rust: cargo new makes a fresh crate, and git init has not produced '
        r'a commit yet.'),
    blank,
    ...para('--',
        r'The comment in the file puts it directly: in a fresh repo with no commits, every file is '
        r'untracked and would otherwise get no signs at all. The file exists to remove that gap. It '
        r'is a field-test fix: the commit that added it is titled "Field test fixes: sandbox '
        r'hardening, local history, nav/search, debug; docs" and is dated 2026-10-12.'),
    ...sec(r'the whole file'),
    ...code('lua', r'lua/plugins/gitsigns.lua · lines 1-6', r'''
-- Show gitsigns for untracked files too (e.g. a fresh repo with no commits,
-- where every file is untracked and would otherwise get no signs at all).
return {
  "lewis6991/gitsigns.nvim",
  opts = { attach_to_untracked = true },
}'''),
    blank,
    ...para('--',
        r'The first two lines are the explanation, the next four are the spec. The only option set '
        r'is attach_to_untracked = true, which makes gitsigns attach to untracked files and show the '
        r'whole file as added.'),
    blank,
    ...para('--',
        r'As in codelens.lua there is no config function. lazy.nvim merges the opts into the plugin '
        r'spec that LazyVim already provides, so everything else about gitsigns, including its '
        r'keymaps and its hunk text objects, stays at the LazyVim defaults.'),
    ...sec(r'how it works, as far as the repo shows'),
    ...para('--',
        r'The repo does not contain gitsigns, so what happens inside is only what the test says. The '
        r'test asserts the observable result: an untracked file in a repo without commits gets 3 '
        r'signs, and gets 0 without the override. That is a before / after pair, so the test fails '
        r'if the option is removed, which is the point of testing a configuration file.'),
    ...sec(r'how it is tested'),
    ...pt('--', r'tests/git-lint-supply-chain_spec.lua',
        r'the describe block "gitsigns attach_to_untracked". One test asserts the plugin opts set it '
        r'to true (line 191), and another builds a repository with no commit and an untracked file, '
        r'and counts the signs: 3 with the setting, 0 without it (line 195).'),
    ...pt('--', r'tests/startup-and-options_spec.lua',
        r'line 670 repeats the option check and the untracked-file check from the point of view of '
        r'the startup configuration, using opts_of for gitsigns.nvim.'),
    ...sec(r'history'),
    ...pt('--', r'0494b52 (2026-10-12)',
        r'added the file, in the same commit as the first sandbox hardening and the local history '
        r'work. It is the only commit that touches this file.'),
    ...sec(r'trade-offs'),
    ...para('--',
        r'Showing signs on untracked files costs nothing for a tracked project, because tracked '
        r'files are unaffected. The one visible side effect is that a new untracked file shows a '
        r'column of added marks on every line. The author’s choice is that this is information (the '
        r'file is new) rather than noise. The file does not claim anything beyond that, and neither '
        r'does this page.'),
    ...sec(r'is it in xyno-plugins?'),
    ...para('--',
        r'No. It configures an upstream plugin and none of the extracted Rust plugins carries a copy '
        r'of it.'),
  ],
);
