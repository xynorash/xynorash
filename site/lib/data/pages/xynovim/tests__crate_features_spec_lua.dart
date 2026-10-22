import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/crate-features_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'crate-features_spec.lua — turning "cannot find derive macro" into a one-line Cargo.toml edit'),
    cm('--', r'scanning a crate source for the gate of an item, editing the manifest as text, and proving cargo check passes after'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/crate_features.lua: the missing-feature fix and the :CrateFeatures explorer'),
    kv(r'language', r'Lua spec, 869 lines, 42 it() blocks, 11 describe() blocks'),
    kv(r'hermetic', r'synthetic crates for the scanner, text fixtures for the manifest editor, a faked cm.exec for the argv checks'),
    kv(r'real crates', r'serde, clap and tokio from the deps-lab fixtures; they need the cargo registry offline and skip with the reason otherwise'),
    kv(r'history', r'4 commits, 2026-10-14 to 2026-10-16'),
    ...sec(r'why this file exists'),
    ...para('--', r'A very common Rust error is use of a derive or a function that exists in the crate but only behind a cargo feature: cannot find derive macro Serialize. The fix is a features entry in Cargo.toml, but a user has to know which feature gates the item. crate_features finds out by reading the crate own source: it scans lib.rs and its modules for cfg gates, and maps the name in the diagnostic to the feature (or the cheapest set of features) that enables it. Then it offers the fix as a normal code action and edits the manifest, with cargo add when it can and as text when it cannot. The header names the three parts: the name-to-feature scanner, the code action in the normal menu, and the Cargo.toml edits, plus the :CrateFeatures explorer.'),
    ...code('lua', r'tests/crate-features_spec.lua · lines 1-9', r'''
-- config.crate_features: the missing-feature fix (name -> feature from the
-- crate's own source, the code action in the normal menu, Cargo.toml edits)
-- and the :CrateFeatures explorer.
-- Hermetic where it can be: synthetic crates in temp dirs for the scanner, text
-- fixtures for the manifest editor, a faked cm.exec for the argv checks. The
-- tests on real crates (serde, clap, tokio from the deps-lab fixtures) need the
-- registry to hold them offline (cargo metadata --offline) and skip with the
-- reason otherwise; one test runs a real `cargo check` on the fixture.
local H = require("xynotest.helpers")'''),
    ...sec(r'reading gates in source'),
    ...para('--', r'The scanner test builds a synthetic crate (make_crate) that imitates the awkward shapes of real ones and asks for the gate of 21 names. It checks that renamed re-exports are found under the new name only, that wrapper macros like cfg_macros! are understood, including nested ones that combine to macros+rt+rt-multi-thread, that an item in a gated module file inherits the gate of the module and its own gate, that pub items of a private module re-exported by a glob are found, that any() gives alternatives while all() gives a combined gate, that #[macro_export] macros count, and that items under cfg(test), commented out items and unknown names are not found. The last two lines guard the scanner against swallowing neighbours: an Item = u8 bound must not hide the next items, and a const with a struct literal ends at its semicolon.'),
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
    ...sec(r'editing TOML without a parser'),
    ...para('--', r'Cargo.toml is edited as text, to keep comments and layout. The edit tests state what is preserved. Adding a feature to a multi-line array keeps the layout, the comments and the trailing comma. Version strings become inline tables, a features array is appended to or created, table and dotted-key forms are handled, the dependency table for the kind and target is chosen, renamed keys and quoted keys work, features can be removed, and cases the editor cannot handle are reported rather than guessed. Review fixes add a comment with brackets inside the features array that must not end it, single-quoted features, and writing through a symlinked Cargo.toml onto the real file.'),
    ...code('lua', r'tests/crate-features_spec.lua · lines 339-343', r'''
  it("keeps a multi-line array's layout, comments and trailing comma", function()
    local src = '[dependencies]\ntokio = { version = "1", features = [\n    "rt", # runtime\n    "net",\n] }\n'
    local out = edit(src, "tokio", "add", { "macros" })
    H.eq('[dependencies]\ntokio = { version = "1", features = [\n    "rt", # runtime\n    "net",\n    "macros",\n] }\n', out)
  end)'''),
    ...sec(r'cargo add when possible, text when not'),
    ...para('--', r'set_features runs cargo add with an argv list, offline first for a registry dependency, adds --dev, --build and --target where needed and falls back to the online run; falls back to the text edit when cargo add is missing or changes nothing; edits renamed and path dependencies as text and never calls cargo for them; switching off is a text edit; and it refuses names that are not plain identifiers and manifests with unsaved changes. The fact that unsaved changes refuse is the safety rule: the tool never overwrites work you have in a buffer.'),
    ...sec(r'the acceptance test on a real crate'),
    ...para('--', r'The acceptance block uses deps-lab-nofeature, a copy of deps-lab whose manifest lacks the derive features. The test finds the line with the derive attribute, asks suggest for a fix from the diagnostic text, and requires exactly one suggestion, crate serde with feature derive. It then wires a real buffer to the in-process language server, sets a diagnostic as bacon-ls would report it, requests code actions for the range, filters the one titled Enable feature derive of serde, checks that its kind is quickfix, applies it, and compares the manifest: serde now has features derive, and clap is unchanged. It ends with cargo check on the edited copy. The point of the whole feature is that the action fixes the build, so the test ends at the build.'),
    ...code('lua', r'tests/crate-features_spec.lua · lines 620-663', r'''
  it("the derive diagnostic yields the action, applying it makes cargo check succeed", function()
    H.need_rust()
    local dir = H.fixture("deps-lab-nofeature")
    local meta, err = cm.metadata(dir)
    if not meta then
      return skip("registry lacks the fixture's crates offline: " .. tostring(err):sub(1, 120))
    end
    local main = dir .. "/src/main.rs"
    local lines = vim.fn.readfile(main)
    local lnum
    for i, l in ipairs(lines) do
      if l:find("#[derive(Debug, Serialize, Deserialize)]", 1, true) then
        lnum = i - 1
      end
    end
    H.ok(lnum, "fixture still derives Serialize")
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
    H.match(after, 'serde = { version = "1", features = ["derive"] }', true)
    H.match(after, 'clap = { version = "4", features = ["derive"] }', true)'''),
    ...sec(r'a manifest cargo cannot edit'),
    ...para('--', r'When a dependency is inherited, serde = { workspace = true }, cargo add is not the right tool. The test builds a workspace in a temp dir with comments in both manifests, fakes cm.exec to return code -1 no cargo, and requires the member manifest to become serde = { workspace = true, features = ["derive"] } # c, with its trailing comment, and the workspace manifest to stay byte for byte identical ("the workspace table is not ..." in the assertion message).'),
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
    ...sec(r'the explorer and its keys'),
    ...para('--', r':CrateFeatures lists a dependency features (declared against available, what derive unlocks, an unused hint), toggles one with an edit of Cargo.toml, says so for a crate that is not a dependency, and registers its key free of other mappings. One test checks that a declared feature whose items the workspace never mentions is flagged as unused (the test name ends in a question mark). A last block checks that a stopped in-process client leaves vim.lsp.get_clients, with on_exit reported, so the in-process server does not look alive after it stopped.'),
    ...sec(r'skipping with a reason'),
    ...para('--', r'Anything that needs real crates calls cm.metadata first. If cargo metadata --offline fails because the registry does not hold the crate, the test calls skip with registry lacks the fixture crates offline and the first 120 characters of the error. The suite therefore stays green on a clean machine and says exactly what was not run.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b9363cd (2026-10-14)', r'created with the macros and dependencies work.'),
    ...pt('--', r'19f974c, b474307 (2026-10-15)', r'review fixes and field test fixes.'),
    ...pt('--', r'9641d08 (2026-10-16)', r'drive letter in canonical roots for the Windows runs.'),
  ],
);
