import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-imports.nvim/tests/e2e/smoke.lua',
  lines: [
    cm(r'''--''', r'''──────────────────────────────────────────'''),
    cm(r'''--''', r'''smoke.lua — does the plugin survive a real plugin manager'''),
    cm(r'''--''', r'''lazy.nvim loads it, the help resolves, the missing dependency is one line'''),
    cm(r'''--''', r'''──────────────────────────────────────────'''),
    blank,
    kv(r'''role''', r'''end-to-end check run by CI after the specs'''),
    kv(r'''language''', r'''Lua, executed with nvim --headless -u tests/e2e/init.lua -c luafile'''),
    kv(r'''size''', r'''67 lines, 17 named checks'''),
    kv(r'''exit''', r'''cquit 1 when any check failed, qa! otherwise'''),
    ...sec(r'''why this file exists'''),
    ...para(r'''--''', r'''The specs load the plugin by putting its directory on the runtime path and calling require. That proves the code works, not that the plugin works the way people install it. Plugin managers add a layer: they decide the module name, call setup with opts, and may load lazily. A plugin can pass every unit test and still fail there, for instance because the module name does not match the directory, or because setup was never called. This file is the cheapest honest check of the real installation path. It was added with the specs in 45d98cb.'''),
    blank,
    ...sec(r'''the harness in 7 lines'''),
    ...para(r'''--''', r'''The file does not use the spec harness. It is a standalone script run after the editor has started, so it defines a check function that prints ok or FAIL with a detail and records failures, and exits at the end according to that list. Output is one line per check, which is what you read in a CI log.'''),
    blank,
    ...code('lua', r'tests/e2e/smoke.lua · lines 4-4, 5-10', r'''
local failures = {}
...
local function check(name, ok, detail)
  io.stdout:write(("%s %s%s\n"):format(ok and "ok  " or "FAIL", name, (not ok and detail) and (": " .. tostring(detail)) or ""))
  if not ok then
    failures[#failures + 1] = name
  end
end'''),

    ...sec(r'''what lazy.nvim made'''),
    ...para(r'''--''', r'''The first block asserts the visible result of installation: the module was required, which means lazy.nvim read the dir spec, resolved main = xyno_imports and called setup; the three commands exist; the autocommand group has at least four entries (FileType, InsertLeave, BufWritePost, TextChanged); no global <leader>rI is defined; the engine module can be required; and the default mode is ask. The autocommand count is asserted as at least four rather than exactly four.'''),
    blank,
    ...code('lua', r'tests/e2e/smoke.lua · lines 12-12, 21-21', r'''
check("lazy.nvim loaded xyno_imports", package.loaded["xyno_imports"] ~= nil)
...
check("mode() default", require("xyno_imports.engine").mode() == "ask")'''),

    ...sec(r'''the help file resolves'''),
    ...para(r'''--''', r'''The help check generates tags for the doc directory with helptags and then runs :help on six tags: the main one, the API, the setup section, and the three commands. Each is in pcall, so a missing tag is a FAIL with the error text, not a crash. It is the only test that reads doc/xyno-imports.txt.'''),
    blank,
    ...code('lua', r'tests/e2e/smoke.lua · lines 23-23, 29-29', r'''
local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))))
...
vim.cmd("only")'''),

    ...sec(r'''a ranking with no server'''),
    ...para(r'''--''', r'''One check ranks two candidates through E.rank with empty facts and asserts a list of two with a score field. It proves the pure part of the engine is reachable through the installed module, without a language server or a parser. It is deliberately shallow: it shows the exports are reachable, and scoring itself is covered by engine_spec.'''),
    blank,
    ...code('lua', r'tests/e2e/smoke.lua · lines 32-35', r'''
local E = require("xyno_imports.engine")
local ranked = E.rank({ E.candidate("std::fmt::Result"), E.candidate("std::io::Result") }, {})
check("rank() returns the candidates", #ranked == 2 and ranked[1].score ~= nil)
'''),

    ...sec(r'''the missing dependency, again'''),
    ...para(r'''--''', r'''The last block repeats the init_spec case in the lazy.nvim environment. It replaces vim.notify, removes the three xyno_rust modules from package.loaded, blanks package.loaders, package.path and the runtime path, and calls setup. Then it restores all of it and checks that setup returned without error and that exactly one one-line notification was produced. Compared with the spec, the block also blanks package.path, which the comments do not explain.'''),
    blank,
    ...code('lua', r'tests/e2e/smoke.lua · lines 47-47, 62-62', r'''
local saved_path = package.path
...
check("setup() without xyno-rust: one line", #notes == 1 and not notes[1]:find("\n"), vim.inspect(notes))'''),

    ...para(r'''--''', r'''The ending is a verdict by exit code: if any check failed, cquit 1; otherwise qa!. CI treats a non-zero exit as a failed step.'''),
    blank,
    ...code('lua', r'tests/e2e/smoke.lua · lines 64-66', r'''
if #failures > 0 then
  vim.cmd("cquit 1")
end'''),

    ...sec(r'''the minimal init that goes with it'''),
    ...para(r'''--''', r'''tests/e2e/init.lua, not given its own page, is the other half. It sets the runtime path to lazy.nvim from XYNO_LAZY, then calls lazy.setup with the checkout and its dependency as dir plugins, lazy = false, main = "xyno_imports", opts = {}. It sets install.missing = false and disables the update checker and change detection, so lazy.nvim neither installs, checks for updates nor watches for changes during the run.'''),
    blank,
    ...sec(r'''limits'''),
    ...pt(r'''--''', r'''One plugin manager''', r'''lazy.nvim only, at one pinned commit. The README install block is for lazy.nvim; other managers are not tested.'''),
    ...pt(r'''--''', r'''No rust-analyzer''', r'''no buffer is opened. The flow with a server is engine_spec territory.'''),
    ...pt(r'''--''', r'''Duplicated logic''', r'''the missing-dependency block copies the spec case instead of sharing a helper, because the smoke file has no helpers and must work standing alone.'''),
    ...sec(r'''history'''),
    ...pt(r'''--''', r'''45d98cb 2026-10-22''', r'''added with tests/e2e/init.lua: 67 lines. Run in CI by 9373a52.'''),
  ],
);
