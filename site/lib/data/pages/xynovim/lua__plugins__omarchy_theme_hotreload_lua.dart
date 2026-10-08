import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/omarchy-theme-hotreload.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'omarchy-theme-hotreload.lua — following the OS theme, live'),
    cm('--', 'clear, unload, reload, reapply: a colorscheme switch with no restart'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'reloads the colorscheme inside a running Neovim when the Omarchy theme changes'),
    kv('language', 'Lua (a local pseudo-plugin spec holding one autocmd)'),
    kv('size', '103 lines: 69 of code, 20 of comment, 14 blank; tab-indented'),
    kv('history', '2 commits: 2026-09-02 (migration) and 2026-09-03 (two bug fixes)'),
    kv('reads', 'lua/plugins/theme.lua; sources plugin/after/transparency.lua'),
    ...sec('the problem'),
    ...para('--',
        r'This config runs on Omarchy (Arch), which changes the system '
        r'theme at runtime, and the editor is supposed to follow '
        r'without a restart. For Neovim that is awkward. A colorscheme '
        r'is not a setting. It is a '
        r'plugin whose Lua modules compute a palette, define dozens of '
        r'highlight groups, and may have stashed state in module-level '
        r'variables. Changing it in a running editor means leaving '
        r'none of the old theme behind and not breaking anything that '
        r'depends on it.'),
    blank,
    ...para('--',
        r'This file solves that. It is described in CHANGELOG 1.0.0 as '
        r'part of the Omarchy desktop integration: “live theme '
        r'switching”. Its sibling pages are all-themes.lua (which makes '
        r'every theme available), theme.lua (the symlink that carries '
        r'the current theme in) and plugin/after/transparency.lua '
        r'(which has to be reapplied afterwards).'),

    ...sec('where this file comes from'),
    ...para('--',
        r'A note on provenance, as an inference from the evidence '
        r'rather than a claim the repo makes. The migration commit '
        r'eabb22a lists this file under “Omarchy desktop integration”, '
        r'and it is indented with tabs while stylua.toml in the same '
        r'repo asks for two spaces, which is how the files written for '
        r'this config are formatted. The same tab style appears in '
        r'all-themes.lua, transparency.lua, disable-news-alert.lua and '
        r'snacks-animated-scrolling-off.lua. My reading is that these '
        r'five arrived from the Omarchy distribution’s own defaults and '
        r'this repo kept them. What is Nash’s own contribution here is '
        r'the maintenance: the two fixes in f35b4f6 below.'),

    ...sec('the shape: a spec that is really an autocmd'),
    ...code('lua', 'lua/plugins/omarchy-theme-hotreload.lua · the shell', r'''
return {
  {
    name = "theme-hotreload",
    dir = vim.fn.stdpath("config"),
    lazy = false,
    priority = 1000,
    config = function()
      local transparency_file = vim.fn.stdpath("config") .. "/plugin/after/transparency.lua"

      vim.api.nvim_create_autocmd("User", {
        pattern = "LazyReload",
        callback = function()
          ...
        end,
      })
    end,
  },
}'''),
    ...para('--',
        r'There is no plugin here. dir = vim.fn.stdpath("config") makes '
        r'the spec point at the Neovim configuration directory itself, '
        r'so lazy.nvim has nothing to download, and lazy = false with '
        r'priority = 1000 loads it at startup before ordinary plugins. '
        r'The config function runs once and its only job is to '
        r'register one autocmd, on a User event called LazyReload. It '
        r'is a common lazy.nvim idiom for attaching code to the '
        r'plugin manager’s lifecycle.'),
    blank,
    ...para('--',
        r'What fires LazyReload? Not this repo. It is an event '
        r'lazy.nvim emits after a spec reload. The chain that connects '
        r'it to a theme switch is: Omarchy switches the theme, the '
        r'contents behind lua/plugins/theme.lua change, something '
        r'causes lazy.nvim to reload specs, and LazyReload fires. The '
        r'first two links and the trigger live outside the repo, in '
        r'Omarchy, and I could not verify them from here. What the '
        r'file shows is its side of the contract: it will run when '
        r'that event arrives.'),

    ...sec('step one: read the new theme from disk'),
    ...code('lua', 'lua/plugins/omarchy-theme-hotreload.lua · re-reading the spec (trimmed)', r'''
          -- Unload the theme module
          package.loaded["plugins.theme"] = nil

          vim.schedule(function()
            local ok, theme_spec = pcall(require, "plugins.theme")
            if not ok then
              return
            end'''),
    ...para('--',
        r'plugins.theme is the Lua module name of lua/plugins/theme.lua. '
        r'Lua caches every module in package.loaded after the first '
        r'require, so a second require would hand back the previous '
        r'theme. Setting the cache entry to nil forces a fresh read '
        r'of the file, and the file is a symlink to Omarchy’s '
        r'current theme, so a fresh read means the new theme.'),
    blank,
    ...para('--',
        r'vim.schedule postpones the rest until the current event '
        r'handler has finished, so the work does not run in the '
        r'middle of lazy.nvim’s own reload. The pcall means a theme '
        r'file with an error leaves the editor on the old theme '
        r'instead of throwing from inside an autocmd.'),
    blank,
    ...para('--',
        r'The loaded value is a list of lazy.nvim specs, and the rest '
        r'of the file relies on its shape. It expects some spec with '
        r'a plugin name in the first slot, and a spec for '
        r'LazyVim/LazyVim whose opts.colorscheme names what to '
        r'apply. all-themes.lua’s header comment describes where '
        r'such files come from: “Omarchy 4 generates most theme '
        r'specs from default/themed/neovim.lua.tpl on top of aether”, '
        r'and Omarchy 3.8 ships a neovim.lua per theme.'),

    ...sec('step two: find which plugin is the theme'),
    ...code('lua', 'lua/plugins/omarchy-theme-hotreload.lua · naming the theme plugin', r'''
          -- Find the theme plugin and unload it
          local theme_plugin_name = nil
          for _, spec in ipairs(theme_spec) do
            if spec[1] and spec[1] ~= "LazyVim/LazyVim" then
              theme_plugin_name = spec.name or spec[1]
              break
            end
          end'''),
    ...para('--',
        r'The rule is “the first spec that is not LazyVim itself”. It '
        r'prefers an explicit name field over the repository string, '
        r'because that is the name lazy.nvim registers the plugin '
        r'under. The aether comment in all-themes.lua shows why names '
        r'matter here: a generated spec that renames a plugin changes '
        r'the key it is registered under. The first-match rule is a '
        r'heuristic; a theme file that listed a helper plugin before '
        r'the theme would confuse it.'),

    ...sec('step three: leave nothing of the old theme behind'),
    ...code('lua', 'lua/plugins/omarchy-theme-hotreload.lua · clearing state', r'''
          -- Clear all highlight groups before applying new theme
          vim.cmd("highlight clear")
          -- vim.fn.exists returns 0/1, and 0 is truthy in Lua -
          -- must compare, or this branch always runs
          if vim.fn.exists("syntax_on") == 1 then
            vim.cmd("syntax reset")
          end

          -- Reset background to default so colorscheme can set it properly (light themes will set to light)
          vim.o.background = "dark"'''),
    ...para('--',
        r'Three resets. highlight clear wipes every highlight group, so '
        r'the new scheme starts from an empty slate and nothing of the '
        r'old palette survives. syntax reset returns syntax '
        r'highlighting to its defaults, but only if syntax is on. And '
        r'background goes '
        r'back to dark so a scheme that is light can set itself to '
        r'light, instead of inheriting the previous theme’s choice.'),
    blank,
    ...para('--',
        r'The comment on the middle block is the first of two bug '
        r'fixes in f35b4f6 (2026-09-03). The original line was '
        r'if vim.fn.exists("syntax_on") then. vim.fn.exists returns '
        r'1 or 0 as a number, and in Lua the number 0 is truthy, '
        r'only nil and false are not. So the condition was true on '
        r'every reload and the syntax reset always ran, whether '
        r'syntax was on or not. CHANGELOG 1.3.0 says it plainly: '
        r'“compared == 1 (0 is truthy in Lua — the branch always '
        r'ran)”. It is the kind of bug that no test notices, because '
        r'the result looks fine, and that anyone who switches between '
        r'Vimscript and Lua will meet exactly once.'),

    ...sec('step four: unload the old theme’s code'),
    ...code('lua', 'lua/plugins/omarchy-theme-hotreload.lua · unloading modules', r'''
          -- Unload theme plugin modules to force full reload
          if theme_plugin_name then
            local plugin = require("lazy.core.config").plugins[theme_plugin_name]
            if plugin then
              -- Unload all lua modules from the plugin directory
              -- (pcall: a pure-vimscript colorscheme has no lua/ dir)
              local plugin_dir = plugin.dir .. "/lua"
              pcall(require("lazy.core.util").walkmods, plugin_dir, function(modname)
                package.loaded[modname] = nil
                package.preload[modname] = nil
              end)
            end
          end'''),
    ...para('--',
        r'The same trick as step one, applied to the colorscheme '
        r'plugin. walkmods iterates every Lua module under the '
        r'plugin’s lua/ directory, and each module is removed from '
        r'both package.loaded and package.preload. After this, '
        r'requiring the plugin again re-executes its code from the '
        r'top, including any module-level caches. Colorscheme '
        r'plugins that compute their palettes in a module (the usual '
        r'case) would otherwise keep serving the old values.'),
    blank,
    ...para('--',
        r'The second fix of f35b4f6 is the pcall around walkmods and '
        r'its comment “a pure-vimscript colorscheme has no lua/ dir”. '
        r'Without it, a missing directory would presumably raise inside '
        r'the scheduled callback and stop the reload after the '
        r'highlights had already been cleared (my inference from the '
        r'code; the changelog records only the fix). A half-applied '
        r'reload is the worst outcome this file can produce: no theme '
        r'at all. The pcall turns a missing directory into “nothing '
        r'to unload”.'),

    ...sec('step five: load the new colorscheme the right way'),
    ...code('lua', 'lua/plugins/omarchy-theme-hotreload.lua · loading (trimmed)', r'''
          -- Find and apply the new colorscheme
          for _, spec in ipairs(theme_spec) do
            if spec[1] == "LazyVim/LazyVim" and spec.opts and spec.opts.colorscheme then
              local colorscheme = spec.opts.colorscheme

              -- Load the colorscheme plugin. If it's already loaded (old and new
              -- theme sharing the same plugin, e.g. generic themes on aether.nvim),
              -- lazy won't rerun setup() on a spec reload and keeps the old
              -- resolved opts in the plugin's property cache, so fully reload it
              -- to reapply setup() with the new theme's opts.
              local theme_plugin = theme_plugin_name and require("lazy.core.config").plugins[theme_plugin_name]
              if theme_plugin and theme_plugin._.loaded then
                require("lazy.core.loader").reload(theme_plugin)
              else
                require("lazy.core.loader").colorscheme(colorscheme)
              end'''),
    ...para('--',
        r'This is the subtlest part, and the comment is a compact '
        r'account of a real trap. Two cases:'),
    ...pt('--', 'the plugin is not loaded yet',
        r'ask lazy.nvim to load whichever plugin provides the named '
        r'colorscheme. This is the point of all-themes.lua: every '
        r'theme plugin is declared lazy = true, so none is loaded '
        r'until it is needed, and this call is what needs it.'),
    ...pt('--', 'the plugin is already loaded',
        r'old and new theme belong to the same plugin. The comment '
        r'gives the example of “generic themes on aether.nvim”: in '
        r'Omarchy 4 many themes are generated on top of one plugin, '
        r'each with different opts. lazy.nvim does not re-run setup() '
        r'when a spec reloads and it keeps the previous opts in a '
        r'cache, so merely re-applying the colorscheme would paint '
        r'the new theme name with the old theme’s palette options. '
        r'The fix is the heavier loader.reload, which redoes setup '
        r'with the new opts.'),
    blank,
    ...para('--',
        r'Note the code asks the plugin object rather than guessing: '
        r'theme_plugin._.loaded is lazy.nvim’s own bookkeeping flag. '
        r'The for loop ends with a break after the first LazyVim spec '
        r'that carries a colorscheme, so only one is applied even if '
        r'a theme file lists several.'),

    ...sec('step six: apply, then repair the things a repaint breaks'),
    ...code('lua', 'lua/plugins/omarchy-theme-hotreload.lua · applying (trimmed)', r'''
              vim.defer_fn(function()
                -- Apply the colorscheme (it will set background itself)
                pcall(vim.cmd.colorscheme, colorscheme)

                -- Force redraw to update all UI elements
                vim.cmd("redraw!")

                -- Reload transparency settings
                if vim.fn.filereadable(transparency_file) == 1 then
                  vim.defer_fn(function()
                    vim.cmd.source(transparency_file)

                    -- Trigger UI updates for various plugins
                    vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
                    vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })

                    -- Final redraw
                    vim.cmd("redraw!")
                  end, 5)
                end
              end, 5)'''),
    ...para('--',
        r'Two nested 5 ms deferrals move the colorscheme command, and '
        r'then the transparency step, to later event-loop ticks, so '
        r'the new scheme is applied first and transparency is applied '
        r'on top of it. The 5 ms is not explained anywhere, and I '
        r'would read it as “just after the current tick”, not as a '
        r'tuned value. The colorscheme command is pcall-ed so a '
        r'missing scheme does not raise from a timer.'),
    blank,
    ...para('--',
        r'After the colorscheme, three repairs happen in order:'),
    ...pt('--', 'transparency is reapplied',
        r'a new colorscheme repaints every background, so the '
        r'transparent look from plugin/after/transparency.lua is '
        r'gone until that file runs again. The file is sourced '
        r'explicitly, but only if it is readable.'),
    ...pt('--', 'ColorScheme is fired by hand',
        r'listeners, such as statuslines and other colour-aware '
        r'plugins, recompute their colours when that event fires.'),
    ...pt('--', 'VimEnter is fired by hand',
        r'the comment says “trigger UI updates for various plugins”. '
        r'This is the bluntest tool in the file, because it re-runs '
        r'every handler registered for VimEnter, including any that '
        r'assumed it would run only once. Whether that matters '
        r'depends on the plugins loaded. I did not find a recorded '
        r'reason or a recorded problem, so it stays on the list of '
        r'things to know about.'),
    blank,
    ...para('--',
        r'The ordering interacts with an earlier decision. CHANGELOG '
        r'1.3.0 records that transparency used to be applied only at '
        r'startup, and that “only the Omarchy hot-reload path '
        r're-sourced it”. That was the entire reason for the source '
        r'line above: without it, a theme switch brought back the '
        r'opaque background. After 1.3.0 transparency.lua registers '
        r'its own ColorScheme handler, so the explicit source is now '
        r'partly redundant (the colorscheme command already fires '
        r'the event, and so does the exec_autocmds line). That is my '
        r'observation about the current code, not something the '
        r'changelog says, and the redundancy is harmless because the '
        r'transparency file is written to be sourced repeatedly.'),

    ...sec('what was fixed, and how it was verified'),
    cm('--', '  2026-09-03  f35b4f6'),
    cm('--', '    exists("syntax_on") compared == 1   (0 is truthy in Lua)'),
    cm('--', '    walkmods wrapped in pcall           (vimscript themes)'),
    blank,
    ...para('--',
        r'Both are listed in CHANGELOG 1.3.0 under Fixed, in a single '
        r'line each. The entry does not describe how either was '
        r'verified, and, unlike the bacon-ls and auto-save work, no '
        r'measurement or reproduction is recorded. The first is '
        r'verifiable by reading (Lua truthiness is documented); the '
        r'second is a guard whose failure case, a theme with no lua '
        r'directory, I take on the changelog’s word. I note this '
        r'because most of this config’s fixes come with evidence '
        r'and these two do not.'),

    ...sec('limits'),
    ...pt('--', 'the trigger is outside the repo',
        r'LazyReload is fired by lazy.nvim, and the link from an '
        r'Omarchy theme switch to a spec reload is not visible '
        r'here.'),
    ...pt('--', 'heuristic matching',
        r'“first spec that is not LazyVim” and “first LazyVim spec '
        r'with a colorscheme” are rules that fit today’s generated '
        r'theme files and could be wrong for a different layout.'),
    ...pt('--', 'blunt event replay',
        r'firing VimEnter again re-runs every VimEnter handler.'),
    ...pt('--', 'fixed delays',
        r'two 5 ms timers order the steps; on a loaded machine that '
        r'is a race by construction, though no failure is recorded.'),
    ...pt('--', 'no tests',
        r'this file is exercised only by switching themes by hand.'),
    blank,
    ...para('--',
        r'The sequence is the lesson: tear down the old, load the new '
        r'by the cheapest correct route, reapply what the new theme '
        r'overwrites. Each of the six steps exists because skipping '
        r'it leaves a visible artifact, and two of them (the '
        r'== 1 comparison and the pcall) were found only after the '
        r'first version shipped.'),
    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
