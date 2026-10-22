import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/island-theme.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'lua/plugins/island-theme.lua — making the theme the default'),
    cm('--', r'18 lines that say "island-dark" twice'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'lazy.nvim spec that selects Island Dark for LazyVim and lualine'),
    kv(r'language', r'Lua; returns a list of two plugin specs with opts functions'),
    kv(r'size', r'18 lines, 2 commits (2026-10-12, 2026-10-13)'),
    kv(r'depends on', r'colors/island-dark.lua, lua/lualine/themes/island-dark.lua'),
    kv(r'tested by', r'tests/theme-island_spec.lua, island-dark loading'),
    ...sec(r'why this file exists'),
    ...para('--', r'The theme is built from three files that Neovim finds by their location: colors/island-dark.lua (the colourscheme), lua/island/ (the engine and palette) and lua/lualine/themes/island-dark.lua. None of them is a plugin, and none of them selects itself. Something has to tell LazyVim "use this one", and that is the whole job of this spec file.'),
    ...code('lua', r'lua/plugins/island-theme.lua · lines 1-18', r'''
-- Island Dark is the permanent theme (colors/island-dark.lua, lua/island/). The
-- config directory is on the runtimepath, so the colorscheme needs no plugin.

return {
  {
    "LazyVim/LazyVim",
    opts = function(_, opts)
      opts.colorscheme = "island-dark"
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.theme = "island-dark"
    end,
  },
}'''),
    ...sec(r'how it works'),
    ...para('--', r'lazy.nvim merges plugin specs that share a name. A spec for "LazyVim/LazyVim" in this file is combined with LazyVim’s own, and its opts function runs after the defaults have been assembled, receiving the options table. LazyVim reads opts.colorscheme to decide which scheme to load at startup (its default is tokyonight), so setting it to "island-dark" is enough. The call that loads it is :colorscheme island-dark, which finds colors/island-dark.lua on the runtime path because the config directory is on it, as the header comment states. lua/config/lazy.lua also lists island-dark first in lazy’s install.colorscheme fallback list (lua/config/lazy.lua line 44: island-dark, tokyonight, habamax), which only matters during a first install, before any plugins exist.'),
    ...para('--', r'The second spec does the same for lualine: it makes sure options exists, then sets options.theme. The two-step form (opts.options = opts.options or {}) is defensive, so that the file works even if no other spec has created the table yet. It writes only the theme field and leaves the rest of lualine’s options alone, which is how lua/plugins/lualine.lua can add the Rust status component to the same plugin without conflict.'),
    ...sec(r'a function, not a table'),
    ...para('--', r'Both specs use opts = function(_, opts) rather than opts = { ... }. The difference is that a table is merged with other specs by deep extend, while a function receives the table already built and mutates it in place. That makes the file immune to merge order surprises: whatever other specs put in opts.colorscheme earlier, this one assigns last. It is also why the theme cannot be accidentally overridden by an extra added later in lazyvim.json.'),
    ...sec(r'what used to be here'),
    ...para('--', r'The two-line history of this file is the story of a decision being simplified. On 2026-10-12 the spec was 28 lines. It defined a local function island() that returned true unless vim.g.xynovim_follow_omarchy was set, and both opts functions were wrapped in if island() then. The header comment explained that Omarchy’s theme spec (lua/plugins/theme.lua) was neutralised in config/lazy.lua and that setting the global in options.lua would follow Omarchy again. Omarchy is a Linux desktop environment whose themes can be applied to Neovim; the first version let the user opt back in.'),
    ...para('--', r'A day later the commit e874f9f, "Remove Omarchy support: Island Dark unconditional, drop hot-reload, theme symlink, all-themes specs and their lock entries", deleted the switch. The helper and both conditionals went, the file shrank to the 18 lines above, and the theme became unconditional, in line with the header word "permanent". The commit also removed the hot-reload plugin (lua/plugins/omarchy-theme-hotreload.lua) and the all-themes spec, and touched the lockfile to drop their entries. The cost of the decision is a loss of flexibility: there is no longer a supported way to follow the desktop theme. The benefit is that the config has one theme, tested thoroughly, with no mode in which half the groups come from somewhere else.'),
    ...sec(r'is there a standalone repository?'),
    ...para('--', r'On 2026-10-22 the Rust tooling modules were extracted into standalone repositories, the nine xyno-*.nvim plugins next to each other in ~/projects/xyno-plugins. I checked that directory, and none of the nine is a theme: the list is clipboard, crates, guard, history, imports, macros, new, rust and sandbox. Island Dark remains part of this configuration. That fits the header comment: the theme needs no plugin, so there is no reason for lazy.nvim to fetch one, and the only thing a spec has to do is name it.'),
    ...sec(r'failure modes'),
    ...pt('--', r'a typo in the name', r'if either string were wrong, LazyVim would fail to load the colourscheme at startup and lualine would error on its theme lookup. The spec "is configured for LazyVim and lualine through lua/plugins/island-theme.lua" catches this, and a second test runs :colorscheme island-dark and requires that nothing is printed.'),
    ...pt('--', r'another theme later', r'running :colorscheme with some other name works and is supported: the lualine theme file returns the auto theme in that case, so the bar follows.'),
    ...sec(r'tests'),
    ...para('--', r'The describe block "island-dark loading" in tests/theme-island_spec.lua has five tests. They check that the scheme is active after startup, with colors_name set, the background dark and termguicolors on; that the spec configures both LazyVim and lualine; that colors/island-dark.lua clears highlights, resets syntax, sets the globals and then calls setup(); that it runs syntax reset only when syntax is on; and that :colorscheme island-dark produces no messages.'),
    ...sec(r'history'),
    ...pt('--', r'cf842d0 (2026-10-12)', r'created, 28 lines, with the follow-Omarchy escape hatch.'),
    ...pt('--', r'e874f9f (2026-10-13)', r'"Remove Omarchy support: Island Dark unconditional...". The 18 lines of today.'),
  ],
);
