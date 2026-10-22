import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/tests/rust-context_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'tests/rust-context_spec.lua — one choice of features and target, shared by every tool'),
    cm('--', r'root discovery, the state file under concurrency, flag builders, the picker, live servers'),
    cm('--', r'──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/xyno_rust/rust_context.lua (381 lines)'),
    kv(r'language', r'Lua, run by tests/run.lua'),
    kv(r'size', r'1027 lines, 49 tests; the last block (7 tests) needs rust-analyzer and cargo'),
    kv(r'real', r'cargo locate-project, cargo metadata, 8 child Neovim processes, rust-analyzer in the live block'),
    kv(r'faked', r'Snacks.picker, vim.ui.select, vim.system for rustup and cargo, vim.cmd, vim.notify'),
    kv(r'fixtures', r'tests/fixtures/workspace (core-lib with ssr and csr, app), tests/fixtures/basic'),
    kv(r'origin', r'xynovim tests/rust-context_spec.lua, 2026-10-13 (b2fee5c)'),
    ...sec(r'why this file exists'),
    ...para('--', r'Two servers analyse a Rust project at once: rust-analyzer and bacon-ls (the clippy tier). '
        r'If they disagree about which Cargo features are on, a crate with mutually exclusive '
        r'features gets bogus errors from one of them. rust_context.lua is the place where the '
        r'choice lives: per workspace root, features and target, stored in a JSON file, pushed into '
        r'running rust-analyzer clients, passed to bacon-ls as arguments, and appended to the cargo '
        r'commands the plugin runs itself (targets, tools, doctests).'),
    ...para('--', r'Because the choice is shared by so many consumers, a small error spreads. The root of a '
        r'workspace decides which entry is read; the state file is shared between all running '
        r'Neovim instances; the flag builders decide what every cargo command looks like; the apply '
        r'function decides which servers are told. The spec has a block for each of those.'),
    ...para('--', r'The fixture that makes the whole thing concrete is core-lib in tests/fixtures/workspace. '
        r'It declares ssr and csr features and carries a line that refuses to build when both are '
        r'on.'),
    ...code('lua', r'tests/fixtures/workspace/core/src/lib.rs · lines 1-2', r'''
#[cfg(all(feature = "ssr", feature = "csr"))]
compile_error!("features `ssr` and `csr` are mutually exclusive");
'''),
    ...para('--', r'With the default (all features) rust-analyzer reports that error. With only ssr it does '
        r'not. The live block of the spec watches that difference appear and disappear.'),
    ...sec(r'the module’s entry points'),
    ...code('lua', r'lua/xyno_rust/rust_context.lua · lines 108-127', r'''
local function sanitize(ctx)
  if type(ctx) ~= "table" then
    return nil
  end
  local out = vim.deepcopy(ctx)
  for _, k in ipairs({ "all", "no_default" }) do
    if type(out[k]) ~= "boolean" then
      out[k] = nil
    end
  end
  if type(out.features) == "table" then
    out.features = vim.tbl_filter(function(f)
      return type(f) == "string" and f ~= ""
    end, vim.islist(out.features) and out.features or {})
  else
    out.features = nil
  end
  if type(out.target) ~= "string" or out.target == "" then
    out.target = nil
  end
'''),
    ...para('--', r'The two pure builders are the heart of the contract. cargo_flags maps a context to '
        r'arguments (nil or all means --all-features; otherwise --no-default-features, then '
        r'--features a,b; then --target) and ra_cargo maps the same context to the settings table '
        r'of rust-analyzer. apply (not shown here) stores, updates the clients that serve the root, '
        r'schedules a reload and restarts bacon-ls.'),
    ...sec(r'the preamble: seven stub helpers'),
    ...code('lua', r'tests/rust-context_spec.lua · lines 33-60', r'''
--- Cleanups of stubs installed by a test, run (reverse order) by after_each.
local undo = {}
local function on_undo(fn)
  undo[#undo + 1] = fn
end

local function notes()
  local cap = H.capture_notify()
  on_undo(cap.restore)
  return cap
end

--- Make a named scratch buffer current (M.root() with no argument reads its name).
local function buf_named(path)
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(b)
  vim.api.nvim_buf_set_name(b, path)
  return b
end

--- A crate directory with the given Cargo.toml text (+ an empty src/lib.rs).
local function crate(toml)
  local dir = H.tmpdir()
  write_text(dir .. "/Cargo.toml", toml)
  write_text(dir .. "/src/lib.rs", "")
  return dir
end

'''),
    ...para('--', r'The spec starts with a long list of helpers. They share one idea: every replacement '
        r'registers an undo closure, and reset_world, called from after_each, runs them in reverse, '
        r'stops all LSP clients, wipes buffers and deletes the state file. A test can break '
        r'anything without affecting the next.'),
    ...pt('--', r'stub_system', r'replaces vim.system for chosen executables only (cargo, rustup) and records every call '
        r'with its wait argument, so a test can assert that the command was cargo metadata '
        r'--format-version 1 --no-deps, run in the root, with a 30000 ms wait. Other commands go to '
        r'the real function.'),
    ...pt('--', r'stub_picker', r'replaces Snacks.picker with a callable table that records the options and still forwards '
        r'field reads to the original, because snacks reads fields of the picker function.'),
    ...pt('--', r'fake_picker', r'the object that confirm receives: selected() returns the items whose text was named, '
        r'close() records that it was called.'),
    ...pt('--', r'record_cmd', r'replaces vim.cmd by a recorder so that RustLsp reloadWorkspace and lsp restart bacon_ls '
        r'can be observed without a rust-analyzer or bacon-ls.'),
    ...sec(r'root: which Cargo.toml is the project'),
    ...code('lua', r'tests/rust-context_spec.lua · lines 189-206', r'''
    it("walks up to the outermost Cargo.toml with [workspace], from a member crate", function()
      local ws = H.fixture("workspace")
      H.eq(ws, rc.root(ws .. "/app/src/main.rs"))
      H.eq(ws, rc.root(ws .. "/core/src/lib.rs"))
      -- a nested crate with its own [workspace] is its own root when cargo
      -- says so (see the excluded-crate test); without cargo the text walk
      -- takes the outermost [workspace]
      local outer = crate('[workspace]\nmembers = ["inner"]\n')
      write_text(outer .. "/inner/Cargo.toml", '[package]\nname = "inner"\n[workspace]\n')
      write_text(outer .. "/inner/src/lib.rs", "")
      H.eq(vim.fn.executable("cargo") == 1 and (outer .. "/inner") or outer, rc.root(outer .. "/inner/src/lib.rs"))
      -- a plain package above a workspace is not the root; [workspace.xxx] tables count
      local plain = crate('[package]\nname = "plain"\n')
      write_text(plain .. "/mid/Cargo.toml", "[workspace.package]\nedition = '2021'\n")
      write_text(plain .. "/mid/leaf/Cargo.toml", '[package]\nname = "leaf"\n')
      H.eq(plain .. "/mid", rc.root(plain .. "/mid/leaf/src/lib.rs"))
    end)

'''),
    ...para('--', r'The first test lists the rules. From a member crate the root is the workspace directory. '
        r'A nested crate with its own [workspace] is its own root when cargo says so, and when '
        r'cargo is not there the text walk takes the outermost manifest that mentions [workspace]; '
        r'the expected value switches on vim.fn.executable("cargo"). A plain package above a '
        r'workspace is not a root, and a [workspace.package] table counts as a workspace marker.'),
    ...code('lua', r'tests/rust-context_spec.lua · lines 237-246', r'''
    it("an excluded crate and one with its own [workspace] are their own root (cargo locate-project)", function()
      if vim.fn.executable("cargo") ~= 1 then
        return H.skip_file("cargo not found")
      end
      local ws = H.tmpdir()
      write_text(ws .. "/Cargo.toml", '[workspace]\nmembers = ["a"]\nexclude = ["ex", "nested"]\n')
      write_text(ws .. "/a/Cargo.toml", '[package]\nname = "a"\nversion = "0.1.0"\nedition = "2021"\n')
      write_text(ws .. "/ex/Cargo.toml", '[package]\nname = "ex"\nversion = "0.1.0"\nedition = "2021"\n')
      write_text(ws .. "/nested/Cargo.toml", '[package]\nname = "nested"\nversion = "0.1.0"\nedition = "2021"\n[workspace]\n')
      for _, d in ipairs({ "a", "ex", "nested" }) do
'''),
    ...para('--', r'The next test is the reason the module calls cargo at all. In a workspace with members = '
        r'["a"] and exclude = ["ex", "nested"], an excluded crate is not part of the parent’s '
        r'workspace and a crate with its own [workspace] is not either: cargo locate-project '
        r'--workspace says so, a plain text walk cannot. The test also edits the manifest and bumps '
        r'its mtime by five seconds with fs_utime, to prove the cached answer follows the edit: the '
        r'cache key is the mtime of the manifests. Without that bump the filesystem timestamp '
        r'resolution could make the test flaky, which is why it is explicit.'),
    ...para('--', r'Smaller tests pin the rest: a plain crate falls back to the nearest manifest, no argument '
        r'means the current buffer, and a path outside any crate gives nil.'),
    ...sec(r'the state file'),
    ...code('lua', r'tests/rust-context_spec.lua · lines 279-290,296-315', r'''
    it("concurrent nvims applying different roots lose none (8 x 15 applies; was 79 of 160 without the lock)", function()
      local state = H.tmpdir()
      local script = H.tmpdir() .. "/many.lua"
      write_text(
        script,
        ([[
package.path = %q .. "/lua/?.lua;" .. package.path
local rc = require("xyno_rust.rust_context")
local id = tonumber(arg[1])
for i = 1, 15 do
  rc.apply(("/proj/%%d/%%d"):format(id, i), { all = false, features = { "f" .. i }, no_default = false })
end
...
          env = {
            XDG_STATE_HOME = state,
            XDG_CONFIG_HOME = state,
            XDG_DATA_HOME = state,
            XDG_CACHE_HOME = state,
            LOCALAPPDATA = state, -- Windows: stdpath("state") is $LOCALAPPDATA/nvim-data
          },
          text = true,
        })
      end
      for id, j in ipairs(jobs) do
        local r = j:wait(60000)
        H.eq(0, r.code, "worker " .. id .. ": " .. tostring(r.stderr))
      end
      local dir = state .. (vim.fn.has("win32") == 1 and "/nvim-data" or "/nvim")
      local f = assert(io.open(dir .. "/rust-context.json"))
      local all = vim.json.decode(f:read("*a"))
      f:close()
      H.eq(120, vim.tbl_count(all), "every worker's keys are in the file")
      H.eq(0, vim.fn.filereadable(dir .. "/rust-context.json.lock"), "lock released")
'''),
    ...para('--', r'The first test of the group has the best title of the file. It starts eight headless '
        r'Neovim processes (nvim --headless -u NONE -l script), each applying fifteen contexts for '
        r'its own roots, with every XDG directory pointed at one temporary state directory. When '
        r'all have exited the file must hold 120 keys and the lock file must be gone. The title '
        r'says that without the lock only 79 of 160 survived. The figure comes from the module comment, which counts 8 nvims x 20 applies and 160 keys. The test itself '
        r'applies 15 per worker, which is why it expects 120.'),
    ...para('--', r'The cause is the read-modify-write cycle. Two processes read the old file, each adds its '
        r'key and the later rename wipes the other’s. The module takes a lock by creating a file '
        r'with the "wx" flag, retries for up to about two seconds, and treats a lock older than '
        r'five seconds as the leftover of a dead owner. In xynovim the lock first appears in a3d33c8 (2026-10-13), whose subject lists “rust-context lock”.'),
    ...para('--', r'Three small tests describe the file. It is keyed by root, under stdpath("state") as '
        r'rust-context.json. It is written aside and renamed: the test wraps vim.uv.fs_rename, '
        r'applies once and asserts exactly one rename, from a name matching '
        r'rust-context.json.<pid>.tmp to the state file, with no temporary left behind. That is the '
        r'fsutil.rename call, seen from the caller’s side.'),
    ...para('--', r'Robustness. An absent file reads as empty. So does anything that is not a table: {not '
        r'json, an empty file, 42, "str", null and true all give nil from get, never an error. A '
        r'JSON array is a table but holds no roots. A half-written file does not raise and is '
        r'overwritten by the next apply.'),
    ...para('--', r'The sanitising test belongs here too. A hand-edited file with {"features":5,"target":[]} '
        r'used to make describe() and ra_cargo() raise. Now get drops the fields of the wrong type '
        r'and keeps the rest: features filtered to non-empty strings, target kept only as a '
        r'non-empty string, booleans only as booleans. The assertion also checks that describe, '
        r'ra_cargo and bacon_args do not raise on what remains. This test is marked as a known '
        r'issue on Windows, with the reason that it failed in the xynovim CI and was not diagnosed.'),
    ...para('--', r'The directory test replaces vim.fn.stdpath, reloads the module so it picks up the new '
        r'state directory, and checks that apply creates the missing parents. The module is '
        r'restored in package.loaded afterwards, even if the assertions fail.'),
    ...sec(r'the pure builders'),
    ...para('--', r'The groups ra_cargo, cargo_flags, bacon_args and describe are short tables of input and '
        r'output. In words:'),
    ...pt('--', r'ra_cargo', r'nil without a context; all = true gives allFeatures = true with an empty feature list; an '
        r'explicit list is passed through with the target.'),
    ...pt('--', r'cargo_flags', r'the default is --all-features. A context with no_default and a feature list gives '
        r'--no-default-features --features a,b, then --target. An empty feature list adds nothing.'),
    ...pt('--', r'bacon_args', r'--workspace, the context flags, then --no-deps --keep-going, in that order. The module '
        r'comment says it replaces a hard-coded --all-features.'),
    ...pt('--', r'describe', r'all features, host target for the default; features: ssr,csr | target: '
        r'wasm32-unknown-unknown for a stored one; no default is mentioned when set.'),
    ...para('--', r'These strings are what the user reads in notifications and picker titles, so they are '
        r'compared literally. tests/rust-tasks-tools_spec.lua relies on the same strings.'),
    ...sec(r'apply without servers'),
    ...code('lua', r'tests/rust-context_spec.lua · lines 516-528', r'''
  describe("apply without servers", function()
    it("writes the state, schedules RustLsp reloadWorkspace and notifies", function()
      local cap = notes()
      local log = record_cmd()
      local ctx = { all = false, no_default = false, features = { "ssr", "csr" }, target = "t" }
      rc.apply("/r/one", ctx)
      H.eq({ ["/r/one"] = ctx }, state())
      H.eq({ { msg = "Rust context: features: ssr,csr | target: t", level = nil } }, cap.list)
      H.wait_for(function()
        return vim.tbl_contains(log, "RustLsp reloadWorkspace")
      end, 2000, "RustLsp reloadWorkspace")
      H.not_ok(vim.tbl_contains(log, "lsp restart bacon_ls"), "no bacon_ls client: no restart")
    end)
'''),
    ...para('--', r'With no LSP clients at all, apply still writes the state, still schedules RustLsp '
        r'reloadWorkspace (observed through the recorded vim.cmd), and notifies with Rust context: '
        r'features: ssr,csr | target: t. A call with nil forgets that root’s entry and reports the '
        r'default, all features, host target, and the other roots stay in the file. No bacon_ls '
        r'client exists here, so no restart is logged.'),
    ...sec(r'the command and the picker'),
    ...para('--', r':RustContext takes an optional argument and completes to show and reset. Further tests: '
        r'show prints the stored context or the default; reset forgets the choice of the current '
        r'workspace only and warns outside a crate; any other argument warns with the usage; the '
        r'bare command still opens the picker. Outside a crate the picker warns no Cargo.toml found.'),
    ...para('--', r'The picker calls cargo metadata --no-deps once in the root with a 30 second wait. The '
        r'test lets the stub answer an empty package list and checks the argument vector, the cwd '
        r'and the wait. The comment notes that root() may also ask cargo locate-project, which is '
        r'filtered out.'),
    ...para('--', r'The list for a multi-package workspace is the three special entries (all features, '
        r'default features only, no-default-features) followed by pkg/feature items sorted, so '
        r'core-lib/csr and core-lib/ssr. A single-package crate gets plain feature names, sorted, '
        r'without the default. The title contains the stored context after "now:".'),
    ...para('--', r'The multi-select and the target step. Confirming with core-lib/ssr and * '
        r'no-default-features selected closes the picker, asks rustup target list --installed, and '
        r'offers (host default) first, then the installed targets, with the prompt Target '
        r'(currently host). Nothing is applied until a target is chosen; choosing one stores the '
        r'context. Further tests: the host default clears a stored target, cancelling changes '
        r'nothing, and the picker preselects the current target when only the features change.'),
    ...sec(r'live servers'),
    ...para('--', r'The last block starts a real rust-analyzer on the workspace fixture. stop_all_clients '
        r'runs first because, as the comment says, a client of a previous test that is still '
        r'shutting down must not be picked up.'),
    ...para('--', r'The first live test is the one that proves apply reaches the right clients and only them. '
        r'A second rust-analyzer is started by hand for the basic fixture, and the first one is '
        r'given a stale target. After applying, the first client’s cargo settings are allFeatures '
        r'false, noDefaultFeatures true, features csr, no target, while an unrelated setting '
        r'(targetDir) survives and the other client is untouched.'),
    ...para('--', r'The end-to-end behaviour. With the default context the compile_error from core-lib '
        r'appears in rust-analyzer’s diagnostics. Applying only ssr removes it, resetting brings it '
        r'back. Each wait allows 60 to 90 seconds because indexing is slow.'),
    ...code('lua', r'tests/rust-context_spec.lua · lines 950-962', r'''
  it("apply for a second workspace reaches the shared rust-analyzer client", function()
    notes()
    local first, second = crate('[package]\nname = "first"\n'), crate('[package]\nname = "second"\n')
    local sent = {}
    local fake = {
      name = "rust-analyzer",
      config = { root_dir = first },
      workspace_folders = { { name = first, uri = vim.uri_from_fname(first) }, { name = second, uri = vim.uri_from_fname(second) } },
      settings = { ["rust-analyzer"] = { cargo = { allFeatures = true } } },
      notify = function(_, method)
        sent[#sent + 1] = method
      end,
    }
'''),
    ...para('--', r'One test needs no real server. rustaceanvim attaches every further workspace to the one '
        r'running rust-analyzer as a workspace folder, while its root_dir stays the first. The fake '
        r'client has the first root as root_dir and both as folders; applying for the second must '
        r'still reach it, with exactly one workspace/didChangeConfiguration.'),
    ...para('--', r'A stored choice is what a fresh start gets, and the wasm32 test checks target set live '
        r'and in the file, then cleared by reset. It skips unless rustup and the '
        r'wasm32-unknown-unknown target are installed, and says which command installs it.'),
    ...sec(r'what is skipped and why'),
    ...para('--', r'Five live tests call H.known_issue for Windows with the reason live rust-analyzer flows '
        r'fail or hang on Windows in the xynovim CI; not diagnosed, and the sanitising test has a '
        r'known issue of its own. The README says the same. So everything in this file except the '
        r'live block is expected to pass on Windows, and the live block is not claimed to work '
        r'there. On macOS nothing here has run in this repository.'),
    ...sec(r'gaps'),
    ...para('--', r'The bacon_ls restart after apply is only checked as absent (no client). The positive path '
        r'needs a real or fake bacon_ls client and is not in this file.'),
    ...para('--', r'The lock’s five-second stale rule is not tested; only the happy path under contention is.'),
    ...para('--', r'The Windows branch of canon (backslashes, \\?\ prefixes, drive-letter case) has no test here.'),
    ...sec(r'history'),
    ...pt('--', r'be73b6c, 2026-10-12', r'xynovim: rust_context in the commit Rust workflow robustness (bacon-ls workspace root, '
        r'server supervision).'),
    ...pt('--', r'b2fee5c, 2026-10-13', r'the spec is born with the 22-spec suite.'),
    ...pt('--', r'98c9bb4, 2026-10-13', r'root discovery asks cargo locate-project (the excluded-crate test).'),
    ...pt('--', r'a3d33c8, 2026-10-13', r'the lock around the state file (the concurrency test).'),
    ...pt('--', r'f31e013 and 25086fd, 2026-10-14', r'RustContext arguments (show, reset) and the sanitising of hand-edited state.'),
    ...pt('--', r'9641d08, 6524272 and d3e1442, 2026-10-16 and 2026-10-21', r'Windows and macOS runs: canonical root keys, drive-letter case, the known-issue skips.'),
    ...pt('--', r'7c1d2d9, 2026-10-22', r'this repository: namespace, fake_snacks, setup().'),
  ],
);
