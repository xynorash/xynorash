import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/disable-news-alert.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'disable-news-alert.lua — turning off two pop-ups with two lines'),
    cm('--', 'the smallest spec in the repo, and the template for the override pattern'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'switches off LazyVim’s news announcements for LazyVim and for Neovim'),
    kv('language', 'Lua (a lazy.nvim spec that only supplies opts); tab-indented'),
    kv('size', '9 lines, no comments'),
    kv('history', '1 commit, eabb22a (2026-09-02); never changed'),
    kv('pinned', 'LazyVim at c10948c in lazy-lock.json'),
    ...sec('the whole file'),
    ...code('lua', 'lua/plugins/disable-news-alert.lua · the entire file', r'''
return {
	"LazyVim/LazyVim",
	opts = {
		news = {
			lazyvim = false,
			neovim = false,
		},
	},
}'''),
    ...para('--',
        r'There is nothing to hide in nine lines, so this page is '
        r'mostly about what they rely on. The spec has a plugin name, '
        r'LazyVim/LazyVim, and an opts table with one key, news, '
        r'holding two booleans named after the two news feeds: '
        r'lazyvim and neovim. Setting both to false is the whole '
        r'effect.'),

    ...sec('what the names say, and what they do not'),
    ...para('--',
        r'From the repo alone two things are clear. The option '
        r'group is called news and has exactly two members, so there '
        r'are two sources of news that can be switched independently. '
        r'And lazyvim.json, the file LazyVim itself maintains, '
        r'contains a news record:'),
    ...code('json', 'lazyvim.json · the news record', r'''
  "news": {
    "NEWS.md": "10960"
  },'''),
    ...para('--',
        r'Nothing in this repo describes what these two options do. The names and the news record suggest the NEWS.md of the distribution and Neovim’s release notes, and the number looks like bookkeeping of what has been shown, but that is an inference from the names, not a documented fact about this config.'),
    blank,
    ...para('--',
        r'What the repo does tell us is the timing. The file arrived '
        r'with everything else in the migration commit eabb22a, and '
        r'the CHANGELOG lists it in one line under 1.0.0, Added: '
        r'“disable-news-alert.lua and snacks-animated-scrolling-off.lua '
        r'LazyVim tweaks”. No reason is given, in the changelog, the '
        r'commit message or the README. It is a preference, recorded '
        r'as a preference.'),

    ...sec('why a spec that names LazyVim works'),
    ...para('--',
        r'It looks odd that a plugin spec configures a distribution. '
        r'The reason it works is in lua/config/lazy.lua, where '
        r'LazyVim is itself declared as a plugin spec:'),
    ...code('lua', 'lua/config/lazy.lua · LazyVim is a spec too', r'''
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },'''),
    ...para('--',
        r'The second line imports every file in lua/plugins/, this '
        r'one included. When two specs refer to the same plugin, '
        r'lazy.nvim merges them by url. The opts tables are '
        r'merged key by key, which is why this file can contain only '
        r'the keys it wants to change and leave the rest of '
        r'LazyVim’s options alone. A file that wrote out the whole '
        r'options table would work too, and would also silently '
        r'freeze every other default at today’s values.'),

    ...sec('one pattern, four files'),
    ...para('--',
        r'This is the template for how this config customises the '
        r'tools it did not write. Four of the files in lua/plugins/ that use it are these, '
        r'each naming an existing plugin and changing a few opts:'),
    blank,
    cm('--', '  file                                  names             changes'),
    cm('--', '  ------------------------------------  ----------------  ---------'),
    cm('--', '  disable-news-alert.lua                LazyVim/LazyVim   news'),
    cm('--', '  snacks-animated-scrolling-off.lua     folke/snacks.nvim scroll'),
    cm('--', '  bacon-ls.lua                          neovim/nvim-      servers.'),
    cm('--', '                                        lspconfig         bacon_ls'),
    cm('--', '  rustaceanvim.lua                      mrcjkb/           server.'),
    cm('--', '                                        rustaceanvim      default_settings'),
    blank,
    ...para('--',
        r'The first two are one-liners. The second two carry the '
        r'measurements and bug stories that fill the other pages in '
        r'this directory. The shape is the same in all four, and the '
        r'design has a useful property: LazyVim upgrades keep '
        r'flowing, and each file records exactly where this config '
        r'disagrees with the distribution. Deleting a file restores '
        r'the default.'),

    ...sec('what is not here'),
    ...pt('--', 'a reason',
        r'the repo does not say why the news is off. The nearby '
        r'decisions in the changelog share a preference for a quiet '
        r'editor (the update checker is off and unused providers are '
        r'disabled, 1.3.0), but those entries do not mention news, '
        r'and this page does not attribute this one to them.'),
    ...pt('--', 'a test',
        r'there is one. tests/startup-and-options_spec.lua line 614 has '
        r'a describe block for this plugin whose case, “turns both '
        r'LazyVim news checks off”, asserts news.lazyvim and news.neovim '
        r'are false both in the spec opts and in the merged '
        r'lazyvim.config table, so the merge itself is verified.'),
    ...pt('--', 'a guard against renames',
        r'if a future LazyVim renamed the news option, this file '
        r'would stay valid Lua and silently stop doing anything. '
        r'The lock file pins LazyVim at one commit, and that pin is '
        r'what protects the setting for now.'),
    blank,
    ...para('--',
        r'The reason to keep a page for a nine-line file is the '
        r'pattern. Every customisation in this directory is one '
        r'idea: say which plugin you are talking to, say what you '
        r'want changed, and let the merge do the rest.'),
    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
