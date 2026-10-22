import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/crate_features.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'crate_features.lua — enable the cargo feature a name needs'),
    cm('--', r'a source scanner, a Cargo.toml editor, an in-process LSP client'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'missing-feature code action and the :CrateFeatures explorer'),
    kv(r'language', r'Lua for Neovim 0.12, no plugins (Snacks picker used when present)'),
    kv(r'size', r'2027 lines, 4 commits (2026-10-14 to 2026-10-16)'),
    kv(r'spec', r'tests/crate-features_spec.lua (869 lines)'),
    kv(r'commands', r':CrateFeatures [crate], <leader>rG, code action in <leader>ca'),
    kv(r'also lives in', r'xyno-crates.nvim as lua/xyno_crates/crate_features.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'Rust has a failure that looks like a typo but is not one: you write #[derive(Serialize)], and rustc or rust-analyzer answers cannot find derive macro Serialize in this scope. The name exists; it is gated behind a cargo feature (derive, on serde) that is off. Nothing in the diagnostic says so. This file closes that gap. It reads the unpacked source of your dependencies, finds the cfg gate in front of the missing name, resolves it through the crate [features] table, and offers a code action that edits Cargo.toml.'),
    ...para('--', r'The second half is a feature explorer: for one dependency, which features are declared, which are effectively on, what each one unlocks, and which declared ones look unused. It is the same source scan, asked the other way round.'),
    ...code('lua', r'lua/config/crate_features.lua · lines 15-26', r'''
--   * Feature explorer :CrateFeatures [crate]: per dependency the declared
--     and effective features, what each feature unlocks (the gated pub items
--     of the same scan), the default set and an "unused?" hint for a declared
--     feature none of whose items appears in the workspace sources.
--
-- Cargo.toml edits: `cargo add <crate> --features ..` (argv, offline first) for
-- registry dependencies when a feature is switched on, a careful text edit
-- (formatting and comments kept) for everything else: switching off, renamed,
-- path and git dependencies, and when cargo add changed nothing. The member
-- that declares the dependency is edited; `workspace = true` stays and gets
-- the feature in the member's own entry (additive), the workspace table is not
-- touched. Everything that comes from the network or from files (crate and'''),
    ...para('--', r'The header is the specification, and it states the edit policy precisely. A cargo add --features call is used for registry dependencies when a feature is switched on (offline first); a careful text edit that keeps formatting and comments is used for everything else: switching off, renamed, path and git dependencies, and when cargo add changed nothing. For workspace = true the feature goes into the member own entry, additively; the workspace table is not touched. All names are validated before they reach an argv.'),
    ...sec(r'gates are small boolean formulas'),
    ...code('lua', r'lua/config/crate_features.lua · lines 45-47, 55-68', r'''
-- must all be on. {} (no alternative) is "never", { {} } is "always".

local ALWAYS = { {} }
...
local function and_gate(a, b)
  local out, seen = {}, {}
  for _, x in ipairs(a) do
    for _, y in ipairs(b) do
      local u = vim.tbl_extend("force", {}, x, y)
      local k = alt_key(u)
      if not seen[k] and #out < M.config.max_alts then
        seen[k] = true
        out[#out + 1] = u
      end
    end
  end
  return out
end'''),
    ...para('--', r'The core data structure is a gate in disjunctive normal form: a list of alternatives, each a set of features that must all be on. The comment gives both constants: an empty list is never, and a list holding one empty set is always. and_gate multiplies two gates (every pair of alternatives merged) and or_gate concatenates; both de-duplicate by a sorted key and cap the result at max_alts (32), so a pathological cfg(any(...)) cannot blow up. M.config holds the other limits of the scan: 150 source files per crate, 600 KB per file.'),
    ...code('lua', r'lua/config/crate_features.lua · lines 107-125, 135-139', r'''
--- The inside of a `cfg(...)` -> gate. Only `feature = ".."` matters; `not(..)`
--- and other predicates (unix, docsrs, target_*) are treated as true, `test`
--- as false (test modules are no API).
function M.parse_cfg(e)
  e = vim.trim(e)
  local f = e:match('^feature%s*=%s*"([^"]+)"$')
  if f then
    return { { [f] = true } }
  end
  local op, args = e:match("^(%a+)%s*(%b())$")
  if op == "all" then
    local g = ALWAYS
    for _, a in ipairs(split_args(args:sub(2, -2))) do
      g = and_gate(g, M.parse_cfg(a))
    end
    return g
  elseif op == "any" then
    local g = {}
    for _, a in ipairs(split_args(args:sub(2, -2))) do
...
  return ALWAYS
end

-- ============================================================ source scanner'''),
    ...para('--', r'parse_cfg reads the inside of a cfg(...). Only feature = "x" matters. all() ands its arguments and any() ors them; split_args splits on top-level commas, skipping strings and parentheses. The two choices in the doc comment are the interesting ones. not(...) is treated as true: a name behind cfg(not(feature = "std")) is available in the default build, and proposing to enable something because a feature is absent would be wrong. Other predicates (unix, docsrs, target_*) are true, and test is false because test modules are no API.'),
    ...sec(r'scanning a crate without a Rust parser'),
    ...para('--', r'scan_dir reads lib.rs and the modules it declares and builds a map from exported name to candidates, each with a gate, a reach flag (is every module on the way public) and a kind. It is a purpose-built scanner, not name resolution, and it is explicit about that. First strip() removes comments while keeping strings, because the cfg features are in the strings; it handles nested block comments, raw strings with hashes, and tells a char literal from a lifetime. Then parse_region walks items one at a time.'),
    ...code('lua', r'lua/config/crate_features.lua · lines 500-512', r'''
      mods[#mods + 1] = name
      parse_region(t, q + 1, e - 1, { gate = gate, mods = mods, pubchain = st.pubchain and vis, dir = st.dir .. "/" .. name })
      return e + 1
    end
    local rel = path_attr and not path_attr:find("..", 1, true) and path_attr:sub(1, 1) ~= "/" and path_attr or nil
    local cands = rel and { st.dir .. "/" .. rel } or { st.dir .. "/" .. name .. ".rs", st.dir .. "/" .. name .. "/mod.rs" }
    for _, c in ipairs(cands) do
      if vim.uv.fs_stat(c) then
        local child_dir = c:match("/mod%.rs$") and vim.fs.dirname(c) or (st.dir .. "/" .. name)
        load_file(c, st, name, vis, gate, child_dir)
        break
      end
    end'''),
    ...para('--', r'The bounds come first: after max_files files the scan stops and marks itself truncated, an unreadable or oversized file marks it truncated when it was too big. A mod declaration is followed either inline or to name.rs or name/mod.rs. A #[path] attribute is honoured only when it has no .. and is not absolute, the same rule crate_meta applies to a [lib] path: a dependency is untrusted input.'),
    ...code('lua', r'lua/config/crate_features.lua · lines 540-548', r'''
        local attr = t:sub(q + 1, close - 1)
        local cfg = attr:match("^%s*cfg%s*(%b())%s*$")
        if cfg and not inner then
          gate = and_gate(gate, M.parse_cfg(cfg:sub(2, -2)))
        elseif attr:match("^%s*macro_export") then
          macro_export = true
        else
          path_attr = attr:match('^%s*path%s*=%s*"([^"]+)"') or path_attr
        end'''),
    ...para('--', r'Attributes in front of an item are collected in a loop. A cfg adds to the gate with and_gate, macro_export is remembered, and a path attribute is kept for the next mod. Inner attributes (#![...]) are ignored for the gate. The rest of parse_region dispatches on the first word: use (a pub use adds its names, a glob is queued), mod, macro_rules!, const and static, fn/struct/enum/trait/type/union, and macro calls; anything else is skipped with item_end. A guard of 20000 iterations stops a malformed file from looping.'),
    ...code('lua', r'lua/config/crate_features.lua · lines 421-439', r'''
    if not s then
      break
    end
    from = s + 2
  end
  local seg = before:sub(from)
  local g = ALWAYS
  local found = false
  for attr in seg:gmatch("#%s*(%b[])") do
    local cfg = attr:match("^%[%s*cfg%s*(%b())%s*%]$")
    if cfg then
      g = and_gate(g, M.parse_cfg(cfg:sub(2, -2)))
      found = true
    end
  end
  return found and g or nil
end

--- Scan a crate's source: { items = { name = { cand... } }, files, truncated }'''),
    ...para('--', r'The tokio problem is why wrapper_gate exists. Tokio does not write cfg attributes on every item; it defines macros such as cfg_net! whose body wraps each item in #[cfg(feature = "net")]. wrapper_gate reads such a definition: it finds the last $item in the transcriber, looks back to the nearest $( and collects the cfg attributes in between. The scanner then parses the body of every later cfg_net! { ... } call with that gate. Calls are queued in ctx.pending and processed after all files are read, because a definition can come after its use.'),
    ...para('--', r'That loop runs up to 40 rounds, until no new wrapper bodies turn up, since a wrapper body can itself contain another wrapper call. After it, glob re-exports (pub use self::m::*, pub use crate::m::*, super::*) are resolved by copying the pub items of that module at the current level.'),
    ...code('lua', r'lua/config/crate_features.lua · lines 730-751', r'''
function M.gate_of(idx, name)
  local cands = idx.items[name]
  if not cands then
    return nil, "not found"
  end
  local pref = vim.tbl_filter(function(c)
    return c.reach
  end, cands)
  if #pref == 0 then
    pref = cands
  end
  local g = {}
  for _, c in ipairs(pref) do
    for _, alt in ipairs(c.gate) do
      if next(alt) == nil then
        return nil, "ungated"
      end
    end
    g = or_gate(g, c.gate)
  end
  return g
end'''),
    ...para('--', r'M.scan caches a scan per directory with the mtime of lib.rs as stamp: a registry crate never changes, and a path dependency is re-read when its lib.rs changes (a change deeper in a module file is not noticed, which is the trade-off of a one-stat check). gate_of answers for one name. It prefers candidates that are reachable through public modules, returns nil with "ungated" when any candidate is always available (so no feature can be the reason), and ors the gates of the rest.'),
    ...sec(r'from a gate to the features to enable'),
    ...para('--', r'A cargo [features] table maps a feature to a list of items: other features, dep:x, x/y or x?/y. closure(ft, f) collects everything switched on by enabling f. The branch that skips dep: entries and entries with a slash that do not name a feature is how the table is read without confusing a dependency feature (serde_derive/std) with a feature of this crate. is_implicit recognises the feature cargo invents for an optional dependency, which is exactly { "dep:name" }.'),
    ...code('lua', r'lua/config/crate_features.lua · lines 838-866', r'''
function M.resolve(gate, ft, enabled)
  local best
  for _, alt in ipairs(gate) do
    local missing = {}
    for f in pairs(alt) do
      if not enabled[f] then
        missing[#missing + 1] = f
      end
    end
    if #missing == 0 then
      return nil, "enabled"
    end
    table.sort(missing)
    local mapped = {}
    for _, r in ipairs(missing) do
      mapped[#mapped + 1] = nice_feature(ft, r)
    end
    local list = reduce(ft, vim.fn.uniq(vim.fn.sort(mapped)))
    local key = string.format("%03d", #list) .. table.concat(list, ",")
    if not best or key < best.key then
      best = { key = key, list = list }
    end
  end
  if not best then
    return nil, "never"
  end
  return best.list
end'''),
    ...para('--', r'nice_feature turns a requirement into the feature a person would name. If the gate says feature = "serde_derive" but that is only the implicit feature of an optional dependency, and derive = ["serde_derive"] exists, then the answer is derive: the smallest named, non-default feature whose closure contains the requirement, ties broken alphabetically. resolve then takes the cheapest alternative of the gate: for each alternative it lists the missing features, maps them with nice_feature, drops any that another feature of the list already implies, and picks the shortest list (the key is the zero-padded length plus the names). It returns nil, "enabled" when an alternative already holds, which is how the code avoids offering a fix for a name that is missing for another reason.'),
    ...para('--', r'enabled_set computes what is on for a declared dependency: the declared features and what they imply, plus default unless default-features is false. features_of, just below, reads the table from the metadata, and falls back to the registry manifest through crate_meta.parse_features, adding the implicit features of optional dependencies that no dep: mentions.'),
    ...sec(r'from a diagnostic to a name'),
    ...code('lua', r'lua/config/crate_features.lua · lines 936-945', r'''
      out[#out + 1] = { name = name, qual = qual }
    end
  end
  for n in msg:gmatch("cannot find [%w%- ]-`([^`]+)`") do
    add(n)
  end
  for n, q in msg:gmatch("could not find `([^`]+)` in `([^`]+)`") do
    add(n, (q:match("^([^:]+)")))
  end
  for n, q in msg:gmatch("no `([^`]+)` in `([^`]+)`") do'''),
    ...para('--', r'names_from_message reads three dialects: rustc, rust-analyzer and bacon-ls. The patterns cover cannot find X, could not find X in Y, no X in Y, unresolved import, unresolved macro, no X in the root and failed to resolve. Each name is cut at the last path segment, qualified by the first segment of the path when there is one, and must be a plain identifier. diag_names adds a fallback for rust-analyzer messages that carry no name: the identifier under the diagnostic, but only when the line holds an attribute, so #[derive(Serialize)] and #[tokio::main] work.'),
    ...para('--', r'suggest is the pure core and says so in its doc comment: pure apart from the cached source scans. For each diagnostic name it narrows the dependencies of the file member to those hinted by the qualifier or by a use of that alias, otherwise tries all of them, with the kind of the file first (a test, example or bench reads dev-dependencies before normal ones). For each candidate it scans, finds the gate, and resolves it. Several names that need the same features of the same crate are merged into one suggestion, so two missing derives give one action, not two.'),
    ...sec(r'editing Cargo.toml by hand, carefully'),
    ...code('lua', r'lua/config/crate_features.lua · lines 1129-1145', r'''
  local items = {}
  local i = lb + 1
  while i <= #text do
    local c = text:sub(i, i)
    if c == '"' or c == "'" then
      local e = text:find(c, i + 1, true) or #text
      items[#items + 1] = { s = i, e = e, v = text:sub(i + 1, e - 1) }
      i = e + 1
    elseif c == "#" then
      i = (text:find("\n", i, true) or #text) + 1
    elseif c == "]" then
      rb = i
      break
    else
      i = i + 1
    end
  end'''),
    ...para('--', r'array_edit is the lowest layer: it adds or removes a feature in the array whose [ is at a given offset. The comment says what was learned in review: one walk, # comments skipped (a comment can contain [ or ]), and both basic and literal strings count as items. The first version used a pattern for quoted strings and ended the array at the first bracket in a comment; commit 19f974c replaced it, and the spec has tests for exactly that case and for single-quoted features. Adding to a multi-line array reuses the indent of the last item; removing swallows the neighbouring comma.'),
    ...code('lua', r'lua/config/crate_features.lua · lines 1195-1204', r'''
function M.edit_manifest(text, spec, op, features)
  local lines = split_lines(text)
  local suffix = spec.workspace and "workspace.dependencies" or KIND_SECTION[spec.kind or "normal"]
  local want = suffix
  if spec.target and not spec.workspace then
    want = "target." .. norm_header(spec.target) .. "." .. suffix
  end
  local kp = key_pat(spec.key)
  local secs'''),
    ...para('--', r'edit_manifest finds the dependency in text, not through a TOML parser, because a parser would lose comments and layout. It builds the section name from the kind and target (dependencies, dev-dependencies, target.cfg.dependencies, or workspace.dependencies), splits the file into section ranges, and handles four shapes of entry: a [dependencies.serde] table, dotted keys (serde.features = [...]), an inline table, and a bare version string.'),
    ...code('lua', r'lua/config/crate_features.lua · lines 1296-1303', r'''
              local inner = tbl:sub(2, -2):gsub("%s+$", "")
              local ins
              if inner:match("^%s*$") then
                ins = '{ features = ["' .. f .. '"] }'
              else
                ins = "{" .. inner .. (inner:match(",$") and "" or ",") .. ' features = ["' .. f .. '"] }'
              end
              return cur:sub(1, abs - 1) .. ins .. cur:sub(e + 1)'''),
    ...para('--', r'The inline-table and string cases are the ones people write most. A bare serde = "1" becomes { version = "1", features = ["derive"] }; an inline table without features gets the key appended with a comma only when needed. What it cannot do, it reports as a reason string and does not guess: dependency is not declared in this manifest, cannot read the dependency entry, already enabled, feature not declared (for a remove). The final loop over features applies them one by one on the evolving text.'),
    ...sec(r'applying an edit safely'),
    ...code('lua', r'lua/config/crate_features.lua · lines 1343-1346', r'''
  -- a symlinked Cargo.toml: rename onto the real file, or the link is replaced by a copy
  path = vim.uv.fs_realpath(path) or path
  local tmp = ("%s.%d.tmp"):format(path, vim.uv.os_getpid())
  local f = io.open(tmp, "wb")'''),
    ...para('--', r'write_all is small but carries two decisions. A symlinked Cargo.toml is resolved with fs_realpath first, so the rename lands on the real file and the link is not replaced by a copy (a fix from commit 19f974c, with its own spec). The file mode is copied to the temporary file before the rename. The rename goes through fsutil.rename (ff1c8fa, the portability commit, which replaced a raw fs_rename).'),
    ...code('lua', r'lua/config/crate_features.lua · lines 1376-1386', r'''
local function after_edit(manifest)
  cm.invalidate()
  -- the edit did not go through a buffer save: restart bacon-ls like a save of Cargo.toml would
  pcall(require("config.rust_restart").manifest_saved, manifest)
  -- an open, unmodified Cargo.toml buffer picks the new text up
  pcall(vim.cmd, "silent! checktime")
end

--- Switch features of the dependency entry `d` (a cargo metadata dependency of
--- crate_meta) on or off in its member's Cargo.toml. cb(ok, how_or_err), how =
--- "cargo add" | "text edit".'''),
    ...para('--', r'After any manifest edit that did not pass through a buffer save, after_edit invalidates the metadata, tells rust_restart that Cargo.toml was saved (so bacon-ls restarts as it would after a real save) and runs checktime so an open buffer picks the text up. set_features refuses to start when the manifest buffer has unsaved changes, and decides the route: switching off, a renamed dependency or a non-registry source go straight to the text edit.'),
    ...code('lua', r'lua/config/crate_features.lua · lines 1442-1464', r'''
    local all = now ~= before
    for _, f in ipairs(features) do
      all = all and now:find('"' .. f .. '"', 1, true) ~= nil
    end
    if all then
      after_edit(manifest)
      return cb(true, "cargo add")
    end
    text_edit()
  end
  cm.exec(argv(true), { cwd = vim.fs.dirname(manifest), timeout = 60000 }, function(r1)
    if r1.code == 0 then
      return done_ok()
    end
    cm.exec(argv(false), { cwd = vim.fs.dirname(manifest), timeout = 60000 }, function(r2)
      if r2.code == 0 then
        return done_ok()
      end
      text_edit() -- cargo add refused or is missing: edit the text
    end)
  end)
end'''),
    ...para('--', r'For the registry route it runs cargo add with an argv list, offline first and then online, adding --dev, --build or --target to match the kind. After a zero exit done_ok verifies that the manifest changed and that every feature string appears, and otherwise falls back to the text edit, which is the case when cargo add succeeds but changes nothing because the dependency is declared with workspace = true. If cargo is missing or refuses, text edit again. The callback receives "cargo add" or "text edit" as the how, shown in the notification.'),
    ...sec(r'an LSP server that lives inside the editor'),
    ...code('lua', r'lua/config/crate_features.lua · lines 1558-1580', r'''
  function srv.request(method, params, callback)
    next_id = next_id + 1
    local id = next_id
    if method == "initialize" then
      callback(nil, {
        capabilities = {
          codeActionProvider = { codeActionKinds = { "quickfix" } },
          executeCommandProvider = { commands = { M.command } },
        },
        serverInfo = { name = M.client_name },
      })
    elseif method == "textDocument/codeAction" then
      local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
      local diags = collect_diags(bufnr, params.range.start.line, params.range["end"].line)
      M.suggest_async(bufnr, diags, function(list)
        callback(nil, vim.tbl_map(action_of, list))
      end)
    elseif method == "workspace/executeCommand" then
      local arg = params.arguments and params.arguments[1]
      if params.command ~= M.command or type(arg) ~= "table" or not valid_features(arg.features) or not cm.valid_name(arg.crate or "") then
        return callback({ code = -32602, message = "bad arguments" }), id
      end
      M.apply(arg, function(ok, how)'''),
    ...para('--', r'The action is delivered the way users already expect, in the normal code-action menu, by a tiny in-process LSP server. make_server returns the table Neovim calls for cmd. initialize advertises a quickfix code action provider and one executeCommand; textDocument/codeAction collects the diagnostics that overlap the requested range and answers with the suggestions as actions; executeCommand revalidates the arguments (feature list and crate name again) before applying. Diagnostics from other servers are read with vim.diagnostic.get, so it works with rust-analyzer and bacon-ls alike.'),
    ...code('lua', r'lua/config/crate_features.lua · lines 1546-1556', r'''
local function make_server(dispatchers)
  local closing = false
  local next_id = 0
  local srv = {}
  -- on_exit exactly once, from exit and from terminate: a client that never
  -- reports it stays in vim.lsp.get_clients() as a stopped entry
  local function close()
    if not closing then
      closing = true
      dispatchers.on_exit(0, 0)
    end'''),
    ...para('--', r'The lifecycle fix is from b474307 (field test fixes): close() reports on_exit exactly once, from either exit or terminate. The comment explains the symptom: a client that never reports its exit stays in vim.lsp.get_clients as a stopped entry. attach starts or reuses the client per root with vim.lsp.start inside pcall, only for normal file buffers, and the spec has a case named after this bug.'),
    ...para('--', r'fix_at_cursor is the no-menu path: it applies the only suggestion on the cursor line, offers vim.ui.select when there are several, and says so when there is none. In this repository it is bound to <leader>rG.'),
    ...sec(r'the explorer'),
    ...code('lua', r'lua/config/crate_features.lua · lines 1724-1739', r'''
    local used = false
    for _, it in ipairs(items) do
      used = used or words[it] == true
    end
    list[#list + 1] = {
      name = f,
      declared = declared[f] or false,
      on = on[f] and true or false,
      via_default = d.uses_default_features and default_set[f] and not declared[f] or false,
      unified = on[f] == "unified",
      implicit = is_implicit(ft, f),
      in_default = default_set[f] or false,
      implies = implies,
      items = items,
      unused = (declared[f] or false) and #items > 0 and not used,
    }'''),
    ...para('--', r'explore builds the model the picker shows. For every item in the scan it resolves the gate against an empty enabled set, which gives the features that unlock it from scratch. For each feature it records whether it is declared in this manifest, effectively on (including features unified from other crates, marked separately), in the default set, what it implies, and what it unlocks. The unused? hint is deliberately modest: a declared feature is flagged only when it unlocks some item and none of those names appears among the words of the workspace sources (workspace_words reads at most 400 files and 4 MB, cached 30 seconds). The preview says the same in words, and says when a scan was capped.'),
    ...para('--', r'feature_line is the whole vocabulary of the list: [x] declared here, [~] on but not declared (by default, implied, or unified from another crate), [ ] off, then default, what it unlocks (four names and a count) and unused?.'),
    ...code('lua', r'lua/config/crate_features.lua · lines 1881-1903', r'''
local function toggle_feature(info, f)
  local d = info.dep
  local features = { f.name }
  -- declared in this manifest: remove it; anything else (off, on by default,
  -- implied, unified from another crate) is switched on by declaring it
  local turn_on = not f.declared
  M.set_features(d, features, turn_on, function(ok, how)
    if ok then
      vim.notify(("%s feature `%s` of `%s` (%s)"):format(turn_on and "Enabled" or "Disabled", f.name, info.crate, how), vim.log.levels.INFO)
    else
      vim.notify(("Cannot %s `%s`: %s"):format(turn_on and "enable" or "disable", f.name, how or "?"), vim.log.levels.WARN)
    end
    -- the manifest changed: show the list again with fresh metadata
    cm.metadata_async(info.root, function(meta)
      if meta then
        local nd = find_dep(meta, { member = d.member, kind = d.kind, crate = d.name, target = d.target })
        if nd then
          open_features(meta, nd, info.root)
        end
      end
    end, { refresh = true })
  end)
end'''),
    ...para('--', r'The picker is replaceable: M.pick uses Snacks.picker when it is loaded and falls back to vim.ui.select, and the specs replace it. The comment on preview = "none" records a field-test bug: the default preview tries to show item.file and produced an error plus a table dump for these items (19f974c). Toggling follows one rule stated in a comment: a feature declared in this manifest is removed; anything else (off, on by default, implied, unified) is switched on by declaring it. After the edit the metadata is refreshed and the list is reopened, so the marks are current.'),
    ...sec(r'setup and keys'),
    ...code('lua', r'lua/config/crate_features.lua · lines 1989-1993, 2012-2027', r'''
function M.on_rust_buffer(buf)
  M.attach(buf)
  vim.keymap.set("n", "<leader>rG", M.fix_at_cursor, { buffer = buf, desc = "Fix missing crate feature" })
end

...

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "rust",
    callback = function(ev)
      M.on_rust_buffer(ev.buf)
    end,
  })
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "rust" then
      M.on_rust_buffer(b)
    end
  end
end

return M'''),
    ...para('--', r'setup is guarded by a flag, creates :CrateFeatures with completion from the workspace dependencies, and attaches the client to every Rust buffer, current and future. In this repository the key is hard wired: on_rust_buffer maps <leader>rG buffer-locally. The comment records how the key was chosen: free of every global and Rust mapping of this config, with <leader>rE already taken by Open docs. It is loaded from lua/plugins/crate-features.lua as an init function of a lazy spec for nvim-lspconfig marked optional.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/crate-features_spec.lua has groups for cfg parsing and use trees; the source scan (re-exports, wrapper macros, modules, globs, macro_export; a cap on files; a crate with no lib.rs); feature resolution (implicit feature mapping, implied features dropped, already enabled, cheapest alternative, enabled set); diagnostic wording from the three tools; Cargo.toml edits (string to inline table, multi-line arrays keeping layout and comments, table and dotted forms, kinds and targets, renames and quoted keys, removal, reported reasons); set_features with a faked cargo (argv, offline first, dev/build/target, fallback, refusal of bad names and unsaved manifests); real crates (serde, clap, tokio); an acceptance test on the deps-lab-nofeature fixture where applying the action makes cargo check succeed; the command, the key and the toggle; and the review-fix and client-lifecycle cases.'),
    ...sec(r'history'),
    ...pt('--', r'b9363cd · 2026-10-14', r'added with crate_add, import engine and macro tools'),
    ...pt('--', r'19f974c · 2026-10-15', r'review: comment-aware array walk, literal strings, symlinked manifest, bacon-ls restart, picker preview'),
    ...pt('--', r'b474307 · 2026-10-15', r'field test: report on_exit once'),
    ...pt('--', r'ff1c8fa · 2026-10-16', r'portability: rename through fsutil'),
    ...sec(r'the same file in xyno-crates.nvim'),
    ...para('--', r'On 2026-10-22 the module was extracted to xyno-crates.nvim as lua/xyno_crates/crate_features.lua. The scanner, the gates, the editor and the explorer are unchanged. A diff shows only these differences. The LSP client is named xyno-features and the command xyno.enable_feature instead of xynovim-features and xynovim.enable_feature. Requires of config.crate_meta, config.fsutil and config.rust_restart become xyno_rust.crate_meta, xyno_rust.fsutil and xyno_rust.rust_restart. The hard-wired key is gone: on_rust_buffer maps the fix key only when setup received a string for it (xyno_crates passes keymaps.fix, off by default, with the default key suggested as <leader>rG), and the command is created only when opts.commands is not false. The autocommand group is renamed xyno_crates_features. The setup function takes an opts table and the first call wins.'),
  ],
);
