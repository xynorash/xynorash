import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-macros.nvim/tests/attrs_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'attrs_spec.lua — a table of cursors and what the menu must and must not contain'),
    cm('--', r'40 tests, about 70 of them table rows; cargo metadata stubbed, files in temp dirs'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'the spec of the attribute and derive completion'),
    kv(r'language', r'Lua on the repo harness; needs xyno-rust.nvim and xyno-imports.nvim'),
    kv(r'size', r'1,402 lines, 40 it() blocks (the table of cases is registered by a loop)'),
    kv(r'fixtures', r'tests/fixtures/deps-lab, a small cargo workspace copied per test'),
    kv(r'history', r'added in 08b2e8f (2026-10-22, Add specs, a headless runner and a lazy.nvim smoke test)'),
    ...sec(r'why this file exists'),
    ...para('--', r'A completion source has two ways to be wrong: it can offer something invalid, and it can '
        r'fail to offer something valid. Both are visible only as behaviour at a cursor. The spec '
        r'is therefore built around a single question asked many times: given this source text, '
        r'with the cursor at the bar, which labels does the menu contain? The header says how '
        r'hermetic the answer is.'),
    ...code('lua', r'tests/attrs_spec.lua · lines 1-7', r'''
-- xyno_macros.attrs: completion inside helper-attribute arguments and #[derive(...)]
-- (lua/xyno_macros/attrs.lua, data/macro_attrs/*.json).
-- Hermetic: workspaces are temp copies of the deps-lab fixture, cargo metadata is
-- stubbed out (dependencies come from the Cargo.toml scan) except in the one test that
-- asks for the real thing. Derive discovery reads the registry sources of serde_derive,
-- clap_derive and thiserror-impl and skips without them. Only the derive `use` test
-- needs rust-analyzer.
'''),
    ...sec(r'the harness around it'),
    ...code('lua', r'tests/attrs_spec.lua · lines 14-21', r'''
local function stub(t, k, v)
  local orig = t[k]
  t[k] = v
  restores[#restores + 1] = function()
    t[k] = orig
  end
end

'''),
    ...para('--', r'stub replaces a field of a module and registers the way back; after_each plays the '
        r'restorations in reverse. A before_each hook stubs cargo metadata to answer with an error, '
        r'so every test uses the manifest scan unless it explicitly asks for the real thing. The '
        r'result is a suite that does not need the network and, for most cases, does not need cargo.'),
    ...code('lua', r'tests/attrs_spec.lua · lines 90-114', r'''
local function at(src, dir)
  dir = dir or lab()
  local lines = vim.split(src, "\n", { plain = true })
  local row, col
  for i, l in ipairs(lines) do
    local c = l:find("|", 1, true)
    if c then
      row, col = i, c - 1
      lines[i] = l:gsub("|", "", 1)
      break
    end
  end
  assert(row, "no | in the case")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, dir .. "/src/lib.rs")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local items, info = ma.items(buf, row, col)
  vim.api.nvim_buf_delete(buf, { force = true })
  local labels, by = {}, {}
  for _, it in ipairs(items) do
    labels[#labels + 1] = it.label
    by[it.label] = it
  end
  return labels, items, info, by
end
'''),
    ...para('--', r'at(src, dir) is the core helper: it finds the bar in the source, removes it, creates a '
        r'scratch buffer named src/lib.rs under a workspace directory (the deps-lab copy by '
        r'default, or a wider one with more dependencies written in the Cargo.toml), calls items at '
        r'that position and returns the labels, the items, the info table and an index by label. '
        r'Because the buffer is real, the same code path as in the editor runs: windowing, lexing, '
        r'repair, tree-sitter, dependency resolution.'),
    ...code('lua', r'tests/attrs_spec.lua · lines 116-140', r'''
local function has_all(labels, want, ctx)
  for _, w in ipairs(want or {}) do
    if not vim.tbl_contains(labels, w) then
      error(("%s: %q missing from %s"):format(ctx, w, table.concat(labels, " ")), 0)
    end
  end
end

local function has_none(labels, unwanted, ctx)
  for _, w in ipairs(unwanted or {}) do
    if vim.tbl_contains(labels, w) then
      error(("%s: %q must not be offered (got %s)"):format(ctx, w, table.concat(labels, " ")), 0)
    end
  end
end

local function unique(labels, ctx)
  local seen = {}
  for _, l in ipairs(labels) do
    if seen[l] then
      error(("%s: %q offered twice"):format(ctx, l), 0)
    end
    seen[l] = true
  end
end
'''),
    ...para('--', r'Three assertion helpers have the failure messages written for a person reading a CI log: '
        r'has_all names the missing label and lists what was offered; has_none names the label that '
        r'must not be there; unique catches a label that appears twice.'),
    ...sec(r'the table'),
    ...code('lua', r'tests/attrs_spec.lua · lines 144-181', r'''
local SERDE_CASES = { "lowercase", "UPPERCASE", "PascalCase", "camelCase", "snake_case", "SCREAMING_SNAKE_CASE", "kebab-case", "SCREAMING-KEBAB-CASE" }

-- { name, src, has, lacks, dir = "wide", exact = n, registry = true }
local cases = {
  -- serde
  {
    "serde container struct",
    "use serde::Serialize;\n#[derive(Serialize)]\n#[serde(|)]\nstruct A { x: u32 }",
    { "rename", "rename_all", "deny_unknown_fields", "default", "bound", "transparent", "from", "try_from", "into", "remote", "tag", "crate" },
    { "skip", "flatten", "alias", "skip_serializing_if", "content", "untagged", "getter" },
  },
  {
    "serde container enum",
    "#[derive(Deserialize)]\n#[serde(|)]\nenum E { A }",
    { "tag", "content", "untagged", "rename_all", "rename_all_fields", "deny_unknown_fields" },
    { "transparent", "flatten", "skip" },
  },
  {
    "serde field",
    "#[derive(Serialize, Deserialize)]\nstruct A {\n    #[serde(|)]\n    x: u32,\n}",
    { "rename", "alias", "default", "skip", "skip_serializing", "skip_deserializing", "skip_serializing_if", "flatten", "with", "serialize_with", "deserialize_with", "bound", "getter", "borrow" },
    { "deny_unknown_fields", "tag", "transparent", "rename_all", "from", "remote" },
  },
  {
    "serde field, unfinished attribute at the end of the struct",
    "#[derive(Serialize)]\nstruct A {\n    x: u32,\n    #[serde(|\n}",
    { "rename", "flatten", "skip" },
    { "rename_all", "deny_unknown_fields" },
  },
  {
    "serde field, key prefix typed",
    "#[derive(Serialize)]\nstruct A {\n    #[serde(ren|\n    x: u32,\n}",
    { "rename" },
    { "rename_all", "deny_unknown_fields" },
  },
  {
    "serde variant",
    "#[derive(Serialize)]\nenum E {\n    #[serde(|)]\n    A,\n}",
'''),
    ...para('--', r'Each row is a name, a source text with a bar, the labels that must appear and the labels '
        r'that must not, with optional fields: an exact count, a different workspace, or a registry '
        r'requirement. The serde rows show the point of the whole data model. A container struct '
        r'gets rename_all and deny_unknown_fields but not flatten, skip or alias. A container enum '
        r'gets tag, content and untagged. A field gets skip, flatten and with, and not '
        r'deny_unknown_fields. An unfinished attribute at the end of a struct still completes. A '
        r'prefix filters. A tuple-struct field and a struct-variant field are recognised. These '
        r'rows are the executable form of the applies_to lists in serde.json.'),
    ...code('lua', r'tests/attrs_spec.lua · lines 590-619', r'''
    {},
    {},
    exact = 0,
  },
  {
    "a crate that is not a dependency (serde_json's derive-less lab has no sqlx)",
    "#[derive(sqlx::FromRow)]\nstruct R {\n    #[sqlx(|)]\n    a: u32,\n}",
    {},
    { "rename", "json" },
    exact = 0,
  },
}

describe("attribute argument and derive completion (table)", function()
  for _, c in ipairs(cases) do
    local name, src, has, lacks = c[1], c[2], c[3], c[4]
    it(name, function()
      if c.registry and not registry_ok then
        skip("serde_derive / clap_derive / thiserror-impl are not in the local cargo registry")
      end
      local labels = at(src, c.dir == "wide" and wide() or nil)
      unique(labels, name)
      has_all(labels, has, name)
      has_none(labels, lacks, name)
      if c.exact then
        H.eq(c.exact, #labels, name .. ": number of items, got " .. table.concat(labels, " "))
      end
    end)
  end
end)
'''),
    ...para('--', r'Two rows at the end show the negative cases that matter: a key already written is not '
        r'offered again, with an exact count of zero, and a crate that is not a dependency yields '
        r'nothing, with the case name saying why. The loop registers one test per row, skips those '
        r'that need the local cargo registry when serde_derive, clap_derive and thiserror-impl '
        r'sources are missing, asserts uniqueness, presence and absence, and compares the exact '
        r'count when the row has one.'),
    ...sec(r'version and schema behaviour'),
    ...code('lua', r'tests/attrs_spec.lua · lines 768-796', r'''
describe("version requirements", function()
  local s = ma.satisfies
  it("understands ranges, carets, tildes and partial versions", function()
    H.eq(true, s("1.0.229", ">=1.0.0, <2.0.0"))
    H.eq(false, s("2.0.0", ">=1.0.0, <2.0.0"))
    H.eq(false, s("0.9.9", ">=1.0.0"))
    H.eq(true, s("1.4.2", "^1"))
    H.eq(false, s("2.0.0", "^1"))
    H.eq(true, s("0.3.5", "^0.3"))
    H.eq(false, s("0.4.0", "^0.3"))
    H.eq(true, s("1.2.9", "~1.2"))
    H.eq(false, s("1.3.0", "~1.2"))
    H.eq(true, s("1.2.3", "=1.2"))
    H.eq(false, s("1.3.0", "=1.2"))
    H.eq(true, s("0.27.2", ">0.26.0, <=0.27.2"))
    H.eq(true, s("9.9.9", "*"))
  end)
  it("never hides data because of what it cannot read", function()
    H.eq(true, s(nil, ">=1.0.0"))
    H.eq(true, s("1.0.0", nil))
    H.eq(true, s("not-a-version", ">=1.0.0"))
    H.eq(true, s("1.0.0", ">=banana"))
  end)

  it("keys newer than the resolved version are hidden, the file's range is honoured", function()
    local real = ma.dependencies
    stub(ma, "dependencies", function(path, root)
      local d = real(path, root)
      d.by_name.serde.version = "1.0.100"
'''),
    ...para('--', r'The version table is a compact specification: caret on a major, on a zero minor; tilde; a '
        r'partial equals; a range with open and closed ends; a star. The second test is the policy '
        r'in four lines: nil version, nil range, a string that is not a version and a requirement '
        r'that is not parseable all give true. Never hide because of what cannot be read.'),
    ...code('lua', r'tests/attrs_spec.lua · lines 901-923', r'''
describe("project schemas (.xyno-macros/attrs)", function()
  local function ws(extra_toml)
    local dir = H.tmpdir() .. "/proj"
    write(
      dir .. "/Cargo.toml",
      '[package]\nname = "proj"\nversion = "0.1.0"\nedition = "2024"\n\n[dependencies]\nserde = "1"\n' .. (extra_toml or "")
    )
    write(dir .. "/src/main.rs", "fn main() {}\n")
    return dir
  end

  it("an attribute of the project file replaces the shipped one of the same name, the rest stays", function()
    local dir = ws()
    write(
      dir .. "/.xyno-macros/attrs/serde.json",
      vim.json.encode({
        crate = "serde",
        attributes = { { name = "serde", derives = { "Serialize" }, applies_to = { "container" }, args = { { key = "my_key", kind = "flag", doc = "mine" } } } },
      })
    )
    local labels = at("#[derive(Serialize)]\n#[serde(|)]\nstruct A;", dir)
    H.eq({ "my_key" }, labels)
    -- another workspace is not affected
'''),
    ...para('--', r'The project override tests build a workspace on the fly. The first writes a serde.json '
        r'under .xyno-macros/attrs with one invented key and asserts that the menu is exactly that '
        r'one key, and, in the same test, that another workspace is not affected. This is the '
        r'replace-by-name rule seen from the user’s side.'),
    ...sec(r'learning from usage'),
    ...code('lua', r'tests/attrs_spec.lua · lines 998-1030', r'''
describe("learn from usage (attributes without a schema)", function()
  --- A workspace using `fancy` (a path proc-macro dependency declaring #[fancy(...)])
  --- and writing the attribute in its own code and in the dependency's examples.
  local function fancy_ws()
    local base = H.tmpdir()
    write(base .. "/fancy/Cargo.toml", '[package]\nname = "fancy"\nversion = "0.1.0"\nedition = "2021"\n\n[lib]\nproc-macro = true\n')
    write(base .. "/fancy/src/lib.rs", '#[proc_macro_derive(Fancy, attributes(fancy))]\npub fn fancy(i: TokenStream) -> TokenStream { i }\n')
    write(base .. "/fancy/examples/e.rs", '#[derive(Fancy)]\n#[fancy(gamma, alpha = 1)]\nstruct E;\n/// #[fancy(gamma)]\n/// #[fancy(gamma)]\n')
    write(base .. "/ws/Cargo.toml", '[package]\nname = "ws"\nversion = "0.1.0"\nedition = "2021"\n\n[dependencies]\nfancy = { path = "../fancy" }\n')
    write(
      base .. "/ws/src/a.rs",
      table.concat({
        '#[derive(Fancy)]\n#[fancy(alpha = 1, beta(x, y))]\nstruct A;',
        '#[derive(Fancy)]\n#[fancy(alpha = "two")]\nstruct B;',
        '#[derive(Fancy)]\n#[fancy(alpha, delta = f(1, 2))]\nstruct C;',
        "",
      }, "\n")
    )
    write(base .. "/ws/src/main.rs", "fn main() {}\n")
    return base .. "/ws"
  end

  it("offers the keys the workspace and the dependency already write, most frequent first", function()
    local dir = fancy_ws()
    local labels, items, info = at("#[derive(Fancy)]\n#[fancy(|)]\nstruct Z;", dir)
    H.eq({ "alpha", "gamma", "beta", "delta" }, labels, "ranking by frequency (workspace counts double)")
    H.eq(false, info.matched, "no schema matched")
    H.match(items[1].detail, "fancy", true)
    H.match(items[1].documentation.value, "3× in this workspace", true)
    H.match(items[1].documentation.value, "learned from usage", true)
    H.eq("learned", items[1].data.macro_attrs)
  end)

'''),
    ...para('--', r'fancy_ws builds a path proc-macro dependency with a #[proc_macro_derive(Fancy, '
        r'attributes(fancy))] and gives it an example file, then writes the attribute in the '
        r'workspace three times with different keys. The test asserts the ranking alpha, gamma, '
        r'beta, delta (workspace usage counts double), that no schema matched, that the detail '
        r'mentions the crate, and that the documentation says it was learned from usage and counts '
        r'three occurrences in the workspace.'),
    ...sec(r'accepting a derive'),
    ...code('lua', r'tests/attrs_spec.lua · lines 1268-1300', r'''
  describe("the default hook", function()
    local function fake_actions(actions)
      local applied = {}
      stub(ca, "request", function(_, _, _, cb)
        vim.schedule(function()
          cb(actions, nil)
        end)
      end)
      stub(ca, "apply_async", function(a, cb)
        applied[#applied + 1] = a.title
        vim.schedule(function()
          cb(true)
        end)
      end)
      return applied
    end
    local info = { bufnr = 0, row = 1, col = 17, path = "serde::Serialize", crate = "serde" }
    local function action(title)
      return { title = title, kind = "quickfix" }
    end

    it("applies the single import that offers the expected path", function()
      local applied = fake_actions({ action("Import `serde::Serialize`"), action("Import `other::Serialize`"), action("Qualify as `serde::Serialize`") })
      ma.on_derive_accepted("Serialize", info)
      H.wait_for(function()
        return #applied > 0
      end, 2000, "an import applied")
      H.eq({ "Import `serde::Serialize`" }, applied)
    end)

    it("applies the only import when none names the expected path", function()
      local applied = fake_actions({ action("Import `serde::ser::Serialize`") })
      ma.on_derive_accepted("Serialize", info)
'''),
    ...para('--', r'The default import hook is tested without rust-analyzer: the code-action layer is '
        r'stubbed, request answering a list of actions and apply_async recording the title of the '
        r'one that is applied. The first test gives three actions, the right import, a lookalike '
        r'from another crate and a qualify action, and expects exactly the right import to be '
        r'applied. The next tests cover the only import that does not name the expected path, and '
        r'the ambiguous cases.'),
    ...sec(r'bounded reads'),
    ...code('lua', r'tests/attrs_spec.lua · lines 1391-1402', r'''
describe("macro_attrs bounded reads", function()
  it("skips a project schema file over 1 MB and reports it", function()
    local dir = H.tmpdir() .. "/big"
    write(dir .. "/Cargo.toml", '[package]\nname = "big"\nversion = "0.1.0"\nedition = "2024"\n')
    write(dir .. "/src/main.rs", "fn main() {}\n")
    write(dir .. "/.xyno-macros/attrs/big.json", '{"crate":"big","attributes":[]}' .. string.rep(" ", 1100 * 1024))
    local before = #ma.load_errors
    ma.schemas(dir)
    H.ok(#ma.load_errors >= before + 1, vim.inspect(ma.load_errors))
    H.match(table.concat(ma.load_errors, "\n"), "big.json", true)
  end)
end)
'''),
    ...para('--', r'The last group checks the size limit on a project schema: a file over a megabyte, made of '
        r'valid JSON followed by spaces, is skipped, and load_errors names the file.'),
    ...sec(r'what stays outside'),
    ...para('--', r'The live import path through a real rust-analyzer is the one test that needs the language '
        r'server; the rest of the file runs without it. The completion-menu specs that need '
        r'blink.cmp are in the blink source group and skip without it, as the README says.'),
    ...sec(r'history'),
    ...pt('--', r'08b2e8f', r'2026-10-22: the spec arrives with the headless runner and the smoke test.'),
  ],
);
