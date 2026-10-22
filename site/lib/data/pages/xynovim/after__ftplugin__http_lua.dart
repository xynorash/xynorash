import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/after/ftplugin/http.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'after/ftplugin/http.lua — three lines, one setting'),
    cm('--', r'keep the quotes visible in a request body'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'buffer-local option override for .http files'),
    kv(r'language', r'Lua, run by Neovim on FileType http'),
    kv(r'size', r'3 lines, 1 commit (f31e013, 2026-10-14)'),
    kv(r'setting', r'conceallevel = 0, window-local'),
    kv(r'tested by', r'tests/startup-and-options_spec.lua'),
    ...sec(r'the whole file'),
    ...code('lua', r'after/ftplugin/http.lua · lines 1-3', r'''
-- LazyVim sets conceallevel=2 globally; in a request body it hid the quotes of JSON
-- (`{"a": 1}` showed as `{a: 1}`), which is not what a request sends.
vim.opt_local.conceallevel = 0'''),
    ...sec(r'what went wrong first'),
    ...para('--', r'.http files are request files for the kulala REST client: a method and URL, headers, and often a JSON body. The configuration uses them to send requests from the editor. The bug is easy to state and easy to miss. LazyVim sets conceallevel to 2 globally, which makes Neovim hide certain syntax characters, and in the JSON syntax the quote marks around keys and strings are among the things that can be concealed. A body like {"a": 1} was displayed as {a: 1}. Nothing in the file changed, so a request would still send the quotes, but the reader sees something different from what is sent, which is the worst kind of editor behaviour for a tool whose job is to make HTTP requests accurately. The comment says it plainly: this is not what a request sends.'),
    ...sec(r'why an ftplugin'),
    ...para('--', r'Neovim runs ftplugin files named for the filetype when a buffer gets that filetype. conceallevel is a window-local option, so the right tool is vim.opt_local, which sets it for the window that is showing the buffer and does not touch any other window or the global default. The file is placed in after/ftplugin/ rather than ftplugin/ so it loads after the runtime’s own and the plugins’ ftplugin scripts for http, and so it is the last word. If a kulala ftplugin had set conceallevel itself, this file would override it.'),
    ...para('--', r'The alternative would be an autocmd on FileType http in config/autocmds.lua. The ftplugin form needs no autocmd group, no pattern and no cleanup, and it lives with the other per-filetype files: after/ftplugin/rust.lua is its neighbour, and the two together are the repository’s pattern for filetype specific settings.'),
    ...sec(r'edge cases and limits'),
    ...pt('--', r'window-local', r'because the setting is on the window, opening an http buffer in a window and then loading a different file into the same window leaves conceallevel at 0 until something resets it. Neovim’s ftplugin mechanism does not undo window options on a buffer switch (that is why ftplugins normally set b: and w: options with the b:undo_ftplugin convention). This file does not set undo_ftplugin. In practice a split that held a request file and later shows Lua would keep conceallevel 0, which is harmless: it only makes more characters visible.'),
    ...pt('--', r'which characters', r'conceallevel = 0 turns off all concealing in the window, not only quotes. In an .http buffer there is, from what the comment says, nothing worth concealing, so the broad setting costs nothing.'),
    ...pt('--', r'other filetypes', r'nothing else changes. JSON files, markdown and the rest keep LazyVim’s level 2, which the spec also checks.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/startup-and-options_spec.lua, in a block named after the file, creates a Lua scratch buffer and checks that conceallevel is 2 there, then creates another buffer, sets its filetype to http, and checks that conceallevel is 0. Both halves of the claim in the comment are therefore asserted: LazyVim’s global default is real, and this file is what changes it.'),
    ...sec(r'history'),
    ...para('--', r'The file has one commit, f31e013 of 2026-10-14, "Final loop round 4: field test leftovers", whose long subject lists many small fixes, among them "http conceal". The word field test in these commit names refers to the author using the configuration and writing down what annoyed them. This is one of those findings, resolved with the smallest change that works.'),
    ...sec(r'where it sits'),
    ...para('--', r'Together with the Rust ftplugin and the injections queries, this is the "per filetype" layer of the configuration: no plugin, no framework, a few lines each, aimed at one observed annoyance. Both the extraction of the Rust tooling into the xyno-*.nvim plugins on 2026-10-22 and the new Island Dark theme left it untouched.'),
  ],
);
