import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-new.nvim/tests/rust-new_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'tests/rust-new_spec.lua — testing a plugin that shells out to cargo'),
    cm('--', r'real cargo for the happy path, shell stubs for every way it can go wrong'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'tests', r'lua/xyno_new/rust.lua'),
    kv(r'size', r'1,003 lines, 51 cases in 10 groups'),
    kv(r'needs', r'cargo (real), git; sh stubs, so the header says xyno-os: linux,macos'),
    kv(r'shape', r'pure functions first, then real-cargo flows, failure paths, then the prompts'),
    kv(r'origin', r'tests/rust-new_spec.lua in xynovim, 1,074 lines at d163480 (2026-10-16)'),
    ...sec(r'the header is a contract'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 1-10', r'''
-- xyno-timeout: 300
-- xyno_new.rust (:RustNewBin, :RustNewLib, :RustNewWorkspace, :RustNewMember). Pure functions
-- first, then the flows with the REAL cargo in temp directories (cargo new works offline) and the
-- failure paths (stub cargo / empty PATH / read-only parent). The dashboard entries are in
-- dashboard_spec.lua.
-- xyno-os: linux,macos (sh cargo stubs)
local H = require("xyno_new_test.helpers")
local R = require("xyno_new.rust")
local E = require("xyno_new.egui")
require("xyno_new").setup()'''),
    ...para('--', r'The first lines state the structure and the constraints. “Pure functions first, then the flows with the REAL cargo in temp directories (cargo new works offline) and the failure paths (stub cargo / empty PATH / read-only parent).” The xyno-os header is read by tests/run.lua and makes the whole file a SKIP on Windows. The xyno-timeout header is not read by this plugin’s runner (see the run.lua page), though it was honoured in xynovim.'),
    ...sec(r'three small tools'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 13-20, 139-146', r'''

local restores = {}
local function stub(t, k, v)
  local orig = t[k]
  t[k] = v
  restores[#restores + 1] = function()
    t[k] = orig
  end
...
--- A directory holding a `cargo` stub (script body) first on PATH.
local function stub_cargo(body)
  local d = H.tmpdir()
  write(d .. "/cargo", "#!/bin/sh\n" .. body .. "\n")
  vim.uv.fs_chmod(d .. "/cargo", 493)
  vim.env.PATH = d .. ":" .. saved_path
  return d
end'''),
    ...para('--', r'stub(t, k, v) replaces a field and remembers how to put it back; after_each plays the restorers in reverse. That is how vim.ui.input and vim.ui.select are replaced by canned answers without ever leaking. stub_cargo writes an executable sh script called cargo into a temp directory and puts that directory first on PATH, so everything that runs “cargo” in the plugin runs the stub. The mode 493 is octal 755. need_cargo skips a test when the real cargo is missing.'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 75-89, 116-125', r'''
local function stub_input(answers)
  local log = {}
  stub(vim.ui, "input", function(opts, cb)
    log[#log + 1] = opts
    local a = table.remove(answers, 1)
    if a == nil then
      error("unexpected prompt: " .. tostring(opts.prompt))
    end
    if a == false then
      return cb(nil)
    end
    cb(a)
  end)
  return log
end
...
local function wait_cb(fn)
  local done
  fn(function(err, info)
    done = { err, info }
  end)
  H.wait_for(function()
    return done ~= nil
  end, 60000, "the run did not finish")
  return done[1], done[2]
end'''),
    ...para('--', r'stub_input answers vim.ui.input from a list: false means cancel (the callback gets nil), and running out of answers raises “unexpected prompt”, so a flow that asks one question more than expected fails loudly instead of hanging. wait_cb turns the callback API of the creators into a synchronous call: it records the (err, info) pair and waits up to 60 seconds with H.wait_for, which pumps the event loop so the coroutine runner can finish.'),
    ...sec(r'pure functions, with the real cargo as an oracle'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 264-282', r'''
  it("works on the text the installed cargo really writes", function()
    need_cargo()
    for _, kind in ipairs({ "--bin", "--lib" }) do
      local text = real_cargo_toml(kind)
      local out = R.inherit(text)
      H.has(out, "version.workspace = true")
      H.has(out, "edition.workspace = true")
      H.no_match(out, 'version = "', true)
      H.no_match(out, 'edition = "', true)
      -- every other line is untouched
      local keep = vim.tbl_filter(function(l)
        return not l:match("^version") and not l:match("^edition")
      end, vim.split(text, "\n", { plain = true }))
      local keep2 = vim.tbl_filter(function(l)
        return not l:match("^version") and not l:match("^edition")
      end, vim.split(out, "\n", { plain = true }))
      H.eq(keep, keep2)
    end
  end)'''),
    ...para('--', r'The inherit tests would be weak if they only checked a literal string the author typed. This one asks the installed cargo to create a binary and a library, passes the real Cargo.toml through M.inherit and asserts the result. If a future cargo changes the shape of its manifest, this case fails, which is the purpose. It sits next to a test of the literal form so the failure mode is clear.'),
    ...sec(r'the member list: examples as documentation'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 327-332, 334-343', r'''
  it("adds to a one-line list, keeping everything else", function()
    H.eq('[workspace]\nmembers = ["a", "crates/n"]\n', R.add_member_path('[workspace]\nmembers = ["a"]\n', "crates/n"))
    H.eq('[workspace]\nmembers = [ "a", "crates/n" ]\n', R.add_member_path('[workspace]\nmembers = [ "a" ]\n', "crates/n"))
    H.eq('[workspace]\nmembers = ["crates/n"]\n', R.add_member_path("[workspace]\nmembers = []\n", "crates/n"))
    H.eq('[workspace]\nmembers = ["a", "crates/n"]\n', R.add_member_path('[workspace]\nmembers = ["a",]\n', "crates/n"))
  end)
...
  it("adds a line to a multi-line list with its indent, comma and comments", function()
    local t = '[workspace]\nresolver = "2"\nmembers = [\n    "a",\n    "b" # last\n]\n\n[workspace.package]\nversion = "0.1.0"\n'
    H.eq(
      '[workspace]\nresolver = "2"\nmembers = [\n    "a",\n    "b", # last\n    "crates/n",\n]\n\n[workspace.package]\nversion = "0.1.0"\n',
      R.add_member_path(t, "crates/n")
    )
    local t2 = "[workspace]\nmembers = [\n\t'a',\n\t'b',\n]\n"
    H.eq("[workspace]\nmembers = [\n\t'a',\n\t'b',\n\t\"crates/n\",\n]\n", R.add_member_path(t2, "crates/n"))
    H.eq('[workspace]\nmembers = [\n  "crates/n",\n]\n', R.add_member_path("[workspace]\nmembers = [\n]\n", "crates/n"))
  end)'''),
    ...para('--', r'These two cases are the specification of add_member_path. Each H.eq pair is an input manifest and the expected output, byte for byte: bracket spacing is preserved, a trailing comma in a one-line list is handled, a comment after the last entry keeps its place and the comma lands before it, single quotes are respected and the new entry uses double quotes, an empty multi-line list gets an indented entry on its own line.'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 360-369, 371-384', r'''
  it("adds the comma after the LAST entry of a line holding several", function()
    H.eq(
      '[workspace]\nmembers = [\n  "a", "b",\n  "crates/x",\n]\n',
      R.add_member_path('[workspace]\nmembers = [\n  "a", "b"\n]\n', "crates/x")
    )
    H.eq(
      '[workspace]\nmembers = [\n  "b", "c", # "d"\n  "crates/x",\n]\n',
      R.add_member_path('[workspace]\nmembers = [\n  "b", "c" # "d"\n]\n', "crates/x")
    )
  end)
...
  it("keeps the comment of an empty list and the CRLF line endings", function()
    H.eq(
      '[workspace]\nmembers = [ # hi\n  "crates/x",\n]\n',
      R.add_member_path("[workspace]\nmembers = [ # hi\n]\n", "crates/x")
    )
    H.eq(
      '[workspace]\r\nmembers = [\r\n  "a",\r\n  "crates/x",\r\n]\r\n',
      R.add_member_path('[workspace]\r\nmembers = [\r\n  "a"\r\n]\r\n', "crates/x")
    )
    H.eq(
      '[workspace]\r\nmembers = [\r\n  "crates/x",\r\n]\r\n',
      R.add_member_path("[workspace]\r\nmembers = [\r\n]\r\n", "crates/x")
    )
  end)'''),
    ...para('--', r'The next two cases were written after a review found bugs (e166947). A line with two entries and a trailing comment containing a quote and a comma-less last entry; an empty list with a comment after the opening bracket; and three CRLF manifests. Each H.eq is a regression test with its input kept in the file.'),
    ...sec(r'workspace creation against real cargo'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 459-479', r'''
  it("builds the layout with a binary member and inherited version / edition", function()
    local parent = H.tmpdir()
    local err, info = ws(parent, "my-ws", "binary", "my-ws-app")
    H.is_nil(err)
    local root = parent .. "/my-ws"
    H.eq(root, info.dir)
    H.eq(root .. "/crates/my-ws-app/src/main.rs", info.file)
    local top = read(root .. "/Cargo.toml")
    local edition = R.parse_edition(real_cargo_toml("--bin"))
    H.eq(R.workspace_toml(edition), top)
    H.eq(R.resolver(edition), info.resolver)
    H.eq("/target\n", read(root .. "/.gitignore"))
    H.eq(
      '[package]\nname = "my-ws-app"\nversion.workspace = true\nedition.workspace = true\n\n[dependencies]\n',
      read(root .. "/crates/my-ws-app/Cargo.toml")
    )
    H.ok(vim.uv.fs_stat(root .. "/.git"), "git init")
    H.is_nil(vim.uv.fs_stat(root .. "/crates/my-ws-app/.git"), "no repository inside the member")
    H.eq("main", vim.trim(run({ "git", "symbolic-ref", "--short", "HEAD" }, root).stdout))
    H.eq("", vim.trim(run({ "git", "log", "--oneline" }, root).stdout), "no commit")
  end)'''),
    ...para('--', r'The most important end-to-end case. It creates a workspace in a temp directory and then reads everything back: the top manifest equals workspace_toml(edition) for the edition that a probe cargo new reports, the .gitignore is exactly /target, and the member manifest is exactly the text shown, with version.workspace and edition.workspace. A repository exists at the root and not in the member; HEAD is main; git log is empty, so there is no commit. The assertion that the root manifest equals the function output means the test and the code share the same expectation of what “correct” is, while the edition comes from outside.'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 517-543', r'''
  it("resolver follows the edition cargo reports (stub cargo for 2021 and 2018)", function()
    local real = vim.fn.exepath("cargo")
    for ed, resolver in pairs({ ["2021"] = "2", ["2018"] = "2" }) do
      R.reset_edition()
      vim.env.PATH = saved_path
      local d = H.tmpdir()
      write(
        d .. "/cargo",
        ([[#!/bin/sh
"%s" "$@" || exit $?
for a in "$@"; do last=$a; done
# rewrite the edition cargo wrote, as if this were an older cargo
f="$last/Cargo.toml"; [ -f "$f" ] || f="$PWD/$last/Cargo.toml"
sed -i.bak 's/^edition = .*/edition = "%s"/' "$f"; rm -f "$f.bak"
]]):format(real, ed)
      )
      vim.uv.fs_chmod(d .. "/cargo", 493)
      vim.env.PATH = d .. ":" .. saved_path
      local parent = H.tmpdir()
      local err, info = ws(parent, "old", "binary", "old-app")
      H.is_nil(err, ed)
      H.eq(ed, info.edition)
      H.eq(resolver, info.resolver)
      H.has(read(parent .. "/old/Cargo.toml"), 'resolver = "' .. resolver .. '"')
      H.has(read(parent .. "/old/Cargo.toml"), 'edition = "' .. ed .. '"')
    end
  end)'''),
    ...para('--', r'To test an edition cargo of 2021 or 2018 without installing old toolchains, the test writes a cargo shell wrapper: it runs the real cargo, takes the last argument as the created path, and rewrites the edition line with sed -i.bak to look like an older cargo (the -i.bak spelling is the one both GNU and BSD sed accept). The loop resets the edition cache for each value and checks that the resolver in the manifest becomes 2 for both. 2024 is covered by the real cargo case above and by the pure resolver test.'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 545-558', r'''
  it("asks cargo for the edition once per session", function()
    local calls = H.tmpdir() .. "/calls"
    local real = vim.fn.exepath("cargo")
    local d = H.tmpdir()
    write(d .. "/cargo", ('#!/bin/sh\necho x >> "%s"\nexec "%s" "$@"\n'):format(calls, real))
    vim.uv.fs_chmod(d .. "/cargo", 493)
    vim.env.PATH = d .. ":" .. saved_path
    local parent = H.tmpdir()
    H.is_nil((ws(parent, "one", "binary", "one-app")))
    H.is_nil((ws(parent, "two", "binary", "two-app")))
    -- per workspace: the cargo new of the member; the edition probe ran once in total
    local n = #vim.split(vim.trim(read(calls)), "\n", { plain = true })
    H.eq(3, n)
  end)'''),
    ...para('--', r'A logging stub appends a line to a file for every invocation and then execs the real cargo. Two workspaces are created; the log must have three lines: the edition probe once, plus one cargo new per member. This is a test about a performance decision, the cache, written as a test about observable behaviour.'),
    ...sec(r'failure paths: nothing left behind'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 684-703, 705-720', r'''
  it("cargo missing: a clear error and nothing created, parents included", function()
    local parent = H.tmpdir()
    local empty = H.tmpdir()
    vim.env.PATH = empty
    for _, f in ipairs({
      function(cb)
        R.create_project({ name = "a", parent = parent .. "/p/q", kind = "binary" }, cb)
      end,
      function(cb)
        R.create_workspace({ name = "a", parent = parent .. "/p/q", kind = "binary", member = "m" }, cb)
      end,
      function(cb)
        R.create_member({ root = parent, kind = "binary", name = "m" }, cb)
      end,
    }) do
      local err = wait_cb(f)
      H.eq("cargo not found", err)
    end
    H.eq({}, vim.fn.readdir(parent))
  end)
...
  it("cargo failing: its first stderr line, no directory left (project, workspace)", function()
    local parent = H.tmpdir()
    stub_cargo('echo "error: the stub says no" >&2\necho "second line" >&2\nexit 101')
    local err = wait_cb(function(cb)
      R.create_project({ name = "boom", parent = parent .. "/new/dir", kind = "binary" }, cb)
    end)
    H.eq("cargo new failed: error: the stub says no", err)
    H.eq({}, vim.fn.readdir(parent))
    -- the edition probe is the first cargo call of a workspace
    R.reset_edition()
    err = wait_cb(function(cb)
      R.create_workspace({ name = "boom", parent = parent .. "/new/dir", kind = "binary", member = "m" }, cb)
    end)
    H.match(err, "error: the stub says no", true)
    H.eq({}, vim.fn.readdir(parent))
  end)'''),
    ...para('--', r'Setting PATH to an empty temp directory simulates a machine without cargo. All three creators must fail with exactly the message cargo not found, and the parent must be empty afterwards: the nested p/q directories that would have been created are gone. The failing-cargo case stubs a script that prints an error line and a second line to stderr and exits 101, and demands the exact message cargo new failed: error: the stub says no, then again for the workspace flow (after reset_edition, since the probe is its first cargo call).'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 722-732', r'''
  it("a workspace whose member step fails leaves no directory behind", function()
    need_cargo()
    local real = vim.fn.exepath("cargo")
    local parent = H.tmpdir()
    stub_cargo(('case "$*" in *probe*) exec "%s" "$@";; esac\necho "error: member step failed" >&2\nexit 101'):format(real))
    local err = wait_cb(function(cb)
      R.create_workspace({ name = "half", parent = parent .. "/x/y", kind = "library", member = "half-core" }, cb)
    end)
    H.match(err, "error: member step failed", true)
    H.eq({}, vim.fn.readdir(parent))
  end)'''),
    ...para('--', r'The stub lets the edition probe through (case "$*" in *probe*) and fails the member creation. By then the root directory exists with its manifest and .gitignore, so this is the case that proves the recursive delete of the root and the removal of created parents. The read-only parent case chmods the directory to r-xr-xr-x and skips itself if running as root or if the directory stays writable on that file system.'),
    ...sec(r'the prompts: driving vim.ui'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 792-805', r'''
  it("binary: name, parent (default vim.g.xyno_new_projects_dir), cargo new, cd, main.rs, next steps", function()
    local parent, cap = setup_flow()
    local log = stub_input({ "hello-bin", parent })
    vim.cmd("RustNewBin")
    H.eq(2, #log)
    H.match(log[1].prompt, "name")
    H.eq(parent, log[2].default)
    wait_msg(cap, "created ")
    local dir = parent .. "/hello-bin"
    H.eq(vim.uv.fs_realpath(dir), vim.uv.fs_realpath(vim.uv.cwd()))
    H.eq(vim.uv.fs_realpath(dir .. "/src/main.rs"), vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)))
    H.has(find_msg(cap, "created ").msg, "cargo run")
    H.ok(vim.uv.fs_stat(dir .. "/.git"))
  end)'''),
    ...para('--', r'The flow tests call the real commands, with stubbed prompts, and wait for notifications. This one checks the number of prompts (2), that the first one mentions the name, that the second one is prefilled with vim.g.xyno_new_projects_dir, and then looks at the final state: the directory, the open buffer, the cwd and the “next steps” text. Neovim’s own working directory changing is part of the product, so it is asserted.'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 936-990', r'''
  it(":RustNewMember: finds the workspace from the current buffer, asks kind and name, refuses elsewhere", function()
    local parent, cap = setup_flow()
    stub_input({ "mw", parent, "mw-app" })
    stub_select({ "binary" })
    vim.cmd("RustNewWorkspace")
    wait_msg(cap, "created ")
    local root = parent .. "/mw"
    local log = stub_input({ "mw-core" })
    local sel = stub_select({ "library" })
    vim.cmd("RustNewMember")
    H.wait_for(function()
      return vim.uv.fs_stat(root .. "/crates/mw-core/src/lib.rs")
    end, 60000, "member created")
    H.eq(1, #sel)
    H.eq(1, #log)
    H.wait_for(function()
      return find_msg(cap, "added crates/mw-core")
    end, 10000, "notification")
    H.eq(vim.uv.fs_realpath(root .. "/crates/mw-core/src/lib.rs"), vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)))

    -- a name that exists is re-prompted
    stub_input({ "mw-app", "mw_core", "another" })
    stub_select({ "binary" })
    local before = #cap.list
    vim.cmd("RustNewMember")
    H.wait_for(function()
      return vim.uv.fs_stat(root .. "/crates/another/Cargo.toml")
    end, 60000, "third member")
    local warned = 0
    for i = before + 1, #cap.list do
      if tostring(cap.list[i].msg):find("exists already", 1, true) then
        warned = warned + 1
      end
    end
    H.eq(2, warned)

    -- outside a workspace: refused, no prompt
    H.wait_for(function()
      return not R.running()
    end, 60000, "the third member to be finished")
    local lone = H.tmpdir()
    run({ "cargo", "new", "--vcs", "none", "lone" }, lone)
    vim.cmd("silent! %bwipeout!")
    vim.cmd("edit " .. vim.fn.fnameescape(lone .. "/lone/src/main.rs"))
    local log2 = stub_input({})
    cap = H.capture_notify()
    vim.cmd("RustNewMember")
    vim.wait(100)
    H.eq(0, #log2)
    H.ok(find_msg(cap, "not a workspace with a members list", vim.log.levels.ERROR), vim.inspect(cap.list))
    H.eq({ "src" }, vim.tbl_filter(function(n)
      return n == "src"
    end, vim.fn.readdir(lone .. "/lone")))
    H.is_nil(vim.uv.fs_stat(lone .. "/lone/crates"))
  end)'''),
    ...para('--', r'The longest flow case builds a workspace through the command, then exercises :RustNewMember three ways: a good name, a name that collides (typed mw-app, then mw_core, which clash through hyphen/underscore equivalence, then another which succeeds), and a lone cargo project where the command must refuse with “not a workspace with a members list” without prompting at all. It counts the exists already warnings, expects exactly two, and asserts that the lone project gained no crates directory.'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 992-1002', r'''
  it("a second command while one runs is refused", function()
    local parent, cap = setup_flow()
    stub_input({ "first", parent, "second", parent })
    vim.cmd("RustNewBin")
    -- the run of the first one is in flight (async)
    vim.cmd("RustNewBin")
    H.ok(find_msg(cap, "being created already", vim.log.levels.WARN) or find_msg(cap, "created "), vim.inspect(cap.list))
    H.wait_for(function()
      return find_msg(cap, "created ")
    end, 60000, "first created")
  end)'''),
    ...para('--', r'The last case starts a binary, issues the command again while the first run is still in flight, and expects the warning “being created already” (or, if the first finished quickly, the “created” notification). The accepted alternative is an honest admission that the race cannot be forced: the test is deterministic about the guard but tolerant about timing.'),
    ...sec(r'cleanup after every case'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 53-71', r'''
after_each(function()
  -- a run still in flight (a test that stopped early) must not leak into the next one
  pcall(H.wait_for, function()
    return not R.running()
  end, 60000, "the run to finish")
  for i = #restores, 1, -1 do
    pcall(restores[i])
  end
  restores = {}
  vim.env.PATH = saved_path
  vim.g.xyno_new_projects_dir = saved_g.dir
  -- opening a generated main.rs starts the Rust language servers
  pcall(function()
    for _, c in ipairs(vim.lsp.get_clients()) do
      c:stop(true)
    end
  end)
  pcall(vim.cmd, "silent! %bwipeout!")
  pcall(vim.cmd, "cd " .. vim.fn.fnameescape(vim.env.HOME or "/"))'''),
    ...para('--', r'The after_each is worth reading. It first waits for any run still in flight (up to 60 seconds), so a test that stopped early cannot bleed into the next one; restores the stubs, PATH and the variable; stops every LSP client (opening a generated main.rs starts Rust language servers, as the comment says); wipes buffers; and returns to the home directory so the temp directory can be deleted.'),
    ...sec(r'history'),
    ...pt('--', r'd163480 (2026-10-16, xynovim)', r'created with 1,074 lines alongside rust_new.lua.'),
    ...pt('--', r'e166947 (2026-10-16, xynovim)', r'39 lines added for the review fixes.'),
    ...pt('--', r'01f8e4c / 1de2687 (2026-10-22, here)', r'moved under the xyno_new namespace as 1,003 lines.'),
  ],
);
