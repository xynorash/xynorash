import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-macros.nvim/data/macro_attrs/README.md',
  lines: [
    heading(r'# Attribute schemas'),
    blank,
    ...text(r'This file is the specification of the data format that attrs.lua reads. It is the '
        r'contract between the knowledge about ten crates and the code that uses it. Each field in '
        r'the tables below is read by a specific function, and this page follows each field to the '
        r'line of code that gives it meaning.'),
    kv(r'role', r'format reference for data/macro_attrs/*.json and .xyno-macros/attrs/*.json'),
    kv(r'size', r'61 lines, three tables and two short sections'),
    kv(r'read by', r'lua/xyno_macros/attrs.lua (check_schema, schema_items, arg_allowed and others)'),
    kv(r'history', r'added with the data in b9854b7 (2026-10-22)'),
    ...sec(r'why a format and not code'),
    ...text(r'The alternative to a data file per crate is a Lua table inside the plugin, or hard-coded '
        r'knowledge scattered through the completion logic. Data wins here for three reasons that '
        r'can be read in the code. A user can override or extend it per project without touching '
        r'the plugin (the merge rule is in M.schemas). A broken file can be skipped with a message '
        r'instead of breaking completion (check_schema returns problems and keeps the rest). And a '
        r'crate’s attributes change faster than the plugin does, so the version range is part of '
        r'the data (satisfies is applied to each file).'),
    ...sec(r'the file'),
    ...code('markdown', r'data/macro_attrs/README.md · lines 7-21', r'''
```json
{
  "crate": "serde",
  "versions": ">=1.0.0, <2.0.0",
  "docs_url": "https://serde.rs/attributes.html",
  "attributes": [ { "name": "serde", "...": "..." } ]
}
```

| field | meaning |
| --- | --- |
| `crate` | the dependency's package name (`-` and `_` are the same). The file is used only when the workspace member depends on it |
| `versions` | cargo-style requirement on the resolved version (`>=1.0.0, <2`, `^1`, `~1.2`, `*`); a file whose range the dependency does not satisfy is ignored. An unknown version (metadata not loaded yet) satisfies everything |
| `docs_url` | default documentation link shown in the item's preview |
| `attributes` | the attributes the crate defines |
'''),
    ...text(r'The top level has four fields. crate is the dependency’s package name, with hyphen and '
        r'underscore treated as the same; the file is used only if the workspace member depends on '
        r'it, which the code checks with dependencies().by_name. versions is a cargo requirement '
        r'matched against the resolved version, and the README says the important consequence: an '
        r'unknown version (metadata not loaded yet) satisfies everything, which is the '
        r'never-hide-data rule of satisfies. docs_url is the fallback link in the preview, and '
        r'attributes is the list that matters.'),
    ...sec(r'the attribute'),
    ...code('markdown', r'data/macro_attrs/README.md · lines 25-32', r'''
| field | meaning |
| --- | --- |
| `name` | the attribute path as written: `serde`, `arg`, `error`, or `tokio::main`. A `crate::name` attribute macro matches when written in full, or by its last segment when imported (`use tokio::main;`) |
| `derives` | derive macros that bring this helper attribute into scope (`["Serialize", "Deserialize"]`). The helper is offered only when one of them is in a `#[derive(...)]` (also inside `cfg_attr`) of the item the attribute belongs to, and the derive resolves to this crate (a qualified path, or the `use` that imports it, so `Error` of thiserror and of derive_more are told apart). Leave it out for attribute macros |
| `applies_to` | where the attribute may be written: `container` (struct, enum, union), `container:struct`, `container:enum`, `field`, `variant`, `fn`, `param` (a function parameter). Also valid on each argument, where it narrows the attribute's |
| `needs_attr` | the item (the function, for `param`) must carry one of these attributes: `["bon::builder", "builder"]` |
| `docs_url` | link for this attribute (default: the file's) |
| `args` | the keys it takes |
'''),
    ...text(r'An attribute is matched by its name as written. A path such as tokio::main matches when '
        r'written in full, or by its last segment when imported (use tokio::main), which is '
        r'path_matches. The derives field is the scope rule: the helper is offered only when one of '
        r'those derives is on the item and resolves to this crate. The text gives the example that '
        r'is the reason for the clause about resolution: Error of thiserror and Error of '
        r'derive_more are told apart by a qualified path or by the use that imports them. For '
        r'attribute macros the field is left out. applies_to is the target classification from '
        r'target_of: container (struct, enum, union), container:struct, container:enum, field, '
        r'variant, fn and param. needs_attr is how bon’s builder attributes are scoped: the item, '
        r'or for param the function, must carry one of the listed attributes.'),
    ...sec(r'the argument'),
    ...code('markdown', r'data/macro_attrs/README.md · lines 36-53', r'''
| field | meaning |
| --- | --- |
| `key` | the key as written (`rename_all`). A key that is only a label (`"..."` for a positional string) uses `positional` |
| `kind` | `flag` (bare key), `string` (`key = "..."`), `ident`, `path`, `int`, `bool` (bare key or `= true/false`), `enum`, `expr` |
| `values` | for `enum`: the choices, strings or `{ "value": ..., "doc": ... }` |
| `quoted` | for `enum`: the value is a string literal (`rename_all = "camelCase"`); otherwise it is bare (`action = ArgAction::SetTrue`). The menu inserts the quotes when they are not typed yet |
| `applies_to` | see above; default: the attribute's |
| `derives` | the argument only exists for these derives of the item (sqlx's `FromRow` keys vs `Type` keys) |
| `conflicts` | keys that cannot be combined with this one. A key is hidden when it, or any key already written, lists the other |
| `requires` | keys this one needs; still offered, but sorted last until they are present |
| `repeatable` | may appear several times (`alias`); every other key is offered once |
| `since` | first version of the crate that has it; hidden for older resolved versions |
| `nested` | keys accepted in a parenthesised form: `rename(serialize = "..", deserialize = "..")` |
| `positional` | an unkeyed entry that may only come first (`#[error("message")]`) |
| `doc` | one sentence, shown in the preview with the other facts |
| `doc_url` | link for this key |
| `snippet` | what to insert, in LSP snippet syntax (`rename = "${1:name}"`); the default follows `kind`. A snippet ending in a quote placeholder re-opens the menu inside it, for `enum` values |
| `alt` | extra menu entries for the same key: `[{ "label": "default = \"path\"", "snippet": "default = \"$1\"", "doc": "..." }]` |
'''),
    ...text(r'Arguments are where the value of the data lies. The kind says how to complete: a flag is '
        r'a bare key, a string takes key = "...", an enum offers values, and expr is the catch-all. '
        r'quoted decides whether the menu inserts the quotes. The relationships between keys are '
        r'three fields. conflicts hides a key when it or any already written key lists the other, '
        r'so the declaration only has to be on one side. requires keeps a key offered but sorts it '
        r'last until its prerequisites are written. repeatable allows a key to appear again '
        r'(alias). since hides a key for older resolved versions, which the code checks against the '
        r'version from cargo metadata. nested is for the parenthesised form, rename(serialize = '
        r'"..", deserialize = ".."). positional is an unkeyed first entry like the message of '
        r'#[error("...")]. snippet gives the exact insertion in LSP snippet syntax, and the note '
        r'about a snippet that ends in a quote placeholder explains the retrigger: for an enum, '
        r'accepting the key reopens the menu inside the quotes. alt adds extra menu entries for the '
        r'same key, such as default = "path".'),
    ...sec(r'overrides'),
    ...code('markdown', r'data/macro_attrs/README.md · lines 57-57', r'''
`.xyno-macros/attrs/<anything>.json` in the workspace root uses the same format. For a crate that has a shipped file, an attribute with the same `name` replaces every shipped attribute of that name in that crate (the others stay); for another crate the file is added as it is. A broken file is skipped and the problem is listed by `:MacroAttrs`. Edit a file and the next completion picks it up.
'''),
    ...text(r'The rule is stated precisely, and it is the one implemented in schemas(): for a crate '
        r'that has a shipped file, an attribute of the same name replaces every shipped attribute '
        r'of that name in that crate and the others stay; for another crate the file is added as it '
        r'is. A broken file is skipped and :MacroAttrs lists the problem. Editing a file takes '
        r'effect on the next completion because the cache is keyed by modification times.'),
    ...sec(r'no schema'),
    ...code('markdown', r'data/macro_attrs/README.md · lines 61-61', r'''
An attribute of a dependency without a schema is not left empty: the keys already written inside the same attribute in the workspace and in the dependency's own sources (examples, docs, tests) are offered, most frequent first (bounded scan, cached for two minutes).
'''),
    ...text(r'The last paragraph describes the fallback: when an attribute of a dependency has no '
        r'schema, the keys already written inside the same attribute in the workspace and in the '
        r'dependency’s own sources, examples, docs and tests, are offered by frequency, from a '
        r'bounded scan cached for two minutes. The two minutes are the learn_ttl value in attrs.lua.'),
    ...sec(r'how the ten shipped files use the format'),
    ...text(r'The shipped schemas show how much of the format is needed in practice. By the count of '
        r'key fields: clap has 111, utoipa 53, bon 40, schemars 31, serde 30, strum 25, derive_more '
        r'22, sqlx 11, tokio 9 and thiserror 3. Small files are small because the crate has little '
        r'to complete: thiserror’s helper is #[error(...)] with a positional format string and a '
        r'few keys.'),
    ...sec(r'a point to notice'),
    ...text(r'The data README documents sixteen argument fields. The checker in attrs.lua checks the crate name, '
        r'that each attribute has a name and that each argument has a key and a known kind; list-valued fields may be '
        r'given as single values; the other argument fields are not checked (a misspelt conflicts, for instance, '
        r'would be silently unused). The format is documented more strictly than it is enforced.'),
    ...sec(r'history'),
    ...bullet(r'b9854b7', r'2026-10-22, with the ten schema files and the code that reads them.'),
  ],
);
