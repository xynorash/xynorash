import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lazyvim.json',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'lazyvim.json — the file LazyVim writes about itself'),
    cm('//', 'two extras, one format version, one stale news counter'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'LazyVim state: enabled extras and format versions'),
    kv('language', 'JSON, written by LazyVim, not by hand'),
    kv('size', '11 lines'),
    kv('extras', 'editor.neo-tree, lang.rust'),
    kv('history', 'one commit: eabb22a, 2026-09-02'),

    ...sec('what it is'),
    ...para('//',
        'lazyvim.json is a state file that LazyVim keeps in the '
        'config directory. The framework writes it, for example '
        'when you toggle something in :LazyExtras or when its news '
        'counter updates, and reads it back at every start. It '
        'entered this repository once, '
        'in the migration commit eabb22a, and has never changed '
        'since: the extras it lists were enabled on day one and '
        'no other extra has been added.'),
    ...code('json', 'lazyvim.json · the whole file', r'''
{
  "extras": [
    "lazyvim.plugins.extras.editor.neo-tree",
    "lazyvim.plugins.extras.lang.rust"
  ],
  "install_version": 8,
  "news": {
    "NEWS.md": "10960"
  },
  "version": 8
}'''),

    ...sec('why the keys are in alphabetical order'),
    ...para('//',
        'Nobody sorted this by hand. LazyVim saves the file with '
        'its own tiny JSON encoder (lua/lazyvim/util/json.lua at '
        'the pinned commit) that sorts object keys and indents two '
        'spaces, and it sorts the extras list before saving as '
        'well. That is why the order is extras, install_version, '
        'news, version, and why editor.neo-tree sorts ahead of '
        'lang.rust. The practical rule: edit this file through '
        ':LazyExtras, not in an editor, because the next toggle '
        'rewrites it anyway.'),

    ...sec('the two version numbers'),
    ...pt('//', 'version = 8',
        'the format version of this file. LazyVim 16.0.0 (the '
        'release pinned in lazy-lock.json) declares 8 as current '
        'and, if a file carries an older number, runs a chain of '
        'migrations: renamed extras, extras that became core, and '
        'the move of the AI plugins into an ai namespace. A file '
        'already at 8 passes through untouched.'),
    ...pt('//', 'install_version = 8',
        'the format version at the time this config was first '
        'created. LazyVim sets it when no lazyvim.json exists at '
        'first launch. It matters because it selects defaults.'),
    ...para('//',
        'Here is the consequence, read from lua/lazyvim/config/'
        'init.lua at the pinned commit. LazyVim picks a default '
        'picker, completion engine and explorer from ordered lists '
        'of extras. If install_version is below 8 it moves the '
        'second entry of the picker list and of the explorer list '
        'to the front, so that existing installs keep their old '
        'defaults (fzf and neo-tree). With '
        'install_version at 8 a fresh install gets the new '
        'defaults instead: snacks as the picker and the explorer, '
        'and blink.cmp for completion. So on this machine the '
        'picker is snacks, completion is blink.cmp (which '
        'lazy-lock.json confirms and which the 99 spec relies on '
        'through blink.compat), and the explorer is neo-tree only '
        'because this file says so.'),

    ...sec('the explicit extra that overrides a default'),
    ...para('//',
        'Two extras, and they do different jobs. editor.neo-tree '
        'is a choice against the new default: with install_version '
        'at 8 the explorer would otherwise be snacks. Naming '
        'neo-tree here makes LazyVim treat it as the selected '
        'explorer. plugin/after/transparency.lua carries a block of '
        'NeoTree highlight names (NeoTreeNormal, NeoTreeWinSeparator '
        'and friends), alongside an NvimTree block that this '
        'config does not use, which is consistent with neo-tree '
        'being the explorer in daily use.'),
    ...para('//',
        'lang.rust is the one that defines this repository. Reading '
        'lua/lazyvim/plugins/extras/lang/rust.lua at the pinned '
        'commit, enabling it does the following:'),
    ...pt('//', 'rustaceanvim',
        'configured with default rust-analyzer settings: all '
        'cargo features, build scripts and proc macros on, and a '
        'files.exclude list that includes target. Two keymaps are '
        'added on attach: <leader>cR for code actions and '
        '<leader>dr for debuggables.'),
    ...pt('//', 'crates.nvim',
        'loaded on BufRead of a Cargo.toml, with its LSP-style '
        'completion, hover and actions switched on.'),
    ...pt('//', 'treesitter',
        'parsers for rust and ron are added to ensure_installed.'),
    ...pt('//', 'mason',
        'codelldb is installed for debugging. If the global '
        'diagnostics setting is bacon-ls it also installs the '
        'bacon package, which CHANGELOG 1.1.0 says failed to '
        'produce a binary in practice (bacon came from pacman '
        'instead).'),
    ...pt('//', 'neotest',
        'the rustaceanvim neotest adapter is registered.'),
    ...pt('//', 'lspconfig',
        'rust_analyzer is disabled in lspconfig because '
        'rustaceanvim owns it, and the bacon_ls server is enabled '
        'only when the diagnostics global equals bacon-ls.'),
    ...para('//',
        'That last switch is the hinge of the whole design. The '
        'extra reads vim.g.lazyvim_rust_diagnostics, which '
        'lua/config/options.lua sets to "bacon-ls". With that '
        'value the extra turns rust-analyzer’s checkOnSave and its '
        'diagnostics off. lua/plugins/rustaceanvim.lua then turns '
        'the native diagnostics back on, which is how the two-tier '
        'setup in the README comes into being. The override works '
        'because LazyVim imports all extras before it imports the '
        'user’s lua/plugins directory, and warns if that order '
        'is wrong.'),

    ...sec('the stale news counter'),
    ...para('//',
        'The news block is how LazyVim decides whether to pop up its '
        'NEWS.md. The “hash” is not a hash at all: in the pinned '
        'source it is the file size in bytes, kept as a string. '
        'The recorded value is 10960. The NEWS.md in the pinned '
        'LazyVim checkout is 11866 bytes, so the number was '
        'recorded against a different LazyVim than the one '
        'lazy-lock.json pins, most likely an older one.'),
    ...para('//',
        'It stays stale because the code that updates it never '
        'runs here. lua/plugins/disable-news-alert.lua sets both '
        'news.lazyvim and news.neovim to false, and LazyVim only '
        'checks and rewrites the stored size when the option is '
        'on. If the option were turned back on, the mismatch would '
        'make the news window open once. It is a small, harmless '
        'inconsistency, and the useful lesson is that a state '
        'file can silently outlive the code that maintains it.'),

    ...sec('how this connects to the rest of the repository'),
    ...pt('//', 'lazy-lock.json',
        'pins the LazyVim commit that decides what these extras '
        'mean. Extras are code inside LazyVim, so the same '
        'extras string can mean different plugins after an update. '
        'The lockfile is what makes this file reproducible.'),
    ...pt('//', 'lua/config/options.lua',
        'sets the diagnostics global that the lang.rust extra '
        'reads.'),
    ...pt('//', 'lua/plugins/*',
        'every file there is a layer on top of what these two '
        'extras install: rustaceanvim.lua and bacon-ls.lua patch '
        'the rust extra, and the neo-tree transparency groups live '
        'in plugin/after/transparency.lua.'),

    ...sec('limits'),
    ...pt('//', 'opaque module names',
        'the file stores module paths, not plugin names. To know '
        'what lang.rust installs you have to read the pinned '
        'LazyVim source, as this page did.'),
    ...pt('//', 'no record of intent',
        'the commit that added the file explains the migration but '
        'does not say why neo-tree was chosen over the new '
        'default explorer; the reason above is inferred from how '
        'LazyVim resolves defaults, not stated by the author.'),

    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
