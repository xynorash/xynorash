import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-macros.nvim/data/macro_attrs/serde.json',
  lines: [
    cm('//', r'──────────────────────────────────────────'),
    cm('//', r'serde.json — the format at work: one attribute, 30 arguments'),
    cm('//', r'the data behind #[serde(rename_all = "camelCase")] completion'),
    cm('//', r'──────────────────────────────────────────'),
    kv(r'role', r'the shipped schema for serde, as a representative of the ten'),
    kv(r'format', r'JSON, described in data/macro_attrs/README.md'),
    kv(r'size', r'435 lines, one attribute (serde) with 30 arguments'),
    kv(r'scope', r'versions >=1.0.0, <2.0.0; derives Serialize and Deserialize'),
    kv(r'history', r'added with the other schemas in b9854b7 (2026-10-22)'),
    ...sec(r'why this file exists'),
    ...para('//', r'serde’s helper attribute is irregular in its details: some '
        r'keys exist only on containers, some only on fields, some only on enums, some conflict, '
        r'one needs another, a few exist only since a certain release. This file records all of '
        r'that as data. The code in attrs.lua has no knowledge of serde; remove this file and serde '
        r'completion disappears, and everything else keeps working.'),
    ...sec(r'the header of the file'),
    ...code('json', r'data/macro_attrs/serde.json · lines 1-6', r'''
{
  "crate": "serde",
  "versions": ">=1.0.0, <2.0.0",
  "docs_url": "https://serde.rs/attributes.html",
  "attributes": [
    {
'''),
    ...para('//', r'The first lines scope the whole file. The crate is serde and the file applies to any 1.x '
        r'release; a workspace that depends on serde 2.0.0 would not get '
        r'these suggestions. The attribute is called serde, and its derives are Serialize and '
        r'Deserialize: the serde helper is offered only when one of those two derives is on the '
        r'item, which is how a #[serde(...)] on an item without the derive stays quiet.'),
    ...code('json', r'data/macro_attrs/serde.json · lines 7-19', r'''
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
        {
'''),
    ...para('//', r'applies_to lists the targets the attribute may be written on: container, field and '
        r'variant. A container is a struct, enum or union; the schema distinguishes '
        r'container:struct and container:enum where a key needs it.'),
    ...sec(r'a simple string key with a nested form'),
    ...code('json', r'data/macro_attrs/serde.json · lines 20-34', r'''
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
    ...para('//', r'rename is a string with a snippet that leaves the cursor in the quotes, valid on '
        r'container, field and variant, and with the nested keys serialize and deserialize, which '
        r'gives rename(serialize = "..", deserialize = "..") completion.'),
    ...sec(r'an enum with its values'),
    ...code('json', r'data/macro_attrs/serde.json · lines 36-59', r'''
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
        {
'''),
    ...para('//', r'rename_all is the model case. It is an enum whose values are the eight case conventions '
        r'serde accepts, it is quoted, so the menu inserts the quotation marks and, because the '
        r'key’s accept action retriggers the menu, the values appear immediately after the key is '
        r'accepted. It applies to the container and to variants, and takes the nested form as well.'),
    ...code('json', r'data/macro_attrs/serde.json · lines 60-82', r'''
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
    ...para('//', r'rename_all_fields shows the version gate: it applies only to container:enum and carries '
        r'since 1.0.195, so with a serde resolved at 1.0.100 it is hidden. The spec for version '
        r'gating stubs the resolved version of serde to 1.0.100 for this purpose.'),
    ...sec(r'relationships between keys: tag, content, untagged'),
    ...code('json', r'data/macro_attrs/serde.json · lines 91-131', r'''
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
        {
'''),
    ...para('//', r'Three keys describe the enum representations. tag conflicts with untagged. content '
        r'conflicts with untagged and requires tag, so it is still offered without a tag but sorted '
        r'last. untagged conflicts with both. Because conflicts is symmetric in the code, the '
        r'declarations are consistent but would work with fewer. The effect in the editor: after '
        r'writing tag the menu no longer offers untagged, and after untagged it offers neither tag '
        r'nor content.'),
    ...sec(r'alternates'),
    ...code('json', r'data/macro_attrs/serde.json · lines 132-147', r'''
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
'''),
    ...para('//', r'default is a flag that also has an alternate entry. The first menu item inserts the bare '
        r'key, and the alt adds default = "path" with its own snippet and a short explanation. This '
        r'is how a key with two forms appears twice in the menu, each with its own insertion.'),
    ...sec(r'the long conflict lists'),
    ...code('json', r'data/macro_attrs/serde.json · lines 148-168', r'''
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
        {
'''),
    ...para('//', r'skip is the longest conflict list in the file: it conflicts with skip_serializing, '
        r'skip_deserializing, skip_serializing_if, serialize_with, deserialize_with, with, rename, '
        r'alias, flatten and borrow. Declaring it makes every one of those disappear from the menu '
        r'once skip is written, and, since conflicts are symmetric in the code, makes skip '
        r'disappear once any of them is written. These lists encode judgement: whether serde would '
        r'reject a particular combination is a claim about serde that this file makes, and it is '
        r'the author’s data, not something the plugin verifies.'),
    ...code('json', r'data/macro_attrs/serde.json · lines 199-210', r'''
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
'''),
    ...para('//', r'skip_serializing_if is a path-kind key whose snippet puts the common value '
        r'Option::is_none in a placeholder; it conflicts with skip and skip_serializing, which is '
        r'what the spec’s serde field row relies on when it asserts that skip_serializing_if is '
        r'offered on a field.'),
    ...sec(r'repeatable keys'),
    ...code('json', r'data/macro_attrs/serde.json · lines 269-283', r'''
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
        {
'''),
    ...para('//', r'alias is the one repeatable key in the file. Every other key is offered once; a '
        r'repeatable one stays in the menu after it is written, because serde accepts several '
        r'aliases.'),
    ...sec(r'keys that exist since a release'),
    ...code('json', r'data/macro_attrs/serde.json · lines 398-415', r'''
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
'''),
    ...para('//', r'expecting (since 1.0.133) and other (since 1.0.131) are gated by version. The since field '
        r'is compared with the resolved version only when the version is known and valid; with no '
        r'metadata yet, the scan gives no version and everything is shown.'),
    ...sec(r'how the file is used at a cursor'),
    ...para('//', r'Putting it together with the code: the lexer says the cursor is in a key position of '
        r'#[serde(. The target classifier says whether the attribute is on a container, field or '
        r'variant, and which derives the item has. attrs.lua picks this file if the member depends '
        r'on serde within the range and a Serialize or Deserialize derive is in scope. Each '
        r'argument is then filtered by applies_to, by since, and by what is already written. What '
        r'remains becomes the menu: the snippet decides what is inserted and the doc shows what the '
        r'key means.'),
    ...sec(r'history'),
    ...pt('//', r'b9854b7', r'2026-10-22, with the other schemas.'),
  ],
);
