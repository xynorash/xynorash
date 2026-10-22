import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/egui-new_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'egui-new_spec.lua — a new egui project from the live template, tested without trusting the network'),
    cm('--', r'a ZIP built in the test, a tiny HTTP server inside nvim, and every way an archive can be hostile'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/egui_new.lua (:EguiNew and the New egui Project dashboard entry) and lua/plugins/egui.lua'),
    kv(r'language', r'Lua spec, 1498 lines, 66 it() blocks, 14 describe() blocks, 300 second timeout'),
    kv(r'limits', r'a header requests a 300 second timeout; Linux and macOS only (sh stubs, file mode bits, sed -i)'),
    kv(r'network', r'one test downloads the real template and skips without network'),
    kv(r'history', r'7 commits, 2026-10-15 to 2026-10-21'),
    ...sec(r'why this file exists'),
    ...para('--', r':EguiNew creates a new egui application from the current eframe_template: it downloads the template ZIP, renames the crate, edits the manifest, lockfile, README and title text, moves the result into place and opens main.rs. That is a download-and-unpack pipeline on top of a moving upstream, so every part can fail in a way that hurts: a name that is not a valid crate, a template that changed its file list, an archive that tries to write outside the target, a server that is down. The header shows the strategy: pure text functions first, with a trimmed copy of the real template files embedded as fixtures; then the whole flow against a local fake template served through file:// or a tiny http server inside this nvim.'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 1-8', r'''
-- xyno-timeout: 300
-- config.egui_new (:EguiNew and the "New egui Project" dashboard entry) and
-- lua/plugins/egui.lua. Pure text functions first (a trimmed copy of today's
-- eframe_template files is embedded as fixtures), then the whole flow against
-- a LOCAL fake template: a ZIP built here and served through a file:// or an
-- http://127.0.0.1 base_url (a tiny server inside this nvim, so the ETag /
-- If-None-Match / offline-cache behaviour is exercised without the network).
-- ONE test downloads the real template and skips without network.'''),
    ...sec(r'a scale for names'),
    ...para('--', r'validate_name has a table of cases that is a specification in itself. Accepted: names with underscores, hyphens turned into underscores (-lead becomes _lead), 64 characters, surrounding spaces trimmed. Rejected with a reason fragment that must appear in the message: empty or blank, 65 characters, starting with a digit, a lone underscore, spaces, dots, slashes, shell characters and newlines, Rust keywords (fn, match, Self, async, gen), reserved names (test, core, std, alloc, proc_macro, build), the template own name in both spellings, and every dependency name of the template (egui, eframe, log, serde, env-logger, web_sys, wasm-bindgen-futures), because a crate cannot depend on a crate with its own name. A separate test shows that the whole non-ASCII character in the name is named in the message.'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 395-436', r'''
    { "_private", "_private" },
    { "-lead", "_lead", true },
    { "a", "a" },
    { "a1_b2", "a1_b2" },
    { ("x"):rep(64), ("x"):rep(64) },
    { "  spaced  ", "spaced" },
    { "", nil, "empty" },
    { "   ", nil, "empty" },
    { ("x"):rep(65), nil, "64" },
    { "1app", nil, "start with a letter" },
    { "9", nil, "start with a letter" },
    { "_", nil, "not a valid" },
    { "my app", nil, "not allowed" },
    { "my.app", nil, "not allowed" },
    { "my/app", nil, "not allowed" },
    { "../x", nil, "not allowed" },
    { "app;rm", nil, "not allowed" },
    { "app\nx", nil, "not allowed" },
    { 'a"b', nil, "not allowed" },
    { "fn", nil, "keyword" },
    { "match", nil, "keyword" },
    { "Self", nil, "keyword" },
    { "async", nil, "keyword" },
    { "gen", nil, "keyword" },
    { "test", nil, "reserved" },
    { "core", nil, "reserved" },
    { "std", nil, "reserved" },
    { "alloc", nil, "reserved" },
    { "proc_macro", nil, "reserved" },
    { "proc-macro", nil, "reserved" },
    { "build", nil, "reserved" },
    { "eframe_template", nil, "template's own" },
    { "eframe-template", nil, "template's own" },
    { "egui", nil, "dependency" },
    { "eframe", nil, "dependency" },
    { "log", nil, "dependency" },
    { "serde", nil, "dependency" },
    { "env-logger", nil, "dependency" },
    { "web_sys", nil, "dependency" },
    { "wasm-bindgen-futures", nil, "dependency" },
  }
  for _, c in ipairs(cases) do'''),
    ...sec(r'editing text exactly'),
    ...para('--', r'The tests of the text functions describe what is changed and what is not: the crate name is replaced but not links to the template; several occurrences per line work; the name is plain text, with no pattern characters; eframe_template with an underscore stays alone in replace_title. edit_cargo_toml touches only [package], keeps a trailing comment and CRLF line endings, replaces a multi-line authors array whole, and adds a missing line after name. edit_cargo_lock renames only the template own package and moves the entry to its sorted place, because cargo --locked wants the order, while keeping every other byte, header and final newline.'),
    ...sec(r'the whole flow against a fake template'),
    ...para('--', r'The create block builds a ZIP in the test and points vim.g.xynovim_egui_template at a file:// base_url. It checks that the project is downloaded, personalised and moved into place, that the executable bit of archived files is kept, that no authors removes the line and only a name gives Name, that new files with the token are handled so the code does not depend on today file list, that missing parent directories are created and removed again when the run fails, and that a curl failure without a cached copy is a clear error that leaves nothing behind.'),
    ...sec(r'a hostile archive'),
    ...para('--', r'This test is the security core. It builds three archives and requires an unsafe entry error for each, with nothing left behind. The first has an entry named top/../../evil.txt that would write outside the target; the test also checks that no evil.txt appeared next to the parent. The second has an absolute path entry. The third contains a symlink entry pointing to /etc/passwd. After each case the cache is deleted so that the next archive is really downloaded. The parent directory must be empty at the end.'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 794-816', r'''
  it("rejects archives whose entries escape the target or are symlinks", function()
    local parent = H.tmpdir()
    local root = H.tmpdir()
    vim.g.xynovim_egui_template = { base_url = "file://" .. root }
    local z = root .. "/emilk/eframe_template/archive/main.zip"
    build_zip(z, { { name = "top/ok.txt", text = "1" }, { name = "top/../../evil.txt", text = "x" } })
    local err = create({ crate = "slip", author_name = "", author_email = "", parent = parent })
    H.match(err, "unsafe entry")
    H.is_nil(vim.uv.fs_stat(vim.fs.dirname(parent) .. "/evil.txt"))
    H.eq({}, leftovers(parent))

    build_zip(z, { { name = "/abs/evil.txt", text = "x" }, { name = "top/ok.txt", text = "1" } })
    vim.fn.delete(cache_dir(), "rf")
    err = create({ crate = "slip", author_name = "", author_email = "", parent = parent })
    H.match(err, "unsafe entry")

    build_zip(z, { { name = "top/ok.txt", text = "1" }, { name = "top/link", link = "/etc/passwd" } })
    vim.fn.delete(cache_dir(), "rf")
    err = create({ crate = "linked", author_name = "", author_email = "", parent = parent })
    H.match(err, "unsafe entry")
    H.eq({}, leftovers(parent))
    H.eq({}, vim.fn.glob(parent .. "/*", true, true))
  end)'''),
    ...sec(r'the toolchain pin'),
    ...para('--', r'An earlier version of the feature prepared the pinned toolchain of the template. That was removed in commit 0cfb739 (2026-10-16, "stop enforcing the template toolchain pin (keep rust-version as the minimum), remove toolchain preparation"). The test now states the new behaviour: the pin is removed in every form (a legacy one-line rust-toolchain, both files with the same content, and a rust-toolchain.toml next to an empty rust-toolchain), the rust-version field of Cargo.toml is kept byte for byte, and the README no longer mentions the toolchain.'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 718-736', r'''
  it("removes the toolchain pin in every form (legacy one-line, rust-toolchain.toml) and keeps rust-version byte for byte", function()
    local forms = {
      { { name = "rust-toolchain", text = "1.95.0\n" } },
      { { name = "rust-toolchain", text = TOOLCHAIN }, { name = "rust-toolchain.toml", text = TOOLCHAIN } },
      { { name = "rust-toolchain.toml", text = TOOLCHAIN }, { name = "rust-toolchain", text = "" } },
    }
    for i, extra in ipairs(forms) do
      file_template(extra)
      local parent = H.tmpdir()
      local err = create({ crate = "np" .. i, author_name = "", author_email = "", parent = parent })
      H.is_nil(err, err)
      local dir = parent .. "/np" .. i
      H.is_nil(vim.uv.fs_lstat(dir .. "/rust-toolchain"), "form " .. i)
      H.is_nil(vim.uv.fs_lstat(dir .. "/rust-toolchain.toml"), "form " .. i)
      H.eq(E.parse_rust_version(CARGO_TOML), E.parse_rust_version(read(dir .. "/Cargo.toml")))
      H.has(read(dir .. "/Cargo.toml"), '\nrust-version = "1.95"\n')
      H.no_match(read(dir .. "/README.md"), "toolchain", true)
    end
  end)'''),
    ...sec(r'ETag, conditional request, offline cache'),
    ...para('--', r'The fetch block starts a real HTTP server inside nvim on 127.0.0.1 and records every request. The scenario is told as a story in one test. First download: one request, GET of the archive path, no If-None-Match header, the User-Agent xynovim (github.com/xynorash/xynovim), and a cached ZIP. Second create: the request carries If-None-Match with the ETag, the server answers 304 and the cache is used. The template changes: a new body and ETag lead to a new download. The server answers 500: the cached copy is used and a warning is shown. The server is gone: the cached copy again, with a warning. And with no cache and no server: a clear error. Other tests make sure a 200 answer that is not a ZIP never replaces the cache, a cache of another template is never used, and an ETag that is not a single printable line is ignored.'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 852-896', r'''
  it("asks again with If-None-Match, downloads only on a change, falls back offline", function()
    local z1, z2 = H.tmpdir() .. "/v1.zip", H.tmpdir() .. "/v2.zip"
    fake_zip(z1)
    fake_zip(z2, { { name = "NEW_IN_V2.txt", text = "v2" } })
    local srv = serve(read(z1), '"v1"')
    vim.g.xynovim_egui_template = { base_url = "http://127.0.0.1:" .. srv.port }
    local parent = H.tmpdir()
    local cap = H.capture_notify()

    H.is_nil(create({ crate = "one", author_name = "", author_email = "", parent = parent }))
    H.eq(1, #srv.requests)
    H.eq("GET /emilk/eframe_template/archive/main.zip HTTP/1.1", srv.requests[1].line)
    H.is_nil(srv.requests[1].inm)
    H.eq("xynovim (github.com/xynorash/xynovim)", srv.requests[1].ua)
    H.ok(vim.uv.fs_stat(cache_dir() .. "/egui-template.zip"), "the zip is cached")

    -- same template: 304, the cached copy is used
    H.is_nil(create({ crate = "two", author_name = "", author_email = "", parent = parent }))
    H.eq(2, #srv.requests)
    H.eq('"v1"', srv.requests[2].inm)
    H.ok(vim.uv.fs_stat(parent .. "/two/Cargo.toml"))
    H.is_nil(vim.uv.fs_stat(parent .. "/two/NEW_IN_V2.txt"))

    -- the template changed: downloaded again
    srv.body, srv.etag = read(z2), '"v2"'
    H.is_nil(create({ crate = "three", author_name = "", author_email = "", parent = parent }))
    H.eq(3, #srv.requests)
    H.eq('"v1"', srv.requests[3].inm)
    H.eq("v2", read(parent .. "/three/NEW_IN_V2.txt"))
    H.eq({}, leftovers(parent))

    -- the server errors: the cached copy is used with a warning
    srv.mode = "500"
    H.is_nil(create({ crate = "four", author_name = "", author_email = "", parent = parent }))
    H.eq("v2", read(parent .. "/four/NEW_IN_V2.txt"))
    H.ok(find_msg(cap, "cached template", vim.log.levels.WARN), "warns about the cached copy")

    -- the server is gone
    srv.stop()
    vim.wait(100)
    cap.list = {}
    H.is_nil(create({ crate = "five", author_name = "", author_email = "", parent = parent }))
    H.ok(vim.uv.fs_stat(parent .. "/five/Cargo.toml"))
    H.ok(find_msg(cap, "cached template", vim.log.levels.WARN))
'''),
    ...sec(r'the prompts'),
    ...para('--', r':EguiNew asks name, author, e-mail and parent directory (prefilled), then creates the project, changes into it and opens main.rs. An argument skips the name prompt, an invalid name re-prompts with the reason, bad authors, an existing target and a file as a parent re-prompt, a missing parent is created only after asking (a No creates nothing), a tilde is expanded, cancelling any prompt aborts silently and leaves nothing, and a failed download is reported as an error after which a second run works. The option vim.g.xynovim_egui_build_after_new starts cargo build in a terminal, and without it nothing is built.'),
    ...sec(r'the dashboard entry'),
    ...para('--', r'The New egui Project entry sits before Quit with a unique key in the merged preset, both layouts (tall and short) render the preset keys, and at 80 columns the entry is visible together with Quit and the footer, and the key e opens the name prompt.'),
    ...sec(r'the minimum Rust version'),
    ...para('--', r'The template says which Rust it needs through rust-version. The pure functions parse_version, parse_rustc and parse_rust_version are tested with tables, including a missing patch component counting as .0 and a nightly suffix being ignored. check_rust_version is tested with a rustc stub on PATH: an older rustc gives one warning with both versions and the update command, equal or newer is silent, rustc is run inside the project so a project-local override is honoured, a missing rustc is said once and does not fail, and garbage output gives one note.'),
    ...sec(r'no rustup call'),
    ...para('--', r'The last test is a regression guard for the removal of the toolchain preparation. It writes stub rustup and rustc scripts into a temp bin directory, the second printing rustc 1.90.0, prepends it to PATH, creates a project from a template with a pin, runs finish and requires the warning run rustup update stable and needs Rust >= 1.95 (you have 1.90.0). It then requires that the rustup log file does not exist, that E.prepare_toolchain, E.runner and E.kill_jobs are nil, and that the autocmd group XynovimEguiToolchain does not exist.'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 1470-1497', r'''
  it("a project made from a template with a pin never runs rustup; an old rustc gets the warning", function()
    file_template()
    local bin, log = H.tmpdir(), H.tmpdir() .. "/rustup.log"
    write(bin .. "/rustup", ("#!/bin/sh\necho \"$*\" >> %s\n"):format(log))
    write(bin .. "/rustc", "#!/bin/sh\necho 'rustc 1.90.0 (x 2026-01-01)'\n")
    vim.uv.fs_chmod(bin .. "/rustup", tonumber("755", 8))
    vim.uv.fs_chmod(bin .. "/rustc", tonumber("755", 8))
    local orig = vim.env.PATH
    vim.env.PATH = bin .. ":" .. orig
    restores[#restores + 1] = function()
      vim.env.PATH = orig
    end
    local parent = H.tmpdir()
    local cap = H.capture_notify()
    local err, info = create({ crate = "min_app", author_name = "", author_email = "", parent = parent })
    H.is_nil(err, err)
    E.finish(info)
    H.wait_for(function()
      return find_msg(cap, "run rustup update stable", vim.log.levels.WARN)
    end, 10000, "the minimum-version warning")
    H.ok(find_msg(cap, "needs Rust >= 1%.95 %(you have 1%.90%.0%)"))
    vim.wait(300)
    H.is_nil(vim.uv.fs_stat(log), "rustup was never called")
    H.eq(nil, E.prepare_toolchain)
    H.eq(nil, E.runner)
    H.eq(nil, E.kill_jobs)
    H.not_ok((pcall(vim.api.nvim_get_autocmds, { group = "XynovimEguiToolchain" })), "no toolchain autocmd group")
  end)'''),
    ...sec(r'history'),
    blank,
    ...pt('--', r'ddc51eb, 59cc11b (2026-10-15)', r'New egui Project on the dashboard and :EguiNew, review fixes.'),
    ...pt('--', r'b020526, d2ac9a4 (2026-10-15)', r'toolchain preparation and its review fixes.'),
    ...pt('--', r'0cfb739 (2026-10-16)', r'toolchain pin no longer enforced.'),
    ...pt('--', r'ff1c8fa (2026-10-16), 6524272 (2026-10-21)', r'platform work; the file is Linux and macOS only.'),
  ],
);
