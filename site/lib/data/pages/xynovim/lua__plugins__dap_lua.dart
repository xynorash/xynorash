import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/dap.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'dap.lua — debugging Rust so that locals show and panics stop'),
    cm('--', r'codelldb configs, a workspace debuggable picker, a pause that works, a console that stays'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'nvim-dap, mason-nvim-dap and nvim-dap-ui tuned for Rust on top of LazyVim’s dap.core and lang.rust extras'),
    kv(r'language', r'Lua, local helper functions followed by a three-entry spec list'),
    kv(r'size', r'403 lines, 7 commits (0494b52, 2026-10-12 to 6524272, 2026-10-21)'),
    kv(r'keys', r'<leader>dR (workspace debuggables), <leader>dP (pause)'),
    kv(r'adapter', r'codelldb from Mason; every launch carries sourceLanguages = rust'),
    kv(r'needs', r'cargo, rustc, config.rust_context, rustaceanvim'),
    ...sec(r'why this file exists'),
    ...para('--',
        r'The header lists three things the stock setup did not do. Rust launch configurations that '
        r'default to the package binary under the target directory’s debug folder instead of the '
        r'project root. A wider dap-ui sidebar, because Rust type names are long, with wrapping on. '
        r'And <leader>dR, debuggables for the whole workspace: binaries, examples and the current '
        r'file’s rust-analyzer runnables, where the stock <leader>dr only offers what rust-analyzer '
        r'returns for the current file (in lib.rs that is just tests).'),
    blank,
    ...para('--',
        r'The last header line is a warning about something outside the repository: locals need full '
        r'debuginfo, see profile.dev in ~/.cargo/config.toml. docs/DETAILS.md records the '
        r'measurement behind it: the user-level profile is set to debug = true, because '
        r'line-tables-only and limited show no locals, and split-debuginfo, packed or unpacked, left '
        r'codelldb without locals. The measured cost of full debuginfo against line-tables-only is '
        r'given there as about 14 percent on a clean build and about 28 percent on target/debug (two fixtures, single noisy runs, as the same entry says).'),
    blank,
    ...para('--',
        r'Later commits added the two other things the file does now: a breakpoint on rust_panic '
        r'with Rust’s lldb formatters (be73b6c, 2026-10-12), and a console that stays readable after '
        r'the session ends (3f868dd, 2026-10-13). The page is organised along the file: helpers, the '
        r'three launch configurations, the init hook, the debuggable picker, pause, and then the '
        r'three specs.'),
    ...sec(r'reading cargo metadata'),
    ...code('lua', r'lua/plugins/dap.lua · lines 9-37', r'''
local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "dap" })
end

--- `cargo metadata --no-deps` for the workspace holding `path`, or nil.
local function metadata(path)
  local root = require("config.rust_context").root(path)
  if not root then
    return nil
  end
  local o = vim
    .system({ "cargo", "metadata", "--format-version", "1", "--no-deps" }, { cwd = root, text = true })
    :wait(30000)
  if o.code ~= 0 then
    return nil
  end
  local ok, meta = pcall(vim.json.decode, o.stdout)
  return ok and meta or nil, root
end

local function bins_of(pkg, kind)
  local r = {}
  for _, t in ipairs(pkg.targets) do
    if vim.tbl_contains(t.kind, kind) then
      r[#r + 1] = t
    end
  end
  return r
end'''),
    blank,
    ...para('--',
        r'notify gives every message the title dap, which the tests rely on. metadata(path) is the '
        r'entry point for everything that needs to know about the workspace. It asks '
        r'config.rust_context for the Cargo root of the path, runs cargo metadata --format-version 1 '
        r'--no-deps in that root, and waits up to 30 seconds. A non-zero exit gives nil. A zero exit '
        r'with unparseable JSON gives nil as well because the decode is wrapped in pcall. The tests '
        r'for the two cases are "an invalid Cargo.toml gives no binary and no error" and "cargo '
        r'exiting 0 with invalid JSON gives nil, not an error".'),
    blank,
    ...para('--',
        r'--no-deps keeps the output small: only workspace packages, not the dependency graph. '
        r'bins_of(pkg, kind) filters a package’s targets by kind, "bin" or "example".'),
    ...sec(r'which binary is "the current binary"'),
    ...code('lua', r'lua/plugins/dap.lua · lines 45-88', r'''
local function drive_fold(p)
  if vim.fn.has("win32") == 1 then
    return (p:gsub("^%a:", string.lower))
  end
  return p
end

local function current_binary()
  local file = drive_fold(vim.fs.normalize(vim.api.nvim_buf_get_name(0)))
  local meta, root = metadata(file ~= "" and file or (vim.uv.cwd() .. "/x"))
  if not meta then
    return nil
  end
  local best, best_len, rootpkg, firstbin
  for _, pkg in ipairs(meta.packages) do
    local dir = drive_fold(vim.fs.normalize(vim.fs.dirname(pkg.manifest_path)))
    if #bins_of(pkg, "bin") > 0 then
      firstbin = firstbin or pkg
      if dir == drive_fold(vim.fs.normalize(root)) then
        rootpkg = pkg
      end
      if file:sub(1, #dir + 1) == dir .. "/" and #dir > (best_len or 0) then
        best, best_len = pkg, #dir
      end
    end
  end
  local pkg = best or rootpkg or firstbin
  if not pkg then
    return nil
  end
  local bins = bins_of(pkg, "bin")
  local bin = bins[1]
  for _, b in ipairs(bins) do
    if b.name == pkg.name then
      bin = b
    end
  end
  return {
    pkg = pkg.name,
    bin = bin.name,
    dir = vim.fs.dirname(pkg.manifest_path),
    path = meta.target_directory .. "/debug/" .. bin.name .. (vim.fn.has("win32") == 1 and ".exe" or ""),
  }
end'''),
    blank,
    ...para('--',
        r'The doc comment above drive_fold (lines 39 to 44) is the description of current_binary: '
        r'the package containing the file, otherwise the root package, otherwise the first one, and '
        r'in it the binary named like the package, otherwise the first binary. In the file the '
        r'comment sits above drive_fold, with current_binary after it, so the text and the function '
        r'it describes are separated.'),
    blank,
    ...para('--',
        r'drive_fold exists for Windows only. The comment explains: the drive is spelled C: or c: '
        r'depending on who reports the path, namely cargo metadata, the buffer name and '
        r'rust_context’s canonical root, so the paths are compared with the drive letter lowercased. '
        r'On other systems it returns the path unchanged. This arrived with the Windows and macOS '
        r'run fixes (commit 6524272, 2026-10-21, ".exe suffix and drive-letter case in '
        r'dap/rust_context/..."). The same commit is why line 86 adds .exe on win32.'),
    blank,
    ...para('--',
        r'The selection loop is worth reading slowly. It iterates over the packages and ignores any '
        r'without a binary target. Each of those can become firstbin (the fallback), rootpkg (its '
        r'directory is the workspace root), or best (the file is inside the package directory, and '
        r'the directory is longer than the best so far). The test is a prefix check with a slash '
        r'appended, dir .. "/", so /w/app does not match a file in /w/app-extra. The longest '
        r'directory wins, which is how a nested package beats its parent. The result of the three '
        r'alternatives is pkg = best or rootpkg or firstbin.'),
    blank,
    ...para('--',
        r'The spec file tests each rule by name: "picks the package containing the buffer file", '
        r'"bin named like the package wins, else the first bin", "a package without a bin is '
        r'skipped...", "longest directory match: a nested package wins over its parent", "no file: '
        r'the workspace root package, else (virtual workspace) the first package with a bin", and '
        r'"no package with a bin: default program falls back to <cwd>/, package dir to the cwd".'),
    blank,
    ...para('--',
        r'current_binary returns a table with the package name, the binary name, the package '
        r'directory, and the path to the executable: meta.target_directory .. "/debug/" .. bin.name, '
        r'plus .exe on Windows. It uses cargo’s own target_directory, so a CARGO_TARGET_DIR or a '
        r'build.target-dir setting is respected without any extra code. That is the "target dir" in '
        r'the header.'),
    ...sec(r'prompts and the build step'),
    ...code('lua', r'lua/plugins/dap.lua · lines 90-135', r'''
local function default_program()
  local b = current_binary()
  return b and b.path or vim.fn.getcwd() .. "/"
end

local function prompt_program()
  return vim.fn.input("Path to executable: ", default_program(), "file")
end

local function prompt_args()
  return vim.split(vim.fn.input("Args: "), " +", { trimempty = true })
end

--- Build the current package's binary (yielding when run inside nvim-dap's
--- coroutine so the UI stays responsive) and return its path.
local function build_current_binary()
  local b = current_binary()
  if not b then
    notify("no Cargo package with a binary found for this buffer", vim.log.levels.ERROR)
    return require("dap").ABORT
  end
  notify("cargo build --package " .. b.pkg .. " --bin " .. b.bin)
  local cmd = { "cargo", "build", "--package", b.pkg, "--bin", b.bin }
  local co = coroutine.running()
  local res
  if co then
    vim.system(cmd, { cwd = b.dir, text = true }, function(o)
      vim.schedule(function()
        coroutine.resume(co, o)
      end)
    end)
    res = coroutine.yield()
  else
    res = vim.system(cmd, { cwd = b.dir, text = true }):wait()
  end
  if res.code ~= 0 then
    notify("cargo build failed:\n" .. (res.stderr or ""), vim.log.levels.ERROR)
    return require("dap").ABORT
  end
  return b.path
end

local function package_dir()
  local b = current_binary()
  return b and b.dir or vim.fn.getcwd()
end'''),
    blank,
    ...para('--',
        r'default_program proposes the binary path, falling back to the current directory with a '
        r'trailing slash when no package is found. prompt_program is a vim.fn.input with that '
        r'default and file completion. prompt_args splits the input on runs of spaces and drops '
        r'empty fields. The test: "config 2 args: split on spaces, empty fields dropped". It does '
        r'not understand quotes, so an argument with a space cannot be passed through this prompt.'),
    blank,
    ...para('--',
        r'build_current_binary is the clever one. nvim-dap evaluates a function-valued program field '
        r'inside a coroutine. When this function runs in a coroutine, the build is started with '
        r'vim.system and an asynchronous callback; the coroutine yields, and the callback, '
        r'rescheduled into the main loop, resumes it with the result. The editor stays responsive '
        r'during a cargo build. When it is called outside a coroutine (a script, a test), it falls '
        r'back to a blocking :wait(). Both paths are tested: "config 3: program builds the binary in '
        r'the package dir (blocking outside a coroutine)" and "inside a coroutine the build yields '
        r'(UI not blocked) and resumes with the path".'),
    blank,
    ...para('--',
        r'Errors are handled in two ways and both return dap.ABORT, the sentinel that makes nvim-dap '
        r'cancel the launch quietly. No binary found: an ERROR notification. Build failure: an ERROR '
        r'"cargo build failed:" with stderr. The tests assert both. package_dir gives the cwd for '
        r'config 3: the package directory, or the current directory when none is found.'),
    ...sec(r'the Rust formatters and the panic breakpoint'),
    ...code('lua', r'lua/plugins/dap.lua · lines 137-175', r'''
local sysroot_script

--- `<rustc sysroot>/lib/rustlib/etc/lldb_lookup.py` (rust's lldb formatters:
--- String, Vec, Option, enums...) or nil when the toolchain does not ship it.
--- Resolved once, on the first launch (not at startup).
local function lldb_lookup_script()
  if sysroot_script == nil then
    local o = vim.system({ "rustc", "--print", "sysroot" }, { text = true }):wait(10000)
    local script = o.code == 0 and vim.trim(o.stdout) .. "/lib/rustlib/etc/lldb_lookup.py"
    sysroot_script = script and vim.uv.fs_stat(script) and script or false
  end
  return sysroot_script or nil
end

--- Every codelldb launch of Rust code (configs 1-3 below, <leader>dr via
--- rustaceanvim, <leader>dR, launch.json: all carry sourceLanguages = rust)
--- gets rust's lldb formatters and a breakpoint on `rust_panic`, so a panic
--- stops at the panicking frame instead of the session ending with exit 101.
--- Done here, not in the configs, because rustaceanvim overwrites initCommands
--- on its own launches. A `#[should_panic]` test stops there too. Only the
--- lldb_lookup.py import is added, never `command source .../lldb_commands`
--- (that file does not exist on current toolchains).
local function rust_lldb_init(config)
  if config.type ~= "codelldb" or not vim.tbl_contains(config.sourceLanguages or {}, "rust") then
    return config
  end
  local cmds = vim.deepcopy(type(config.initCommands) == "table" and config.initCommands or {})
  local script = lldb_lookup_script()
  if script and not vim.iter(cmds):any(function(c)
    return c:find("lldb_lookup.py", 1, true)
  end) then
    table.insert(cmds, 1, 'command script import "' .. script .. '"')
  end
  if not vim.tbl_contains(cmds, "breakpoint set -n rust_panic") then
    cmds[#cmds + 1] = "breakpoint set -n rust_panic"
  end
  config.initCommands = cmds
  return config
end'''),
    blank,
    ...para('--',
        r'lldb_lookup_script finds the Rust pretty printers. It asks rustc --print sysroot once and '
        r'checks that <sysroot>/lib/rustlib/etc/lldb_lookup.py exists. The result is cached in a '
        r'module variable, and false is stored for failure so a missing script is not looked up '
        r'again on every launch. Three tests pin the cache: "resolves rustc --print sysroot once '
        r'across calls", "a failing rustc is cached as missing: no import, no second lookup", and "a '
        r'toolchain without lldb_lookup.py is cached as missing too". The lookup is done at first '
        r'launch, not at startup.'),
    blank,
    ...para('--',
        r'rust_lldb_init is registered as a dap on_config listener, so it sees every configuration '
        r'just before it is used. The comment gives the scope: every codelldb launch of Rust code, '
        r'meaning configs 1 to 3, <leader>dr through rustaceanvim, <leader>dR and launch.json, since '
        r'all carry sourceLanguages = rust. It is done here and not in the configurations because '
        r'rustaceanvim overwrites initCommands on its own launches.'),
    blank,
    ...para('--',
        r'The function does three things. It returns the config unchanged unless the type is '
        r'codelldb and sourceLanguages contains rust. It copies initCommands (deepcopy, so shared '
        r'tables are not mutated) and inserts command script import "<lldb_lookup.py>" at position 1 '
        r'unless a command already mentions lldb_lookup.py. And it appends breakpoint set -n '
        r'rust_panic unless present. A panic then stops at the panicking frame, so the session does '
        r'not simply end with exit code 101. A #[should_panic] test stops there too, as the comment '
        r'adds.'),
    blank,
    ...para('--',
        r'The comment ends with a deliberate omission: only the lldb_lookup.py import is added, '
        r'never command source .../lldb_commands, because that file does not exist on current '
        r'toolchains. The tests cover idempotence ("a second call adds nothing"), the order ("import '
        r'first and the rust_panic breakpoint last, nothing else") and that other adapters and '
        r'languages are untouched.'),
    ...sec(r'the three configurations'),
    ...code('lua', r'lua/plugins/dap.lua · lines 177-214', r'''
--- Replace mason-nvim-dap's generic codelldb configs for Rust.
local function rust_configurations()
  return {
    {
      name = "LLDB: Launch",
      type = "codelldb",
      request = "launch",
      sourceLanguages = { "rust" },
      program = prompt_program,
      cwd = "${workspaceFolder}",
      stopOnEntry = false,
      args = {},
      console = "integratedTerminal",
    },
    {
      name = "LLDB: Launch (args)",
      type = "codelldb",
      request = "launch",
      sourceLanguages = { "rust" },
      program = prompt_program,
      cwd = "${workspaceFolder}",
      stopOnEntry = false,
      args = prompt_args,
      console = "integratedTerminal",
    },
    {
      name = "Rust: run current package binary (args prompt)",
      type = "codelldb",
      request = "launch",
      sourceLanguages = { "rust" },
      program = build_current_binary,
      cwd = package_dir,
      stopOnEntry = false,
      args = prompt_args,
      console = "integratedTerminal",
    },
  }
end'''),
    blank,
    ...para('--',
        r'mason-nvim-dap’s generic codelldb setup adds the same configuration tables to c, cpp and '
        r'rust. rust_configurations returns a Rust-only list of three. "LLDB: Launch" and "LLDB: '
        r'Launch (args)" ask for the executable path (default: the package binary) and the second '
        r'also for arguments. The third, "Rust: run current package binary (args prompt)", builds '
        r'first with build_current_binary, uses the package directory as cwd and asks for arguments. '
        r'All set stopOnEntry = false and console = "integratedTerminal", so the program’s output '
        r'lands in a terminal.'),
    blank,
    ...para('--',
        r'Using function-valued program, args and cwd fields is what allows the prompt at launch '
        r'time rather than at startup. The test "replaces dap.configurations.rust with exactly the '
        r'three Rust configs" and "does not leak the Rust list into c/cpp" check both sides of the '
        r'replacement.'),
    ...sec(r'the workspace debuggable picker'),
    ...code('lua', r'lua/plugins/dap.lua · lines 216-256', r'''
--- All debuggable cargo runnables of the workspace: bins/examples from cargo
--- metadata plus rust-analyzer's runnables for the current file, as
--- rustaceanvim runnables ({ label, args = { cargoArgs, workspaceRoot, ... } }).
local function workspace_debuggables(ra_result)
  local ra_runnables = require("rustaceanvim.runnables")
  local items, seen = {}, {}
  local function add(label, args)
    -- per-test entries differ only in executableArgs (the test name)
    local key = table.concat(args.cargoArgs, " ") .. " -- " .. table.concat(args.executableArgs or {}, " ")
    if not seen[key] then
      seen[key] = true
      items[#items + 1] = { label = label, args = args }
    end
  end
  local meta, root = metadata(vim.api.nvim_buf_get_name(0))
  for _, pkg in ipairs(meta and meta.packages or {}) do
    for _, kind in ipairs({ "bin", "example" }) do
      for _, t in ipairs(bins_of(pkg, kind)) do
        add(("%s %s (%s)"):format(kind, t.name, pkg.name), {
          cargoArgs = { "build", "--package", pkg.name, "--" .. kind, t.name },
          cargoExtraArgs = {},
          executableArgs = {},
          workspaceRoot = root,
          cwd = vim.fs.dirname(pkg.manifest_path),
        })
      end
    end
  end
  local overrides = require("rustaceanvim.overrides")
  for _, r in ipairs(ra_result or {}) do
    local c = ra_runnables.as_cargo_runnable(r)
    if c and c.args.cargoArgs[1] ~= "check" then
      overrides.sanitize_command_for_debugging(c.args.cargoArgs)
      add(
        "test/run: " .. table.concat(c.args.cargoArgs, " ") .. " -- " .. table.concat(c.args.executableArgs or {}, " "),
        c.args
      )
    end
  end
  return items
end'''),
    blank,
    ...para('--',
        r'workspace_debuggables builds the list that <leader>dR shows. It produces rustaceanvim '
        r'runnables, the shape { label, args = { cargoArgs, workspaceRoot, ... } }, from two '
        r'sources. From cargo metadata it adds, for each package, an entry for every bin and every '
        r'example, labelled like "bin app (app-pkg)", with cargoArgs of build --package <pkg> '
        r'--<kind> <name>. From the current file’s rust-analyzer runnables it adds the ones that '
        r'rustaceanvim can turn into cargo runnables, skipping a check command and passing the '
        r'arguments through sanitize_command_for_debugging, which makes a test run debuggable.'),
    blank,
    ...para('--',
        r'The add function deduplicates on a key made of the cargo arguments and the executable '
        r'arguments. The comment explains the second half: per-test entries differ only in '
        r'executableArgs, the test name, so omitting them would hide all but the first test. Bins, '
        r'examples and runnables that describe the same invocation collapse into one entry.'),
    ...para('--',
        r'pick_workspace_debuggable checks first that the buffer is a Rust buffer: otherwise it '
        r'warns that <leader>dR works from a Rust buffer. It asks rust-analyzer for '
        r'experimental/runnables for the current document through rustaceanvim’s buf_request, merges '
        r'the result with the cargo targets, and shows vim.ui.select with the kind '
        r'"rust-tools/debuggables", the same kind rustaceanvim uses so pickers that special-case it '
        r'work. The choice starts rustaceanvim.dap.start(args, true, dap.run) and records the choice '
        r'with cached_commands.set_last_debuggable, so a "repeat last" command knows it. Cancelling '
        r'starts nothing; an empty list warns "no debuggable targets found".'),
    blank,
    ...para('--',
        r'This function is a user of rustaceanvim internals (rustaceanvim.runnables, overrides, dap, '
        r'cached_commands, rust_analyzer). The test "uses rustaceanvim internals that exist in the '
        r'locked version" checks that each of those functions exists in the version pinned by '
        r'lazy-lock.json, so an upgrade that moves one fails the suite instead of failing at the '
        r'first debug session. The local params table has position = nil, which is a no-op written '
        r'out; a document-wide request.'),
    ...sec(r'pause that works on a running process'),
    ...code('lua', r'lua/plugins/dap.lua · lines 287-305', r'''
--- <leader>dP: dap.pause() picks from session.threads, which codelldb fills only when it stops, so
--- on a running process it saw no thread ("No thread to stop") and did nothing. Ask for the threads first.
local function pause()
  local dap = require("dap")
  local session = dap.session()
  if not session then
    return notify("no debug session", vim.log.levels.WARN)
  end
  if next(session.threads or {}) then
    return dap.pause()
  end
  session:request("threads", nil, function(err, resp)
    local t = not err and resp and resp.threads and resp.threads[1]
    if not t then
      return notify("no thread to pause", vim.log.levels.WARN)
    end
    dap.pause(t.id)
  end)
end'''),
    blank,
    ...para('--',
        r'The comment names the reason: dap.pause() picks from session.threads, which codelldb fills '
        r'only when it stops; on a running process it saw no thread ("No thread to stop") and did '
        r'nothing. The fix asks the adapter for the threads first. With no session, a WARN "no debug '
        r'session". With known threads, a plain dap.pause(). Otherwise session:request("threads") '
        r'and pause the first thread by id, or WARN "no thread to pause". It came in 25086fd '
        r'(2026-10-14, "dP pause"). Tests: "a running session with no known threads asks for them '
        r'and pauses the first" and "known threads: plain dap.pause(); no session: a notice".'),
    ...sec(r'the three specs'),
    ...code('lua', r'lua/plugins/dap.lua · lines 307-328', r'''
return {
  {
    "mfussenegger/nvim-dap",
    keys = {
      { "<leader>dR", pick_workspace_debuggable, desc = "Rust Debuggables (whole workspace)" },
      { "<leader>dP", pause, desc = "Pause" },
    },
  },
  {
    "jay-babu/mason-nvim-dap.nvim",
    opts = {
      handlers = {
        codelldb = function(config)
          require("mason-nvim-dap").default_setup(config)
          -- default_setup extends c/cpp/rust with the same shared tables;
          -- give Rust its own list.
          require("dap").configurations.rust = rust_configurations()
          require("dap").listeners.on_config["xynovim_rust_lldb"] = rust_lldb_init
        end,
      },
    },
  },'''),
    blank,
    ...para('--',
        r'The first adds the two keys to nvim-dap; because they have keys, the plugin spec is merged '
        r'with LazyVim’s. The second is the codelldb handler of mason-nvim-dap. It runs '
        r'default_setup first (which defines the adapter), then replaces dap.configurations.rust '
        r'with the Rust list and registers the on_config listener under the key xynovim_rust_lldb. A '
        r'fixed key means loading the handler twice replaces the listener instead of stacking two. '
        r'The comment says why the replacement is needed: default_setup extends c, cpp and rust with '
        r'the same shared tables.'),
    ...sec(r'dap-ui: keeping the output'),
    ...code('lua', r'lua/plugins/dap.lua · lines 329-340, 358-373', r'''
  {
    "rcarriga/nvim-dap-ui",
    -- LazyVim's dap.core closes the UI on terminated/exited: the program's
    -- output then lived only in the hidden [dap-terminal] buffer. Keep it open
    -- (close with <leader>du) once the session is over.
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "LazyLoad",
        callback = function(ev)
          if ev.data == "nvim-dap-ui" then
            vim.schedule(function()
              local l = require("dap").listeners.before
...
              for _, ev in ipairs({ "event_stopped", "event_terminated", "event_exited" }) do
                la[ev]["xynovim_console"] = rescroll
              end
              -- LazyVim gives the breakpoint signs DiagnosticInfo (blue) unless the icon carries a group;
              -- the theme's red / yellow / grey groups exist
              for name, hl in pairs({ DapBreakpoint = "DapBreakpoint", DapBreakpointCondition = "DapBreakpointCondition", DapBreakpointRejected = "DapBreakpointRejected" }) do
                local def = vim.fn.sign_getdefined(name)[1]
                if def then
                  vim.fn.sign_define(name, { text = def.text, texthl = hl, linehl = def.linehl, numhl = def.numhl })
                end
              end
            end)
          end
        end,
      })
    end,'''),
    blank,
    ...para('--',
        r'LazyVim’s dap.core closes the UI on terminated and exited events, and the program’s output '
        r'then lived only in the hidden [dap-terminal] buffer. The init function hooks the LazyLoad '
        r'user event for nvim-dap-ui. When it fires for that plugin, it schedules a function that '
        r'deletes the two listeners named dapui_config under before.event_terminated and '
        r'before.event_exited. The UI stays open after the session, and the user closes it with '
        r'<leader>du.'),
    blank,
    ...para('--',
        r'The second part is the re-scroll. The comment: the Console, a terminal window, kept a '
        r'stale topline after the layout resized; the output was in the buffer but the window showed '
        r'blank lines. After stopped, terminated and exited events, a deferred function (50 ms) '
        r'looks at every window in the tab for the dapui_console filetype and, if its topline is at '
        r'or past the last line of its buffer, runs normal! gg in that window. The condition keeps '
        r'it from moving a console that is showing real content. The loop variable named ev in the '
        r'for loop shadows the callback parameter of the same name; it is harmless because the '
        r'callback does not use its ev after that point.'),
    ...para('--',
        r'The last part is the signs. The comment says LazyVim gives the breakpoint signs '
        r'DiagnosticInfo (blue) unless the icon carries a group, and that the theme’s red, yellow '
        r'and grey groups exist. The code redefines DapBreakpoint, DapBreakpointCondition and '
        r'DapBreakpointRejected with the same text, linehl and numhl but texthl set to the group of '
        r'the same name. This ties to the island theme: it defines those highlight groups, so a '
        r'breakpoint is red instead of blue.'),
    ...sec(r'the dap-ui layout'),
    ...code('lua', r'lua/plugins/dap.lua · lines 374-401', r'''
    opts = function()
      -- wide enough for `alloc::vec::Vec<alloc::string::String, alloc::alloc::Global>`
      -- on a normal terminal, but never more than a third of a narrow one.
      local width = math.max(40, math.min(60, math.floor(vim.o.columns * 0.35)))
      return {
        wrap = true,
        layouts = {
          {
            elements = {
              { id = "scopes", size = 0.4 },
              { id = "breakpoints", size = 0.15 },
              { id = "stacks", size = 0.25 },
              { id = "watches", size = 0.2 },
            },
            position = "left",
            size = width,
          },
          {
            elements = {
              { id = "repl", size = 0.5 },
              { id = "console", size = 0.5 },
            },
            position = "bottom",
            size = 10,
          },
        },
      }
    end,'''),
    blank,
    ...para('--',
        r'The comment gives the numbers: wide enough for alloc::vec::Vec<alloc::string::String, '
        r'alloc::alloc::Global> on a normal terminal, but never more than a third of a narrow one. '
        r'The formula is max(40, min(60, floor(columns * 0.35))). The test "sidebar width = max(40, '
        r'min(60, floor(columns * 0.35)))" asserts it. The sidebar holds scopes (40 percent), '
        r'breakpoints (15), stacks (25) and watches (20), and the bottom panel is the REPL and the '
        r'console at half each, 10 rows high. wrap = true makes the long type names wrap rather than '
        r'being cut off. Because opts is a function, the width is computed when the plugin is '
        r'configured, from the actual terminal.'),
    ...sec(r'design decisions'),
    ...pt('--', r'replace, do not extend',
        r'the Rust list is built fresh from three functions because the shared generic tables are '
        r'the thing to avoid. The effect on C and C++ is none; a test asserts it.'),
    ...pt('--', r'listener over configuration',
        r'the lldb hook is on dap.listeners.on_config so it covers the launch.json configurations '
        r'and the rustaceanvim launches too, which no static list could.'),
    ...pt('--', r'asynchrony only where it pays',
        r'the build yields in a coroutine; the metadata call blocks for up to 30 seconds, but only '
        r'when you start a debug session or the picker, and only once per use.'),
    ...pt('--', r'internals are pinned',
        r'the picker uses private modules of rustaceanvim and a test checks they still exist.'),
    ...sec(r'what the real session test proves'),
    ...para('--',
        r'describe "real debug session (codelldb + cargo)" at line 1178 of '
        r'tests/dap-neotest-coverage_spec.lua builds a small crate with a function that creates a '
        r'String, a Vec and an enum and panics with all three in the message. The tests: "configs 1 '
        r'and 3 stop in rust_panic with the locals of the check frame", "a breakpoint in main stops '
        r'with its locals, then continues into rust_panic", "<leader>dR (workspace debuggables) '
        r'stops in rust_panic with the same locals", and "<leader>dr (rustaceanvim debuggables) '
        r'stops in rust_panic with the same locals". They drive the real codelldb. What stays '
        r'pending is clicking a Debug codelens: "needs a mouse-driven UI session".'),
    ...sec(r'history'),
    ...pt('--', r'0494b52 (2026-10-12)',
        r'field test fixes ("debug"): the first version.'),
    ...pt('--', r'be73b6c (2026-10-12)',
        r'"dap lldb formatters and rust_panic stop, autoload_configurations off, Debug codelens".'),
    ...pt('--', r'98c9bb4, 3f868dd (2026-10-13)',
        r'field-test rounds; round 3 lists "dap-ui console and breakpoint signs".'),
    ...pt('--', r'25086fd (2026-10-14)',
        r'"dP pause".'),
    ...pt('--', r'ff1c8fa (2026-10-16)',
        r'Windows and macOS portability fixes.'),
    ...pt('--', r'6524272 (2026-10-21)',
        r'.exe suffix and drive-letter case.'),
    ...sec(r'is it in xyno-plugins?'),
    ...para('--',
        r'No. Nothing in the extracted plugins implements debugging; xyno-rust.nvim carries '
        r'rust_context.lua, which this file calls (as config.rust_context), and the task runner. The '
        r'copy in lua/config/rust_context.lua (373 lines) and the extracted '
        r'lua/xyno_rust/rust_context.lua (381 lines) differ in the module paths they require, an '
        r'optional Snacks dependency and a setup option; the functions dap.lua uses, root and the '
        r'path handling, are the same in both.'),
  ],
);
