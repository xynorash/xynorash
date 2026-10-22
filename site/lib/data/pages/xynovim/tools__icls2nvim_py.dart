import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tools/icls2nvim.py',
  lines: [
    cm(r'#', '──────────────────────────────────────────'),
    cm(r'#', r'tools/icls2nvim.py'),
    cm(r'#', r'a JetBrains colour scheme in, a Lua palette out'),
    cm(r'#', r'resolved, deterministic, and no scheme file committed'),
    cm(r'#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'generates lua/island/palette.lua, the data behind the Island Dark theme'),
    kv(r'language', r'Python 3, standard library only (xml.etree)'),
    kv(r'size', r'188 lines, four commits (cf842d0, 9641d08, 0da94f4, f7b8cf0)'),
    kv(r'usage', r'python3 tools/icls2nvim.py SCHEME.icls [OUT.lua]'),
    kv(r'output', r'a table with colors, derived and attrs, every value already resolved'),
    ...sec(r'why this file exists'),
    ...para(r'#', r'The Island Dark colour scheme began as a RustRover colour scheme export. An .icls file is XML with a block of named colours and a long list of named attributes, and an attribute can inherit from another one, or from the parent scheme, or from nothing at all. The repository converts it with this script, keeps the output as data (lua/island/palette.lua, 251 lines) and has the theme code, lua/island/init.lua, build its highlights from that table (its header says only palette colours are used). The palette header names the scheme and IDE version it came from.'),
    blank,
    ...para(r'#', r'The header states a distribution fact: the committed palette was generated from the author’s own export, which is not distributed. A later commit, 0da94f4, removed tools/Dark.icls from the repository, and f7b8cf0 turned the docstring first person. The script therefore says in plain words that it needs a scheme the caller exports from their own IDE, and prints a message and exits 1 without it.'),
    blank,
    ...code('python', r'tools/icls2nvim.py · lines 1-23', r'''
#!/usr/bin/env python3
"""Convert a JetBrains .icls colour scheme into lua/island/palette.lua.

Usage:
    python3 tools/icls2nvim.py SCHEME.icls [OUT.lua]
SCHEME.icls is a scheme file you supply (an export from your own IDE); none is
committed to this repo. Without it the script prints a message and exits 1.
Default OUT.lua: lua/island/palette.lua (relative to the repo). The committed
palette was generated from my own export, which is not distributed;
you only need this script to regenerate the palette from your own export.

Stdlib only. The output is a table of fully resolved values:

    colors  name -> "#rrggbb"            (the <colors> block)
    attrs   name -> { fg, bg, bold, italic, effect, effect_color, stripe }
    derived name -> "#rrggbb"            (colours the scheme does not define,
                                          taken from other entries of it)

Resolution of an attribute, in order: its own explicit values, then its
`baseAttributes` chain (cycle-safe), then the FALLBACK key the IDE would use for
an empty entry. Entries that stay empty are dropped. The scheme's parent
(Darcula) is not available, so values only it defines are simply missing.
"""
'''),
    ...sec(r'what is in the palette'),
    ...para(r'#', r'The docstring defines the output model. colors is the colour block of the file with a name for each. attrs maps each attribute name to fg, bg, bold, italic, effect, effect_color and stripe. derived holds colours the scheme does not define, taken from other entries. The resolution order of an attribute is documented in one sentence: its own explicit values, then its base chain (guarded against cycles), then the fallback key that the IDE would use for an empty entry. Entries that stay empty are dropped.'),
    blank,
    ...para(r'#', r'The last sentence of the docstring is a statement of a limit: the parent scheme, Darcula, is not available, so values only it defines are simply missing. The script does not make up values for them.'),
    blank,
    ...sec(r'mapping IntelliJ ideas to Neovim ones'),
    ...code('python', r'tools/icls2nvim.py · lines 31-61', r'''
# IntelliJ EFFECT_TYPE -> nvim decoration. 0 (box) has no nvim equivalent.
EFFECTS = {
    "1": "underline",
    "2": "undercurl",
    "3": "strikethrough",
    "4": "underline",  # bold underline
    "5": "underdotted",  # bold dotted line
}

# Entries that are empty in the file inherit from the parent scheme in the IDE;
# with the parent unavailable, use the DEFAULT_* key the language falls back to.
FALLBACKS = {
    "ANNOTATION_NAME_ATTRIBUTES": "DEFAULT_METADATA",
    "MARKDOWN_IMAGE": "MARKDOWN_LINK_TEXT",
    "REGEXP.BRACES": "DEFAULT_BRACES",
    "REGEXP.BRACKETS": "DEFAULT_BRACKETS",
    "REGEXP.PARENTHS": "DEFAULT_PARENTHS",
    "REGEXP.ESC_CHARACTER": "DEFAULT_VALID_STRING_ESCAPE",
    "REGEXP.META": "DEFAULT_KEYWORD",
}

# Colours the scheme itself lacks (they come from the parent scheme in the IDE),
# each taken from an existing colour/attribute foreground/background of the file.
# name -> (kind, key[, field])
DERIVED = {
    # Darcula selection is not in the file; the scheme's own blue selection-like
    # tint (VCS annotation blue #2) is the closest member of its palette.
    "SELECTION_BACKGROUND": ("color", "VCS_ANNOTATIONS_COLOR_2"),
    "SELECTION_STRONG": ("color", "VCS_ANNOTATIONS_COLOR_1"),
    "BORDER": ("color", "SELECTED_INDENT_GUIDE"),
}
'''),
    ...para(r'#', r'EFFECTS maps IntelliJ’s numeric effect types to Neovim decorations: 1 underline, 2 undercurl (a wave), 3 strikethrough, and for the bold variants 4 and 5 underline and underdotted. Type 0, a box, has no Neovim equivalent and is simply absent from the table, so it produces no effect.'),
    blank,
    ...para(r'#', r'FALLBACKS lists seven attributes that are empty in the file and which the IDE would fill from the parent scheme; for those the script uses the DEFAULT_ key that the language falls back to, for example REGEXP.BRACES to DEFAULT_BRACES. DERIVED lists three colours that Darcula would provide and that the scheme lacks: SELECTION_BACKGROUND, SELECTION_STRONG and BORDER. Each is borrowed from a colour the file does have (VCS annotation colours 2 and 1, and the selected indent guide), and the comment gives the reason in one line: the scheme’s own blue selection-like tint is the closest member of its palette. These are judgement calls and they are marked as such, in a table, where they can be seen and changed.'),
    blank,
    ...sec(r'parsing'),
    ...code('python', r'tools/icls2nvim.py · lines 64-93', r'''
def hexcolor(value):
    """'da19e' -> '#0da19e'; 8 digits (RGBA) are kept as '#rrggbbaa'."""
    value = value.strip().lower()
    if len(value) < 6:
        value = value.rjust(6, "0")
    return "#" + value


def parse(path):
    root = ET.parse(path).getroot()
    colors = {o.get("name"): hexcolor(o.get("value")) for o in root.find("colors") if o.get("value")}
    raw = {}
    for o in root.find("attributes"):
        value = o.find("value")
        fields = {x.get("name"): x.get("value") for x in value} if value is not None else {}
        raw[o.get("name")] = {"base": o.get("baseAttributes"), "fields": fields}
    return root, colors, raw


def resolve(name, raw, seen=()):
    """Merge explicit fields over the base chain / fallback; None if nothing."""
    entry = raw.get(name)
    if entry is None or name in seen:
        return {}
    fields = dict(entry["fields"])
    parent = entry["base"] or (FALLBACKS.get(name) if not fields else None)
    if parent:
        for key, value in resolve(parent, raw, seen + (name,)).items():
            fields.setdefault(key, value)
    return fields
'''),
    ...para(r'#', r'hexcolor repairs a quirk of the format: colours are stored as hex without leading zeros, so da19e means 0da19e. It pads on the left to six digits; a value of eight digits (red, green, blue, alpha) is kept as it is. parse reads the colour block into a dictionary and each attribute into its explicit fields and its baseAttributes name.'),
    blank,
    ...para(r'#', r'resolve is the interesting function. It copies the attribute’s own fields, then decides which parent to follow: its base attribute if there is one, and the fallback only when the entry has no fields of its own. It then merges the parent’s result under the child’s with setdefault, so explicit values always win. A tuple of names already visited (seen) makes a cyclic chain return an empty result instead of recursing forever, which is the cycle safety the docstring promises.'),
    blank,
    ...sec(r'converting one attribute'),
    ...code('python', r'tools/icls2nvim.py · lines 96-114', r'''
def convert_attr(fields):
    out = {}
    if fields.get("FOREGROUND"):
        out["fg"] = hexcolor(fields["FOREGROUND"])
    if fields.get("BACKGROUND"):
        out["bg"] = hexcolor(fields["BACKGROUND"])
    font = int(fields.get("FONT_TYPE", 0) or 0)
    if font & 1:
        out["bold"] = True
    if font & 2:
        out["italic"] = True
    if fields.get("EFFECT_COLOR"):
        out["effect_color"] = hexcolor(fields["EFFECT_COLOR"])
    effect = EFFECTS.get(fields.get("EFFECT_TYPE", ""))
    if effect:
        out["effect"] = effect
    if fields.get("ERROR_STRIPE_COLOR"):
        out["stripe"] = hexcolor(fields["ERROR_STRIPE_COLOR"])
    return out
'''),
    ...para(r'#', r'FONT_TYPE is a bit field in IntelliJ: 1 is bold, 2 is italic, and the code tests each bit with &. Colours go through hexcolor. The error stripe colour is kept as stripe. The int() call tolerates a missing or empty FONT_TYPE by treating it as 0.'),
    blank,
    ...sec(r'emitting Lua'),
    ...code('python', r'tools/icls2nvim.py · lines 117-155', r'''
def lua_key(name):
    if name.isidentifier():
        return name
    return '["%s"]' % name.replace("\\", "\\\\").replace('"', '\\"')


def lua_value(value):
    if value is True:
        return "true"
    return '"%s"' % value


def emit(root, scheme_path, colors, attrs, derived):
    meta = {p.get("name"): (p.text or "").strip() for p in root.iter("property")}
    lines = [
        "-- GENERATED by tools/icls2nvim.py from %s. DO NOT EDIT BY HAND;" % os.path.basename(scheme_path),
        "-- regenerate with: python3 tools/icls2nvim.py YOUR_EXPORT.icls (the original export is not distributed)",
        '-- scheme "%s" (parent %s) from %s %s'
        % (
            root.get("name"),
            root.get("parent_scheme"),
            meta.get("ide", "?"),
            meta.get("ideVersion", "?"),
        ),
        "return {",
        '  name = "%s",' % root.get("name"),
        "  colors = {",
    ]
    for key in sorted(colors):
        lines.append("    %s = %s," % (lua_key(key), lua_value(colors[key])))
    lines += ["  },", "  derived = {"]
    for key in sorted(derived):
        lines.append("    %s = %s," % (lua_key(key), lua_value(derived[key])))
    lines += ["  },", "  attrs = {"]
    for key in sorted(attrs):
        body = ", ".join("%s = %s" % (k, lua_value(v)) for k, v in sorted(attrs[key].items()))
        lines.append("    %s = { %s }," % (lua_key(key), body))
    lines += ["  },", "}", ""]
    return "\n".join(lines)
'''),
    ...para(r'#', r'The emitter writes Lua by hand. A key that is a valid identifier is written bare; anything else (names in the scheme contain dots, for example) becomes a quoted bracket key with backslashes and quotes escaped. Keys are sorted everywhere, which makes the output deterministic: regenerating from the same input gives the same file, and a git diff of the palette after re-export shows only what the scheme changed. The first three lines are a header saying the file is generated, DO NOT EDIT BY HAND, how to regenerate it, and the scheme name, parent and the IDE name and version, read from the property elements of the file.'),
    blank,
    ...sec(r'main'),
    ...code('python', r'tools/icls2nvim.py · lines 158-188', r'''
def main(argv):
    if len(argv) < 2:
        print(
            "icls2nvim: no input. Pass a JetBrains .icls scheme file you exported yourself:\n"
            "    python3 tools/icls2nvim.py SCHEME.icls [OUT.lua]\n"
            "(no scheme file is committed to this repository)",
            file=sys.stderr,
        )
        return 1
    src = argv[1]
    dst = argv[2] if len(argv) > 2 else os.path.join(ROOT, "lua", "island", "palette.lua")
    root, colors, raw = parse(src)
    attrs = {}
    for name in raw:
        converted = convert_attr(resolve(name, raw))
        if converted:
            attrs[name] = converted
    derived = {}
    for name, (kind, key) in DERIVED.items():
        if kind == "color" and key in colors:
            derived[name] = colors[key]
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "w", newline="\n") as fh:
        fh.write(emit(root, src, colors, attrs, derived))
    print("%s: %d colours, %d attributes (of %d), %d derived -> %s" % (
        os.path.basename(src), len(colors), len(attrs), len(raw), len(derived), dst))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
'''),
    ...para(r'#', r'Without an argument the script explains itself on stderr and returns 1. With one it defaults the output to lua/island/palette.lua relative to the repository, creates the directory if necessary, and writes the file with LF endings (newline set in 9641d08, so Windows and Linux produce the same bytes). Derived colours are only produced if the key they are borrowed from exists. The final line reports how many colours, how many attributes (of how many in the file) and how many derived values were written.'),
    blank,
    ...sec(r'how it is tested'),
    ...para(r'#', r'tests/theme-island_spec.lua has a group for this script. Six tests cover it: no input prints a message, exits non-zero and writes nothing; a round trip, where a synthetic .icls is rebuilt from the committed palette and converted back to the same colours and attributes; the script is stdlib only (run with -I -S, without site-packages); custom input and output arguments work and create the output directory; baseAttributes chains are resolved cycle-safely with the DEFAULT_ fallbacks; and the effect types map as in EFFECTS. The round trip is a good test of a converter whose input cannot be committed: it proves the conversion is the inverse of the data it produced.'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt(r'#', r'data, not code', r'the palette is a table; the highlight logic lives in lua/island/init.lua and can be read and changed without the IDE.'),
    ...pt(r'#', r'explicit gaps', r'missing parent values are left missing, with a short list of documented fallbacks instead of guessed colours.'),
    ...pt(r'#', r'determinism', r'sorted keys, LF endings, no timestamps. The only variable text in the output is the header taken from the scheme itself.'),
    ...pt(r'#', r'one unused field', r'the DERIVED entries are tuples of (kind, key) and the code only handles the kind color; the comment mentions an optional third field that no entry uses yet.'),
    ...sec(r'history'),
    ...pt(r'#', r'cf842d0 2026-10-12', r'Theme: Island Dark from the RustRover scheme, permanent. The script and the first palette arrive together.'),
    ...pt(r'#', r'9641d08 2026-10-16', r'first full Windows and macOS runs: the output is written with LF.'),
    ...pt(r'#', r'0da94f4 2026-10-22', r'removes tools/Dark.icls, keeps only the generated palette.'),
    ...pt(r'#', r'f7b8cf0 2026-10-22', r'docstring in first person.'),
  ],
);
