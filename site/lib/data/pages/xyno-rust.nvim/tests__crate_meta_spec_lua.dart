import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/tests/crate-meta_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'tests/crate-meta_spec.lua — what we know about crates, and how far we trust what we are told'),
    cm('--', r'validation, cargo metadata, registry sources, a crates.io client with a fake curl, code actions'),
    cm('--', r'──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/xyno_rust/crate_meta.lua (899 lines) and lua/xyno_rust/code_actions.lua (336 lines)'),
    kv(r'language', r'Lua, run by tests/run.lua'),
    kv(r'size', r'942 lines, 44 tests in 10 describe blocks'),
    kv(r'hermetic', r'path-only temp workspaces, a fake CARGO_HOME, a faked or file:// curl, a fake LSP client'),
    kv(r'real', r'cargo (metadata), rust-analyzer in one test, curl against file://, the network in two tests'),
    kv(r'fixtures', r'tests/fixtures/deps-lab and deps-lab-nofeature (serde derive, tokio macros), made in code otherwise'),
    kv(r'origin', r'xynovim tests/crate-meta_spec.lua, 2026-10-14 (6e1b567)'),
    ...sec(r'why this file exists'),
    ...para('--', r'crate_meta.lua is the information layer under every dependency feature: which packages '
        r'are in the workspace, what each one depends on and under what name, which features a '
        r'crate has, where its source lives on disk, what crates.io says about it, and whether the '
        r'first segment of a path (use rand::..., helpers::...) names anything at all. '
        r'code_actions.lua is its sibling for the language server: ask for code actions at a range, '
        r'filter them, resolve them and apply them. The header of crate_meta.lua states the '
        r'conventions that this spec tests. Functions that can wait come in pairs, foo_async and a '
        r'blocking foo. They return result, err and never raise for network, tool or file problems. '
        r'And names and versions that come from the network or from files are validated before they '
        r'reach an argv or a path.'),
    ...para('--', r'Those two sentences are the reason for the shape of the spec. Half of it is not about the '
        r'happy path at all. It is about hostile or broken input: a crate name with a semicolon, a '
        r'version with a command in it, a source file that is a symlink to /dev/zero, a server that '
        r'answers with junk, a network that is gone. The code reads names from a registry index and '
        r'puts them in file paths and command lines; any of those can be wrong or malicious, and '
        r'each guard has a test that tries to get past it.'),
    ...sec(r'the module header and defaults'),
    ...code('lua', r'lua/xyno_rust/crate_meta.lua · lines 1-33', r'''
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
local M = {}

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
local JSON_OPTS = { luanil = { object = true, array = true } }

'''),
    ...para('--', r'Every fixture of the spec hangs off this config table. cache_dir, cargo_home, index_url, '
        r'api_url and proto are replaced by stubs in the tests, so no test touches the real cache, '
        r'the real registry or the real network, except the two that say so. The user agent names '
        r'this plugin; the faked-curl test below asserts the exact string.'),
    ...sec(r'the preamble'),
    ...para('--', r'stub replaces a field and records the way back. after_each restores everything in reverse '
        r'order, then calls cm.invalidate() to drop the metadata cache and wipes buffers. The '
        r'invalidate matters: the module caches cargo metadata per root, and a stale cache from one '
        r'test would otherwise answer the next.'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 40-62', r'''
  local root = H.tmpdir() .. "/ws"
  write(root .. "/Cargo.toml", '[workspace]\nmembers = ["app", "util", "opt", "dev_only", "builder"]\nresolver = "2"\n')
  for _, n in ipairs({ "util", "opt", "dev_only", "builder" }) do
    write(
      ("%s/%s/Cargo.toml"):format(root, n),
      ('[package]\nname = "%s"\nversion = "0.2.0"\nedition = "2021"\n\n[features]\nfast = []\nextra = ["fast"]\n'):format(n)
    )
    write(("%s/%s/src/lib.rs"):format(root, n), "pub fn f() {}\n")
  end
  write(
    root .. "/app/Cargo.toml",
    [[
[package]
name = "app"
version = "0.1.0"
edition = "2021"

[dependencies]
helpers = { package = "util", path = "../util", default-features = false, features = ["fast"] }
opt = { path = "../opt", optional = true }

[dev-dependencies]
dev_only = { path = "../dev_only" }
'''),
    ...para('--', r'make_workspace builds the fixture for most of the file, in code, because the shape is the '
        r'point. A workspace with five members: app, which has a binary and a library, and four '
        r'path crates. app depends on util under the name helpers (a rename, with default-features '
        r'= false and features = ["fast"]), on opt as optional, on dev_only as a dev dependency and '
        r'on builder as a build dependency. It has a net module with a nested http module, an '
        r'inline module, a local struct, and macro_rules! in two files. With path crates only, '
        r'cargo metadata needs no registry and no network, so the tests are hermetic.'),
    ...sec(r'validation'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 79-97', r'''
describe("crate_meta validation", function()
  it("accepts crate names and rejects anything a shell or path could misread", function()
    for _, n in ipairs({ "serde", "serde_json", "tokio-util", "a1" }) do
      H.ok(cm.valid_name(n), n)
    end
    for _, n in ipairs({ "", "a b", "a/b", "../x", "a;b", "a$(x)", "a\nb", "é", string.rep("a", 65), 5 }) do
      H.not_ok(cm.valid_name(n), vim.inspect(n))
    end
  end)

  it("accepts semver-ish versions only", function()
    for _, v in ipairs({ "1.0.0", "0.9.15", "1.2.3-rc.1", "1.0.0+build.5" }) do
      H.ok(cm.valid_version(v), v)
    end
    for _, v in ipairs({ "1", "1.0", "^1.0.0", "1.0.0; rm", "../1.0.0", "" }) do
      H.not_ok(cm.valid_version(v), v)
    end
  end)

'''),
    ...para('--', r'The first group is the one that guards the boundary. valid_name accepts letters, digits, '
        r'underscore and dash up to 64 characters and refuses the empty string, spaces, slashes, '
        r'dots, semicolons, command substitutions, a newline, a non-ASCII letter, a 65-character '
        r'name and a non-string. valid_version wants three numeric parts and an optional suffix, '
        r'and refuses 1, 1.0, a caret requirement, 1.0.0; rm and a path.'),
    ...para('--', r'compare_versions is numeric, so 1.0.9 is below 1.0.10 and 2.0.0 is above 1.99.99, and a '
        r'pre-release sorts before its release. index_path follows the sparse index layout: 1/a, '
        r'2/ab, 3/s/syn, then two-and-two letters, se/rd/serde.'),
    ...para('--', r'One assertion in the index test is vacuous. Line 111 compares the expected string with '
        r'cm.index_path("Serde_Json"):gsub(...) and "se/rd/serde_json". The and returns the right '
        r'operand whenever the left is truthy, so the expression is the expected string whatever '
        r'index_path returns for upper case. The intent, that a mixed-case name maps to the '
        r'lower-case path, is not actually checked.'),
    ...sec(r'cargo metadata'),
    ...para('--', r'The first test reads the five members and the dependencies by kind, with the rename, the '
        r'optional flag and the features. member_of maps a file to the member that owns it, and '
        r'gives nil for a path outside.'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 164-182', r'''
  it("caches until a manifest or the lock changes", function()
    H.need_rust()
    local root = make_workspace()
    local a = cm.metadata(root)
    H.ok(a)
    H.ok(rawequal(a, cm.metadata(root)), "second call is the cached table")
    -- a member manifest edit (new mtime) invalidates
    local f = root .. "/app/Cargo.toml"
    local txt = io.open(f):read("*a")
    vim.uv.fs_utime(f, os.time() + 5, os.time() + 5)
    local b = cm.metadata(root)
    H.ok(not rawequal(a, b), "recomputed after the member manifest changed")
    write(f, txt:gsub('version = "0.1.0"', 'version = "0.1.1"'))
    local c = cm.metadata(root)
    H.eq("0.1.1", vim.tbl_filter(function(m)
      return m.name == "app"
    end, c.members)[1].version)
    -- refresh forces
    H.ok(not rawequal(c, cm.metadata(root, { refresh = true })))
'''),
    ...para('--', r'The cache test is a lesson in how a cache key can go wrong. The second call must return '
        r'the very same table (rawequal). Bumping the mtime of a member manifest with fs_utime five '
        r'seconds ahead invalidates it. Changing the file content recomputes and shows the new '
        r'version. And the refresh option forces a recompute. The cache key is the modification '
        r'times of the manifests and the lock.'),
    ...para('--', r'There is an async variant, and the test checks that a second call while nothing is '
        r'pending is answered from the cache. The error variant checks that metadata returns an '
        r'error value, not an exception, outside a workspace and for a broken manifest.'),
    ...sec(r'registry and sources'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 258-268', r'''
  it("finds the highest unpacked version, an exact one, and never a prefix-sibling", function()
    local _, reg = fake_home()
    H.eq(reg .. "/serde-1.0.11-rc.1", (cm.registry_dir("serde")))
    H.eq(reg .. "/serde-1.0.10", (cm.registry_dir("serde", "1.0.10")))
    H.eq(reg .. "/serde-0.9.15", (cm.registry_dir("serde", "0.9.15")))
    H.eq(reg .. "/serde_json-1.0.1", (cm.registry_dir("serde_json")))
    H.eq(reg .. "/foo-2.0.0", (cm.registry_dir("foo")))
    H.eq(reg .. "/foo-bar-1.0.0", (cm.registry_dir("foo-bar")))
    H.is_nil(cm.registry_dir("serde", "9.9.9"))
    H.is_nil(cm.registry_dir("nonexistent"))
  end)
'''),
    ...para('--', r'A fake CARGO_HOME with seven unpacked crates: serde in four versions including a '
        r'pre-release, serde_json, foo-bar and foo. registry_dir picks the highest unpacked version '
        r'(a pre-release 1.0.11-rc.1 beats 1.0.10 because the comparison is plain semver), an exact '
        r'version when asked, and never a prefix sibling: asking for foo gives foo-2.0.0, not '
        r'foo-bar-1.0.0, and foo-bar gives foo-bar-1.0.0. Unknown names and versions give nil. The '
        r'second test shows that ../x, * and 1.0.* never reach the file system.'),
    ...para('--', r'read_lib is where the spec starts to distrust files. It reads src/lib.rs, or the path '
        r'given in [lib], but a [lib] path that escapes the crate directory '
        r'(../serde-1.0.9/src/lib.rs) falls back to src/lib.rs. Missing files and a nil directory '
        r'give nil.'),
    ...para('--', r'parse_features reads a [features] table with comments, a multi-line array, a quoted key '
        r'and a trailing section, and gives {} for a manifest without one. It is a small parser '
        r'written for the job, so its test is a sample of every awkward form.'),
    ...sec(r'the crates.io client'),
    ...para('--', r'Everything below runs with fake data: a three-version sparse index body with a yanked '
        r'version, a features2 override, an optional dependency, a line that is not JSON, a line '
        r'with the name ../evil and a line with the version x; rm -rf. fake_curl replaces cm.exec '
        r'and answers by URL substring.'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 392-408', r'''
describe("crate_meta crates.io client (faked curl)", function()
  it("reads the index: versions, merged features, implicit features, yanked, junk lines", function()
    cache_setup()
    local calls = fake_curl({ ["index.crates.io/se/rd/serde"] = { body = INDEX_SERDE }, ["/crates/serde"] = { body = API_SERDE } })
    local info, err = cm.info("serde")
    H.ok(info, err)
    H.eq(3, #info.versions, "junk and invalid lines are dropped")
    H.eq("1.0.9", info.newest, "the newest version that is not yanked")
    H.eq({ "dep:serde_derive" }, info.features.derive, "features2 overrides")
    H.eq({ "std" }, info.features.default)
    H.eq({}, info.features.std)
    H.is_nil(info.features.serde_derive, "dep: is explicit, so no implicit feature")
    H.eq({ "dep:rand" }, info.features.rand, "an optional dependency becomes a feature of the same name")
    H.eq("A serialization framework", info.description)
    H.eq(123456, info.downloads)
    H.eq(789, info.recent_downloads)
    -- argv, never a shell string
'''),
    ...para('--', r'The first test reads the index. Three valid versions survive, the junk and invalid lines '
        r'are dropped, the newest is the highest non-yanked one (1.0.9, not the yanked 1.0.10), '
        r'features2 overrides features for derive, an optional dependency becomes a feature of the '
        r'same name unless it was named with dep:, and the API answer supplies the description and '
        r'downloads. Then it checks the command: curl as argv, the plugin’s user agent, --max-time '
        r'5, and the URL as the last element. An argv list, never a shell string.'),
    ...para('--', r'The offline behaviour. A fresh cache is served without a request, and refresh forces one. '
        r'When the network fails after the TTL passes (the test sets it to 0 and waits 1.1 seconds '
        r'because the TTL is in whole seconds), stale cached data is returned and marked stale. '
        r'With no cache the error is offline; an unknown crate is not found (404); a 503 is http '
        r'503. Names and queries are validated before anything is run: six bad names and four bad '
        r'queries, and the call list stays empty.'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 517-534', r'''
describe("crate_meta crates.io client (real curl, file:// stand-in)", function()
  it("runs curl with argv against the index layout", function()
    if vim.fn.executable("curl") ~= 1 then
      return skip("curl not found")
    end
    cache_setup()
    local srv = H.tmpdir()
    write(srv .. "/idx/se/rd/serde", INDEX_SERDE)
    stub(cm.config, "index_url", "file://" .. srv .. "/idx")
    stub(cm.config, "api_url", "file://" .. srv .. "/api")
    stub(cm.config, "proto", "=file")
    local info, err = cm.info("serde")
    H.ok(info, err)
    H.eq("1.0.9", info.newest)
    H.is_nil(info.downloads, "the API answer is optional")
    local _, e = cm.info("not-there")
    H.ok(e, "a missing file is an error value")
  end)
'''),
    ...para('--', r'Two tests with a real curl and file:// URLs. The first points index_url and api_url at a '
        r'temp directory, sets proto to =file and checks that the client runs curl against the '
        r'index layout and that the optional API answer may be absent. The second leaves the '
        r'default protocol rule and expects a file:// URL to be refused. This is the guard that '
        r'stops a poisoned URL from reading a local file.'),
    ...sec(r'the two network tests'),
    ...para('--', r'The group at lines 550 to 594 is guarded by an online check: curl must exist and an '
        r'actual request to the index must succeed within five seconds. Otherwise the tests skip '
        r'with no network to crates.io. They look up serde in the real index and search the real '
        r'API. They are the only tests in this file that depend on the outside world.'),
    ...sec(r'is_known_path_head'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 595-616', r'''
describe("crate_meta.is_known_path_head", function()
  local root, meta, main
  local function known(name, file)
    return cm.is_known_path_head(root, name, { file = file or main, meta = meta })
  end

  before_each(function()
    H.need_rust()
    root = make_workspace()
    main = root .. "/app/src/main.rs"
    meta = cm.metadata(root)
  end)

  it("knows keywords and the std crates", function()
    H.eq("keyword", (known("crate")))
    H.eq("keyword", (known("self")))
    H.eq("keyword", (known("super")))
    for _, n in ipairs(cm.std_crates) do
      H.eq("std", (known(n)))
    end
    H.eq({ "std", "core", "alloc", "proc_macro", "test" }, cm.std_crates)
  end)
'''),
    ...para('--', r'Given a file and the metadata, does the first segment of a path name something? Keywords '
        r'(crate, self, super) and the five std crates are known. A dependency is known by its '
        r'renamed name (helpers), and the original name (util) is not. dev and build dependencies '
        r'count. The package’s own library name is own_crate. Another member’s dependencies are not '
        r'in scope for this file. Local modules, inline modules, structs and macros are found from '
        r'the file tree, including a macro_rules! in a sibling file. Nothing returns nil, and an '
        r'unsaved buffer is read instead of the disk. On deps-lab, its dependencies are known, rand '
        r'is not, and a bin-only package has no library name.'),
    ...sec(r'code actions with a fake client'),
    ...para('--', r'The fake client implements request with a canned reply per method and schedules the '
        r'callback, like a real client would. It replaces the client lookup and get_client_by_id. '
        r'This lets the tests control exactly what the server says.'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 727-745', r'''
  it("requests with the range, diagnostics, only and the client's encoding, and normalises", function()
    local c = fake_client({
      ["textDocument/codeAction"] = {
        edit_action(buf, "Import `serde::Serialize`", "quickfix", "use serde::Serialize;\n"),
        { title = "Disabled", kind = "refactor", disabled = { reason = "x" } },
        { title = "Lazy", kind = "refactor.extract", data = { id = 1 } },
        { title = "Run it", kind = "source", command = { title = "Run it", command = "ra.run", arguments = { 1 } } },
      },
    })
    local diag = { lnum = 1, col = 5, end_lnum = 1, end_col = 8, message = "unresolved", severity = 1, source = "rustc" }
    local list, errs = ca.request_wait(buf, { start = { 1, 5 }, ["end"] = { 1, 8 } }, { diagnostics = { diag }, only = { "quickfix" } })
    H.is_nil(errs)
    H.eq(3, #list, "disabled actions are dropped")
    local p = c.requests[1].params
    H.eq({ line = 1, character = 4 }, p.range.start, "byte col 5 after the two-byte é is utf-16 char 4")
    H.eq({ line = 1, character = 7 }, p.range["end"])
    H.eq({ "quickfix" }, p.context.only)
    H.eq(1, #p.context.diagnostics)
    H.eq("unresolved", p.context.diagnostics[1].message)
'''),
    ...para('--', r'The request carries the range, the diagnostics, the only list and the client’s encoding. '
        r'The comment in the assertion explains one detail: byte column 5 after a two-byte é is '
        r'UTF-16 character 4. Disabled actions are dropped, so three of four survive, each '
        r'normalised to title, kind, is_preferred, edit or command, client_id and the raw action. A '
        r'bare position becomes an empty range.'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 805-822', r'''
  it("retries resolve while the server says content modified", function()
    local n = 0
    fake_client({
      ["textDocument/codeAction"] = { { title = "Lazy", kind = "quickfix", data = { id = 1 } } },
      ["codeAction/resolve"] = function()
        n = n + 1
        if n < 3 then
          return { err = { code = -32801, message = "content modified" } }
        end
        return edit_action(buf, "Lazy", "quickfix", "// ok\n")
      end,
    })
    local a = ca.request_wait(buf, { 0, 0 })[1]
    local ok, err = ca.apply(a)
    H.ok(ok, err)
    H.eq(3, n)
  end)

'''),
    ...para('--', r'A lazy action has no edit and is resolved with codeAction/resolve before it is applied. '
        r'When the server answers content modified (code -32801), apply retries; the test fails it '
        r'twice and expects three attempts. Any other error gives up with false and the message. '
        r'request_wait retries content-modified for the request itself and wait_for polls until an '
        r'action matching the filter appears. Several edits of one action are applied as one undo '
        r'step.'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 908-922', r'''
describe("code_actions (real rust-analyzer)", function()
  it("offers an Import action for an unresolved std name and applies it", function()
    H.need_rust()
    local dir, buf = H.open_fixture("basic", "src/lib.rs")
    write(dir .. "/src/lib.rs", "pub fn make() -> HashMap<u8, u8> {\n    HashMap::new()\n}\n")
    vim.cmd("edit!")
    buf = vim.api.nvim_get_current_buf()
    H.start_ra(buf, dir)
    local hits = ca.wait_for(buf, { 1, 5 }, { kind = "quickfix", title = "^Import `std::collections::HashMap`" }, { timeout = 90000 })
    H.ok(#hits >= 1, "rust-analyzer offered the import")
    local ok, err = ca.apply(hits[1])
    H.ok(ok, err)
    H.match(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"), "use std::collections::HashMap;", true)
  end)
end)
'''),
    ...para('--', r'The only real server test: an unresolved HashMap in a fixture file. rust-analyzer must '
        r'offer the import quick fix within 90 seconds, and applying it puts use '
        r'std::collections::HashMap; in the buffer.'),
    ...sec(r'bounded reads'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 924-942', r'''
describe("crate_meta bounded reads", function()
  it("does not read a symlink to /dev/zero, a FIFO or an oversized source file", function()
    local dir = H.tmpdir() .. "/evil"
    write(dir .. "/Cargo.toml", '[package]\nname = "evil"\nversion = "0.1.0"\n')
    vim.fn.mkdir(dir .. "/src", "p")
    vim.uv.fs_symlink("/dev/zero", dir .. "/src/lib.rs")
    H.is_nil((cm.read_lib(dir)))
    os.remove(dir .. "/src/lib.rs")
    if vim.fn.executable("mkfifo") == 1 then
      vim.system({ "mkfifo", dir .. "/src/lib.rs" }):wait()
      H.is_nil((cm.read_lib(dir))) -- would block forever on an open for reading
    end
    os.remove(dir .. "/src/lib.rs")
    write(dir .. "/src/lib.rs", string.rep("a", 3 * 1024 * 1024))
    H.is_nil((cm.read_lib(dir)))
    write(dir .. "/src/lib.rs", "pub fn x() {}\n")
    H.match((cm.read_lib(dir)), "pub fn x", true)
  end)
end)
'''),
    ...para('--', r'The last test is the sharpest. A crate source directory is data from the outside. A '
        r'src/lib.rs that is a symlink to /dev/zero, a FIFO (mkfifo) and a 3 MiB file must each be '
        r'refused by read_lib without hanging or reading everything. The comment on the FIFO says '
        r'why: it would block forever on an open for reading. Then a normal file is read.'),
    ...sec(r'design decisions'),
    ...pt('--', r'hermetic by default', r'the cache directory, the cargo home, the URLs and curl are all replaced. A failure then '
        r'means the plugin is wrong, not that crates.io is slow.'),
    ...pt('--', r'fixtures in code', r'make_workspace and the index text are written in the spec, next to their assertions, '
        r'instead of in files you have to open.'),
    ...pt('--', r'errors are values', r'every failure test asserts nil plus a string and no raised error. That is the convention '
        r'of the module header.'),
    ...sec(r'gaps'),
    ...para('--', r'Async variants have one test each; the ordering of overlapping async calls is not tested.'),
    ...para('--', r'On Windows only the binary-mode writer is covered by the history. The README states the '
        r'Windows guards of the original code are kept without evidence from this repository.'),
    ...sec(r'history'),
    ...pt('--', r'6e1b567, 2026-10-14', r'xynovim: the foundation modules crate_meta and code_actions, with fixtures and this spec.'),
    ...pt('--', r'19f974c, 2026-10-15', r'review fixes: 20 lines of tests added.'),
    ...pt('--', r'9641d08, 2026-10-16', r'Windows and macOS runs: the writer in the spec opens files in binary mode (wb).'),
    ...pt('--', r'6524272, 2026-10-21', r'.exe suffix and drive-letter case fixes in crate_meta.'),
    ...pt('--', r'7c1d2d9, 2026-10-22', r'this repository: namespace, the user agent and the cache directory carry the plugin name '
        r'(xyno-rust.nvim).'),
  ],
);
