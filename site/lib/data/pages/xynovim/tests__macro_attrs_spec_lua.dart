import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/macro-attrs_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'macro-attrs_spec.lua — completing the arguments of serde, clap, thiserror and seven more attribute macros'),
    cm('--', r'a table of cases, shipped JSON schemas checked against the real proc-macro crates, version gating and learning from usage'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/macro_attrs.lua, data/macro_attrs/*.json and lua/plugins/macro-attrs.lua'),
    kv(r'language', r'Lua spec, 1382 lines, 39 it() blocks, 12 describe() blocks'),
    kv(r'hermetic', r'workspaces are temp copies of the deps-lab fixture; cargo metadata is stubbed except in one test'),
    kv(r'registry', r'derive discovery reads serde_derive, clap_derive and thiserror-impl sources and skips without them'),
    kv(r'history', r'4 commits, 2026-10-14 to 2026-10-21'),
    ...sec(r'why this file exists'),
    ...para('--', r'rust-analyzer completes names and paths. It does not know what goes inside #[serde(...)], #[arg(...)] or #[error(...)], because those are arguments of proc macros, in a language defined by the macro crate. macro_attrs fills the gap with data: JSON schemas for ten crates (serde, clap, thiserror, tokio, strum, derive_more, sqlx, utoipa, schemars and bon) in data/macro_attrs, plus a completion source for blink.cmp that works out which attribute the cursor is in, on which target (container, field, variant), which derives are in scope, which keys apply and which are already written. Since it is driven by data, the spec is partly data driven too: a table of cases and tests that validate the data against reality.'),
    ...code('lua', r'tests/macro-attrs_spec.lua · lines 1-8', r'''
-- config.macro_attrs: completion inside helper-attribute arguments and #[derive(...)]
-- (lua/config/macro_attrs.lua, data/macro_attrs/*.json, lua/plugins/macro-attrs.lua).
-- Hermetic: workspaces are temp copies of the deps-lab fixture, cargo metadata is
-- stubbed out (dependencies come from the Cargo.toml scan) except in the one test that
-- asks for the real thing. Derive discovery reads the registry sources of serde_derive,
-- clap_derive and thiserror-impl and skips without them. Only the derive `use` test
-- needs rust-analyzer.
local H = require("xynotest.helpers")'''),
    ...sec(r'the table of cases'),
    ...para('--', r'Each case is a title, a Rust source with a bar where the cursor is, a list of labels that must be present and a list that must not be. Examples: clap command on the container offers name, version, author and about but not short or long; on a field it offers subcommand, flatten and skip but not name; on a Subcommand variant it offers alias and hide but not subcommand; action = offers ArgAction::SetTrue without quoting; value on a ValueEnum variant offers name, alias, help and skip but not short or about. Negative cases have exact = 0: outside an attribute; after the attribute is closed; inside a format string of the attribute (error("bad |")); a crate that is not a dependency, where sqlx keys must not appear. A loop turns each case into a test, with a skip when the case needs registry sources that are not in the local cargo registry. The assertion helpers also check that labels are unique and count the items when exact is given.'),
    ...code('lua', r'tests/macro-attrs_spec.lua · lines 147-153, 335-352, 583-601, 603-621', r'''
local cases = {
  -- serde
  {
    "serde container struct",
    "use serde::Serialize;\n#[derive(Serialize)]\n#[serde(|)]\nstruct A { x: u32 }",
    { "rename", "rename_all", "deny_unknown_fields", "default", "bound", "transparent", "from", "try_from", "into", "remote", "tag", "crate" },
    { "skip", "flatten", "alias", "skip_serializing_if", "content", "untagged", "getter" },
...
  {
    "clap command on the container",
    "#[derive(Parser)]\n#[command(|)]\nstruct C {}",
    { "name", "version", "author", "about", "long_about", "subcommand_required", "arg_required_else_help", "propagate_version", "next_line_help", "disable_help_flag", "disable_help_subcommand", "rename_all" },
    { "short", "long", "subcommand", "flatten", "value_name" },
  },
  {
    "clap command on a field (subcommand / flatten)",
    "#[derive(Parser)]\nstruct C {\n    #[command(|)]\n    sub: Sub,\n}",
    { "subcommand", "flatten", "skip" },
    { "name", "about", "version" },
  },
  {
    "clap command on a Subcommand variant",
    "#[derive(Subcommand)]\nenum S {\n    #[command(|)]\n    Run,\n}",
    { "name", "about", "alias", "external_subcommand", "hide" },
    { "subcommand" },
  },
...
    {},
    {},
    exact = 0,
  },
  {
    "inside a format string of the attribute",
    '#[derive(Error)]\nenum E {\n    #[error("bad |")]\n    A,\n}',
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
...
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

-- ------------------------------------------------------------- item details'''),
    ...sec(r'data that is validated'),
    ...para('--', r'The schema test loads every shipped schema and requires zero load errors; each of the ten crates must be present with a docs_url and a versions table; every argument must have a doc, an enum must have values, and no key may be defined twice for the same targets and derives. A schema that passes this cannot show an empty description or a duplicated item.'),
    ...code('lua', r'tests/macro-attrs_spec.lua · lines 673-699', r'''
  it("every shipped schema is valid and every key is unique per attribute and target", function()
    local shipped = ma.shipped()
    H.ok(next(shipped), "schemas loaded")
    H.eq(0, #ma.load_errors, "load errors: " .. vim.inspect(ma.load_errors))
    for _, crate in ipairs({ "serde", "clap", "thiserror", "tokio", "strum", "derive_more", "sqlx", "utoipa", "schemars", "bon" }) do
      H.ok(shipped[crate], "schema for " .. crate)
      H.ok(shipped[crate].docs_url, crate .. " has docs_url")
      H.ok(shipped[crate].versions, crate .. " has versions")
    end
    for crate, file in pairs(shipped) do
      for _, attr in ipairs(file.attributes) do
        local keys = {}
        for _, arg in ipairs(attr.args) do
          H.ok(arg.doc and arg.doc ~= "", ("%s.%s.%s has a doc"):format(crate, attr.name, arg.key))
          if arg.kind == "enum" then
            H.ok(arg.values and #arg.values > 0, ("%s.%s.%s enum without values"):format(crate, attr.name, arg.key))
          end
          local id = arg.key .. "|" .. table.concat(arg.applies_to or {}, ",") .. "|" .. table.concat(arg.derives or {}, ",")
          H.not_ok(keys[id], ("%s.%s: %s defined twice for the same targets"):format(crate, attr.name, arg.key))
          keys[id] = true
          for _, c in ipairs(arg.conflicts or {}) do
            H.ok(type(c) == "string")
          end
        end
      end
    end
  end)'''),
    ...sec(r'the schemas are checked against the real macro crates'),
    ...para('--', r'The most interesting test goes to the cargo registry. For seven helper attributes it finds the registry directory of the proc-macro crate, reads src/*.rs, finds the proc_macro_derive attribute that names the derive, and requires the helper name inside the next 300 characters. For instance serde_derive declares serde on Serialize, clap_derive declares arg and command on Parser, value on ValueEnum and group on Args, and thiserror-impl declares error and from on Error. If a crate renames a helper, the schema disagrees with the source and the test says which crate declares which helper. It skips if the sources are not in the registry.'),
    ...code('lua', r'tests/macro-attrs_spec.lua · lines 712-738', r'''
  it("derive helper attributes in the schemas are declared by the real proc-macro crates (where in the registry)", function()
    if not registry_ok then
      skip("registry sources of serde_derive / clap_derive / thiserror-impl missing")
    end
    local checks = {
      { "serde_derive", "serde", "Serialize" },
      { "clap_derive", "arg", "Parser" },
      { "clap_derive", "command", "Parser" },
      { "clap_derive", "value", "ValueEnum" },
      { "clap_derive", "group", "Args" },
      { "thiserror-impl", "error", "Error" },
      { "thiserror-impl", "from", "Error" },
    }
    for _, c in ipairs(checks) do
      local dir = cm.registry_dir(c[1])
      local found = false
      for _, d in ipairs(dir and vim.fn.glob(dir .. "/src/*.rs", true, true) or {}) do
        local text = assert(io.open(d)):read("*a")
        local s = text:find("proc_macro_derive%s*%(%s*" .. c[3])
        if s then
          local inside = text:sub(s, s + 300)
          found = found or inside:find("%f[%w_]" .. c[2] .. "%f[^%w_]") ~= nil
        end
      end
      H.ok(found, ("%s declares helper %s on %s"):format(c[1], c[2], c[3]))
    end
  end)'''),
    ...sec(r'long files stay fast'),
    ...para('--', r'Completion runs on each keystroke, so reading whole buffers would hurt. The test builds a file of about 12,500 lines (2,500 derived structs) with a use thiserror::Error at the top and an open #[error( at the bottom, asks for items at the cursor and checks three things: thiserror keys appear (the import at the top still counts), derive_more keys do not, the target is a variant, and the work took under 300 ms.'),
    ...code('lua', r'tests/macro-attrs_spec.lua · lines 744-763', r'''
  it("are read around the cursor only (fast), imports at the top still count", function()
    local lines = { "use thiserror::Error;", "" }
    for i = 1, 2500 do
      vim.list_extend(lines, { "#[derive(Debug)]", ("pub struct S%d {"):format(i), "    pub a: u32,", "}", "" })
    end
    vim.list_extend(lines, { "#[derive(Error)]", "enum E {", "    #[error(", "    A,", "}" })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, wide() .. "/src/lib.rs")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local t = vim.uv.hrtime()
    local items, info = ma.items(buf, #lines - 2, #"    #[error(")
    local ms = (vim.uv.hrtime() - t) / 1e6
    local labels = vim.tbl_map(function(i)
      return i.label
    end, items)
    has_all(labels, { "transparent", "fmt" }, "thiserror's keys: Error is imported from thiserror in the head of the file")
    has_none(labels, { "source", "ignore" }, "derive_more's keys")
    H.eq("variant", info.target.kind)
    H.ok(ms < 300, ("took %.0f ms for %d lines"):format(ms, #lines))
  end)'''),
    ...sec(r'versions'),
    ...para('--', r'A key that appeared in a later release must not be offered to a project on an older version. The test stubs the dependency scan to report serde 1.0.100 and requires tag and rename_all but not rename_all_fields (since 1.0.195); with 1.0.200 it must appear; with serde 2.0.0, which is outside the schema range, no key is offered at all. Another test establishes that unreadable ranges never hide data.'),
    ...code('lua', r'tests/macro-attrs_spec.lua · lines 792-818', r'''
  it("keys newer than the resolved version are hidden, the file's range is honoured", function()
    local real = ma.dependencies
    stub(ma, "dependencies", function(path, root)
      local d = real(path, root)
      d.by_name.serde.version = "1.0.100"
      d.by_name.thiserror.version = "2.0.0"
      return d
    end)
    local labels = at("#[derive(Serialize)]\n#[serde(|)]\nenum E { A }")
    has_all(labels, { "tag", "rename_all" }, "old serde")
    has_none(labels, { "rename_all_fields" }, "old serde (rename_all_fields is since 1.0.195)")
    stub(ma, "dependencies", function(path, root)
      local d = real(path, root)
      d.by_name.serde.version = "1.0.200"
      return d
    end)
    has_all(at("#[derive(Serialize)]\n#[serde(|)]\nenum E { A }"), { "rename_all_fields" }, "new serde")
    stub(ma, "dependencies", function(path, root)
      local d = real(path, root)
      d.by_name.serde.version = "2.0.0"
      return d
    end)
    local _, items = at("#[derive(Serialize)]\n#[serde(|)]\nenum E { A }")
    for _, it in ipairs(items) do
      H.not_ok(it.data.macro_attrs == "key", "serde 2.x is outside the schema's range, offered " .. it.label)
    end
  end)'''),
    ...sec(r'project schemas'),
    ...para('--', r'A project can ship its own schemas in .xynovim/macro_attrs. An attribute in the project file replaces the shipped one of the same name and the rest stays; another workspace is unaffected. A file for another crate is added with its own derive scope; a broken file is skipped and reported while the shipped ones keep working; a wrong shape is reported, not raised; and editing the file is picked up by the next request. A file over 1 MB is skipped and reported (the last block). The first test replaces serde in a temp workspace by a one-key schema and expects exactly my_key.'),
    ...code('lua', r'tests/macro-attrs_spec.lua · lines 912-925', r'''
  it("an attribute of the project file replaces the shipped one of the same name, the rest stays", function()
    local dir = ws()
    write(
      dir .. "/.xynovim/macro_attrs/serde.json",
      vim.json.encode({
        crate = "serde",
        attributes = { { name = "serde", derives = { "Serialize" }, applies_to = { "container" }, args = { { key = "my_key", kind = "flag", doc = "mine" } } } },
      })
    )
    local labels = at("#[derive(Serialize)]\n#[serde(|)]\nstruct A;", dir)
    H.eq({ "my_key" }, labels)
    -- another workspace is not affected
    has_all(at("#[derive(Serialize)]\n#[serde(|)]\nstruct A;"), { "rename" }, "lab")
  end)'''),
    ...sec(r'learning from usage'),
    ...para('--', r'When no schema matches, for example a custom derive Fancy with a #[fancy(...)] helper, the source offers the keys that the workspace and the dependency already write, most frequent first, with the workspace counting double. The test builds a workspace and requires alpha, gamma, beta, delta in that order, a detail naming the attribute, documentation like 3× in this workspace and learned from usage, and data marking it learned. Keys already written are not offered, a typed key does not teach itself, and values are not learned.'),
    ...code('lua', r'tests/macro-attrs_spec.lua · lines 1020-1029', r'''
  it("offers the keys the workspace and the dependency already write, most frequent first", function()
    local dir = fancy_ws()
    local labels, items, info = at("#[derive(Fancy)]\n#[fancy(|)]\nstruct Z;", dir)
    H.eq({ "alpha", "gamma", "beta", "delta" }, labels, "ranking by frequency (workspace counts double)")
    H.eq(false, info.matched, "no schema matched")
    H.match(items[1].detail, "fancy", true)
    H.match(items[1].documentation.value, "3× in this workspace", true)
    H.match(items[1].documentation.value, "learned from usage", true)
    H.eq("learned", items[1].data.macro_attrs)
  end)'''),
    ...sec(r'the blink.cmp source'),
    ...para('--', r'The source answers get_completions with the same items, marked incomplete because the answer depends on the text. It claims trigger characters only inside an attribute it knows: after #[serde( it claims the parenthesis and the quote, after #[cfg( it claims none (rust-analyzer keeps #[cfg( ), after plain code none, after #[derive( the parenthesis and after #[tokio::main( the equals sign. It is registered for Rust buffers next to the default sources and above rust-analyzer. An integration test types inside #[serde( and shows that accepting a key expands its snippet and re-opens the menu for values.'),
    ...code('lua', r'tests/macro-attrs_spec.lua · lines 1083-1105', r'''
  it("only claims trigger characters inside an attribute it knows", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local source = ma.new({})
    --- trigger characters with the cursor at the end of `line`, in insert mode
    local function chars_after(line)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
      local got
      _G.__macro_attrs_trig = function()
        got = source:get_trigger_characters()
      end
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      H.feed("A<Cmd>lua _G.__macro_attrs_trig()<CR><Esc>")
      _G.__macro_attrs_trig = nil
      return got
    end
    H.has(chars_after("#[serde("), "(")
    H.has(chars_after("#[serde("), '"')
    H.eq({}, chars_after("#[cfg("), "rust-analyzer keeps #[cfg(")
    H.eq({}, chars_after("let x = foo("))
    H.has(chars_after("#[derive("), "(")
    H.has(chars_after("#[tokio::main("), "=")
  end)'''),
    ...sec(r'accepting a derive that is not in scope'),
    ...para('--', r'Offering Serialize in a derive list without the use line leaves code that does not compile. The hook receives the name, the expected path and where it was inserted. It is not called when the name is imported, glob-imported, builtin or qualified, or when a key was accepted. The default hook applies the single import that offers the expected path; the only import when none names it; nothing when ambiguous; and asks again while rust-analyzer does not know the name yet. One test uses the real rust-analyzer.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b9363cd (2026-10-14)', r'created (attribute and derive completion).'),
    ...pt('--', r'19f974c (2026-10-15)', r'review fixes.'),
    ...pt('--', r'9641d08 (2026-10-16)', r'drive letter in canonical roots for Windows.'),
    ...pt('--', r'7715eb8 (2026-10-21)', r'"reduce the Windows/macOS suites to what run 39655339161 shows passing; the rest skips with a reason".'),
  ],
);
