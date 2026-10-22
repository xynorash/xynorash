import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/data/macro_attrs/serde.json',
  lines: [
    cm(r'//', '──────────────────────────────────────────'),
    cm(r'//', r'data/macro_attrs/serde.json'),
    cm(r'//', r'the schema of #[serde(...)]'),
    cm(r'//', r'30 keys, each with a doc, a target, and the rules that keep wrong combinations out of the menu'),
    cm(r'//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'shipped schema for the serde crate, one of ten in data/macro_attrs'),
    kv(r'format', r'described in data/macro_attrs/README.md'),
    kv(r'size', r'435 lines of JSON: one attribute (serde), 30 arguments'),
    kv(r'crate range', r'>=1.0.0, <2.0.0'),
    kv(r'commit', r'b9363cd (2026-10-14), with the other shipped schemas'),
    ...sec(r'what the file says'),
    ...code('json', r'data/macro_attrs/serde.json · lines 1-18', r'''
{
  "crate": "serde",
  "versions": ">=1.0.0, <2.0.0",
  "docs_url": "https://serde.rs/attributes.html",
  "attributes": [
    {
      "name": "serde",
      "derives": [
        "Serialize",
        "Deserialize"
      ],
      "applies_to": [
        "container",
        "field",
        "variant"
      ],
      "docs_url": "https://serde.rs/attributes.html",
      "args": [
'''),
    ...para(r'//', r'The top of the file follows the README. The crate is serde, the file applies to versions from 1.0.0 up to but not including 2.0.0, and the documentation link is serde’s attribute page. There is one attribute, serde. It has derives of Serialize and Deserialize, so #[serde(...)] is offered on an item that derives either of them, and applies_to of container, field and variant, so it is not offered on a function or a parameter.'),
    blank,
    ...sec(r'a key with a nested form'),
    ...code('json', r'data/macro_attrs/serde.json · lines 19-34', r'''
        {
          "key": "rename",
          "kind": "string",
          "doc": "Serialize and deserialize this item under the given name instead of its Rust name.",
          "applies_to": [
            "container",
            "field",
            "variant"
          ],
          "nested": [
            "serialize",
            "deserialize"
          ],
          "snippet": "rename = \"${1:name}\"",
          "doc_url": "https://serde.rs/attributes.html"
        },
'''),
    ...para(r'//', r'rename is a string key that applies to a container, a field or a variant. Its nested list names serialize and deserialize, the two keys that serde accepts in a parenthesised form, rename(serialize = "a", deserialize = "b"). The snippet gives the cursor a placeholder inside the quotes. Every key has a doc sentence, which the spec requires; of the 30 keys only rename carries a doc_url of its own.'),
    blank,
    ...sec(r'an enum key, and a key that needs a version'),
    ...code('json', r'data/macro_attrs/serde.json · lines 35-58', r'''
        {
          "key": "rename_all",
          "kind": "enum",
          "doc": "Rename all fields (struct) or variants (enum) according to the given case convention.",
          "applies_to": [
            "container",
            "variant"
          ],
          "values": [
            "lowercase",
            "UPPERCASE",
            "PascalCase",
            "camelCase",
            "snake_case",
            "SCREAMING_SNAKE_CASE",
            "kebab-case",
            "SCREAMING-KEBAB-CASE"
          ],
          "quoted": true,
          "nested": [
            "serialize",
            "deserialize"
          ]
        },
'''),
    ...para(r'//', r'rename_all is an enum with eight case conventions. quoted is true, because serde wants a string literal: the menu inserts the quotes when they are not there. The eight values are listed from lowercase to SCREAMING-KEBAB-CASE. It applies to a container and a variant and has the same nested form as rename.'),
    blank,
    ...code('json', r'data/macro_attrs/serde.json · lines 59-82', r'''
        {
          "key": "rename_all_fields",
          "kind": "enum",
          "doc": "Rename the fields of all struct variants of this enum according to the given case convention.",
          "applies_to": [
            "container:enum"
          ],
          "values": [
            "lowercase",
            "UPPERCASE",
            "PascalCase",
            "camelCase",
            "snake_case",
            "SCREAMING_SNAKE_CASE",
            "kebab-case",
            "SCREAMING-KEBAB-CASE"
          ],
          "quoted": true,
          "since": "1.0.195",
          "nested": [
            "serialize",
            "deserialize"
          ]
        },
'''),
    ...para(r'//', r'rename_all_fields is the same set of values but applies only to container:enum, and it has since set to 1.0.195. In a project that resolves an older serde, the key is hidden; with an unknown version it is shown. The two other keys with a since in this file are expecting (1.0.133) and other (1.0.131).'),
    blank,
    ...sec(r'keys that exclude and require each other'),
    ...code('json', r'data/macro_attrs/serde.json · lines 91-130', r'''
        {
          "key": "tag",
          "kind": "string",
          "doc": "On an enum: internally tagged representation, the variant name is stored in this field. On a struct: the struct name is written as this field.",
          "applies_to": [
            "container"
          ],
          "conflicts": [
            "untagged"
          ],
          "snippet": "tag = \"${1:type}\""
        },
        {
          "key": "content",
          "kind": "string",
          "doc": "On an enum with `tag`: adjacently tagged representation, the contents go in this field.",
          "applies_to": [
            "container:enum"
          ],
          "conflicts": [
            "untagged"
          ],
          "requires": [
            "tag"
          ],
          "snippet": "content = \"${1:content}\""
        },
        {
          "key": "untagged",
          "kind": "flag",
          "doc": "Serialize and deserialize without a tag: the variants are tried in order.",
          "applies_to": [
            "container:enum",
            "variant"
          ],
          "conflicts": [
            "tag",
            "content"
          ]
        },
'''),
    ...para(r'//', r'tag, content and untagged are the three ways of choosing an enum representation. The file encodes the grammar between them. tag conflicts with untagged. content conflicts with untagged and requires tag. untagged conflicts with both. Because the menu hides a key when it, or any key already written, lists the other, writing tag = "type" removes untagged from the list. content stays visible but sorted last until tag is written. The data says it once per key, and the behaviour follows from the README’s rules, not from code written for serde.'),
    blank,
    ...sec(r'many names for one intent'),
    ...code('json', r'data/macro_attrs/serde.json · lines 131-167', r'''
        {
          "key": "default",
          "kind": "flag",
          "doc": "Use Default::default() (or the given function) for missing fields when deserializing.",
          "applies_to": [
            "container",
            "field"
          ],
          "alt": [
            {
              "label": "default = \"path\"",
              "snippet": "default = \"${1:path::to::fn}\"",
              "doc": "Call this function for missing values."
            }
          ]
        },
        {
          "key": "skip",
          "kind": "flag",
          "doc": "Skip this field or variant in both serialization and deserialization.",
          "applies_to": [
            "field",
            "variant"
          ],
          "conflicts": [
            "skip_serializing",
            "skip_deserializing",
            "skip_serializing_if",
            "serialize_with",
            "deserialize_with",
            "with",
            "rename",
            "alias",
            "flatten",
            "borrow"
          ]
        },
'''),
    ...para(r'//', r'default is a flag and has a second menu entry in alt: default = "path", with its own snippet and doc. skip lists ten keys it cannot be combined with, including rename, alias, flatten and borrow. skip_serializing and skip_deserializing each list their own set: the first conflicts with skip, serialize_with, with and skip_serializing_if, the second with skip, deserialize_with, with and alias. The file does not say where these rules come from.'),
    blank,
    ...sec(r'paths, repeatable keys and a lifetime'),
    ...code('json', r'data/macro_attrs/serde.json · lines 198-210, 223-237, 268-282', r'''
        {
          "key": "skip_serializing_if",
          "kind": "path",
          "doc": "Call a function to decide whether to skip serializing this field, e.g. Option::is_none.",
          "applies_to": [
            "field"
          ],
          "conflicts": [
            "skip",
            "skip_serializing"
          ],
          "snippet": "skip_serializing_if = \"${1:Option::is_none}\""
        },
...
        {
          "key": "with",
          "kind": "path",
          "doc": "Use a module with `serialize` and `deserialize` functions for this field or variant.",
          "applies_to": [
            "field",
            "variant"
          ],
          "conflicts": [
            "serialize_with",
            "deserialize_with",
            "skip"
          ],
          "snippet": "with = \"${1:module}\""
        },
...
        {
          "key": "alias",
          "kind": "string",
          "doc": "Accept this additional name when deserializing (may be repeated).",
          "applies_to": [
            "field",
            "variant"
          ],
          "repeatable": true,
          "conflicts": [
            "skip",
            "skip_deserializing"
          ],
          "snippet": "alias = \"${1:name}\""
        },
'''),
    ...para(r'//', r'skip_serializing_if, with and the _with keys are path kinds, which tells the completion that a path is expected after the equals sign and not a string. with conflicts with serialize_with and deserialize_with. alias is the only key marked repeatable, so after writing it once, it is still offered, whereas every other key disappears once present.'),
    blank,
    ...code('json', r'data/macro_attrs/serde.json · lines 369-387', r'''
        {
          "key": "borrow",
          "kind": "flag",
          "doc": "Borrow data for this field from the deserializer (optionally for given lifetimes).",
          "applies_to": [
            "field",
            "variant"
          ],
          "conflicts": [
            "skip"
          ],
          "alt": [
            {
              "label": "borrow = \"'a\"",
              "snippet": "borrow = \"'${1:a}\"",
              "doc": "Borrow only for these lifetimes."
            }
          ]
        },
'''),
    ...para(r'//', r'borrow is a flag with a conflict with skip and an alt entry whose label contains a lifetime. In the JSON file the quote of the lifetime sits inside an escaped string. The snippet puts the cursor in the lifetime name.'),
    blank,
    ...sec(r'the end of the file'),
    ...code('json', r'data/macro_attrs/serde.json · lines 388-435', r'''
        {
          "key": "crate",
          "kind": "path",
          "doc": "Path to the serde crate when it is renamed or re-exported.",
          "applies_to": [
            "container"
          ],
          "snippet": "crate = \"${1:serde}\""
        },
        {
          "key": "expecting",
          "kind": "string",
          "doc": "Custom text of the 'expecting ...' part of the deserialization error.",
          "applies_to": [
            "container"
          ],
          "since": "1.0.133",
          "snippet": "expecting = \"${1:message}\""
        },
        {
          "key": "other",
          "kind": "flag",
          "doc": "Deserialize unknown variants into this variant (internally/adjacently tagged enums).",
          "applies_to": [
            "variant"
          ],
          "since": "1.0.131"
        },
        {
          "key": "field_identifier",
          "kind": "flag",
          "doc": "This enum is an identifier of fields; unit variants and one newtype variant.",
          "applies_to": [
            "container:enum"
          ]
        },
        {
          "key": "variant_identifier",
          "kind": "flag",
          "doc": "This enum is an identifier of variants.",
          "applies_to": [
            "container:enum"
          ]
        }
      ]
    }
  ]
}
'''),
    ...para(r'//', r'crate, expecting, other, field_identifier and variant_identifier close the list. crate takes the path of a renamed serde. The last two are flags that apply to container:enum, with docs saying the enum is an identifier of fields or of variants. After them the arrays and the object end.'),
    blank,
    ...sec(r'how it is verified'),
    ...para(r'//', r'tests/macro-attrs_spec.lua checks this file in two places. The generic test loads every shipped schema and asserts that there are no load errors, that all ten crates (serde, clap, thiserror, tokio, strum, derive_more, sqlx, utoipa, schemars and bon) have a docs_url and a versions range, that every argument has a doc, that an enum has values, and that no key is defined twice for the same attribute, targets and derives. A specific test, serde schema has every key the task lists, names 24 keys that must exist (rename through borrow in this file’s order) and checks the file for each of them. The 30 arguments of this file are the 24 plus rename_all_fields, crate, expecting, other, field_identifier and variant_identifier.'),
    blank,
    ...para(r'//', r'A third test checks that the derive helper attributes in all schemas are declared by the real proc-macro crates, looked up where the cargo registry is available, so a schema cannot claim an attribute that the crate does not define.'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt(r'//', r'pretty-printed JSON', r'every list is one item per line (the file is 435 lines for 30 keys). It is long, and one item per line makes a diff show the keys that changed.'),
    ...pt(r'//', r'conflicts are data', r'the conflicts and requires lists are written down here, and the completion hides or sorts keys by them (README rules).'),
    ...pt(r'//', r'one sentence per doc', r'each doc is a single sentence, which the README describes as shown in the preview with the other facts.'),
    ...sec(r'history'),
    ...pt(r'//', r'b9363cd 2026-10-14', r'added with the other shipped schemas, the completion module and the README. The file has not been touched since.'),
  ],
);
