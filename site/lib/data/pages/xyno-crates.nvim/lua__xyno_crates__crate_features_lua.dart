import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-crates.nvim/lua/xyno_crates/crate_features.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'crate_features.lua — "cannot find derive macro Serialize": which feature, exactly?'),
    cm('--', r'a mini Rust source scanner, a DNF over cfg gates, and a Cargo.toml editor that keeps your comments'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'missing-feature code action, :CrateFeatures explorer, manifest feature editor'),
    kv(r'language', r'Lua (Neovim 0.12+); no tree-sitter here, a hand-written scanner'),
    kv(r'size', r'2034 lines, the largest file of the plugin'),
    kv(r'reads', r'unpacked crate sources in the cargo registry, cargo metadata, Cargo.toml text'),
    kv(r'config', r'max_files 150, max_file_bytes 600 KB, max_unused_files 400, max_unused_bytes 4 MB, max_alts 32'),
    kv(r'history', r'xynovim b9363cd (2026-10-14) at 2018 lines, three small fixes after, extracted 5cd9905 (2026-10-22)'),
    ...sec(r'why this file exists'),
    ...para('--', r'Add serde = "1" to a manifest, write #[derive(Serialize)], and rustc answers: cannot find derive macro `Serialize` in this scope. Nothing in the message says that serde has a feature called derive which is off. xynovim’s assessment calls this gap G4, "A missing crate feature is silent": the code actions on that line were Convert to manual impl, Wrap in cfg_attr and Generate impl, none of which enables the feature, and the stated cost was that nothing told you derive was off. The spec on real crates checks the same shape with clap and Parser (needs derive) and tokio and main (needs macros).'),
    blank,
    ...para('--', r'The idea of the file is that the answer is already on your disk. cargo has unpacked the crate source under ~/.cargo/registry. In that source, Serialize is exported by a pub use behind #[cfg(feature = "...")]. So the module reads the crate’s own source to find the name and the gate in front of it, resolves the gate through the [features] table, and offers "Enable feature `derive` of `serde`". It is the longest source file of the plugin (2034 lines) and has to be a small parser, a small boolean algebra and a careful text editor at once.'),
    blank,
    ...sec(r'step 1: gates are boolean formulas in disjunctive normal form'),
    ...code('lua', r'lua/xyno_crates/crate_features.lua · lines 45-47, 55-68', r'''
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
    ...para('--', r'A gate is a list of alternatives, each a set of features that must all be on: {} is "never", { {} } is "always". That is disjunctive normal form, and the whole file speaks it. and_gate multiplies two gates (all alternatives pairwise), or_gate concatenates them, and both stop at max_alts (32) so a pathological cfg cannot explode. The cap is a design decision about failure: past it you lose alternatives (a missed suggestion), never correctness.'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_features.lua · lines 110-136', r'''
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
      g = or_gate(g, M.parse_cfg(a))
    end
    return g
  elseif op == "not" then
    return ALWAYS
  end
  if e == "test" then
    return {}
  end
  return ALWAYS
end'''),
    ...para('--', r'parse_cfg reads what is inside cfg(...). Only feature = "x" creates a requirement. all() is AND, any() is OR. The rest is a deliberate simplification stated in the comment: not(..) and the other predicates (unix, docsrs, target_*) are treated as true, and test as false, because test modules are no API. Treating not(feature = "x") as always is the optimistic reading for a tool whose job is to find a feature to turn on; the spec pins the behaviour: not() yields the empty requirement.'),
    blank,
    ...sec(r'step 2: scan the crate source without a Rust parser'),
    ...para('--', r'There is no tree-sitter here and no regular expression over the whole file. strip() removes comments while keeping strings (the features are in them), and it knows raw strings, nested block comments, and char literals versus lifetimes. close_of() matches brackets the same careful way, and item_end() finds where an item stops, with a special case for const and static whose initialiser may contain braces. The scan test in the spec has an assertion for each of these, with the messages "a const initialised with a struct literal ends at its ;", "Item = u8 in a bound does not swallow the next items", "a commented-out item is no item".'),
    blank,
    ...para('--', r'scan_dir then walks parse_region over lib.rs. For each item it keeps a state: the accumulated gate (the AND of every cfg on the way down, including the cfg of enclosing modules), the module path, and pubchain, meaning every module on the way is pub so the item is reachable from outside. Items are recorded under their name with their gate and a reach flag. Modules are followed into files (name.rs, name/mod.rs, or a #[path] attribute that is rejected if it contains ".." or starts with a slash), up to max_files (150) files of at most 600 KB, and the result says truncated = true when it stopped early.'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_features.lua · lines 429-436, 647-657', r'''
  for attr in seg:gmatch("#%s*(%b[])") do
    local cfg = attr:match("^%[%s*cfg%s*(%b())%s*%]$")
    if cfg then
      g = and_gate(g, M.parse_cfg(cfg:sub(2, -2)))
      found = true
    end
  end
  return found and g or nil
...
      elseif word and t:sub(wend, wend) == "!" then
        -- a macro call; a wrapper macro's body is parsed with its gate (later,
        -- once every file is read: the definition may come after the use)
        local b = skip_ws(t, wend + 1, lim)
        local e = t:sub(b, b):match("[{%(%[]") and close_of(t, b)
        if e then
          ctx.pending[#ctx.pending + 1] = { name = word, t = t, s = b + 1, e = e - 1, st = st, gate = gate }
          p = e + 1
        else
          p = item_end(t, wend, lim)
        end'''),
    ...para('--', r'Crates can hide gates in their own macros; the header mentions the crate’s own cfg_xxx! { .. } wrapper macros, and the spec’s fake crate imitates tokio with cfg_macros! and cfg_rt!. wrapper_gate extracts that gate from the definition, and a call to a known wrapper is parsed later, once all files are read, because the definition may come after the use. Nested wrappers combine with AND, so the spec expects the fake crate’s spawn to need macros+rt and spawn_mt macros+rt+rt-multi-thread. After the walk, pub use m::* globs copy the items of module m into the importing level with the glob’s own gate.'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_features.lua · lines 730-751', r'''
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
    ...para('--', r'gate_of answers the question the action needs. It prefers candidates that are reachable from outside the crate, returns "not found" when no item has the name, and "ungated" the moment any alternative is the empty set, since then no feature is needed and a feature suggestion would be wrong. Otherwise it ORs the gates of all candidates. The cache scans[dir] is keyed by directory and stamped with the mtime of lib.rs: a registry crate never changes, a path dependency is re-read when its lib.rs does.'),
    blank,
    ...sec(r'step 3: from the gate to the smallest list of features'),
    ...para('--', r'Cargo makes every optional dependency an implicit feature. In serde, the gate on Serialize is feature = "serde_derive", but nobody enables serde_derive; they enable derive, which is declared as derive = ["serde_derive"]. nice_feature maps the raw requirement back to the user-facing feature: the name itself if it is declared and not implicit, otherwise the declared feature whose closure contains it and is the smallest, ties broken alphabetically.'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_features.lua · lines 838-864', r'''
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
  return best.list'''),
    ...para('--', r'resolve works alternative by alternative. For each, it computes the missing features (those not in the enabled set), maps them through nice_feature, removes any feature already implied by another one in the list (reduce), and keys the result by length and name so the cheapest alternative wins. If an alternative has nothing missing it returns nil, "enabled": the name is not missing because of a feature, so the module stays silent. This is the answer to a worry in any such tool, the false suggestion; the spec for it is "offers nothing when the feature is already on, for an item in no feature, or for no diagnostic".'),
    blank,
    ...sec(r'step 4: from diagnostics to names'),
    ...para('--', r'names_from_message reads the wording of rustc, rust-analyzer and bacon-ls: "cannot find ... `X`", "could not find `X` in `Y`", "unresolved import", "unresolved macro", "no `X` in the root", "failed to resolve: could not find". It keeps only identifiers, with the qualifier when the message has one. When a message has no name at all, diag_names looks at the source: if the line is an attribute and the diagnostic range is on one line, the identifier under the range is used, so #[tokio::main] works even when the message does not say main.'),
    blank,
    ...para('--', r'M.suggest then does the join. It restricts to the dependencies of the file’s member, sorts so the kind the file belongs to comes first (a test file reads dev-dependencies too), and, when the file mentions the name through a crate (use serde::..., qualifier match, alias), narrows to those dependencies. For each candidate it locates the unpacked source (metadata first, registry second), scans, resolves, and merges duplicates so one action can cover several names. Output: member, manifest, kind, target, features, and a truncated flag.'),
    blank,
    ...sec(r'step 5: editing Cargo.toml without destroying it'),
    ...para('--', r'The header states the policy: cargo add --features for registry dependencies when a feature is switched on, a careful text edit for everything else (switching off, renamed, path and git dependencies, and when cargo add changed nothing). The text editor is the part where a lazy implementation would round-trip the file through a TOML library and lose every comment and the user’s formatting. edit_manifest instead finds the right section by name (dependencies, dev-dependencies, build-dependencies, workspace.dependencies, target.<cfg>.<table>), handles the four ways a dependency can be written, and changes the minimum number of characters.'),
    blank,
    ...para('--', r'array_edit walks the array once. It treats both "basic" and literal strings as items, skips # comments (which may contain [ or ]), and ends at the matching bracket. That loop replaced an earlier version in the review commit 19f974c, which found items with a pattern over the inner text and was therefore fooled by brackets in comments and by single-quoted features. Both are now specs ("a comment with brackets inside the features array does not end it early", "single-quoted features are items and are kept").'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_features.lua · lines 1160-1172', r'''
    local last = items[#items]
    local ins
    if inner:find("\n", 1, true) then
      local ls = last.s
      while ls > 1 and text:sub(ls - 1, ls - 1) ~= "\n" do
        ls = ls - 1
      end
      local indent = text:sub(ls, last.s - 1):match("^%s*") or "  "
      ins = ",\n" .. indent .. q
    else
      ins = ", " .. q
    end
    return text:sub(1, last.e) .. ins .. text:sub(last.e + 1)'''),
    ...para('--', r'Adding to a multi-line array copies the indentation of the last item and appends after it, so a layout like features = [ with each item on a line and a trailing comma stays as written. The other cases are handled in edit_manifest: a version string "1" becomes { version = "1", features = ["derive"] } with a trailing comment preserved, an inline table gains a features key (or its array grows), the table form [dependencies.serde] gains a features line, the dotted form serde.workspace = true gains serde.features. The function never guesses: when the dependency is not in this manifest, or the feature is already there, it returns nil and a reason ("dependency `x` is not declared in this manifest", "already enabled in this manifest").'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_features.lua · lines 1420-1423, 1452-1462', r'''
  local registry = d.source and d.source:match("^registry") ~= nil
  if not on or d.rename or not registry then
    return vim.schedule(text_edit)
  end
...
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
  end)'''),
    ...para('--', r'set_features chooses the strategy. Switching off, a renamed dependency or a non-registry source go straight to the text edit. A registry dependency being switched on tries cargo add --offline first, then online, then falls back to the text edit if cargo refuses or is missing; done_ok accepts the cargo result only if the file changed and every feature appears in the new text, otherwise it also falls back. An unsaved Cargo.toml buffer is refused with "save it first", and writes go through a temp file and rename onto the real path, so a symlinked manifest stays a symlink (fix 19f974c, with a spec). After every edit, rust_restart.manifest_saved runs for the same reason as in crate_add.'),
    blank,
    ...para('--', r'The workspace case is a design choice in the header: "workspace = true stays and gets the feature in the member’s own entry (additive), the workspace table is not touched." One member enabling derive must not change what the other members build with. The spec shows the result: serde = { workspace = true, features = ["derive"] } # c, and the workspace root byte-for-byte the same.'),
    blank,
    ...sec(r'the code action and the key'),
    ...para('--', r'A second in-process language client, named xyno-features, serves quickfix actions titled like "Enable feature `derive` of `serde`" (plural for several features). It is attached per Rust buffer with vim.lsp.start and a function as cmd. executeCommand validates the argument (valid_features, valid crate name) and answers an LSP error for bad arguments. The optional key calls fix_at_cursor: collect the diagnostics of the cursor line, apply directly when there is one suggestion, or vim.ui.select for several. As in crate_add, close() reports on_exit exactly once (b474307).'),
    blank,
    ...sec(r'the explorer: what does each feature unlock?'),
    ...code('lua', r'lua/xyno_crates/crate_features.lua · lines 1699-1710', r'''
  -- item -> the features that unlock it (from scratch)
  local unlocks = {}
  for name in pairs(idx.items) do
    local gate = M.gate_of(idx, name)
    if gate then
      local feats = M.resolve(gate, ft, {})
      for _, f in ipairs(feats or {}) do
        unlocks[f] = unlocks[f] or {}
        table.insert(unlocks[f], name)
      end
    end
  end'''),
    ...para('--', r'explore inverts the scan. For every scanned item name it resolves the gate from scratch (an empty enabled set), and files the name under each feature that unlocks it. The rest is bookkeeping: declared, on, on by default, implied, "unified" from another crate through the resolver, and an unused? flag for a declared feature none of whose items appears as a word in the workspace sources (workspace_words reads src, tests, examples, benches and build.rs, bounded by max_unused_files and bytes, cached for 30 seconds). The preview says so when the scan was capped. Toggling is symmetrical to the code action: a declared feature is removed; anything else (off, default, implied, unified) is switched on by declaring it, then the metadata is reloaded with refresh = true and the list reopens with fresh state.'),
    blank,
    ...para('--', r':CrateFeatures with one match opens its list directly, with several shows a dependency picker, and completes crate names from the metadata.'),
    blank,
    ...para('--', r'One detail to know: this picker looks for the Snacks global with rawget(_G, "Snacks"), where crate_add’s pickers use require("xyno_rust.deps").snacks(). The README says :CrateFeatures falls back to vim.ui.select(); the code does so whenever the global is absent. The diff against the xynovim original does not touch this spot, so it behaved the same there.'),
    blank,
    ...sec(r'how it is tested'),
    ...para('--', r'tests/crate-features_spec.lua (865 lines) is the most structured spec of the three. It builds a fake registry crate in a temp directory that contains every hard case at once: a derive-style re-export behind an optional dependency, a tokio-style cfg wrapper macro, a gated module, a glob re-export, a macro_export macro, a commented-out decoy and a cfg(test) item. Then it asserts the gate of about twenty names. Further groups cover cfg parsing, resolution, diagnostic wording, eight groups of manifest-edit cases (with exact before and after strings), set_features with a faked cm.exec (argv lists, offline first, fallbacks, refusals), real crates (serde, clap, tokio from the deps-lab fixtures, skipped with a reason when the registry lacks them offline), and an acceptance test on deps-lab-nofeature that applies the code action and then runs cargo check --offline.'),
    blank,
    ...sec(r'history'),
    ...pt('--', r'b9363cd, 2026-10-14', r'added to xynovim at 2018 lines, in the "Macros and dependencies" commit, together with its plan row 1.3.'),
    ...pt('--', r'19f974c, 2026-10-15', r'review fixes: array_edit rewritten for comments and single quotes, symlinked manifests, manifest_saved after edits, preview "none" for the picker.'),
    ...pt('--', r'b474307, 2026-10-15', r'the client now reports on_exit once.'),
    ...pt('--', r'ff1c8fa, 2026-10-16', r'the temp-file rename goes through fsutil.rename (Windows and macOS portability commit).'),
    ...pt('--', r'5cd9905, 2026-10-22', r'extraction: names (xyno-features, xyno.enable_feature, xyno_crates_features), requires, the opt-in key and the commands switch. 57 differing lines of 2034.'),
  ],
);
