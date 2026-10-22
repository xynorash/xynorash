import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-imports.nvim/lua/xyno_imports/engine.lua',
  lines: [
    cm(r'''--''', r'''──────────────────────────────────────────'''),
    cm(r'''--''', r'''engine.lua — the whole plugin: scan, ask, rank, remember, apply'''),
    cm(r'''--''', r'''a 1,705-line module that turns "cannot find type" into one keystroke'''),
    cm(r'''--''', r'''──────────────────────────────────────────'''),
    blank,
    kv(r'''role''', r'''everything except option handling: scan, rank, memory, flow, organize, triggers'''),
    kv(r'''language''', r'''Lua (Neovim 0.12 APIs: vim.system, vim.uv, vim.treesitter, vim.lsp)'''),
    kv(r'''size''', r'''1,705 lines; the xynovim original ended at 1,689'''),
    kv(r'''depends on''', r'''xyno_rust.code_actions, xyno_rust.crate_meta, xyno_rust.fsutil'''),
    kv(r'''state''', r'''stdpath("state")/xyno-imports/imports.json, one map per workspace root'''),
    kv(r'''tested by''', r'''tests/engine_spec.lua, 820 lines, fake and real rust-analyzer'''),
    ...sec(r'''why this file exists'''),
    ...para(r'''--''', r'''rust-analyzer already knows how to fix an unresolved name: it offers a quickfix titled Import `std::io::Error`. What it does not do is decide for you, remember what you decided last time, or notice the unresolved name without being asked. This file is the layer that does those three things. It never builds a use line itself; every edit that reaches the buffer is a code action rust-analyzer produced.'''),
    blank,
    ...para(r'''--''', r'''The file began as lua/config/import_engine.lua in xynovim. It arrived whole on 2026-10-14 (b9363cd, 1,661 lines) inside a large commit about macros and dependencies, then got small commits: dc846f6 (a ripgrep-less fallback), 19f974c and b474307 on 10-15 (review and field-test fixes) and ff1c8fa on 10-16 (a Windows rename helper). On 2026-10-22 it was copied here as 0e6c052. The diff between the two final versions is namespaces, options and opt-in keymaps: the engine is the code that ran in the config.'''),
    blank,
    ...sec(r'''the shape of the file'''),
    ...para(r'''--''', r'''One table M, cut into labelled sections: memory, use paths, candidates, scoring, tree-sitter bits, use index, facts, sources, asking the server, applying, :ImportName, organize, triggers, setup. Pure functions come first (flatten_use, parse_title, score, rank, decide) and are exported so the spec can call them without a buffer. The header states the contract in one place.'''),
    blank,
    ...sec(r'''memory: a choice you made once stays made'''),
    ...para(r'''--''', r'''The memory is a table root -> { name -> path }, loaded lazily from a JSON file. The decision worth noticing is validation: data read from disk is not trusted. A name must match ^[%w_]+$ and a path ^[%w_]+[%w_:]*$ or the pair is dropped, and remember() applies the same check. The spec writes a file containing "x::Bad; rm -rf" and expects it to vanish. Saving writes a temp file named with the process id and renames it over the target through xyno_rust.fsutil.rename, which retries on Windows when another process holds the file (ff1c8fa).'''),
    blank,
    ...code('lua', r'lua/xyno_imports/engine.lua · lines 94-107', r'''
    local ok, data = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
    if ok and type(data) == "table" then
      for root, names in pairs(data) do
        if type(root) == "string" and type(names) == "table" then
          memory[root] = {}
          for name, path in pairs(names) do
            -- from a file: only plain identifiers and paths are ever used
            if type(name) == "string" and name:match("^[%w_]+$") and type(path) == "string" and path:match("^[%w_]+[%w_:]*$") then
              memory[root][name] = path
            end
          end
        end
      end
    end'''),

    ...sec(r'''reading use statements without a Rust parser'''),
    ...para(r'''--''', r'''Scoring needs the paths the project already imports, from every .rs file under the root, far more than are ever open. So use statements are read with a small tokenizer and a recursive descent over the brace tree, not tree-sitter. flatten_use turns use a::{b, c::{self, d as e}}; into a::b, a::c, a::c::d: braces expanded, self folded into its parent, aliases dropped, globs kept as ::*. Comments are stripped first. It is a heuristic and the spec pins the cases that matter, including a commented use and a variable called use_it.'''),
    blank,
    ...code('lua', r'lua/xyno_imports/engine.lua · lines 257-263', r'''
function M.flatten_use(stmt)
  local body = strip_comments(stmt)
  body = body:gsub("^%s*pub%s*%b()", ""):gsub("^%s*pub%s+", ""):gsub("^%s*use%s+", ""):gsub("%s*;%s*$", "")
  local out = {}
  parse_tree(tokenize(body), 1, {}, out)
  return out
end'''),

    ...sec(r'''scoring: what the project already does'''),
    ...para(r'''--''', r'''This is the ranked choice. Each candidate gets a number and a list of reasons, and the reasons are what the picker prints, so the ranking is never a black box. An exact use of the path counts 4 in this file, 3 in sibling modules, 2 elsewhere in the crate, capped at 5 occurrences per tier so one file full of the same import cannot outvote everything. A use from the same parent module counts half. The spec shows the consequence: two crate uses (4) beat one sibling use (3), and a file use (4) loses to two sibling uses (6). Counting rewards repetition, not mere presence.'''),
    blank,
    ...code('lua', r'lua/xyno_imports/engine.lua · lines 311-311, 333-344', r'''
M.weights = { file = 4, sibling = 3, crate = 2, near = 0.5, cap = 5 }
...
local function count_in(paths, cand)
  local W = M.weights
  local exact, near = 0, 0
  for _, p in ipairs(paths or {}) do
    if p == cand.path or vim.startswith(p, cand.path .. "::") then
      exact = exact + 1
    elseif cand.parent ~= "" and (p:match("^(.*)::[^:]+$") or "") == cand.parent then
      near = near + 1
    end
  end
  return math.min(exact, W.cap), math.min(near, W.cap)
end'''),

    ...para(r'''--''', r'''Context rules follow, each a flat bonus with a reason string. Inside #[derive( a proc-macro crate gains 10 and std loses 4, which is what lets a derive-macro candidate from a proc-macro crate outrank the std one. In an error position names ending in Error gain 5; a function returning io::Result gives 8 to candidates from io. A trait where a trait is expected gains 5. A std item that a dependency also offers loses 3, a core or alloc twin of std loses 2, a candidate that would need a new crate loses 5, and the order in Cargo.toml adds at most one point as a tie-breaker.'''),
    blank,
    ...code('lua', r'lua/xyno_imports/engine.lua · lines 370-376, 380-385, 401-403', r'''
  if ctx.derive then
    if facts.proc_macro and facts.proc_macro[cand.crate] then
      add(10, "derive macro of a proc-macro crate")
    elseif is_std then
      add(-4, "std items are not derive macros")
    end
  end
...
  if ctx.ret and ctx.ret.mod then
    local parent_last = cand.parent:match("([^:]+)$")
    if parent_last == ctx.ret.mod or cand.crate == ctx.ret.mod then
      add(8, ("matches the return type `%s::Result`"):format(ctx.ret.mod))
    end
  end
...
  if cand.add_crate then
    add(-5, "not a dependency yet")
  end'''),

    ...para(r'''--''', r'''Every number is a judgement, not a measurement, and nothing in the repository claims otherwise. What the code does guarantee is determinism: rank() sorts by score and breaks ties by path, so the same facts give the same order. The spec "breaks ties by dependency order, then by path" locks that in.'''),
    blank,
    ...sec(r'''deciding without guessing'''),
    ...para(r'''--''', r'''decide() is the policy in a few lines. A remembered choice wins, but only if the server still offers it, so a stale memory never yields an import rust-analyzer would not make. Otherwise the only automatic case is exactly one candidate. Several candidates give "pick", which the automatic flow treats as do nothing, leaving the choice to :ImportName. Candidates marked add_crate are excluded from the count of real candidates, so a source suggesting a new dependency can never turn an ambiguous name into an automatic import.'''),
    blank,
    ...code('lua', r'lua/xyno_imports/engine.lua · lines 451-451, 459-461, 465-467', r'''
  local pick, why
...
  if not pick and #real == 1 and #cands == 1 then
    pick, why = real[1], "single"
  end
...
  if #cands == 0 then
    return { act = "none" }
  end'''),

    ...sec(r'''finding names that resolve to nothing'''),
    ...para(r'''--''', r'''Two scanners run and are merged. The diagnostic scanner trusts rust-analyzer and the clippy tier: a message containing "cannot find", "undeclared", "failed to resolve" or "unresolved", except "unresolved import", names a position. The syntax scanner exists because diagnostics lag right after you type. It is a deliberate superset: type identifiers and path heads in the changed rows minus everything the file declares, imports, binds as a generic, or finds in the prelude. The language server vetoes the rest by offering nothing to import.'''),
    blank,
    ...para(r'''--''', r'''Three guards matter. Buffers above max_lines (20,000) are skipped because the scan reads the whole buffer per edit, added in b474307. The whole-buffer part is memoised per buffer by changedtick, the first review fix in 19f974c. And single capitals such as T or T1 are never reported, since they are nearly always generics. Lowercase heads like io::Error are reported only when cargo metadata says the head is unknown.'''),
    blank,
    ...code('lua', r'lua/xyno_imports/engine.lua · lines 637-654, 667-667', r'''
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local memo = known_memo[buf]
  local known
  if memo and memo.tick == tick then
    known = memo.known
  else
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    known = declared_names(text)
    for _, p in ipairs(M.use_paths(text)) do
      known[p:match("([%w_]+)$") or p] = true
      -- a glob import may bring anything: nothing is "unresolved" by syntax then
    end
    for _, gq in ipairs(generic_queries()) do
      for _, node in gq:iter_captures(root, buf, 0, -1) do
        known[node_text(node, buf)] = true
      end
    end
    known_memo[buf] = { tick = tick, known = known }
...
      ok = not name:match("^%u%d?$")'''),

    ...sec(r'''the use index: learning from the whole crate'''),
    ...para(r'''--''', r'''use_index asks ripgrep for every use statement as JSON with a multiline pattern, so a statement spread over several lines still matches whole. The argv is a list, never a shell string; files over 1 MB and target/ are skipped; the result is cached per root. If rg is missing, exits with a code other than 0 or 1, or cannot be spawned, a Lua walk takes over, capped at 3,000 files and depth 8.'''),
    blank,
    ...para(r'''--''', r'''The fallback has a story. dc846f6 (18 minutes after the engine landed) fixed a skip predicate that compared the whole path instead of the base name and had the polarity wrong, since for vim.fs.dir a true return means descend. The comment that records this survived into the plugin.'''),
    blank,
    ...para(r'''--''', r'''Invalidation is coarse on purpose. A save of any .rs file clears every root, and the next resolve rebuilds. That is one ripgrep run per edit session instead of tracking which file changed.'''),
    blank,
    ...sec(r'''facts and sources'''),
    ...para(r'''--''', r'''facts_async assembles what score() reads: the context at the position, the use paths of the buffer, of sibling files (same directory) and of crate files (under the nearest Cargo.toml), the order of the normal dependencies of the owning workspace member, and which dependencies are proc-macro crates (read from their manifests). It always calls back; what cannot be read is left out, so ranking degrades to fewer signals instead of failing.'''),
    blank,
    ...para(r'''--''', r'''register_source is the extension point. A source returns { path, crate, add_crate, apply } tables, optionally asynchronously. xynovim used it for a crates.io lookup, Add crate X and import; that part is not in this plugin. Every returned path is validated with the memory pattern, duplicates of the server answer are dropped, a throwing source is wrapped in pcall, and an async source is cut off after source_wait_ms (4 seconds) by a timer and a finished flag.'''),
    blank,
    ...sec(r'''asking rust-analyzer, and being patient with it'''),
    ...para(r'''--''', r'''candidates_at sends a code action request restricted to quickfix, with the diagnostic attached when there is one. After an edit rust-analyzer answers ContentModified (-32801) or ServerCancelled (-32802) while it re-analyses, which is exactly the state after InsertLeave. busy() recognises both codes and the English message; the request is retried up to 5 times, 400 ms apart, and each retry re-checks that the buffer is still valid. Titles are parsed strictly and Import `x as _` loses its alias.'''),
    blank,
    ...sec(r'''the automatic flow: run()'''),
    ...para(r'''--''', r'''run() takes a row range, finds unresolved names (first occurrence of each, at most max_names = 8) and handles them one at a time. Two details carry the care. Positions are extmarks: importing the first name inserts a line at the top and shifts every other row, so each name keeps an extmark with right_gravity = false and is re-located before use; if the text under the mark changed, it is skipped. And every asynchronous hop re-checks changedtick, so an edit made while rust-analyzer was thinking cancels the stale action.'''),
    blank,
    ...code('lua', r'lua/xyno_imports/engine.lua · lines 1221-1221, 1244-1245', r'''
        p.mark = vim.api.nvim_buf_set_extmark(buf, ns, p.row, p.col, { end_col = p.end_col, right_gravity = false })
...
      if line:sub(cur.col + 1, cur.col + #p.name) ~= p.name then
        return nextp() -- the text under the mark was edited meanwhile'''),

    ...para(r'''--''', r'''The ask path is the product decision. It prompts only when the buffer is current and Neovim is in normal mode, so a dialog never opens over text being typed. It uses vim.fn.confirm, not echo plus getcharstr: the comment explains that a notification UI hid the old prompt after a few seconds while Neovim kept waiting, and the next key typed (":w") was taken as the answer (19f974c). If you typed while the question was open the yes is kept (p.answered) and the candidate is looked up again at the extmark. A no is cached for the session by root, name and path. Imports of one run are undojoined into one undo step.'''),
    blank,
    ...code('lua', r'lua/xyno_imports/engine.lua · lines 1273-1292', r'''
        if d.act == "ask" then
          if vim.api.nvim_get_current_buf() ~= buf or vim.fn.mode() ~= "n" then
            return nextp()
          end
          if p.answered or M.ask_key(d.cand, p.name) then
            if not p.answered and vim.api.nvim_buf_get_changedtick(buf) ~= tick then
              -- typed while the question was open: the candidate's edit is stale; look again
              -- at the extmark instead of dropping the yes
              p.answered = true
              i = i - 1
              return nextp()
            end
            apply()
          else
            dismissed[dkey(root, p.name, d.cand.path)] = true
            nextp()
          end
        else
          apply()
        end'''),

    ...sec(r'''the picker: :ImportName'''),
    ...para(r'''--''', r'''import_name resolves the word under the cursor, shows the candidates best first through vim.ui.select with the path, score and reasons, then applies and remembers the pick. A crate-adding guess is never remembered. A remembered choice leads the list and the rest keep ranked order. That detail has a history: the first version used table.sort with a comparator looking only at the remembered flag, and LuaJIT sort is not stable, which scrambled the rest. 19f974c replaced it with a partition into two lists; the last spec of engine_spec.lua pins it with six candidates.'''),
    blank,
    ...code('lua', r'lua/xyno_imports/engine.lua · lines 1359-1359, 1360-1364', r'''
        -- no table.sort: LuaJIT's is not stable and would scramble the ranked order
...
        local first, rest = {}, {}
        for _, c in ipairs(items) do
          table.insert(c.remembered and first or rest, c)
        end
        items = vim.list_extend(first, rest)'''),

    ...sec(r'''organize imports'''),
    ...para(r'''--''', r'''organize() composes its own routine from four assists matched by title (it also accepts any action of kind source.organizeImports). The comment records that the titles were measured on a given release and that some are offered only at a cursor inside a use. So organize_ranges builds an empty range at the path of every top-level use plus one range for the whole buffer, and the loop re-asks after each applied edit because the ranges moved.'''),
    blank,
    ...code('lua', r'lua/xyno_imports/engine.lua · lines 1393-1396, 1397-1397', r'''
-- Titles measured on rust-analyzer 1.99: "Merge imports" and "Normalize
-- import" (refactor.rewrite, offered at a cursor inside a `use`, not for a
-- selection of it), "Remove unnecessary braces" and "Remove all unused imports"
-- (quickfix, the latter for any range that holds an unused import).
...
local ORGANIZE = { "^Merge imports", "^Normalize import", "^Remove unnecessary braces", "^Remove all unused imports" }'''),

    ...para(r'''--''', r'''The loop is bounded by organize_rounds (30). An assist that fails or changes nothing goes into skipped under title plus use text, so it is not retried forever. When a round finds nothing, the function waits 800 ms once and looks again, because rust-analyzer may still be re-analysing. Every applied assist after the first uses join = true, so the command is one undo; the real-server spec undoes it and compares the buffer.'''),
    blank,
    ...sec(r'''triggers: when to look'''),
    ...para(r'''--''', r'''The triggers are the moments a name is finished: InsertLeave, a save, a paste. A buffer is tracked with nvim_buf_attach, whose on_lines callback widens a dirty row range, and only those rows are scanned. trigger() debounces with one libuv timer per buffer (600 ms), a running flag makes a second trigger wait, and eligible() requires a valid Rust buffer of normal type with mode not off.'''),
    blank,
    ...para(r'''--''', r'''Paste is its own case. Bracketed paste calls vim.paste, so the plugin wraps it once and triggers on phase -1 (single chunk) and 3 (end of a stream). A p, P or :put does not use vim.paste, so TextChanged covers it, limited to changes spanning more than one line, which tells a put from a keystroke.'''),
    blank,
    ...para(r'''--''', r'''The undo guard solves a loop that would be maddening: you accept an import, dislike it, press u, and the plugin imports it again. undo_guard compares the undo sequence with the one stored at the last import; if it went backwards, the name is dismissed for the session. The spec "triggers after InsertLeave and a save, debounced, and not again after an undo" covers it.'''),
    blank,
    ...sec(r'''setup, and what changed in the extraction'''),
    ...para(r'''--''', r'''setup() creates one augroup (cleared on each call), defines the commands unless commands = false, hooks FileType, InsertLeave, BufWritePost and TextChanged, wraps paste, and tracks Rust buffers already open. Three differences from the original show in the diff. The mode can now also be set by the setup option; the global vim.g.xyno_auto_import still overrides it. Keymaps are opt-in: xynovim mapped <leader>rI and <leader>rO itself, only on a free key and counting stub maps whose desc was which_key_ignore as free; that check belonged to its own keymaps.lua and the plugin maps nothing unless asked. And names carry the plugin prefix: namespace, augroup, state directory.'''),
    blank,
    ...sec(r'''design decisions and trade-offs'''),
    ...pt(r'''--''', r'''One file, no sub-modules''', r'''scoring, scanning, flow and triggers share local state (memory, caches, dismissed). Splitting needs an internal state module for little gain, and the pure functions are already exported for tests.'''),
    ...pt(r'''--''', r'''rust-analyzer does the editing''', r'''the plugin selects among server-made code actions, so merging into an existing use group and edition rules stay the server job.'''),
    ...pt(r'''--''', r'''Never silent by default''', r'''mode ask needs a keystroke; single is opt-in and still only for one candidate or a remembered choice.'''),
    ...pt(r'''--''', r'''Heuristics over parsing''', r'''the use reader and the scanners are approximate, and their errors cost a missed suggestion, not a wrong edit, because the server has the last word.'''),
    ...pt(r'''--''', r'''Stale-edit paranoia''', r'''changedtick checks at every asynchronous boundary, extmarks for positions, validity checks before callbacks.'''),
    ...sec(r'''how it is tested'''),
    ...para(r'''--''', r'''tests/engine_spec.lua covers the pure parts with table-driven cases, the memory against a temp state file, the scanners on real buffers, the flow against a fake rust-analyzer client, and acceptance cases against a real rust-analyzer on the deps-lab fixture, skipped with a printed reason when the server, cargo or the registry crates are missing. tests/init_spec.lua covers setup().'''),
    blank,
    ...sec(r'''history'''),
    ...pt(r'''--''', r'''b9363cd 2026-10-14''', r'''import_engine.lua enters xynovim, 1,661 lines.'''),
    ...pt(r'''--''', r'''dc846f6 2026-10-14''', r'''the use-index fallback walked no directories; the skip predicate was wrong.'''),
    ...pt(r'''--''', r'''19f974c 2026-10-15''', r'''review fixes: changedtick memo, dedup before context_at, confirm() prompt, answered state, stable partition.'''),
    ...pt(r'''--''', r'''b474307 2026-10-15''', r'''max_lines guard for the whole-buffer scan.'''),
    ...pt(r'''--''', r'''ff1c8fa 2026-10-16''', r'''fsutil.rename for the state file.'''),
    ...pt(r'''--''', r'''0e6c052 2026-10-22''', r'''the file arrives in xyno-imports.nvim with the changes above.'''),
  ],
);
