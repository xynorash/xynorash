import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/plugin/after/unsafe-highlight.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'plugin/after/unsafe-highlight.lua — underline the unsafe'),
    cm('--', r'one highlight group, re-applied after every colourscheme'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'make rust-analyzer’s unsafe tokens underlined'),
    kv(r'language', r'Lua, runs once at startup from plugin/after/'),
    kv(r'size', r'15 lines, 2 commits (2026-10-09, 2026-10-13)'),
    kv(r'sibling', r'plugin/after/transparency.lua (same re-apply pattern)'),
    kv(r'tested by', r'tests/theme-island_spec.lua, describe unsafe highlight'),
    ...sec(r'why this file exists'),
    ...para('--', r'In Rust, unsafe is not a style, it is the place where the compiler stops checking for you. rust-analyzer marks every token that is unsafe in the semantic token stream with an unsafe modifier: a call to an unsafe function, a dereference of a raw pointer, the name of an unsafe fn. This file turns that modifier into a visible underline so those tokens stand out in otherwise ordinary code.'),
    ...code('lua', r'plugin/after/unsafe-highlight.lua · lines 1-15', r'''
-- Underline everything rust-analyzer marks with the `unsafe` semantic-token
-- modifier (unsafe calls, derefs of raw pointers, unsafe fns). A modifier
-- group only adds an attribute on top of the token's own colour. Like
-- transparency.lua this is applied now and on every ColorScheme, because a
-- theme switch (`highlight clear` from a theme switch) wipes it.
local function apply()
	vim.api.nvim_set_hl(0, "@lsp.mod.unsafe.rust", { underline = true })
end

vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("user_unsafe_highlight", { clear = true }),
	callback = apply,
})

apply()'''),
    ...sec(r'a modifier, not a colour'),
    ...para('--', r'Neovim names semantic token highlights @lsp.type.<type> and @lsp.mod.<modifier>, with an optional language suffix. The group @lsp.mod.unsafe.rust is therefore "the unsafe modifier, in Rust buffers". When a token has both a type and modifiers, Neovim applies the groups in layers, and a modifier group that sets only underline leaves the foreground from the type group untouched. That is exactly what the second comment sentence says. An unsafe function call stays the function colour and gains an underline; a raw pointer dereference stays the text colour and gains an underline. The attribute travels with the token instead of replacing its colour.'),
    ...para('--', r'It is also the reason this is not done in lua/island/init.lua with the other semantic token groups. That file contains a comment on exactly this point: unsafe is left to plugin/after/unsafe-highlight.lua, and the scheme’s UNSAFE_CODE background is not applied because it would paint a code-wide band. So the theme file defines the group RustUnsafeCode with the scheme colour for anyone who wants it, and this file decides how unsafe actually looks.'),
    ...sec(r'why it survives a colourscheme change'),
    ...para('--', r'Every colourscheme starts with :highlight clear, which wipes all highlight groups, including ones set by other files. A one-off nvim_set_hl at startup would therefore vanish the first time the theme was reloaded or replaced. The pattern here is the one transparency.lua uses: wrap the setting in apply(), call it now, and call it again from a ColorScheme autocmd. The ColorScheme event fires after the scheme has finished loading, so apply() runs on top of the cleared state.'),
    ...para('--', r'The augroup is created with clear = true. That makes the file safe to source more than once (for example with :source or in a test) because the second run replaces the autocmd instead of adding a duplicate. The spec asserts that there is exactly one ColorScheme autocmd in user_unsafe_highlight.'),
    ...sec(r'why plugin/after'),
    ...para('--', r'Files under plugin/ run at startup, and those under plugin/after/ run last of all, after every plugin’s own plugin/ files. Because of that, the apply() at the end of the file sets the group after anything a plugin might have defined, and it does not depend on lazy.nvim’s loading order. The spec confirms the result after a complete :colorscheme island-dark: the group is still underlined.'),
    ...sec(r'details of the file'),
    ...pt('--', r'indentation', r'this file is indented with tabs, like transparency.lua; island/init.lua and the ftplugins use two spaces. It is cosmetic (the file was written once, in commit 527f350, and never reformatted) and stylua.toml in the repository decides what the formatter would do if run.'),
    ...pt('--', r'the comment', r'the last line of the header reads "(`highlight clear` from a theme switch)", which is a leftover. Until 2026-10-13 it said "Omarchy hot-reload runs `highlight clear`". When Omarchy support was removed, commit e874f9f edited the words but not the sentence, so it reads a little circular now. The behaviour is unchanged.'),
    ...pt('--', r'only underline', r'no colour, no sp. The underline takes the token’s foreground. Mutable bindings in the theme use the same mechanism with an explicit sp colour, so the two underlines are distinguishable by colour: mutable ones are underlined in the text grey, unsafe ones follow the token colour.'),
    ...sec(r'what could go wrong'),
    ...pt('--', r'rust-analyzer does not send the modifier', r'the group is only ever used if the server reports the unsafe modifier. This depends on the server version and on semantic tokens being enabled in the client. The file cannot detect that.'),
    ...pt('--', r'a theme that sets the group itself', r'if a later colourscheme defined @lsp.mod.unsafe.rust differently, the ColorScheme handler would still run afterwards and overwrite it with plain underline. That is intended: the user prefers this look regardless of the theme.'),
    ...sec(r'tests'),
    ...para('--', r'The describe block "unsafe highlight" in tests/theme-island_spec.lua has two cases. The first checks the whole life cycle in one test: the group is underlined, :highlight clear leaves it empty, there is exactly one autocmd in the augroup, and after a manual doautocmd ColorScheme the underline is back. The second checks the group after a full :colorscheme island-dark. A separate Rust test in the same repository runs a real rust-analyzer and checks that actual tokens resolve to the scheme colours.'),
    ...sec(r'history'),
    ...pt('--', r'527f350 (2026-10-09)', r'"Roadmap step 10 wip: rest extra, domain plugin, routes, sql injection, unsafe hl". The file is created, 15 lines, before the Island Dark theme existed. At that time the thing that wiped highlights was Omarchy’s hot-reload, as the original comment states.'),
    ...pt('--', r'e874f9f (2026-10-13)', r'"Remove Omarchy support: Island Dark unconditional...". One line changes, the comment.'),
  ],
);
