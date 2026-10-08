import '../../models/project.dart';
import '../authoring.dart';

final Buffer xynovimBuffer = Buffer(
  id: 'xynovim',
  fileName: 'xynovim.lua',
  icon: '\u{e620}',
  filetype: 'lua',
  repo: 'xynovim',
  summary: 'LazyVim tuned for Rust · sub-second clippy',
  fallbackStars: 1,
  fallbackPushed: '2026-09-04',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'xynovim — the config this site is cosplaying'),
    cm('--', 'LazyVim on Omarchy/Arch, tuned for Rust'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('base', 'LazyVim · extras: lang.rust, neo-tree'),
    kv('platform', 'Linux — Omarchy / Arch'),
    kv('startup', '~18 ms (down from 29)'),
    kv('releases', '1.0.0 → 1.4.1, every change in CHANGELOG.md'),

    ...sec('how I treat an editor config'),
    ...para('--',
        'A config is software with users — me, every day — and '
        'the failure mode of most configs is that nobody can say '
        'why a line exists. So the rule here is that every '
        'non-obvious setting carries the reason next to it, and '
        'every change is in CHANGELOG.md with what was measured '
        'and how. The comments in the files below are real; the '
        'numbers are measurements, not vibes.'),
    blank,
    ...para('--',
        'Structurally: one plugin spec per concern, nothing '
        'configured twice, and LazyVim’s defaults kept wherever '
        'they are already right. v1.0.0 was a deliberate '
        'platform switch — a from-scratch Windows config '
        'replaced by LazyVim on Linux — not an incremental edit, '
        'and the old tree still lives on the windows-legacy '
        'branch.'),

    ...sec('the problem: diagnostics that are fast and deep'),
    ...para('--',
        'In Rust there are two kinds of feedback. rust-analyzer '
        'answers “is this type-correct?” in memory, almost '
        'instantly. Clippy answers “is this good Rust?” but needs '
        'a real cargo run. I wanted both, live, without saving: '
        'RustRover-style feedback in Neovim. The first '
        'configuration worked and was miserable — diagnostics '
        'took seconds and “checking (0%)” rows stacked up for '
        'minutes.'),
    blank,
    ...para('--',
        'Instead of tweaking by feel, I measured. Two cargo '
        'pipelines were running: clippy on save (triggered by '
        'the ~1 s auto-save) and clippy on every change. They '
        'cancelled each other and queued on cargo’s build-dir '
        'file lock, and --all-targets doubled every run. The fix '
        'was subtractive:'),
    ...code('lua', 'lua/plugins/bacon-ls.lua (trimmed)', r'''
local bacon_ls_settings = {
  backend = "cargo",
  cargo = {
    command = "clippy",
    extraArgs = { "--workspace", "--all-features", "--no-deps" },
    updateOnInsert = true,
    updateOnInsertDebounceMillis = 500,
    -- OFF deliberately: with ~1s auto-save, checkOnSave is a
    -- second run pipeline racing the updateOnInsert one.
    -- Single pipeline measured 0.8-0.9s edit-to-diagnostic
    -- vs 5.6s with both pipelines on.
    checkOnSave = false,
  },
}'''),
    ...pt('--', 'one pipeline',
        'checkOnSave off, so there is exactly one cargo run in '
        'flight: 5.6 s → under a second.'),
    ...pt('--', 'updateOnInsert must stay on',
        'learned by A/B test. Without it the server advertises '
        'no document sync at initialise time, Neovim ignores its '
        'late dynamic registration, and diagnostics never '
        'refresh at all — a marker diagnostic never arrived in '
        '300 s. That is why it lives in init_options, not '
        'settings: the server needs it at handshake.'),
    ...pt('--', 'the 500 ms debounce',
        'measured with real keystroke bursts. Any debounce '
        'longer than the typing cadence coalesces a burst into one '
        'cargo spawn: 500 and 800 ms both spawned once for an '
        '18-keystroke burst, 300 ms spawned 18 times. 500 ms is '
        'the smallest value I tested that coalesces, giving 0.56 s median '
        'latency with no churn.'),
    ...pt('--', '--no-deps, no --all-targets',
        'do not re-lint crates that merely recompiled; test '
        'targets can run in CI.'),
    blank,
    ...para('--',
        'The instant tier is rust-analyzer’s native diagnostics, '
        'left on (150–250 ms warm). The only cost is cosmetic: a '
        'type error may briefly appear from both sources. I '
        'accepted that rather than suppress one — duplicate '
        'display is a cheaper failure than a missing one.'),

    ...sec('when the tool is the bug: patching bacon-ls'),
    ...para('--',
        'With one pipeline, a sharper problem remained. Typing '
        'during a run silently killed it. Reading the source: the '
        'debounce task is aborted on the next keystroke even '
        'after its sleep has finished — and at that point the '
        'task is no longer waiting, it is the cargo run. The '
        'progress token never closed, so “checking…” rows '
        'stacked, and diagnostics went stale.'),
    blank,
    ...para('--',
        'I fixed it locally in three parts, wrote a 35-check '
        'headless end-to-end suite to prove each, then reworked '
        'the fix so it adds no struct field (upstream CI runs '
        'clippy with a size lint) and filed it upstream as a '
        'pull request. The config points at the patched binary '
        'and says exactly when to delete the override:'),
    ...code('lua', 'lua/plugins/bacon-ls.lua (excerpt)', r'''
bacon_ls = {
  -- Locally patched build (upstream 0.30.0 + our fix
  -- branch), NOT the Mason binary. Filed as
  -- crisidev/bacon-ls#139. Drop this cmd override once
  -- it merges.
  cmd = { vim.fn.expand("~/.cargo/bin/bacon-ls") },
  init_options = bacon_ls_settings,
  settings = { bacon_ls = bacon_ls_settings },
},'''),
    ...pt('--', 'fix 1 — run supersession',
        'the debounce task drops its own handle once its sleep '
        'is over, so abort() can only cancel a trigger that is '
        'still sleeping. In-flight runs are superseded through '
        'CancelRunning, which closes progress tokens properly.'),
    ...pt('--', 'fix 2 — save inside the window',
        'with checkOnSave off, a save no longer cancels the '
        'only pending live check; before, a save landing mid-'
        'debounce silently skipped a check.'),
    ...pt('--', 'fix 3 — closing a dirty buffer',
        'orphaned diagnostics are cleared, and the shadow file '
        'is restored by copy so it has a fresh mtime. Restoring '
        'by hardlink kept the old mtime, so cargo replayed the '
        'dirty build’s cached warnings.'),
    link('→ bacon-ls PR #139', 'https://github.com/crisidev/bacon-ls/pull/139'),

    ...sec('auto-save that language servers can live with'),
    ...para('--',
        'Auto-save with a ~1 s debounce is what makes the live '
        'diagnostics loop feel continuous. But the plugin writes '
        'with noautocmd so format-on-save does not fire on every '
        'autosave — and noautocmd also suppresses the '
        'BufWritePost that makes Neovim send textDocument/didSave '
        'to language servers. bacon-ls needs that notification to '
        'restore its shadow workspace. Confirmed directly: a '
        'noautocmd write sends zero LSP notifications; a normal '
        'write sends didSave.'),
    ...code('lua', 'lua/plugins/auto-save.lua (trimmed)', r'''
vim.api.nvim_create_autocmd("User", {
  pattern = "AutoSaveWritePost",
  group = group,
  callback = function(ev)
    local buf = ev.data and ev.data.saved_buffer
    if not (buf and vim.api.nvim_buf_is_valid(buf)) then
      return
    end
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
      if client:supports_method("textDocument/didSave", buf) then
        client:notify("textDocument/didSave", {
          textDocument = { uri = vim.uri_from_bufnr(buf) },
        })
      end
    end
  end,
})'''),
    ...para('--',
        'The first version monkey-patched vim.cmd and matched the '
        'plugin’s internal command string — it broke silently '
        'whenever upstream renamed anything, and put a metatable '
        'in front of every vim.cmd call in the session. I '
        'replaced it with the plugin’s own supported '
        'AutoSaveWritePost user event. A second subtlety: '
        'TextChanged only fires outside insert mode, so '
        'defer_save also lists TextChangedI, or nothing would '
        'save while you are still typing.'),

    ...sec('rust-analyzer, tuned instead of defaulted'),
    ...code('lua', 'lua/plugins/rustaceanvim.lua (trimmed)', r'''
["rust-analyzer"] = {
  diagnostics = { enable = true },
  -- Separate target dir for rust-analyzer's own cargo runs
  -- so they never contend for the build-dir file lock with
  -- terminal `cargo run` / `cargo test`.
  cargo = { targetDir = true },
  inlayHints = {
    closureReturnTypeHints = { enable = "with_block" },
    lifetimeElisionHints = { enable = "skip_trivial",
                             useParameterNames = true },
  },
  completion = {
    callable = { snippets = "fill_arguments" },
    fullFunctionSignatures = { enable = true },
  },
},'''),
    ...para('--',
        'targetDir = true is the same lesson as the diagnostics '
        'work, applied elsewhere: when two tools share one build '
        'directory they share one lock, and “why is cargo '
        'waiting?” is the question to ask first. Outside the repo '
        'the build is sped up too — mold as the linker and '
        'line-tables-only debuginfo (backtraces kept, the cost '
        'dropped) — documented in the README because it lives in '
        '~/.cargo/config.toml.'),

    ...sec('clipboard that follows you over SSH'),
    ...para('--',
        'Yanking inside tmux or over SSH normally leaves the text '
        'trapped on the remote machine. The module emits every '
        'copy as an OSC 52 escape sequence (tmux rebroadcasts it '
        'to attached clients), but prefers the local Wayland '
        'clipboard for paste so text copied in other apps still '
        'pastes. The part worth reading is how it decides whether '
        'to activate at all:'),
    ...code('lua', 'lua/config/remote_clipboard.lua (trimmed)', r'''
-- Ordered cheapest-first so the /proc ancestor walk
-- (16 process-file reads) only runs when no env var has
-- already decided the answer.
local relevant = vim.env.TMUX ~= nil
  or vim.env.SSH_TTY ~= nil
  or vim.env.SSH_CONNECTION ~= nil
  or vim.env.HERDR_PANE_ID ~= nil
  or ancestor_process_named("herdr")

if not relevant then
  return
end'''),
    ...para('--',
        'Cheap checks first, expensive last, and in a plain local '
        'terminal the whole module returns before touching /proc. '
        'That ordering is a startup-time decision as much as a '
        'correctness one.'),

    ...sec('following the OS theme live'),
    ...para('--',
        'Omarchy changes the system theme at runtime; the editor '
        'should follow without a restart. The hot-reload spec '
        'unloads the theme’s Lua modules, clears highlights, '
        'resets the background and reapplies the new colorscheme '
        '— then transparency has to be reapplied, because the '
        'new scheme repaints every background. Two bugs there are '
        'instructive, and both are in the changelog:'),
    ...code('lua', 'omarchy-theme-hotreload.lua (excerpt)', r'''
-- vim.fn.exists returns 0/1, and 0 is truthy in Lua -
-- must compare, or this branch always runs
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end'''),
    ...para('--',
        'In Lua 0 is truthy, so the unqualified check ran '
        '“syntax reset” every time. And transparency used to be '
        'applied only at startup, so a manual :colorscheme '
        'brought the opaque background back. It is now applied '
        'on every ColorScheme event inside an augroup that clears '
        'itself, which also makes the file safe for the hot-reload '
        'path to source repeatedly.'),

    ...sec('an AI assistant, with the footguns fixed'),
    ...para('--',
        'ThePrimeagen’s 99 runs on the Claude Code provider with '
        'a search-to-quickfix flow, visual-selection replace and '
        'telescope pickers for model and provider, all under '
        '<leader>9 and lazy-loaded on those keys. Everything '
        'surprising about it is in the setup:'),
    ...code('lua', 'lua/plugins/ninety-nine.lua (trimmed)', r'''
-- MUST be absolute. 99 resolves a relative tmp_dir against
-- nvim's cwd, but claude resolves the same relative
-- TEMP_FILE against the project it's working in - launch
-- nvim from outside the project and the answer lands where
-- 99 never reads, so every response comes back empty.
tmp_dir = tmp_dir,
logger = {
  -- type = "file" is required for path to take effect;
  -- without it the logger silently uses a void sink.
  type = "file",
  level = _99.DEBUG,
  path = "/tmp/" .. vim.fs.basename(vim.uv.cwd() or "nvim")
         .. ".99.debug",
},'''),
    ...para('--',
        'Two failures that look like “the tool is broken” and '
        'are really configuration: responses written to a path '
        'the reader never checks, and a logger that logs nowhere '
        'because the README example omits one key. The same '
        'file also prunes week-old request files, since 99 never '
        'cleans its own cache.'),

    ...sec('startup: 29 ms → ~18 ms by removing work'),
    ...para('--',
        'Each saving came from finding something that loaded '
        'earlier than it needed to. The clearest was harpoon:'),
    ...code('lua', 'lua/plugins/harpoon.lua (excerpt)', r'''
-- static keys table with requires deferred into the
-- callbacks: a keys FUNCTION that requires harpoon at
-- spec-build time force-loads harpoon+plenary during
-- startup, defeating lazy-loading entirely.
keys = {
  { "<leader>a",
    function() require("harpoon"):list():add() end,
    desc = "Harpoon: Add file" },
  -- ...
},'''),
    ...para('--',
        'A keys function looks harmless, but evaluating it to '
        'build the spec requires the plugin, which defeats the '
        'lazy loading it appears to configure. The other wins '
        'are the same shape: 99, telescope and blink.compat load '
        'on their keymaps; the remote-clipboard /proc walk '
        'short-circuits behind env checks; lazy.nvim’s periodic '
        'update checker is off (it re-fetched every plugin on a '
        'timer and dragged its own modules into every start); '
        'unused remote-plugin providers are disabled. Updates '
        'happen when I run :Lazy sync, on purpose.'),

    ...sec('the habit this repo shows'),
    ...para('--',
        'Measure first, change one thing, keep the reason in the '
        'file, write down what was verified, and when the bug is '
        'in someone else’s tool, fix it and send the fix '
        'upstream instead of living with a private fork '
        'forever. The layout is small on purpose:'),
    plain('lua/config/    options, keymaps, autocmds, clipboard'),
    plain('lua/plugins/   one spec per concern'),
    plain('plugin/after/  transparency'),
    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
