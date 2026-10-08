import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/README.md',
  summary: 'LazyVim on Omarchy/Arch tuned for Rust',
  repo: 'xynovim',
  fallbackStars: 1,
  fallbackPushed: '2026-09-04',
  lines: [
    heading('# xynovim'),
    blank,
    ...text('The Neovim configuration I run on Linux (Omarchy on '
        'Arch), built on LazyVim and tuned for one job: writing '
        'Rust with the always-on feedback of a JetBrains IDE. Its '
        'centrepiece is a two-tier diagnostics pipeline. '
        'rust-analyzer’s own in-memory diagnostics appear 155 to '
        '235 ms after a keystroke, and clippy’s deeper lints '
        'follow with a median edit-to-diagnostic time of 0.56 s, '
        'both before the file is saved. Getting there meant '
        'measuring a slow first attempt, deleting a second cargo '
        'pipeline, and finally patching an upstream language '
        'server, bacon-ls, and sending the fix to its '
        'maintainers as crisidev/bacon-ls#139. Everything else '
        'is small on purpose: 759 lines of Lua in 16 files, 58 '
        'pinned plugins, and a 478-line CHANGELOG that records, '
        'for every change, what was measured and how it was '
        'checked. The project was called xyno-neovim until the '
        'rename commit 5e60f65 on 2026-09-03.'),
    blank,
    kv('base', 'LazyVim (install_version 8) · extras neo-tree, lang.rust'),
    kv('platform', 'Linux, Omarchy/Arch; the Windows lineage is on windows-legacy'),
    kv('history', '27 commits, 2026-08-17 to 2026-09-04, on 6 distinct days'),
    kv('size', '759 lines of Lua in 16 files, 25 tracked files in all'),
    kv('measured', 'instant tier 155-235 ms · clippy tier 0.56 s median'),
    kv('startup', '28.7 ms down to about 18 ms (CHANGELOG 1.3.0)'),
    kv('releases', '0.1.0 to 1.4.1, all in CHANGELOG.md; no git tags'),
    kv('tests', 'none in the repo; 35-check E2E suite lives in ~/.bacon-e2e'),

    ...sec('the problem, and why it is harder than it looks'),
    ...text('RustRover draws a red squiggle as you type and a clippy '
        'suggestion a moment later, without saving. The CHANGELOG '
        'names that behaviour as the goal from its first entry: '
        '“RustRover-style” feedback, “matches the inline '
        'error-message style from JetBrains IDEs”. Neovim does '
        'not do this out of the box, and the reason is more '
        'interesting than it sounds.'),
    ...text('Rust feedback comes from two very different sources. '
        'rust-analyzer computes type errors, unresolved names and '
        'typos in memory, with no cargo run (the comment in '
        'lua/plugins/rustaceanvim.lua says exactly that). Clippy '
        'answers a deeper question, whether this is good Rust, '
        'but it needs a real cargo run over files on disk, and '
        'an unsaved buffer is not on disk. Running cargo on every '
        'keystroke is expensive, running it on save is late, and '
        'anything in between has to answer questions that sound '
        'easy: where does the unsaved text go, what happens when '
        'a second run is requested while the first is still '
        'going, and how do you know a diagnostic belongs to the '
        'text now on the screen?'),
    ...text('This repository is the record of working through those '
        'questions in the order they hurt. The story has three '
        'acts, and the commit history makes them easy to see.'),
    ...bullet('act one, 2026-08-17 and 18, the Windows config',
        'rust-analyzer with check.command set to clippy, then a '
        'chain of four commits in 64 minutes to make diagnostics '
        'refresh while typing: update_in_insert, a missing '
        'textDocument/didSave, a missing TextChangedI, and a '
        'regression from the fix itself. The details are in the '
        'CHANGELOG page.'),
    ...bullet('act two, 2026-09-02 and 03, LazyVim on Linux',
        'the migration, then bacon-ls with updateOnInsert so '
        'clippy runs on unsaved text. The first version worked '
        'and was miserable: “checking (0%)” rows stacking for '
        'minutes, 5.6 s from edit to diagnostic.'),
    ...bullet('act three, 2026-09-04, the bug upstream',
        'a stuck-progress bug traced into bacon-ls itself, a '
        'locally patched build with a 35-check test harness, and '
        'a pull request.'),

    ...sec('the system in one picture'),
    plain('  you type'),
    plain('    |  didChange on every edit, before any save'),
    plain('    +--> rust-analyzer'),
    plain('    |      diagnostics computed in memory, no cargo run'),
    plain('    |      155-235 ms warm                  [instant tier]'),
    plain('    +--> bacon-ls (local patched build)'),
    plain('           dirty buffer -> hardlinked shadow workspace'),
    plain('           target/bacon-ls-live/, 500 ms debounce, then'),
    plain('           cargo clippy --workspace --all-features'),
    plain('           --no-deps; 0.56 s median       [depth tier]'),
    plain('  both publish into vim.diagnostic'),
    blank,
    plain('  auto-save, about 1 s after you stop typing'),
    plain('    write with noautocmd (no format-on-save)'),
    plain('    -> User AutoSaveWritePost -> didSave to every LSP client'),
    blank,
    ...text('The two tiers do not duplicate work. LazyVim’s lang.rust '
        'extra disables rust-analyzer’s own checkOnSave and '
        'diagnostics when one global is set to bacon-ls, and '
        'this config sets it. The instant tier is then switched '
        'back on deliberately, for diagnostics only. Three '
        'files carry the design:'),
    ...code('lua', 'lua/config/options.lua · hand the diagnostics role to bacon-ls', r'''
vim.g.lazyvim_rust_diagnostics = "bacon-ls"'''),
    ...code('lua', 'lua/plugins/rustaceanvim.lua · the instant tier (trimmed)', r'''
          diagnostics = { enable = true },
          -- Separate target dir for rust-analyzer's own cargo runs (build
          -- scripts, proc-macros) so they never contend for the build-dir
          -- file lock with terminal `cargo run`/`cargo test`.
          cargo = { targetDir = true },'''),
    ...code('lua', 'lua/plugins/bacon-ls.lua · the depth tier (trimmed)', r'''
local bacon_ls_settings = {
  backend = "cargo",
  cargo = {
    command = "clippy",
    extraArgs = { "--workspace", "--all-features", "--no-deps" },
    updateOnInsert = true,
    ...
    updateOnInsertDebounceMillis = 500,
    ...
    checkOnSave = false,
  },
}'''),
    ...text('Read the settings as a list of decisions, each with a '
        'measurement behind it. The CLI is clippy, not check, '
        'because clippy finds things check never will: the first '
        'verification in the CHANGELOG used needless_return, a '
        'lint only clippy raises. The flag list is short because '
        'every flag costs time: --all-targets was dropped since it '
        'doubled every run, --no-deps keeps clippy from '
        're-linting dependency crates after they recompile. '
        'checkOnSave is off and updateOnInsert is on, and the '
        'next two sections explain why both are the opposite of '
        'what a first guess would be.'),

    ...sec('one pipeline, not two: 5.6 s down to 0.9 s'),
    ...text('The first working version of this design (CHANGELOG '
        '1.1.0) was live but slow and churning. The root cause the 1.3.0 '
        'entry records is that two clippy pipelines were running '
        'at once: checkOnSave runs, triggered by the roughly one '
        'second auto-save, and the updateOnInsert shadow runs. '
        'They cancelled each other and serialised on cargo’s '
        'build-directory lock, and --all-targets doubled the '
        'scope of every run. The fix was subtractive: one '
        'pipeline, a smaller workload. Measured on a warmed '
        'project it went from 5.6 s to 0.8–0.9 s.'),
    ...text('The more instructive part is what the obvious '
        'simplification does. If two pipelines are the problem, '
        'turn updateOnInsert off. The comment in bacon-ls.lua '
        'records the result of trying it: the server then '
        'advertises no document sync at all, Neovim ignores its '
        'late dynamic registration, and diagnostics never '
        'refresh, with a measured “marker diagnostic never '
        'arrived in 300s”. A/B testing found the asymmetry that '
        'drives the final settings. The feature that looks '
        'redundant is the load-bearing one, and the feature that '
        'looks essential (check on save) is the one to remove.'),
    ...text('The debounce got the same treatment. In the 1.4.0 '
        'measurement, edit-to-diagnostic latency is the debounce '
        'plus about 60 ms, and an 18-keystroke burst produced 18 '
        'cargo spawns at 300 ms but exactly one at 500 or 800. So '
        'the smaller wins, and 500 ms is where the 0.56 s median '
        'comes from. The decision was made with a count of '
        'spawns, not with a feeling.'),

    ...sec('the bug that was not mine'),
    ...text('With one pipeline the editor was fast, but bacon_ls '
        'sometimes stayed stuck on “checking…” with stale '
        'diagnostics. The 1.4.0 entry traces it to bacon-ls '
        '0.29.0: it aborts its debounce task even after the '
        'sleep is over, at which point the task is the in-flight '
        'cargo run, so a keystroke (or auto-save’s didSave '
        'arriving about 200 ms into every burst’s final run) '
        'kills the run silently. The LSP progress token begins '
        'and never ends, which is the immortal “checking” row, '
        'and diagnostics go stale.'),
    ...text('Two more defects came with it, and all three went into '
        'one patch set. A save inside the debounce window could '
        'drop the only pending check when checkOnSave is off. '
        'And closing a dirty buffer left orphaned diagnostics, '
        'while cargo replayed cached warnings because the '
        'hardlink restore had moved a file’s mtime backwards. '
        'The result is a locally built binary, wired in with one '
        'line:'),
    ...code('lua', 'lua/plugins/bacon-ls.lua · the override (trimmed)', r'''
        -- crisidev/bacon-ls#139. Drop this cmd override once it merges.
        cmd = { vim.fn.expand("~/.cargo/bin/bacon-ls") },
        init_options = bacon_ls_settings,'''),
    ...text('That override, and the comment above it, show how a '
        'patched dependency is carried here: the change is one '
        'line in the config, a comment says what the upstream '
        'bug is, links the pull request, and states the '
        'condition for deleting the override. The CHANGELOG '
        'shows the second half of the discipline. In 1.4.1 the '
        'fix was redone so that it adds no struct field, because '
        'a field would set off the large_enum_variant size lint '
        'that upstream CI enforces, and the whole 35-check suite '
        'plus upstream’s 124 tests were run again on the new '
        'build. The behaviour was already identical; the '
        'reshaping was done for the maintainers’ CI, not for '
        'the local build, which worked.'),

    ...sec('the editor around the loop'),
    ...text('Several smaller files exist only to keep that loop '
        'honest. Each has its own page in this section.'),
    ...bullet('auto-save (lua/plugins/auto-save.lua)',
        'buffers are written about a second after the last '
        'change, in insert mode too (TextChangedI), with '
        'noautocmd so autosaves skip format-on-save. noautocmd also suppresses the LSP '
        'clients’ didSave, which the plugin’s own '
        'User AutoSaveWritePost event is used to re-send. The '
        'history behind it is a bug that took four commits in '
        'an afternoon and a later replacement of a monkey-patch '
        'with a supported hook.'),
    ...bullet('99 (lua/plugins/ninety-nine.lua)',
        'ThePrimeagen’s AI plugin, on the Claude Code provider. '
        'Its hard-won notes: tmp_dir must be absolute, because '
        '99 and the claude process resolve a relative path '
        'against different directories, so responses came back '
        'empty while generation worked; the logger needs '
        'type = "file" or it logs nowhere. Eleven keymaps under '
        '<leader>9, all lazy-loading the plugin.'),
    ...bullet('harpoon (lua/plugins/harpoon.lua)',
        'six keys, with a static keys table because a keys '
        'function that requires the plugin forces it to load at '
        'startup.'),
    ...bullet('rustaceanvim (lua/plugins/rustaceanvim.lua)',
        'inlay hints for closure return types and elided '
        'lifetimes, fill-arguments completion snippets, full '
        'function signatures and module-grouped auto-imports.'),
    ...bullet('Omarchy integration',
        'all-themes.lua pre-loads 20 colourscheme plugins so a '
        'desktop theme change finds its plugin already installed; '
        'omarchy-theme-hotreload.lua re-applies the theme on '
        'lazy’s reload event; transparency.lua clears the '
        'background of 40 highlight groups on every ColorScheme '
        'event; remote_clipboard.lua turns on OSC 52 copy '
        'only when the session is under tmux, SSH or herdr.'),
    ...code('lua', 'lua/plugins/auto-save.lua · the supported hook (trimmed)', r'''
    local group = vim.api.nvim_create_augroup("user_autosave_didsave", { clear = true })
    vim.api.nvim_create_autocmd("User", {
      pattern = "AutoSaveWritePost",
      group = group,
      callback = function(ev)
        local buf = ev.data and ev.data.saved_buffer
        ...
        for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
          if client:supports_method("textDocument/didSave", buf) then
            client:notify("textDocument/didSave", {
            ...'''),

    ...sec('performance: what about 18 ms is made of'),
    ...text('Startup went from 28.7 ms to about 18 ms in release '
        '1.3.0. The changelog lists the causes and does not '
        'price each one. A harpoon keys function was requiring '
        'the plugin at spec-build time and so force-loading it '
        'and plenary on every start; 99, telescope and '
        'blink.compat now load on their keymaps; the stock '
        'example.lua is deleted; the clipboard module’s /proc '
        'ancestry walk is short-circuited behind cheaper '
        'checks; four remote-plugin providers are disabled; and '
        'lazy.nvim’s update checker is off. The only item with '
        'a number in the code is the checker:'),
    ...code('lua', 'lua/config/lazy.lua · the update checker (trimmed)', r'''
  checker = {
    -- OFF: the periodic checker spawns background git fetches AND pulls
    -- lazy's whole management machinery (lazy.manage, view.commands,
    -- runner, task, process - ~6-10ms) into every startup. Update
    -- manually with :Lazy sync instead.
    enabled = false,
    notify = false,
  },'''),
    ...text('Taken at face value, the checker alone would be most of '
        'the roughly 10.7 ms saved, though the entry gives no '
        'per-item breakdown and the figures may not have been '
        'measured the same way. It does not say how startup was '
        'timed or how many runs were averaged either, so the '
        'pair of figures is one machine’s before and after, not '
        'a benchmark. The second win is behavioural: with the '
        'checker off there are no periodic background git '
        'fetches, and an update happens when :Lazy sync is run, '
        'which rewrites lazy-lock.json and shows up as a diff.'),

    ...sec('alternatives that were tried and dropped'),
    ...bullet('rust-analyzer clippy on save',
        'the setup in 1.0.0 (check.command clippy, push '
        'diagnostics with style lints). It only updates when '
        'cargo has run, which means after a save. Replaced in '
        '1.1.0 by the bacon-ls live pipeline.'),
    ...bullet('bacon-ls with the bacon backend',
        'watches the filesystem and needs a saved file. Kept as '
        'a verified-working fallback in ~/.config/bacon/prefs.toml, '
        'unused.'),
    ...bullet('both pipelines at once',
        '5.6 s and stacked progress rows. Removed in 1.3.0.'),
    ...bullet('a 300 ms debounce', '18 spawns for 18 keystrokes.'),
    ...bullet('an 800 ms debounce',
        'chosen in 1.3.0, reversed in 1.4.0 as “compensating for '
        'the now-fixed abort bug”.'),
    ...bullet('a generation counter in the fork',
        'the first form of the abort fix. Reworked in 1.4.1 to '
        'add no struct field.'),
    ...bullet('a vim.cmd proxy for didSave',
        'two versions of it (a plain function that broke '
        'vim.cmd.helptags, then a metatable proxy) before 1.3.0 '
        'replaced it with User AutoSaveWritePost.'),
    ...bullet('a relative tmp_dir for 99',
        'a “./tmp” attempt that was never pushed and still broke '
        'whenever nvim’s cwd was not the project root.'),

    ...sec('a timeline from git history'),
    ...text('All times are +0300, from git log. Of the 27 commits, '
        '18 fall on 17 and 18 August, one on the 28th, and the '
        'other 8 between 2 and 4 September.'),
    ...bullet('2026-08-17 14:22, 1c496fd',
        'initial commit: a minimal config for Rust, TypeScript, '
        'PowerShell and Flutter plus 99, “inspired by '
        'ThePrimeagen’s init.lua … but built from scratch”. 17 '
        'files, 540 insertions.'),
    ...bullet('2026-08-17 16:02, 3dacffb',
        'IDE-like diagnostics, inlay hints and clippy, '
        'auto-save, 99 bumped to claude-sonnet-5 at --effort '
        'medium. The first CHANGELOG. Merged as PR #1.'),
    ...bullet('2026-08-18, 15 commits, PRs #2 to #7',
        'between 12:57 and 16:16: the lightbulb and an ESLint '
        'check, the four-commit diagnostics chain, a lualine '
        'statusline, a colourscheme ported from RustRover’s '
        'Islands Dark, the move to OneDrive and a full device '
        'bootstrap script.'),
    ...bullet('2026-08-28 15:44, 9fff81e',
        'a README tweak. This is the tip of windows-legacy.'),
    ...bullet('2026-09-02 23:42, eabb22a',
        'the migration to LazyVim on Linux, release 1.0.0: 40 '
        'files, 1,147 insertions and 1,273 deletions.'),
    ...bullet('2026-09-03 07:05, 3ec11c4',
        'live-as-you-type diagnostics through bacon-ls, 1.1.0.'),
    ...bullet('2026-09-03 07:37, 07993a4',
        'empty 99 responses fixed, README rewritten, 1.2.0.'),
    ...bullet('2026-09-03 12:36, 5e60f65',
        'renamed to xynovim.'),
    ...bullet('2026-09-03 19:54, f35b4f6',
        'two tiers, startup work, bug fixes, 1.3.0.'),
    ...bullet('2026-09-04 01:18, 0715b98',
        'the patched bacon-ls and a 500 ms debounce, 1.4.0.'),
    ...bullet('2026-09-04 07:25 and 07:28, 6aeebfd and 77149b8',
        'the fix upstreamed as #139 and rebuilt on 0.30.0, '
        '1.4.1, then a README correction three minutes later.'),
    ...text('Two process facts show in the log. During the Windows '
        'era most units of work came through a feature branch and '
        'a pull request (seven merges, all on 17 and 18 August); '
        'after the migration there are no merge commits at all.'),

    ...sec('a tour of the tree'),
    ...text('Everything below is a real path. The README’s own '
        'layout section is three lines:'),
    ...code('md', 'README.md · Layout (trimmed)', r'''
lua/config/    options, keymaps, autocmds, remote clipboard
lua/plugins/   one spec per concern (bacon-ls, rustaceanvim, ninety-nine, auto-save, …)
plugin/after/  transparency'''),
    ...bullet('init.lua',
        'two lines. It requires config.lazy and nothing else.'),
    ...bullet('lua/config/lazy.lua',
        '57 lines. Bootstraps lazy.nvim from git if missing, then '
        'declares the spec: LazyVim plus an import of '
        'lua/plugins. Custom plugins load eagerly by default, '
        'version = false follows the latest commit, the update '
        'checker is off, and five runtime plugins are disabled.'),
    ...bullet('lua/config/options.lua',
        '18 lines. Starts the remote-clipboard setup, turns off '
        'relative numbers and global autoformat, disables the '
        'python3, ruby, perl and node providers, and sets the '
        'rust diagnostics global to bacon-ls.'),
    ...bullet('lua/config/remote_clipboard.lua',
        '103 lines. Copy as OSC 52, paste from the Wayland '
        'clipboard when one exists, only for sessions under '
        'tmux, SSH or herdr.'),
    ...bullet('lua/config/keymaps.lua, autocmds.lua',
        '3 and 8 lines, both only comments. '
        'Every custom keymap in the config lives in a plugin '
        'spec, with a desc for which-key.'),
    ...bullet('lua/plugins/bacon-ls.lua',
        '63 lines, 40 of them comments. The pipeline above.'),
    ...bullet('lua/plugins/rustaceanvim.lua', '38 lines. The instant tier and the inlay hints.'),
    ...bullet('lua/plugins/ninety-nine.lua', '79 lines. 99 and its eleven keymaps.'),
    ...bullet('lua/plugins/auto-save.lua', '53 lines. Auto-save and the didSave hook.'),
    ...bullet('lua/plugins/harpoon.lua', '24 lines. Mark and jump between files.'),
    ...bullet('lua/plugins/all-themes.lua',
        '120 lines. Twenty colourscheme plugins, all lazy, so '
        'every Omarchy theme is already installed.'),
    ...bullet('lua/plugins/omarchy-theme-hotreload.lua',
        '103 lines. A local spec (dir = the config directory) '
        'that re-runs the theme on lazy’s reload event.'),
    ...bullet('lua/plugins/theme.lua',
        'a symbolic link, not a file with Lua in it. It points '
        'to ../../../../.local/state/omarchy/current/theme/'
        'neovim.lua, the file Omarchy rewrites when the desktop '
        'theme changes. The relative path only resolves if this '
        'repository is checked out at ~/.config/nvim, which is '
        'where the code implies it lives.'),
    ...bullet('disable-news-alert.lua, snacks-animated-scrolling-off.lua',
        '9 and 8 lines. LazyVim news popups off, scroll '
        'animation off.'),
    ...bullet('plugin/after/transparency.lua',
        '71 lines. Clears the background of 40 highlight '
        'groups and re-applies on every ColorScheme event.'),
    ...bullet('lazy-lock.json',
        '60 lines, 58 plugins, each a branch and a commit. '
        'Written by lazy.nvim, never by hand.'),
    ...bullet('lazyvim.json',
        'records the enabled extras (editor.neo-tree, lang.rust) '
        'and the LazyVim install version (8).'),
    ...bullet('stylua.toml, .neoconf.json',
        'formatter settings (two-space indent, 120 columns) and '
        'lua_ls library settings. Five Lua files are tab '
        'indented anyway: all-themes, disable-news-alert, '
        'omarchy-theme-hotreload, snacks-animated-scrolling-off '
        'and transparency.'),
    ...bullet('CHANGELOG.md', '478 lines. The evidence log.'),
    ...bullet('LICENSE', 'Apache-2.0, 201 lines, from the LazyVim starter.'),
    ...bullet('.gitignore',
        'eight patterns (tt.*, .tests, doc/tags, debug, .repro, '
        'foo.*, *.log, data), last changed in the migration '
        'commit.'),
    ...text('What is not here is also a decision. There is no '
        'colourscheme of its own (Omarchy supplies it), no LSP '
        'setup for TypeScript, PowerShell or Flutter (removed in '
        '1.0.0 with the note that this machine’s config is '
        '“currently scoped to Rust”), no custom keymaps file and '
        'no formatter or linter configuration beyond stylua.toml. '
        'Whatever LazyVim does well stays untouched.'),

    ...sec('building and running it'),
    ...text('This is a personal configuration, so “running it” means '
        'adopting my setup. The facts the repository supports:'),
    ...bullet('location',
        'the theme symlink and the hot-reload spec (dir = '
        'vim.fn.stdpath("config")) both assume the repository is '
        'the Neovim config directory, ~/.config/nvim on Linux.'),
    ...bullet('first launch',
        'lua/config/lazy.lua clones lazy.nvim (the stable branch, '
        'blobless) if it is missing, and exits with an error '
        'message if the clone fails. lazy.nvim then installs the '
        'plugins, with lazy-lock.json recording the commits.'),
    ...bullet('requires (README)',
        'rust-analyzer on PATH; bacon-ls at ~/.cargo/bin/bacon-ls, '
        'the local patched build, installed with cargo install '
        '--path ~/.local/src/bacon-ls-upstream, not Mason’s '
        'copy; mold and clang from pacman. The bacon binary is '
        'not needed by the cargo backend.'),
    ...bullet('for 99',
        'the Claude Code command line tool, which '
        'ClaudeCodeProvider invokes, and a working login.'),
    ...bullet('optional',
        'wl-copy and wl-paste for the Wayland side of the '
        'clipboard; an Omarchy install for the theme file.'),
    ...bullet('outside the repo',
        '~/.cargo/config.toml (mold through clang and '
        'profile.dev.debug = "line-tables-only"), '
        '~/.config/bacon/prefs.toml, the patched bacon-ls source '
        'and the E2E suite.'),
    ...bullet('updating',
        ':Lazy sync, as the README and lazy.lua both say. '
        'Because the checker is off, nothing updates until then.'),

    ...sec('key numbers'),
    ...bullet('27 commits, 7 PR merges', '6 distinct days.'),
    ...bullet('759 lines of Lua', '16 files, plus one symlink.'),
    ...bullet('58 plugins pinned', '20 of them colourschemes.'),
    ...bullet('5.6 s → 0.8–0.9 s', 'one pipeline instead of two.'),
    ...bullet('155–235 ms', 'rust-analyzer native diagnostics, warm.'),
    ...bullet('0.56 s median', 'edit to clippy diagnostic, warm.'),
    ...bullet('500 ms', 'debounce; latency is debounce + ~60 ms.'),
    ...bullet('28.7 → ~18 ms', 'startup.'),
    ...bullet('35 checks, 120-op soak', '9.5 MB resident, zero leaked tokens.'),
    ...bullet('124 upstream tests', 'passed with the patch applied.'),
    ...bullet('17 of 20', 'non-merge commits edit CHANGELOG.md.'),

    ...sec('how it was checked'),
    ...text('There is no test directory in the repository. The '
        'checking is described in the CHANGELOG, and most of it '
        'is headless Neovim: probes that count LSP notifications, '
        'list extmarks, evaluate the statusline and read hex '
        'values from highlight groups. The strongest piece of '
        'evidence is the 35-check end-to-end suite for the '
        'patched server, with a tiny crate, a three-crate '
        'workspace and a randomized 120-operation soak, which '
        'reports zero leaked progress tokens, no stray cargo '
        'processes and a resident size of 9.5 MB afterwards. It lives in ~/.bacon-e2e/, outside the '
        'repository, so a reader sees its description and '
        'results but cannot run it from a clone.'),

    ...sec('limits and honest notes'),
    ...bullet('one machine, one platform',
        'every number is from my Linux machine. Nothing here '
        'has been tried on another system, and the theme '
        'symlink dangles anywhere Omarchy is not installed.'),
    ...bullet('not reproducible from the repo alone',
        'the patched server, the cargo config, the bacon prefs '
        'and the test harness live in the home directory. The '
        'README tells you where they are; it cannot ship them.'),
    ...bullet('no automated tests or CI',
        'the lockfile has been exercised only on the machine '
        'that wrote it.'),
    ...bullet('one comment is stale',
        'lua/config/options.lua says bacon “watches the '
        'filesystem and re-runs clippy on every (auto)save”. '
        'That describes the unused bacon backend. The cargo '
        'backend configured in bacon-ls.lua runs clippy itself '
        'on every buffer change. Both were written in the same '
        'commit, 3ec11c4.'),
    ...bullet('the README contradicts itself once',
        'it says manual :w still formats and, a few lines later, '
        'that format-on-save is off globally. The code '
        'sets vim.g.autoformat = false, which is authoritative.'),
    ...bullet('a branch name',
        'CHANGELOG 1.0.0 says the old config stays on master; the '
        'README and the remote say windows-legacy.'),
    ...bullet('two latency figures',
        'CHANGELOG 1.4.0 gives an “error tier” of 0.68 s while '
        '1.3.0 measured native diagnostics at 155–235 ms. They '
        'may be different probes; the entry does not say.'),
    ...bullet('the patch depends on a merge',
        'the override stays until #139 lands. I could not '
        'check its status from the repository, only the '
        'instruction to drop the override once it merges.'),

    ...sec('what is next'),
    ...text('The repository states two follow-ups and no more. '
        'Remove the cmd override in bacon-ls.lua when '
        'crisidev/bacon-ls#139 merges. And keep the five '
        'single-theme plugins in all-themes.lua “until 3.8 is '
        'out of support”, the comment’s condition for the older '
        'Omarchy release. Beyond those, this is a configuration '
        'that is allowed to stop growing: LazyVim carries the '
        'rest.'),

    ...sec('what I would like you to take from it'),
    ...bullet('measure, then choose',
        'the debounce is a count of spawns, the pipeline change '
        'is 5.6 s against 0.9 s, the startup figure is a before '
        'and an after. None of the settings are folklore.'),
    ...bullet('subtract before you add',
        'the biggest improvement here was deleting a pipeline.'),
    ...bullet('fix it at the root, upstream',
        'a stuck progress bar led to a defect in someone else’s '
        'server, a harness, and a pull request, and the local '
        'override carries its own removal condition.'),
    ...bullet('write down the reason next to the line',
        'nearly every non-obvious setting in the Lua has a '
        'comment explaining why, and the CHANGELOG explains how '
        'it was checked.'),
    ...bullet('state what you could not verify',
        'the changelog says when headless Neovim cannot '
        'reproduce something, instead of pretending.'),
    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
