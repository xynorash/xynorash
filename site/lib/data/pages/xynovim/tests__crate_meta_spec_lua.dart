import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/crate-meta_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'crate-meta_spec.lua — cargo metadata, the crates.io index and code actions as plain functions'),
    cm('--', r'validation that refuses what a shell could misread, a faked curl, a fake LSP client, and a hostile source file'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/crate_meta.lua and lua/config/code_actions.lua, the foundation of the macros and dependencies features'),
    kv(r'language', r'Lua spec, 942 lines, 44 it() blocks, 10 describe() blocks'),
    kv(r'hermetic', r'path-only temp workspaces, a fake CARGO_HOME, a faked or file:// curl, a fake LSP client'),
    kv(r'network', r'two tests skip without it; the deps-lab tests skip unless cargo metadata --offline succeeds'),
    kv(r'history', r'3 commits: 6e1b567 (2026-10-14), 19f974c (2026-10-15), 9641d08 (2026-10-16)'),
    ...sec(r'why this file exists'),
    ...para('--', r'crate_meta is the layer that other modules ask about Rust projects: who are the members, what are the dependencies by kind, which versions of a crate exist, what features does this crate have, is this name a known path head. code_actions is the layer that talks to language servers: request, filter, apply, wait. Everything in crate_add, crate_features, crate_import and the import engine rests on them. The spec was written in the first commit of the feature (6e1b567, "foundation modules (crate_meta, code_actions) and fixtures"). Its header says how everything is made hermetic.'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 1-6', r'''
-- config.crate_meta (cargo metadata, registry sources, crates.io client, known
-- path heads) and config.code_actions (request, filter, apply, wait).
-- Hermetic: path-only temp workspaces, a fake CARGO_HOME, a faked or file://
-- curl, a fake LSP client. The deps-lab fixtures need cargo metadata --offline
-- to succeed (the registry must already hold their crates) and skip otherwise;
-- the two network tests skip without network.'''),
    ...sec(r'names and versions are validated before use'),
    ...para('--', r'The first block is a statement of principle. Crate names are accepted only when a shell or a path could not misread them, versions only when they are semver-ish, versions are compared numerically with pre-releases first, and the sparse index path for a name is built by the module. Almost every other module passes crate names from buffers or the network to commands, so this one place decides what a name may look like.'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 80-87, 89-96, 98-104', r'''
  it("accepts crate names and rejects anything a shell or path could misread", function()
    for _, n in ipairs({ "serde", "serde_json", "tokio-util", "a1" }) do
      H.ok(cm.valid_name(n), n)
    end
    for _, n in ipairs({ "", "a b", "a/b", "../x", "a;b", "a$(x)", "a\nb", "é", string.rep("a", 65), 5 }) do
      H.not_ok(cm.valid_name(n), vim.inspect(n))
    end
  end)
...
  it("accepts semver-ish versions only", function()
    for _, v in ipairs({ "1.0.0", "0.9.15", "1.2.3-rc.1", "1.0.0+build.5" }) do
      H.ok(cm.valid_version(v), v)
    end
    for _, v in ipairs({ "1", "1.0", "^1.0.0", "1.0.0; rm", "../1.0.0", "" }) do
      H.not_ok(cm.valid_version(v), v)
    end
  end)
...
  it("compares versions numerically and puts pre-releases first", function()
    H.eq(-1, cm.compare_versions("1.0.9", "1.0.10"))
    H.eq(1, cm.compare_versions("2.0.0", "1.99.99"))
    H.eq(0, cm.compare_versions("1.2.3", "1.2.3"))
    H.eq(-1, cm.compare_versions("1.0.0-rc.1", "1.0.0"))
    H.eq(1, cm.compare_versions("1.0.0", "1.0.0-rc.1"))
  end)'''),
    ...sec(r'metadata as a value, not an exception'),
    ...para('--', r'metadata reads members, dependencies by kind, renames, optional flags and features; caches until a manifest or the lock file changes; has an async variant; and returns an error value outside a workspace and for a broken manifest rather than raising. That choice shapes all callers, who test for nil plus a message and never need pcall.'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 208-218', r'''
  it("returns an error value, not an exception, outside a workspace and for a broken manifest", function()
    H.need_rust()
    local dir = H.tmpdir()
    local m, e = cm.metadata(dir)
    H.is_nil(m)
    H.match(e, "workspace", true)
    write(dir .. "/Cargo.toml", "this is [not toml")
    local m2, e2 = cm.metadata(dir)
    H.is_nil(m2)
    H.ok(type(e2) == "string" and #e2 > 0)
  end)'''),
    ...sec(r'a faked crates.io client'),
    ...para('--', r'The client calls curl with an argument list. The tests fake curl, so the behaviour around the network can be tested exactly: the index lines give versions, merged features, implicit features and yanked flags (junk lines are skipped); a fresh cache is served without a request while refresh forces one; and with the network gone the module falls back to stale cached data and says so. The stale test fakes a curl that answers, sets the cache time-to-live to 0, waits 1.1 seconds because the TTL is in whole seconds (the comment says so), then fakes a curl failing with exit code 6 and requires the cached answer with stale set to true and the newest version still 1.0.9.'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 429-440', r'''
  it("falls back to stale cached data when offline, and says so", function()
    cache_setup()
    stub(cm.config, "index_ttl", 0)
    fake_curl({ ["index.crates.io"] = { body = INDEX_SERDE }, ["/crates/"] = { body = API_SERDE } })
    H.ok(cm.info("serde"))
    vim.wait(1100) -- the TTL is in whole seconds
    fake_curl({ ["index.crates.io"] = { code = 6, err = "Could not resolve host" }, ["/crates/"] = { code = 6 } })
    local info, err = cm.info("serde")
    H.ok(info, err)
    H.eq(true, info.stale)
    H.eq("1.0.9", info.newest)
  end)'''),
    ...para('--', r'Other tests: an offline error value without a cache, not found for an unknown crate, names and queries validated before anything runs, search with url-encoded query and per_page, and async variants. A separate block runs real curl against a file:// index laid out like the real one, and checks that non-https URLs are refused under the default protocol rule.'),
    ...sec(r'reading source files from untrusted crates'),
    ...para('--', r'Registry sources are other people files. The bounded reads test is the security highlight: a lib.rs that is a symlink to /dev/zero, a FIFO (which would block forever on open) and an oversized file of three megabytes must each give nil, and a normal file after them must be read again. The test removes the file between steps and runs the FIFO case only when mkfifo exists.'),
    ...code('lua', r'tests/crate-meta_spec.lua · lines 925-941', r'''
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
  end)'''),
    ...sec(r'known path heads'),
    ...para('--', r'is_known_path_head answers whether a leading identifier is something: keywords and the std crates, dependencies of the file member, renames, the own lib name, local modules, items and macros found in the file tree. It reads an unsaved buffer, not the disk, and answers nil for nonsense. This is the function crate_add trusts not to flag valid code.'),
    ...sec(r'code actions against a fake client'),
    ...para('--', r'The code_actions block builds a fake language client and checks the request carries the range, diagnostics, only filter and the client offset encoding; that filtering works by kind with a dot-prefix, title pattern, literal title and preferred flag; that edits apply with the client encoding; that a lazy action is resolved before applying, with retries while the server says content modified, and gives up with an error value; that a command is run via workspace/executeCommand; that several edits form one undo step; and that a missing client is reported as a value. One test uses the real rust-analyzer to apply an Import action for an unresolved std name.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'6e1b567 (2026-10-14)', r'foundation modules and fixtures.'),
    ...pt('--', r'19f974c (2026-10-15)', r'review fixes. 9641d08 (2026-10-16) :: drive letter in canonical roots on Windows.'),
  ],
);
