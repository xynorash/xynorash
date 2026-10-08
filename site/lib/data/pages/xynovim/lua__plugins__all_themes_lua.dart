import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/all-themes.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'all-themes.lua — twenty colorschemes, none of them applied'),
    cm('--', 'so that a live theme switch never has to wait for a download'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'declares every theme plugin Omarchy can pick, installed but dormant'),
    kv('language', 'Lua (a list of 20 lazy.nvim plugin specs); tab-indented'),
    kv('size', '120 lines: 106 of code, 14 of comment, no blank lines'),
    kv('history', 'one commit, eabb22a (2026-09-02), unchanged since'),
    kv('pinned', '20 of the 58 entries in lazy-lock.json are these themes'),
    ...sec('why this file exists'),
    ...para('--',
        r'The file’s first two comment lines state the whole purpose: '
        r'“Load all theme plugins but don’t apply them. This ensures '
        r'all colorschemes are available for hot-reloading.” Hot-'
        r'reloading is omarchy-theme-hotreload.lua. When the desktop '
        r'theme changes, that file asks lazy.nvim to load the plugin '
        r'that provides the new colorscheme and then applies it. For '
        r'that to be quick, the plugin has to be declared and '
        r'installed already, whichever theme comes next. '
        r'This file declares all of them.'),
    blank,
    ...para('--',
        r'It contains no logic. It is twenty tables. The interesting '
        r'part is what two of the fields mean, the one entry that has '
        r'a long comment, and a list of five plugins that are '
        r'scheduled for deletion.'),

    ...sec('the shape of every entry'),
    ...code('lua', 'lua/plugins/all-themes.lua · the first entry', r'''
return {
  -- Load all theme plugins but don't apply them
  -- This ensures all colorschemes are available for hot-reloading
  --
  -- Omarchy 4 generates most theme specs from default/themed/neovim.lua.tpl on
  -- top of aether, so the single-theme plugins below (ethereal, vantablack,
  -- white, monokai-pro, miasma) are only reached by Omarchy 3.8, which ships a
  -- neovim.lua per theme. Keep them until 3.8 is out of support.
  {
    "ribru17/bamboo.nvim",
    lazy = true,
    priority = 1000,
  },'''),
    ...para('--',
        r'Every entry follows this template: a repository string, '
        r'lazy = true and priority = 1000.'),
    ...pt('--', 'lazy = true',
        r'the plugin is installed on disk and pinned in the lock '
        r'file, but its code is not executed at startup. Nothing is '
        r'loaded until something asks for the colorscheme by name. '
        r'This config sets defaults.lazy = false (lua/config/lazy.lua), '
        r'so user plugins would otherwise load at launch; the field '
        r'overrides that for all twenty. A new session loads at most '
        r'the plugin of the theme that is currently active.'),
    ...pt('--', 'priority = 1000',
        r'a plugin that has to be present at startup is conventionally '
        r'given a high priority so that it loads before the others '
        r'that depend on its highlight groups. With lazy = true '
        r'it only matters if one of the plugins is later loaded '
        r'eagerly; it is there because it is the usual spelling '
        r'for colorscheme plugins. That is my reading of '
        r'lazy.nvim’s documented behaviour, not a claim in the repo.'),
    blank,
    ...para('--',
        r'The cost model is worth stating. Twenty dormant plugins '
        r'cost disk (20 of the 58 entries in lazy-lock.json, about '
        r'a third of everything the lock file tracks) and some '
        r'spec-parsing work; they cost no plugin code at startup. The '
        r'notes do not measure the parsing part separately, and the '
        r'18 ms startup figure in CHANGELOG 1.3.0 was taken with this '
        r'file present.'),

    ...sec('the twenty'),
    cm('--', '  repository                  name given   note'),
    cm('--', '  --------------------------  -----------  ------------------'),
    cm('--', '  ribru17/bamboo.nvim'),
    cm('--', '  bjarneo/aether.nvim         aether       branch v3'),
    cm('--', '  bjarneo/ethereal.nvim                    3.8 only'),
    cm('--', '  bjarneo/hackerman.nvim'),
    cm('--', '  bjarneo/vantablack.nvim                  3.8 only'),
    cm('--', '  bjarneo/white.nvim                       3.8 only'),
    cm('--', '  catppuccin/nvim             catppuccin'),
    cm('--', '  neanias/everforest-nvim'),
    cm('--', '  kepano/flexoki-neovim'),
    cm('--', '  ellisonleao/gruvbox.nvim'),
    cm('--', '  rebelot/kanagawa.nvim'),
    cm('--', '  tahayvr/matteblack.nvim'),
    cm('--', '  gthelding/monokai-pro.nvim               3.8 only'),
    cm('--', '  EdenEast/nightfox.nvim'),
    cm('--', '  rose-pine/neovim            rose-pine'),
    cm('--', '  ficcdaf/ashen.nvim'),
    cm('--', '  folke/tokyonight.nvim'),
    cm('--', '  OldJobobo/miasma.nvim                    3.8 only'),
    cm('--', '  OldJobobo/retro-82.nvim'),
    cm('--', '  omacom-io/lumon.nvim'),
    blank,
    ...para('--',
        r'The “3.8 only” markers are the five plugins the header '
        r'comment names. The two entries with a name are not '
        r'decoration, as the next two sections show.'),

    ...sec('names, and why two repos need one'),
    ...code('lua', 'lua/plugins/all-themes.lua · explicit names', r'''
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = true,
    priority = 1000,
  },'''),
    ...para('--',
        r'lazy.nvim names a plugin after its repository by default. '
        r'You can see that in the lock file, where the keys read '
        r'bamboo.nvim, gruvbox.nvim, tokyonight.nvim. The catppuccin '
        r'repository is called just nvim, and rose-pine’s is called '
        r'neovim, which would register as “nvim” and “neovim” and '
        r'collide with anything else of the same name. The name field '
        r'gives them their familiar identities, and the lock file '
        r'confirms the result: the keys are catppuccin and rose-pine.'),
    blank,
    ...para('--',
        r'That second name has a history in this repo. rose-pine was '
        r'the first colorscheme of the whole config. CHANGELOG 0.1.0 '
        r'lists “rose-pine (single colorscheme)”. On 2026-08-18 the '
        r'Windows-lineage config replaced it with islands-dark, a '
        r'palette ported from the author’s own exported RustRover '
        r'scheme, with colours “read directly from that file’s real '
        r'hex values”. The Linux migration then removed the '
        r'hand-made scheme (CHANGELOG 1.0.0: “Omarchy theming '
        r'supersedes them, in the colorscheme’s case”). And here '
        r'rose-pine is again, one of twenty. A single hand-picked '
        r'theme became a catalogue that the operating system '
        r'chooses from.'),

    ...sec('the aether entry: a comment that cost a network clone'),
    ...code('lua', 'lua/plugins/all-themes.lua · aether', r'''
  -- Name and branch must match Omarchy 4's generated theme spec
  -- (default/themed/neovim.lua.tpl). lazy merges specs by url and lets an
  -- explicit name rename the merged plugin, so a bare "bjarneo/aether.nvim"
  -- here builds the cache into lazy/aether.nvim while every aether-themed
  -- Omarchy 4 install renames it to lazy/aether at runtime -- a directory the
  -- package never shipped. That cost a network clone on first launch, and the
  -- theme fell back to tokyonight until nvim was restarted.
  {
    "bjarneo/aether.nvim",
    branch = "v3",
    name = "aether",
    lazy = true,
    priority = 1000,
  },'''),
    ...para('--',
        r'This is the only entry with a story, and the comment tells '
        r'it as a cause chain. Read it as five facts:'),
    ...pt('--', 'one repo, two specs',
        r'this file declares aether, and Omarchy 4’s generated theme '
        r'file declares it too. lazy.nvim merges two specs that name '
        r'the same repository into one plugin.'),
    ...pt('--', 'the merge can rename',
        r'if either spec carries an explicit name, the merged plugin '
        r'takes it. The generated spec says name = "aether".'),
    ...pt('--', 'the mismatch',
        r'this file, written as a bare "bjarneo/aether.nvim", builds '
        r'the cache into lazy/aether.nvim. At '
        r'runtime the merged plugin was called aether and was looked '
        r'up in lazy/aether, “a directory the package never '
        r'shipped”.'),
    ...pt('--', 'the cost',
        r'a network clone on first launch, because the directory it '
        r'wanted did not exist yet. The comment calls that out as the '
        r'thing that hurt.'),
    ...pt('--', 'the visible symptom',
        r'“the theme fell back to tokyonight until nvim was '
        r'restarted”. The fallback is not an accident. lua/config/'
        r'lazy.lua sets install.colorscheme to tokyonight then '
        r'habamax, the list lazy.nvim tries while it is still '
        r'installing, so a half-installed theme degrades to the '
        r'first available one.'),
    blank,
    ...para('--',
        r'The fix is the two fields the comment names. branch = "v3" '
        r'and name = "aether" make this file agree with the generated '
        r'spec, so the merge becomes a no-op, and the lock file '
        r'records exactly that: the key is aether, on branch v3, at '
        r'commit 567efb7. The sentence “Name and branch must match” '
        r'is a contract with a file this repo does not contain; if '
        r'Omarchy changes its template, the comment tells the next '
        r'reader where to look.'),
    blank,
    ...para('--',
        r'I cannot see the generated spec, so the cause chain above '
        r'is the comment’s account, not something I could reproduce. '
        r'It is plausible and internally consistent with the lock '
        r'file and with lazy.lua’s install list, and I have no '
        r'evidence against it.'),

    ...sec('five plugins with an expiry date'),
    ...para('--',
        r'The header comment contains a small piece of release '
        r'management. Omarchy 4 builds most theme specs from one '
        r'template on top of aether, so most themes need no plugin '
        r'of their own. Omarchy 3.8 was different: each theme '
        r'shipped its own neovim.lua. The plugins that exist only '
        r'for those per-theme files are named in parentheses: '
        r'ethereal, vantablack, white, monokai-pro, miasma. The '
        r'instruction that follows is “Keep them until 3.8 is out of '
        r'support”.'),
    blank,
    ...para('--',
        r'It is the same pattern as the bacon-ls.lua override, which '
        r'says “Drop this cmd override once it merges”. A leftover is '
        r'fine, and an undocumented leftover is debt. Here the '
        r'comment states why the five exist and when they can '
        r'go. What it cannot do is notify anyone when 3.8 reaches the '
        r'end of its support; that remains a manual check.'),

    ...sec('what the file does not do'),
    ...pt('--', 'it never picks a theme',
        r'which colorscheme is active comes from theme.lua, a symlink '
        r'to Omarchy’s current theme, and is applied by '
        r'omarchy-theme-hotreload.lua.'),
    ...pt('--', 'it does not verify anything',
        r'there is no check that all twenty install, load or even '
        r'exist upstream. A repository that disappears would show up '
        r'when lazy.nvim tries to restore it.'),
    ...pt('--', 'it does not stay in sync by itself',
        r'adding a theme to Omarchy means adding an entry here by '
        r'hand, unless the theme ships a spec that brings its own '
        r'plugin. Nothing in the repo automates the list.'),
    ...pt('--', 'it does not explain every entry',
        r'no comment says why lumon, retro-82 or ashen are present. I '
        r'will not guess.'),

    ...sec('history'),
    ...para('--',
        r'One commit created this file and none has changed it. '
        r'eabb22a, the Linux migration of 2026-09-02, lists it with '
        r'“Omarchy desktop integration” (CHANGELOG 1.0.0). The '
        r'tab indentation, which differs from the two-space style '
        r'that stylua.toml asks for and that the files written for '
        r'this repo use, suggests it came from Omarchy’s defaults '
        r'(an inference). The aether comment reads like an observed '
        r'incident, with exact directory names, but a single commit '
        r'cannot tell me whether it was written here or arrived with '
        r'the file.'),

    ...sec('what to take from it'),
    ...pt('--', 'dormant is cheap',
        r'declaring twenty plugins as lazy costs disk, not startup. '
        r'The performance work in CHANGELOG 1.3.0 never needed to '
        r'touch this file.'),
    ...pt('--', 'names are part of the interface',
        r'when two specs merge by url, an explicit name is a contract. '
        r'The aether incident cost a clone and a wrong theme for the '
        r'length of a session.'),
    ...pt('--', 'write the exit condition',
        r'“until 3.8 is out of support” turns five unexplained '
        r'plugins into five scheduled deletions.'),
    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
