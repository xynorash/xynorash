import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-new.nvim/tests/e2e/smoke.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'tests/e2e/smoke.lua — does it install the way the README says?'),
    cm('--', r'lazy.nvim loads the plugin; every command, a help tag, and one real RustNewBin'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'end-to-end check through a real plugin manager'),
    kv(r'language', r'Lua, 62 lines, run with luafile after tests/e2e/init.lua'),
    kv(r'needs', r'XYNO_LAZY, XYNO_RUST; cargo for the last check'),
    kv(r'output', r'ok / FAIL lines, exit 1 on any failure'),
    ...sec(r'why this file exists'),
    ...para('--', r'The spec suite loads the plugin with a hand-made runtimepath. That proves the code, not the installation. This file is the other half: lazy.nvim is the plugin manager, tests/e2e/init.lua gives it two specs (the dependency by dir, the plugin with dependencies = { "xyno-rust.nvim" }, lazy = false and main = "xyno_new"), and then this script asks what a user would ask in the first minute.'),
    ...sec(r'what it checks'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 1-18', r'''
-- End-to-end smoke test (see tests/e2e/init.lua): lazy.nvim loaded the plugin and its
-- dependency, setup() ran, every documented command exists, :help xyno-new resolves, and
-- a binary, a library and a workspace are made in a scratch directory (cargo, offline).
local failures = {}
local function check(name, ok, detail)
  io.stdout:write(("%s %s%s\n"):format(ok and "ok  " or "FAIL", name, (not ok and detail) and (": " .. tostring(detail)) or ""))
  if not ok then
    failures[#failures + 1] = name
  end
end

check("lazy.nvim loaded xyno_new", package.loaded["xyno_new"] ~= nil)
check("lazy.nvim made xyno_rust available", (pcall(require, "xyno_rust.rust_context")))
for _, c in ipairs({ "RustNewBin", "RustNewLib", "RustNewWorkspace", "RustNewMember", "EguiNew" }) do
  check("command :" .. c, vim.fn.exists(":" .. c) == 2)
end
check("no global keymap by default", vim.fn.maparg("<leader>rnb", "n") == "")
for _, m in ipairs({ "rust", "egui", "dashboard" }) do'''),
    ...para('--', r'The first lines define check, which prints ok or FAIL with a detail and records failures. The assertions after it, in order: lazy.nvim loaded xyno_new, so package.loaded has it; the dependency is reachable, via pcall(require, "xyno_rust.rust_context"); each of the five commands exists, exists(":Name") == 2; no global keymap was set by default; the three modules rust, egui and dashboard can be required; and dashboard_keys, given a list holding only a Quit entry, returns five entries with Quit last.'),
    ...sec(r'help tags'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 24-30', r'''
local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))))
vim.cmd("helptags " .. vim.fn.fnameescape(repo .. "/doc"))
for _, tag in ipairs({ "xyno-new", "xyno-new-setup", "xyno-new-api", ":RustNewBin", ":RustNewLib", ":RustNewWorkspace", ":RustNewMember", ":EguiNew", "xyno_new.dashboard_keys()" }) do
  local ok, err = pcall(vim.cmd, "help " .. tag)
  check(":help " .. tag, ok, err)
end
vim.cmd("only")'''),
    ...para('--', r'The plugin ships doc/xyno-new.txt but the tags file doc/tags is generated, so the smoke test regenerates it with :helptags and then runs :help on nine tags, from xyno-new to xyno_new.dashboard_keys(). A broken *tag* line in the help file, or a tag referenced from the README that does not exist, fails here. The repo path is derived from the script’s own location, three directories up. The final vim.cmd("only") closes the help window so the later steps run in a normal layout.'),
    ...sec(r'one real command'),
    ...code('lua', r'tests/e2e/smoke.lua · lines 32-50', r'''
if vim.fn.executable("cargo") == 1 then
  local parent = vim.fn.tempname()
  vim.fn.mkdir(parent, "p")
  vim.g.xyno_new_projects_dir = parent
  local answers = { "smoke-bin", parent }
  local orig_input = vim.ui.input
  vim.ui.input = function(opts, cb)
    cb(table.remove(answers, 1))
  end
  local orig_notify = vim.notify
  local notes = {}
  vim.notify = function(msg)
    notes[#notes + 1] = msg
  end
  vim.cmd("RustNewBin")
  local ok = vim.wait(60000, function()
    return vim.uv.fs_stat(parent .. "/smoke-bin/src/main.rs") ~= nil and vim.fn.expand("%:t") == "main.rs"
  end, 50)
  check(":RustNewBin creates and opens a binary", ok, table.concat(notes, " | "))'''),
    ...code('lua', r'tests/e2e/smoke.lua · lines 51-54', r'''
  vim.ui.input = orig_input
  vim.notify = orig_notify
  vim.cmd("cd /")
  vim.fn.delete(parent, "rf")'''),
    ...para('--', r'The test creates a scratch directory, points projects_dir at it, replaces vim.ui.input so that the two prompts get the answers smoke-bin and the scratch directory, silences notifications into a list, and runs :RustNewBin. Then it waits up to 60 seconds for src/main.rs to exist and the current buffer to be main.rs: the command is asynchronous, so the check is a poll, not a sleep. The collected notifications are printed as the failure detail. Afterwards the stubs are restored, the directory is left and deleted. Without cargo, the check is replaced by a line saying it was skipped.'),
    ...sec(r'the init file behind it'),
    ...code('lua', r'tests/e2e/init.lua · lines 8-17, 19-26', r'''
require("lazy").setup({
  {
    dir = assert(vim.env.XYNO_RUST, "XYNO_RUST not set"),
    name = "xyno-rust.nvim",
    lazy = true,
  },
  {
    dir = repo,
    name = "xyno-new.nvim",
    dependencies = { "xyno-rust.nvim" },
...
    opts = {},
    main = "xyno_new",
  },
}, {
  install = { missing = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
  performance = { reset_packpath = false, rtp = { reset = false } },'''),
    ...para('--', r'The init file is short enough to read here. lazy.nvim is put on the runtimepath from XYNO_LAZY, then given two specs. The dependency is lazy = true with dir = the XYNO_RUST checkout, a name, and no code of its own; the plugin is lazy = false, so it loads at startup, with opts = {} and main = "xyno_new", which tells lazy.nvim to call require("xyno_new").setup({}). Because the repository directory is passed as dir, lazy.nvim does not clone anything.'),
    ...para('--', r'The options set install.missing = false, the update checker and change detection are disabled, and performance.reset_packpath and rtp.reset are false. The file gives no reasons for these settings.'),
    ...sec(r'reading the output'),
    ...para('--', r'A passing run prints a line per check, in order: the lazy.nvim and dependency checks, five command lines, the keymap check, three module lines, the dashboard line, nine :help lines and the RustNewBin line. A failure prints FAIL with a detail and the process exits with code 1 through cquit; a pass leaves with qa!. Because the output is ordinary text, the CI log shows exactly which expectation broke.'),
    ...sec(r'a comment that says more than the code does'),
    ...para('--', r'The comment at the top of the file says a binary, a library and a workspace are made in a scratch directory. The code creates only the binary. The README and CI run the file as written, so the claim in the comment is stronger than what is tested; the library and workspace flows are covered by rust-new_spec.lua instead. It is a stale comment, not a missing test, but it is worth knowing when you read the output.'),
    ...sec(r'history'),
    ...para('--', r'Added in 1de2687 on 2026-10-22. It runs as the second step of the CI job after the specs.'),
  ],
);
