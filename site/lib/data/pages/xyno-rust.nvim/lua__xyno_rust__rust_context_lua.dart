import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/lua/xyno_rust/rust_context.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust_context.lua - one answer to "which features, which target"'),
    cm('--', r'stored per workspace, applied to rust-analyzer and bacon-ls together'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'per-project Cargo context: features and target, shared by every tool that runs cargo'),
    kv(r'language', r'Lua'),
    kv(r'size', r'381 lines, one ancestor: lua/config/rust_context.lua in xynovim (first commit f5936dc, 2026-10-09)'),
    kv(r'command', r':RustContext, :RustContext show, :RustContext reset'),
    kv(r'state', r'stdpath("state")/rust-context.json, keyed by workspace root'),
    kv(r'tested by', r'tests/rust-context_spec.lua (1,027 lines)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The header comment of the file states the problem in three lines. rust-analyzer and bacon-ls, the clippy tier that runs cargo on every edit, both build the project. If they are configured with different features or a different target, then a crate with mutually exclusive features gets bogus errors from whichever server was told the wrong thing. The fix is not clever: there must be exactly one choice per workspace, stored where both servers can read it, and every consumer must derive its arguments from that one value.'),
    ...code('lua', r'lua/xyno_rust/rust_context.lua · lines 1-9', r'''
-- Per-project Cargo "context" (features / target), inspired by the Cargo tool
-- window toggles. rust-analyzer and bacon-ls (the clippy tier) must agree on
-- both, otherwise mutually exclusive features give bogus errors from one tier.
-- Stored per workspace root in stdpath("state"); applied at server start
-- (rustaceanvim `server.settings`, bacon_ls `before_init`) and live by
-- :RustContext.
--
-- ctx = { all = boolean, no_default = boolean, features = string[], target = string? }
-- Default (nothing stored): all features, host target - i.e. the old behaviour.'''),
    ...para('--', r'The first line says the module is inspired by the Cargo tool window toggles, and the README names the source of that inspiration as the Cargo tool window of the JetBrains IDEs. The default when nothing is stored is stated in the comment: all features, host target, the comment calls this “the old behaviour”, so a project that never opens the picker behaves as it did before the module existed.'),
    ...sec(r'the shape of a context'),
    ...para('--', r'A context is a plain table: { all = boolean, no_default = boolean, features = string[], target = string? }. Three small functions turn it into the argument shapes the different consumers want. They are pure functions of the table, which is why the spec can check them without any server.'),
    ...code('lua', r'lua/xyno_rust/rust_context.lua · lines 136-173', r'''
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
end'''),
    ...para('--', r'ra_cargo produces the Settings.cargo table that rust-analyzer expects (allFeatures, noDefaultFeatures, features, target). cargo_flags produces CLI flags for commands the plugin runs itself, with --all-features as the default for a nil context. bacon_args is a composition: --workspace, then the context flags, then --no-deps and --keep-going, in that order, which the spec pins ("is --workspace, the context flags, --no-deps in that order"). The comment on bacon_args says what it replaced: a hard-coded --all-features in the bacon-ls configuration of xynovim. rust_tasks and the doctests runner use cargo_flags too, so :RustTargets, :RustTools and the doctest key build with the same features as the diagnostics.'),
    ...sec(r'finding the workspace root'),
    ...para('--', r'Everything is keyed by workspace root, so root() matters. The first version walked upward to the outermost Cargo.toml containing a [workspace] table; that survives in the code as a fallback. The primary answer is cargo’s own.'),
    ...code('lua', r'lua/xyno_rust/rust_context.lua · lines 39-61', r'''
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
end'''),
    ...para('--', r'cargo locate-project --workspace knows about members and exclude, which a text scan of Cargo.toml files cannot: an excluded crate, or one with its own [workspace], is its own root. The result is cached per directory together with a stamp of the modification times of the manifests it was computed from (mtime builds the stamp), so editing a manifest invalidates the entry but pressing a key a thousand times does not spawn a thousand cargos. Failure is quiet by design: no cargo on PATH, a five second timeout, a manifest that does not parse, or output that does not end in Cargo.toml all fall through to the Lua walk. The spec names the case: "an excluded crate and one with its own [workspace] are their own root (cargo locate-project)". In xynovim the change arrived in the first round of field-test fixes (98c9bb4, 2026-10-13, whose subject lists "cargo locate-project root").'),
    ...code('lua', r'lua/xyno_rust/rust_context.lua · lines 78-81', r'''
--- Workspace root (dir holding the top Cargo.toml) for a path.
function M.root(path)
  return canon(M._root(path))
end'''),
    ...sec(r'one spelling of a path'),
    ...code('lua', r'lua/xyno_rust/rust_context.lua · lines 63-76', r'''
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

M.canon = canon'''),
    ...para('--', r'The state file is a map from path to context, so two spellings of one directory would be two entries. The comment names where the spellings come from on Windows: cargo prints backslashes and sometimes a \\?\ prefix, while LSP gives file URIs with a lowercase drive letter. canon normalises both, and does so only on Windows; elsewhere the path is returned untouched, which matters because a Linux path may contain characters that normalisation would change. canon is exported (M.canon) because crate_meta and the sibling plugins need the same key. In xynovim the drive-letter case was fixed in 9641d08 (2026-10-16) and again in 6524272 (2026-10-21), both after Windows CI runs showed the mismatch.'),
    ...sec(r'a state file that anyone may edit'),
    ...code('lua', r'lua/xyno_rust/rust_context.lua · lines 106-129', r'''
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
end'''),
    ...para('--', r'The state file is JSON in the user’s state directory, so it can be edited by hand or truncated. sanitize drops fields of the wrong type and keeps the rest as stored. The comment records the bug it fixed: a stored { "features": 5, "target": [] } used to raise inside describe() and ra_cargo(). The reading side is equally defensive (read_all returns an empty table for a missing file, invalid JSON or JSON that is not a table), and the spec has the cases "reads as empty when the file is missing, invalid or not a table" and "does not raise on a corrupt file and overwrites it on the next apply".'),
    ...sec(r'writing without losing a neighbour'),
    ...code('lua', r'lua/xyno_rust/rust_context.lua · lines 24-32', r'''
local function write_all(data)
  vim.fn.mkdir(vim.fs.dirname(state_file), "p")
  -- write aside and rename: a reader (another nvim) never sees a truncated file
  local tmp = ("%s.%d.tmp"):format(state_file, vim.uv.os_getpid())
  local f = assert(io.open(tmp, "w"))
  f:write(vim.json.encode(data))
  f:close()
  assert(require("xyno_rust.fsutil").rename(tmp, state_file))
end'''),
    ...code('lua', r'lua/xyno_rust/rust_context.lua · lines 221-254', r'''
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
    ...para('--', r'Two defences, for two different races. write_all never writes the real file in place: it writes a temp file named with the process id and renames it, so a reader in another Neovim never sees a truncated file (the spec checks there is no leftover temp file). The rename goes through fsutil.rename, which retries on Windows. The second race is a lost update: two Neovim instances each read the old map, set their own key, and the later rename drops the other key. The comment gives the measurement that motivated the lock: 8 nvims times 20 applies kept 79 of 160 entries. The fix is a lock file created with the "wx" flag (fail if it exists), retried up to 400 times with a 5 ms sleep (about two seconds). A lock older than five seconds is treated as the leftover of a dead owner and removed; if the lock cannot be taken after the loop, the write goes on anyway, because losing the lock is better than refusing to save the user’s choice. The lock is released in all paths, and an error inside the guarded block is re-raised after the release. The regression spec is named after the number: "concurrent nvims applying different roots lose none (8 x 15 applies; was 79 of 160 without the lock)".'),
    ...sec(r'applying a context to the running servers'),
    ...code('lua', r'lua/xyno_rust/rust_context.lua · lines 202-219', r'''
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
    ...para('--', r'serves answers "does this rust-analyzer instance serve that workspace?" by comparing roots. A client counts if its root_dir resolves to the workspace or if any of its workspace_folders does. The second branch exists for rustaceanvim, which attaches a further workspace’s buffers to the one running rust-analyzer as an added folder while its root_dir stays the first one.'),
    ...code('lua', r'lua/xyno_rust/rust_context.lua · lines 256-277', r'''
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
    ...para('--', r'apply is the whole mechanism in about twenty lines. It stores the choice first, so even if nothing is running the next server start picks it up. For each matching rust-analyzer client it mutates c.settings in place, merges the new cargo table (setting target explicitly so that nil clears it) and sends workspace/didChangeConfiguration. Then, scheduled, it asks rustaceanvim to reloadWorkspace (inside pcall, so it is harmless without rustaceanvim) and restarts bacon-ls with the built-in :lsp restart, but only once and only when a bacon_ls client serves this workspace. ctx == nil is the reset path: the stored value becomes nil and the effective context falls back to all features. The final notification prints the effective context through describe.'),
    ...sec(r'the picker'),
    ...code('lua', r'lua/xyno_rust/rust_context.lua · lines 280-310', r'''
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
  local Snacks = require("xyno_rust.deps").snacks()
  if not Snacks then
    return
  end
  Snacks.picker({'''),
    ...para('--', r'The picker is built from cargo metadata --no-deps, with a 30 second wait. Three special entries come first (all features, default features only, no-default-features) and then every feature of every package. In a multi-package workspace features are qualified as package/feature, because that is what cargo --features accepts; in a single package they are bare. The default feature is skipped, since it is what "default features only" already means. The title carries the current context so the user sees what they are changing. After confirm (not shown here) a second step lists (host default) plus the targets from rustup target list --installed and applies the pair.'),
    ...sec(r'the command'),
    ...code('lua', r'lua/xyno_rust/rust_context.lua · lines 354-379', r'''
function M.setup(opts)
  if opts and opts.commands == false then
    return
  end
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
    ...para('--', r'Unknown arguments warn with the usage rather than opening the picker, so a typo of reset does not silently open a dialog. commands = false skips the definition entirely, which is what lets another plugin use the module as a library.'),
    ...sec(r'failure modes handled'),
    ...pt('--', r'no Cargo.toml', r'root() returns nil; pick, reset and show each warn "no Cargo.toml found" instead of erroring.'),
    ...pt('--', r'cargo metadata fails', r'an ERROR notification with cargo’s stderr.'),
    ...pt('--', r'no snacks', r'the picker returns after deps.snacks() has printed its one line.'),
    ...pt('--', r'corrupt or hand-edited state', r'sanitised or treated as empty.'),
    ...pt('--', r'parallel Neovims', r'lock file plus atomic rename.'),
    ...sec(r'history'),
    ...para('--', r'In xynovim the file went through the project history like this: first appearance in f5936dc (2026-10-09, a work-in-progress commit); the supervision commit be73b6c (2026-10-12) made bacon-ls root at the Cargo workspace and rebuild its settings on reset; the field-test rounds of 2026-10-13 and 2026-10-14 added the cargo locate-project root, the lock, and the sanitising; the portability work of 2026-10-16 and 2026-10-21 (ff1c8fa, 9641d08, 6524272) added the Windows path canonicalisation; and 0247401 (2026-10-22, subject “Positioning: a personal project inspired by JetBrains, not a competitor”) reworded the first header line from naming RustRover’s Cargo tool window to “inspired by the Cargo tool window toggles”. It was copied into this repository in c1c7958 with the namespace changed from config to xyno_rust and the snacks call routed through deps.lua.'),
  ],
);
