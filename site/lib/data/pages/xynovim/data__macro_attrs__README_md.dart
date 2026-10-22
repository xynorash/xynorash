import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/data/macro_attrs/README.md',
  lines: [
    heading(r'# Attribute schemas'),
    blank,
    ...text(r'The data format that lets #[serde( and #[clap( complete their keys. One JSON file per crate, plus per-project overrides. This page walks through the README of data/macro_attrs and what the code and the specs show behind each rule.'),
    blank,
    kv(r'role', r'documentation of the JSON schema format for macro-attribute completion'),
    kv(r'read by', r'lua/config/macro_attrs.lua (shipped files via the glob data/macro_attrs/*.json)'),
    kv(r'shipped schemas', r'bon, clap, derive_more, schemars, serde, sqlx, strum, thiserror, tokio, utoipa'),
    kv(r'size', r'61 lines of README, one commit (b9363cd, 2026-10-14)'),
    kv(r'tested by', r'tests/macro-attrs_spec.lua, macros-deps-flows_spec.lua, macro-tools_spec.lua'),
    blank, heading(r'## the problem this solves'),
    ...text(r'The header of lua/config/macro_attrs.lua says that rust-analyzer returns nothing inside the arguments of helper attributes, so keys and values were typed from memory. The data answers what a completion there needs to know, for example that rename_all takes one of eight case conventions, that tag and untagged exclude each other, or that rename_all_fields has since 1.0.195 in serde.json. The configuration carries that knowledge as data: a schema per crate that says which attributes exist, where they may be written, which keys they take and how the keys relate to each other.'),
    blank,
    ...text(r'The opening paragraph of the README states the scope in one sentence: the data for the completion inside helper-attribute arguments, with #[serde(, #[arg(, #[tokio::main( as examples, read by lua/config/macro_attrs.lua. One JSON file per crate, shipped in this directory, overridden by a project with .xynovim/macro_attrs/*.json in the workspace root.'),
    blank,
    ...code('markdown', r'data/macro_attrs/README.md · lines 1-3', r'''
# Attribute schemas

Data for the completion inside helper-attribute arguments (`#[serde(`, `#[arg(`, `#[tokio::main(`, ...), read by `lua/config/macro_attrs.lua`. One JSON file per crate. Shipped here; a project overrides them with `.xynovim/macro_attrs/*.json` in the workspace root (see the end).
'''),
    ...text(r'The consumer is a 1840-line Lua module, lua/config/macro_attrs.lua, which registers a completion source for blink.cmp for Rust buffers and a command, :MacroAttrs, that shows what the source sees at the cursor (attribute, target, schemas and where the dependency information came from). The module header says: Data: data/macro_attrs/<crate>.json (format in data/macro_attrs/README.md), overridden per attribute by <workspace>/.xynovim/macro_attrs/*.json. This README is therefore the contract between the data files and that module.'),
    blank,
    blank, heading(r'## the shape of a file'),
    ...code('markdown', r'data/macro_attrs/README.md · lines 5-14', r'''
## File

```json
{
  "crate": "serde",
  "versions": ">=1.0.0, <2.0.0",
  "docs_url": "https://serde.rs/attributes.html",
  "attributes": [ { "name": "serde", "...": "..." } ]
}
```
'''),
    ...text(r'Four fields at the top. The ellipsis in the example is literally in the README, a placeholder for the list of attributes; the real file is serde.json on the next pages of this directory.'),
    blank,
    ...bullet(r'crate', r'the package name of the dependency. A dash and an underscore are the same, because Cargo treats them so. The file is used only when the workspace member depends on that crate, so a project without serde never sees serde keys.'),
    ...bullet(r'versions', r'a Cargo-style requirement (>=1.0.0, <2, ^1, ~1.2, *). A file whose range the resolved version does not satisfy is ignored. The README adds the rule that matters for startup: an unknown version, for instance when cargo metadata has not loaded yet, satisfies everything. The completion works at once and gets more exact once the real version is known. The spec says the same: it never hides data because of what it cannot read.'),
    ...bullet(r'docs_url', r'the default link shown in the preview of an item.'),
    ...bullet(r'attributes', r'the list of attributes the crate defines.'),
    blank, heading(r'## an attribute'),
    ...code('markdown', r'data/macro_attrs/README.md · lines 23-32', r'''
## Attribute

| field | meaning |
| --- | --- |
| `name` | the attribute path as written: `serde`, `arg`, `error`, or `tokio::main`. A `crate::name` attribute macro matches when written in full, or by its last segment when imported (`use tokio::main;`) |
| `derives` | derive macros that bring this helper attribute into scope (`["Serialize", "Deserialize"]`). The helper is offered only when one of them is in a `#[derive(...)]` (also inside `cfg_attr`) of the item the attribute belongs to, and the derive resolves to this crate (a qualified path, or the `use` that imports it, so `Error` of thiserror and of derive_more are told apart). Leave it out for attribute macros |
| `applies_to` | where the attribute may be written: `container` (struct, enum, union), `container:struct`, `container:enum`, `field`, `variant`, `fn`, `param` (a function parameter). Also valid on each argument, where it narrows the attribute's |
| `needs_attr` | the item (the function, for `param`) must carry one of these attributes: `["bon::builder", "builder"]` |
| `docs_url` | link for this attribute (default: the file's) |
| `args` | the keys it takes |
'''),
    ...bullet(r'name', r'the attribute path as written. For a path like tokio::main, the match is on the full path, or on the last segment when it was imported with use tokio::main;. This is how one data file serves both writing styles.'),
    ...bullet(r'derives', r'the derive macros that bring a helper attribute into scope. This is the rule that makes the data accurate: #[serde(...)] is valid only on an item that derives Serialize or Deserialize, so the helper is offered only when one of them is in a #[derive(...)] of the item, also inside cfg_attr, and only when the derive resolves to this crate. The README gives the example of why: Error from thiserror and Error from derive_more are different derives with different helper attributes, and the editor tells them apart by a qualified path or by the use that imports the name. For attribute macros such as tokio::main, derives is left out.'),
    ...bullet(r'applies_to', r'where the attribute may be written: container (struct, enum, union), container:struct, container:enum, field, variant, fn, param. It can also be set on an argument, where it narrows the attribute’s.'),
    ...bullet(r'needs_attr', r'the item (or the function, for param) must carry one of the listed attributes: the README example is the two spellings of a builder, bon::builder and builder.'),
    ...bullet(r'docs_url and args', r'a link for this attribute, and its keys.'),
    blank, heading(r'## an argument'),
    ...code('markdown', r'data/macro_attrs/README.md · lines 34-40', r'''
## Argument

| field | meaning |
| --- | --- |
| `key` | the key as written (`rename_all`). A key that is only a label (`"..."` for a positional string) uses `positional` |
| `kind` | `flag` (bare key), `string` (`key = "..."`), `ident`, `path`, `int`, `bool` (bare key or `= true/false`), `enum`, `expr` |
| `values` | for `enum`: the choices, strings or `{ "value": ..., "doc": ... }` |
'''),
    ...text(r'An argument is a key inside the parentheses. The kind decides how the completion inserts it and what it offers after the equals sign: flag is a bare key, string is key = "...", ident, path and int are what they say, bool is a bare key or = true/false, enum offers a fixed list, and expr is an arbitrary expression.'),
    blank,
    ...bullet(r'key and positional', r'the key as written. A key that is only a label, like the unkeyed string of #[error("message")], uses positional instead, and it may only come first. The spec shows it sorts first and carries a placeholder.'),
    ...bullet(r'values and quoted', r'for an enum, the choices, as strings or as objects with a value and a doc. quoted says whether the value is a string literal: rename_all = "camelCase" has quotes, action = ArgAction::SetTrue has none. The menu inserts the quotes only if they are not typed yet.'),
    ...bullet(r'snippet', r'what to insert, in LSP snippet syntax, with rename = "${1:name}" as the example. Without one, the default follows the kind. A snippet that ends in a quote placeholder re-opens the menu inside the quotes, which is how an enum key leads on to its values; the spec for the blink.cmp source tests the sequence of typing inside #[serde(, accepting a key and seeing its values.'),
    ...bullet(r'alt', r'extra menu entries for the same key, each with a label, a snippet and a doc. For serde’s default there are two entries: the flag and default = "path".'),
    blank, heading(r'## relations between keys'),
    ...text(r'Most of the value of a schema is in the rules that stop wrong code. Four fields describe how keys relate.'),
    blank,
    ...bullet(r'conflicts', r'keys that cannot be combined with this one. The README says a key is hidden when it, or any key already written, lists the other. The relation is therefore symmetric in practice: it is enough for one side to name the other. In serde.json, rename has no conflicts entry at all, but skip lists rename, so after writing skip the menu does not offer rename and after writing rename it does not offer skip.'),
    ...bullet(r'requires', r'keys this one needs. Such a key is still offered but sorted last until its requirements are present. In serde.json, content requires tag, so content comes after tag in the menu and is never hidden, which is the right behaviour for a key that cannot work without another one.'),
    ...bullet(r'repeatable', r'may appear several times; every other key is offered once. In serde.json only alias has it.'),
    ...bullet(r'derives on an argument', r'the argument exists only for these derives of the item. The README gives the example of sqlx, whose FromRow keys and Type keys differ although both live in one attribute.'),
    ...bullet(r'since', r'the first version of the crate that has the key. It is hidden for older resolved versions: rename_all_fields has since 1.0.195, expecting has 1.0.133 and other has 1.0.131.'),
    ...bullet(r'nested', r'keys accepted in a parenthesised form: rename(serialize = "..", deserialize = "..").'),
    ...bullet(r'doc and doc_url', r'one sentence, shown in the preview with the other facts, and a link for this key.'),
    blank, heading(r'## project overrides'),
    ...code('markdown', r'data/macro_attrs/README.md · lines 55-57', r'''
## Project overrides

`.xynovim/macro_attrs/<anything>.json` in the workspace root uses the same format. For a crate that has a shipped file, an attribute with the same `name` replaces every shipped attribute of that name in that crate (the others stay); for another crate the file is added as it is. A broken file is skipped and the problem is listed by `:MacroAttrs`. Edit a file and the next completion picks it up.
'''),
    ...text(r'A project can add or replace schemas without editing this repository. The rules are exact and small. A file in .xynovim/macro_attrs/ has the same format and any name. For a crate that has a shipped file, an attribute with the same name replaces every shipped attribute of that name in that crate, and the others stay; for a crate without one, the file is added as it is. So a project can fix one attribute of serde without copying the whole file. A broken file is skipped and :MacroAttrs lists the problem, and editing a file takes effect on the next completion, with no restart. Five tests in the spec group project schemas in tests/macro-attrs_spec.lua cover these: replacement of the same attribute while the rest stays, a file for another crate with its own derive scope, a broken file skipped and reported with the shipped schemas still working, a hand-written file with a string where a list is expected (reported, not raised), and an edited file picked up by the next request.'),
    blank,
    blank, heading(r'## no schema at all'),
    ...code('markdown', r'data/macro_attrs/README.md · lines 59-61', r'''
## No schema

An attribute of a dependency without a schema is not left empty: the keys already written inside the same attribute in the workspace and in the dependency's own sources (examples, docs, tests) are offered, most frequent first (bounded scan, cached for two minutes).
'''),
    ...text(r'An attribute from a crate that has no shipped schema is not left empty. The completion looks at keys already written inside the same attribute elsewhere, in the workspace and in the dependency’s own sources (examples, docs and tests), and offers them most frequent first. The scan is bounded and cached for two minutes (the module sets learn_ttl to 120 seconds). Only keys are learned, not values, a key that is being typed does not teach itself, and only the helper of a derive in scope is learned. Those three points are in the spec group learn from usage.'),
    blank,
    blank, heading(r'## how the data is kept honest'),
    ...text(r'Hand-written schemas can rot, so the spec checks them. Every shipped schema must load without errors; ten crates must have a schema with a docs_url and a versions range; every argument must have a non-empty doc; an enum must have values; and a key must be unique for the same attribute, targets and derives. Another test checks that the derive helper attributes in the schemas are declared by the real proc-macro crates, looked up in the registry where that is available. The serde schema is also tested against a fixed list of 24 keys (the test is titled every key the task lists), so removing one of them fails a test.'),
    blank,
    blank, heading(r'## design decisions and trade-offs'),
    ...bullet(r'data, not code', r'adding a crate is adding a file; no Lua is touched. The cost is that a crate that changes its attributes needs a schema edit, which the since and versions fields soften.'),
    ...bullet(r'JSON, not Lua', r'the files are plain data that other tools can read, and a broken file is a reported error, not a crash on require.'),
    ...bullet(r'hide only when sure', r'unknown version, unreadable data, missing metadata all lead to showing more, never less.'),
    ...bullet(r'one directory, one format', r'shipped files and project files are parsed by the same code and follow the same rules.'),
    blank, heading(r'## history'),
    ...bullet(r'b9363cd 2026-10-14', r'Macros and dependencies: dependency freshness, crate add, missing-feature fix, attribute and derive completion, macro tools, import engine. The schemas and this README arrive in that commit.'),
    ...bullet(r'2026-10-22', r'the Rust tooling was also extracted into the standalone repository xyno-macros.nvim, which carries its own copy of this directory. The two READMEs differ in exactly two lines: the plugin’s names the reader lua/xyno_macros/attrs.lua and the override directory .xyno-macros/attrs, where this one names lua/config/macro_attrs.lua and .xynovim/macro_attrs. In this repository the data, the module and the spec are unchanged by that.'),
  ],
);
