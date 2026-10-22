import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-new.nvim/tests/egui-new_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'tests/egui-new_spec.lua — testing a downloader without a network'),
    cm('--', r'a fake template built in Python, served from file:// or a 45-line HTTP server'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'tests', r'lua/xyno_new/egui.lua'),
    kv(r'size', r'1,419 lines, 63 cases in 13 groups; the largest file in the repository'),
    kv(r'needs', r'curl, unzip, python3 (skips with a message), git, sh stubs: xyno-os linux,macos'),
    kv(r'network', r'one case downloads the real template and skips without network'),
    kv(r'origin', r'tests/egui-new_spec.lua in xynovim: 1,244 lines at ddc51eb (2026-10-15)'),
    ...sec(r'the plan in the header'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 1-9', r'''
-- xyno-timeout: 300
-- xyno_new.egui (:EguiNew). Pure text functions first (a trimmed copy of today's
-- eframe_template files is embedded as fixtures), then the whole flow against
-- a LOCAL fake template: a ZIP built here and served through a file:// or an
-- http://127.0.0.1 base_url (a tiny server inside this nvim, so the ETag /
-- If-None-Match / offline-cache behaviour is exercised without the network).
-- ONE test downloads the real template and skips without network.
-- xyno-os: linux,macos (sh stubs, file mode bits, sed -i)
local H = require("xyno_new_test.helpers")'''),
    ...para('--', r'Pure text functions first, with a trimmed copy of the template’s real files embedded as fixtures; then the whole flow against a local fake template; then one test against the real template. The header names the two ways the fake is served, because they exercise different code: file:// proves the fetch, unpack and personalise path, and http://127.0.0.1 proves ETag, If-None-Match and the offline cache.'),
    ...sec(r'fixtures that are dated'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 87-124, 161-169', r'''
-- trimmed from the template as downloaded on 2026-10-15
local CARGO_TOML = [==[
[package]
name = "eframe_template"
version = "0.1.0"
authors = ["Template Author <author@example.org>"]
edition = "2024"
license = "MIT OR Apache-2.0"
include = ["LICENSE-APACHE", "LICENSE-MIT", "**/*.rs", "Cargo.toml"]
rust-version = "1.95"

[package.metadata.docs.rs]
all-features = true
targets = ["x86_64-unknown-linux-gnu", "wasm32-unknown-unknown"]

[dependencies]
egui = "0.36.0"
eframe = { version = "0.36.0", features = ["persistence"] }
log = "0.4.27"

# You only need serde if you want app persistence:
serde = { version = "1.0.219", features = ["derive"] }

# native:
[target.'cfg(not(target_arch = "wasm32"))'.dependencies]
env_logger = "0.11.8"

# web:
[target.'cfg(target_arch = "wasm32")'.dependencies]
wasm-bindgen-futures = "0.4.50"
web-sys = "0.3.70"              # to access the DOM (to hide the loading text)

[profile.release]
opt-level = 2 # fast and small wasm

[lints]
workspace = true
]==]
...
local MAIN_RS = [==[
fn main() -> eframe::Result {
    eframe::run_native(
        "eframe template",
        native_options,
        Box::new(|cc| Ok(Box::new(eframe_template::TemplateApp::new(cc)))),
    )
}
]==]'''),
    ...para('--', r'The fixtures are literal strings with a comment giving the date the real template was downloaded. They are trimmed, not invented: CARGO_TOML keeps the sections that matter (a package with an authors array, rust-version, dependencies, two target-specific dependency tables, a profile and a lints table); CARGO_LOCK has four packages in cargo’s sorted order with the template second, so a rename to most names has to move it; MAIN_RS and APP_RS contain the eframe template window title and a link back to the template, the two cases replace_token must tell apart. A fixture is a snapshot, which has a cost: when the template changes, these do not, and the one real-template test exists to notice.'),
    ...sec(r'building ZIPs'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 248-262', r'''
