import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/rust_tasks.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust_tasks.lua — run, test, profile and audit from a picker'),
    cm('--', r':RustTargets, :RustTools, :ActJob, :RustNew and the doctest key'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'cargo task launchers: every command runs in one reusable bottom terminal'),
    kv(r'language', r'Lua; cargo metadata JSON, Snacks picker and terminal, treesitter for YAML'),
    kv(r'size', r'261 lines, 9 commits (025f7a6 on 2026-10-09 to 0247401 on 2026-10-22)'),
    kv(r'commands', r':RustTargets (<leader>rX) · :RustTools (<leader>rZ) · :ActJob · :RustNew · <leader>tD'),
    kv(r'depends on', r'rust_context.lua (root, context flags), Snacks'),
    kv(r'also lives in', r'xyno-rust.nvim (lua/xyno_rust/rust_tasks.lua): Snacks guards and a commands option added'),
    ...sec(r'why this file exists'),
    ...para('--', r'Running a cargo target is rarely one command. For a binary there are run, test, build, a samply profile and a flamegraph; for a library, tests, doctests and a build; for the workspace there are supply-chain checks, size reports and build timings. A person who works in the JetBrains IDEs gets this from the Cargo tool window and the run configurations, and the header says so: "Cargo targets picker (inspired by the Cargo tool window / run configurations of the JetBrains IDEs, minimal) and a project scaffold command. Honors the :RustContext choice." This file is the minimal version: build a list of runnable things from cargo metadata, let the user pick one with the Snacks picker, run it in a terminal.'),
    ...para('--', r'The last sentence of the header matters most. Every command that builds code gets the feature and target flags of the current context (rust_context.lua), so that tests, profiles and coverage compile the same configuration as the diagnostics on screen.'),
    ...sec(r'a profile with a shell in between: samply_cmd'),
    ...code('lua', r'lua/config/rust_tasks.lua · lines 5-15', r'''
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
    ...para('--', r'A profiling run is two steps: build the binary with symbols, then run it under samply. They have to be one terminal job so that the second step does not start if the first one fails, which is what the && is for. The command is a table for Snacks, so it has to name a shell to interpret the &&. On POSIX that is sh -c with each argument escaped by shellescape. The comment explains the Windows branch: sh may be missing there, and shellescape quotes for the shell option (which is not cmd.exe’s quoting), so the function writes its own quoting for cmd.exe: each argument wrapped in double quotes with embedded quotes doubled, and the whole command line wrapped once more in quotes after /s /c, which tells cmd to strip exactly the outer pair. It was made a public function (M.samply_cmd) so the spec can test it directly: "the samply item shellescapes odd target directories and names". The portability commit ff1c8fa (2026-10-16) added the Windows branch.'),
    ...sec(r'one terminal, reused'),
    ...code('lua', r'lua/config/rust_tasks.lua · lines 17-42', r'''
local rc = require("config.rust_context")

local function cargo_metadata(root)
  local o = vim.system({ "cargo", "metadata", "--format-version", "1", "--no-deps" }, { cwd = root, text = true }):wait(30000)
  if o.code ~= 0 then
    return nil, o.stderr
  end
  return vim.json.decode(o.stdout)
end

--- Run in a bottom terminal that stays open after exit 0 (Snacks closes it
--- by default and the output is gone). A rerun replaces the previous one:
--- Snacks.terminal would just toggle the finished window.
local last_term
local function term(cmd, root)
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
    ...para('--', r'term() is the one place where every command ends up, and its comments are two bug reports. By default Snacks closes a terminal when the command exits with 0, and "the output is gone", which is wrong for a test run or a report you want to read; so auto_close = false keeps it. And Snacks.terminal.open with the same command toggles an existing finished window instead of running again, so a rerun first closes the old one (with its buffer, for a clean slate) and opens a new terminal. The second paragraph, added later, handles a different command: only an identical command was found by the first lookup, so each different command opened one more split. The function now remembers the last terminal it opened in last_term and closes it too, in a pcall. The result is that the bottom area always holds exactly one task output.'),
    ...para('--', r'cargo_metadata is the same helper that rust_context.lua has privately: it runs cargo metadata with --no-deps (only workspace members, fast) in the workspace root with a 30-second wait and returns the decoded table, or nil and stderr. The two files each carry a copy; they do not share it.'),
    ...sec(r'flags: the context, and one tool that cannot take --all-features'),
    ...code('lua', r'lua/config/rust_tasks.lua · lines 44-64', r'''
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
    ...para('--', r'ctx_flags is one line over rust_context: look up the stored context for the root and translate it to flags; the default is --all-features. cargo flamegraph does not accept --all-features, so flamegraph_flags rewrites the list. It finds the flag (vim.fn.index returns a 0-based position, hence the i + 1 when removing from a Lua list), removes it, and spells out the features of the package from its metadata, sorted for stable output and without default, which is on already. A package with no features adds nothing; a context that already lists explicit features is left alone, as the specs for the flamegraph item confirm ("keeps the target flag and leaves a feature-list context alone").'),
    ...sec(r':RustTargets: building the list'),
    ...code('lua', r'lua/config/rust_tasks.lua · lines 66-130', r'''
-- target kind -> { label, cargo subcommand words, target selector flag }
local ACTIONS = {
  bin = { { "run", "run", "--bin" }, { "test", "test", "--bin" }, { "build", "build", "--bin" } },
  example = { { "run", "run", "--example" }, { "build", "build", "--example" } },
  test = { { "test", "test", "--test" } },
  bench = { { "bench", "bench", "--bench" } },
  lib = { { "test", "test", "--lib" }, { "doc-test", "test", "--doc" }, { "build", "build", "--lib" } },
}

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
        end
        vim.list_extend(cmd, ctx_flags(root))
        items[#items + 1] = {
          text = ("%s  %s %s (%s)"):format(a[1], kind, t.name, p.name),
          cmd = cmd,
        }
      end
    end
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
    ...para('--', r'The ACTIONS table is the whole policy: for each kind of target, which cargo subcommands are offered and which selector flag picks the target. A binary can be run, tested or built with --bin name; an example can be run or built; a test target, a benchmark target and a library each get their own lines; and the library gets a "doc-test" line, which is cargo test --doc, because the library has no name argument (a[3] is a flag without the target name for kind lib). Five different crate types that cargo calls lib-like (proc-macro, rlib, cdylib, staticlib, dylib) are folded into lib. Every command carries -p package so that the item works from any directory of the workspace, and ends with the context flags.'),
    ...para('--', r'Binaries get two more items. The profiling profile is the one defined in the user’s ~/.cargo/config.toml ("release + debug symbols", per the comment), so samply builds with symbols and then runs target/profiling/<name> (with .exe appended on Windows). The flamegraph item uses cargo flamegraph with the same profile. All items are plain tables with text and cmd; the picker is a Snacks select layout with the title showing the current context, and confirming runs term(item.cmd, root). The spec for this is thorough about shapes: "builds run/test/build + samply + flamegraph for a bin, run/build for an example, test, bench, and the lib trio".'),
    ...sec(r':RustNew: the older scaffold'),
    ...code('lua', r'lua/config/rust_tasks.lua · lines 132-165', r'''
--- :RustNew [name]: cargo new (bin or lib) in the current directory and open it.
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
    ...para('--', r':RustNew asks for a name (or takes it from the command line), then asks bin or lib, runs cargo new and opens src/main.rs or src/lib.rs. The guard on a leading dash is the one detail: a name such as -x would otherwise be read by cargo as an option. A cancelled prompt does nothing. The header of lua/config/rust_new.lua says that this command is retained: "The older :RustNew (rust_tasks.lua) stays", next to the newer :RustNewBin, :RustNewLib and :RustNewWorkspace commands and the dashboard entries, which scaffold more (they have their own pages).'),
    ...sec(r':RustTools: the workspace-wide checks'),
    ...code('lua', r'lua/config/rust_tasks.lua · lines 167-217', r'''
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
}

local function has_deny_config(root)
  for _, f in ipairs({ "deny.toml", ".deny.toml", ".cargo/deny.toml" }) do
    if vim.uv.fs_stat(root .. "/" .. f) then
      return true
    end
  end
  return false
end

function M.tools()
  local root = rc.root()
  if not root then
    return vim.notify("no Cargo.toml found", vim.log.levels.WARN)
  end
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
  end, TOOLS)
  Snacks.picker({
    title = "Cargo tools",
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
    ...para('--', r'TOOLS is a data table of nine entries: a label, the command, and an optional third value that means "this one builds the workspace, so give it the context flags". Timings, both bloat reports and the coverage summary build code; machete, deny, audit and tree -d only read manifests and lockfiles. The flags are appended to a deep copy, so repeated calls do not accumulate flags in the shared table; the spec asserts that ("repeated calls do not accumulate flags").'),
    ...para('--', r'One entry has a special case, and it is worth reading twice. cargo deny check runs the licence check too, and without a deny.toml the licence allow-list is empty, so "every dependency fails" it. The code detects the entry by its shape (third word "check" and exactly three words) and, when no deny configuration exists in any of the three places cargo-deny looks (deny.toml, .deny.toml, .cargo/deny.toml), swaps in a command that checks advisories, bans and sources only, and relabels the line "(no deny.toml: licenses skipped)" so the user sees what was done. The commit message that introduced this is f31e013 ("deny fallback and parser"). The spec: "deny: check all runs the licence check only when the crate has a deny.toml".'),
    ...sec(r':ActJob: run the CI job under the cursor'),
    ...code('lua', r'lua/config/rust_tasks.lua · lines 219-250', r'''
--- :ActJob - run the GitHub Actions job under the cursor locally with `act`.
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
end

--- <leader>tD: neotest (nextest) cannot run doctests.
function M.doctests()
  local root = rc.root()
  if not root then
    return vim.notify("no Cargo.toml found", vim.log.levels.WARN)
  end
  term(vim.list_extend({ "cargo", "test", "--doc", "--workspace" }, ctx_flags(root)), root)
end'''),
    ...para('--', r'act runs a GitHub Actions job locally. Which job is under the cursor of a workflow YAML is a question about the syntax tree, and the loop walks up from the cursor node looking for a block_mapping_pair whose grandparent pair is keyed "jobs": the job is the key of that pair. The walk past parent():parent() reflects how the YAML grammar nests a mapping inside a pair. The cursor can be anywhere in the job, on a step deep inside, and still finds it; the spec states that and also the multi-job case. Outside a job the user gets a warning that explains the rule. The command runs act -j <job> -W <this file> from the git root (the working directory if there is no .git), in the same shared terminal.'),
    ...para('--', r'doctests() is the smallest function: cargo test --doc --workspace with the context flags, in the workspace root. The doc comment gives the reason it exists at all: "neotest (nextest) cannot run doctests". It is bound to <leader>tD as a buffer-local key in keymaps.lua.'),
    ...code('lua', r'lua/config/rust_tasks.lua · lines 252-259', r'''
function M.setup()
  vim.api.nvim_create_user_command("RustTargets", M.targets, { desc = "Run/test/bench a cargo target" })
  vim.api.nvim_create_user_command("RustTools", M.tools, { desc = "Cargo tools: deny, audit, bloat, timings, ..." })
  vim.api.nvim_create_user_command("ActJob", M.act_job, { desc = "Run the GitHub Actions job under the cursor with act" })
  vim.api.nvim_create_user_command("RustNew", function(a)
    M.new(a.args)
  end, { nargs = "?", desc = "cargo new in the current directory" })
end'''),
    ...sec(r'design decisions and trade-offs'),
    ...pt('--', r'commands as data', r'ACTIONS and TOOLS are tables. A new cargo subcommand is a line of data, not a function. The specs can compare whole command lines.'),
    ...pt('--', r'blocking metadata calls', r'cargo metadata is run with :wait(30000), which blocks the editor while cargo works. It is a deliberate simplicity: the picker needs the answer before it can open, and with --no-deps the call is usually fast. A workspace that needs to download or resolve something can freeze the UI up to 30 seconds.'),
    ...pt('--', r'one terminal slot', r'the choice to keep exactly one task terminal means you lose the output of the previous run; the benefit is a quiet screen. Rerunning is a single key.'),
    ...pt('--', r'context everywhere', r'every compile uses the same features and target as the diagnostics, so the result of a test run explains what the squiggles say, not a different configuration.'),
    ...sec(r'what differs in xyno-rust.nvim'),
    ...para('--', r'The plugin copy (lua/xyno_rust/rust_tasks.lua, 2026-10-22) is the same code with three kinds of change: the require of rust_context points at xyno_rust.rust_context; term(), targets() and tools() each first ask xyno_rust.deps.snacks() for Snacks and return quietly if it is not installed, where this version uses the global; and setup(opts) returns early when opts.commands is false, so none of :RustTargets, :RustTools, :ActJob or :RustNew is defined. A diff of the two shows no other change.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/rust-tasks-tools_spec.lua (51 it() blocks and 1 pending entry) has a describe per command: the command definitions, :RustTargets errors and items (shapes, lib kinds, context flags, samply and flamegraph), the terminal behaviour through :RustTools confirm, :RustNew, :RustTools, :ActJob and doctests. The same file also holds the coverage specs for <leader>tc, which are a different module’s subject.'),
    ...sec(r'history'),
    ...pt('--', r'025f7a6 and 81e0650 · 2026-10-09', r'the first versions (wip commits).'),
    ...pt('--', r'be73b6c · 2026-10-12', r'Rust workflow robustness.'),
    ...pt('--', r'8779a6e · 2026-10-12', r'Batch 2: keys that did nothing: "terminals keep output", "tD doctests".'),
    ...pt('--', r'98c9bb4 · 2026-10-13', r'Final loop round 1: "cargo-deny log/lock lines", "nextest progress bar".'),
    ...pt('--', r'f31e013 · 2026-10-14', r'Final loop round 4: "deny fallback and parser".'),
    ...pt('--', r'25086fd · 2026-10-14', r'Final loop round 5: "RustTools flags".'),
    ...pt('--', r'ff1c8fa · 2026-10-16', r'Windows and macOS: the cmd.exe branch of samply_cmd and the .exe suffix.'),
    ...pt('--', r'0247401 · 2026-10-22', r'Positioning: header reworded from RustRover’s Cargo tool window to the JetBrains IDEs.'),
  ],
);
