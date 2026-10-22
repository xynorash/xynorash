import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/after/ftplugin/rust.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'after/ftplugin/rust.lua — three small fights with defaults'),
    cm('--', r'lifetimes, spelling and an escaped quote'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'Rust-only buffer settings and insert-mode mappings'),
    kv(r'language', r'Lua, run by Neovim on FileType rust'),
    kv(r'size', r'43 lines, 2 commits (2026-10-13, 2026-10-14)'),
    kv(r'overrides', r'mini.pairs, LazyVim spell defaults'),
    kv(r'tested by', r'tests/keymaps-global_spec.lua, tests/keymaps-rust_spec.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'It is a list of three things that the generic editing setup gets wrong in Rust. None of them is a Rust feature. All of them are the cost of letting a plugin or a default do something sensible for most languages. Each one was found by using the editor and is written up in the comment above it, with the exact input that went wrong.'),
    ...sec(r'1. the lifetime quote'),
    ...code('lua', r'after/ftplugin/rust.lua · lines 1-7', r'''
-- Rust-only buffer settings.

-- mini.pairs pairs `'` after `&` and `<`, so typing a lifetime left a stray
-- quote (`&'a str)` became `&'a str')`). Rust has lifetimes and char
-- literals, which no pairing rule tells apart: type `'` plainly (a char
-- literal's closing quote is one more key).
vim.keymap.set("i", "'", "'", { buffer = true, desc = "Quote (no pairing: lifetimes)" })'''),
    ...para('--', r'mini.pairs inserts a closing character when you type an opening one. For the single quote it has rules about when pairing is wanted, and it pairs after an ampersand or an opening angle bracket, a convention that works for many languages. In Rust those are exactly the positions where a lifetime appears: &’a str, Foo<’a>. Typing the apostrophe produced two, and the extra one stayed behind.'),
    ...para('--', r'The fix is a buffer-local insert-mode mapping of the quote key to the quote character. The right-hand side is just "’", which means "insert a quote", and because a mapping replaces the plugin’s global one for this buffer, mini.pairs no longer sees the key. The cost is stated in the last line of the comment: a character literal needs its closing quote typed by hand. The comment also explains why a smarter rule is not attempted: nothing in the text before the cursor tells a lifetime from the start of a char literal, so the file picks the behaviour that never leaves junk. The desc field names the mapping in the which-key and :imap listings. The spec in tests/keymaps-global_spec.lua checks that exact description in a Rust buffer, and also that the mapping did not leak into a Lua buffer.'),
    ...sec(r'2. spelling, but only where it helps'),
    ...code('lua', r'after/ftplugin/rust.lua · lines 9-25', r'''
-- Spell check comments and doc comments only: the Rust highlights query marks
-- them @spell, so identifiers and strings are skipped. `camel` also checks
-- the parts of camelCase words.
vim.opt_local.spell = true
vim.opt_local.spelloptions:append("camel")

-- Rust words (Vec, tokio, impl, usize, ...) are not in the `en` dictionary and
-- were flagged in every comment: spell/en.utf-8.add ships them (it must be named
-- after a 'spelllang' language, else nvim does not load it). nvim only reads the
-- compiled .spl, which is built here when missing or older (git-ignored). `zg`
-- still writes to the first entry (the user's own list, not this repo).
local add = vim.fn.stdpath("config") .. "/spell/en.utf-8.add"
local add_stat, spl_stat = vim.uv.fs_stat(add), vim.uv.fs_stat(add .. ".spl")
if add_stat and (not spl_stat or spl_stat.mtime.sec < add_stat.mtime.sec) then
  pcall(vim.cmd, "silent mkspell! " .. vim.fn.fnameescape(add))
end
vim.opt_local.spellfile = { vim.fn.stdpath("data") .. "/site/spell/en.utf-8.add", add }'''),
    ...para('--', r'The first commit turned spell checking on in Rust buffers. Spelling is only useful in prose, and Neovim’s spell checker consults the syntax: the Rust highlights query marks comments with @spell, so identifiers and string literals are skipped. The camel option makes the checker split camelCase words and check the parts. Both are buffer-local (opt_local), so nothing changes for other filetypes.'),
    ...para('--', r'The second commit (f31e013, the next day) fixed what that caused. Rust vocabulary (Vec, tokio, impl, usize) is not English, so every comment lit up with red underlines. The solution is a word list shipped in the repository, spell/en.utf-8.add, and the comment records three non-obvious facts about how Neovim handles it. The file has to be named after a language in spelllang, otherwise it is not loaded. Neovim reads only the compiled .spl file, so the code builds one with :mkspell! when it is missing or older than the word list, comparing modification times. The compiled file is git-ignored, so each machine builds its own on first opening a Rust file. And zg, the command that adds a word under the cursor, writes to the first entry of spellfile, which is why the user’s own list in the data directory comes first and the repository’s list second: personal additions never end up in the repository.'),
    ...para('--', r'The mkspell call is inside pcall and silent. If the directory is read-only, or the word list has an error, the worst outcome is that the Rust words are flagged again; opening a file never fails. The mtime comparison is on whole seconds (mtime.sec), so a list and a compiled file written within the same second count as up to date.'),
    ...sec(r'3. the escaped quote'),
    ...code('lua', r'after/ftplugin/rust.lua · lines 27-43', r'''
-- mini.pairs jumps over the auto-inserted closing `"` when it is typed behind
-- a backslash, so `"a\"b"` ended as `"a\"b";"`. An escaped quote (odd number
-- of backslashes before the cursor) is inserted plainly; every other `"`
-- keeps the global mini.pairs mapping.
vim.keymap.set("i", '"', function()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local backslashes = #vim.api.nvim_get_current_line():sub(1, col):match("\\*$")
  if backslashes % 2 == 1 then
    return '"'
  end
  for _, m in ipairs(vim.api.nvim_get_keymap("i")) do
    if m.lhs == '"' and m.expr == 1 then
      return m.callback and m.callback() or vim.api.nvim_eval(m.rhs) -- mini.pairs: a v:lua expression
    end
  end
  return '"'
end, { buffer = true, expr = true, replace_keycodes = false, desc = "Quote (plain after a backslash)" })'''),
    ...para('--', r'The third one is the most delicate, because here the plugin’s behaviour is mostly right and only a case must be carved out. Typing the opening quote of a string gives a pair. Typing a backslash and a quote inside a string is meant to put a literal quote in the string, and mini.pairs, seeing a closing quote under the cursor, jumped over it, so "a\"b" ended as "a\"b";" with a stray character. The new mapping is an expression mapping, so it returns the keys to insert.'),
    blank,
    ...pt('--', r'counting backslashes', r'the text before the cursor is matched against the pattern \\*$, zero or more backslashes at the end. The pattern always matches (possibly with an empty string), so the length is always defined. Odd means the quote is escaped, because a pair of backslashes is an escaped backslash and the quote is then real. Odd: return a plain quote, nothing else.'),
    ...pt('--', r'delegating the rest', r'otherwise the function looks through the insert-mode mappings for the global one on the same key with the expr flag and calls it. The comment on the evaluation line tells what to expect: mini.pairs maps the key to a v:lua expression, and the code runs it either through its Lua callback or with nvim_eval of the right-hand side. If the plugin’s mapping is not found, the fallback returns a plain quote, so typing never breaks even when the plugin is disabled.'),
    ...pt('--', r'replace_keycodes = false', r'the returned string comes from mini.pairs, which already contains termcodes (such as the left-arrow sequence that puts the cursor inside the new pair). Asking Neovim to replace keycodes a second time would mangle them, so it is turned off. This matters; leaving the default would break pairing in every string.'),
    blank,
    ...para('--', r'This function is also an example of a decision to wrap, not replace. The author could have disabled the plugin’s pairing for double quotes in Rust altogether. They chose a precise exception and let the plugin keep doing everything else.'),
    ...sec(r'why after/ftplugin'),
    ...para('--', r'A file in after/ftplugin runs after every other ftplugin for the type, which is the only time the mappings above are guaranteed to override the global mini.pairs mappings and the spell settings of anything else. The effect is scoped by buffer = true and opt_local, so Lua, Markdown and the rest keep the defaults. The spec for the quote mapping states this boundary in a negative test: the Rust mapping must not appear in a Lua buffer.'),
    ...sec(r'related changes in the repository'),
    ...para('--', r'The pairing and spell files sit next to the repository’s other editing decisions: the sqlx injection queries, the snippets, and the http ftplugin. After the 2026-10-22 split of the Rust tooling into xyno-*.nvim plugins, this file stayed in the configuration: it is about editor behaviour, not about cargo or rust-analyzer, so it has no obvious home in a plugin like xyno-rust.nvim.'),
    ...sec(r'history'),
    ...pt('--', r'99acd7e (2026-10-13)', r'"Batch 4: editing and UI (lifetime-safe quote, comment spelling, ...)". Creates the file with the quote mapping and the spell settings, 13 lines.'),
    ...pt('--', r'f31e013 (2026-10-14)', r'"Final loop round 4: field test leftovers (... escaped quote pairing, Rust spellfile, ...)". Adds the word list handling and the escaped-quote mapping (30 lines added). The escaped-quote case is test 33 in tests/keymaps-rust_spec.lua.'),
  ],
);
