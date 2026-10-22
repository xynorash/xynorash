import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/lua/xyno_rust/crate_meta.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'crate_meta.lua - what Neovim knows about crates'),
    cm('--', r'cargo metadata, registry sources, a crates.io client, and "does this name exist?"'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'headless data layer for the dependency and macro plugins (no UI)'),
    kv(r'language', r'Lua (vim.system, vim.json, curl as a subprocess)'),
    kv(r'size', r'899 lines; 881 in xynovim at birth (6e1b567, 2026-10-14)'),
    kv(r'public', r'metadata, metadata_async, invalidate, normalize, dependencies, member_of, root, registry_dir, source_dir, read_manifest, read_lib, parse_features, info, info_async, search, search_async, index_path, parse_index, valid_name, valid_version, compare_versions, is_known_path_head, exec, config, std_crates'),
    kv(r'tested by', r'tests/crate-meta_spec.lua (942 lines, ten describe blocks)'),
    ...sec(r'why this file exists'),
    ...para('--', r'Features such as "add this crate", "enable the missing feature", "complete this derive", "import this symbol" all begin with the same questions. What are the workspace members? What does each depend on, and with which features? Where are the sources of a dependency on disk? What is the newest version of a crate on crates.io, and which features does it declare? Is the first segment of this path something that exists at all? The header says this file answers all of them in one place with no UI, and it names the four areas. The sibling plugins xyno-crates.nvim, xyno-imports.nvim and xyno-macros.nvim require it, which is why it lives in the base plugin.'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 1-16', r'''
-- Everything the dependency and macro features need to know about crates, in
-- one place (no UI here):
--   * cargo metadata of a workspace (cached, members + dependencies + the
--     resolved package of each dependency with its full [features] table)
--   * the unpacked sources of a crate (~/.cargo/registry/src, git checkouts
--     and path deps through the metadata manifest_path)
--   * a small crates.io client (sparse index for exact names, the web API for
--     search), curl with an argv list, cached on disk, offline-tolerant
--   * is_known_path_head(): is this first path segment something that exists
--
-- Conventions: functions that can wait come in pairs, `foo_async(..., cb)` and
-- a blocking `foo(...)` built on it. They return `result, err` (never raise
-- for network, tool or file problems); `err` is a plain string. Names and
-- versions that come from the network or from files are validated before they
-- reach an argv or a path.
local M = {}'''),
    ...para('--', r'The last paragraph of the header is the contract and it is worth reading twice. Functions that can wait come in pairs, foo_async(..., cb) and a blocking foo(...) built on top of it. They return result, err and never raise for network, tool or file problems. And every name or version that comes from the network or from a file is validated before it reaches an argv or a path. The rest of the file follows these three rules.'),
    ...sec(r'configuration and the test seams'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 18-32', r'''
M.config = {
  timeout_ms = 5000, -- one curl call (curl --max-time)
  metadata_timeout_ms = 60000, -- cargo metadata (may have to resolve)
  index_ttl = 3600, -- seconds a cached index answer is fresh
  search_ttl = 600,
  index_url = "https://index.crates.io",
  api_url = "https://crates.io/api/v1",
  proto = "=https", -- curl --proto; specs point the URLs at file:// and set "=file"
  user_agent = "xyno-rust.nvim (github.com/xynorash/xyno-rust.nvim)",
  cache_dir = nil, -- default stdpath("cache")/xyno-rust/crates
  cargo_home = nil, -- default $CARGO_HOME or ~/.cargo
}

-- JSON null -> nil (vim.NIL is truthy and breaks `x or default`)
local JSON_OPTS = { luanil = { object = true, array = true } }'''),
    ...para('--', r'Everything tunable is in M.config: timeouts (5 s for one curl call, 60 s for cargo metadata, which may have to resolve), the cache lifetimes (an hour for the index, ten minutes for search), the two crates.io URLs, the curl protocol restriction, the user agent that carries the plugin name, and the cache and cargo home directories. The comment on proto explains a testing decision: the specs point the URLs at file:// and set proto to =file, so a "real curl" spec runs without a network. JSON_OPTS makes vim.json.decode return nil for JSON null; the comment gives the reason, vim.NIL is truthy and breaks x or default.'),
    ...sec(r'validation first'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 36-77', r'''
--- A crate name as crates.io allows it (and nothing a shell or a path could
--- misread).
function M.valid_name(name)
  return type(name) == "string" and #name > 0 and #name <= 64 and name:match("^[A-Za-z0-9_-]+$") ~= nil
end

--- semver-ish: 1.2.3, 1.2.3-rc.1, 1.2.3+build
function M.valid_version(v)
  return type(v) == "string" and #v <= 64 and v:match("^%d+%.%d+%.%d+[A-Za-z0-9.+-]*$") ~= nil
end

local function parse_version(v)
  local a, b, c, pre = tostring(v):match("^(%d+)%.(%d+)%.(%d+)(.*)$")
  if not a then
    return nil
  end
  pre = pre:match("^%-([^+]*)")
  return { tonumber(a), tonumber(b), tonumber(c), pre }
end

--- -1 / 0 / 1; a release is newer than its pre-releases; unparsable sorts first.
function M.compare_versions(x, y)
  local a, b = parse_version(x), parse_version(y)
  if not a or not b then
    return (a and 1 or 0) - (b and 1 or 0)
  end
  for i = 1, 3 do
    if a[i] ~= b[i] then
      return a[i] < b[i] and -1 or 1
    end
  end
  if a[4] == b[4] then
    return 0
  end
  if not a[4] then
    return 1
  end
  if not b[4] then
    return -1
  end
  return a[4] < b[4] and -1 or 1
end'''),
    ...para('--', r'valid_name allows letters, digits, underscore and dash up to 64 characters: the doc comment says “nothing a shell or a path could misread”. valid_version accepts 1.2.3 plus pre-release and build suffixes. compare_versions is a deliberately small semver: three numbers, then the pre-release text, with the documented rules that a release is newer than its pre-releases and an unparsable version sorts first. It compares pre-release strings as plain strings, not as semver identifiers, which is a simplification the code does not hide.'),
    ...sec(r'running processes'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 81-105', r'''
--- Run argv. With `cb` it is asynchronous (cb(result) on the main loop),
--- without it blocks. result = { code, stdout, stderr } (code -1 on a spawn
--- failure or timeout). Specs replace this to fake cargo and curl.
function M.exec(argv, opts, cb)
  opts = opts or {}
  local function finish(r)
    return { code = r.code, stdout = r.stdout or "", stderr = r.stderr or "" }
  end
  local ok, res = pcall(vim.system, argv, { text = true, cwd = opts.cwd, timeout = opts.timeout }, cb and vim.schedule_wrap(function(r)
    cb(finish(r))
  end) or nil)
  if not ok then
    local r = { code = -1, stdout = "", stderr = tostring(res) }
    if cb then
      vim.schedule(function()
        cb(r)
      end)
      return
    end
    return r
  end
  if not cb then
    return finish(res:wait())
  end
end'''),
    ...para('--', r'exec is the one place that spawns processes. With a callback it is asynchronous (the callback is scheduled onto the main loop); without it blocks. Spawn failures and timeouts come back as code -1 instead of an error, and the comment says why the function is public: specs replace M.exec to fake cargo and curl. The comment on exec names that purpose.'),
    ...sec(r'reading files that may be hostile'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 109-137', r'''
local MAX_READ = 2 * 1024 * 1024 -- source and manifest files; bigger is not a real one

-- Regular files only: a symlink to /dev/zero exhausts memory and a FIFO blocks the main thread
-- (dependency sources, git and path ones included, are untrusted).
local function read_file(path)
  local st = vim.uv.fs_stat(path)
  if not st or st.type ~= "file" or st.size > MAX_READ then
    return nil
  end
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local s = f:read("*a")
  f:close()
  return s
end

local function write_file(path, data)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local tmp = ("%s.%d.tmp"):format(path, vim.uv.os_getpid())
  local f = io.open(tmp, "wb")
  if not f then
    return false
  end
  f:write(data)
  f:close()
  return require("xyno_rust.fsutil").rename(tmp, path) and true or false
end'''),
    ...para('--', r'Dependency sources, including git and path dependencies, are untrusted. read_file therefore refuses anything that is not a regular file (a symlink to /dev/zero would exhaust memory; a FIFO would block the main thread) and anything over 2 MiB. The last describe block of the spec, "crate_meta bounded reads", checks it. write_file writes a temp file with the pid and renames it through fsutil, so a half-written cache entry is never read.'),
    ...sec(r'cargo metadata'),
    ...para('--', r'normalize turns cargo’s JSON into a shape the features want: members (with their targets and a lib_name, where dashes become underscores because that is how code names the crate), dependencies, packages and a by_name index.'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 181-232', r'''
--- cargo's JSON -> { root, members, dependencies, packages, by_name }
function M.normalize(raw, root)
  local by_id, nodes = {}, {}
  local member_ids = {}
  for _, id in ipairs(raw.workspace_members or {}) do
    member_ids[id] = true
  end
  local packages, by_name = {}, {}
  for _, p in ipairs(raw.packages or {}) do
    local rec = {
      name = p.name,
      version = p.version,
      id = p.id,
      manifest_path = p.manifest_path,
      dir = dir_of(p.manifest_path),
      source = p.source,
      features = p.features or {},
      is_member = member_ids[p.id] or false,
      _raw = p,
    }
    by_id[p.id] = rec
    packages[#packages + 1] = rec
    by_name[p.name] = by_name[p.name] or {}
    table.insert(by_name[p.name], rec)
  end
  for _, n in ipairs(raw.resolve and raw.resolve.nodes or {}) do
    nodes[n.id] = n
  end

  local members, dependencies = {}, {}
  for _, p in ipairs(packages) do
    if p.is_member then
      local m = {
        name = p.name,
        version = p.version,
        id = p.id,
        manifest_path = p.manifest_path,
        dir = p.dir,
        features = p.features,
        targets = {},
        lib_name = nil,
      }
      for _, t in ipairs(p._raw.targets or {}) do
        m.targets[#m.targets + 1] = { name = t.name, kind = t.kind, src_path = t.src_path, edition = t.edition }
        for _, k in ipairs(t.kind or {}) do
          if LIB_KINDS[k] then
            m.lib_name = t.name:gsub("%-", "_")
          end
        end
      end
      members[#members + 1] = m
      local node = nodes[p.id]'''),
    ...para('--', r'The dependency half joins two views of the same data. A member’s declared dependencies (requirement, kind, optional, features, rename, target) come from the package record; the resolved package of each one comes from the resolve graph node of that member, found by comparing the alias, the dependency kind and the package name. The result is attached as resolved, with enabled_features from the node. This is what lets a feature plugin answer both "which features may I enable on serde" and "which are on right now".'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 286-351', r'''
local function run_metadata(root, cb)
  local manifest = root .. "/Cargo.toml"
  local base = { "cargo", "metadata", "--format-version", "1", "--manifest-path", manifest }
  local function parse(r)
    if r.code ~= 0 then
      return nil, vim.trim(r.stderr) ~= "" and vim.trim(r.stderr) or ("cargo metadata exited " .. r.code)
    end
    local ok, raw = pcall(vim.json.decode, r.stdout, JSON_OPTS)
    if not ok or type(raw) ~= "table" then
      return nil, "cargo metadata printed no JSON"
    end
    local ok2, meta = pcall(M.normalize, raw, root)
    if not ok2 then
      return nil, "cannot read cargo metadata: " .. tostring(meta)
    end
    return meta
  end
  local opts = { cwd = root, timeout = M.config.metadata_timeout_ms }
  -- offline first: deterministic and fast when the registry already has the
  -- crates; the online run only happens when that cannot resolve
  local offline = vim.list_extend(vim.deepcopy(base), { "--offline" })
  M.exec(offline, opts, function(r1)
    local meta, err = parse(r1)
    if meta then
      return cb(meta)
    end
    M.exec(base, opts, function(r2)
      local m2, e2 = parse(r2)
      cb(m2, e2 or err)
    end)
  end)
end

--- cargo metadata of the workspace at `root` (a directory or any file in it);
--- cached until a Cargo.toml (workspace or member) or Cargo.lock changes.
--- cb(meta) or cb(nil, err).
function M.metadata_async(root, cb, opts)
  opts = opts or {}
  root = M.root(root)
  if not root then
    return vim.schedule(function()
      cb(nil, "not in a cargo workspace")
    end)
  end
  local hit = cache[root]
  if hit and not opts.refresh and hit.stamp == stamp_of(root, hit.meta) then
    return vim.schedule(function()
      cb(hit.meta)
    end)
  end
  if pending[root] then
    table.insert(pending[root], cb)
    return
  end
  pending[root] = { cb }
  run_metadata(root, function(meta, err)
    local cbs = pending[root]
    pending[root] = nil
    if meta then
      cache[root] = { stamp = stamp_of(root, meta), meta = meta }
    end
    for _, f in ipairs(cbs) do
      f(meta, err)
    end
  end)
end'''),
    ...para('--', r'run_metadata tries cargo metadata --offline first. The comment gives the reason: deterministic and fast when the registry already has the crates; the online run happens only when that cannot resolve. If the offline attempt fails, the online one is tried; the callback receives the online error (e2 or err), falling back to the offline error only when the online run gives none. Results are cached per workspace root together with a stamp built from the mtimes of the workspace Cargo.toml, Cargo.lock and every member manifest (stamp_of), so the cache invalidates itself when any of them is saved. The pending table coalesces concurrent calls: a second request for a root that is already being computed joins the queue of callbacks, so several callers asking at once start one cargo.'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 353-403', r'''
function M.metadata(root, opts)
  opts = opts or {}
  local done, meta, err
  M.metadata_async(root, function(m, e)
    done, meta, err = true, m, e
  end, opts)
  if not vim.wait(opts.timeout or (M.config.metadata_timeout_ms + 5000), function()
    return done
  end, 10) then
    return nil, "timed out"
  end
  return meta, err
end

function M.invalidate(root)
  if root then
    cache[root] = nil
  else
    cache = {}
  end
end

--- Dependencies filtered by { member = name, kind = "normal"|"dev"|"build", name = crate }.
function M.dependencies(meta, filter)
  filter = filter or {}
  return vim.tbl_filter(function(d)
    return (not filter.member or d.member == filter.member)
      and (not filter.kind or d.kind == filter.kind)
      and (not filter.name or d.name == filter.name or d.alias == filter.name)
  end, meta.dependencies)
end

--- The member whose directory contains `path` (the longest match).
function M.member_of(meta, path)
  -- cargo's manifest paths and a buffer name may spell one Windows path
  -- differently (drive letter case, slashes): compare one spelling
  local win = vim.fn.has("win32") == 1
  local function key(p)
    p = require("xyno_rust.rust_context").canon(p)
    return win and p:lower() or p
  end
  local want = key(path)
  local best
  for _, m in ipairs(meta.members) do
    local dir = key(m.dir)
    if (want == dir or vim.startswith(want, dir .. "/")) and (not best or #m.dir > #best.dir) then
      best = m
    end
  end
  return best
end'''),
    ...para('--', r'metadata is the blocking form (timeout is the cargo timeout plus five seconds). member_of finds the workspace member that contains a path, longest directory wins, and compares one canonical spelling of each path, lowercased on Windows. The comment above it records the bug it fixed: cargo manifest paths and buffer names spell one Windows path differently. In xynovim that was commit d3e1442 (2026-10-21, "member_of compares one path spelling").'),
    ...sec(r'sources on disk'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 411-447', r'''
--- Unpacked registry source of `name` (exact `version`, else the highest one
--- that is unpacked), or nil.
function M.registry_dir(name, version)
  if not M.valid_name(name) or (version and not M.valid_version(version)) then
    return nil
  end
  local best, best_v
  for _, d in ipairs(vim.fn.glob(cargo_home() .. "/registry/src/*/" .. name .. "-*", true, true)) do
    local v = vim.fs.basename(d):sub(#name + 2)
    -- "serde-1.0.1" but not "serde_json-1.0.1" (the glob needs the dash) nor
    -- "foo-bar-1.0.0" when asking for "foo" (v would not start like a version)
    if M.valid_version(v) and (not version or v == version) and (not best_v or M.compare_versions(v, best_v) > 0) then
      best, best_v = d, v
    end
  end
  return best, best_v
end

--- Source directory of a dependency `name` of the workspace `root`: the
--- metadata's manifest_path (registry, git and path deps alike), else the
--- registry. `version` picks one when several are resolved.
function M.source_dir(root, name, version)
  if not M.valid_name(name) then
    return nil
  end
  local meta = M.metadata(root)
  if meta then
    for _, p in ipairs(meta.by_name[name] or meta.by_name[(name:gsub("_", "-"))] or {}) do
      if not version or p.version == version then
        if p.dir and vim.uv.fs_stat(p.dir) then
          return p.dir, p.version
        end
      end
    end
  end
  return M.registry_dir(name, version)
end'''),
    ...para('--', r'registry_dir globs ~/.cargo/registry/src/*/name-* and picks the exact version or the highest unpacked one. The comment explains how the glob avoids confusing serde with serde_json (the glob needs the dash) and foo with foo-bar-1.0.0 (the remainder must parse as a version). source_dir prefers cargo’s own answer, the manifest path in the metadata, which handles registry, git and path dependencies alike, and falls back to the registry directory. For a name written with an underscore it retries with dashes, because that is how crates are spelled in the metadata.'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 454-503', r'''
--- Crate root source: the [lib] path of the manifest, else src/lib.rs.
--- Returns text, path.
function M.read_lib(dir)
  if not dir then
    return nil
  end
  local toml = M.read_manifest(dir) or ""
  local path
  local lib = toml:match("%[lib%]\n(.-)\n%[") or toml:match("%[lib%]\n(.*)$")
  if lib then
    path = lib:match('\npath%s*=%s*"([^"]+)"') or lib:match('^path%s*=%s*"([^"]+)"')
  end
  -- a path out of the crate is not something to open
  if path and (path:find("..", 1, true) or path:sub(1, 1) == "/") then
    path = nil
  end
  path = dir .. "/" .. (path or "src/lib.rs")
  local text = read_file(path)
  return text, text and path or nil
end

--- The [features] table of a Cargo.toml text (single and multi-line arrays),
--- for crates that are in the registry but not in the metadata:
--- { name = { "dep:x", "y/z", ... } }
function M.parse_features(toml)
  local out = {}
  local body = toml:match("\n%[features%]\n(.-)\n%[") or toml:match("\n%[features%]\n(.*)$") or toml:match("^%[features%]\n(.*)$")
  if not body then
    return out
  end
  body = body:gsub("#[^\n]*", "")
  local pos = 1
  while true do
    local s, e, name = body:find('([%w_%-"]+)%s*=%s*%[', pos)
    if not s then
      break
    end
    local close = body:find("%]", e + 1)
    if not close then
      break
    end
    local list = {}
    for item in body:sub(e + 1, close - 1):gmatch('"([^"]*)"') do
      list[#list + 1] = item
    end
    out[(name:gsub('"', ""))] = list
    pos = close + 1
  end
  return out
end'''),
    ...para('--', r'read_lib finds a crate root without parsing TOML properly: the [lib] path if present, else src/lib.rs. A path with .. or an absolute path is dropped, "a path out of the crate is not something to open". parse_features does the same for crates that are in the registry but not in the metadata, with a small scanner that handles single and multi-line arrays and strips comments. It is a pragmatic choice: a full TOML parser is not available in the Neovim runtime, and a features table is regular enough.'),
    ...sec(r'the crates.io client'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 530-561', r'''
--- GET `url` through curl. cb(body) or cb(nil, err, kind) with kind "offline"
--- (no network), "notfound" or "http".
local function http_get(url, cb)
  local argv = {
    "curl", "--silent", "--show-error",
    "--max-time", tostring(math.max(1, math.floor(M.config.timeout_ms / 1000))),
    "--proto", M.config.proto, "--proto-redir", M.config.proto,
    "-A", M.config.user_agent,
    "-H", "Accept: application/json",
    "--write-out", "\n%{http_code}",
    url,
  }
  M.exec(argv, { timeout = M.config.timeout_ms + 2000 }, function(r)
    if r.code ~= 0 then
      -- 6 host, 7 connect, 28 timeout, 35 TLS, 52/56 network, -1 no curl
      local offline = ({ [6] = 1, [7] = 1, [28] = 1, [35] = 1, [52] = 1, [56] = 1, [-1] = 1 })[r.code]
      return cb(nil, (offline and "offline: " or "request failed: ") .. vim.trim(r.stderr), offline and "offline" or "http")
    end
    local body, status = r.stdout:match("^(.*)\n(%d+)$")
    status = tonumber(status) or 0
    if status == 0 and url:sub(1, 7) == "file://" then
      status = 200 -- file:// has no status; --write-out prints 000
    end
    if status == 404 or status == 403 then
      return cb(nil, "not found", "notfound")
    end
    if status < 200 or status >= 300 then
      return cb(nil, "http " .. status, "http")
    end
    cb(body)
  end)
end'''),
    ...para('--', r'The client is curl with an argv list, never a shell string, so a crate name can never be interpreted as shell syntax. It restricts protocols and redirects with --proto and --proto-redir, sets an explicit user agent (the plugin name from M.config), appends the HTTP status with --write-out, and maps curl exit codes 6, 7, 28, 35, 52, 56 and a missing curl to "offline" so the UI can say so instead of "failed". 404 and 403 mean "not found". The file:// special case exists only for the specs.'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 563-596', r'''
--- Path of a crate in the sparse index.
function M.index_path(name)
  name = name:lower()
  local n = #name
  if n == 1 then
    return "1/" .. name
  elseif n == 2 then
    return "2/" .. name
  elseif n == 3 then
    return "3/" .. name:sub(1, 1) .. "/" .. name
  end
  return name:sub(1, 2) .. "/" .. name:sub(3, 4) .. "/" .. name
end

--- cached-or-fetched text with the TTL / stale / offline rules. cb(text, err, meta)
--- where meta = { from_cache, stale }.
local function cached_get(file, ttl, url, refresh, cb)
  local text, fresh = cache_get(file, ttl)
  if text and fresh and not refresh then
    return vim.schedule(function()
      cb(text, nil, { from_cache = true })
    end)
  end
  http_get(url, function(body, err, kind)
    if body then
      write_file(cache_dir() .. "/" .. file, body)
      return cb(body, nil, {})
    end
    if text and kind ~= "notfound" then
      return cb(text, nil, { from_cache = true, stale = true, offline = kind == "offline", note = err })
    end
    cb(nil, err, { offline = kind == "offline" })
  end)
end'''),
    ...para('--', r'index_path implements the sparse index layout (one-letter names under 1/, two under 2/, three under 3/x/, otherwise the first two and next two letters). cached_get is the policy in one function: a fresh cache entry is served without touching the network; otherwise the fetch happens; a successful fetch rewrites the cache; and a failed fetch falls back to the stale cache entry, marked stale and offline, unless the server said "not found", in which case the stale answer would be wrong. That is what the header means by offline-tolerant.'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 598-641', r'''
--- Merge `features` and `features2` of an index line and add the implicit
--- feature of every optional dependency that no `dep:` mentions.
local function index_features(line)
  local feats = {}
  for _, tbl in ipairs({ line.features or {}, line.features2 or {} }) do
    for k, v in pairs(tbl) do
      feats[k] = v
    end
  end
  local explicit = {}
  for _, list in pairs(feats) do
    for _, item in ipairs(list) do
      local d = item:match("^dep:(.+)$")
      if d then
        explicit[d] = true
      end
    end
  end
  for _, d in ipairs(line.deps or {}) do
    local key = d.name
    if d.optional and not explicit[key] and not feats[key] then
      feats[key] = { "dep:" .. key }
    end
  end
  return feats
end

--- The JSON lines of an index file -> versions, oldest first.
function M.parse_index(text)
  local versions = {}
  for l in text:gmatch("[^\n]+") do
    local ok, v = pcall(vim.json.decode, l, JSON_OPTS)
    if ok and type(v) == "table" and M.valid_name(v.name) and M.valid_version(v.vers) then
      versions[#versions + 1] = {
        version = v.vers,
        yanked = v.yanked or false,
        features = index_features(v),
        deps = v.deps or {},
        rust_version = v.rust_version,
      }
    end
  end
  return versions
end'''),
    ...para('--', r'The sparse index stores features in two fields, features and features2, and leaves the implicit feature of an optional dependency unlisted. index_features merges both and adds dep:name for every optional dependency that no explicit dep: mentions, which reproduces what cargo does. parse_index reads one JSON object per line and skips lines that are not valid or fail the name/version validation.'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 643-699', r'''
--- Exact-name lookup. cb(info) or cb(nil, err). info = { name, versions
--- (oldest first), newest (newest non-yanked), features (of the newest),
--- description, downloads, recent_downloads (when the API answered),
--- from_cache, stale }.
function M.info_async(name, cb, opts)
  opts = opts or {}
  if not M.valid_name(name) then
    return vim.schedule(function()
      cb(nil, "invalid crate name")
    end)
  end
  local lname = name:lower()
  cached_get("index-" .. lname .. ".jsonl", M.config.index_ttl, M.config.index_url .. "/" .. M.index_path(name), opts.refresh, function(text, err, how)
    if not text then
      return cb(nil, err)
    end
    local versions = M.parse_index(text)
    if #versions == 0 then
      return cb(nil, "no versions in the index answer")
    end
    local newest
    for _, v in ipairs(versions) do
      if not v.yanked and (not newest or M.compare_versions(v.version, newest.version) > 0) then
        newest = v
      end
    end
    newest = newest or versions[#versions]
    local info = {
      name = name,
      versions = versions,
      newest = newest.version,
      features = newest.features,
      deps = newest.deps,
      from_cache = how.from_cache,
      stale = how.stale,
    }
    if opts.index_only then
      return cb(info)
    end
    -- description and downloads are only in the web API (`?include=` leaves out
    -- the 400 KB of version rows, which time out a 5 s call); its failure does not
    -- fail the lookup
    cached_get("crate-" .. lname .. ".json", M.config.index_ttl, M.config.api_url .. "/crates/" .. lname .. "?include=", opts.refresh, function(api)
      if api then
        local ok, j = pcall(vim.json.decode, api, JSON_OPTS)
        local c = ok and type(j) == "table" and j.crate
        if type(c) == "table" then
          info.description = type(c.description) == "string" and c.description or nil
          info.downloads = tonumber(c.downloads)
          info.recent_downloads = tonumber(c.recent_downloads)
          info.repository = type(c.repository) == "string" and c.repository or nil
        end
      end
      cb(info)
    end)
  end)
end'''),
    ...para('--', r'info_async is the exact-name lookup: the index gives versions, the newest non-yanked version and its features; the web API adds description and downloads. The comment at the API call carries a measurement: ?include= leaves out the 400 KB of version rows, which time out a 5 second call. The API failing does not fail the lookup, because the index alone is enough for the features. search_async validates the query (non-empty, at most 100 characters, no control characters), percent-encodes it, and caches under a hash of the query. It prefers max_stable_version over max_version.'),
    ...sec(r'is this name known?'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 823-897', r'''
--- Is `name` the first segment of a path that resolves to something that
--- exists? Returns the kind ("keyword", "std", "dependency", "own_crate",
--- "module", "local_item", "macro") and a detail, or nil when it is unknown.
---
--- A cheap heuristic, not name resolution: dependencies and the crate's own
--- lib name come from cargo metadata (renames and `-` / `_` handled); local
--- modules from `mod name` in the file, `name.rs` / `name/mod.rs` next to it
--- (or under the member's src/); items from a `struct|enum|trait|type|fn|
--- const|static|union name` declaration in the file; macro_rules! names from
--- the file or any .rs of the member (the textual `#[macro_use]` scope is not
--- modelled). Names that arrive by a `use` of another module are NOT
--- recognised, so call it for the head of `use` paths and for heads that start
--- an expression path, not for every identifier.
--- opts.file: the file the path is in (default the current buffer).
function M.is_known_path_head(root, name, opts)
  opts = opts or {}
  if type(name) ~= "string" or name == "" then
    return nil
  end
  if KEYWORDS[name] then
    return "keyword"
  end
  if STD[name] then
    return "std"
  end
  local file = opts.file or vim.api.nvim_buf_get_name(0)
  local meta = opts.meta
  if not meta then
    meta = M.metadata(root)
  end
  local member = meta and file ~= "" and M.member_of(meta, file) or nil
  if meta then
    for _, d in ipairs(meta.dependencies) do
      if d.alias == name and (not member or d.member == member.name) then
        return "dependency", d.name
      end
    end
    -- workspace-wide fallback when the file is not in a member (a scratch file)
    for _, m in ipairs(meta.members) do
      if (not member or m == member) and m.lib_name == name then
        return "own_crate", m.name
      end
    end
  end
  if file ~= "" then
    local text = file_text(file)
    if declares(text, "mod", name) then
      return "module", file
    end
    local mdir = module_dir(file)
    if has_file(mdir .. "/" .. name .. ".rs") or has_file(mdir .. "/" .. name .. "/mod.rs") then
      return "module", mdir .. "/" .. name
    end
    for _, kw in ipairs({ "struct", "enum", "trait", "type", "fn", "const", "static", "union" }) do
      if declares(text, kw, name) then
        return "local_item", kw
      end
    end
    if macro_declared(text, name) then
      return "macro", file
    end
    local src = member and (member.dir .. "/src")
    if src and (has_file(src .. "/" .. name .. ".rs") or has_file(src .. "/" .. name .. "/mod.rs")) then
      return "module", src .. "/" .. name
    end
    if src and vim.fn.isdirectory(src) == 1 then
      for _, f in ipairs(rs_files(src, 300)) do
        if f ~= file and macro_declared(read_file(f), name) then
          return "macro", f
        end
      end
    end
  end
  return nil
end'''),
    ...para('--', r'is_known_path_head is the cheapest possible name check, and its doc comment is honest that it is not name resolution. In order: Rust keywords (crate, self, super, Self), the std crates, a dependency alias of the member that owns the file, the crate’s own lib name, a mod declared in the file or next to it as name.rs or name/mod.rs, a local item (struct, enum, trait, type, fn, const, static, union), and a macro_rules! name in the file or any .rs file of the member (capped at 300 files; textual macro_use scope is not modelled). It returns the kind and a detail, or nil. The limit that matters is in the comment: names that arrive through a use of another module are not recognised, so it should be called for the head of use paths and expression paths, not for every identifier. It is what lets the auto-import and the missing-crate features avoid offering to add a crate for something that already exists locally.'),
    ...sec(r'how it is tested'),
    ...para('--', r'The spec is organised like the module: validation; metadata; registry and sources; the client with faked curl, with a real curl against file:// URLs and with the real network (the last is a separate block); is_known_path_head; code_actions against a fake client and against a real rust-analyzer; and the bounded reads. Fixtures include a workspace laboratory for dependencies.'),
    ...sec(r'history'),
    ...para('--', r'Born in 6e1b567 (2026-10-14, "Macros and deps: foundation modules (crate_meta, code_actions) and fixtures") at 881 lines. Reviewed in 19f974c (2026-10-15), made portable in ff1c8fa (2026-10-16), given the .exe and drive-letter fixes in 6524272 (2026-10-21) and the member_of fix in d3e1442 (2026-10-21). In this repository (c1c7958) it gained the user agent and cache directory named after xyno-rust, and nothing else.'),
  ],
);
