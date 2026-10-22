import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/crate-add_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'crate-add_spec.lua — suggesting and adding the crate you forgot to depend on'),
    cm('--', r'the unknown-crate hint, the code action and :CrateAdd, tested without a network and once for real'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/crate_add.lua'),
    kv(r'language', r'Lua spec, 841 lines, 35 it() blocks, 10 describe() blocks'),
    kv(r'hermetic', r'path-only temp workspaces, stubbed pickers, stubbed crates.io client and stubbed cargo add; one test is the real thing'),
    kv(r'needs', r'nothing for most; network and cargo for the real flow (it skips without them)'),
    kv(r'history', r'5 commits, 2026-10-14 to 2026-10-21'),
    ...sec(r'why this file exists'),
    ...para('--', r'Writing use rand::Rng; in a crate that does not depend on rand produces an error from rust-analyzer that does not tell you what to do. crate_add closes the loop: it scans the buffer with treesitter, marks the unknown head with a hint, offers a code action Add crate rand through an in-process language server, and runs a flow that searches crates.io, lets you tick features, chooses a target manifest and runs cargo add. That is many moving parts, and the header of the spec states how they are kept testable: path-only temp workspaces because cargo metadata needs no registry for those, stubbed pickers, stubbed crates.io client and stubbed cargo add, and exactly one real run at the end.'),
    ...code('lua', r'tests/crate-add_spec.lua · lines 1-6', r'''
-- config.crate_add: the unknown-crate hint (treesitter scan, diagnostics, the
-- code action served by the in-process server) and :CrateAdd (search ->
-- features -> target -> cargo add argv).
-- Hermetic: path-only temp workspaces (cargo metadata needs no registry),
-- stubbed pickers, crates.io client and `cargo add`. One test runs the whole
-- flow for real (crates.io + cargo add itoa on a copy of the deps-lab fixture,'''),
    ...sec(r'the scanner: what is flagged'),
    ...para('--', r'The first test feeds a small Rust file with every shape an unknown crate can take and expects the exact list of flagged heads with line numbers: rand in a use path, serde_json inside a brace group, a type path chrono::Utc, an attribute macro tokio::main on one line and a call tokio::spawn on another. The compact form rand@1 is name at line. The localdep in the same use group is not flagged because it is a real dependency of the temp workspace. Further tests check wildcard and nested lists and that the reported range is exactly the head, not the whole path.'),
    ...code('lua', r'tests/crate-add_spec.lua · lines 93-111', r'''
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
  end)'''),
    ...sec(r'what is never flagged'),
    ...para('--', r'A false alarm in an editor is worse than a miss, so this test is long and each line carries a reason. std and core; dependencies; a rename (a dependency by its alias); a dev-dependency; the own crate name; use of a local alias; extern crate with an alias; modules, structs and enums; macro_rules bodies; a generic parameter named t; a primitive type path such as u32::MAX; and rand inside println! arguments, with the comment that macro arguments are tokens, not paths. The assertion is simply that the scan returns an empty list.'),
    ...code('lua', r'tests/crate-add_spec.lua · lines 131-167', r'''
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
    ...para('--', r'More cases follow. Files that glob-import from the own crate or from another file are quiet, because the name may come from there; but a glob from std, from an enum or from super inside an inline mod still flags. A glob from a dependency keeps quiet (the field test: use predicates::prelude::* brings predicate). Buffers above max_lines are skipped since the scan walks the whole tree, edition 2015 packages are skipped, as are non-Rust and dependency-source files and files outside every workspace member.'),
    ...sec(r'the command line is built, not typed'),
    ...para('--', r'build_argv produces the argument vector for cargo add for each target and flag, and the test of refusal is a security test. It tries the names a;b, a b, ../x, $(x), the empty string, a name with a newline, --git and -p, and expects no argv and an error for each; then a package with a space, a feature x;rm, a feature with a space and a kind evil. Since the argv is passed as a list, there is no shell involved, but a name that begins with a dash could still be an option, and the test covers that case.'),
    ...code('lua', r'tests/crate-add_spec.lua · lines 240-250', r'''
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
    ...sec(r'the flow with stubs'),
    ...para('--', r'With the pickers and the client stubbed, tests show what the user sees: name, version, downloads and description with features and their dependency lists; the right argv for each target; every member and kind offered, with those already in [workspace.dependencies] marked; no member prefix for a single-package workspace; the line cargo wrote reported and the view refreshed; a cargo error reported as a failure; offline behaviour (a clear message without a search answer, and --offline when the results came from the cache); defaults when the feature list cannot be fetched; and a message outside a cargo workspace.'),
    ...sec(r'the hint and the code action'),
    ...para('--', r'A larger test runs the editor part: the hint appears within 3 seconds, the code-action menu offers Add crate rand, and the hint clears after the add. Others check that nothing is offered away from the hint, that the second action opens the flow for that crate, that there is no hint for a dependency or after the crate is removed again, that vim.g.xynovim_crate_check = false switches the check off, and that :CrateAdd and leader r A are registered.'),
    ...sec(r'the real run'),
    ...para('--', r'The last test with the network does the whole flow on a copy of the deps-lab fixture. It skips when offline, or when cargo metadata cannot resolve the fixture crates from the local registry, and then stubs only the picker: it picks itoa from the crates.io list and the preselected features. It then waits up to 90 seconds for cargo add, requires success and itoa in the message and in Cargo.toml, and finally runs cargo check --quiet in the copy, which must return 0. The fixture’s role is described on the page for tests/fixtures/deps-lab/Cargo.toml.'),
    ...code('lua', r'tests/crate-add_spec.lua · lines 761-806', r'''
  it("adds itoa to a copy of deps-lab, which then builds", function()
    local ok, why = online()
    if not ok then
      return skip(why)
    end
    local dir = H.fixture("deps-lab")
    local meta, err = cm.metadata(dir)
    if not meta then
      return skip("the registry lacks the deps-lab crates offline: " .. tostring(err):sub(1, 100))
    end
    stub(cm.config, "cache_dir", H.tmpdir() .. "/crates")
    cm.invalidate()
    vim.cmd.edit(vim.fn.fnameescape(dir .. "/src/main.rs"))
    local chosen
    stub(ca.ui, "pick", function(spec, cb)
      if spec.title:find("^crates.io") then
        for _, it in ipairs(spec.items) do
          if it.crate.name == "itoa" then
            chosen = it
          end
        end
        return cb({ chosen or spec.items[1] })
      elseif spec.title:find("^Features") then
        local sel = {}
        for _, it in ipairs(spec.items) do
          if it.preselect then
            sel[#sel + 1] = it
          end
        end
        return cb(sel)
      end
      cb({ spec.items[1] })
    end)
    local done, okk, msg
    ca.add("itoa", function(a, b)
      done, okk, msg = true, a, b
    end)
    H.wait_for(function()
      return done
    end, 90000, "cargo add itoa")
    H.ok(okk, msg)
    H.ok(chosen, "itoa is among the search results")
    H.match(msg, "itoa", true)
    H.match(read(dir .. "/Cargo.toml"), "\nitoa = ", true)
    local b = vim.system({ "cargo", "check", "--quiet" }, { cwd = dir, text = true }):wait(110000)
    H.eq(0, b.code, b.stderr)'''),
    ...sec(r'follows auto-save and the bacon-ls restart'),
    ...para('--', r'Auto-save writes with noautocmd, so there is no BufWritePost to trigger a rescan; the test shows that the scan is rescheduled when auto-save wrote the buffer. A review-fix test shows that the bacon-ls client is restarted after cargo add like after a manifest save, even though no buffer was edited, and that a fresh cached answer is not labelled offline.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b9363cd (2026-10-14)', r'created with dependency freshness, missing-feature fix, attribute completion and the import engine.'),
    ...pt('--', r'19f974c, b474307 (2026-10-15)', r'review fixes and field test fixes of the same feature set.'),
    ...pt('--', r'9641d08 (2026-10-16), d3e1442 (2026-10-21)', r'Windows and macOS runs; the latter made member_of compare one path spelling.'),
  ],
);
