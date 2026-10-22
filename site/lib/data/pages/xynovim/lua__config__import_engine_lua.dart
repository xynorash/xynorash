import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/import_engine.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'import_engine.lua — imports without the menu'),
    cm('--', r'find the unresolved name, rank the candidates, remember the choice'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'auto-import, ranked disambiguation, organize imports for Rust'),
    kv(r'language', r'Lua for Neovim 0.12, treesitter (rust), rust-analyzer code actions'),
    kv(r'size', r'1689 lines, 5 commits (2026-10-14 to 2026-10-16)'),
    kv(r'spec', r'tests/import-engine_spec.lua (816 lines)'),
    kv(r'commands', r':ImportName, :ImportForget, :ImportOrganize, <leader>rI, <leader>rO'),
    kv(r'also lives in', r'xyno-imports.nvim as lua/xyno_imports/engine.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'In Rust you write the name first and the use line afterwards. rust-analyzer will fix that with an Import X code action, but only through a menu: you stop, open it, pick, and when std::fmt::Result and std::io::Result both exist you pick between them every time. This engine removes the menu where there is nothing to decide and makes the decision cheaper where there is. It scans for unresolved names after you change code, asks rust-analyzer for the candidates, and either applies the only one, asks for one key, or leaves ambiguity to a ranked picker whose choice is remembered per project.'),
    ...code('lua', r'lua/config/import_engine.lua · lines 3-9, 20-23', r'''
--
--   * vim.g.xynovim_auto_import = "ask" (default, never silent) | "single" | "off"
--     After InsertLeave, after a save and after a paste the changed lines are
--     scanned for names that resolve to nothing (diagnostics of both tiers plus
--     a treesitter scan). rust-analyzer is asked for the code actions at each
--     one. Exactly one `Import X` (or a choice remembered for this project):
--     "single" applies it as one undo step with a one-line note, "ask" prompts
...
--     for candidates the language server does not know (a crate that is not a
--     dependency yet): fn(name, ctx) -> { { path = "rand::Rng", crate = "rand",
--     add_crate = true, apply = function(cb) ... cb(ok, err) end }, ... }.
--     Such candidates are ranked last and never applied automatically.'''),
    ...para('--', r'The header is also the contract with other modules. Modes are ask (the default, never silent), single and off. The words never silent are a design rule: in single mode the result is one undo step and a one-line note, and in ask mode the user answers before anything changes. Several candidates are never guessed at. The engine.resolve and engine.register_source functions are the surface used by crate_import, by macro_attrs (which passes sources = false for derives that come from a dependency) and by the specs.'),
    ...sec(r'configuration and the memory'),
    ...code('lua', r'lua/config/import_engine.lua · lines 29-37', r'''
M.config = {
  debounce = 600, -- ms between the last change and the scan
  max_names = 8, -- names looked at per scan
  retries = 5, -- "content modified" retries of a code action request
  retry_ms = 400,
  organize_rounds = 30,
  max_lines = 20000, -- the syntax scan reads the whole buffer per edit: skipped above this
  source_wait_ms = 4000, -- how long resolve() waits for the async sources (crates.io)
}'''),
    ...para('--', r'The numbers are the story of a debounced background worker: 600 ms after the last change, at most 8 names per scan, five retries 400 ms apart when the server answers content modified, a 20000-line cap on the syntax scan (added in field-test commit b474307 because the scan reads the whole buffer per edit), and a 4 second ceiling on how long resolve waits for asynchronous sources such as crates.io. M.known_traits, just below, is a list of 20 well-known std traits. It exists only so that a candidate can be tagged as a trait.'),
    ...code('lua', r'lua/config/import_engine.lua · lines 94-103', r'''
      for root, names in pairs(data) do
        if type(root) == "string" and type(names) == "table" then
          memory[root] = {}
          for name, path in pairs(names) do
            -- from a file: only plain identifiers and paths are ever used
            if type(name) == "string" and name:match("^[%w_]+$") and type(path) == "string" and path:match("^[%w_]+[%w_:]*$") then
              memory[root][name] = path
            end
          end
        end'''),
    ...para('--', r'The memory file maps a project root to name and chosen path, and lives in stdpath state. It is read lazily once. What it accepts from the file is narrow: names that match ^[%w_]+$ and paths that look like ident paths. The comment says why: from a file, only plain identifiers and paths are ever used. A corrupt file is survived by pcall around the decode (there is a spec for it), and saving goes through a temporary file renamed over the target, since ff1c8fa through fsutil.rename. remember() applies the same check on the way in, so nothing malformed is ever stored.'),
    ...sec(r'reading use statements without a parser'),
    ...code('lua', r'lua/config/import_engine.lua · lines 255-262', r'''
function M.flatten_use(stmt)
  local body = strip_comments(stmt)
  body = body:gsub("^%s*pub%s*%b()", ""):gsub("^%s*pub%s+", ""):gsub("^%s*use%s+", ""):gsub("%s*;%s*$", "")
  local out = {}
  parse_tree(tokenize(body), 1, {}, out)
  return out
end'''),
    ...para('--', r'The scoring needs to know what the project already imports, in this file, in the neighbouring files, in the crate. flatten_use turns one statement into paths: braces expanded, aliases dropped, self folded into the parent, globs kept as a trailing ::*. The doc comment gives the example, use a::{b, c::{self, d as e}}; becoming a::b, a::c, a::c::d. It uses a tiny tokenizer and a recursive parse_tree rather than patterns because braces nest. use_paths runs three line-anchored patterns over comment-stripped text, for use, pub use and pub(crate) use.'),
    ...para('--', r'parse_title is the bridge to rust-analyzer: the only thing the engine knows about a code action is its title, Import std::io::Error. Anything that does not match, and anything whose path is not an identifier path, returns nil, which is how unrelated quickfixes and odd titles are ignored. An as alias suffix is cut off.'),
    ...sec(r'ranking: reasons, not just a number'),
    ...code('lua', r'lua/config/import_engine.lua · lines 309-309, 375-401', r'''
M.weights = { file = 4, sibling = 3, crate = 2, near = 0.5, cap = 5 }
...
  if ctx.error and cand.name:match("Error$") then
    add(5, "error type in an error context")
  end
  if ctx.ret and ctx.ret.mod then
    local parent_last = cand.parent:match("([^:]+)$")
    if parent_last == ctx.ret.mod or cand.crate == ctx.ret.mod then
      add(8, ("matches the return type `%s::Result`"):format(ctx.ret.mod))
    end
  end
  if ctx.trait_pos and cand.kind == "trait" then
    add(5, "a trait where a trait is expected")
  end
  if facts.shadowed and facts.shadowed[cand.name] and is_std then
    add(-3, "a dependency offers the same name")
  end
  if cand.crate == "core" or cand.crate == "alloc" then
    if facts.std_twin and facts.std_twin[cand.name] then
      add(-2, "std offers it too")
    end
  end
  local idx = facts.dep_index and facts.dep_index[cand.crate]
  if idx then
    add(math.floor(10 / idx + 0.5) / 10, ("dependency #%d"):format(idx))
  end
  if cand.add_crate then
    add(-5, "not a dependency yet")
  end'''),
    ...para('--', r'M.score returns a number and the reasons for it, and the reasons are shown to the user. The weights are in M.weights: a use in this file counts 4, in a sibling module 3, in the crate 2, and a use from the same parent module counts as near at half a point, each capped at 5 occurrences. Then the context adds fixed amounts: +10 for the derive macro of a proc-macro crate inside #[derive(, +8 when the function returns io::Result and the candidate comes from io, +5 for an Error type in an error context, +5 for a trait where a trait is expected, -3 when a dependency offers the same name as a std item, -2 for a core twin of a std item, a small bonus for earlier dependencies, and -5 for a candidate that needs a crate added. The values are not derived from anything; they are hand-picked priorities, and the spec names the cases they encode (proc-macro derive first, io::Error for io::Result, file over sibling over crate, traits in trait position, shadowing, ties by dependency order then path).'),
    ...code('lua', r'lua/config/import_engine.lua · lines 442-467', r'''
function M.decide(mode, cands, remembered)
  if mode == "off" then
    return { act = "off" }
  end
  local real = vim.tbl_filter(function(c)
    return not c.add_crate
  end, cands)
  local pick, why
  if remembered then
    for _, c in ipairs(cands) do
      if c.path == remembered then
        pick, why = c, "remembered"
      end
    end
  end
  if not pick and #real == 1 and #cands == 1 then
    pick, why = real[1], "single"
  end
  if pick then
    return { act = mode == "single" and "apply" or "ask", cand = pick, why = why }
  end
  if #cands == 0 then
    return { act = "none" }
  end
  return { act = "pick" }
end'''),
    ...para('--', r'decide turns a ranked list into an action. The rules are short and conservative. Mode off does nothing. A remembered choice that is still offered wins over ambiguity. Exactly one candidate, and that one a real import, is taken as single. A candidate that adds a crate is never taken automatically (it is filtered out of the real list). In single mode the action is apply, in ask mode it is ask; with several candidates and no memory the answer is pick, which the background run treats as leave it alone. This is where never guess becomes code.'),
    ...sec(r'finding the unresolved names'),
    ...code('lua', r'lua/config/import_engine.lua · lines 641-646', r'''
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    known = declared_names(text)
    for _, p in ipairs(M.use_paths(text)) do
      known[p:match("([%w_]+)$") or p] = true
      -- a glob import may bring anything: nothing is "unresolved" by syntax then
    end'''),
    ...para('--', r'scan_syntax is deliberately a superset: its doc comment says the language server decides, and a name it knows nothing to import is dropped. A treesitter query collects type names and path heads; a name is skipped if the file declares it, imports it, binds it as a generic, or it is in the prelude, or it sits inside a use declaration or a macro definition. The whole-buffer part is computed once per changedtick and memoized (a review fix, 19f974c), because the scan runs for several row ranges. Note the comment inside the use loop: it says a glob import may bring anything, so nothing is unresolved by syntax then. The code under it does not implement that; a glob path ends in ::* and does not match the last-segment pattern, so it adds nothing to the known set and the file is scanned as usual. rust-analyzer finding no import is what drops those names in the end.'),
    ...para('--', r'M.unresolved merges two tiers: the diagnostics that say cannot find, undeclared, failed to resolve or unresolved (but not unresolved import, which is a different problem), and the syntax scan. One entry per position, diagnostics first because they carry the diagnostic that rust-analyzer needs for its code actions. The treesitter context check for macro definitions runs only for hits that survive de-duplication, another review fix.'),
    ...sec(r'asking rust-analyzer'),
    ...code('lua', r'lua/config/import_engine.lua · lines 987-996', r'''
local function busy(errs)
  for _, e in ipairs(errs or {}) do
    if e.code == -32801 or e.code == -32802 or tostring(e.message or ""):lower():find("content modified", 1, true) then
      return true
    end
  end
  return false
end

--- Import candidates rust-analyzer offers for the name at `pos`'''),
    ...para('--', r'candidates_at is the one call to the language server. It sends the range with the diagnostics and only quickfix, through code_actions.request, and treats the content modified answers (-32801, -32802 or that text) as a reason to retry up to five times. A real server returns that error exactly when it is still analysing the last edit, so retrying is the correct reaction. The result is a list of candidates, each with the original action attached so that applying it does not need a second request.'),
    ...para('--', r'Sources are how the engine learns about candidates the server cannot offer, such as crates that are not dependencies yet. The doc comment defines the contract: a function from name and context to candidates with path, crate, add_crate, apply, guess and note; async sources take a callback; resolve waits at most source_wait_ms. add_extras validates every path before it becomes a candidate. Source functions run inside pcall, so a broken source cannot break an import.'),
    ...para('--', r'M.resolve is the public API for other modules and is the best place to see the whole pipeline: validate the name, find its first use, ask the server, add the sources (unless sources = false), gather facts (use index, dependency order, proc-macro crates, syntactic context), rank, and report. The result carries the ranked list, the best, the remembered candidate and a choice, which is what single mode would take. Without a callback it blocks with vim.wait for up to 30 seconds and returns the result, which is how the specs and the macro tools use it.'),
    ...sec(r'the background run'),
    ...para('--', r'run handles a range of changed rows. It checks mode, modifiability and that a client is attached, clamps the rows, and loads the workspace metadata first, because lowercase path heads such as io::Error can only be judged with the dependency list. A failure of the scan is reported with a warning and never raised into an autocommand.'),
    ...code('lua', r'lua/config/import_engine.lua · lines 1260-1280', r'''
          M.apply_candidate(buf, d.cand, function(ok, err)
            if ok then
              imported = imported + 1
              last_import[buf] = { name = p.name, seq = undo_seq(buf) }
              notify("imported " .. d.cand.path)
            elseif err then
              notify(("cannot import %s: %s"):format(d.cand.path, err), vim.log.levels.WARN)
            end
            nextp()
          end, { join = imported > 0 })
        end
        if d.act == "ask" then
          if vim.api.nvim_get_current_buf() ~= buf or vim.fn.mode() ~= "n" then
            return nextp()
          end
          if p.answered or M.ask_key(d.cand, p.name) then
            if not p.answered and vim.api.nvim_buf_get_changedtick(buf) ~= tick then
              -- typed while the question was open: the candidate's edit is stale; look again
              -- at the extmark instead of dropping the yes
              p.answered = true
              i = i - 1'''),
    ...para('--', r'The loop over the names is where the design is exercised. Each name is tracked by an extmark, so edits while the server answers move or cancel it; the text under the mark is compared with the name before every step. A dismissed candidate is cached for the session, and the dismissal key also supports a wildcard that undo_guard sets: when the user undoes an import, the engine must not re-import the name a second later, so the undo marks that name as dismissed. In ask mode it only asks in normal mode of the current buffer. If the buffer changed while the question was open, the edit that the action carries is stale; the yes is kept (p.answered) and the same name is looked up again instead of applying stale text or dropping the answer, a review fix. Several imports of one run join into one undo step with undojoin.'),
    ...code('lua', r'lua/config/import_engine.lua · lines 1180-1188', r'''
function M.ask_key(cand, name)
  if #vim.api.nvim_list_uis() == 0 then
    return false
  end
  local ok, n = pcall(vim.fn.confirm, ("Import %s?"):format(cand.path), "&Yes\n&No", 1)
  return ok and n == 1
end

local ns = vim.api.nvim_create_namespace("xynovim_import_engine")'''),
    ...para('--', r'ask_key explains a field bug in its comment. The first version printed a question with echo and waited in getcharstr. A notification UI hides that prompt after a few seconds while Neovim still waits, and the next key typed (:w) was taken as the answer. It now uses vim.fn.confirm, which stays until an answer, and without any UI it answers no. Note that the header of the file still describes the old prompt, one key with CR or y accepting; the dialog now offers Yes and No.'),
    ...sec(r':ImportName and the picker'),
    ...para('--', r'Every row of the picker is the path, the score, tags for remembered, adds the crate and guess, a note, and the reasons joined by semicolons, or no signals. The reasons are what makes a ranked list trustworthy, because they say why the first entry is first.'),
    ...code('lua', r'lua/config/import_engine.lua · lines 1355-1372', r'''
      local items = vim.deepcopy(res.candidates)
      if res.remembered then
        -- no table.sort: LuaJIT's is not stable and would scramble the ranked order
        local first, rest = {}, {}
        for _, c in ipairs(items) do
          table.insert(c.remembered and first or rest, c)
        end
        items = vim.list_extend(first, rest)
      end
      local by_path = {}
      for _, cand in ipairs(res.candidates) do
        by_path[cand.path] = cand
      end
      M.select(items, { prompt = "Import " .. name, format_item = M.format_item }, function(choice)
        if not choice then
          return
        end
        local cand = by_path[choice.path] or choice'''),
    ...para('--', r'The remembered choice leads the list. The comment explains an implementation detail that came from a bug: no table.sort here, because LuaJIT sort is not stable and would scramble the ranked order of everything else, so the code partitions into remembered and rest. After a successful import the path is remembered for the project and name, except for crate-adding guesses: a guess is not a settled choice. This is the review fix whose spec is named ImportName with a remembered choice keeps the others in ranked order.'),
    ...sec(r'organize imports'),
    ...code('lua', r'lua/config/import_engine.lua · lines 1391-1398', r'''
-- Titles measured on rust-analyzer 1.99: "Merge imports" and "Normalize
-- import" (refactor.rewrite, offered at a cursor inside a `use`, not for a
-- selection of it), "Remove unnecessary braces" and "Remove all unused imports"
-- (quickfix, the latter for any range that holds an unused import).
local ORGANIZE = { "^Merge imports", "^Normalize import", "^Remove unnecessary braces", "^Remove all unused imports" }

local function organize_match(a)
  if a.kind:match("^source%.organizeImports") then'''),
    ...para('--', r'ImportOrganize does not implement organizing itself; it applies rust-analyzer assists. The comment above ORGANIZE records the titles measured on a particular rust-analyzer: Merge imports and Normalize import (refactor.rewrite, offered at a cursor inside a use and not for a selection of it), Remove unnecessary braces and Remove all unused imports (quickfix, for any range that holds an unused import). That explains organize_ranges: one empty range inside each top-level use, plus the whole buffer for the unused-imports fix.'),
    ...code('lua', r'lua/config/import_engine.lua · lines 1460-1479', r'''
      end
      if did then
        break -- the ranges moved: look again from the top
      end
    end
    if not did then
      -- rust-analyzer may still be re-analysing after our last edit: look
      -- once more before concluding that nothing is left
      if settled then
        break
      end
      settled = true
      vim.wait(800)
    else
      settled = false
    end
  end
  notify(applied > 0 and ("organized imports (%d change%s)"):format(applied, applied == 1 and "" or "s") or "imports already organized")
  return applied
end'''),
    ...para('--', r'The loop applies one assist at a time, in a single undo step, and starts again from the top each time because every edit moves the ranges. An assist that fails or changes nothing is remembered in skipped by title and text, so the loop terminates. A final settle round waits 800 ms and looks once more, since rust-analyzer may still be re-analysing after the last edit. A cap of 30 rounds bounds everything. It blocks, which is acceptable for an explicit command and is documented as up to about a minute on a cold server.'),
    ...sec(r'triggers'),
    ...code('lua', r'lua/config/import_engine.lua · lines 1519-1530', r'''
function M.trigger(buf)
  if not eligible(buf) then
    return
  end
  track(buf)
  local t = timers[buf]
  if not t then
    t = assert(vim.uv.new_timer())
    timers[buf] = t
  end
  t:stop()
  t:start('''),
    ...para('--', r'trigger keeps one timer per buffer and a dirty row range that grows with each change; on_lines records the changed rows through nvim_buf_attach. When the timer fires it takes the range, clears it, and runs the scan. If a run is already going it re-arms the timer instead of starting a second one, and the whole thing is wrapped in pcall. The events that arm it are InsertLeave, a save, and TextChanged for multi-line changes in normal mode (a put), but only when the undo sequence moved forward: an undo or redo is not a new change.'),
    ...para('--', r'The paste hook wraps vim.paste, the function that bracketed paste and nvim_paste go through, and triggers a scan when a paste ends (phases -1 and 3). The comment adds that p does not call it and TextChanged covers that case.'),
    ...sec(r'setup and keys'),
    ...code('lua', r'lua/config/import_engine.lua · lines 1596-1606', r'''
    return
  end
  local function map(lhs, rhs, desc)
    -- only a free key (keymaps.lua keeps a "not bound" stub on every <leader>r key:
    -- that one counts as free, a real map does not)
    local cur = vim.fn.maparg(lhs, "n", false, true)
    if next(cur) == nil or cur.desc == "which_key_ignore" then
      vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc, silent = true })
    end
  end
  map("<leader>rI", function()'''),
    ...para('--', r'In this repository the two keys are bound buffer-locally in Rust buffers, but only if the key is free. The comment explains the test: keymaps.lua keeps a not-bound stub on every <leader>r key, and that stub counts as free (its description is which_key_ignore) while a real mapping does not. The setup function then creates :ImportName, :ImportForget (which also clears the session dismissals of the project) and :ImportOrganize, and installs the autocommands. lua/plugins/import-engine.lua calls it on VeryLazy and then sets up crate_import.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/import-engine_spec.lua is built in layers. Pure units: flattening use statements, title parsing, return-type hints, the scoring cases and the decisions. The memory: persistence across a restart, forgetting one name or a project, refusing non-identifiers also from a file, surviving a corrupt state file. The syntax scan and the use index (multi-line use statements, invalidation). The auto-import flow against a fake rust-analyzer: single mode with one undo step, joined imports, ambiguous names left alone, remembered choices, off and non-modifiable buffers, macro definitions, ask mode and its session dismissal, never prompting outside normal mode, debounce and no re-trigger after an undo. Then resolve and sources, and finally the real rust-analyzer on the deps-lab fixture: Serialize imported in one undo step, thiserror::Error first inside a derive, a remembered choice across a restart, organizing, and import on paste.'),
    ...sec(r'history'),
    ...pt('--', r'b9363cd · 2026-10-14', r'added with 1661 lines'),
    ...pt('--', r'dc846f6 · 2026-10-14', r'CI: the use index without ripgrep walked no directories (vim.fs.dir skip returns whether to descend)'),
    ...pt('--', r'19f974c · 2026-10-15', r'review: memoized known names, confirm dialog, stale-yes fix, stable order for remembered'),
    ...pt('--', r'b474307 · 2026-10-15', r'field test: max_lines cap'),
    ...pt('--', r'ff1c8fa · 2026-10-16', r'portability: rename through fsutil'),
    ...sec(r'the same file in xyno-imports.nvim'),
    ...para('--', r'On 2026-10-22 the engine became lua/xyno_imports/engine.lua in xyno-imports.nvim, and the tooling around it changed more than the code. The scoring, scanning, ranking, ask loop and organize logic are identical. What changed: names (state file in stdpath state/xyno-imports/imports.json, namespace xyno_imports, requires of xyno_rust.code_actions, crate_meta and fsutil); the mode may now come from setup{ mode = ... } as M.default_mode, with vim.g.xyno_auto_import still winning; the keys are off by default and are given as keymaps = true or a table with import and organize (defaults <leader>rI and <leader>rO), and the free-key probe against the which_key_ignore stub is gone because the plugin no longer has to coexist with that stub; the commands are defined by define_commands and skipped when commands = false; and setup takes opts. A tuning table can override the engine config through setup{ config = {...} }. An existing remembered-choice file in the old directory is not read by the plugin.'),
  ],
);
