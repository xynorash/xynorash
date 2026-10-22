import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/stylua.toml',
  lines: [
    cm(r'#', '──────────────────────────────────────────'),
    cm(r'#', r'stylua.toml'),
    cm(r'#', r'the Lua formatter settings'),
    cm(r'#', r'two spaces and 120 columns'),
    cm(r'#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'configuration for stylua, the Lua formatter'),
    kv(r'language', r'TOML'),
    kv(r'size', r'3 lines, one commit'),
    kv(r'origin', r'the first commit of the LazyVim-based config, eabb22a (2026-09-02)'),
    ...sec(r'the whole file'),
    ...code('toml', r'stylua.toml · lines 1-3', r'''
indent_type = "Spaces"
indent_width = 2
column_width = 120
'''),
    ...sec(r'what each setting does'),
    ...pt(r'#', r'indent_type = "Spaces"', r'stylua’s documented default is tabs (not stated in this repository); this pins spaces, which most Lua files in the repository use (a few, such as lua/plugins/disable-news-alert.lua and plugin/after/transparency.lua, contain tab-indented lines).'),
    ...pt(r'#', r'indent_width = 2', r'two spaces per level.'),
    ...pt(r'#', r'column_width = 120', r'stylua’s documented default is 120 as well (not stated in this repository), so writing it down only makes the limit explicit. Lines in the repository are long on purpose in places: provision.lua has a one-line table of thirteen Mason package names that is far wider than 120 columns.'),
    ...sec(r'how it is used'),
    ...para(r'#', r'stylua is one of the Mason packages that scripts/provision.lua installs (the TOOLS table has stylua in it). stylua looks for a stylua.toml in the directory tree above the file it formats, so a file in the repository root applies to the whole checkout (that is stylua’s documented behaviour, not something this repository states). docs/DETAILS.md notes that stylua --check is not clean: Mason’s stylua reported drift in 61 files under lua/ and tests/ when that sentence was written, and nothing was reformatted to keep the diff reviewable.'),
    blank,
    ...sec(r'what the formatter is applied to'),
    ...para(r'#', r'The repository tracks 115 Lua files, in lua/, colors/, plugin/, after/, tests/ and scripts/. Most of them use two spaces and double-quoted strings. The line lengths show that 120 is the formatter’s limit and not a hard rule of the code. A count of the tracked files under lua/ finds 163 lines over 120 bytes, which is possible because stylua cannot break a long string or a comment, and because some lines hold a list of data. provision.lua is a good example: the table of Mason package names is a single line of thirteen strings.'),
    blank,
    ...sec(r'the options that are not set'),
    ...para(r'#', r'Three keys are set and the rest are left to stylua’s defaults. Quote style is stylua’s automatic mode, which prefers double quotes and switches to single ones only when that saves escapes; call parentheses are always written; line endings are Unix, which matches the repository’s .gitattributes rule. The three set keys are the ones whose defaults (tabs, four columns) would produce a visibly different file from the one the repository uses. These defaults come from stylua’s own documentation, not from anything the repository states.'),
    blank,
    ...sec(r'history'),
    ...pt(r'#', r'eabb22a 2026-09-02', r'added in the migration to a LazyVim-based configuration. It is unchanged since: one commit in its history.'),
  ],
);
