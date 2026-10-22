import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/options.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'options.lua — what has to be true before any plugin loads'),
    cm('--', '81 lines: PATH, options, providers, one switch, and the setup() calls'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'early settings, loaded by LazyVim before plugin specs; also the wiring point for config modules'),
    kv('language', 'Lua'),
    kv('size', '81 lines (was 18 on 2026-09-03)'),
    kv('origin', 'starter stub, then grown over 18 commits'),
    kv('history', 'eabb22a (2026-09-02) to ff1c8fa (2026-10-16)'),

    ...sec('why this file exists'),
    ...para('--',
        'LazyVim loads user options earlier than anything else it '
        'configures: the call sits in its init(), which runs while '
        'lazy.nvim is still reading plugin specs. The order inside the '
        'call is LazyVim’s own lazyvim.config.options first and then this '
        'file, so anything written here overrides the framework. A '
        'setting belongs here if a plugin spec reads it while it is '
        'being built, or if it must exist before the first buffer is '
        'drawn.'),
    ...para('--',
        'The file has changed character. On 2026-09-03 it was 18 lines '
        'of overrides. It is now 81 lines and has a second job: it is '
        'the place where every self-contained module under lua/config '
        'is switched on with a setup() call (lines 2, 64 to 81). The '
        'options are the first half of the file, the wiring the '
        'second.'),

    ...sec('the clipboard comes first'),
    ...code('lua', 'lua/config/options.lua · clipboard', r'''
-- Options are automatically loaded before lazy.nvim startup.
require("config.remote_clipboard").setup()'''),
    ...para('--',
        'The order is deliberate. Neovim’s documentation says '
        'g:clipboard has to be set before the clipboard providers are '
        'initialised, which happens when something calls '
        'has("clipboard"). Making it the first statement of the earliest '
        'user file is the cheapest way to be sure. The module returns '
        'without touching anything unless the session is inside tmux, '
        'SSH or herdr. It also exists as the standalone plugin '
        'xyno-clipboard.nvim (~/projects/xyno-plugins), split into '
        'detect.lua and init.lua; the copy in this repository is a '
        'single 108-line file and has its own page.'),

    ...sec('putting rustup on PATH'),
    ...code('lua', 'lua/config/options.lua · lines 4-25', r'''
-- rustup's proxies (rust-analyzer, cargo) live in ~/.cargo/bin: a start from a desktop launcher or
-- another non-login environment lacks it, and opening a .rs file raised a rustaceanvim error
local win = vim.fn.has("win32") == 1
local sep = win and ";" or ":"
local cargo_home = vim.env.CARGO_HOME
local cargo_bin = vim.fs.joinpath(cargo_home and cargo_home ~= "" and cargo_home or vim.fs.joinpath(vim.uv.os_homedir(), ".cargo"), "bin")
local function norm(p)
  p = vim.fs.normalize(p):gsub("/+$", "")
  return win and p:lower() or p
end
if vim.uv.fs_stat(cargo_bin) then
  local present = false
  for entry in vim.gsplit(vim.env.PATH or "", sep, { plain = true }) do
    if entry ~= "" and norm(entry) == norm(cargo_bin) then
      present = true
      break
    end
  end
  if not present then
    vim.env.PATH = (vim.env.PATH or "") .. sep .. cargo_bin
  end
end'''),
    ...para('--',
        'The comment states the failure: a launch from a desktop '
        'launcher or another non-login environment does not have '
        '~/.cargo/bin on PATH, rustup’s proxies for rust-analyzer and '
        'cargo are not found, and opening a .rs file raised a '
        'rustaceanvim error. The block appends the directory, once.'),
    ...pt('--', 'CARGO_HOME',
        'respected when set and non-empty, otherwise the home directory '
        'plus .cargo. The result ends in bin.'),
    ...pt('--', 'Windows',
        'the separator is a semicolon and norm() lowercases, because '
        'Windows paths compare case-insensitively. This part was added '
        'in ff1c8fa (2026-10-16, “Windows and macOS: portability '
        'fixes”), the commit that also introduced the has("win32") '
        'branch.'),
    ...pt('--', 'duplicate check',
        'the loop splits PATH with vim.gsplit(plain = true) and '
        'compares normalised entries, so a trailing slash or a different '
        'case on Windows does not produce a second copy. If the '
        'directory does not exist (fs_stat fails) nothing is changed.'),
    ...pt('--', 'append, not prepend',
        'a toolchain already earlier on PATH keeps winning; the block '
        'only fills in what is missing.'),
    ...para('--',
        'The behaviour is tested: tests/startup-and-options_spec.lua '
        'around line 203 builds a child Neovim with a PATH of '
        '/usr/bin:/bin and asserts the cargo bin directory is appended, '
        'then starts one that already contains it and asserts PATH is '
        'unchanged.'),

    ...sec('overrides of LazyVim defaults'),
    ...code('lua', 'lua/config/options.lua · overrides', r'''
vim.opt.relativenumber = false
vim.g.autoformat = false

-- Floats (hover, signature help, diagnostics, completion docs) get a rounded
-- border: with a solid NormalFloat and a transparent editor they had no edge.
-- Plugins that set their own border are unaffected.
vim.o.winborder = "rounded"
-- LazyVim blends the popup menu by 10%, which let the buffer text show
-- through the menu rows (right-click menu, wildmenu).
vim.o.pumblend = 0'''),
    ...pt('--', 'relativenumber = false',
        'LazyVim turns relative numbers on. The migration flipped the '
        'setting off. No commit message gives a reason, so it reads as '
        'a preference.'),
    ...pt('--', 'autoformat = false',
        'LazyVim defaults vim.g.autoformat to true, which makes every '
        'write pass through a formatting hook. With false, formatting '
        'exists only on request (<leader>cf).'),
    ...pt('--', 'winborder = rounded',
        'added in 99acd7e (2026-10-13, “Batch 4: editing and UI”). The '
        'comment gives the reason: the theme has a solid NormalFloat '
        'over a transparent editor, so floats had no visible edge. '
        'tests/ux-menu-diagnostics-colourblind_spec.lua line 661 asserts '
        'both winborder and pumblend.'),
    ...pt('--', 'pumblend = 0',
        'the same commit. With LazyVim’s 10 percent blend the buffer '
        'text showed through the right-click and wildmenu rows.'),

    ...sec('four providers, switched off'),
    ...code('lua', 'lua/config/options.lua · providers', r'''
-- No remote-plugin hosts are in use: skip provider probing entirely
-- (removes startup/health overhead; zero effect on UI or LSP).
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0'''),
    ...para('--',
        'Remote plugins are plugins written in another language that '
        'talk to Neovim through a host process. Neovim looks for hosts '
        'for Python 3, Ruby, Perl and Node on demand, and :checkhealth '
        'reports on them. Setting g:loaded_<name>_provider to 0 is '
        'Neovim’s documented opt-out. It arrived in f35b4f6 '
        '(2026-09-03) in the “zero background activity” group of '
        'CHANGELOG 1.3.0, next to the update-checker change in '
        'lua/config/lazy.lua. The repository gives no separate timing '
        'for these lines; the measured figure belongs to the commit '
        'as a whole (28.7 ms to about 18 ms).'),

    ...sec('nextest progress bar, and the breadcrumb'),
    ...code('lua', 'lua/config/options.lua · lines 45-54', r'''
-- neotest runs nextest in a pty, so nextest drew its live progress bar and the
-- output panel (<leader>to) held cursor-up/erase-line redraws instead of the
-- failure text. (The bar is also gone from nextest runs in a Snacks terminal.)
vim.env.NEXTEST_HIDE_PROGRESS_BAR = vim.env.NEXTEST_HIDE_PROGRESS_BAR or "1"

-- The lualine breadcrumb is LazyVim's editor.navic one (it shows
-- `impl Shape for Square`): with Trouble's symbols component (the default
-- when this is true) navic's insert is skipped, and Trouble's kind filter
-- drops impl blocks.
vim.g.trouble_lualine = false'''),
    ...para('--',
        'Both arrived in 98c9bb4 (2026-10-13, “Final loop round 1: field '
        'test and spec findings”). The first is an environment default '
        'that respects an existing value (x or "1"): neotest runs '
        'cargo nextest in a pty, so the live progress bar wrote '
        'cursor-up and erase-line sequences into the output panel '
        'instead of the failure text. The second keeps the navic '
        'breadcrumb, which can show impl blocks, instead of Trouble’s '
        'symbols component, which filters them out. Line 340 and 341 of '
        'tests/startup-and-options_spec.lua assert both values, and '
        'tests/snippets-completion-injections_spec.lua line 600 checks '
        'that the lualine navic component matches the setting.'),

    ...sec('the switch that shapes the Rust setup'),
    ...code('lua', 'lua/config/options.lua · rust diagnostics', r'''
-- Rust diagnostics via bacon-ls (lua/plugins/bacon-ls.lua): its native cargo
-- backend runs clippy itself on every buffer change (no bacon process) and
-- sends the results as LSP diagnostics. The lang.rust extra reads this and
-- turns off rust-analyzer's checkOnSave and diagnostics so cargo runs once;
-- rustaceanvim.lua switches the native in-memory diagnostics back on.
vim.g.lazyvim_rust_diagnostics = "bacon-ls"'''),
    ...para('--',
        'One line of code, and it is the hinge of the repository. The '
        'lang.rust extra in lazyvim.json reads '
        'vim.g.lazyvim_rust_diagnostics when its module is loaded, '
        'defaulting to "rust-analyzer", which is why the global is set '
        'here in the earliest file and not in a plugin spec that would '
        'run after the extra has already decided. With "bacon-ls" the '
        'extra turns rust-analyzer’s checkOnSave and diagnostics off '
        'and enables the bacon_ls server; lua/plugins/rustaceanvim.lua '
        'turns the native diagnostics back on as the instant tier.'),
    ...para('--',
        'The comment above the line was rewritten (it used to say bacon '
        'watches the filesystem and re-runs clippy on each save, which '
        'described the older backend). It now matches lua/plugins/'
        'bacon-ls.lua: the cargo backend runs clippy itself on every '
        'buffer change and no bacon process is involved.'),

    ...sec('the setup() calls'),
    ...code('lua', 'lua/config/options.lua · lines 63-81', r'''
-- Local History: shadow-ref snapshots on every (throttled) save.
require("config.local_history").setup()

-- Auto-save safety: no writes into dependency sources or over files that
-- changed on disk; save everything a multi-file rename touched.
require("config.disk_guard").setup()

-- :RustContext (cargo features / target for both diagnostic tiers).
require("config.rust_context").setup()
require("config.rust_tasks").setup()
require("config.rust_routes").setup()
require("config.egui_new").setup()
require("config.rust_new").setup()

-- Rust server readiness in the statusline, right-click menu, Neovide,
-- opt-in colourblind palette.
require("config.lsp_status").setup()
require("config.rust_restart").setup()
require("config.ux").setup()'''),
    ...para('--',
        'Each module registers its own commands, autocmds and keymaps '
        'inside setup(), so this file is a table of contents. The '
        'history of the list is the history of the project: local_history '
        'arrived in 8e212cf, rust_context in f5936dc, rust_tasks in '
        '025f7a6, rust_routes in 527f350 (all 2026-10-09), lsp_status and '
        'ux in bdd0225, rust_restart in be73b6c (2026-10-12), disk_guard '
        'in b65284f (2026-10-13), egui_new in ddc51eb (2026-10-15) and '
        'rust_new in d163480 (2026-10-16).'),
    ...pt('--', 'standalone copies',
        'on 2026-10-22 several of these were also extracted into '
        'repositories under ~/projects/xyno-plugins: xyno-history.nvim '
        '(local_history), xyno-guard.nvim (disk_guard), xyno-new.nvim '
        '(egui_new and rust_new), and xyno-rust.nvim, which contains '
        'rust_context, rust_tasks, rust_routes, lsp_status and '
        'rust_restart among others. This file still requires the '
        'config.* modules, so the extraction has not changed the '
        'wiring here.'),
    ...pt('--', 'why options.lua',
        'these modules set up autocmds and commands that must exist '
        'before the first buffer loads. LazyVim loads this file at the '
        'right moment, so the repository has no separate plugin spec '
        'for most of them.'),

    ...sec('what is not here, and where it went'),
    ...para('--',
        'The first commit had 37 lines of private defaults. The '
        'migration to LazyVim (eabb22a) replaced them with LazyVim’s '
        'own defaults: tabstop and shiftwidth now 2, scrolloff 4, '
        'updatetime 200, undofile on, and the leader on space, all '
        'from LazyVim’s options file. Moving from private defaults to '
        'overrides is the point of choosing a framework: the file now '
        'records where this setup disagrees with LazyVim, or where it '
        'must act before LazyVim does.'),

    ...sec('limits'),
    ...pt('--', 'order-sensitive',
        'moving the clipboard line below a call that touches the '
        'clipboard would defeat it, and nothing would say so.'),
    ...pt('--', 'one failure stops the rest',
        'the setup() calls are plain requires. If one module throws '
        'while loading, the lines after it in this file do not run.'),
    ...pt('--', 'unreasoned preferences',
        'relativenumber and autoformat are recorded without rationale.'),

    blank,
    link('→ github.com/xynorash/xynovim', 'https://github.com/xynorash/xynovim'),
  ],
);
