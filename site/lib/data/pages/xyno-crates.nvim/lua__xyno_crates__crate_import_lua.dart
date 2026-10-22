import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-crates.nvim/lua/xyno_crates/crate_import.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'crate_import.lua — import a name from a crate you have not added yet'),
    cm('--', r'an import-engine source, a bounded wait, and honest "guess" labels'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'async candidate source for xyno-imports.nvim + the add-then-import path'),
    kv(r'language', r'Lua (Neovim 0.12+)'),
    kv(r'size', r'282 lines; 7 lines differ from the xynovim original (14 counting both sides of the diff)'),
    kv(r'talks to', r'crates.io sparse index and search, rust-analyzer code actions, cargo add'),
    kv(r'config', r'max_guesses 3, min_guess_len 3, poll_ms 1000, reload_timeout_ms 60000'),
    kv(r'history', r'one xynovim commit (b9363cd, 2026-10-14), then the extraction (5cd9905, 2026-10-22)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The sequence goes like this. You type Uuid::new_v4(), the name is red, rust-analyzer offers nothing, because it only offers imports from crates that are already in the dependency graph (the plan document’s measurement, not a general claim about rust-analyzer). You open crates.io, find uuid, run cargo add uuid, wait for the project to reload, and only then does the lightbulb offer use uuid::Uuid. In xynovim’s plan document (docs/PLAN_MACROS_DEPS.md) this is gap G3: "A crate that is not yet a dependency cannot be imported", measured as 0 code actions for rand::random::<u8>() with rand absent, and the cost written down as "I must leave the editor to run cargo add".'),
    blank,
    ...para('--', r'This module closes the gap in the smallest way that respects what the editor knows. It does not try to be the import engine. It is one source plugged into someone else’s engine (xyno-imports.nvim): when the engine has no candidate for a name, this source proposes crates that might provide it, and when you accept one, it adds the crate, waits until rust-analyzer has loaded it, and then applies the import rust-analyzer now offers. The header comment (lines 1-18) is the whole contract: the crate named exactly like a lowercase name, search hits for other names labelled as guesses, the default add, a bounded wait, then the import.'),
    blank,
    ...sec(r'two kinds of candidate, and why only one is honest'),
    ...para('--', r'The comment separates the two cases, and the separation is the best design decision in the file. A lowercase name such as rand is a path head: rand::random() can only mean the crate called rand, so one lookup in the sparse index settles it. An item name such as Rng or Utc or Uuid is a different problem: crates.io is searched by crate name, not by the items a crate exports, so searching for Rng finds nothing called "rng" inside the rand crate. The module does not pretend otherwise. For item names it looks at search hits whose name equals or contains the lowercased item name and labels the result as a guess. The label is a field on the candidate (guess = true) and a note that says so in words, and the spec checks that resolve() lists the guesses after rust-analyzer’s own candidates, labelled.'),
    blank,
    ...para('--', r'The source function is where this happens. Read its first lines before the steps.'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_import.lua · lines 182-198', r'''
--- Engine source: fn(name, ctx, cb). Only fills gaps: nothing when
--- rust-analyzer offered candidates, or for a name that is already a dependency.
function M.source(name, ctx, cb)
  if (ctx.local_candidates and #ctx.local_candidates > 0) or ctx.crates == false then
    return cb({})
  end
  local buf = ctx.bufnr
  local pos = ctx.pos and { row = ctx.pos.row, col = ctx.pos.col } or nil
  local out = {}
  local function emit()
    cb(out)
  end
  local function with_meta(meta)
    local lname = name:lower()
    local steps = {}
    -- 1. the crate called exactly like the name (a path head: `rand::random()`)
    if name:match("^[a-z][a-z0-9_]*$") and not is_dependency(meta, name) then'''),
    ...para('--', r'The first condition is "only fill gaps". If rust-analyzer already offered candidates (ctx.local_candidates), or the caller turned crates off (ctx.crates == false), the source answers an empty list at once and costs nothing. Then it reads the workspace metadata, which is cached in xyno-rust.nvim, and runs up to two steps. Step 1 applies only to names that match ^[a-z][a-z0-9_]*$ and are not already a dependency.'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_import.lua · lines 199-224', r'''
      steps[#steps + 1] = function(next_)
        local variants = { name }
        if name:find("_", 1, true) then
          variants[2] = (name:gsub("_", "-"))
        end
        local i = 0
        local function try()
          i = i + 1
          if not variants[i] then
            return next_()
          end
          cm.info_async(variants[i], function(info)
            if info and usable(info.name) and ident(info.name) == name then
              out[#out + 1] = candidate(info.name, nil, {
                bufnr = buf,
                pos = pos,
                fields = { note = ("crate %s %s on crates.io"):format(info.name, info.newest or "") },
              })
              return next_()
            end
            try()
          end, { index_only = true })
        end
        try()
      end
    end'''),
    ...para('--', r'Notice the variants. A crate whose name contains a dash is written with an underscore in Rust paths, so a path head serde_json is looked up as serde_json and then as serde-json. The check at the end is strict: the crate found must satisfy ident(info.name) == name, which stops the index from answering a different crate that merely looks similar. index_only = true tells crate_meta to answer from the sparse index data without the web API call for description and downloads (crate_meta.lua returns the info before that call); the successful result becomes a candidate with a note like "crate rand 0.9.1 on crates.io".'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_import.lua · lines 225-253', r'''
    -- 2. crates.io search by name for item names (guesses)
    if #name >= M.config.min_guess_len and not name:match("^[a-z][a-z0-9_]*$") then
      steps[#steps + 1] = function(next_)
        cm.search_async(lname, function(list)
          local hits = {}
          for _, c in ipairs(list or {}) do
            local id = usable(c.name) and ident(c.name):lower() or nil
            if id and (id == lname or id:find(lname, 1, true)) and not is_dependency(meta, ident(c.name)) then
              hits[#hits + 1] = c
            end
          end
          table.sort(hits, function(a, b)
            return (a.downloads or 0) > (b.downloads or 0)
          end)
          for i = 1, math.min(#hits, M.config.max_guesses) do
            local c = hits[i]
            out[#out + 1] = candidate(c.name, name, {
              bufnr = buf,
              pos = pos,
              fields = {
                guess = true,
                note = ("%s %s, %s downloads: crates.io search by name, the path is a guess"):format(c.name, c.version or "", c.downloads and tostring(c.downloads) or "?"),
              },
            })
          end
          next_()
        end)
      end
    end'''),
    ...para('--', r'Step 2 is the guess. It needs at least min_guess_len (3) characters, because the config comment says shorter names would match half of crates.io, and it only runs for names that are not plain lowercase. The filter keeps a hit when its identifier equals or contains the lowercased name and it is not already a dependency, sorts by download count, and keeps the top max_guesses (3). Two details are worth the reader’s attention. usable(c.name) is called before anything else, because the network is not trusted: a hit called "-uuid" would become an argv flag, and the spec puts exactly that name in its fake search result to prove it is dropped. And the note spells out what the candidate is: crate, version, download count, "crates.io search by name, the path is a guess".'),
    blank,
    ...sec(r'validation: nothing from the network reaches a command line'),
    ...code('lua', r'lua/xyno_crates/crate_import.lua · lines 33-40', r'''
--- The Rust identifier of a crate name ("serde-json" -> "serde_json").
local function ident(crate)
  return (crate:gsub("-", "_"))
end

local function usable(crate)
  return type(crate) == "string" and cm.valid_name(crate) and crate:sub(1, 1) ~= "-" and ident(crate):match("^[%a_][%w_]*$") ~= nil
end'''),
    ...para('--', r'usable() is the gate every network string passes. cm.valid_name (from xyno-rust.nvim) accepts letters, digits, underscore and dash up to 64 characters; this function additionally refuses a leading dash and requires the identifier form to be a legal Rust identifier. The header comment states the rule in one line, "Everything from the network is validated before it reaches an argv or a path; the engine only accepts ident paths", and the code applies it twice, once when building candidates and once more in add_and_import, so a caller that builds a spec by hand cannot skip it either.'),
    blank,
    ...sec(r'what accepting a candidate does'),
    ...para('--', r'A candidate is data plus a closure. path is what the engine shows and inserts (uuid::Uuid), crate is the identifier, add_crate = true marks it as needing a manifest change first, and apply(cb) runs add_and_import. The extra fields (guess, note) are merged last, so the labelling cannot be lost by accident. The cursor position travels with the candidate (extra.pos), which matters in a moment.'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_import.lua · lines 102-136', r'''
function M.add_and_import(buf, spec, cb)
  cb = cb or function() end
  if not usable(spec.crate) then
    return cb(false, "invalid crate name")
  end
  spec.ident = spec.ident or ident(spec.crate)
  local ns = vim.api.nvim_create_namespace("xyno_crate_import")
  local mark
  if spec.name and spec.name:match("^[%w_]+$") and vim.api.nvim_buf_is_valid(buf) then
    local pos = spec.pos
    if not pos then
      for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if not l:match("^%s*use%s") and not l:match("^%s*//") then
          local s = 1
          while true do
            local a, b = l:find(spec.name, s, true)
            if not a then
              break
            end
            if not l:sub(a - 1, a - 1):match("[%w_]") and not l:sub(b + 1, b + 1):match("[%w_]") then
              pos = { row = i - 1, col = a - 1 }
              break
            end
            s = b + 1
          end
          if pos then
            break
          end
        end
      end
    end
    if pos then
      mark = vim.api.nvim_buf_set_extmark(buf, ns, pos.row, pos.col, { right_gravity = false })
    end
  end'''),
    ...para('--', r'add_and_import does the setup work before touching cargo. If the spec has a name that is a plain identifier, it needs to find the name again later, after cargo and rust-analyzer have taken seconds, and the user may have typed in the meantime. So it places an extmark at the position, with right_gravity = false, in a private namespace. If no position was given (the case of the "Add crate" code action, which knows only a name) it scans the buffer for the first whole-word occurrence outside use lines and line comments. The checks on the characters before and after the match are the usual way to get a word boundary in Lua patterns without a regex engine.'),
    blank,
    ...para('--', r'Only then does it call add_direct in crate_add.lua. A failure stops there and is passed to the callback. A success without a mark (a bare path head) ends there too: the crate is added and there is nothing to import. Otherwise comes the wait.'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_import.lua · lines 137-156', r'''
  require("xyno_crates.crate_add").add_direct(buf, spec.crate, function(ok, msg)
    if not ok then
      return cb(false, msg)
    end
    if not mark then
      return cb(true, msg)
    end
    notify(("added %s, waiting for rust-analyzer to load it ..."):format(spec.crate))
    M.wait_and_import(buf, ns, mark, spec.name, spec, function(done, m2)
      pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
      if done then
        notify(m2)
      else
        notify(tostring(m2), vim.log.levels.WARN)
      end
      -- the crate IS added: the add succeeded even when the import did not
      cb(done, m2)
    end)
  end)
end'''),
    ...para('--', r'The callback of the wait always clears the namespace, notifies, and then reports done to the caller, with the comment that matters: "the crate IS added: the add succeeded even when the import did not". A failed import is a warning, never a rollback; the manifest edit was real and useful by itself.'),
    blank,
    ...sec(r'the wait: polling, bounded, and suspicious of the buffer'),
    ...code('lua', r'lua/xyno_crates/crate_import.lua · lines 44-96', r'''
--- Poll rust-analyzer for an "Import ..." action of `crate_ident` at `mark`
--- (an extmark on the name) until it shows up or the time is over, then apply
--- it. cb(ok, message). Preference: the candidate's own path, then the shortest
--- path under the crate (the least surprising re-export).
function M.wait_and_import(buf, mark_ns, mark, name, spec, cb)
  local engine = require("xyno_imports.engine")
  local ca = require("xyno_rust.code_actions")
  local started = vim.uv.now()
  local poll
  local function again()
    if vim.uv.now() - started > M.config.reload_timeout_ms then
      return cb(false, ("rust-analyzer did not offer an import of %s from %s within %d s; the crate is added, try :ImportName"):format(name, spec.ident, M.config.reload_timeout_ms / 1000))
    end
    vim.defer_fn(poll, M.config.poll_ms)
  end
  poll = function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return cb(false, "buffer closed")
    end
    local m = vim.api.nvim_buf_get_extmark_by_id(buf, mark_ns, mark, { details = true })
    if not m[1] then
      return cb(false, "the name was edited away")
    end
    local line = vim.api.nvim_buf_get_lines(buf, m[1], m[1] + 1, false)[1] or ""
    if line:sub(m[2] + 1, m[2] + #name) ~= name then
      return cb(false, "the name was edited meanwhile")
    end
    local pos = { row = m[1], col = m[2], end_col = m[2] + #name }
    engine.candidates_at(buf, pos, function(cands)
      local mine = vim.tbl_filter(function(c)
        return c.crate == spec.ident
      end, cands)
      if #mine == 0 then
        return again()
      end
      table.sort(mine, function(a, b)
        if (a.path == spec.path) ~= (b.path == spec.path) then
          return a.path == spec.path
        end
        if #a.path ~= #b.path then
          return #a.path < #b.path
        end
        return a.path < b.path
      end)
      engine.apply_candidate(buf, mine[1], function(ok, err)
        cb(ok, ok and ("imported " .. mine[1].path) or err)
      end)
    end, vim.diagnostic.get(buf, { lnum = m[1] }))
  end
  -- first look immediately only if the dependency is already loaded; otherwise
  -- give cargo and rust-analyzer a moment
  vim.defer_fn(poll, M.config.poll_ms)
end'''),
    ...para('--', r'There is no event for "rust-analyzer finished loading the new crate", so the module polls, which is the honest answer to a protocol that does not tell you. Each poll asks the import engine for candidates at the tracked position (with the diagnostics of the line, so the engine sees what the server sees) and keeps only those whose crate equals the added one. Zero matches means not yet: schedule the next poll after poll_ms (1000), unless more than reload_timeout_ms (60 seconds) has passed since the start, in which case the callback gets a message that names the name, the crate and the number of seconds, and ends with the instruction ":ImportName".'),
    blank,
    ...para('--', r'The first poll is deferred by one interval. The comment above the last line says why: the module could look immediately only if the dependency were already loaded, and otherwise gives cargo and rust-analyzer a moment. After the extra second the loop is cheap, because every iteration is one code-action request.'),
    blank,
    ...para('--', r'Three checks protect the user’s text. If the buffer is gone, the answer is "buffer closed". If the extmark is gone, "the name was edited away". And if the text at the mark no longer equals the name, "the name was edited meanwhile". The third check is the one that prevents a wrong write: an extmark follows edits, but it cannot know that the user changed Uuid into Url in place. Without the comparison the import would be applied to a different word.'),
    blank,
    ...para('--', r'When candidates do arrive, the choice among them is deterministic. The sort puts the candidate whose path equals the one that was offered first, then the shortest path, then alphabetical order. For Uuid the spec offers uuid::fmt::Uuid, uuid::Uuid and other::Uuid, and expects uuid::Uuid applied: the candidate path wins, the foreign crate is filtered, the deeper re-export loses. The comment calls the shortest path "the least surprising re-export".'),
    blank,
    ...sec(r'registering with the engine'),
    ...code('lua', r'lua/xyno_crates/crate_import.lua · lines 274-280', r'''
local unregister
function M.setup()
  if unregister then
    return
  end
  unregister = require("xyno_imports.engine").register_source(M.source, { async = true })
end'''),
    ...para('--', r'setup() is the whole connection to xyno-imports.nvim: register_source(M.source, { async = true }). The engine’s API supports asynchronous sources and bounds them: the import spec in this repository includes a test that a slow source does not hold resolve() beyond source_wait_ms. The module keeps the unregister function in an upvalue so that a second setup() call is a no-op. This is also why crate_import needs no options of its own in init.lua.'),
    blank,
    ...sec(r'how it is tested'),
    ...para('--', r'tests/crate-import_spec.lua has 14 tests and does most of its work hermetically with stubs on xyno_rust.crate_meta. The source tests prove: no search at all when rust-analyzer already offered candidates; the lowercase case returns the crate itself as an add-crate candidate without a guess flag; a path head with an underscore falls back to the dashed name; item names yield guesses ordered by downloads, with "-uuid" dropped; names shorter than three characters and crates that are already dependencies yield nothing and never search; and offline or failing lookups give no candidates and no error. The add_and_import tests drive the poll loop with a fake engine: three polls, the wrong crate first, the right one on the third; a bounded give-up after 150 ms in the test with the crate left added; a failed add that stops the flow; and a bare path head that only adds. The last test, "real: Uuid from nothing", uses a copy of the no-deps-lab fixture, real crates.io, real rust-analyzer and a real cargo check, and skips when any of them is missing.'),
    blank,
    ...sec(r'edge cases handled, and one the code leaves open'),
    ...pt('--', r'offline', r'cm.info_async and cm.search_async fail quietly; the source emits an empty list and the editor behaves as if the feature were not there.'),
    ...pt('--', r'a crate that is already a dependency', r'never proposed. is_dependency compares identifiers, so a renamed dependency counts under its alias.'),
    ...pt('--', r'the name was inside a use line', r'ignored when the module has to find the position itself: lines starting with use or // are skipped.'),
    ...pt('--', r'open question', r'guesses match by crate name only, as the module’s own comment admits. xynovim’s docs/DETAILS.md lists this as a residual limit: Rng does not find rand. The module labels the result a guess instead of hiding the limit.'),
    ...sec(r'history'),
    ...para('--', r'The file was added in xynovim commit b9363cd on 2026-10-14, in the large "Macros and dependencies" change that also added crate_add.lua and crate_features.lua; git log shows no later change to it there. The extraction (xyno-crates.nvim 5cd9905, 2026-10-22) changed 7 of its 282 lines (14 in a diff): the require paths (config.import_engine became xyno_imports.engine, config.crate_meta and config.code_actions became xyno_rust.*), the extmark namespace (xynovim_crate_import became xyno_crate_import), and the first comment line, which had pointed at a plan item and a gap number that mean nothing outside xynovim.'),
    blank,
  ],
);
