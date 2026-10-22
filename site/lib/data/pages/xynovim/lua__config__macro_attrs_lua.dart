import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/macro_attrs.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'macro_attrs.lua — completion where rust-analyzer says nothing'),
    cm('--', r'keys, values and derive names inside #[serde(...)], #[arg(...)],'),
    cm('--', r'#[tokio::main(...)] and #[derive(...)], from data, as a blink.cmp source'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'blink.cmp source: keys, enum values and derives inside attribute arguments'),
    kv(r'language', r'Lua (Neovim 0.12 APIs: vim.uv, vim.lsp.protocol, vim.treesitter)'),
    kv(r'size', r'1840 lines, 3 commits (2026-10-14 to 2026-10-21)'),
    kv(r'data', r'data/macro_attrs/*.json (10 crates) + <workspace>/.xynovim/macro_attrs/*.json'),
    kv(r'pure core', r'M.items(bufnr, row, col): returns the items and an info table'),
    kv(r'also lives in', r'xyno-macros.nvim, lua/xyno_macros/attrs.lua (1846 lines)'),
    ...sec(r'why this file exists'),
    ...para('--', r'Typing #[serde( in a Rust buffer gives you nothing from rust-analyzer. The arguments of a helper attribute are opaque tokens to it: serde’s rename_all, clap’s value_parser, thiserror’s #[error("...")] are parsed by the proc macro, not by the language server, so the server has no list of keys to offer. The result is that keys, their allowed values and the names inside #[derive(...)] get typed from memory. This file is the answer: a completion source that knows those keys because they are written down as data.'),
    ...para('--', r'The header comment of the file states the plan in four steps, and the code follows them in the same order. A small lexer reads the attribute from its #[ to the cursor. The buffer is then parsed with the attribute repaired, so treesitter can say what the attribute is attached to. Only schemas of crates that are really dependencies are used, version-gated and scope-checked. And for dependency attributes that have no schema, keys the project already writes are offered by frequency.'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 10-27', r'''
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
local M = {}'''),
    ...para('--', r'Two things in that header shape the rest. The source must never block: dependency information comes from cargo metadata once it is cached, and from a text scan of Cargo.toml until then. And nothing is parsed with treesitter at the cursor, because the attribute under the cursor is unfinished by definition and a grammar parse of half an attribute is unreliable. The file therefore lexes by hand, and uses treesitter only on a text where the attribute has been closed.'),
    ...sec(r'configuration and bounds'),
    ...para('--', r'Every limit the file applies is one field of M.config, defined once at the top. They are all bounds on work, which tells you what the author worried about: a completion source runs on every keystroke inside an attribute, so no scan may grow with the size of the project.'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 31-44', r'''
M.config = {
  shipped_glob = "data/macro_attrs/*.json",
  user_dir = ".xynovim/macro_attrs", -- under the workspace root
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
}'''),
    ...pt('--', r'context_lines = 15', r'how far above the cursor an attribute may start. A long #[derive(...)] or a multi-line #[clap(...)] can begin above the cursor; fifteen lines is the search window.'),
    ...pt('--', r'window_min / window_lines', r'a file longer than 1500 lines is parsed around the cursor only, 300 lines each way. Section "the entry point" shows how the window is cut.'),
    ...pt('--', r'learn_*', r'the learn-from-usage scan: cached for 120 seconds, at most 300 files and 2 MB per scanned tree.'),
    ...pt('--', r'derive_*', r'the proc-macro source scan of a dependency: at most 80 files and 2 MB per crate.'),
    ...pt('--', r'import_attempts / import_interval', r'10 tries, 500 ms apart: used after accepting a derive, because rust-analyzer needs a moment to know a name that was just typed.'),
    blank,
    ...para('--', r'M.load_errors is a public list of problems met while loading schemas. Nothing is raised for a bad schema file; the message is appended to the list and surfaced by :MacroAttrs and by the specs. A broken project file therefore costs the user one line in a debugging command, not a failed completion.'),
    ...para('--', r'The helper read_file is worth reading for what it refuses. It stats the path first and returns nil unless it is a regular file under a size limit (2 MB by default, 1 MB for schemas, 400 KB for a proc-macro source). The comment says why: the files read here belong to the project or to a dependency, and a huge one, a FIFO or a link to /dev/zero must not block the editor. That guard arrived in the review-fixes commit 19f974c (2026-10-15); the first version read whatever path it was given.'),
    ...sec(r'semver without a library'),
    ...para('--', r'Schemas carry a versions field (">=1.0.0, <2.0.0") and individual keys carry since. To apply them the file needs a requirement matcher. It has its own, because the only version helpers available are cm.valid_version and cm.compare_versions from crate_meta. M.satisfies handles comparison operators, caret, tilde, a bare version (which cargo treats as caret) and partial versions such as "1" or "1.2".'),
    ...para('--', r'The first line of the contract is the important design decision: unknown or unparsable input is satisfied. If the dependency version is not known yet (metadata not cached), or the requirement cannot be read, the schema is NOT hidden. A completion source that silently disappears because of data it cannot parse is much harder to debug than one that offers a key which turns out to be too new. The caret branch follows cargo’s rule that the leftmost non-zero component is the one that may not change (1.2 caps at 2.0.0, 0.2 at 0.3.0, 0.0.3 at 0.0.4).'),
    ...para('--', r'The equals operator is the odd one: a partial version pins only the parts it names, so =1.2 matches 1.2.9. Each component of a comma-separated requirement is checked independently and all must pass.'),
    ...sec(r'schemas: shape, validation, overrides'),
    ...para('--', r'A schema is JSON, one file per crate. The format is documented in data/macro_attrs/README.md; the Lua side validates it in check_schema. The kinds an argument may have are a closed set, and the fields that must be lists are normalised so a hand-written file may write "field" where a list is expected.'),
    ...para('--', r'check_schema returns the file plus a list of errors rather than raising. A bad attribute is dropped and reported, the rest of the file survives: an attribute without a name, an argument without a key, an unknown kind. A file whose crate field is not a valid crate name is rejected whole. The kind check uses arg.kind or "flag", so a bare key defaults to a flag.'),
    ...para('--', r'Shipped schemas come from data/macro_attrs/*.json found through nvim_get_runtime_file, so they are read from wherever the config lives on the runtime path. Files named README are skipped by name, since the README sits in the same directory. First file wins per crate. The whole result is cached in shipped_cache for the session.'),
    ...para('--', r'The project override is the part users can touch. A directory .xynovim/macro_attrs/ under the workspace root may hold *.json files in the same format. The merge rule is deliberately coarse: a user attribute REPLACES every shipped attribute of the same crate and name, and a user file for another crate is simply added. Replacement per attribute (not per key) means a user can fix one attribute completely without having to understand how the rest merge.'),
    ...para('--', r'Caching is by modification time. The stamp is the sorted list of file paths with their mtime, joined; if the stamp is unchanged the previous merged set is returned. Editing a project schema is picked up by the next request without a restart; the spec "editing a project file is picked up by the next request" pins that. The shipped set is copied with vim.list_slice before merging so the user layer never mutates the shipped cache.'),
    ...sec(r'the lexer: reading half an attribute'),
    ...para('--', r'The central difficulty of this file is that the text under the cursor is invalid Rust. #[serde(rename_all = "snake_case", default, skip_s is a perfectly ordinary state to be in, and what the source needs from it is: which attribute path, which key is being typed or which key’s value, which keys already appeared, and whether the cursor is inside a string. A tiny hand-written state machine gives that without a parser.'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 316-347', r'''
local CLOSER = { ["("] = ")", ["["] = "]", ["{"] = "}" }

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

local function push_frame(st, key)
  st.frames[#st.frames + 1] = { key = key, seen = {}, entry = nil }
end

local function finish_entry(f)
  local e = f.entry
  if e and e.key ~= "" then
    f.seen[e.key] = true
    local last = e.key:match("([%w_]+)$")
    if last then
      f.seen_last = f.seen_last or {}
      f.seen_last[last] = e.key
    end
  end
  f.entry = nil
end'''),
    ...para('--', r'new_state creates a machine with three phases: path (reading serde or tokio::main), args (inside the parentheses) and after. A stack of expected closers (bstack) tracks nesting. For cfg_attr(cond, derive(...)) the lexer is started a second time on the inner attribute with inner = true, which puts an extra ")" on the stack. Each parenthesis level gets a frame: its key, the keys seen so far and the entry currently being written.'),
    ...para('--', r'Entries move through states key, value, nested and after. The function that does this is token(), roughly a hundred lines of branches. Its shape is easiest to see on the value branch:'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 425-445', r'''
  elseif e.state == "value" then
    if text == "(" or text == "[" or text == "{" then
      e.depth = e.depth + 1
      e.vtokens = e.vtokens + 1
    elseif text == ")" or text == "]" or text == "}" then
      if e.depth > 0 then
        e.depth = e.depth - 1
        e.vtokens = e.vtokens + 1
      elseif text == ")" then
        finish_entry(f)
        table.remove(st.frames)
        if #st.frames == 0 then
          st.phase = "after"
        end
      end
    elseif text == "," and e.depth == 0 then
      finish_entry(f)
    else
      e.vtokens = e.vtokens + 1
      e.vtext = (e.vtext or "") .. text
    end'''),
    ...para('--', r'A value is a sequence of tokens up to a top-level comma; e.depth counts brackets inside it, vtokens how many tokens it holds. vtokens == 0 is the moment the cursor is at the START of a value, which is the only moment value completion applies. A key written as a path (a::b) is accumulated with its "::" so qualified keys work.'),
    ...para('--', r'run() feeds characters to the machine. It knows strings with escapes, line and block comments, identifiers, "::" as one token, and the three bracket kinds. A closer that does not match the stack sets broken and stops reading; the lexer prefers to stop than to guess.'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 488-500', r'''
    elseif st.str then
      if c == "\\" then
        st.str.buf = st.str.buf .. text:sub(i, i + 1)
        i = i + 1
      elseif c == '"' then
        local s = st.str
        st.str = nil
        token(st, "string", s.buf, i)
      else
        st.str.buf = st.str.buf .. c
      end
    elseif c:match("[%w_]") then
      st.pending = (st.pending or "") .. c'''),
    ...para('--', r'snapshot() then turns machine state into the thing completion needs. It answers nil (nothing to complete) when the attribute is already closed, the cursor is in a comment, or the cursor is in the middle of a value that is more than one token. In a string, it answers only when the string is the whole first token of a value, which is what makes #[serde(rename_all = "sn|")] complete and #[error("{} fo|")] not.'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 546-553, 576-589', r'''
local function snapshot(st)
  if st.closed or st.comment then
    return nil
  end
  if st.phase ~= "args" then
    return { mode = "path", path = st.path .. (st.pending or "") }
  end
  local f = st.frames[#st.frames]
...
  if not e then
    ctx.mode, ctx.prefix = "key", st.pending or ""
  elseif e.state == "key" then
    if e.key:sub(-2) == "::" then
      ctx.mode, ctx.prefix, ctx.qualifier = "key", st.pending or "", e.key:sub(1, -3)
    else
      return nil
    end
  elseif e.state == "value" and e.vtokens == 0 and e.depth == 0 then
    ctx.mode, ctx.key, ctx.prefix = "value", e.key, st.pending or ""
  else
    return nil
  end
  return ctx'''),
    ...para('--', r'The result is a ctx table: mode (path, key or value), the attribute path, the chain of keys for nested frames, seen (keys already present), seen_last (the same set by last path segment, used for derives), the typed prefix and, for qualified keys, the qualifier. The info table that M.items returns carries it so :MacroAttrs and the specs can look at it.'),
    ...sec(r'finding the attribute that holds the cursor'),
    ...para('--', r'lex_attr runs the machine from just after "#[" to the cursor, takes the snapshot, then keeps lexing forward over the rest of the cursor line and over following lines that still read like attribute arguments. The forward pass exists for one purpose: to learn where the attribute ends so that closers can be appended for the treesitter parse. The continuation heuristic is a pattern test per line (a key followed by = , ( or ]; a string; a closer), capped at 20 lines, and it refuses a line that looks like a new statement (two identifiers in a row).'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 613-630', r'''
  local function line_end(r)
    return offs[r] + #lines[r]
  end
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
  return ctx, st, st.closed and not st.broken, line_end(last)
end'''),
    ...para('--', r'attribute_at walks upward from the cursor line through at most context_lines lines looking for "#[" or "#![". It tries at most four candidate starts in total (tried > 4 returns nil), nearest first, and returns on the first one whose lexer state says the cursor is inside it. A note on the code as written: the loop body ends in return nil, so after the first candidate has been examined the function returns whether or not it matched; the counter and the downward loop over starts suggest an intent to try more than one, but the code only ever tries the nearest start on the nearest line that has one.'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 652-658, 682-684', r'''
    for k = #starts, 1, -1 do
      tried = tried + 1
      if tried > 4 then
        return nil
      end
      local start = offs[r] + starts[k][2] + 1
      local ctx, st, closed, end_off = lex_attr(text, lines, offs, start, cur, row, false)
...
      end
      return nil
    end'''),
    ...para('--', r'For cfg_attr the function does the nested trick: the first top-level comma inside cfg_attr( marks where the real attribute begins, and the lexer is run again from there with inner = true, so #[cfg_attr(feature = "serde", serde(rename_all = "..."))] completes serde keys while #[cfg_attr(feature = "s|" gets nothing. The recorded closers string is built from what is still open (a quote, then the reversed bracket stack), and is what the next step inserts.'),
    ...sec(r'dependencies, without blocking'),
    ...para('--', r'A schema only applies if the workspace member depends on the crate. M.dependencies(path, root) is the function that answers, and its contract is in its doc comment: it never blocks. If cargo metadata is cached and its stamp (mtime of the root Cargo.toml, Cargo.lock and every member manifest) still matches, the resolved dependency list is used and versions are known. Otherwise a metadata run is started in the background (once, with a 60 second backoff after a failure) and the answer comes from scanning the manifests as text.'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 806-825', r'''
  if not inflight[root] and (not failed[root] or os.time() - failed[root] > 60) then
    inflight[root] = true
    M.refresh_dependencies(root)
  end
  local by_name = {}
  local seen_file = {}
  for _, manifest in ipairs({ root .. "/Cargo.toml", nearest_manifest(path, root) }) do
    if not seen_file[manifest] then
      seen_file[manifest] = true
      for _, d in ipairs(manifest_deps(read_file(manifest) or "")) do
        -- a path dependency has its sources next to the manifest (no registry needed)
        local dir = d.path and vim.fs.normalize(vim.fs.dirname(manifest) .. "/" .. d.path) or nil
        local rec = { name = d.name, alias = norm(d.alias), dir = dir }
        by_name[norm(d.name)] = by_name[norm(d.name)] or rec
        by_name[rec.alias] = by_name[rec.alias] or rec
      end
    end
  end
  return { by_name = by_name, from = "scan", root = root }
end'''),
    ...para('--', r'The text scan is manifest_deps. It understands the table forms a real manifest uses: [dependencies], [dev-dependencies] (optionally skipped), [dependencies.name], renamed dependencies through package = "...", and path dependencies. A set of keys such as version, features or optional is skipped so inline-table fields are not mistaken for crate names. For a path dependency the sources are right next to the manifest, so no registry lookup is needed.'),
    ...para('--', r'By_name is indexed twice, by the package name with - turned into _ and by the alias, so a renamed dependency answers under both names. The scan result has no version, so M.satisfies falls through to true: while metadata loads, completion works on shapes only. That is the "unknown is satisfied" rule from the semver section paying off.'),
    ...sec(r'derive discovery'),
    ...para('--', r'#[derive( completes the nine standard derives plus the derive macros found in the dependencies. The second list is not data: it is read from the dependency sources. For each dependency the code finds its directory (a path dependency’s own dir, else the registry copy through cm.registry_dir), also looks at proc-macro crates its manifest depends on (a crate like clap re-exports derives from clap_derive), and scans their src for #[proc_macro_derive(Name, attributes(a, b))].'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 877-892', r'''
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
            if not seen[nm] then
              seen[nm] = true
              out[#out + 1] = { name = nm, helpers = helpers }
            end
            from = e + 1'''),
    ...para('--', r'The balanced helper reads the inside of a parenthesis with a 600 character cap, honouring strings, so attributes(...) is found even when it follows other arguments. A directory is a proc-macro crate only if its manifest says proc-macro = true (or proc_macro). The depth-3 directory walk, the per-file and per-crate byte limits and the memo keyed by directory keep this from costing anything after the first request.'),
    ...para('--', r'There is one more subtlety in pkg_dir: when cargo metadata is known, a crate that is not in the resolved graph returns nil rather than falling back to the registry, with the comment "a crate that is not in it is not enabled". The memo key includes whether metadata or the scan was used. Results are sorted by name, then crate, so ties are stable.'),
    ...sec(r'what is the attribute attached to'),
    ...para('--', r'Whether serde’s skip_serializing_if is valid depends on the thing the attribute decorates. target_of(text, row0, col0) parses the REPAIRED text with a treesitter string parser and walks from the attribute_item node outward. The parent decides the kind: a field_declaration_list means a field, enum_variant_list a variant, parameters a parameter; otherwise the next named sibling that is not another attribute or a comment is the item, and its node type says container, fn or item.'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 1027-1054', r'''
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
    local t = sib and sib:type()
    if t and ITEM_NODES[t] then
      kind = "container"
    elseif t == "function_item" or t == "function_signature_item" then
      kind = "fn"
    elseif t then
      kind = "item"
    end
  end'''),
    ...para('--', r'attr_run reads the contiguous attribute_item siblings before the item and extracts both the attribute paths and the derive names (with their qualification, so derive(serde::Serialize) records qual = "serde"). skip_error steps over ERROR nodes, which is how the repaired-but-still-odd text from a half-typed buffer survives. When treesitter cannot place the attribute, the result is an empty table and every later check treats an unknown kind as "do not hide anything".'),
    ...sec(r'scope: is this helper really in scope here'),
    ...para('--', r'Offering serde keys inside #[error(...)] would be wrong. The file implements the Rust rule in a cheap way: a helper attribute is in scope only if a derive that provides it is on the same item, and that derive resolves to this crate. Resolution is done from the text of the use statements.'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 1125-1144', r'''
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
end'''),
    ...para('--', r'derive_ok is the rule. A derive written with a qualifier counts when the qualifier’s first segment is the crate. An unqualified derive counts when the use statements import it from that crate, or when no use statement mentions it at all (next(from) == nil). That last clause is what keeps completion working in a file where the derive is imported by a glob or a prelude. It also explains why thiserror’s Error and derive_more’s Error can both exist as schemas: the use line tells them apart.'),
    ...para('--', r'path_matches handles attribute macros: a schema attribute named tokio::main matches the full path as written, or its last segment ("main") when a use statement imports it from tokio. And the since check in arg_allowed compares the resolved version to the key’s since, so keys newer than the installed crate are hidden.'),
    ...sec(r'turning schema into completion items'),
    ...para('--', r'The item builders make the menu readable. A key gets a kind label (flag, = "…", = number, = one of …), a LSP snippet so accepting it types the right punctuation (key = "$1" for strings, key = ${1:0} for integers, a bare key for flags), and a markdown preview that lists applies_to, since, conflicts, requires and the enumerated values, plus a docs link.'),
    ...para('--', r'Sorting is encoded in sortText: positional arguments (the message of #[error("...")]) sort first with prefix 0, ordinary keys with 5, and keys whose requires are not met yet with 9, so a key that needs another sinks below the ones that are ready. The data.retrigger flag on a quoted-enum key makes execute() re-open the menu after the snippet is expanded, so the value list appears immediately after the key.'),
    ...para('--', r'schema_items is the filter pipeline. It matches every shipped schema of a dependency against the attribute path, then filters by applies_to, by the derive scope, by needs_attr (the function must carry bon::builder, for example) and by the rule that a function parameter attribute needs needs_attr. Then, for each key, arg_allowed and conflicts_with_seen remove what cannot be written here: a non-repeatable key already present, a key listed in conflicts of something already present (in either direction), and a positional key once anything has been written.'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 1269-1284', r'''
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
end'''),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 1292-1311', r'''
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
      end'''),
    ...para('--', r'Deduplication uses a dedupe table so two crates that define the same attribute name do not yield duplicate keys. Alternatives (alt) produce additional labelled items from the same arg, ordered by a fractional offset. In value mode the same machinery looks up the key under the cursor and produces EnumMember items from its values, with quotes added unless the cursor is already inside a string (in_string), and booleans always offering true and false.'),
    ...sec(r'learning from usage when there is no schema'),
    ...para('--', r'There are more proc-macro crates than schemas. For an attribute that belongs to a dependency but that no schema describes, the file falls back to what the code around it already does. learn() counts the top-level keys written inside #[path(...)] in the workspace members and in the dependency sources, scoring each as 2 × workspace uses + dependency uses, so the project’s own habits outrank the library’s examples.'),
    ...para('--', r'body_keys splits an attribute body on top-level commas, skipping strings and nested brackets; count_keys finds every "#[path" in a file with a plain-text find, then reads the balanced parenthesis after it. scan_files walks a tree to depth 6 with the file, byte and per-file limits and skips target, .git, node_modules and .cargo.'),
    ...para('--', r'learn_items decides whose attribute it is: either the path is qualified by a dependency (tokio::something) or it is a helper attribute declared by a derive in scope, found in the derive catalogue. Keys already present are not offered; a key equal to the typed prefix that has been used only once is dropped, so a half-typed word does not teach itself. Learned values are not offered, only keys (the spec "values are not learned (only keys)").'),
    ...sec(r'derive items'),
    ...para('--', r'derive_items lists the standard derives (only when the user has not typed a qualifier like serde::) and the catalogue ones. Each carries data for execute(): the crate, the path, a builtin flag and a qualified flag. The documentation lists the helper attributes the derive declares, which is useful on its own: seeing that Parser brings #[arg] and #[command] is a way to discover them.'),
    ...sec(r'the entry point'),
    ...para('--', r'M.items is the pure function the specs drive; the blink source is a thin shell around it. It first decides whether to parse the whole buffer or a window. Parsing an entire 20,000 line file on every keystroke would be the obvious performance bug, so window() cuts a slice that starts and ends at item boundaries (lines starting in column 0, ending with a } in column 0). The top 400 lines are added back for the use statements, since imports sit outside the window.'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 1639-1673', r'''
  local at = attribute_at(lines, row, col)
  if not at or at.ctx.mode == "path" then
    return {}, { ctx = at and at.ctx }
  end
  local ctx = at.ctx
  local path = ctx.path
  local name = vim.api.nvim_buf_get_name(bufnr)
  local root = name ~= "" and cm.root(name) or nil
  local deps = root and M.dependencies(name, root) or { by_name = {}, from = "none" }
  local info = { ctx = ctx, deps_from = deps.from, root = root }

  -- the item the attribute belongs to, with the attribute repaired for treesitter
  local text = at.text
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
end'''),
    ...para('--', r'After the attribute is found, the text is repaired by inserting the closers at end_off, treesitter runs on the repaired text, and the use statements are collected. Then the three paths: #[derive( goes to derive_items; anything nested more than two levels deep, or any file without a Cargo root, returns nothing; otherwise schema_items runs, and only if no schema matched, the key mode, and no nesting is involved, learn_items runs. The info table records deps_from, matched and learned, which is what :MacroAttrs prints.'),
    ...sec(r'the blink.cmp source'),
    ...para('--', r'Four methods make the source. enabled is true in Rust buffers. get_completions calls M.items inside pcall and answers with is_incomplete_forward and is_incomplete_backward both true, since the answer depends on which keys are already written. The pcall means an error in this module can never break the completion menu; the user gets fewer items instead of a stack trace.'),
    ...para('--', r'get_trigger_characters is the interesting one. blink asks for trigger characters per request, and the source returns them only when the line before the cursor is inside an attribute it knows (derive, or a path some shipped schema describes). The reason is in the comment: returning triggers everywhere would suppress rust-analyzer’s own triggers elsewhere, for example inside #[cfg(...)]. Without the ")" rule typing #[serde( opened no menu at all: an auto-pair types () and blink sees only the last character typed, which is the ")", so between the parentheses that closing paren has to be the trigger. The comment records that this was measured in a real terminal.'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 1706-1723', r'''
function Source:get_trigger_characters()
  local ok, chars = pcall(function()
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
    end
    return {}
  end)
  return ok and chars or {}
end'''),
    ...sec(r'accepting a derive that is not imported'),
    ...para('--', r'Completing derive(Parser) is only half useful if Parser is not imported. execute() runs the default insertion, then, for a derive that is not builtin, not qualified and not already in scope, calls M.on_derive_accepted(name, info) 30 ms later (after the buffer has the text). The default hook asks the import engine: it applies the remembered choice of the project or the single candidate whose path matches the derive’s own crate, tells the user when several candidates exist and none is unambiguous, and retries up to import_attempts times while rust-analyzer still does not know the name.'),
    ...code('lua', r'lua/config/macro_attrs.lua · lines 1750-1769', r'''
    engine.resolve(name, {
      bufnr = info.bufnr,
      pos = { info.row - 1, info.col - #name },
      derive = true,
      sources = false, -- the derive comes from a dependency: no crates to add
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
        end'''),
    ...para('--', r'The hook is a plain field on M so a user can replace it. The retry is a real feature: right after typing a derive that was never in the file, rust-analyzer has not indexed it, so the first resolve returns no candidates and the code tries again 500 ms later, ten times at most.'),
    ...sec(r':MacroAttrs'),
    ...para('--', r'The one command is a debugging aid, and a good habit: when a completion is missing, the question is always "what did the source see". The command runs M.items at the cursor and prints the attribute path, the mode, the key, the prefix, the target kind and its derives, where the dependencies came from, whether a schema matched, the item count, and any schema problems collected in load_errors.'),
    ...sec(r'the same module in xyno-macros.nvim'),
    ...para('--', r'The Rust tooling of this configuration was extracted into standalone plugins on 2026-10-22. This file lives on as lua/xyno_macros/attrs.lua in ~/projects/xyno-plugins/xyno-macros.nvim (1846 lines against 1840 here). A line diff shows the extraction was close to mechanical. What differs:'),
    ...pt('--', r'requires', r'crate_meta, rust_context and the import engine come from xyno_rust.* and xyno_imports.engine instead of config.*. The plugin’s init checks they exist and prints one error line if not.'),
    ...pt('--', r'user schema directory', r'.xyno-macros/attrs under the workspace root instead of .xynovim/macro_attrs.'),
    ...pt('--', r'shipped schema lookup', r'the plugin computes its own directory from debug.getinfo and globs plugin_root/data/macro_attrs, instead of searching the runtime path (nvim_get_runtime_file). The plugin has to find its data wherever the plugin manager put it.'),
    ...pt('--', r'setup', r'M.setup(opts) accepts commands = false to skip creating :MacroAttrs. Here setup() takes no arguments.'),
    ...pt('--', r'everything else', r'the lexer, the target logic, the scoring and the blink source are identical. The comments that referenced plan items (2.1, 2.2, G1, G2) were dropped.'),
    blank,
    ...para('--', r'The blink wiring that sits in lua/plugins/macro-attrs.lua in this repository is, in the plugin, a function M.blink_opts in xyno_macros/init.lua that registers both sources with one call.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/macro-attrs_spec.lua (1382 lines) is the spec, and its structure mirrors this file: a table-driven section for attribute and derive completion with fake buffers, a section on item content, long files, version requirements, dependencies (the Cargo.toml scan against real cargo metadata), project schemas, learning from usage, the blink source, accepting a derive, and :MacroAttrs. Two of its checks are worth naming because they guard the data rather than the code.'),
    ...pt('--', r'every shipped schema is valid and every key is unique', r'a lint over data/macro_attrs/*.json using the same check_schema, so a typo in a schema fails the suite.'),
    ...pt('--', r'derive helper attributes in the schemas are declared by the real proc-macro crates', r'where the registry has the crate, the helper attributes a schema lists for a derive are compared with what proc_macro_derive(..., attributes(...)) declares, which keeps the shipped data honest.'),
    ...pt('--', r'opens the menu while typing inside #[serde(', r'an end-to-end spec with the real blink.cmp completion list: type the attribute, the menu opens, accepting a key expands its snippet and re-opens the values.'),
    ...pt('--', r'adds the use line through rust-analyzer’s own import action', r'a spec against a real rust-analyzer for the derive-import path (H.need_rust); it is marked a known issue on macOS after a 95 s timeout in CI.'),
    ...sec(r'history'),
    ...pt('--', r'b9363cd 2026-10-14', r'"Macros and dependencies": the file arrives with 1833 lines, together with the ten schemas in data/macro_attrs, crate_meta use, the import engine, crate add and crate features. The same commit adds lua/plugins/macro-attrs.lua.'),
    ...pt('--', r'19f974c 2026-10-15', r'review fixes: read_file gains the regular-file and size guard (so a FIFO or /dev/zero link cannot block), schema loads cap at 1 MB, proc-macro sources at 400 KB.'),
    ...pt('--', r'6524272 2026-10-21', r'Windows and macOS CI fixes. One line here: refresh_dependencies canonicalises the root through rust_context.canon, so a drive-letter case or a path spelling does not give two metadata entries for the same workspace.'),
    ...pt('--', r'2026-10-22', r'extraction to xyno-macros.nvim (b9854b7 in that repository).'),
    ...sec(r'rough edges worth knowing'),
    ...pt('--', r'attribute_at', r'as noted above, the candidate loop returns after the first start it examines, so the tried counter is dead code and an earlier #[ on the same line is never retried.'),
    ...pt('--', r'doc comment placement', r'the "Items for the cursor at (row 1-based, col 0-based byte)" comment (line 1609) sits above the window() helper, not above M.items, which follows it. The doc describes the wrong function.'),
    ...pt('--', r'execute', r'after the deferred hook call, a pcall result is stored in ok and then tested with if not ok then return end, which does nothing. The branch can be deleted without changing behaviour.'),
    ...pt('--', r'doc_text', r'arg.key:gsub("%*", "") inside a format call passes gsub’s second return value (the count) as an extra argument. string.format ignores extras, so it is harmless.'),
  ],
);
