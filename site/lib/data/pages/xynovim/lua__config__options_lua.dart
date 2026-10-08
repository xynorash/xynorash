import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/options.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'options.lua — what has to be true before any plugin loads'),
    cm('--', '18 lines: a clipboard, two overrides, four providers, one switch'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'early settings, loaded by LazyVim before plugin specs'),
    kv('language', 'Lua'),
    kv('size', '18 lines'),
    kv('origin', 'starter stub, then grown in 3 commits'),
    kv('history', 'eabb22a, 3ec11c4, f35b4f6 (2026-09-02 to 09-03)'),

    ...sec('why this file exists'),
    ...para('--',
        'LazyVim loads user options earlier than anything else it '
        'configures. In its config module the call to load '
        'options sits in init(), which runs while lazy.nvim is '
        'still reading plugin specs, with a source comment saying '
        'why: the options must be in place “while sourcing plugin '
        'modules”. The order inside the call is LazyVim’s own '
        'lazyvim.config.options first and then this file, so '
        'anything written here overrides the framework.'),
    ...para('--',
        'That timing is the whole reason for the file. A setting '
        'belongs here if a plugin spec reads it while it is being '
        'built, or if it must exist before the first buffer is '
        'drawn. The clipboard, the provider switches and the Rust '
        'switch below all meet that test. The file is only 18 '
        'lines, but each group of lines answers a different '
        'question.'),

    ...sec('the clipboard comes first'),
    ...code('lua', 'lua/config/options.lua · clipboard', r'''
-- Options are automatically loaded before lazy.nvim startup.
require("config.remote_clipboard").setup()'''),
    ...para('--',
        'The order is deliberate. Neovim’s documentation says '
        'g:clipboard has to be set before the clipboard providers '
        'are initialised, and warns that initialisation happens '
        'when something calls has("clipboard"). The cheapest way '
        'to be sure of that is to make it the first statement of '
        'the earliest user file. The module itself is described on '
        'its own page (lua/config/remote_clipboard.lua): it '
        'returns without touching anything unless the session is '
        'inside tmux, SSH or herdr, so in a plain terminal the '
        'line costs a few environment lookups and Neovim picks '
        'its own provider as usual.'),
    ...para('--',
        'LazyVim adds a second layer of care. Right after loading '
        'options it stashes the value of the clipboard option and '
        'sets it to an empty string, and restores the stash on '
        'VeryLazy. The source comment explains that built-in '
        'clipboard detection with xsel or pbcopy “can be slow”, so '
        'the cost is moved out of the startup path. Both layers '
        'push the same way: do not pay for clipboard setup until '
        'it is needed.'),

    ...sec('two overrides of LazyVim defaults'),
    ...code('lua', 'lua/config/options.lua · overrides', r'''
vim.opt.relativenumber = false
vim.g.autoformat = false'''),
    ...pt('--', 'relativenumber = false',
        'LazyVim’s options file turns relative numbers on. The '
        'very first commit of this repository turned them on as '
        'well, and the migration flipped the setting off. No '
        'commit message or changelog line gives a reason, so it '
        'reads as a preference.'),
    ...pt('--', 'autoformat = false',
        'LazyVim defaults vim.g.autoformat to true, which makes '
        'every write pass through a BufWritePre hook that '
        'formats. Setting it to false turns that hook into a '
        'no-op: the format function returns early unless the '
        'caller passes force. Formatting still exists, on '
        'request, through the <leader>cf mapping or :LazyFormat.'),
    ...para('--',
        'The second override has a consequence that the README '
        'has not caught up with. Its auto-save paragraph says '
        'autosaves skip format-on-save “via noautocmd” and that a '
        'manual :w “still formats”. With autoformat off globally, '
        'a manual :w does not format either, as the LazyVim '
        'source shows. The noautocmd flag in lua/plugins/'
        'auto-save.lua still has a job (it keeps every '
        'BufWritePre and BufWritePost autocmd from firing during '
        'an autosave, which is why the didSave notification had '
        'to be re-sent), but the format-on-save protection is '
        'now doubled up. The sentence appears to carry over the '
        'Windows-lineage changelog (0.2.0: only a manual :w '
        'formats), from the era when conform formatted on save.'),

    ...sec('four providers, switched off'),
    ...code('lua', 'lua/config/options.lua · providers', r'''
-- No remote-plugin hosts are in use: skip provider probing entirely
-- (removes startup/health overhead; zero effect on UI or LSP).
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0'''),
    ...para('--',
        'Remote plugins are plugins written in another language '
        'that talk to Neovim through a host process. Neovim looks '
        'for hosts for Python 3, Ruby, Perl and Node on demand, '
        'and :checkhealth reports on them. Neovim’s own '
        'documentation gives this exact recipe for opting out: '
        'set g:loaded_<name>_provider to 0 for each one.'),
    ...para('--',
        'It arrived in f35b4f6 (2026-09-03) as part of the '
        '“zero background activity” group in CHANGELOG 1.3.0 '
        'beside the update checker change in lua/config/lazy.lua. '
        'The claim attached to it is deliberately narrow: nothing '
        'in this configuration uses a remote plugin, so turning '
        'the probing off changes nothing visible. The repository '
        'gives no separate timing for these four lines; the '
        'measured number belongs to the commit as a whole (28.7 '
        'ms to about 18 ms).'),
    ...para('--',
        'The trade is easy to state: if a future plugin does need '
        'a Python or Node host, this block is the first place to '
        'look when the plugin reports that no provider is '
        'available.'),

    ...sec('the switch that shapes the Rust setup'),
    ...code('lua', 'lua/config/options.lua · rust diagnostics', r'''
-- Rust diagnostics via bacon-ls: bacon watches the filesystem and re-runs
-- clippy on every (auto)save, bacon-ls streams the results in as LSP
-- diagnostics. The lang.rust extra reads this and disables rust-analyzer's
-- own checkOnSave/diagnostics so nothing is reported twice.
vim.g.lazyvim_rust_diagnostics = "bacon-ls"'''),
    ...para('--',
        'One line of code, and it is the hinge of the repository. '
        'The lang.rust extra in lazyvim.json reads '
        'vim.g.lazyvim_rust_diagnostics when its module is loaded: '
        'the first thing it does is capture the value, defaulting '
        'to "rust-analyzer". That is why the global must be set '
        'here, in the earliest file, and not in a plugin spec that '
        'would run after the extra has already decided.'),
    ...para('--',
        'The value picks which tool owns diagnostics, and the '
        'extra switches several things on it, all visible in its '
        'source at the pinned commit:'),
    ...pt('--', 'rust-analyzer checkOnSave',
        'set to true only when the value is "rust-analyzer", so '
        'here it is false.'),
    ...pt('--', 'rust-analyzer diagnostics',
        'enabled only for "rust-analyzer", so the extra turns '
        'them off here. lua/plugins/rustaceanvim.lua turns them '
        'back on, deliberately, as the instant tier.'),
    ...pt('--', 'the bacon_ls server',
        'enabled only for "bacon-ls", which is what makes '
        'lua/plugins/bacon-ls.lua meaningful at all.'),
    ...pt('--', 'mason',
        'ensure_installed gains the bacon package for "bacon-ls". '
        'CHANGELOG 1.1.0 records that this package failed to '
        'produce a binary, which is why bacon came from pacman.'),

    ...sec('a comment that fell behind the code'),
    ...para('--',
        'The comment above the switch dates from 3ec11c4 '
        '(2026-09-03 07:05) and was never edited, while the design '
        'changed around it within the same day. Two statements no '
        'longer describe the system:'),
    ...pt('--', 'the “bacon watches” sentence',
        '“bacon watches the filesystem and re-runs clippy on every '
        '(auto)save” describes bacon-ls’s older backend. bacon-ls.lua selects '
        'the cargo backend, which, in that file’s own words, needs '
        'no bacon process or .bacon-locations export, and runs '
        'clippy on every buffer change before any save. A save '
        'is not what triggers it.'),
    ...pt('--', 'the “nothing is reported twice” sentence',
        '“disables rust-analyzer’s own checkOnSave/diagnostics so '
        'nothing is reported twice” is true of checkOnSave and of the extra’s defaults, but '
        'CHANGELOG 1.3.0 re-enabled the native diagnostics as the '
        'instant tier, accepting a small visual overlap '
        'instead of duplicate pipelines.'),
    ...para('--',
        'The code is right and the comment is stale, which is the '
        'cheaper failure of the two, but it is worth fixing '
        'because a reader who trusts the comment will assume bacon '
        'is required. The README’s Requires paragraph says it is '
        'not. The honest summary of the current design is in '
        'lua/plugins/bacon-ls.lua and lua/plugins/rustaceanvim.lua.'),

    ...sec('what is not here, and where it went'),
    ...para('--',
        'The file got shorter at the migration: 37 lines in the '
        'first commit, 5 after eabb22a (a comment, the clipboard '
        'line and two options), 18 now. The deleted settings were not '
        'lost, they were replaced by LazyVim’s defaults, '
        'read from its options file at the pinned commit:'),
    ...pt('--', 'indentation',
        'was tabstop, softtabstop and shiftwidth of 4. Now 2 for '
        'tabstop and shiftwidth, with shiftround on.'),
    ...pt('--', 'scrolling',
        'scrolloff 8 became 4; updatetime 50 became 200.'),
    ...pt('--', 'saved state',
        'swapfile and backup were switched off and undodir was '
        'set by hand. LazyVim keeps undofile on and sets neither '
        'swapfile nor backup, so Neovim’s own defaults apply.'),
    ...pt('--', 'dropped outright',
        'colorcolumn 80, guicursor empty, hlsearch off, and the '
        'three netrw_ globals. LazyVim sets none of them.'),
    ...pt('--', 'the leader',
        'moved out of init.lua. LazyVim sets mapleader to a space '
        'and maplocalleader to a backslash, in its options file.'),
    ...para('--',
        'Moving from 37 lines of private defaults to 18 lines of '
        'overrides is the point of choosing a framework: the '
        'file now only records where this setup disagrees with '
        'LazyVim, or where it must act before LazyVim does.'),

    ...sec('how it is checked'),
    ...para('--',
        'There is no test that loads this file. What exists is '
        'indirect evidence recorded in the changelog: the Rust '
        'switch is exercised by every diagnostics measurement '
        '(1.3.0 and 1.4.0, with the real LazyVim config and real '
        'auto-save), the provider lines by the startup figure, and '
        'the clipboard by the behaviour of remote_clipboard.lua. '
        'A cheap regression check would be a headless start that '
        'asserts these four globals and the two options.'),

    ...sec('limits'),
    ...pt('--', 'order-sensitive',
        'moving the clipboard line below a call that touches the '
        'clipboard would defeat it, and nothing would say so.'),
    ...pt('--', 'stale comment',
        'see above.'),
    ...pt('--', 'unreasoned preferences',
        'relativenumber and autoformat are recorded without '
        'rationale. The first is taste; the second explains itself '
        'only through the history of the auto-save work.'),

    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
