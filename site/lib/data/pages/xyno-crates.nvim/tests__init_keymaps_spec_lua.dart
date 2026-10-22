import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-crates.nvim/tests/init-keymaps_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'init-keymaps_spec.lua — keys exist where they should and nowhere else'),
    cm('--', r'two tests in a file of their own, because modules start once per process'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for keymaps = true in lua/xyno_crates/init.lua'),
    kv(r'language', r'Lua on tests/harness.lua'),
    kv(r'size', r'36 lines, 2 tests'),
    kv(r'needs', r'nothing external'),
    kv(r'history', r'added in 9d33ca7 (2026-10-22)'),
    ...sec(r'why this file exists, and why it is separate'),
    ...para('--', r'In xynovim the keys were part of the configuration: crate_add set <leader>rA buffer-locally, crate_features set <leader>rG, and the specs of the config asserted that no other global <leader>r map existed (a comment in the original crate-add spec calls it "keymaps.lua’s rule: the only global <leader>r maps are the hidden stubs"). The plugin turns that around: keys are opt-in, off by default, and when requested they are still buffer-local. This spec protects the opt-in half.'),
    blank,
    ...para('--', r'It has a file to itself because of one line in the header of tests/init_spec.lua: "the modules start once per process, so the opt-in keys are checked in init-keymaps_spec.lua". crate_add.setup and crate_features.setup guard with did_setup, and the keymap option is read on the first call only. A test that calls setup({ keymaps = true }) after another test called setup({}) would silently test nothing. The runner starts a fresh nvim per spec file, so a file of its own is the cheapest isolation.'),
    blank,
    ...code('lua', r'tests/init-keymaps_spec.lua · lines 1-8', r'''
-- xyno_crates.setup{ keymaps = true }: the default keys are buffer-local in Rust
-- files (and <leader>rA also in Cargo.toml), never global.
local H = require("xyno_crates_test.helpers")
local C = require("xyno_crates")

describe("setup with keymaps = true", function()
  it("maps the default keys in Rust buffers only", function()
    C.setup({ keymaps = true })'''),
    ...sec(r'test 1: Rust buffers get both keys, buffer-local'),
    ...code('lua', r'tests/init-keymaps_spec.lua · lines 7-25', r'''
  it("maps the default keys in Rust buffers only", function()
    C.setup({ keymaps = true })
    H.eq(C.default_keymaps.add, "<leader>rA")
    local rs = H.tmpdir() .. "/x.rs"
    vim.fn.writefile({ "fn main() {}" }, rs)
    vim.cmd.edit(vim.fn.fnameescape(rs))
    vim.bo.filetype = "rust"
    local add = H.wait_for(function()
      local m = vim.fn.maparg("<leader>rA", "n", false, true)
      return m.buffer == 1 and m
    end, 3000, "the buffer-local add key")
    H.match(add.rhs, "CrateAdd", true)
    local fix = vim.fn.maparg("<leader>rG", "n", false, true)
    H.eq(1, fix.buffer)
    H.eq("Fix missing crate feature", fix.desc)
    vim.cmd("enew")
    H.eq("", vim.fn.maparg("<leader>rA", "n"))
    H.eq("", vim.fn.maparg("<leader>rG", "n"))
  end)'''),
    ...para('--', r'The first assertion reads M.default_keymaps from the module instead of repeating the string, so the documented default and the tested default cannot drift apart; it asserts the add key is <leader>rA. Then it writes a real x.rs file in a temp directory, edits it, sets the filetype to rust, and uses H.wait_for to poll maparg until the key appears with buffer == 1. Polling is needed because the keys are installed from a FileType autocommand and, in crate_add, a vim.schedule that also covers buffers already open; the test does not assume which comes first. maparg is called with the dict flag, so the test can check the mapping’s buffer flag and not only its existence. The right-hand side must mention CrateAdd. For <leader>rG the test checks both the buffer flag and the description "Fix missing crate feature", which is the desc given in crate_features.on_rust_buffer.'),
    blank,
    ...para('--', r'The last three lines are the important ones. vim.cmd("enew") makes a fresh, non-Rust buffer current, and both maparg calls must return an empty string. A global map would have survived the buffer switch. That is how the spec proves "buffer-local" and not merely "present".'),
    blank,
    ...sec(r'test 2: Cargo.toml gets the add key'),
    ...code('lua', r'tests/init-keymaps_spec.lua · lines 27-35', r'''
  it("maps <leader>rA in a Cargo.toml too", function()
    local dir = H.tmpdir()
    vim.fn.writefile({ "[package]", 'name = "x"' }, dir .. "/Cargo.toml")
    vim.cmd.edit(vim.fn.fnameescape(dir .. "/Cargo.toml"))
    vim.bo.filetype = "toml"
    H.wait_for(function()
      return vim.fn.maparg("<leader>rA", "n", false, true).buffer == 1
    end, 3000, "the key in Cargo.toml")
  end)'''),
    ...para('--', r'A tiny Cargo.toml with a [package] table is written to a temp directory, opened, given the toml filetype, and the test waits for <leader>rA to appear with buffer == 1. This is the second of the two places the README promises: "<leader>rA (:CrateAdd, buffer-local in Rust and Cargo.toml buffers)". The code behind it is the FileType autocommand in crate_add.setup with pattern { "rust", "toml" }, which maps the key for a Rust buffer or a file whose basename is exactly Cargo.toml. The spec does not test that another .toml file is left alone; the basename check is therefore verified only by reading it.'),
    blank,
    ...sec(r'limits and observations'),
    ...pt('--', r'no assertion on <leader>rG in toml', r'the README says the fix key is for Rust buffers only; the spec checks the add key in toml but never that rG is absent there.'),
    ...pt('--', r'no table form', r'keymaps = { add = "<leader>ca", fix = false } is not exercised anywhere in the specs. The code path is short, keys.add and keys.fix read from the table, but it has no test of its own.'),
    ...pt('--', r'timing', r'the 3000 ms timeouts of H.wait_for give the scheduled mapping time to appear; the file states no further reason for the number.'),
  ],
);
