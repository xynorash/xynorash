import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/rust-context_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust-context_spec.lua — which cargo features and target you are working in'),
    cm('--', r'a state file shared by many editors, a picker, a command, two consumers, and live servers that must follow'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/rust_context.lua (:RustContext) and its two consumers in plugins/rustaceanvim.lua and plugins/bacon-ls.lua'),
    kv(r'language', r'Lua spec, 1169 lines, 53 it() blocks, 12 describe() blocks, 400 second timeout'),
    kv(r'layers', r'pure functions and the command without servers; plugin glue; live servers (rust-analyzer, and bacon-ls when Mason bacon-ls attaches)'),
    kv(r'history', r'9 commits, 2026-10-13 to 2026-10-21'),
    ...sec(r'why this file exists'),
    ...para('--', r'A Rust workspace compiles differently depending on features and target. rust-analyzer and the clippy tier must agree about them, or one will show an error the other does not. :RustContext stores the choice per workspace root (all features, selected features, no default features, a target such as wasm32-unknown-unknown), then pushes it into both tiers. The spec tests the storage, the mapping to settings and arguments, the picker, the command, and then, with servers, that the editor really changes. The header states the three layers.'),
    ...code('lua', r'tests/rust-context_spec.lua · lines 1-6', r'''
-- xyno-timeout: 400
-- config.rust_context (:RustContext, per-workspace cargo features/target) and
-- its two consumers, plugins/rustaceanvim.lua (server.settings) and
-- plugins/bacon-ls.lua (before_init). The pure part and the picker/command
-- part run without servers; the "live" part needs rust-analyzer + cargo
-- (bacon-ls assertions are made when Mason's bacon-ls attaches).'''),
    ...sec(r'the root of a workspace'),
    ...para('--', r'root walks up to the outermost Cargo.toml with a [workspace] table, falls back to the nearest Cargo.toml for a plain crate, treats an excluded crate and one with its own [workspace] as their own roots (it asks cargo locate-project), defaults to the current buffer, and returns nil outside any crate. One test sanitises a hand-edited state file with wrong types so show, ra_cargo and bacon_args do not raise.'),
    ...sec(r'the state file survives eight editors'),
    ...para('--', r'The state is a JSON file under stdpath state. Several nvim processes can apply a context at the same time, and a naive read-modify-write loses entries. The test starts eight headless nvim workers, each applying fifteen contexts for different roots, waits for all of them, and requires 120 entries in the file and no lock file left. The title records the field result: without the lock, only 79 of 160 applies survived. Note that the environment of the workers points every XDG directory and LOCALAPPDATA to a temp dir, so the test never touches the real state.'),
    ...code('lua', r'tests/rust-context_spec.lua · lines 280-317', r'''
    it("concurrent nvims applying different roots lose none (8 x 15 applies; was 79 of 160 without the lock)", function()
      local state = H.tmpdir()
      local script = H.tmpdir() .. "/many.lua"
      write_text(
        script,
        ([[
package.path = %q .. "/lua/?.lua;" .. package.path
local rc = require("config.rust_context")
local id = tonumber(arg[1])
for i = 1, 15 do
  rc.apply(("/proj/%%d/%%d"):format(id, i), { all = false, features = { "f" .. i }, no_default = false })
end
]]):format(H.repo)
      )
      local jobs = {}
      for id = 1, 8 do
        jobs[id] = vim.system({ vim.fn.exepath("nvim"), "--headless", "-u", "NONE", "-l", script, tostring(id) }, {
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
    end)'''),
    ...sec(r'the write is atomic'),
    ...para('--', r'The file is written to a temporary name and renamed over the target. The test wraps fs_rename, applies a context and requires exactly one rename whose target is the state file and whose source matches rust-context.json.<pid>.tmp, which no longer exists afterwards. A reader can never see a truncated file. A corrupt or missing file reads as empty and is overwritten on the next apply; write_all creates the missing parent directory.'),
    ...code('lua', r'tests/rust-context_spec.lua · lines 327-344', r'''
    it("is written aside and renamed (no truncated file for a reader, no leftover temp file)", function()
      notes()
      local seen_tmp = {}
      local orig = vim.uv.fs_rename
      vim.uv.fs_rename = function(from, to)
        seen_tmp[#seen_tmp + 1] = { from, to }
        return orig(from, to)
      end
      on_undo(function()
        vim.uv.fs_rename = orig
      end)
      rc.apply("/r/one", { all = true, features = {} })
      H.eq(1, #seen_tmp)
      H.eq(state_file, seen_tmp[1][2])
      H.match(seen_tmp[1][1], "rust%-context%.json%.%d+%.tmp$")
      H.eq(0, vim.fn.filereadable(seen_tmp[1][1]))
      H.eq({ ["/r/one"] = { all = true, features = {} } }, state())
    end)'''),
    ...sec(r'from context to settings'),
    ...para('--', r'ra_cargo maps all = true to allFeatures with an empty feature list (the list is ignored when all is on), an explicit feature list and the target to the cargo settings, and is nil without a context. cargo_flags defaults to --all-features and handles all, target, feature lists and no-default. bacon_args are --workspace, then the context flags, then --no-deps and --keep-going, in that order, and calling it twice gives the same answer, which proves that no shared table is mutated.'),
    ...code('lua', r'tests/rust-context_spec.lua · lines 431-435, 480-493', r'''
    it("maps all=true to allFeatures with an empty feature list", function()
      H.eq({ allFeatures = true, noDefaultFeatures = false, features = {} }, rc.ra_cargo({ all = true }))
      -- the list is ignored when all is on
      H.eq({}, rc.ra_cargo({ all = true, features = { "a" } }).features)
    end)
...
    it("is --workspace, the context flags, --no-deps in that order", function()
      local ctx = { no_default = true, features = { "ssr" }, target = "t" }
      H.eq(
        vim.list_extend(vim.list_extend({ "--workspace" }, rc.cargo_flags(ctx)), { "--no-deps", "--keep-going" }),
        rc.bacon_args(ctx)
      )
      H.eq(
        { "--workspace", "--no-default-features", "--features", "ssr", "--target", "t", "--no-deps", "--keep-going" },
        rc.bacon_args(ctx)
      )
      -- calling twice gives the same answer (no shared table mutated)
      H.eq({ "--workspace", "--all-features", "--no-deps", "--keep-going" }, rc.bacon_args(nil))
      H.eq({ "--workspace", "--all-features", "--no-deps", "--keep-going" }, rc.bacon_args(nil))
    end)'''),
    ...sec(r'the command and the picker'),
    ...para('--', r':RustContext takes an optional argument, completes show and reset, show notifies the stored context or the default, reset forgets the choice of that workspace only and warns outside a crate, and any other argument warns with the usage. The picker reads cargo metadata --no-deps in the root with a 30 second wait, notifies an ERROR when cargo fails, lists the special entries and then pkg/feature entries for a multi-package workspace (single-package crates have no prefix and sorted features), shows the stored context in the title, offers (host default) plus the installed rustup targets, and choosing the host target clears the stored one. Cancelling changes nothing and changing only the features keeps the current target.'),
    ...sec(r'the consumers'),
    ...para('--', r'rustaceanvim server.settings layers ra_cargo(ctx) over the default settings and tolerates a missing root; the bacon_ls before_init rebuilds its init options and settings from bacon_args(ctx), and its root is the workspace root, from a member, and none for non-crates.'),
    ...sec(r'live servers'),
    ...para('--', r'The live block opens the core crate of the workspace fixture, whose lib.rs holds a compile_error! that fires when mutually exclusive features are on; the helper conflict looks for a diagnostic from a given source containing mutually exclusive. The default context (all features) must show the error in both tiers. Selecting only ssr must remove the error in both tiers, rust-analyzer within 60 seconds, bacon-ls after restarting with exactly --workspace --features ssr --no-deps --keep-going; applying nil must bring the error back and the arguments back to --workspace --all-features --no-deps --keep-going. The bacon-ls half runs only when Mason bacon-ls attached. The other live tests: apply updates the matching clients, reloads and notifies; resetting returns running clients to all features; applying for a second workspace reaches the shared rust-analyzer client; a stored choice is applied on a fresh server start; and choosing wasm32-unknown-unknown sets cargo.target live and in the state file, and reset clears both.'),
    ...code('lua', r'tests/rust-context_spec.lua · lines 1041-1074', r'''
  it("selecting only ssr removes the error in both tiers, reset brings it back", function()
    H.known_issue({ "windows" }, "live servers need bacon_ls / rust-analyzer (windows-latest run 39647013043); the state-file sanitising failure is not diagnosed")
    local s = live()
    H.wait_for(function()
      return conflict(s.buf, "rust-analyzer") and (not s.bacon or conflict(s.buf, "bacon-ls"))
    end, 90000, "the compile_error in both tiers before the change")
    notes()

    rc.apply(s.root, { all = false, no_default = false, features = { "ssr" } })
    H.wait_for(function()
      return not conflict(s.buf, "rust-analyzer")
    end, 60000, "rust-analyzer's error to disappear with only ssr")
    if s.bacon then
      H.wait_for(function()
        return vim.deep_equal(bacon_args(), { "--workspace", "--features", "ssr", "--no-deps", "--keep-going" })
      end, 30000, "bacon_ls restarted with '--workspace --features ssr --no-deps'")
      H.wait_for(function()
        return not conflict(s.buf, "bacon-ls")
      end, 60000, "bacon-ls's error to disappear with only ssr")
    end

    rc.apply(s.root, nil)
    H.wait_for(function()
      return conflict(s.buf, "rust-analyzer")
    end, 60000, "rust-analyzer's error to come back after reset")
    if s.bacon then
      H.wait_for(function()
        return vim.deep_equal(bacon_args(), { "--workspace", "--all-features", "--no-deps", "--keep-going" })
      end, 30000, "bacon_ls restarted without the stale --features args")
      H.wait_for(function()
        return conflict(s.buf, "bacon-ls")
      end, 60000, "bacon-ls's error to come back after reset")
    end
  end)'''),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created.'),
    ...pt('--', r'98c9bb4, a3d33c8, 3f868dd, f31e013, 25086fd (2026-10-13 and 2026-10-14)', r'field test rounds, the lock among them (RustContext lock is named in 25086fd).'),
    ...pt('--', r'9641d08, 6524272, d3e1442 (2026-10-16 and 2026-10-21)', r'Windows and macOS: drive letters, .exe suffixes, path spelling. The live test is a known issue on Windows with the run number in its reason.'),
  ],
);
