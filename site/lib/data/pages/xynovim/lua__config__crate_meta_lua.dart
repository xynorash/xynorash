import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/crate_meta.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'crate_meta.lua — what the editor knows about crates'),
    cm('--', r'cargo metadata, registry sources, a crates.io client, path heads'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the data layer under every dependency and macro feature (no UI)'),
    kv(r'language', r'Lua for Neovim 0.12, vim.system and vim.uv, no plugins'),
    kv(r'size', r'899 lines, 5 commits (2026-10-14 to 2026-10-21)'),
    kv(r'spec', r'tests/crate-meta_spec.lua (942 lines)'),
    kv(r'used by', r'crate_add, crate_features, crate_import, import_engine, macro_attrs'),
    kv(r'also lives in', r'xyno-rust.nvim as lua/xyno_rust/crate_meta.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'Several features need to answer questions about crates: is this name a dependency, which features does serde have, what is the newest tokio, does a crate called rand exist. The answers come from different places: cargo itself, the unpacked sources in the cargo registry, the sparse index at index.crates.io, the crates.io web API. If every feature asked in its own way there would be four curl invocations and four ideas of what a workspace is. crate_meta is the single place that knows.'),
    ...para('--', r'It landed as a foundation commit on 2026-10-14 (6e1b567, with code_actions, the deps-lab fixtures and a 922-line spec) before any module that uses it. That is why it never mentions a feature by name: it was written first as an interface and the features were written against it.'),
    ...sec(r'the contract'),
    ...code('lua', r'lua/config/crate_meta.lua · lines 10-16', r'''
--
-- Conventions: functions that can wait come in pairs, `foo_async(..., cb)` and
-- a blocking `foo(...)` built on it. They return `result, err` (never raise
-- for network, tool or file problems); `err` is a plain string. Names and
-- versions that come from the network or from files are validated before they
-- reach an argv or a path.
local M = {}'''),
    ...para('--', r'Anything that can wait comes as a pair, foo_async(..., cb) and a blocking foo(...) built on it, and both return result, err instead of raising. A caller in a code action or a completion source can show a failure as a value without wrapping every call in pcall. The blocking versions are the async ones plus vim.wait with a timeout. The last sentence is the security stance: network and file input is validated before it reaches an argv or a path.'),
    ...code('lua', r'lua/config/crate_meta.lua · lines 18-31, 38-45', r'''
M.config = {
  timeout_ms = 5000, -- one curl call (curl --max-time)
  metadata_timeout_ms = 60000, -- cargo metadata (may have to resolve)
  index_ttl = 3600, -- seconds a cached index answer is fresh
  search_ttl = 600,
  index_url = "https://index.crates.io",
  api_url = "https://crates.io/api/v1",
  proto = "=https", -- curl --proto; specs point the URLs at file:// and set "=file"
  user_agent = "xynovim (github.com/xynorash/xynovim)",
  cache_dir = nil, -- default stdpath("cache")/xynovim/crates
  cargo_home = nil, -- default $CARGO_HOME or ~/.cargo
}

-- JSON null -> nil (vim.NIL is truthy and breaks `x or default`)
...
function M.valid_name(name)
  return type(name) == "string" and #name > 0 and #name <= 64 and name:match("^[A-Za-z0-9_-]+$") ~= nil
end

--- semver-ish: 1.2.3, 1.2.3-rc.1, 1.2.3+build
function M.valid_version(v)
  return type(v) == "string" and #v <= 64 and v:match("^%d+%.%d+%.%d+[A-Za-z0-9.+-]*$") ~= nil
end'''),
    ...para('--', r'M.config is a plain table so specs can replace any value: the comment on proto says specs point the URLs at file:// and set =file, so the real curl code runs against fixture files instead of a mock. valid_name allows letters, digits, underscore and dash up to 64 characters. That is wider than crates.io (a leading dash passes) but it is the right layer for a character-class check; crate_import adds the stricter rules where a name becomes an argument of cargo add.'),
    ...para('--', r'Every cargo and curl call goes through M.exec, which the specs replace to fake both tools. With a callback it is asynchronous and the callback is wrapped in schedule_wrap so it runs on the main loop. The spawn is inside pcall because vim.system raises when the executable is missing; that becomes code -1, and the callback is still delivered later through vim.schedule, so no caller sees a synchronous callback in one branch and an asynchronous one in another.'),
    ...sec(r'reading untrusted sources'),
    ...code('lua', r'lua/config/crate_meta.lua · lines 108-122', r'''

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
  local s = f:read("*a")'''),
    ...para('--', r'Dependency sources are somebody else code, git checkouts and path dependencies included. read_file only reads regular files up to 2 MiB; the comment names the two attacks: a symlink to /dev/zero exhausts memory and a FIFO blocks the main thread. fs_stat follows the link, so it reports a character device and the file is refused. The spec group crate_meta bounded reads builds exactly those cases.'),
    ...sec(r'cargo metadata: one normalized shape'),
    ...code('lua', r'lua/config/crate_meta.lua · lines 146-168', r'''
local cache = {} -- root -> { stamp = string, meta = table }
local pending = {} -- root -> { callbacks }

--- Workspace root of a directory or file (a directory holding Cargo.toml is
--- taken as is, which also covers a path outside any workspace of its own).
function M.root(path)
  path = path or vim.api.nvim_buf_get_name(0)
  local st = vim.uv.fs_stat(path)
  local rc = require("config.rust_context")
  if st and st.type == "directory" and vim.uv.fs_stat(path .. "/Cargo.toml") then
    return rc.canon(path) -- one spelling of a root (Windows drive letter / slashes)
  end
  return rc.root(path)
end

local function stamp_of(root, meta)
  local parts = { mtime(root .. "/Cargo.toml"), mtime(root .. "/Cargo.lock") }
  if meta then
    for _, m in ipairs(meta.members) do
      parts[#parts + 1] = m.manifest_path .. "=" .. mtime(m.manifest_path)
    end
  end
  return table.concat(parts, "|")'''),
    ...para('--', r'The cache maps a workspace root to the normalized metadata plus a stamp, and pending maps a root to the callbacks waiting for a run already in flight. The stamp is the invalidation rule: the mtime of Cargo.toml and Cargo.lock plus every member manifest. Nothing watches the disk; a hit means the stamp recomputed now equals the stored one, a handful of stat calls. M.root returns canon(path) since 6524272 (2026-10-21): the root is the cache key, and a Windows drive letter in two spellings would have meant two caches and two cargo runs.'),
    ...code('lua', r'lua/config/crate_meta.lua · lines 216-263', r'''
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
      local node = nodes[p.id]
      for _, d in ipairs(p._raw.dependencies or {}) do
        local alias = alias_of(d)
        local kind = d.kind or "normal"
        local resolved
        for _, e in ipairs(node and node.deps or {}) do
          if e.name == alias then
            local dk_ok = #(e.dep_kinds or {}) == 0
            for _, dk in ipairs(e.dep_kinds or {}) do
              if (dk.kind or "normal") == kind then
                dk_ok = true
              end
            end
            local target = by_id[e.pkg]
            if dk_ok and target and target.name == d.name then
              resolved = vim.tbl_extend("force", {}, target, {
                enabled_features = nodes[e.pkg] and nodes[e.pkg].features or {},
              })
              resolved._raw = nil
              break
            end
          end
        end
        dependencies[#dependencies + 1] = {
          name = d.name,
          alias = alias,
          rename = d.rename,
          req = d.req,
          kind = kind,
          optional = d.optional or false,
          features = d.features or {},
          uses_default_features = d.uses_default_features ~= false,'''),
    ...para('--', r'normalize turns cargo JSON into members, dependencies, packages and by_name. This loop matches each declared dependency with its resolved package. The key is the alias (rename or name, dashes to underscores), the edge must carry the declared kind (an empty dep_kinds list is accepted), and target.name must equal the declared name, so two edges that share an alias after dash normalization cannot be confused. The resolved copy carries enabled_features from the resolve node, which is what the feature explorer shows: what the lockfile turned on, not what the manifest asked for. Dependencies that do not resolve stay in the list with resolved = nil.'),
    ...code('lua', r'lua/config/crate_meta.lua · lines 286-320', r'''
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
--- cached until a Cargo.toml (workspace or member) or Cargo.lock changes.'''),
    ...para('--', r'The comment gives the order: offline first, because it is deterministic and fast when the registry already has the crates; the online run happens only when that cannot resolve. parse separates three failures: a non-zero exit (cargo own stderr), output that is not JSON, and JSON normalize cannot read (inside pcall so a field from a future cargo cannot raise into an autocommand). The 60 second timeout is separate from the 5 second curl one because resolving can legitimately take long.'),
    ...code('lua', r'lua/config/crate_meta.lua · lines 322-351', r'''
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
    ...para('--', r'The coalescing is the important part. A fresh cache hit is delivered through vim.schedule, so the function is uniformly asynchronous. If a run for that root is already pending the callback joins the list and no second cargo starts. When the run ends the cache is filled only on success, the list is detached before the callbacks run, and every waiter gets the same result. A code action, an import and a diagnostic asking at once cost one cargo process. invalidate(root) drops one entry or all; the writers call it after they edit a manifest.'),
    ...code('lua', r'lua/config/crate_meta.lua · lines 386-404', r'''
function M.member_of(meta, path)
  -- cargo's manifest paths and a buffer name may spell one Windows path
  -- differently (drive letter case, slashes): compare one spelling
  local win = vim.fn.has("win32") == 1
  local function key(p)
    p = require("config.rust_context").canon(p)
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
    ...para('--', r'member_of finds the workspace member whose directory contains a path, longest match winning, so a file in a nested member resolves to the inner one. It compares one canonical spelling, lower-cased on Windows (d3e1442, 2026-10-21), because cargo reports a manifest path with one drive-letter case and a buffer name can carry the other.'),
    ...sec(r'registry and sources'),
    ...code('lua', r'lua/config/crate_meta.lua · lines 413-428', r'''
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
end'''),
    ...para('--', r'registry_dir globs registry/src/*/name-* and takes what follows the name plus one dash as the version. The comment spells out two traps: serde_json-1.0.1 does not match serde-* because the glob needs the dash, and foo-bar-1.0.0 is not a version of foo because bar-1.0.0 fails valid_version. source_dir prefers the metadata manifest_path (registry, git and path dependencies alike), so a path dependency is read from your working tree, and falls back to the registry glob.'),
    ...code('lua', r'lua/config/crate_meta.lua · lines 456-475', r'''
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

--- The [features] table of a Cargo.toml text (single and multi-line arrays),'''),
    ...para('--', r'read_lib finds the crate root: the path key of the [lib] table, else src/lib.rs. A manifest is untrusted, so a path with .. or a leading slash is discarded. parse_features, just below, is a deliberately small reader for the [features] table of crates that are in the registry but not in the metadata; it scans name = [ ... ] with patterns, single-line and multi-line, and does not pretend to parse TOML.'),
    ...sec(r'the crates.io client'),
    ...code('lua', r'lua/config/crate_meta.lua · lines 532-562', r'''
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
    ...para('--', r'http_get builds an argv for curl, never a shell string. It passes --proto and --proto-redir so a redirect cannot leave https, a user agent, and --write-out with the HTTP status so it can be split off the body. Exit codes 6, 7, 28, 35, 52, 56 and -1 (no curl) mean offline; a 404 or 403 is notfound; other statuses are http errors. file:// prints status 000, treated as 200, which is the line that lets the specs run the genuine curl path against files.'),
    ...code('lua', r'lua/config/crate_meta.lua · lines 564-597', r'''
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
    ...para('--', r'index_path is the sparse-index layout: 1/, 2/, 3/x/ for short names, ab/cd/name for the rest. cached_get is what makes the client usable offline. A fresh cache entry is served without a request. Otherwise it fetches and overwrites the cache. If the fetch fails and an older copy exists, that copy is returned flagged stale (and offline when it was a network failure), unless the failure was a definitive not found: a crate that does not exist must not be answered from an old copy. The ttl is 3600 seconds for the index and 600 for search.'),
    ...code('lua', r'lua/config/crate_meta.lua · lines 600-624', r'''
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
end'''),
    ...para('--', r'index_features is why the feature explorer is right for crates with the newer manifest syntax. An index line has features and features2 (the latter holds dep: and ? syntax); they are merged. Then the implicit features are added: cargo gives every optional dependency a feature of its own name unless some feature mentions it with dep:. Without that, an optional dependency with no [features] entry would show no way to turn it on.'),
    ...code('lua', r'lua/config/crate_meta.lua · lines 647-698', r'''
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
  end)'''),
    ...para('--', r'info_async is an exact-name lookup in two layers. The index gives versions and features and must succeed; the newest version is the highest non-yanked one. Callers that only need existence, like crate_import, pass index_only and stop there. The web API adds description, downloads and repository, and its failure never fails the lookup. The comment records why the URL ends in ?include=: the default answer holds about 400 KB of version rows, which time out a 5 second call.'),
    ...para('--', r'search_async rejects an empty query, one over 100 characters, or one with control characters before anything runs. The query is percent-encoded, the cache file is named from a sha256 prefix of the query so any text maps to a safe name, and every hit is revalidated with valid_name. The version prefers max_stable_version.'),
    ...sec(r'path heads'),
    ...code('lua', r'lua/config/crate_meta.lua · lines 826-880', r'''
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
    end'''),
    ...para('--', r'is_known_path_head answers: is rand in rand::random() the head of something that exists? Its doc comment is honest: a cheap heuristic, not name resolution. The order is keyword, std crate, dependency of the file member by alias, the member own library name, then the file text and tree (mod declarations, name.rs or name/mod.rs, struct/enum/trait/type/fn/const/static/union, macro_rules!). Names that arrive through a use of another module are explicitly not recognised, and callers are told to use it only for heads of use paths and expression paths. When the file is open in a buffer it reads the buffer, not the disk, so a mod you just typed counts before you save; the scan of the member tree is bounded to 300 files.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/crate-meta_spec.lua follows the file: validation and index paths; metadata (members, dependencies by kind, renames, optional, features; caching until a manifest or the lockfile changes; async; error values outside a workspace and for a broken manifest; the deps-lab fixture); registry and sources (highest unpacked version, never a prefix sibling, a [lib] path honoured but escapes refused); a faked-curl group (implicit features, yanked versions, junk lines, stale cache when offline); a real-curl group against file:// that also checks non-https URLs are refused; two network groups against real crates.io; is_known_path_head; and the bounded reads.'),
    ...sec(r'history'),
    ...pt('--', r'6e1b567 · 2026-10-14', r'foundation commit with code_actions and the deps-lab fixtures'),
    ...pt('--', r'19f974c · 2026-10-15', r'review fixes'),
    ...pt('--', r'ff1c8fa · 2026-10-16', r'portability: write_file renames through fsutil'),
    ...pt('--', r'6524272 · 2026-10-21', r'canonical root spelling and drive letter case'),
    ...pt('--', r'd3e1442 · 2026-10-21', r'member_of compares one path spelling'),
    ...sec(r'the same file in xyno-rust.nvim'),
    ...para('--', r'On 2026-10-22 the Rust tooling was extracted into standalone plugins. crate_meta lives on as lua/xyno_rust/crate_meta.lua in xyno-rust.nvim and a diff shows renaming only: the user agent becomes xyno-rust.nvim (github.com/xynorash/xyno-rust.nvim), the default cache directory moves from stdpath cache/xynovim/crates to stdpath cache/xyno-rust/crates, and the requires of fsutil and rust_context change namespace. The logic is identical. An existing cache in the old directory is simply not read by the plugin. xyno-crates.nvim and xyno-imports.nvim list xyno_rust.crate_meta as required and refuse to start with an error naming xyno-rust.nvim when it is missing.'),
  ],
);
