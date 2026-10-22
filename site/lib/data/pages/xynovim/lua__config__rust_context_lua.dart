import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/rust_context.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust_context.lua — which features and which target does this project mean?'),
    cm('--', r'one stored answer per Cargo workspace, applied to rust-analyzer and bacon-ls alike'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'workspace-root finder, per-project Cargo features/target store, :RustContext'),
    kv(r'language', r'Lua; cargo locate-project / metadata, JSON state file, LSP settings'),
    kv(r'size', r'373 lines, 11 commits (f5936dc on 2026-10-09 to 0247401 on 2026-10-22)'),
    kv(r'state', r'stdpath("state")/rust-context.json, keyed by workspace root, guarded by a lock file'),
    kv(r'used by', r'rust_tasks, rust_routes, rust_restart, crate_meta, rust_new, plugins/bacon-ls, coverage, dap'),
    kv(r'also lives in', r'xyno-rust.nvim (lua/xyno_rust/rust_context.lua): Snacks guard and a commands option added'),
    ...sec(r'why this file exists'),
    ...para('--', r'This setup runs two diagnostic tiers on the same code: rust-analyzer for the language-server errors and bacon-ls for clippy. Cargo projects with optional features can have features that exclude each other (the example in describe()’s doc comment is the pair ssr,csr). If rust-analyzer checks with all features on and clippy checks with a different set, one of them reports errors that the other considers fine. The header puts it in one sentence: "rust-analyzer and bacon-ls (the clippy tier) must agree on both, otherwise mutually exclusive features give bogus errors from one tier." The two things they must agree on are the feature set and the target triple.'),
    ...para('--', r'The idea comes from the toggles of the Cargo tool window in the JetBrains IDEs (the header says "inspired by the Cargo tool window toggles"). Here it is stored per workspace in the editor’s state directory, applied when a server starts (rustaceanvim’s server.settings for rust-analyzer, the before_init hook for bacon-ls) and applied live by the :RustContext command. The default, when nothing is stored, is "all features, host target - i.e. the old behaviour", so a project that never uses the command behaves as it did before this module existed.'),
    ...para('--', r'Because "the workspace" is the key of everything stored, the file also contains the one function in the config that decides what the root of a Rust project is, M.root, and that is why almost every other Rust module requires it.'),
    ...sec(r'the state file: read, write aside, rename'),
    ...code('lua', r'lua/config/rust_context.lua · lines 12-37', r'''
local state_file = vim.fn.stdpath("state") .. "/rust-context.json"

local function read_all()
  local f = io.open(state_file)
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return ok and type(data) == "table" and data or {}
end

local function write_all(data)
  vim.fn.mkdir(vim.fs.dirname(state_file), "p")
  -- write aside and rename: a reader (another nvim) never sees a truncated file
  local tmp = ("%s.%d.tmp"):format(state_file, vim.uv.os_getpid())
  local f = assert(io.open(tmp, "w"))
  f:write(vim.json.encode(data))
  f:close()
  assert(require("config.fsutil").rename(tmp, state_file))
end

local function mtime(path)
  local st = path and vim.uv.fs_stat(path)
  return st and (st.mtime.sec .. "." .. st.mtime.nsec) or "-"
end'''),
    ...para('--', r'The store is one JSON object in stdpath("state"), keyed by workspace root. Reading is forgiving: a missing file, unreadable JSON or JSON of the wrong shape all return an empty table, so a damaged file means "defaults" instead of an error at every startup. Writing is careful. The new content goes to a temporary file whose name includes the process id (so two editors never share a temp file) and is then renamed over the real one. A reader in another Neovim therefore sees the old file or the new file, never a truncated one. The rename goes through fsutil.rename, the shim that retries on Windows when the destination is held open. The mtime helper turns a file’s modification time into a string and returns "-" for a missing file; it is used as a cache key below.'),
    ...sec(r'finding the workspace root'),
    ...code('lua', r'lua/config/rust_context.lua · lines 39-104', r'''
--- Cargo's own answer for the workspace of `dir` (`cargo locate-project
--- --workspace`): knows `members` and `exclude`, so an excluded crate or one
--- with its own [workspace] is its own root. Cached per directory and the
--- modification time of the manifests it was computed from.
local located = {}
local function cargo_workspace(dir, stamp)
  local hit = located[dir]
  if hit and hit.stamp == stamp then
    return hit.root or nil
  end
  local root = false
  if vim.fn.executable("cargo") == 1 then
    local ok, o = pcall(function()
      return vim.system({ "cargo", "locate-project", "--workspace", "--message-format", "plain" }, { cwd = dir, text = true }):wait(5000)
    end)
    local manifest = ok and o and o.code == 0 and vim.trim(o.stdout or "") or ""
    if manifest:match("Cargo%.toml$") then
      root = vim.fs.dirname(manifest)
    end
  end
  located[dir] = { stamp = stamp, root = root }
  return root or nil
end

--- One spelling of a root per directory (the state file is keyed by it):
--- cargo prints backslashes and sometimes a \\?\ prefix, LSP gives file URIs with
--- a lowercase drive letter. Only on Windows; elsewhere the path is untouched.
local function canon(p)
  if p and vim.fn.has("win32") == 1 then
    p = vim.fs.normalize((p:gsub("^\\\\%?\\", "")), { expand_env = false })
    p = p:gsub("^(%a):", function(d)
      return d:lower() .. ":"
    end)
  end
  return p
end

M.canon = canon

--- Workspace root (dir holding the top Cargo.toml) for a path.
function M.root(path)
  return canon(M._root(path))
end

function M._root(path)
  path = path or vim.api.nvim_buf_get_name(0)
  local found = vim.fs.find("Cargo.toml", { upward = true, path = vim.fs.dirname(path) })
  local top
  -- Fallback when cargo cannot answer (no cargo, a manifest that does not
  -- parse): walk up to the outermost Cargo.toml that declares a [workspace]
  for _, f in ipairs(vim.fs.find("Cargo.toml", { upward = true, path = vim.fs.dirname(path), limit = math.huge })) do
    local fh = io.open(f)
    if fh then
      local txt = fh:read("*a")
      fh:close()
      if txt:find("%[workspace") then
        top = f
      end
    end
  end
  local f = top or found[1]
  if not found[1] then
    return nil
  end
  return cargo_workspace(vim.fs.dirname(path), mtime(found[1]) .. "|" .. mtime(top)) or vim.fs.dirname(f)
end'''),
    ...para('--', r'The question "what is the root of this Rust project" has two answers, and the code uses both in order of trust. The best authority is cargo itself: cargo locate-project --workspace prints the manifest of the workspace root and knows about members and exclude lists, so an excluded crate or a crate with its own [workspace] table is correctly its own root. The commit that introduced this is 98c9bb4 (2026-10-13), whose message contains "cargo locate-project root". The call has a five-second limit, runs only if cargo is on the path, and any failure is swallowed in a pcall. The answer is cached per directory together with a stamp, the modification times of the nearest Cargo.toml and of the outermost workspace manifest, so editing a manifest invalidates the cache and ordinary navigation does not spawn cargo again.'),
    ...para('--', r'The fallback is a pure file walk, as the comment says: "when cargo cannot answer (no cargo, a manifest that does not parse)". It finds every Cargo.toml up the tree (limit = math.huge), reads each, and remembers the outermost one that contains a [workspace table; if there is none, the nearest manifest is the root. If there is no Cargo.toml at all, the function returns nil, which every caller turns into the "no Cargo.toml found" message. Notice that the stamp is computed before cargo is asked, using the fallback’s own findings, which is why the cache can be keyed without running anything.'),
    ...para('--', r'canon handles Windows spelling. Cargo prints backslashes and sometimes a \\?\ prefix, while LSP file URIs carry a lower-case drive letter, so the same root has several spellings, and the state file is keyed by root. canon strips the prefix, normalises slashes and lower-cases the drive letter, only on Windows; elsewhere the path is returned untouched. M.root is the public name and wraps the private _root with canon. This is the work of the Windows fixes (9641d08 on 2026-10-16 "drive letter in canonical roots", and 6524272 on 2026-10-21 "drive-letter case in dap/rust_context/crate_meta/macro_attrs, canonical state keys"). M.canon is exported for the other modules that must compare roots the same way.'),
    ...sec(r'reading a context defensively'),
    ...code('lua', r'lua/config/rust_context.lua · lines 106-134', r'''
--- A hand-edited state file may hold anything (`{"features":5,"target":[]}` raised in describe()
--- and ra_cargo()): drop the fields of the wrong type, keep the rest as stored.
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
  return out
end

function M.get(root)
  root = canon(root)
  return root and sanitize(read_all()[root]) or nil
end'''),
    ...para('--', r'The state file is plain JSON that a person can edit, so get() never trusts it. The doc comment names the input that broke an earlier version: {"features":5,"target":[]} raised errors in describe() and ra_cargo(). sanitize drops each field of the wrong type (booleans must be booleans, features must be a list of non-empty strings, target must be a non-empty string) and keeps the rest as stored; the stored value is deep-copied so the cache of read_all is not mutated. This came in the "Final loop round 5" commit (25086fd, 2026-10-14), whose message includes "context sanitising".'),
    ...sec(r'translating a context: three consumers, three vocabularies'),
    ...code('lua', r'lua/config/rust_context.lua · lines 136-190', r'''
--- Settings.cargo table for rust-analyzer.
function M.ra_cargo(ctx)
  if not ctx then
    return nil
  end
  return {
    allFeatures = ctx.all == true,
    noDefaultFeatures = ctx.no_default == true,
    features = (ctx.all and {}) or ctx.features or {},
    target = ctx.target,
  }
end

--- Feature/target CLI flags of a context (nil = the defaults: all features,
--- host target), for the cargo commands the config runs itself.
function M.cargo_flags(ctx)
  local f = {}
  if not ctx or ctx.all then
    f[#f + 1] = "--all-features"
  else
    if ctx.no_default then
      f[#f + 1] = "--no-default-features"
    end
    if ctx.features and #ctx.features > 0 then
      vim.list_extend(f, { "--features", table.concat(ctx.features, ",") })
    end
  end
  if ctx and ctx.target then
    vim.list_extend(f, { "--target", ctx.target })
  end
  return f
end

--- cargo extraArgs for bacon-ls (replaces the hardcoded --all-features).
function M.bacon_args(ctx)
  return vim.list_extend(vim.list_extend({ "--workspace" }, M.cargo_flags(ctx)), { "--no-deps", "--keep-going" })
end

--- Human-readable summary, e.g. "features: ssr,csr | target: wasm32-unknown-unknown".
function M.describe(ctx)
  if not ctx or (ctx.all and not ctx.target) then
    return "all features, host target"
  end
  local parts = {}
  if ctx.all then
    parts[#parts + 1] = "all features"
  else
    parts[#parts + 1] = "features: " .. ((ctx.features and #ctx.features > 0) and table.concat(ctx.features, ",") or "(none)")
    if ctx.no_default then
      parts[#parts + 1] = "no default"
    end
  end
  parts[#parts + 1] = "target: " .. (ctx.target or "host")
  return table.concat(parts, " | ")
end'''),
    ...para('--', r'One stored context becomes three different shapes. For rust-analyzer it is a settings.cargo table (allFeatures, noDefaultFeatures, a features list, a target); when all is true the features list is forced empty, since all features already include every other. For cargo commands run by this config (tests, flamegraphs, coverage) it is a list of flags: --all-features if the context is nil or has all set, otherwise --no-default-features and --features a,b, then --target when there is one. For bacon-ls it is the cargo extra arguments: --workspace, the flags, then --no-deps and --keep-going, in that order, which the spec pins ("is --workspace, the context flags, --no-deps in that order"). The doc comment on bacon_args notes that it replaces a hard-coded --all-features. describe produces the text shown in notifications and picker titles, with the default phrased as "all features, host target".'),
    ...para('--', r'A nil context and a context with all set and no target all mean the same thing, "the defaults", and the code treats them identically. That is what lets :RustContext reset store nothing at all.'),
    ...sec(r'does this client serve this root?'),
    ...code('lua', r'lua/config/rust_context.lua · lines 192-219', r'''
local function cargo_metadata(root)
  local o = vim.system({ "cargo", "metadata", "--format-version", "1", "--no-deps" }, { cwd = root, text = true }):wait(30000)
  if o.code ~= 0 then
    return nil, o.stderr
  end
  return vim.json.decode(o.stdout)
end

--- Push ctx into the running rust-analyzer and restart bacon-ls with matching args.
--- `ctx == nil` resets to the defaults (all features, host target) and forgets the stored choice.
--- Whether a client serves the workspace `root`: its root_dir, or any workspace
--- folder (rustaceanvim attaches a further workspace's buffers to the ONE
--- running rust-analyzer as an added folder; its root_dir stays the first's).
local function serves(c, root)
  root = canon(root)
  local function is(dir)
    return dir ~= nil and M.root(dir .. "/x") == root
  end
  if is(c.config.root_dir) then
    return true
  end
  for _, wf in ipairs(c.workspace_folders or {}) do
    if is(wf.uri and vim.uri_to_fname(wf.uri)) then
      return true
    end
  end
  return false
end'''),
    ...para('--', r'There is a documentation slip in this part of the file, and it is worth showing as it stands. The two doc-comment lines "Push ctx into the running rust-analyzer and restart bacon-ls with matching args" sit above the function serves, and the description of apply is merged into serves’ own comment. They belong to M.apply further down. The code is unaffected; only the comment is misplaced.'),
    ...para('--', r'serves answers a real problem. rustaceanvim runs one rust-analyzer per session and attaches buffers of a second workspace to it as an added workspace folder, while the client’s root_dir stays the first one. A test on root_dir alone would think the second workspace has no server and the context would never reach it. So a client serves a root if its root_dir resolves to that root, or if any of its workspace folders does. The check resolves a directory by asking M.root about a fictitious file "x" inside it, so the same cargo-based logic decides both sides of the comparison.'),
    ...sec(r'store: a lock file, because two editors share one state file'),
    ...code('lua', r'lua/config/rust_context.lua · lines 221-254', r'''
--- Read, set one key, write, under a lock file: two nvims applying at once each read the
--- old file and the later rename dropped the other's key (8 nvims x 20 applies kept 79 of
--- 160). A lock older than 5s is a dead owner's; after ~2s without it the write goes on.
local function store(root, ctx)
  root = canon(root)
  local lock = state_file .. ".lock"
  -- (mkdir "p" raises E739 when another nvim creates the dir between its stat and mkdir)
  pcall(vim.fn.mkdir, vim.fs.dirname(state_file), "p")
  local fd
  for _ = 1, 400 do
    fd = vim.uv.fs_open(lock, "wx", 420)
    if fd then
      break
    end
    local st = vim.uv.fs_stat(lock)
    if st and os.time() - st.mtime.sec > 5 then
      vim.uv.fs_unlink(lock)
    else
      vim.uv.sleep(5)
    end
  end
  local ok, err = pcall(function()
    local all = read_all()
    all[root] = ctx
    write_all(all)
  end)
  if fd then
    vim.uv.fs_close(fd)
    vim.uv.fs_unlink(lock)
  end
  if not ok then
    error(err, 0)
  end
end'''),
    ...para('--', r'Write-aside-and-rename protects readers but not writers. Two editors that each read the whole file, change one key and write it back will lose one of the changes: the later rename wins. The comment has the measurement from the bug report: "8 nvims x 20 applies kept 79 of 160". The cure is a lock. Creating the lock file with the "wx" flag is atomic (it fails if the file exists), so whoever creates it owns the critical section: read, set the one key, write, release. A loop of up to 400 attempts sleeps 5 ms between tries, which is about two seconds; a lock whose mtime is older than 5 seconds is assumed to belong to a dead process and is removed. If the 400 attempts run out, the write goes ahead without the lock (the comment: "after ~2s without it the write goes on"), a deliberate choice of availability over strictness: losing a feature selection is better than a frozen editor. The critical section is inside a pcall so that the lock is always released, and the error is re-thrown afterwards with level 0. The spec that pins this is called "concurrent nvims applying different roots lose none (8 x 15 applies; was 79 of 160 without the lock)".'),
    ...sec(r'apply: change the running servers, not only the file'),
    ...code('lua', r'lua/config/rust_context.lua · lines 256-277', r'''
function M.apply(root, ctx)
  store(root, ctx)
  local eff = ctx or { all = true, features = {} }
  for _, c in ipairs(vim.lsp.get_clients({ name = "rust-analyzer" })) do
    if serves(c, root) then
      local ra = c.settings["rust-analyzer"]
      ra.cargo = vim.tbl_extend("force", ra.cargo or {}, M.ra_cargo(eff))
      ra.cargo.target = eff.target -- nil clears it
      c:notify("workspace/didChangeConfiguration", { settings = c.settings })
    end
  end
  vim.schedule(function()
    pcall(vim.cmd.RustLsp, "reloadWorkspace")
    for _, c in ipairs(vim.lsp.get_clients({ name = "bacon_ls" })) do
      if serves(c, root) then
        vim.cmd("lsp restart bacon_ls")
        break
      end
    end
  end)
  vim.notify("Rust context: " .. M.describe(eff))
end'''),
    ...para('--', r'Applying a context does four things in order. It stores the choice (a nil context removes the stored entry, because it writes nil under the key). It updates the settings table of every rust-analyzer client that serves the root and sends workspace/didChangeConfiguration, with one extra line: ra.cargo.target is set explicitly, with the comment "nil clears it", because a table merge by vim.tbl_extend would keep an old target when the new context has none. Then, scheduled, it asks rustaceanvim to reload the workspace (in a pcall, as the command may not exist) and restarts bacon-ls, once, if it serves that root. bacon-ls cannot take new arguments live, so it needs a restart for its before_init hook to rebuild them. Finally a notification says what is now in effect.'),
    ...sec(r'the picker and the command'),
    ...code('lua', r'lua/config/rust_context.lua · lines 279-339', r'''
--- Interactive picker: features (multi-select with <Tab>), then target.
function M.pick()
  local root = M.root()
  if not root then
    return vim.notify("no Cargo.toml found", vim.log.levels.WARN)
  end
  local meta, err = cargo_metadata(root)
  if not meta then
    return vim.notify("cargo metadata failed: " .. tostring(err), vim.log.levels.ERROR)
  end
  local cur = M.get(root) or { all = true }
  local items = {
    { text = "* all features", special = "all" },
    { text = "* default features only (clears the list)", special = "default" },
    { text = "* no-default-features", special = "nodefault" },
  }
  local multi = #meta.packages > 1
  for _, p in ipairs(meta.packages) do
    local names = vim.tbl_keys(p.features)
    table.sort(names)
    for _, f in ipairs(names) do
      if f ~= "default" then
        local q = multi and (p.name .. "/" .. f) or f
        items[#items + 1] = { text = q, feature = q }
      end
    end
  end
  Snacks.picker({
    title = "Cargo features (<Tab> multi-select) - now: " .. M.describe(cur),
    items = items,
    format = "text",
    layout = { preset = "select" },
    confirm = function(picker)
      local sel = picker:selected({ fallback = true })
      picker:close()
      local ctx = { all = false, no_default = false, features = {}, target = cur.target }
      for _, it in ipairs(sel) do
        if it.special == "all" then
          ctx.all = true
        elseif it.special == "nodefault" then
          ctx.no_default = true
        elseif it.feature then
          ctx.features[#ctx.features + 1] = it.feature
        end
      end
      local targets = { "(host default)" }
      local o = vim.system({ "rustup", "target", "list", "--installed" }, { text = true }):wait(10000)
      for t in (o.stdout or ""):gmatch("[^\n]+") do
        targets[#targets + 1] = t
      end
      vim.schedule(function()
        vim.ui.select(targets, { prompt = "Target (currently " .. (cur.target or "host") .. ")" }, function(choice)
          if choice then
            ctx.target = choice ~= "(host default)" and choice or nil
            M.apply(root, ctx)
          end
        end)
      end)
    end,
  })
end'''),
    ...para('--', r'The picker is a two-step wizard. Step one lists three special rows (all features, default features only, no-default-features) and then every feature of every package from cargo metadata --no-deps, with the default feature itself left out. In a multi-package workspace features are prefixed with the package (pkg/feature), the form cargo accepts, and in a single crate they are bare. The user multi-selects with Tab; with no selection the row under the cursor counts (fallback = true). Step two asks for a target: the list is "(host default)" plus whatever rustup target list --installed prints, shown with vim.ui.select. The existing target is kept when only features change: the context starts from target = cur.target. The title of the first picker shows the current context, so the user sees what they are replacing. If cargo metadata fails, the user gets its stderr in an ERROR.'),
    ...para('--', r'The "default features only" row has no branch in the confirm function: the code only handles the special values all and nodefault, so choosing it yields a context with all = false, no features and no_default = false, which is cargo’s defaults. That is exactly what its label promises ("clears the list").'),
    ...code('lua', r'lua/config/rust_context.lua · lines 341-371', r'''
function M.reset()
  local root = M.root()
  if not root then
    return vim.notify("no Cargo.toml found: nothing to reset", vim.log.levels.WARN)
  end
  M.apply(root, nil)
end

function M.setup()
  vim.api.nvim_create_user_command("RustContext", function(a)
    if a.args == "reset" then
      M.reset()
    elseif a.args == "show" then
      local root = M.root()
      if not root then
        return vim.notify("no Cargo.toml found", vim.log.levels.WARN)
      end
      vim.notify("Rust context: " .. M.describe(M.get(root)))
    elseif a.args ~= "" then
      vim.notify("RustContext: unknown argument '" .. a.args .. "' (use show or reset, or no argument for the picker)", vim.log.levels.WARN)
    else
      M.pick()
    end
  end, {
    nargs = "?",
    complete = function()
      return { "show", "reset" }
    end,
    desc = "Pick cargo features / target for rust-analyzer + bacon-ls",
  })
end'''),
    ...para('--', r':RustContext with no argument opens the picker, show prints the stored context for the current workspace and reset forgets it. Any other argument gets a warning that spells out the usage: that branch is from "RustContext args" in the Final loop round 4 commit (f31e013, 2026-10-14). The key <leader>rF opens it from the Rust key group.'),
    ...sec(r'what differs in xyno-rust.nvim'),
    ...para('--', r'The standalone copy (lua/xyno_rust/rust_context.lua) differs in three ways, all of them library manners. It requires xyno_rust.fsutil for the rename. Its pick() starts by asking xyno_rust.deps for Snacks and returns quietly if the picker plugin is not installed, where this version uses the global Snacks. And setup(opts) returns early without defining :RustContext when opts.commands is false, so a host that wants its own command can have the module without the default. The root, state, lock and translation logic are the same. This config still loads its own copy.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/rust-context_spec.lua (53 it() blocks, 1169 lines) has a describe for each part: root (the cargo-based answer and the fallback), the state file (round trips, damaged files, the concurrency test against several real Neovim processes), ra_cargo, cargo_flags, bacon_args, describe, apply without servers, the :RustContext command, the picker (cargo metadata is called with a 30 second wait, features are prefixed in workspaces and sorted, confirm lists installed rustup targets, choosing the host target clears the stored one), the glue in the rustaceanvim and bacon-ls specs, and a last section with live servers. The tests for how other modules use the context live in tests/rust-tasks-tools_spec.lua.'),
    ...sec(r'history'),
    ...pt('--', r'f5936dc · 2026-10-09', r'the first version of the file.'),
    ...pt('--', r'be73b6c · 2026-10-12', r'Rust workflow robustness: bacon-ls workspace root, server supervision.'),
    ...pt('--', r'a3d33c8 · 2026-10-13', r'Final loop round 2: the message names "rust-context lock", the lock file in store().'),
    ...pt('--', r'98c9bb4 · 2026-10-13', r'Final loop round 1: cargo locate-project root.'),
    ...pt('--', r'3f868dd · 2026-10-13', r'Final loop round 3.'),
    ...pt('--', r'f31e013 · 2026-10-14', r'Final loop round 4: RustContext args.'),
    ...pt('--', r'25086fd · 2026-10-14', r'Final loop round 5: context sanitising.'),
    ...pt('--', r'ff1c8fa · 2026-10-16', r'Windows and macOS: portability fixes.'),
    ...pt('--', r'9641d08 · 2026-10-16', r'drive letter in canonical roots, realpath temp dirs.'),
    ...pt('--', r'6524272 · 2026-10-21', r'drive-letter case and canonical state keys.'),
    ...pt('--', r'0247401 · 2026-10-22', r'Positioning: the first header line changed from naming RustRover’s Cargo tool window to "inspired by the Cargo tool window".'),
  ],
);