local PY = [[
import sys, json, zipfile
out = sys.argv[1]
with open(sys.argv[2]) as f:
    spec = json.load(f)
with zipfile.ZipFile(out, "w") as z:
    for e in spec:
        zi = zipfile.ZipInfo(e["name"])
        if e.get("link"):
            zi.external_attr = 0o120777 << 16
            z.writestr(zi, e["link"])
        else:
            zi.external_attr = e.get("mode", 0o100644) << 16
            z.writestr(zi, e.get("text", ""))
]]'''),
    ...para('--', r'Archives are made by a short Python script run with python3 -I (isolated mode: no user site, no environment influence). Entries come from a JSON spec: a name, text, an optional mode, or a link. Setting external_attr to 0o120777 shifted by 16 makes a symlink entry, which is how the unpacker’s symlink rejection is tested; mode 100755 for fill_template.sh is how the executable bit test works. The script writes the entry names exactly as given, which is how the test archives get a name like top/../../evil.txt.'),
    ...sec(r'serving them: a 45-line HTTP server in the test editor'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 292-336', r'''
local function serve(body, etag)
  local srv = vim.uv.new_tcp()
  srv:bind("127.0.0.1", 0)
  local state = { requests = {}, body = body, etag = etag, mode = "ok", port = srv:getsockname().port }
  srv:listen(8, function()
    local c = vim.uv.new_tcp()
    srv:accept(c)
    local buf = ""
    c:read_start(function(err, chunk)
      if err or not chunk then
        return c:close()
      end
      buf = buf .. chunk
      if not buf:find("\r\n\r\n", 1, true) then
        return
      end
      c:read_stop()
      local inm = buf:match("[Ii]f%-[Nn]one%-[Mm]atch: ([^\r\n]+)")
      local ua = buf:match("[Uu]ser%-[Aa]gent: ([^\r\n]+)")
      state.requests[#state.requests + 1] = { line = buf:match("^[^\r\n]+"), inm = inm, ua = ua }
      local resp
      if state.mode == "500" then
        resp = "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
      elseif inm and inm == state.etag then
        resp = "HTTP/1.1 304 Not Modified\r\nETag: " .. state.etag .. "\r\nConnection: close\r\n\r\n"
      else
        resp = ("HTTP/1.1 200 OK\r\nContent-Type: application/zip\r\nETag: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"):format(
          state.etag, #state.body
        ) .. state.body
      end
      c:write(resp, function()
        c:shutdown(function()
          c:close()
        end)
      end)
    end)
  end)
  state.stop = function()
    if not srv:is_closing() then
      srv:close()
    end
  end
  restores[#restores + 1] = state.stop
  return state
end'''),
    ...para('--', r'serve binds a TCP server with vim.uv on 127.0.0.1 with port 0 (the OS picks one), and returns a state table: the recorded requests, the body, the ETag, the mode and the port. For each connection it reads until the blank line that ends the HTTP headers, records the request line, the If-None-Match header and the User-Agent, then answers: 500 if mode is 500; 304 with the ETag if the client sent a matching If-None-Match; otherwise 200 with the ZIP, a Content-Length and the ETag. The state is mutable, so a test can change body and etag between calls to simulate a template update, or flip mode to 500, or call stop() to simulate a vanished server. Registering stop in the restorers means a failing test cannot leave the port open.'),
    ...sec(r'the fetch, told as a story'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 852-903', r'''
  it("asks again with If-None-Match, downloads only on a change, falls back offline", function()
    local z1, z2 = H.tmpdir() .. "/v1.zip", H.tmpdir() .. "/v2.zip"
    fake_zip(z1)
    fake_zip(z2, { { name = "NEW_IN_V2.txt", text = "v2" } })
    local srv = serve(read(z1), '"v1"')
    vim.g.xyno_new_egui_template = { base_url = "http://127.0.0.1:" .. srv.port }
    local parent = H.tmpdir()
    local cap = H.capture_notify()

    H.is_nil(create({ crate = "one", author_name = "", author_email = "", parent = parent }))
    H.eq(1, #srv.requests)
    H.eq("GET /emilk/eframe_template/archive/main.zip HTTP/1.1", srv.requests[1].line)
    H.is_nil(srv.requests[1].inm)
    H.eq("xyno-new.nvim (github.com/xynorash/xyno-new.nvim)", srv.requests[1].ua)
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

    -- no cache, no server: a clear error
    vim.fn.delete(cache_dir(), "rf")
    local err = create({ crate = "six", author_name = "", author_email = "", parent = parent })
    H.match(err, "no cached copy")
    H.is_nil(vim.uv.fs_stat(parent .. "/six"))
    H.eq({}, leftovers(parent))
  end)'''),
    ...para('--', r'This one case is the best documentation of the caching behaviour. It creates a project five times plus a failing sixth, and each step asserts both the request log and the filesystem. 1: the first request has no If-None-Match, the right path, the plugin’s user agent, and leaves a cached ZIP. 2: the second sends the ETag and gets 304; the project is built from cache (a file that only the v2 archive has is absent). 3: the server now has v2 and another ETag; the client sends the old ETag, gets 200, and the project has the new file. 4: the server answers 500; the project is still created from cache and a WARN about the cached template appears. 5: the server is gone entirely; same outcome. 6: cache deleted, no server: the error says “no cached copy”, and nothing exists.'),
    ...para('--', r'Three neighbours extend this. A 200 answer with an HTML body, like a captive portal, never replaces the cached ZIP and the old ETag file survives. A cache written for another URL (a different ref) is never used. A cached ETag containing CR LF and a forged header line is not sent: the spec asserts the request carries no If-None-Match header.'),
    ...sec(r'hostile archives'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 794-816', r'''
  it("rejects archives whose entries escape the target or are symlinks", function()
    local parent = H.tmpdir()
    local root = H.tmpdir()
    vim.g.xyno_new_egui_template = { base_url = "file://" .. root }
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
    ...para('--', r'The same archive builder produces zip-slip names. Three archives in sequence: one with a name that climbs out with .., one with an absolute path, one with a symlink to /etc/passwd. Each time the cache directory is deleted so the next archive is fetched again, and each time the error must say “unsafe entry”. The first check goes further than the message: it asserts that no evil.txt appeared in the parent of the parent directory, so the test fails on the harm, not only on the diagnostic. The parent directory must also be left with no stray temp directories (leftovers returns the .egui-new-* entries).'),
    ...sec(r'pure text functions'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 542-545, 547-550', r'''
  it("only touches [package]: name keys elsewhere stay", function()
    local t = '[package]\nname = "a"\n\n[[bin]]\nname = "tool"\nauthors = ["x"]\n\n[lib]\nname = "a_lib"\n'
    H.eq('[package]\nname = "b"\nauthors = ["N"]\n\n[[bin]]\nname = "tool"\nauthors = ["x"]\n\n[lib]\nname = "a_lib"\n', E.edit_cargo_toml(t, "b", "N"))
  end)
...
  it("keeps a trailing comment and CRLF line ends", function()
    local t = '[package]\r\nname = "a" # the name\r\nauthors = ["x"]\r\nversion = "1"\r\n'
    H.eq('[package]\r\nname = "b" # the name\r\nauthors = ["N"]\r\nversion = "1"\r\n', E.edit_cargo_toml(t, "b", "N"))
  end)'''),
    ...para('--', r'Each text function has cases for the happy path and the traps: the name key of a [[bin]] table is untouched, authors in another table is untouched, a trailing comment survives, CRLF survives, a multi-line authors array is replaced by one line, a missing authors line is added after name.'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 582-589', r'''
  it("moves the entry to its sorted place (cargo --locked wants the order)", function()
    local out = E.edit_cargo_lock(CARGO_LOCK, "my_app")
    H.eq({ "eframe", "egui", "log", "my_app" }, names(out))
    out = E.edit_cargo_lock(CARGO_LOCK, "aaa")
    H.eq({ "aaa", "eframe", "egui", "log" }, names(out))
    out = E.edit_cargo_lock(CARGO_LOCK, "ega")
    H.eq({ "eframe", "ega", "egui", "log" }, names(out))
  end)'''),
    ...para('--', r'The Cargo.lock cases show why the lockfile function is not a one-line gsub. Renaming the template to my_app must move it after log; renaming to aaa moves it before eframe; renaming to ega puts it between eframe and egui. The names() helper extracts the order of [[package]] names so the assertion reads as a list. A companion case checks the byte length: the output is exactly nine bytes shorter than the input, the difference between eframe_template and my_app, so nothing else changed. Another puts a [metadata] table after the packages and checks it stays last.'),
    ...sec(r'the flow with a fake template'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 658-681', r'''
  it("downloads, personalises and moves the project into place", function()
    file_template()
    local parent = H.tmpdir()
    local err, info = create({ crate = "my_gui_app", author_name = "Jane Doe", author_email = "j@x.org", parent = parent })
    H.is_nil(err, err)
    local dir = parent .. "/my_gui_app"
    H.eq(dir, info.dir)
    H.eq({}, leftovers(parent))
    H.eq({ "my_gui_app" }, vim.tbl_map(vim.fs.basename, vim.fn.glob(parent .. "/*", true, true)))

    local toml = read(dir .. "/Cargo.toml")
    H.has(toml, 'name = "my_gui_app"')
    H.has(toml, 'authors = ["Jane Doe <j@x.org>"]')
    H.has(toml, 'license = "MIT OR Apache-2.0"')
    H.has(read(dir .. "/src/main.rs"), "my_gui_app::TemplateApp::new(cc)")
    H.has(read(dir .. "/src/main.rs"), '"my gui app"')
    H.has(read(dir .. "/src/app.rs"), 'ui.heading("my gui app")')
    H.has(read(dir .. "/src/app.rs"), "https://github.com/emilk/eframe_template/blob/main/")
    H.has(read(dir .. "/index.html"), "<title>my gui app</title>")
    local sw = read(dir .. "/assets/sw.js")
    H.has(sw, "'./my_gui_app.js'")
    H.has(sw, "'./my_gui_app_bg.wasm'")
    H.has(read(dir .. "/.github/workflows/pages.yml"), "as my_gui_app/favicon.ico")
    H.has(read(dir .. "/Cargo.lock"), 'name = "my_gui_app"')'''),
    ...para('--', r'The master case runs create() against the file:// fake and checks the result from every angle: the returned directory, no leftovers in the parent, exactly one entry in the parent, Cargo.toml with the name and the authors and the licence untouched, main.rs and app.rs with the crate and the title replaced but the link to the template kept, the index.html title, the service worker names, the workflow comment, and Cargo.lock with no mention of the template. The remaining assertions cover the README (regenerated, starts with the title), the removed scripts, licence files and a binary blob left byte for byte (the blob contains eframe_template and a NUL), the removed toolchain pin, rust-version preserved, and a git repository on main with no commit.'),
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
    ...para('--', r'The toolchain pin has three forms: the legacy one-line rust-toolchain file, the TOML form, and both together. The case runs all three and demands that none survives while rust-version stays byte for byte. It is a monument to the 0cfb739 reversal: the history of this feature is that the pin once was kept and prepared, and the test now defends the decision to drop it. The final assertion, that the generated README has no mention of “toolchain”, guards against the README text drifting back.'),
    ...sec(r'the rust version check'),
    ...code('lua', r'tests/egui-new_spec.lua · lines 1313-1326', r'''
  it("older rustc: one warning with both versions and the update command", function()
    local bin = H.tmpdir()
    stub_bin(bin, "rustc", "echo 'rustc 1.94.1 (abc 2026-01-01)'\n")
    with_path(bin)
    local state, cap = check(project())
    H.eq("old", state)
    -- other plugins may notify meanwhile (seen on macOS runners): count the rustc one
    local mine = vim.tbl_filter(function(n)
      return type(n.msg) == "string" and n.msg:find("this project needs Rust", 1, true) ~= nil
    end, cap.list)
    H.eq(1, #mine, vim.inspect(cap.list))
    H.eq(vim.log.levels.WARN, mine[1].level)
    H.has(mine[1].msg, "this project needs Rust >= 1.95 (you have 1.94.1): run rustup update stable")
  end)'''),
    ...para('--', r'check_rust_version runs rustc, so the tests put a stub rustc first on PATH. This case stubs a script printing rustc 1.94.1 and expects state old and exactly one warning with the exact text. A comment records something learned on a macOS runner: other plugins may notify meanwhile, so the test filters notifications to the one it owns rather than counting all. Sibling cases cover equal and newer rustc (silent), a project-local override (rustc is run inside the project), no rustc at all, a failing or garbage rustc, and no rust-version field (rustc is not even run).'),
    ...sec(r'the one test that needs the internet'),
    ...para('--', r'The group “the real template (network)” downloads emilk/eframe_template and personalises it as my_gui_app. It skips itself when github.com cannot be reached (skip("no network to github.com")). It is the check that the snapshot fixtures still resemble the world; nothing else in the file can tell you the template changed.'),
    ...sec(r'history'),
    ...pt('--', r'ddc51eb (2026-10-15, xynovim)', r'created with 1,244 lines.'),
    ...pt('--', r'b020526 / 0cfb739 (2026-10-15 and 16)', r'330 lines added for toolchain preparation, then 573 changed when it was removed.'),
    ...pt('--', r'ff1c8fa (2026-10-16)', r'one line added: the OS header.'),
    ...pt('--', r'1de2687 (2026-10-22, here)', r'moved in under the new namespace, 1,419 lines.'),
  ],
);
