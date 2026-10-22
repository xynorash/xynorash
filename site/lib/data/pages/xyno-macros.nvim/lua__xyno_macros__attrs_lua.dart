import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-macros.nvim/lua/xyno_macros/attrs.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'attrs.lua — completion inside #[serde(...)], driven by data'),
    cm('--', r'a lexer for unfinished text, a repaired parse, schemas gated by version and scope'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'blink.cmp source for helper-attribute arguments and #[derive(...)]'),
    kv(r'language', r'Lua (Neovim 0.12+), tree-sitter rust, cargo metadata'),
    kv(r'size', r'1,846 lines, the largest file of the repository after tools.lua'),
    kv(r'data', r'data/macro_attrs/*.json (ten crates), plus .xyno-macros/attrs/*.json in a project'),
    kv(r'history', r'b9854b7 (2026-10-22); in xynovim lua/config/macro_attrs.lua since b9363cd (2026-10-14)'),
    ...sec(r'why this file exists'),
    ...para('--', r'Type #[serde( in Rust and rust-analyzer offers nothing: the arguments of a helper '
        r'attribute belong to a proc macro, and the language server cannot see inside them. So the '
        r'keys (rename_all, skip_serializing_if) and the enumerated values (camelCase, '
        r'SCREAMING_SNAKE_CASE) are typed from memory, and a misspelling is discovered at compile '
        r'time. This module answers the question rust-analyzer does not: at this cursor, inside '
        r'this attribute, on this item, in this project, which keys and values are valid? The '
        r'header of the file states the problem and then, unusually, the algorithm in four numbered '
        r'steps.'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 1-27', r'''
-- Completion INSIDE the arguments of helper attributes (#[serde(...)], #[arg(...)],
-- #[command(...)], #[error(...)], #[tokio::main(...)], ...) and of #[derive(...)],
-- as a blink.cmp source driven by data.
-- rust-analyzer returns nothing there, so keys, enumerated values and derive names
-- were typed from memory.
--
-- Data: data/macro_attrs/<crate>.json (format in data/macro_attrs/README.md),
-- overridden per attribute by <workspace>/.xyno-macros/attrs/*.json.
--
-- How a request is answered (items(), the pure core the specs drive):
--   1. A small lexer reads the attribute from its `#[` to the cursor (strings,
--      nesting, `key = value` entries) and says: which attribute path, which key or
--      value is being typed, which keys are already there. Nothing is parsed with
--      treesitter here: the attribute is unfinished by definition.
--   2. The buffer is parsed with the attribute REPAIRED (closing quote and brackets
--      appended) so treesitter can say what it is attached to (container struct or
--      enum, field, variant, fn, fn parameter) and which derives that item has.
--   3. Only schemas of crates that are dependencies are used (cargo metadata once it
--      is cached, a scan of Cargo.toml until then; never blocks), version-gated, and
--      only when the helper is in scope (a derive providing it is on the item, or the
--      attribute macro is named in full or imported).
--   4. Attributes of dependency crates WITHOUT a schema: keys the workspace and the
--      crate's own sources already write inside that attribute, by frequency.
-- #[derive( completes the builtin derives plus the derive macros found in the
-- dependencies' proc-macro sources (#[proc_macro_derive(Name, attributes(...))]);
-- accepting one that is not imported calls M.on_derive_accepted(name, info).
local M = {}
'''),
    ...para('--', r'Read the four steps as four constraints. The attribute is unfinished by definition, so it '
        r'cannot be parsed with tree-sitter alone; a small lexer reads it. The item it belongs to '
        r'does need a real parse, so the buffer is repaired first. Only crates that are actually '
        r'dependencies, in a version range that fits, and with the helper really in scope, '
        r'contribute. And where there is no schema, the module learns from how the keys are used in '
        r'the project and in the dependency’s own sources.'),
    ...sec(r'origin'),
    ...para('--', r'The module began as lua/config/macro_attrs.lua in xynovim, added on 2026-10-14 in '
        r'b9363cd, a large commit titled Macros and dependencies, which also brought dependency '
        r'freshness, crate add, a missing-feature fix, the macro tools and the import engine. A '
        r'review-fix commit followed on 2026-10-15 (19f974c), and 6524272 on 2026-10-21 added .exe '
        r'suffixes and drive-letter case handling for Windows. The extraction on 2026-10-22 renamed '
        r'the namespace and the project override directory (to .xyno-macros/attrs), read the '
        r'shipped schemas from the plugin directory, and turned the helper modules into the '
        r'xyno_rust and xyno_imports plugins.'),
    ...sec(r'tuning values in one table'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 34-47', r'''
M.config = {
  shipped_glob = plugin_root .. "/data/macro_attrs/*.json",
  user_dir = ".xyno-macros/attrs", -- under the workspace root
  context_lines = 15, -- how far above the cursor an attribute may start
  window_min = 1500, -- files longer than this are parsed around the cursor only
  window_lines = 300,
  learn_ttl = 120, -- seconds a learn-from-usage scan stays cached
  learn_max_files = 300, -- per scanned directory tree
  learn_max_bytes = 2 * 1024 * 1024,
  derive_max_files = 80, -- per proc-macro crate
  derive_max_bytes = 2 * 1024 * 1024,
  import_attempts = 10, -- rust-analyzer needs a moment to know the new name
  import_interval = 500,
}
'''),
    ...para('--', r'Every limit of the module is a named number here, and setup lets the user override them: '
        r'how many lines above the cursor an attribute may start, when a file is long enough to be '
        r'parsed only around the cursor, how long a learn-from-usage scan is cached, how many files '
        r'and bytes each scan may read, and how many times, and how often, to retry an import. Everything '
        r'that could be slow has a bound, and the bound has a name. load_errors collects problems found while loading schemas, so a '
        r'broken JSON file is reported by :MacroAttrs and not by an error in the middle of typing.'),
    ...sec(r'reading files safely'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 57-60,66-68', r'''
local function read_file(path, max)
  local st = vim.uv.fs_stat(path)
  if not st or st.type ~= "file" or st.size > (max or 2 * 1024 * 1024) then
    return nil
...
  local s = f:read("*a")
  f:close()
  return s
'''),
    ...para('--', r'read_file refuses anything that is not a regular file or is larger than the limit (2 MB '
        r'by default). The comment gives the reason: the files read here belong to the project or '
        r'to a dependency, and a FIFO or a link to /dev/zero must not be able to block the editor. '
        r'This is the kind of defensive code that only exists because a module reads files it did '
        r'not write.'),
    ...sec(r'version requirements without a semver library'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 90-99', r'''
--- Does `version` satisfy a cargo-style requirement (">=1.0.0, <2", "^1.2", "~1.2",
--- "1", "=1.2.3", "*")? Unknown or unparsable input is satisfied (never hide a
--- schema because of data we cannot read).
function M.satisfies(version, range)
  if not version or not range or range == "" or range == "*" then
    return true
  end
  if not cm.valid_version(version) then
    return true
  end
'''),
    ...para('--', r'satisfies answers whether a resolved version fits a cargo-style requirement such as '
        r'>=1.0.0, <2, ^1.2, ~1.2, 1 or *. The rule in its doc comment is the important one: '
        r'unknown or unparsable input is satisfied. The module would rather offer a completion that '
        r'might be stale than hide a schema because it could not read a version. The parsing is '
        r'partial-version aware (a bare 1 means a range), the caret case computes the upper bound '
        r'by cargo’s rules (the first non-zero component is the one that may not change), and the '
        r'tilde case pins the minor version when it is given.'),
    ...para('--', r'The comparison operators and the exact form are straightforward, with one subtlety in the '
        r'equals branch: a partial version pins only the parts it names. The spec has a table of '
        r'ranges and versions for this function.'),
    ...sec(r'schemas, validated softly'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 173-181,196-209', r'''
local function check_schema(file, source)
  local errs = {}
  local function bad(msg)
    errs[#errs + 1] = ("%s: %s"):format(source, msg)
  end
  if type(file) ~= "table" or type(file.crate) ~= "string" or not cm.valid_name(file.crate) then
    bad("`crate` must be a crate name")
    return nil, errs
  end
...
        elseif not KINDS[arg.kind or "flag"] then
          bad(("%s.%s: unknown kind %s"):format(a.name, arg.key, tostring(arg.kind)))
        else
          arg.kind = arg.kind or "flag"
          lists(arg)
          args[#args + 1] = arg
        end
      end
      a.args = args
      attrs[#attrs + 1] = a
    end
  end
  file.attributes = attrs
  return file, errs
'''),
    ...para('--', r'A schema file is data from a person, so it is checked. check_schema returns the file and '
        r'a list of problems, drops what is unusable (an attribute without a name, an argument '
        r'without a key or with an unknown kind) and keeps the rest. A field that should be a list '
        r'may be given as a single value, and lists() quietly wraps it. load_json refuses files '
        r'over 1 MB and reports invalid JSON with the first line of the decoder’s message. The '
        r'effect is that a typo in one argument of a hand-written schema removes that argument and '
        r'shows a problem in :MacroAttrs, but the other arguments still complete.'),
    ...sec(r'shipped schemas and project overrides'),
    ...para('--', r'The shipped schemas are read once from data/macro_attrs, keyed by crate, with the README '
        r'skipped by a name match. The first file for a crate wins.'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 255-258,279-281,294-310', r'''
--- Shipped schemas with the workspace's .xyno-macros/attrs/*.json applied: a user
--- attribute replaces every shipped attribute of the same crate and name; a user file
--- for another crate is added. Cached until a file's mtime changes.
function M.schemas(root)
...
  for crate, file in pairs(base) do
    set[crate] = vim.tbl_extend("force", {}, file, { attributes = vim.list_slice(file.attributes) })
  end
...
    if file then
      local target = set[file.crate]
      if not target then
        set[file.crate] = file
      else
        local names = {}
        for _, a in ipairs(file.attributes) do
          names[a.name] = true
        end
        local kept = vim.tbl_filter(function(a)
          return not names[a.name]
        end, target.attributes)
        vim.list_extend(kept, file.attributes)
        target.attributes = kept
        target.docs_url = file.docs_url or target.docs_url
        target.versions = file.versions or target.versions
      end
'''),
    ...para('--', r'A project can override or extend with .xyno-macros/attrs/*.json in the workspace root. '
        r'The merge rule is precise and documented in the data README: for a crate that already has '
        r'a shipped schema, each attribute in the project file replaces every shipped attribute of '
        r'the same name, while the other shipped attributes stay; for another crate the file is '
        r'added as it is. The result is cached by a stamp made from the files and their '
        r'modification times, so editing a file takes effect on the next completion, and the '
        r'shipped tables are copied before they are changed so that the shared cache is never '
        r'mutated.'),
    ...sec(r'the lexer for unfinished text'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 321-333', r'''
local function new_state(inner)
  return {
    inner = inner,
    phase = "path", -- path | args | after
    path = "",
    frames = {},
    bstack = inner and { "]", ")" } or { "]" },
    closed = false,
    pending = nil, -- identifier being read (not yet a token)
    str = nil, -- { buf = "", entry = entry|nil, frame = frame|nil }
    comment = nil,
  }
end
'''),
    ...para('--', r'A completion request always happens in the middle of a token. The lexer therefore keeps '
        r'an explicit state: a phase (path, args, after), the attribute path read so far, a stack '
        r'of frames for nested parentheses, a stack of expected closers, a pending identifier that '
        r'is not yet a token, a string being read and whether it is in a comment. Each frame '
        r'records the keys already seen, which is what lets the module say a key is already written '
        r'and must not be offered again.'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 353-368,389-405', r'''
local function token(st, kind, text, off)
  if st.phase == "path" then
    if kind == "ident" then
      st.path = st.path .. text
    elseif text == "::" then
      st.path = st.path .. "::"
    elseif text == "(" then
      st.phase = "args"
      push_frame(st, st.path)
    elseif text == "=" then
      st.phase = "after"
    elseif text == ")" and st.inner then
      st.phase = "after"
    end
    return
  end
...
  if not e then
    if kind == "ident" then
      f.entry = { key = text, state = "key", depth = 0, vtokens = 0 }
    elseif text == ")" then
      table.remove(st.frames)
      if #st.frames == 0 then
        st.phase = "after"
      end
    elseif text == "," then
      -- empty entry
    elseif text == "(" or text == "[" or text == "{" then
      f.entry = { key = "", state = "value", depth = 1, vtokens = 1 }
    else
      f.entry = { key = "", state = "value", depth = 0, vtokens = 1 }
    end
    return
  end
'''),
    ...para('--', r'token consumes one token and updates the state machine. The shape of the branches is the '
        r'grammar of an attribute argument list: at the start of an entry an identifier begins a '
        r'key; after a key an equals sign starts a value, an open parenthesis starts a nested frame '
        r'(rename(serialize = "x")), a comma ends the entry; inside a value, brackets deepen and '
        r'close, and a comma at depth zero ends the entry. Strings are handled before everything '
        r'else because a comma in a string is not a separator. One branch handles cfg_attr, where '
        r'the first comma separates the condition from the real attribute.'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 556-571', r'''
  local f = st.frames[#st.frames]
  local e = f.entry
  local ctx = {
    path = st.frames[1].key,
    keys = {}, -- attribute path, then the keys of the nested frames
    seen = f.seen,
    seen_last = f.seen_last or {},
    in_string = false,
    first_comma = st.frames[1].first_comma,
    base = st.frames[1],
  }
  for _, fr in ipairs(st.frames) do
    ctx.keys[#ctx.keys + 1] = fr.key
  end
  ctx.nested = #st.frames > 1 and st.frames[#st.frames].key or nil
  ctx.entries = vim.tbl_count(f.seen) + (e and 1 or 0)
'''),
    ...para('--', r'snapshot is the answer the lexer gives at the cursor: either the attribute path being '
        r'typed, or a context of mode key or value, the attribute, the keys seen, the nested key if '
        r'any, the prefix typed so far and whether the cursor is inside a string. It returns nil '
        r'for situations in which completing makes no sense, for example the middle of a value that '
        r'already has tokens.'),
    ...sec(r'finding the attribute under the cursor'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 619-631', r'''
  run(st, text, cur + 1, line_end(row))
  while not st.closed and last < #lines and last - row < 20 do
    local nxt = lines[last + 1]
    local cont = nxt:match("^%s*[%a_][%w_:]*%s*[=,()%]]")
      or nxt:match('^%s*"')
      or nxt:match("^%s*%)")
      or nxt:match("^%s*%]")
    if not cont or nxt:match("^%s*[%a_][%w_]*%s+[%a_]") then
      break
    end
    run(st, text, offs[last + 1] - 0, line_end(last + 1)) -- the newline itself is not needed
    last = last + 1
  end
'''),
    ...para('--', r'lex_attr lexes from the attribute’s start to the cursor, then keeps going forward over '
        r'the rest of the cursor’s line and over following lines that still read like attribute '
        r'arguments. The continuation test is a pair of patterns, and the loop is bounded to twenty '
        r'extra lines. Reading forward matters for one reason: the lexer must know whether the '
        r'attribute is already closed, to decide how to repair the text for tree-sitter.'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 668-681', r'''
        if ctx.path == "cfg_attr" then
          if not ctx.first_comma then
            return nil
          end
          local ictx, ist, iclosed, iend = lex_attr(text, lines, offs, ctx.first_comma + 1, cur, row, true)
          if not ictx then
            return nil
          end
          ctx, st, closed, end_off = ictx, ist, iclosed, iend
          res.ctx = ictx
        end
        res.closed = closed
        res.end_off = end_off
        res.closers = (st.str and '"' or "") .. table.concat(vim.fn.reverse(vim.deepcopy(st.bstack)))
'''),
    ...para('--', r'attribute_at searches backwards from the cursor line for the opening #[ or #![, up to '
        r'context_lines lines, and tries at most four candidates. The cfg_attr case deserves '
        r'attention: after the first comma of cfg_attr(cond, derive(...)) the text is a new '
        r'attribute, so the lexer runs again from there with the inner flag. The result carries the '
        r'closers that would complete the text, a string quote and the pending brackets in reverse '
        r'order.'),
    ...sec(r'dependencies, never blocking'),
    ...para('--', r'manifest_deps is a hand-rolled reader of the dependency sections of a Cargo.toml. It '
        r'understands the table forms [dependencies], [dev-dependencies], [dependencies.name] and '
        r'the package renaming key, and it skips keys such as version and features that are not '
        r'dependency names. It exists because the real source of truth, cargo metadata, takes time.'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 794-796,809-812', r'''
  local hit = metas[root]
  if hit and hit.stamp == meta_stamp(root, hit.meta) then
    local meta = hit.meta
...
  if not inflight[root] and (not failed[root] or os.time() - failed[root] > 60) then
    inflight[root] = true
    M.refresh_dependencies(root)
  end
'''),
    ...para('--', r'dependencies returns what is known at once. If cargo metadata is cached and its stamp '
        r'(the modification times of the manifests and the lockfile) still matches, it returns the '
        r'resolved dependencies of the member that owns the file, with versions and directories. '
        r'Otherwise it starts a metadata run in the background, at most once per minute after a '
        r'failure, and answers immediately from a scan of the manifests, with no versions. The doc '
        r'comment says it plainly: never blocks. The cost is that the first completion after '
        r'opening a project works from less information (no version gating); the :MacroAttrs '
        r'command shows whether the answer came from metadata or from a scan.'),
    ...sec(r'finding derive macros in dependency sources'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 870-873,880-890', r'''
  local is_proc = manifest:match("proc%-macro%s*=%s*true") or manifest:match("proc_macro%s*=%s*true")
  if is_proc then
    local files, bytes = 0, 0
    for name, kind in vim.fs.dir(dir .. "/src", { depth = 3 }) do
...
            local s, e, nm = text:find("proc_macro_derive%s*%(%s*([%a_][%w_]*)", from)
            if not s then
              break
            end
            local open = text:find("(", s, true)
            local inside = balanced(text, open) or ""
            local helpers = {}
            local attrs = inside:match("attributes%s*%((.-)%)")
            for h in (attrs or ""):gmatch("[%a_][%w_]*") do
              helpers[#helpers + 1] = h
            end
'''),
    ...para('--', r'To complete #[derive( with macros that are not in std, the module reads the sources of '
        r'proc-macro crates. proc_macro_derives checks the manifest for proc-macro = true, then '
        r'scans src/ for #[proc_macro_derive(Name, attributes(...))], reading the helper attribute '
        r'names from the balanced parentheses. The scan is bounded by file count and bytes and '
        r'memoized per directory.'),
    ...para('--', r'derive_catalog joins this across all dependencies: for each, the crate’s own directory '
        r'plus the proc-macro crates its manifest depends on, producing a sorted list of name, crate, helper attributes and path. Memoization '
        r'key includes whether metadata or a scan produced the dependency list.'),
    ...sec(r'what an attribute is attached to'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 1028-1048', r'''
  local parent = skip_error(node:parent())
  local ptype = parent and parent:type()
  local item, kind
  if ptype == "field_declaration_list" or ptype == "ordered_field_declaration_list" then
    kind = "field"
    item = skip_error(parent:parent())
    if item and item:type() == "enum_variant" then
      item = skip_error(skip_error(item:parent()):parent())
    end
  elseif ptype == "enum_variant_list" then
    kind = "variant"
    item = skip_error(parent:parent())
  elseif ptype == "parameters" then
    kind = "param"
    item = skip_error(parent:parent())
  else
    local sib = node:next_named_sibling()
    while sib and SKIP_SIBLINGS[sib:type()] do
      sib = sib:next_named_sibling()
    end
    item = sib
'''),
    ...para('--', r'target_of parses the repaired text with a string parser and finds the attribute node at '
        r'the cursor, then looks at its parent to classify it: a field of a struct or enum variant, '
        r'an enum variant, a function parameter, or a sibling item, which is a container (struct, '
        r'union, enum), a function, or something else. It also collects the item’s derives and its '
        r'other attribute paths. A parse failure returns an empty table, which downstream code '
        r'reads as unknown and treats as permission: derive_ok says not to hide anything when the '
        r'target could not be placed.'),
    ...sec(r'is the helper really in scope'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 1128-1147', r'''
local function derive_ok(crate, names, target, uses)
  if not target.kind then
    return true -- treesitter could not place the attribute: do not hide anything
  end
  for _, d in ipairs(target.derives) do
    if vim.tbl_contains(names, d.name) then
      if d.qual then
        if norm(d.qual:match("^%s*:?:?([%w_]+)") or "") == crate then
          return true
        end
      else
        local from = imported_from(uses, d.name)
        if next(from) == nil or from[crate] then
          return true
        end
      end
    end
  end
  return false
end
'''),
    ...para('--', r'These helpers answer the question that makes the completion trustworthy. A helper '
        r'attribute like serde is only valid when a derive that brings it is on the item. derive_ok '
        r'checks the item’s derives against the schema’s list, and handles qualification: a '
        r'qualified path such as serde::Serialize must name the schema’s crate; an unqualified '
        r'derive is accepted if it is imported from that crate, or if no import is found at all. '
        r'That is how Error from thiserror and Error from derive_more are told apart. path_matches '
        r'handles attribute macros: written in full, or by last segment when imported (use '
        r'tokio::main).'),
    ...sec(r'building the menu items'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 1185-1200', r'''
local function snippet_for(arg)
  if arg.snippet then
    return arg.snippet
  end
  local k = arg.kind
  if k == "flag" or k == "bool" then
    return arg.key
  elseif k == "string" then
    return arg.key .. ' = "$1"'
  elseif k == "enum" then
    if arg.quoted then
      return arg.key .. ' = "$1"'
    end
    return arg.key .. " = $1"
  elseif k == "int" then
    return arg.key .. " = ${1:0}"
'''),
    ...para('--', r'Each argument becomes a snippet. The default follows the kind: a flag inserts the bare '
        r'key, a string inserts key = "$1", an unquoted enum inserts key = $1, an integer defaults '
        r'to 0, a path or ident gets a path placeholder, anything else an expression placeholder. A '
        r'schema can override this with its own snippet. The detail column shows the crate and a '
        r'short hint of the shape.'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 1257-1286', r'''
local function arg_allowed(arg, target, version, uses, file)
  if not applies(arg.applies_to, target) then
    return false
  end
  if arg.since and version and cm.valid_version(version) and cm.compare_versions(version, arg.since) < 0 then
    return false
  end
  if arg.derives and target.kind and target.kind ~= "param" and #target.derives > 0 then
    if not derive_ok(norm(file.crate), arg.derives, target, uses) then
      return false
    end
  end
  return true
end

local function conflicts_with_seen(arg, attr, seen)
  if seen[arg.key] and not arg.repeatable then
    return true
  end
  for _, c in ipairs(arg.conflicts or {}) do
    if seen[c] then
      return true
    end
  end
  for _, other in ipairs(attr.args) do
    if seen[other.key] and other.conflicts and vim.tbl_contains(other.conflicts, arg.key) then
      return true
    end
  end
  return false
'''),
    ...para('--', r'key_item builds the LSP item. The sort text puts positional entries first, normal keys in '
        r'the middle and keys whose requires are not yet satisfied last, with the schema order kept '
        r'inside each group. The data field tells the source what to do on accept: a quoted enum '
        r'key sets retrigger, so the menu opens again inside the quotes to offer the values. '
        r'arg_allowed filters by target, by since against the resolved version, and by the derives '
        r'of the argument itself, which is how sqlx’s FromRow keys and Type keys are told apart. '
        r'conflicts_with_seen removes a key already written (unless repeatable), keys that the '
        r'written ones list as conflicts, and keys that list the written ones; so the conflict is '
        r'symmetric even if only one side declares it.'),
    ...sec(r'the schema engine'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 1292-1316', r'''
  for crate, file in pairs(schemas) do
    local dep = deps.by_name[norm(crate)]
    if dep and M.satisfies(dep.version, file.versions) then
      for _, attr in ipairs(file.attributes) do
        if path_matches(attr.name, path, uses) and applies(attr.applies_to, target) then
          local scope = true
          if attr.derives then
            scope = derive_ok(norm(crate), attr.derives, target, uses)
          end
          if scope and attr.needs_attr then
            scope = false
            for _, p in ipairs(target.attrs or {}) do
              scope = scope or vim.tbl_contains(attr.needs_attr, p)
            end
          end
          if scope and target.kind == "param" and not attr.needs_attr then
            scope = false
          end
          if scope then
            matched[#matched + 1] = { attr = attr, file = file, dep = dep }
          end
        end
      end
    end
  end
'''),
    ...para('--', r'schema_items first selects the schemas that apply: a dependency must exist for the crate, '
        r'the version must satisfy the file’s range, and each attribute must match the path, the '
        r'target, the derive scope, an optional needs_attr check (bon’s builder attributes on a '
        r'function parameter require the function to carry a builder attribute), and parameters are '
        r'refused unless the schema opts in. Then, in key mode, nested keys come from the parent '
        r'argument’s nested list (rename(serialize, deserialize)); otherwise every allowed argument '
        r'becomes an item, with its alternates (default = "path") as additional entries, '
        r'deduplicated by key across the matched attributes.'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 1370-1380', r'''
          local values = def.values
          if def.kind == "bool" then
            values = { "true", "false" }
          end
          for i, v in ipairs(values or {}) do
            local value = type(v) == "table" and v.value or v
            local vdoc = type(v) == "table" and v.doc or nil
            local text = value
            if def.quoted and not ctx.in_string then
              text = '"' .. value .. '"'
            end
'''),
    ...para('--', r'In value mode the item list is the enumerated values: a bool becomes true and false; an '
        r'enum yields its values with their docs; and a quoted enum adds the quotes unless the '
        r'cursor is already inside a string. The function returns the items and whether any schema '
        r'matched, which decides whether the learn-from-usage fallback runs.'),
    ...sec(r'learning from usage'),
    ...para('--', r'scan_files walks a directory to depth six, skipping target, .git, node_modules and '
        r'.cargo, collecting files of the wanted extensions under size and count limits. Files over '
        r'400 KB are skipped.'),
    ...para('--', r'body_keys reads the top-level keys of an attribute body with a character loop that tracks '
        r'depth and strings.'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 1515-1519', r'''
  table.sort(list, function(a, b)
    local sa, sb = a.ws * 2 + a.dep, b.ws * 2 + b.dep
    return sa == sb and a.key < b.key or sa > sb
  end)
  learned[key] = { at = os.time(), list = list }
'''),
    ...para('--', r'learn counts how often each key appears inside #[path(...)] in the workspace members and '
        r'in the dependency’s sources (Rust files and markdown, so documentation examples count), '
        r'and sorts by a score of twice the workspace count plus the dependency count: the '
        r'project’s own habits weigh double. The result is cached for learn_ttl seconds.'),
    ...para('--', r'learn_items finds which dependency owns the attribute (a path-qualified attribute macro, '
        r'or the derive helper whose derive is in scope), runs the scan and turns the list into '
        r'plain items marked as learned. A key that is the prefix being typed and seen only once is '
        r'hidden, since it is probably the very text the user is typing.'),
    ...sec(r'derives'),
    ...para('--', r'derive_items offers the nine standard derives unless a qualifier was typed, and then the '
        r'catalog entries, filtered by the qualifier. Names already written are skipped by their '
        r'last segment. The documentation of each lists its helper attributes. The sort text ranks '
        r'external derive macros before the standard ones.'),
    ...sec(r'the main entry point'),
    ...para('--', r'Long files are not parsed whole. window takes a slice of up to 300 lines on each side of '
        r'the cursor and moves the edges to item boundaries (a line starting with a closing brace '
        r'in column zero), so that tree-sitter sees complete items.'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 1655-1675', r'''
  if not at.closed then
    text = text:sub(1, at.end_off) .. at.closers .. text:sub(at.end_off + 1)
  end
  local target = M.target_of(text, at.attr_row - 1, at.attr_col)
  info.target = target
  local uses = use_statements(import_text and (import_text .. "\n" .. text) or text)

  if path == "derive" and #ctx.keys == 1 then
    return derive_items(ctx, target, deps, uses), info
  end
  if #ctx.keys > 2 or not root then
    return {}, info
  end
  local schemas = M.schemas(root)
  local items, matched = schema_items(ctx, target, deps, schemas, uses, path)
  info.matched = matched
  if not matched and ctx.mode == "key" and not ctx.nested then
    items = learn_items(ctx, target, deps, M.derive_catalog(deps), uses, path, root)
    info.learned = #items > 0
  end
  return items, info
'''),
    ...para('--', r'items is the pure core that the specs drive. Short files are used as they are; long ones '
        r'are windowed and the first 400 lines are prepended for imports. The attribute is located; '
        r'the text is repaired by inserting the closers at the end offset; the target is computed; '
        r'use statements are collected. A derive path with one key goes straight to derive_items. '
        r'A context whose ctx.keys has more than two entries, or a file outside a Cargo workspace, returns nothing. '
        r'Otherwise the schema engine runs, and only if no schema matched, in key mode and not '
        r'nested, does the learn fallback run. The second return value is a table of the context '
        r'for :MacroAttrs and the specs. One nit: the doc comment that describes items (lines 1612 '
        r'and 1613) sits above the comment of window and not above items itself.'),
    ...sec(r'the blink source'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 1728-1734', r'''
function Source:get_completions(ctx, callback)
  local ok, items = pcall(M.items, ctx.bufnr, ctx.cursor[1], ctx.cursor[2])
  callback({
    items = ok and items or {},
    is_incomplete_forward = true, -- the answer depends on the keys already written
    is_incomplete_backward = true,
  })
'''),
    ...para('--', r'The source is tiny because the work is in items. enabled checks the filetype. '
        r'get_completions wraps the call in pcall, so an error in the module yields an empty menu '
        r'instead of an error in the middle of typing, and sets both incomplete flags, because the '
        r'right answer depends on what has already been written.'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 1711-1721', r'''
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local path = vim.api.nvim_get_current_line():sub(1, col):match("#!?%[%s*([%w_:]+)%s*%(")
    if path and (path == "derive" or known_paths()[path]) then
      local chars = { "(", ",", " ", '"', "=", ":" }
      -- an auto-pair types `()` and blink only sees the LAST character typed: the `)`.
      -- Between the two, that closing paren has to be the trigger.
      local line = vim.api.nvim_get_current_line()
      if line:sub(col, col) == "(" and line:sub(col + 1, col + 1) == ")" then
        chars[#chars + 1] = ")"
      end
      return chars
'''),
    ...para('--', r'get_trigger_characters returns trigger characters only when the cursor line is inside a '
        r'known attribute. The comment records a measurement made in a real terminal: without a '
        r'rule for the closing parenthesis, typing #[serde( opened no menu, because an auto-pair '
        r'plugin inserts the pair and blink only sees the last character typed.'),
    ...sec(r'accepting a derive'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 1758-1771', r'''
      cb = function(res)
        local pick = res.choice
        if not pick then
          local mine = vim.tbl_filter(function(c)
            return (info.path and c.path == info.path) or (info.crate and c.crate == info.crate:gsub("%-", "_"))
          end, res.candidates)
          pick = #mine == 1 and mine[1] or nil
        end
        if pick then
          return engine.apply_candidate(info.bufnr, pick, function(done, err)
            if not done then
              vim.notify("macro_attrs: importing " .. name .. " failed: " .. tostring(err), vim.log.levels.WARN)
            end
          end)
'''),
    ...para('--', r'When the user accepts a derive that is not imported, on_derive_accepted asks the import '
        r'engine from xyno-imports.nvim to resolve the name. It applies the remembered choice if '
        r'there is one, otherwise the single candidate that comes from the derive’s own crate, and '
        r'otherwise tells the user how many candidates there are and which command to run. Because '
        r'rust-analyzer needs a moment to know the new name, it retries up to import_attempts times '
        r'at import_interval milliseconds. The function is a hook on M, so a user can replace it.'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 1786-1795', r'''
function Source:execute(ctx, item, callback, default_implementation)
  default_implementation(ctx, item)
  local data = item.data or {}
  if data.retrigger then
    vim.schedule(function()
      pcall(function()
        require("blink.cmp").show()
      end)
    end)
  end
'''),
    ...para('--', r'execute runs blink’s default implementation first, then re-triggers the menu if the item '
        r'asked for it (the value menu inside quotes), then, thirty milliseconds later, checks '
        r'whether a non-builtin, non-qualified derive is in scope by reading the buffer’s use '
        r'statements, and calls the hook if not.'),
    ...sec(r'the debugging command'),
    ...code('lua', r'lua/xyno_macros/attrs.lua · lines 1824-1830', r'''
  vim.api.nvim_create_user_command("MacroAttrs", function()
    local pos = vim.api.nvim_win_get_cursor(0)
    local items, info = M.items(0, pos[1], pos[2])
    local ctx = info.ctx or {}
    local lines = {
      ("attribute: %s  mode: %s  key: %s  prefix: %q"):format(ctx.path or "(none)", ctx.mode or "-", ctx.key or "-", ctx.prefix or ""),
      ("target: %s%s  derives: %s"):format(
'''),
    ...para('--', r':MacroAttrs runs items at the cursor and prints the attribute path, the mode, the key, '
        r'the prefix, the target kind and sub, its derives, where the dependencies came from, '
        r'whether a schema matched, the number of items and any schema problems. It is the answer '
        r'to the question every completion plugin gets, why is nothing showing, built into the '
        r'plugin.'),
    ...sec(r'design decisions'),
    ...pt('--', r'Data, not code', r'the knowledge of ten crates lives in JSON that a user can override per project, with a '
        r'documented format.'),
    ...pt('--', r'Never hide because of ignorance', r'unknown version satisfies, unplaced target hides nothing, a scan answers before metadata exists.'),
    ...pt('--', r'Bounded everything', r'files, bytes, lines, retries and cache lifetimes are named values.'),
    ...pt('--', r'The lexer is its own thing', r'a completion happens inside unfinished text, so the module does not depend on a parser '
        r'that needs finished text for that part.'),
    ...sec(r'tested by'),
    ...para('--', r'tests/attrs_spec.lua: a table of about seventy cases for the completion, then groups for '
        r'items, long files, semver, dependencies, project schemas, learn from usage, the blink '
        r'source, accepting a derive and :MacroAttrs.'),
    ...sec(r'history'),
    ...pt('--', r'b9854b7', r'2026-10-22, Add the xyno_macros modules: attribute and derive completion, macro tools.'),
  ],
);
