import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-crates.nvim/tests/crate-features_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'crate-features_spec.lua — a fake crate with every trap, and exact strings for every edit'),
    cm('--', r'42 tests; the manifest editor is tested by before/after text'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/xyno_crates/crate_features.lua'),
    kv(r'language', r'Lua on tests/harness.lua'),
    kv(r'size', r'865 lines, 42 tests in 11 groups'),
    kv(r'hermetic', r'a synthetic registry crate, text fixtures, a faked cm.exec'),
    kv(r'live', r'serde, clap, tokio from the deps-lab fixtures (skip with a reason when absent offline), and cargo check'),
    kv(r'history', r'xynovim tests/crate-features_spec.lua (b9363cd, 2026-10-14); 24 changed lines at the extraction'),
    ...sec(r'why this file exists'),
    ...para('--', r'The module is a parser, a boolean algebra and a text editor. Each has a different kind of correct. The parser is correct when it ignores decoys, the algebra when it picks the cheapest list, the editor when it changes only what it must. The header describes the split: "Hermetic where it can be: synthetic crates in temp dirs for the scanner, text fixtures for the manifest editor, a faked cm.exec for the argv checks. The tests on real crates ... skip with the reason otherwise; one test runs a real cargo check on the fixture."'),
    blank,
    ...code('lua', r'tests/crate-features_spec.lua · lines 1-9', r'''
-- xyno_crates.crate_features: the missing-feature fix (name -> feature from the
-- crate's own source, the code action in the normal menu, Cargo.toml edits)
-- and the :CrateFeatures explorer.
-- Hermetic where it can be: synthetic crates in temp dirs for the scanner, text
-- fixtures for the manifest editor, a faked cm.exec for the argv checks. The
-- tests on real crates (serde, clap, tokio from the deps-lab fixtures) need the
-- registry to hold them offline (cargo metadata --offline) and skip with the
-- reason otherwise; one test runs a real `cargo check` on the fixture.
local H = require("xyno_crates_test.helpers")'''),
    ...sec(r'the fake crate: every trap in one place'),
    ...code('lua', r'tests/crate-features_spec.lua · lines 47-71', r'''
--- A fake registry crate: a derive-style re-export behind an optional
--- dependency, a tokio-like cfg wrapper macro, a gated module, a glob
--- re-export, a macro_export macro and a commented-out decoy.
local function make_crate()
  local dir = H.tmpdir() .. "/fake-1.0.0"
  write(
    dir .. "/Cargo.toml",
    [[
[package]
name = "fake"
version = "1.0.0"

[features]
default = ["std"]
std = []
derive = ["fake_derive"]
rt = []
rt-multi-thread = ["rt"]
macros = ["fake_macros"]
full = ["derive", "rt-multi-thread", "macros"]

[dependencies]
fake_derive = { version = "1", optional = true }
fake_macros = { version = "1", optional = true }
]]'''),
    ...para('--', r'make_crate() writes a registry-shaped directory, fake-1.0.0, with a [features] table that has all the shapes the resolver must understand: a default that lists std, derive and macros that enable optional dependencies by name, rt and a rt-multi-thread that implies it, and full, which implies three others. The two optional dependencies, fake_derive and fake_macros, give rise to the implicit features that real crates have.'),
    blank,
    ...code('lua', r'tests/crate-features_spec.lua · lines 83-115', r'''
#[cfg(feature = "fake_derive")]
#[doc(inline)]
pub use fake_derive::{Serialize, Deserialize as De};

/* #[cfg(feature = "decoy")] pub struct Decoy2; */

cfg_macros! {
    pub use fake_macros::main;
    cfg_rt! {
        #[cfg(feature = "rt-multi-thread")]
        pub use fake_macros::spawn_mt;
        pub use fake_macros::spawn;
    }
}

#[cfg(feature = "rt")]
pub mod runtime;

mod private_impl;
pub use self::private_impl::*;

#[cfg(any(feature = "derive", feature = "macros"))]
pub fn either() {}

#[cfg(all(feature = "derive", feature = "macros"))]
pub fn both() {}

#[cfg(test)]
pub fn only_in_tests() {}

#[macro_export]
#[cfg(feature = "macros")]
macro_rules! shout { () => {}; }'''),
    ...para('--', r'The source of the crate is a gallery of the things the scanner must not get wrong. A decoy in a doc comment, a commented-out item, a renamed re-export, a tokio-style cfg_macros! block nested around cfg_rt!, a gated module file, a private module re-exported by a glob, any() and all() gates, a cfg(test) item, a #[macro_export] macro behind a feature, a struct with a bound containing Item = u8, and a const initialised with a struct literal. Four more files hold the module bodies and the wrapper macro definitions.'),
    blank,
    ...code('lua', r'tests/crate-features_spec.lua · lines 200-229', r'''
  it("finds the gate of re-exports, wrapper macros, modules, globs and macro_export", function()
    local dir = make_crate()
    local idx = cf.scan(dir)
    H.ok(idx.files >= 5, "read lib.rs, macros/mod.rs, macros/cfg.rs, runtime.rs, private_impl.rs: " .. idx.files)
    local function gate(n)
      local g, why = cf.gate_of(idx, n)
      return g and gate_keys(g) or why
    end
    H.eq({ "fake_derive" }, gate("Serialize"))
    H.eq({ "fake_derive" }, gate("De"), "renamed re-export")
    H.eq("not found", gate("Deserialize"), "the original name was renamed away")
    H.eq({ "macros" }, gate("main"), "cfg_macros! wrapper")
    H.eq({ "macros+rt" }, gate("spawn"), "nested cfg_macros! { cfg_rt! { .. } }")
    H.eq({ "macros+rt+rt-multi-thread" }, gate("spawn_mt"))
    H.eq({ "rt" }, gate("Runtime"), "item of a gated module file")
    H.eq({ "macros+rt" }, gate("MacroRuntime"), "gate of the module AND of the item")
    H.eq({ "derive" }, gate("Exported"), "pub item of a private module re-exported by a glob")
    H.eq({ "derive", "macros" }, gate("either"))
    H.eq({ "derive+macros" }, gate("both"))
    H.eq({ "macros" }, gate("shout"), "#[macro_export] macro_rules")
    H.eq("ungated", gate("Always"))
    H.eq("ungated", gate("always_fn"))
    H.eq("not found", gate("only_in_tests"), "cfg(test) items are not API")
    H.eq("not found", gate("Decoy"), "a commented-out item is no item")
    H.eq("not found", gate("Decoy2"))
    H.eq("not found", gate("NoSuchThing"))
    H.eq({ "std" }, gate("WithStd"))
    H.eq("ungated", gate("Plain"), "`Item = u8` in a where/bound does not swallow the next items")
    H.eq("ungated", gate("AfterConst"), "a const initialised with a struct literal ends at its `;`")
  end)'''),
    ...para('--', r'The scan test asserts the gate of 21 names, each with a message explaining the point. The renamed re-export De is gated by fake_derive and its original name is "not found". Nested wrappers combine: spawn needs macros+rt, spawn_mt macros+rt+rt-multi-thread. Items of a gated module file are gated by the module (Runtime needs rt) and by themselves (MacroRuntime needs macros+rt). Plain items are "ungated", and it matters: for them the module stays silent. Two assertions are regression tests for scanner bugs: Plain with Item = u8 "does not swallow the next items", and AfterConst "ends at its ;".'),
    blank,
    ...sec(r'resolution and wording'),
    ...para('--', r'The resolution group checks that the implicit feature fake_derive maps to the user-facing derive, that a plain gate feature is kept and anything another one implies is dropped, that nothing is returned when the gate already holds, that the cheapest alternative of an any() wins, and that the enabled set is computed from declared features and the default set. The wording group feeds the real texts of rustc, rust-analyzer and bacon-ls to names_from_message, and checks that messages without a name, or with a name that is no identifier, produce nothing.'),
    blank,
    ...sec(r'the manifest editor: exact text in, exact text out'),
    ...code('lua', r'tests/crate-features_spec.lua · lines 327-343', r'''
  it("turns a version string into an inline table", function()
    local out = edit('[dependencies]\nserde = "1" # keep\nrand = "0.8"\n', "serde", "add", { "derive" })
    H.eq('[dependencies]\nserde = { version = "1", features = ["derive"] } # keep\nrand = "0.8"\n', out)
  end)

  it("appends to an existing features array and to an inline table without one", function()
    H.eq('[dependencies]\ntokio = { version = "1", features = ["rt", "macros"] }\n', (edit('[dependencies]\ntokio = { version = "1", features = ["rt"] }\n', "tokio", "add", { "macros" })))
    H.eq('[dependencies]\nx = { version = "1", default-features = false, features = ["a"] }\n', (edit('[dependencies]\nx = { version = "1", default-features = false }\n', "x", "add", { "a" })))
    H.eq('[dependencies]\nx = { features = ["a"] }\n', (edit("[dependencies]\nx = { }\n", "x", "add", { "a" })))
    H.eq('[dependencies]\nserde = { workspace = true, features = ["derive"] } # c\n', (edit("[dependencies]\nserde = { workspace = true } # c\n", "serde", "add", { "derive" })))
  end)

  it("keeps a multi-line array's layout, comments and trailing comma", function()
    local src = '[dependencies]\ntokio = { version = "1", features = [\n    "rt", # runtime\n    "net",\n] }\n'
    local out = edit(src, "tokio", "add", { "macros" })
    H.eq('[dependencies]\ntokio = { version = "1", features = [\n    "rt", # runtime\n    "net",\n    "macros",\n] }\n', out)
  end)'''),
    ...para('--', r'Every edit test compares complete strings. A version string becomes an inline table and the trailing comment "# keep" survives. An inline table without features gains the key, a table with an array extends it, an empty inline table is filled, workspace = true gets features after it. A multi-line array keeps its indentation, its comment, and its trailing comma. These are the tests that make the claim "formatting and comments kept" falsifiable.'),
    blank,
    ...code('lua', r'tests/crate-features_spec.lua · lines 373-383', r'''
  it("reports what it cannot do instead of guessing", function()
    local out, why = edit('[dependencies]\nx = "1"\n', "y", "add", { "f" })
    H.is_nil(out)
    H.match(why, "not declared", false)
    out, why = edit('[dependencies]\nx = { version = "1", features = ["a"] }\n', "x", "add", { "a" })
    H.is_nil(out)
    H.match(why, "already", false)
    out, why = edit('[dependencies]\nx = "1"\n', "x", "remove", { "a" })
    H.is_nil(out)
    H.match(why, "not declared", false)
  end)'''),
    ...para('--', r'The last test of the group is about honesty. When the dependency is not in this manifest the reason contains "not declared"; when the feature is already there, "already"; when asked to remove a feature of a plain version string, "not declared". The function returns nil and a reason, and the spec forbids guessing. The same group covers dev and target tables, quoted keys, a renamed key (helpers = { package = "util", ...}), and removal down to an empty array.'),
    blank,
    ...sec(r'set_features: the argv and its fallbacks'),
    ...code('lua', r'tests/crate-features_spec.lua · lines 412-427', r'''
  it("runs cargo add with an argv list, offline first, for a registry dependency", function()
    local dir = H.tmpdir()
    write(dir .. "/Cargo.toml", '[package]\nname = "app"\nversion = "0.1.0"\n\n[dependencies]\nserde = "1"\n')
    local calls = {}
    stub(cm, "exec", function(argv, opts, cb)
      calls[#calls + 1] = argv
      -- act like cargo add
      write(dir .. "/Cargo.toml", '[package]\nname = "app"\nversion = "0.1.0"\n\n[dependencies]\nserde = { version = "1", features = ["derive"] }\n')
      cb({ code = 0, stdout = "", stderr = "" })
    end)
    local ok, how = run(fake_dep(dir), { "derive" }, true)
    H.eq(true, ok)
    H.eq("cargo add", how)
    H.eq(1, #calls)
    H.eq({ "cargo", "add", "serde", "--features", "derive", "--manifest-path", dir .. "/Cargo.toml", "--offline" }, calls[1])
  end)'''),
    ...para('--', r'The fake exec acts as cargo would: it records the argv and rewrites the manifest. The expected call is the whole contract, cargo add serde --features derive --manifest-path <dir>/Cargo.toml --offline, executed once, with how == "cargo add". The group continues with --dev, --build and --target and the fall back from the offline run to the online one; the fall back to text when cargo is missing or changes nothing; renamed and path dependencies, which must never call cargo; and refusals for names that are not plain identifiers or manifests with unsaved changes.'),
    blank,
    ...sec(r'real crates, and an acceptance test with cargo check'),
    ...code('lua', r'tests/crate-features_spec.lua · lines 636-662', r'''
    local s = cf.suggest(meta, main, lines, { { message = "cannot find derive macro `Serialize` in this scope", lnum = lnum, col = 0 } })
    H.eq(1, #s, vim.inspect(s))
    H.eq({ "serde", { "derive" } }, { s[1].crate, s[1].features })
    -- the code action in the normal menu: a buffer of the file with the
    -- in-process client, a diagnostic as bacon-ls reports it
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, main)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].buftype = ""
    cf.attach(buf)
    local clients = vim.lsp.get_clients({ bufnr = buf, name = cf.client_name })
    H.eq(1, #clients, "the in-process client attached")
    local ns = vim.api.nvim_create_namespace("cf-spec")
    vim.diagnostic.set(ns, buf, { { lnum = lnum, col = 0, end_lnum = lnum, end_col = 5, severity = 1, message = "cannot find derive macro `Serialize` in this scope", source = "bacon-ls" } })
    stub(ca, "client_name", cf.client_name)
    local list = ca.request_wait(buf, { start = { lnum, 0 }, ["end"] = { lnum, 1 } }, {})
    local hits = ca.filter(list, { title = "Enable feature `derive` of `serde`", plain = true })
    H.eq(1, #hits, vim.inspect(vim.tbl_map(function(a)
      return a.title
    end, list)))
    H.eq("quickfix", hits[1].kind)
    local before = read(dir .. "/Cargo.toml")
    local ok, aerr = ca.apply(hits[1], { timeout = 60000 })
    H.eq(true, ok, tostring(aerr))
    local after = read(dir .. "/Cargo.toml")
    H.ok(after ~= before)
    H.match(after, 'serde = { version = "1", features = ["derive"] }', true)'''),
    ...para('--', r'This acceptance test uses the deps-lab-nofeature fixture. It finds the line of #[derive(Debug, Serialize, Deserialize)], feeds the real rustc wording, expects exactly one suggestion for serde with derive, attaches the in-process client to a buffer of the file, plants a diagnostic in the way bacon-ls reports it, requests code actions through xyno_rust.code_actions, filters for the exact title, and applies it. Then it asserts that the file now contains serde = { version = "1", features = ["derive"] } and the same for clap. The final step (lines 665-667) runs cargo check --offline --quiet on the edited copy and requires exit code 0: the claim is not "the text looks right" but "the project builds".'),
    blank,
    ...code('lua', r'tests/crate-features_spec.lua · lines 670-694', r'''
  it("an uneditable-by-cargo manifest still gets the feature through the text edit (workspace = true)", function()
    H.need_rust()
    local root = H.tmpdir() .. "/ws"
    write(root .. "/Cargo.toml", '[workspace]\nmembers = ["m"]\nresolver = "2"\n\n[workspace.dependencies]\nserde = "1" # keep me\n')
    write(root .. "/m/Cargo.toml", '[package]\nname = "m"\nversion = "0.1.0"\nedition = "2021"\n\n[dependencies]\nserde = { workspace = true } # c\n')
    write(root .. "/m/src/main.rs", "fn main() {}\n")
    local meta, err = cm.metadata(root)
    if not meta then
      return skip("registry lacks serde offline: " .. tostring(err):sub(1, 120))
    end
    stub(cm, "exec", function(_, _, cb)
      cb({ code = -1, stdout = "", stderr = "no cargo" })
    end)
    local d = cm.dependencies(meta, { name = "serde" })[1]
    local done, ok, how
    cf.set_features(d, { "derive" }, true, function(a, b)
      done, ok, how = true, a, b
    end)
    H.wait_for(function()
      return done
    end, 5000)
    H.eq(true, ok, tostring(how))
    H.eq('[package]\nname = "m"\nversion = "0.1.0"\nedition = "2021"\n\n[dependencies]\nserde = { workspace = true, features = ["derive"] } # c\n', read(root .. "/m/Cargo.toml"))
    H.eq('[workspace]\nmembers = ["m"]\nresolver = "2"\n\n[workspace.dependencies]\nserde = "1" # keep me\n', read(root .. "/Cargo.toml"), "the workspace table is not touched")
  end)'''),
    ...para('--', r'A second acceptance test handles a workspace dependency with cargo disabled (exec stubbed to fail): the member manifest becomes serde = { workspace = true, features = ["derive"] } # c with the comment intact, and the workspace root is asserted byte-for-byte unchanged.'),
    blank,
    ...sec(r'review fixes and lifecycle'),
    ...code('lua', r'tests/crate-features_spec.lua · lines 805-819', r'''
  it("a comment with brackets inside the features array does not end it early", function()
    local out = cf.edit_manifest(
      '[dependencies]\nserde = { version = "1", features = [ # see [docs]\n "derive" ] }\n',
      { key = "serde", kind = "normal" }, "add", { "std" }
    )
    H.eq('[dependencies]\nserde = { version = "1", features = [ # see [docs]\n "derive",\n "std" ] }\n', out)
  end)

  it("single-quoted features are items and are kept", function()
    local out = cf.edit_manifest(
      "[dependencies]\nserde = { version = \"1\", features = ['derive','alloc'] }\n",
      { key = "serde", kind = "normal" }, "add", { "std" }
    )
    H.eq("[dependencies]\nserde = { version = \"1\", features = ['derive','alloc', \"std\"] }\n", out)
  end)'''),
    ...para('--', r'These tests are the review fixes of 19f974c and b474307. The first has brackets in a comment inside the array: [ # see [docs]; the editor must not end the array at the bracket in the comment. The second has single-quoted features; they are items, and are kept. Both were fixed by the rewrite of array_edit in 19f974c. The symlink test follows: a Cargo.toml that is a symlink must still be a symlink (fs_lstat type "link") after the edit, with the target changed. And the lifecycle test stops the in-process client and waits until get_client_by_id returns nil, the b474307 fix.'),
    blank,
    ...sec(r'history'),
    ...pt('--', r'b9363cd, 2026-10-14', r'added with the module in xynovim (row 1.3 of the plan notes that the diagnostic in the spec is hand-made and the real rustc wording was checked in the assessment).'),
    ...pt('--', r'19f974c, b474307', r'array_edit, symlink, bacon-ls restart and lifecycle tests.'),
    ...pt('--', r'9d33ca7, 2026-10-22', r'copied here; the diff is mostly requires and names.'),
  ],
);
