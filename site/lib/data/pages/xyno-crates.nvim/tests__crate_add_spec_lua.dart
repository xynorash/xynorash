import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-crates.nvim/tests/crate-add_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'crate-add_spec.lua — 35 tests for a feature whose worst bug is a false alarm'),
    cm('--', r'hermetic workspaces, scripted pickers, a faked cargo, and two tests against the real thing'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/xyno_crates/crate_add.lua'),
    kv(r'language', r'Lua on tests/harness.lua'),
    kv(r'size', r'854 lines, 35 tests in 10 groups'),
    kv(r'hermetic', r'path-only temp workspaces, stubbed pickers, stubbed crates.io client, stubbed cargo add'),
    kv(r'live', r'one test with crates.io + cargo add itoa + cargo check; one with rust-analyzer; one with a real snacks picker'),
    kv(r'history', r'xynovim tests/crate-add_spec.lua (b9363cd, 2026-10-14), 841 lines there; 65 changed lines at the extraction'),
    ...sec(r'why this file exists'),
    ...para('--', r'The module has two halves with opposite risks. The scan must never say "rand is not a dependency" when it could be wrong, and the flow must never hand cargo anything a shell or a path could misread. A good spec for the first half is a list of cases, a good spec for the second is a hostile list of strings. This file is both. It comes from xynovim, where it was added with the module in b9363cd and extended by the review and field-test commits; the extraction changed the module names and the command ids.'),
    blank,
    ...code('lua', r'tests/crate-add_spec.lua · lines 1-9', r'''
-- xyno_crates.crate_add: the unknown-crate hint (treesitter scan, diagnostics, the
-- code action served by the in-process server) and :CrateAdd (search ->
-- features -> target -> cargo add argv).
-- Hermetic: path-only temp workspaces (cargo metadata needs no registry),
-- stubbed pickers, crates.io client and `cargo add`. One test runs the whole
-- flow for real (crates.io + cargo add itoa on a copy of the deps-lab fixture,
-- then cargo check) and skips without network or cargo.
local H = require("xyno_crates_test.helpers")
local cm = require("xyno_rust.crate_meta")'''),
    ...sec(r'scaffolding that every test shares'),
    ...code('lua', r'tests/crate-add_spec.lua · lines 13-35', r'''
local function start()
  ca.setup({ keymap = "<leader>rA" })
end

local restores = {}
local function stub(t, k, v)
  local orig = t[k]
  t[k] = v
  restores[#restores + 1] = function()
    t[k] = orig
  end
  return orig
end

after_each(function()
  for i = #restores, 1, -1 do
    pcall(restores[i])
  end
  restores = {}
  cm.invalidate()
  pcall(vim.cmd, "silent! %bwipeout!")
  vim.diagnostic.reset(ca.ns)
end)'''),
    ...para('--', r'stub(t, k, v) swaps a field and records how to put it back; after_each undoes in reverse order and also clears the metadata cache (cm.invalidate), wipes buffers and resets the plugin’s diagnostic namespace. That is how the 35 tests share one process without leaking. The helpers that build workspaces write real files into temp directories created by H.tmpdir():'),
    blank,
    ...code('lua', r'tests/crate-add_spec.lua · lines 58-94', r'''
--- app (bin + lib "app") with a path dependency, a renamed one and a
--- dev-dependency; plus those crates as members.
local function make_ws()
  local root = H.tmpdir() .. "/ws"
  write(root .. "/Cargo.toml", '[workspace]\nmembers = ["app", "localdep", "devdep", "other"]\nresolver = "2"\n')
  for _, n in ipairs({ "localdep", "devdep", "other" }) do
    pkg(root, n)
    write(("%s/%s/src/lib.rs"):format(root, n), "pub fn f() {}\n")
  end
  pkg(
    root,
    "app",
    '\n[dependencies]\nlocaldep = { path = "../localdep" }\nren = { package = "other", path = "../other" }\n\n[dev-dependencies]\ndevdep = { path = "../devdep" }\n'
  )
  write(root .. "/app/src/lib.rs", "pub fn thing() {}\n")
  write(root .. "/app/src/main.rs", "fn main() {}\n")
  write(root .. "/app/src/inner.rs", "pub fn f() {}\n")
  return root
end

--- Write `text` to app/src/main.rs, load it into a buffer and scan it.
--- Returns the list of "name@line" strings (1-based line).
local function scan(root, text, rel)
  H.need_parser("rust")
  local file = root .. "/app/" .. (rel or "src/main.rs")
  write(file, text)
  local meta, err = cm.metadata(root)
  H.ok(meta, err)
  vim.cmd.edit(vim.fn.fnameescape(file))
  local hits = ca.scan(vim.api.nvim_get_current_buf(), meta)
  if not hits then
    return nil
  end
  return vim.tbl_map(function(h)
    return ("%s@%d"):format(h.name, h.lnum + 1)
  end, hits)
end'''),
    ...para('--', r'make_ws() builds a workspace of four path crates, with an application that has a plain path dependency, a renamed one (ren = { package = "other", ... }) and a dev-dependency. Path dependencies need no registry, which is why cargo metadata runs for real and offline in every CI environment. scan() writes text to src/main.rs, loads it into a buffer, runs the module’s scan against real metadata, and returns "name@line" strings, so a test is a table of expected hits. H.need_parser("rust") skips the test, with a reason, if the grammar is missing.'),
    blank,
    ...sec(r'the scan: a table of what is flagged and what is never flagged'),
    ...code('lua', r'tests/crate-add_spec.lua · lines 99-123', r'''
  it("flags unknown heads of use paths, expression paths, types and attributes", function()
    local root = make_ws()
    H.eq(
      { "rand@1", "serde_json@2", "chrono@4", "tokio@5", "tokio@7" },
      scan(
        root,
        table.concat({
          "use rand::Rng;",
          "use {serde_json::Value, localdep::f};",
          "fn main() {",
          "    let d: chrono::Utc = x;",
          "    #[tokio::main]",
          "    fn a() {}",
          "    let m = tokio::spawn(1);",
          "}",
        }, "\n")
      )
    )
  end)

  it("flags the head of a nested use list and of a wildcard use", function()
    local root = make_ws()
    H.eq({ "alpha@1", "beta@2" }, scan(root, "use alpha::{a, b::c};\nuse beta::x;\nfn main() {}\n"))
    H.eq({}, scan(root, "use alpha::{b::*};\nfn main() { rand::random::<u8>(); }\n"), "a glob of an unknown crate may bring any name")
  end)'''),
    ...para('--', r'The flagged cases cover every syntactic position the module claims: a use path, a use list with a head inside braces, a type path, an attribute (#[tokio::main]) and an expression path. The second test pins a subtle rule: alpha::{a, b::c} flags alpha, and a glob of an unknown crate ("use alpha::{b::*}") suppresses everything in the file, including rand::random in the same file, because the glob may bring any name. A test also asserts the exact range, lnum 0, col 20, end_col 24, so the diagnostic underlines the head and nothing else.'),
    blank,
    ...code('lua', r'tests/crate-add_spec.lua · lines 137-173', r'''
  it("keeps quiet about std, dependencies, renames, dev-dependencies, own crate, modules, imports, generics", function()
    local root = make_ws()
    local text = table.concat({
      "use std::io;",
      "use core::fmt;",
      "use localdep::f;",
      "use ren::f as g;", -- a rename is a dependency by its alias
      "use devdep::f as h;", -- a dev-dependency
      "use app::thing;", -- own lib name
      "use io as myio;",
      "extern crate alpha as beta;",
      "mod inner;",
      "struct S;",
      "enum Color { Red }",
      "macro_rules! m { () => { $crate::foo::bar(); other::x(); } }",
      "fn g<t>() {",
      "    t::default();",
      "    io::stdin();",
      "    inner::f();",
      "    let _ = Color::Red;",
      "    beta::x();",
      "    myio::stdout();",
      "    core::mem::drop(1);",
      "    let _ = u32::MAX;",
      "    let _ = S::new();",
      "    println!(\"{}\", rand::random::<u8>());", -- macro arguments are tokens, not paths
      "}",
      "#[rustfmt::skip]",
      "#[cfg(test)]",
      "mod tests {",
      "    use super::*;",
      "    use devdep::f;",
      "    fn t() { devdep::f(); }",
      "}",
    }, "\n")
    H.eq({}, scan(root, text))
  end)'''),
    ...para('--', r'This is the longest single test and the most valuable. It is the comment list of M.scan turned into one source file that must produce zero hits: std and core, a path dependency, a renamed dependency by its alias, a dev-dependency, the application’s own library name, a name bound with use ... as, an extern crate alias, a declared module, local types and enums, a macro_rules body, a lowercase generic parameter, a primitive, an attribute from rustfmt, macro arguments in println!, and an inline mod tests with use super::*. Adding a case here is how a field-test bug becomes permanent: the line "use ren::f as g; -- a rename is a dependency by its alias" is a regression test in one line.'),
    blank,
    ...code('lua', r'tests/crate-add_spec.lua · lines 175-199', r'''
  it("keeps quiet in files that glob-import from the own crate or another file", function()
    local root = make_ws()
    H.eq({}, scan(root, "use crate::prelude::*;\nfn main() { rand::random::<u8>(); }\n"))
    H.eq({}, scan(root, "use super::*;\nfn t() { rand::random::<u8>(); }\n"), "super:: at file level reaches another file")
  end)

  it("keeps flagging when the glob is std, an enum or super inside an inline mod", function()
    local root = make_ws()
    H.eq({ "rand@3" }, scan(root, "use std::collections::*;\nuse Color::*;\nfn main() { rand::random::<u8>(); }\n"))
    H.eq({ "rand@3" }, scan(root, "mod t {\n    use super::*;\n    fn f() { rand::random::<u8>(); }\n}\n"))
  end)

  it("keeps quiet when the glob is a dependency (field test: use predicates::prelude::* brings `predicate`)", function()
    local root = make_ws()
    H.eq({}, scan(root, "use localdep::prelude::*;\nfn main() { predicate::eq(1); rand::random::<u8>(); }\n"))
  end)

  it("skips buffers above max_lines (the scan walks the whole tree)", function()
    local root = make_ws()
    local old = ca.config.max_lines
    stub(ca.config, "max_lines", 2)
    H.eq(nil, scan(root, "fn a() {}\nfn b() {}\nfn main() { rand::random::<u8>(); }\n"))
    ca.config.max_lines = old
    H.eq({ "rand@3" }, scan(root, "fn a() {}\nfn b() {}\nfn main() { rand::random::<u8>(); }\n"))
  end)'''),
    ...para('--', r'The glob group is the clearest record of the module’s decisions. use crate::prelude::* and use super::* at file level silence the file. use std::collections::*, use Color::* and use super::* inside an inline mod do not, and the expected hit rand@3 proves the scan is still alive. The dependency glob test carries the story in its name: "field test: use predicates::prelude::* brings predicate". The line-cap test lowers max_lines to 2 and shows nil, then restores it and shows the hit.'),
    blank,
    ...sec(r'build_argv: a hostile list'),
    ...code('lua', r'tests/crate-add_spec.lua · lines 246-256', r'''
  it("refuses names, packages, features and kinds a shell or a path could misread", function()
    for _, bad in ipairs({ "a;b", "a b", "../x", "$(x)", "", "a\nb", "--git", "-p" }) do
      local argv, err = ca.build_argv({ name = bad })
      H.is_nil(argv, bad)
      H.ok(err)
    end
    H.is_nil(ca.build_argv({ name = "ok", package = "a b" }))
    H.is_nil(ca.build_argv({ name = "ok", features = { "x;rm" } }))
    H.is_nil(ca.build_argv({ name = "ok", features = { "a b" } }))
    H.is_nil(ca.build_argv({ name = "ok", kind = "evil" }))
  end)'''),
    ...para('--', r'The refusal test feeds names no crate has (a;b, a b, ../x, $(x), the empty string, a newline) and two flag lookalikes, --git and -p. Each must give nil and an error. Then a package with a space, features with a semicolon or a space, and an unknown kind. The shell-injection cases cost nothing, since argv lists are never parsed by a shell, but the flag cases are the real danger: a name that reaches cargo add as --git would change its meaning.'),
    blank,
    ...sec(r'the flow: scripted pickers and a fake cargo'),
    ...para('--', r'script_ui (lines 305-333) replaces M.ui.pick with a function that answers by title: the search picker gets its first item, the features picker gets the names named in the plan (default only if none), the target picker gets the first item matching a member and kind. It also records every spec it saw, so a test can inspect what the user would have seen. fake_cargo records the argv and cwd, can edit the manifest as cargo would, and passes everything else through to the real exec. fake_registry stubs search and info, with options for errors and for the cache flags.'),
    blank,
    ...code('lua', r'tests/crate-add_spec.lua · lines 384-395', r'''
    local cases = {
      { { member = "app", kind = "normal" }, { "cargo", "add", "itoa", "-p", "app" } },
      { { member = "app", kind = "dev", features = { "default", "alloc" } }, { "cargo", "add", "itoa", "-p", "app", "--dev", "-F", "alloc" } },
      { { member = "lib2", kind = "build", features = { "std", "alloc" } }, { "cargo", "add", "itoa", "-p", "lib2", "--build", "--no-default-features", "-F", "std,alloc" } },
      { { member = "lib2", kind = "normal", features = { "no-panic" } }, { "cargo", "add", "itoa", "-p", "lib2", "--no-default-features", "-F", "no-panic" } },
    }
    for i, c in ipairs(cases) do
      script_ui(c[1])
      H.ok(run_add("itoa"), "case " .. i)
      H.eq(c[2], calls[i].argv, "case " .. i)
      H.eq(root, calls[i].cwd, "cargo runs in the workspace root")
    end'''),
    ...para('--', r'Four rows of the table map a picker plan to the exact argv: default into [dependencies] gives -p app; dev with alloc gives --dev -F alloc; build with std and alloc, default unticked, gives --build --no-default-features -F std,alloc; and a feature that is not default gives --no-default-features. Each also asserts that cargo runs in the workspace root. The neighbouring tests check six target items for two members and three kinds, the "[workspace.dependencies]" marking, the missing member prefix in a single-package workspace, the reported line, cargo’s error text and ERROR level, the offline wording, and the defaults fallback when the feature list cannot be fetched.'),
    blank,
    ...sec(r'the hint through the real language-client stack'),
    ...code('lua', r'tests/crate-add_spec.lua · lines 553-575', r'''
  it("shows the hint within 3 s, offers 'Add crate rand' through the code-action menu, and clears it after the add", function()
    H.known_issue({ "windows" }, "live rust-analyzer flow fails or hangs on Windows (windows-latest run 39647013043; cause not diagnosed)")
    have_rust()
    local root = make_ws2()
    local calls = fake_cargo(function()
      write(root .. "/app2/Cargo.toml", read(root .. "/app2/Cargo.toml") .. 'rand = { path = "../rand" }\n')
      return { code = 0, stdout = "", stderr = "" }
    end)
    start()
    local t0 = vim.uv.now()
    vim.cmd.edit(vim.fn.fnameescape(root .. "/app2/src/main.rs"))
    local buf = vim.api.nvim_get_current_buf()
    local function hints()
      return vim.diagnostic.get(buf, { namespace = ca.ns })
    end
    H.wait_for(function()
      return #hints() > 0
    end, 3000, "the unknown-crate hint")
    H.ok(vim.uv.now() - t0 < 3000)
    local d = hints()[1]
    H.eq("crate 'rand' is not a dependency", d.message)
    H.eq(vim.diagnostic.severity.HINT, d.severity)
    H.eq("xyno-crates", d.source)'''),
    ...para('--', r'This test starts the plugin, opens a file whose crate is not a dependency, and waits at most 3 seconds for the HINT. It then asserts the message "crate ’rand’ is not a dependency", the severity, the source xyno-crates and the line. The assertions were chosen to match the user’s experience: the code action must reach vim.lsp.buf.code_action, the same API a user’s key calls.'),
    blank,
    ...code('lua', r'tests/crate-add_spec.lua · lines 597-610', r'''
    -- apply it: cargo add rand runs for the package of the file, the hint goes away
    vim.lsp.buf.code_action({
      filter = function(a)
        return a.title == "Add crate rand"
      end,
      apply = true,
    })
    H.wait_for(function()
      return #calls > 0
    end, 5000, "cargo add")
    H.eq({ "cargo", "add", "rand", "-p", "app2" }, calls[1].argv)
    H.wait_for(function()
      return #hints() == 0
    end, 8000, "the hint to disappear")'''),
    ...para('--', r'The second half applies the action by title with apply = true, waits for fake cargo to record [cargo add rand -p app2], and then waits up to 8 seconds for the hint to disappear. The first line of the test is H.known_issue({ "windows" }, ...), which skips on Windows with the reason "live rust-analyzer flow fails or hangs on Windows (windows-latest run 39647013043; cause not diagnosed)". The suite reports what it does not know instead of hiding it.'),
    blank,
    ...sec(r'the real picker, auto-save, and the real flow'),
    ...code('lua', r'tests/crate-add_spec.lua · lines 713-740', r'''
  it("preselects `default`, Tab toggles, Enter returns exactly the ticked items (possibly none)", function()
    local dir = vim.env.XYNO_SNACKS_DIR
    if not dir or dir == "" or vim.fn.isdirectory(dir) ~= 1 then
      return skip("XYNO_SNACKS_DIR (a snacks.nvim checkout) is not set")
    end
    vim.opt.rtp:append(dir)
    require("snacks").setup({ picker = { enabled = true } })
    local Snacks = _G.Snacks
    local items = ca.feature_items({ features = { default = { "std" }, std = {}, alloc = { "dep:h" } } })
    local got
    ca.ui.pick({ title = "Features of x", items = items, multi = true }, function(sel)
      got = sel
    end)
    local p = H.wait_for(function()
      return Snacks.picker.get()[1]
    end, 5000, "the picker")
    H.wait_for(function()
      return #p:selected() == 1
    end, 3000, "default preselected")
    H.eq("default", p:selected()[1].feature)
    H.feed("<Tab>")
    H.eq(0, #p:selected())
    H.feed("<CR>")
    H.wait_for(function()
      return got
    end, 3000, "the callback")
    H.eq({}, got, "nothing ticked is an answer, not the highlighted item")
  end)'''),
    ...para('--', r'The snacks test is skipped unless XYNO_SNACKS_DIR points at a checkout, which CI provides with a pinned commit. It proves what a stub cannot: default is preselected, Tab unticks it, and Enter returns {} (an empty list, "nothing ticked is an answer, not the highlighted item"). That is the --no-default-features path, and it only works because the confirm function in crate_add.ui.pick reads p:selected() instead of the current item. The test also calls require("snacks").setup(...) and then uses _G.Snacks, a point that matters when reading crate_features.lua’s picker.'),
    blank,
    ...para('--', r'The auto-save test sends the User event AutoSaveWritePost with a buffer and checks that M.schedule receives it. The network test is skipped without curl, cargo or a route to index.crates.io, uses the deps-lab fixture, runs the whole :CrateAdd function with a scripted picker for the real crates.io search, asserts that the manifest has an itoa line, and ends with cargo check --quiet whose exit code must be zero.'),
    blank,
    ...para('--', r'The last group (lines 823-854) is the pair of review fixes. A fresh cached search must not be labelled "cached, offline?" in the picker title; a stale one must. The test asserts the title in both cases but never looks at the offline flag passed to cargo, so the inconsistency noted in the crate_add page is outside what the spec covers. The second test checks that a successful add calls rust_restart.manifest_saved once with a path that ends in Cargo.toml.'),
    blank,
    ...sec(r'history'),
    ...pt('--', r'b9363cd, 2026-10-14', r'the spec arrives with the module in xynovim.'),
    ...pt('--', r'19f974c, b474307', r'review and field-test fixes add the cache-label test, the max_lines, dependency-glob and on_exit tests.'),
    ...pt('--', r'9641d08 and d3e1442', r'Windows/macOS rounds: member_of path spelling and the OS-aware skips (H.known_issue).'),
    ...pt('--', r'9d33ca7, 2026-10-22', r'copied into this repository with the new module names.'),
  ],
);
