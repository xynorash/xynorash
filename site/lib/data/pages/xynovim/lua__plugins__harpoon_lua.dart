import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/harpoon.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'harpoon.lua — six keys, and a lesson in lazy loading'),
    cm('--', 'why a keys function defeats the lazy-loading it appears to set up'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'installs Harpoon 2 and binds keys to mark, list and jump between files'),
    kv('language', 'Lua (a lazy.nvim spec whose keys table triggers lazy loading)'),
    kv('size', '24 lines: 21 of code, 3 of comment'),
    kv('history', '3 versions: local clone (2026-08-17), GitHub spec (2026-09-02), static keys (2026-09-03)'),
    kv('pinned', 'harpoon (branch harpoon2) at 87b1a35, plenary.nvim at 74b06c6'),
    ...sec('why this file exists'),
    ...para('--',
        r'Harpoon is one of two plugins by ThePrimeagen in this config '
        r'(the other is 99, see ninety-nine.lua). The idea is to keep '
        r'a short list of the files you are working on right now, and '
        r'to jump between them with one chord instead of searching. '
        r'This config tracks the harpoon2 branch, which is the '
        r'rewrite; the first commit of the repository already chose '
        r'it (CHANGELOG 0.1.0: “Harpoon (harpoon2 branch, local '
        r'clone)”).'),
    blank,
    ...para('--',
        r'The file is 24 lines and most of that is a table of six key '
        r'bindings. What makes it worth a page is the three comment '
        r'lines above that table. They record a change that is '
        r'invisible when it works and costly when it is wrong: whether '
        r'the plugin loads at startup or on first use.'),

    ...sec('the six keys'),
    ...code('lua', 'lua/plugins/harpoon.lua · the spec', r'''
return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {},
  -- static keys table with requires deferred into the callbacks: a keys
  -- FUNCTION that requires harpoon at spec-build time force-loads
  -- harpoon+plenary during startup, defeating lazy-loading entirely.
  keys = {
    { "<leader>a", function() require("harpoon"):list():add() end, desc = "Harpoon: Add file" },
    {
      "<C-e>",
      function()
        local harpoon = require("harpoon")
        harpoon.ui:toggle_quick_menu(harpoon:list())
      end,
      desc = "Harpoon: Quick menu",
    },
    { "<M-1>", function() require("harpoon"):list():select(1) end, desc = "Harpoon: Jump to file 1" },
    ...
  },
}'''),
    blank,
    cm('--', '  key           action'),
    cm('--', '  ------------  --------------------------------------------'),
    cm('--', '  <leader>a     add the current file to the list'),
    cm('--', '  <C-e>         toggle the quick menu (edit or jump)'),
    cm('--', '  <M-1>..<M-4>  jump to list entry 1, 2, 3 or 4'),
    blank,
    ...para('--',
        r'Each binding carries a desc, so which-key shows it as '
        r'“Harpoon: Add file” and so on. That was added in the '
        r'migration to LazyVim (CHANGELOG 1.0.0 notes the same for '
        r'99: “Keymaps gained desc labels for which-key”).'),
    blank,
    ...para('--',
        r'Two small facts about the choices. First, only four direct '
        r'jump slots are bound. A list can grow longer than four; the '
        r'quick menu is how you reach the rest. Second, <C-e> in '
        r'normal mode is Vim’s built-in “scroll the window down one '
        r'line”. Binding it shadows that, a trade the config makes '
        r'on purpose (the same key was bound in the very first '
        r'commit).'),
    blank,
    ...para('--',
        r'The jump keys use Alt rather than Control or leader. Alt + '
        r'digit is a single chord with no prefix, so there is no '
        r'timeout to wait out. Whether Alt chords reach Neovim depends '
        r'on the terminal; the config does not address that.'),

    ...sec('the bug that was not a bug'),
    ...para('--',
        r'Until f35b4f6 (2026-09-03), the keys were not a table at '
        r'all. They were a function. The eabb22a version looked '
        r'like this (abridged):'),
    blank,
    cm('--', '  keys = function()'),
    cm('--', '    local harpoon = require("harpoon")'),
    cm('--', '    local keys = { ...two entries... }'),
    cm('--', '    for i = 1, 4 do table.insert(keys, { ... }) end'),
    cm('--', '    return keys'),
    cm('--', '  end,'),
    blank,
    ...para('--',
        r'It reads well. There is a loop that generates the four jump '
        r'bindings instead of repeating them, and the require is done '
        r'once at the top so every binding can use the local '
        r'harpoon. It is also exactly the kind of tidiness that the '
        r'1.3.0 changelog entry blames for a startup cost: “harpoon’s '
        r'keys function required the plugin at spec-build time '
        r'(force-loading it + plenary every startup — fixed to a '
        r'static keys table)”.'),
    blank,
    ...para('--',
        r'The mechanism is the thing to understand. lazy.nvim has to '
        r'know which keys belong to a plugin before it can wait for '
        r'them, so when keys is a function it calls that function '
        r'while it is still building its list of plugin specs, long '
        r'before any key is pressed. The function contained '
        r'require("harpoon"). Requiring a module is not a '
        r'declaration; it is execution. To satisfy it, lazy.nvim has '
        r'to load the plugin, and plenary with it, which is the whole '
        r'cost the lazy-loading was supposed to avoid. The line that '
        r'looked like preparation was the load.'),
    blank,
    ...para('--',
        r'This is why the 24-line file has a comment that reads like '
        r'a rule. The fix keeps the shape of the user-facing '
        r'configuration and moves every require inside a callback:'),
    ...pt('--', 'a static table',
        r'the spec itself contains only strings and function values. '
        r'Creating a function value does not run it.'),
    ...pt('--', 'require inside each callback',
        r'the module is loaded the first time a key is pressed. '
        r'Lua caches modules, so every press after the first pays '
        r'almost nothing for the repeated require.'),
    ...pt('--', 'the cost is repetition',
        r'the four jump bindings are now written out, not generated '
        r'by a loop. The file got longer and plainer, which is the '
        r'right trade for a spec: what a spec does at definition '
        r'time should be nothing at all.'),
    blank,
    ...para('--',
        r'The other two lazy.nvim fields in the spec are small. '
        r'dependencies lists plenary.nvim, a utility library that '
        r'Harpoon requires. opts = {} is lazy.nvim’s convention for '
        r'“run this plugin’s setup with defaults”, and replaced the '
        r'explicit harpoon:setup() call that the first version made '
        r'inside a config function.'),

    ...sec('what the startup number says, and does not'),
    ...para('--',
        r'CHANGELOG 1.3.0 puts startup at 28.7 ms before and about '
        r'18 ms after a batch of changes, and names harpoon’s keys '
        r'function first in the list: it force-loaded harpoon and '
        r'plenary “every startup”. It does not say how much of the '
        r'10.7 ms difference belongs to this file. The same entry '
        r'lists 99, telescope and blink.compat moving to lazy-load, '
        r'the remote-clipboard /proc walk short-circuiting, and a '
        r'stock example.lua being deleted.'),
    blank,
    ...para('--',
        r'So the honest claim is narrower than “harpoon cost 10 ms”. '
        r'The claim the evidence supports is a qualitative one: the '
        r'plugin and its dependency no longer load at launch. A '
        r'reader who wants the number can measure it with lazy.nvim’s '
        r'profile view; the repository does not include that result.'),

    ...sec('how it grew'),
    cm('--', '  2026-08-17  1c496fd  dir = "~/personal/harpoon", a config'),
    cm('--', '                       function with vim.keymap.set; also'),
    cm('--', '                       <leader>A to prepend an entry'),
    cm('--', '  2026-09-02  eabb22a  ThePrimeagen/harpoon from GitHub on'),
    cm('--', '                       branch harpoon2, opts = {}, a keys'),
    cm('--', '                       function; <leader>A not carried over'),
    cm('--', '  2026-09-03  f35b4f6  static keys table, requires deferred'),
    blank,
    ...para('--',
        r'Two details in that history. The first spec pointed at a '
        r'local clone, the same arrangement as 99, and both were '
        r'moved to GitHub sources in the migration, which is what '
        r'makes the config rebuildable from its lock file (CHANGELOG '
        r'1.0.0: “harpoon carried over as a normal GitHub-sourced '
        r'spec”). And the first spec also bound <leader>A to '
        r'harpoon:list():prepend(), which is absent from the '
        r'current file. The changelog does not mention the removal, '
        r'so whether it was deliberate is not recorded; I only '
        r'report that it is gone.'),

    ...sec('limits'),
    ...pt('--', 'four slots',
        r'only four jump bindings exist. A longer list needs the '
        r'quick menu.'),
    ...pt('--', 'no tests, no measurement',
        r'the lazy-loading claim rests on the changelog entry and '
        r'the reasoning above, not on a per-plugin startup number in '
        r'the repository.'),
    ...pt('--', 'the pin',
        r'the lock file holds harpoon at one commit of the harpoon2 '
        r'branch. A branch is a moving target; the pin is what keeps '
        r'the keymaps’ API calls stable.'),
    ...pt('--', 'terminal dependence',
        r'Alt-digit chords depend on the terminal forwarding them.'),
    blank,
    ...para('--',
        r'The reusable rule is one sentence from the file’s own '
        r'comment. In a lazy.nvim spec, put data in the spec and '
        r'effects in callbacks. A function that does work while the '
        r'spec is being built is not configuration, it is startup '
        r'code.'),
    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
    link('→ github.com/ThePrimeagen/harpoon (harpoon2 branch)', 'https://github.com/ThePrimeagen/harpoon/tree/harpoon2'),
  ],
);
