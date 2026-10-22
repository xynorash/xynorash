import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/diffview.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'diffview.lua — the Git tool window: diff, merge, history'),
    cm('--', r'five keys, one fallback chain for the base branch, one safe close'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'plugin spec for sindrets/diffview.nvim: lazy commands, <leader>g keys, merge layout'),
    kv(r'language', r'Lua, a lazy.nvim plugin spec with one inline function'),
    kv(r'size', r'40 lines, 5 commits (dc15d79 to 0247401, 2026-10-09 to 2026-10-22)'),
    kv(r'keys', r'<leader>gv, gV, gF (normal and visual), gq'),
    kv(r'merge keys', r'<leader>co / ct / cb / ca (documented in the header, owned by diffview)'),
    ...sec(r'why this file exists'),
    ...para('--',
        r'The header describes the role in one sentence: a visual diff, merge-conflict and '
        r'file-history UI, the same idea as the Git tool windows of the JetBrains IDEs. That last '
        r'clause was rewritten on 2026-10-22 (commit 0247401, "Positioning: a personal project '
        r'inspired by JetBrains, not a competitor"); before it, the header named a specific '
        r'JetBrains IDE. The behaviour did not change in that commit, only how the project describes '
        r'itself.'),
    blank,
    ...para('--',
        r'Inline hunks and blame are gitsigns’ job (see gitsigns.lua). What a hunk marker cannot do '
        r'is show a three-way merge, a branch compared with its upstream, or the history of one '
        r'file. Those three jobs are the three keys in this file that open diffview, and a fourth '
        r'key exists to close it safely.'),
    ...sec(r'lazy loading'),
    ...code('lua', r'lua/plugins/diffview.lua · lines 1-8', r'''
-- Visual diff / merge-conflict / file-history UI (same idea as the
-- Git tool windows of the JetBrains IDEs). Merge conflicts: :DiffviewOpen during a merge opens the 3-way
-- view; <leader>co / ct / cb / ca pick ours / theirs / base / all in a hunk.
return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles" },
  keys = {
    { "<leader>gv", "<cmd>DiffviewOpen<cr>", desc = "Diffview: working tree / conflicts" },'''),
    blank,
    ...para('--',
        r'The plugin loads only on its four commands (DiffviewOpen, DiffviewClose, '
        r'DiffviewFileHistory, DiffviewToggleFiles) or on the first of the keys. The keys are '
        r'declared in the spec, so lazy.nvim creates stubs for them and loads the plugin when one is '
        r'pressed. Nothing diffview-related runs at startup.'),
    ...sec(r'the base branch picker, <leader>gV'),
    ...code('lua', r'lua/plugins/diffview.lua · lines 9-30', r'''
    {
      "<leader>gV",
      function()
        -- origin/HEAD only exists after a clone (or `git remote set-head`)
        local root = vim.fs.root(0, ".git") or vim.uv.cwd()
        vim.fn.system({ "git", "-C", root, "rev-parse", "--git-dir" })
        if vim.v.shell_error ~= 0 then
          return vim.notify("not a git repository", vim.log.levels.WARN)
        end
        for _, base in ipairs({ "origin/HEAD", "origin/main", "origin/master" }) do
          vim.fn.system({ "git", "-C", root, "rev-parse", "-q", "--verify", base })
          if vim.v.shell_error == 0 then
            return vim.cmd("DiffviewOpen " .. base .. "...HEAD")
          end
        end
        vim.notify(
          "no origin/HEAD, origin/main or origin/master here (git remote set-head origin -a sets it)",
          vim.log.levels.WARN
        )
      end,
      desc = "Diffview: branch vs origin",
    },'''),
    blank,
    ...para('--',
        r'<leader>gV opens the current branch compared with the remote’s default branch, using the '
        r'three-dot form base...HEAD so that the diff shows the changes since the branches diverged, '
        r'which is the shape of a pull request. The interesting part is how it finds the base.'),
    blank,
    ...para('--',
        r'The comment on line 12 is the reason for the loop: origin/HEAD only exists after a clone '
        r'(or after git remote set-head). A repository created with git init and pushed to a remote '
        r'has no origin/HEAD, so a fixed base would fail there. The function tries three refs in '
        r'order: origin/HEAD, origin/main, origin/master. The first one that git rev-parse -q '
        r'--verify accepts wins.'),
    blank,
    ...para('--',
        r'Before the loop there is a separate check. The function finds a root with vim.fs.root(0, '
        r'".git") or the current directory, then asks git rev-parse --git-dir. If that fails, it '
        r'warns "not a git repository" and returns. This ordering matters: the test named "outside a '
        r'git repository: WARN `not a git repository`, not `no origin`" exists because without the '
        r'first check a non-repository would produce the misleading second message.'),
    blank,
    ...para('--',
        r'If no base ref exists the function tells the user how to fix it instead of failing '
        r'quietly: "no origin/HEAD, origin/main or origin/master here (git remote set-head origin -a '
        r'sets it)". The message is one WARN notification; the spec asserts that no DiffviewOpen is '
        r'issued and no git error leaks out.'),
    ...sec(r'history keys and the safe close'),
    ...code('lua', r'lua/plugins/diffview.lua · lines 31-35', r'''
    { "<leader>gF", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: file history" },
    { "<leader>gF", ":DiffviewFileHistory<cr>", mode = "x", desc = "Diffview: selection history" },
    -- write first: closing with an unsaved conflict buffer raised a raw E445 from tabclose
    { "<leader>gq", "<cmd>silent! wall<cr><cmd>DiffviewClose<cr>", desc = "Diffview: close" },
  },'''),
    blank,
    ...para('--',
        r'<leader>gF in normal mode opens the history of the current file (% is the buffer’s file). '
        r'The same key in visual mode runs :DiffviewFileHistory on the selection, which opens the '
        r'commits that changed those lines, a log -L style view. Two modes, one key, one mnemonic.'),
    blank,
    ...para('--',
        r'The comment on line 33 explains <leader>gq in a single line: closing with an unsaved '
        r'conflict buffer raised a raw E445 from tabclose. Neovim refuses to close a tab page that '
        r'contains a modified buffer if that would abandon it, so the close key writes everything '
        r'first. silent! wall writes all modified buffers and does not complain if some cannot be '
        r'written, then DiffviewClose runs.'),
    blank,
    ...para('--',
        r'A consequence worth stating: <leader>gq saves every modified buffer, not only the conflict '
        r'file. This is a deliberate trade, because the alternative is an error message from the '
        r'middle of a merge. The comment does not say what happens to a buffer that wall cannot '
        r'write; the code shows only that the error is silenced.'),
    ...sec(r'options'),
    ...code('lua', r'lua/plugins/diffview.lua · lines 36-40', r'''
  opts = {
    enhanced_diff_hl = true,
    view = { merge_tool = { layout = "diff3_mixed" } },
  },
}'''),
    blank,
    ...pt('--', r'enhanced_diff_hl = true',
        r'diffview’s option for finer highlighting of the changed parts of lines inside a diff, '
        r'instead of coloring whole lines.'),
    ...pt('--', r'layout = diff3_mixed',
        r'the layout of the merge tool: the header says :DiffviewOpen during a merge opens the 3-way '
        r'view. The mixed layout is one of diffview’s named layouts, used here for merge conflicts '
        r'only. File diffs are not affected by it.'),
    ...sec(r'merge-conflict keys'),
    ...para('--',
        r'The header line "<leader>co / ct / cb / ca pick ours / theirs / base / all in a hunk" is '
        r'documentation only. The file does not define those keys; they belong to diffview’s own '
        r'conflict keymaps, which are active in its merge view. The comment keeps the whole workflow '
        r'readable from one place.'),
    ...sec(r'how it is tested'),
    ...pt('--', r'tests/git-lint-supply-chain_spec.lua, describe "diffview.nvim"',
        r'line 57: the plugin is lazy on its four commands with the diff3_mixed and enhanced_diff_hl '
        r'options. Line 65: :DiffviewOpen in a repository with a change opens a file-panel tab, so '
        r'the plugin works with the installed version and not only in the spec.'),
    ...pt('--', r'same file, describe "<leader>gV base selection"',
        r'line 123: origin/HEAD wins over origin/main and origin/master. Line 133: origin/main wins '
        r'over origin/master. Line 141: origin/master is used when it is the only one. Line 147: '
        r'outside a git repository, WARN "not a git repository". Line 158: without any origin ref, '
        r'exactly one WARN, no DiffviewOpen, no git error.'),
    ...pt('--', r'tests/keymaps-global_spec.lua',
        r'also refers to diffview, checking the keys are registered globally.'),
    ...sec(r'history'),
    ...pt('--', r'dc15d79 (2026-10-09, "wip-s6a")',
        r'first version of the file.'),
    ...pt('--', r'b65284f (2026-10-13, "Batch 3: data safety")',
        r'the commit message lists "gV fallback" among its items: the origin/main and origin/master '
        r'fallback after origin/HEAD.'),
    ...pt('--', r'98c9bb4 and 3f868dd (2026-10-13)',
        r'two field-test rounds touched the file; their messages are long lists of unrelated fixes '
        r'and do not say which line of this file changed, so this page does not attribute a specific '
        r'line to them.'),
    ...pt('--', r'0247401 (2026-10-22)',
        r'the header rewording described above.'),
    ...sec(r'is it in xyno-plugins?'),
    ...para('--',
        r'No. It is configuration for an upstream plugin and was not part of the extraction of Rust '
        r'plugins on 2026-10-22. xyno-history.nvim covers the editor’s local history, which is a '
        r'different feature from git history.'),
  ],
);
