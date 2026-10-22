import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/lua/xyno_rust/rust_tasks.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust_tasks.lua - run, test, bench, profile and audit from a picker'),
    cm('--', r'every command carries the features and target of the Cargo context'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'targets picker, workspace tools picker, :RustNew, :ActJob, doctests'),
    kv(r'language', r'Lua'),
    kv(r'size', r'277 lines; ancestors in xynovim: wip-s8c (025f7a6) and wip-s9a (81e0650), 2026-10-09'),
    kv(r'commands', r':RustTargets :RustTools :RustNew :ActJob (and the doctests function)'),
    kv(r'tested by', r'tests/rust-tasks-tools_spec.lua (757 lines)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The header says it: a Cargo targets picker inspired by the Cargo tool window and run configurations of the JetBrains IDEs, minimal, plus a project scaffold command, honouring the :RustContext choice. For a Rust developer the daily need is small and repetitive: run this binary, run the tests of this crate, profile that one, check the licences before a release. Each is a cargo invocation whose arguments depend on the package, the target kind and the features in force. This module builds those argv lists from cargo metadata and hands them to a terminal that stays open.'),
    ...sec(r'a terminal that does not eat the output'),
    ...code('lua', r'lua/xyno_rust/rust_tasks.lua · lines 27-46', r'''
--- Run in a bottom terminal that stays open after exit 0 (Snacks closes it
--- by default and the output is gone). A rerun replaces the previous one:
--- Snacks.terminal would just toggle the finished window.
local last_term
local function term(cmd, root)
  local Snacks = require("xyno_rust.deps").snacks()
  if not Snacks then
    return
  end
  local old = Snacks.terminal.get(cmd, { cwd = root, create = false })
  if old then
    old:close({ buf = true })
  end
  -- a DIFFERENT command used to open one more split each time (only an
  -- identical command was found above): the previous run's terminal goes too
  if last_term and last_term ~= old and last_term.buf_valid and last_term:buf_valid() then
    pcall(last_term.close, last_term, { buf = true })
  end
  last_term = Snacks.terminal.open(cmd, { cwd = root, auto_close = false, win = { position = "bottom" } })
end'''),
    ...para('--', r'Snacks closes a terminal when the process exits 0, and with it the output the user wanted to read (the test summary, the bloat table). term opens the command with auto_close = false in a bottom split. The second problem is the rerun: Snacks.terminal.open on an identical command would only toggle the finished window. The function therefore looks the old terminal up with create = false and closes its buffer, and since a different command used to open one more split every time, it remembers the previous terminal in last_term and closes that too, inside pcall because the window may already be gone. The result is the behaviour of an IDE run window: one output pane, replaced by the next run. The git history of xynovim says when the second half was added: the Batch 2 commit 8779a6e (2026-10-12, subject "terminals keep output") introduced auto_close = false, and the round 1 commit 98c9bb4 (2026-10-13) introduced last_term.'),
    ...sec(r'the same flags everywhere'),
    ...code('lua', r'lua/xyno_rust/rust_tasks.lua · lines 48-68', r'''
--- Feature/target flags of the context (the default is --all-features).
local function ctx_flags(root)
  return rc.cargo_flags(rc.get(root))
end

--- cargo-flamegraph has no --all-features: spell the package's features out.
local function flamegraph_flags(root, pkg)
  local flags = ctx_flags(root)
  local i = vim.fn.index(flags, "--all-features")
  if i >= 0 then
    table.remove(flags, i + 1)
    local names = vim.tbl_filter(function(n)
      return n ~= "default"
    end, vim.tbl_keys(pkg.features))
    table.sort(names)
    if #names > 0 then
      vim.list_extend(flags, { "--features", table.concat(names, ",") })
    end
  end
  return flags
end'''),
    ...para('--', r'ctx_flags is the bridge to rust_context.cargo_flags. flamegraph_flags exists because of a limitation of an external tool, stated in the comment: cargo-flamegraph does not understand --all-features. When the context is the default (all features) the function finds that flag, removes it and spells the package features out as --features a,b,c, sorted, skipping default. If a package has no features, nothing is added.'),
    ...sec(r'the target table'),
    ...code('lua', r'lua/xyno_rust/rust_tasks.lua · lines 70-77', r'''
-- target kind -> { label, cargo subcommand words, target selector flag }
local ACTIONS = {
  bin = { { "run", "run", "--bin" }, { "test", "test", "--bin" }, { "build", "build", "--bin" } },
  example = { { "run", "run", "--example" }, { "build", "build", "--example" } },
  test = { { "test", "test", "--test" } },
  bench = { { "bench", "bench", "--bench" } },
  lib = { { "test", "test", "--lib" }, { "doc-test", "test", "--doc" }, { "build", "build", "--lib" } },
}'''),
    ...para('--', r'The ACTIONS table is data: for each kind of cargo target, the label shown to the user, the cargo subcommand, and the selector flag. A bin can be run, tested or built; an example run or built; a test, bench run as cargo test --test or cargo bench --bench; a library tested, doc-tested or built. Adding another action is one table entry.'),
    ...code('lua', r'lua/xyno_rust/rust_tasks.lua · lines 79-113', r'''
function M.targets()
  local root = rc.root()
  if not root then
    return vim.notify("no Cargo.toml found", vim.log.levels.WARN)
  end
  local meta, err = cargo_metadata(root)
  if not meta then
    return vim.notify("cargo metadata failed: " .. tostring(err), vim.log.levels.ERROR)
  end
  local items = {}
  for _, p in ipairs(meta.packages) do
    for _, t in ipairs(p.targets) do
      local kind = t.kind[1]
      kind = (kind == "proc-macro" or kind == "rlib" or kind == "cdylib" or kind == "staticlib" or kind == "dylib") and "lib" or kind
      if kind == "bin" then
        -- `profiling` profile = release + debug symbols (~/.cargo/config.toml)
        local bin = ("%s/profiling/%s"):format(meta.target_directory, t.name) .. (vim.fn.has("win32") == 1 and ".exe" or "")
        local build = { "cargo", "build", "--profile", "profiling", "-p", p.name, "--bin", t.name }
        vim.list_extend(build, ctx_flags(root))
        items[#items + 1] = {
          text = ("samply  bin %s (%s)"):format(t.name, p.name),
          cmd = M.samply_cmd(build, bin),
        }
        items[#items + 1] = {
          text = ("flamegraph  bin %s (%s)"):format(t.name, p.name),
          cmd = vim.list_extend({ "cargo", "flamegraph", "--profile", "profiling", "-p", p.name, "--bin", t.name }, flamegraph_flags(root, p)),
        }
      end
      for _, a in ipairs(ACTIONS[kind] or {}) do
        local cmd = { "cargo", a[2], "-p", p.name }
        if kind == "lib" then
          cmd[#cmd + 1] = a[3]
        else
          vim.list_extend(cmd, { a[3], t.name })
        end'''),
    ...para('--', r'cargo metadata --no-deps lists every target of every workspace member. All the library-like kinds (proc-macro, rlib, cdylib, staticlib, dylib) are collapsed to lib so one row covers them. For each bin two profiling rows are added before the ordinary actions. The samply row builds with --profile profiling and then records the resulting binary; the comment says the profile is release plus debug symbols and lives in ~/.cargo/config.toml, which is what the README repeats as the one thing the user must define. The flamegraph row calls cargo flamegraph with the same profile. The binary path is computed from target_directory, with .exe added on Windows.'),
    ...code('lua', r'lua/xyno_rust/rust_tasks.lua · lines 107-138', r'''
      for _, a in ipairs(ACTIONS[kind] or {}) do
        local cmd = { "cargo", a[2], "-p", p.name }
        if kind == "lib" then
          cmd[#cmd + 1] = a[3]
        else
          vim.list_extend(cmd, { a[3], t.name })
        end
        vim.list_extend(cmd, ctx_flags(root))
        items[#items + 1] = {
          text = ("%s  %s %s (%s)"):format(a[1], kind, t.name, p.name),
          cmd = cmd,
        }
      end
    end
  end
  local Snacks = require("xyno_rust.deps").snacks()
  if not Snacks then
    return
  end
  Snacks.picker({
    title = "Cargo targets - " .. rc.describe(rc.get(root)),
    items = items,
    format = "text",
    layout = { preset = "select" },
    confirm = function(picker, item)
      picker:close()
      if item then
        term(item.cmd, root)
      end
    end,
  })
end'''),
    ...para('--', r'The loop over ACTIONS builds the argv: cargo, subcommand, -p package, then the selector (--lib, or --bin name and so on), then the context flags. The picker shows "run  bin name (package)" and confirm hands the stored argv to term. Because the argv is a list, nothing goes through a shell except in the samply case.'),
    ...sec(r'the samply command line'),
    ...code('lua', r'lua/xyno_rust/rust_tasks.lua · lines 5-15', r'''
--- `<build argv> && samply record <bin>`: through sh on POSIX, through cmd.exe on
--- Windows (where sh may be missing and vim.fn.shellescape quotes for the 'shell' option).
function M.samply_cmd(build, bin)
  if vim.fn.has("win32") == 1 then
    local function q(s)
      return '"' .. s:gsub('"', '""') .. '"'
    end
    return { "cmd", "/s", "/c", '"' .. table.concat(vim.tbl_map(q, build), " ") .. " && samply record " .. q(bin) .. '"' }
  end
  return { "sh", "-c", table.concat(vim.tbl_map(vim.fn.shellescape, build), " ") .. " && samply record " .. vim.fn.shellescape(bin) }
end'''),
    ...para('--', r'samply needs two steps, build then record, in one terminal. On POSIX the pieces are quoted with vim.fn.shellescape and joined into an sh -c string. On Windows sh may be missing and shellescape quotes for the shell option, so the command goes through cmd.exe with its own quoting (doubling embedded quotes). The function is public precisely so the spec can assert both shapes; the Windows branch is carried over from the portability commit ff1c8fa (2026-10-16) and, as the README notes, is not exercised by this repository.'),
    ...sec(r'the tools picker'),
    ...code('lua', r'lua/xyno_rust/rust_tasks.lua · lines 175-186', r'''
-- Workspace-wide tools (supply chain, size, build time).
local TOOLS = {
  { "timings (cargo build --timings; report in target/cargo-timings)", { "cargo", "build", "--timings" }, true },
  { "bloat by crate (release)", { "cargo", "bloat", "--release", "--crates" }, true },
  { "bloat by function (release, top 30)", { "cargo", "bloat", "--release", "-n", "30" }, true },
  { "unused dependencies (cargo machete)", { "cargo", "machete" } },
  { "deny: fetch advisory DB", { "cargo", "deny", "fetch" } },
  { "deny: check all", { "cargo", "deny", "check" } },
  { "audit (RustSec)", { "cargo", "audit" } },
  { "duplicate dependency versions", { "cargo", "tree", "-d" } },
  { "coverage report (summary in terminal)", { "cargo", "llvm-cov", "--workspace", "--ignore-run-fail", "--summary-only" }, true },
}'''),
    ...para('--', r'Nine entries: build timings, cargo-bloat by crate and by function, cargo-machete for unused dependencies, cargo-deny fetch and check, cargo-audit, cargo tree -d for duplicate versions, and a llvm-cov summary. The third element of an entry marks the ones that build the workspace; only those get the context flags appended, so that the timings, bloat and coverage numbers describe the same build the diagnostics see. The audit and tree commands do not build and stay untouched.'),
    ...code('lua', r'lua/xyno_rust/rust_tasks.lua · lines 188-197', r'''
local function has_deny_config(root)
  for _, f in ipairs({ "deny.toml", ".deny.toml", ".cargo/deny.toml" }) do
    if vim.uv.fs_stat(root .. "/" .. f) then
      return true
    end
  end
  return false
end

function M.tools()'''),
    ...code('lua', r'lua/xyno_rust/rust_tasks.lua · lines 202-212', r'''
  local items = vim.tbl_map(function(t)
    local cmd = t[2]
    if t[3] then -- builds the workspace: same features/target as the diagnostics
      cmd = vim.list_extend(vim.deepcopy(cmd), ctx_flags(root))
    end
    -- no deny.toml: every dependency fails the (empty) licence allow list
    if t[2][3] == "check" and #t[2] == 3 and not has_deny_config(root) then
      return { text = t[1] .. " (no deny.toml: licenses skipped)", cmd = { "cargo", "deny", "check", "advisories", "bans", "sources" } }
    end
    return { text = t[1], cmd = cmd }
  end, TOOLS)'''),
    ...para('--', r'One entry has a special case. cargo deny check with no deny.toml fails every dependency against an empty licence allow list, which looks like a wall of errors in a healthy project. When no deny.toml, .deny.toml or .cargo/deny.toml exists, the entry is replaced by cargo deny check advisories bans sources and its label says "no deny.toml: licenses skipped". The field-test commit that listed "deny fallback and parser" is f31e013 (2026-10-14).'),
    ...sec(r'scaffolding and CI jobs'),
    ...code('lua', r'lua/xyno_rust/rust_tasks.lua · lines 141-173', r'''
function M.new(name)
  local function create(n, kind)
    local args = { "cargo", "new", n }
    if kind == "lib" then
      table.insert(args, "--lib")
    end
    local o = vim.system(args, { cwd = vim.uv.cwd(), text = true }):wait(30000)
    if o.code ~= 0 then
      return vim.notify(o.stderr, vim.log.levels.ERROR)
    end
    local dir = vim.uv.cwd() .. "/" .. n
    vim.cmd.edit(dir .. "/src/" .. (kind == "lib" and "lib.rs" or "main.rs"))
    vim.notify("created " .. dir)
  end
  local function with_name(n)
    if not n or n == "" then
      return
    end
    if n:sub(1, 1) == "-" then -- cargo would take it as an option
      return vim.notify("crate name cannot start with '-': " .. n, vim.log.levels.ERROR)
    end
    vim.ui.select({ "bin", "lib" }, { prompt = "Crate type" }, function(kind)
      if kind then
        create(n, kind)
      end
    end)
  end
  if name and name ~= "" then
    with_name(name)
  else
    vim.ui.input({ prompt = "New crate name: " }, with_name)
  end
end'''),
    ...para('--', r':RustNew asks for a name (or takes it as the argument), then bin or lib, runs cargo new in the current directory with a 30 second wait, and opens src/main.rs or src/lib.rs. A name that starts with a dash is refused with its own message because cargo would take it for an option. Here there is no template; xyno-new.nvim is the sibling plugin whose README describes the larger scaffolding commands.'),
    ...code('lua', r'lua/xyno_rust/rust_tasks.lua · lines 232-253', r'''
function M.act_job()
  local file = vim.api.nvim_buf_get_name(0)
  local node = vim.treesitter.get_node()
  local job
  while node do
    if node:type() == "block_mapping_pair" then
      local pair_parent = node:parent() and node:parent():parent()
      local grand = pair_parent and pair_parent:parent()
      local gkey = grand and grand:type() == "block_mapping_pair" and grand:field("key")[1]
      if gkey and vim.treesitter.get_node_text(gkey, 0) == "jobs" then
        job = vim.treesitter.get_node_text(node:field("key")[1], 0)
        break
      end
    end
    node = node:parent()
  end
  if not job then
    return vim.notify("cursor is not inside a job under `jobs:`", vim.log.levels.WARN)
  end
  local root = vim.fs.root(file, ".git") or vim.uv.cwd()
  term({ "act", "-j", job, "-W", file }, root)
end'''),
    ...para('--', r':ActJob runs the GitHub Actions job the cursor is in, locally, with act. It walks up the tree-sitter YAML tree from the cursor to a block_mapping_pair whose grandparent pair is keyed jobs, takes the pair key as the job name, and runs act -j job -W file from the git root (falling back to the cwd). That is why the README lists the yaml parser as a requirement of :ActJob alone. A cursor outside jobs: gets a warning, not a guess.'),
    ...sec(r'doctests and setup'),
    ...code('lua', r'lua/xyno_rust/rust_tasks.lua · lines 255-275', r'''
--- <leader>tD: neotest (nextest) cannot run doctests.
function M.doctests()
  local root = rc.root()
  if not root then
    return vim.notify("no Cargo.toml found", vim.log.levels.WARN)
  end
  term(vim.list_extend({ "cargo", "test", "--doc", "--workspace" }, ctx_flags(root)), root)
end

--- opts.commands = false: do not define :RustTargets, :RustTools, :ActJob, :RustNew.
function M.setup(opts)
  if opts and opts.commands == false then
    return
  end
  vim.api.nvim_create_user_command("RustTargets", M.targets, { desc = "Run/test/bench a cargo target" })
  vim.api.nvim_create_user_command("RustTools", M.tools, { desc = "Cargo tools: deny, audit, bloat, timings, ..." })
  vim.api.nvim_create_user_command("ActJob", M.act_job, { desc = "Run the GitHub Actions job under the cursor with act" })
  vim.api.nvim_create_user_command("RustNew", function(a)
    M.new(a.args)
  end, { nargs = "?", desc = "cargo new in the current directory" })
end'''),
    ...para('--', r'The comment on doctests gives the reason it exists in one line: “neotest (nextest) cannot run doctests”. The function runs cargo test --doc --workspace with the context flags. setup defines the four user commands unless commands = false; the Lua functions stay callable either way.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/rust-tasks-tools_spec.lua is 757 lines, the fourth longest spec of the repository because Snacks.picker, Snacks.terminal, vim.ui and vim.system are stubbed (its header says so, and it calls H.fake_snacks()). Its describe blocks follow the module: setup commands, :RustTargets errors and items, the term helper reached through :RustTools confirm, :RustNew, :RustTools, :ActJob and rust_tasks.doctests.'),
    ...sec(r'history'),
    ...para('--', r'First appearances in xynovim are the work-in-progress commits 025f7a6 and 81e0650 (2026-10-09). The relevant fixes: 8779a6e (2026-10-12) "keys that did nothing ... terminals keep output, coverage with failing tests, tD doctests"; 98c9bb4 (2026-10-13); f31e013 (2026-10-14, deny fallback and parser, RustContext args); 25086fd (2026-10-14, RustTools flags); ff1c8fa (2026-10-16, Windows cmd.exe for samply); 0247401 (2026-10-22, the JetBrains positioning comment). Copied into this repository in c1c7958 with require paths changed and Snacks lookups through deps.lua.'),
  ],
);
