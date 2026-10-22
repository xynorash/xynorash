import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/crate_import.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'crate_import.lua — import from a crate you do not have yet'),
    cm('--', r'an import-engine source: guess, add the crate, wait, import'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'import-engine source for names no dependency offers'),
    kv(r'language', r'Lua for Neovim 0.12, uses crate_meta, crate_add, import_engine'),
    kv(r'size', r'282 lines, 1 commit (b9363cd, 2026-10-14), never changed since'),
    kv(r'spec', r'tests/crate-import_spec.lua (408 lines)'),
    kv(r'loaded by', r'lua/plugins/import-engine.lua on VeryLazy'),
    kv(r'also lives in', r'xyno-crates.nvim as lua/xyno_crates/crate_import.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'The import engine can only offer what rust-analyzer offers, and rust-analyzer only knows crates that are already dependencies. Type Uuid::new_v4() in a project that has no uuid and the engine finds no candidate. This file is a source plugged into the engine (engine.register_source, async) that fills exactly this gap: it proposes crates from crates.io, and accepting one adds the dependency, waits for rust-analyzer to load it, and applies the import. Its first line gives the plan item (3.3, gap G5).'),
    ...code('lua', r'lua/config/crate_import.lua · lines 1-18', r'''
-- Import from a crate that is not a dependency yet (plan item 3.3, gap G5).
--
-- An import-engine source (engine.register_source, async): when rust-analyzer
-- offers nothing for an unresolved name, it proposes
--   * the crate named exactly like a lowercase name (`rand` for `rand::random()`),
--     checked in the sparse index;
--   * for other names (Rng, Utc, Uuid) the crates.io search hits whose name equals
--     or contains the lowercased name, most downloaded first, LABELLED AS GUESSES:
--     crates.io is searched by crate name, not by the items a crate exports, so
--     `Rng` finds nothing that is called "rng" in `rand`.
-- Accepting one runs crate_add's default add (newest release, no features, into
-- the package of the buffer), then waits for rust-analyzer to load the new
-- dependency (polling its import actions, bounded) and applies the import.
-- crate_add's "Add crate X" action uses the same add-and-wait path.
--
-- Everything from the network is validated (crate_meta.valid_name) before it
-- reaches an argv or a path; the engine only accepts ident paths.
local M = {}'''),
    ...para('--', r'The header contains an honest limitation. crates.io is searched by crate name, not by the items a crate exports, so a search for Rng finds nothing that is called rng in rand. The module therefore separates two cases and labels the weaker one. A lowercase name is treated as a path head and checked exactly in the sparse index (rand for rand::random()). Any other name (Rng, Utc, Uuid) becomes a search whose hits must have a name that equals or contains the lowercased item name, most downloaded first, and every such candidate is marked as a guess.'),
    ...sec(r'configuration and validation'),
    ...code('lua', r'lua/config/crate_import.lua · lines 22-27, 33-40', r'''
M.config = {
  max_guesses = 3,
  min_guess_len = 3, -- shorter item names would match half of crates.io
  poll_ms = 1000,
  reload_timeout_ms = 60000,
}
...
--- The Rust identifier of a crate name ("serde-json" -> "serde_json").
local function ident(crate)
  return (crate:gsub("-", "_"))
end

local function usable(crate)
  return type(crate) == "string" and cm.valid_name(crate) and crate:sub(1, 1) ~= "-" and ident(crate):match("^[%a_][%w_]*$") ~= nil
end'''),
    ...para('--', r'max_guesses = 3 and min_guess_len = 3 keep the noise down: a two-letter item name would match half of crates.io, which the comment says outright. poll_ms and reload_timeout_ms (1 s and 60 s) bound the wait for rust-analyzer. ident converts a crate name to the Rust identifier (serde-json to serde_json). usable layers three checks: a string, a valid crate name by crate_meta, no leading dash (the same hazard crate_add guards against with cargo add), and an identifier that is a legal Rust name. Everything that came from the network passes through it before it reaches an argv, a path or an identifier, as the header says.'),
    ...sec(r'waiting for rust-analyzer'),
    ...code('lua', r'lua/config/crate_import.lua · lines 48-100', r'''
function M.wait_and_import(buf, mark_ns, mark, name, spec, cb)
  local engine = require("config.import_engine")
  local ca = require("config.code_actions")
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
end

--- Add crate `spec.crate` to the package of `buf` and, when `spec.name` is a
--- name to import (not just a path head), import it once rust-analyzer knows
--- the crate. spec = { crate = "rand", ident = "rand", name = "Rng", path ='''),
    ...para('--', r'After cargo add the dependency is not instantly known to rust-analyzer; it has to reload the workspace. wait_and_import polls rather than sleeping a fixed time. It keeps an extmark on the name in the buffer and every second asks the engine for candidates at that position. The checks before each ask are the part worth reading: the buffer may be closed, the extmark may be gone (the name was edited away), and the text under the extmark may no longer be the name. Each failure ends the wait with a message instead of importing at a position that now means something else.'),
    ...para('--', r'When candidates arrive, only those from the new crate count. They are sorted by a three-level preference: the candidate whose path equals the proposed one, then the shortest path (the comment calls it the least surprising re-export), then alphabetical. If nothing arrives within 60 seconds the message says the crate is added and suggests :ImportName. The first look comes one poll interval after the add. The comment above that line says it would look at once if the dependency were already loaded and otherwise give cargo and rust-analyzer a moment, but the code always defers by poll_ms.'),
    ...sec(r'add and import in one move'),
    ...code('lua', r'lua/config/crate_import.lua · lines 102-158', r'''
function M.add_and_import(buf, spec, cb)
  cb = cb or function() end
  if not usable(spec.crate) then
    return cb(false, "invalid crate name")
  end
  spec.ident = spec.ident or ident(spec.crate)
  local ns = vim.api.nvim_create_namespace("xynovim_crate_import")
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
  end
  require("config.crate_add").add_direct(buf, spec.crate, function(ok, msg)
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
end

-- ------------------------------------------------------------ candidates'''),
    ...para('--', r'add_and_import takes a spec (crate, ident, name, path, optional pos) and a callback. It refuses an unusable crate name first. If the spec has a name that is a plain identifier, it finds a position for the extmark: the one given by the caller, or the first occurrence of the name as a whole word in a line that is neither a use line nor a comment. The mark has right_gravity = false so text typed at the mark does not move it. Then it calls crate_add.add_direct (the same one-click add as the diagnostic action), and only on success waits for the import.'),
    ...para('--', r'The comment at the end states the contract: the crate IS added; the add succeeded even when the import did not. The callback gets the import outcome, so the caller can tell a failed import after a successful add. The same function backs the Add crate X action of crate_add, which passes no name and therefore only adds.'),
    ...sec(r'the candidates'),
    ...code('lua', r'lua/config/crate_import.lua · lines 160-182', r'''
local function candidate(crate, name, extra)
  local id = ident(crate)
  local path = name and (id .. "::" .. name) or id
  return vim.tbl_extend("force", {
    path = path,
    crate = id,
    add_crate = true,
    apply = function(cb)
      M.add_and_import(extra.bufnr, { crate = crate, ident = id, name = name, path = path, pos = extra.pos }, cb)
    end,
  }, extra.fields or {})
end

local function is_dependency(meta, id)
  for _, d in ipairs(meta and cm.dependencies(meta) or {}) do
    if ident(d.rename or d.name or "") == id then
      return true
    end
  end
  return false
end

--- Engine source: fn(name, ctx, cb). Only fills gaps: nothing when'''),
    ...para('--', r'candidate builds the record the engine shows: path, crate, add_crate = true, optional extra fields such as note or guess, and an apply function that calls add_and_import. is_dependency skips crates that already are dependencies, comparing the Rust identifier of the rename or name, so serde-json is recognised as serde_json.'),
    ...code('lua', r'lua/config/crate_import.lua · lines 184-196', r'''
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
    local steps = {}'''),
    ...para('--', r'The source function begins with its gap-filling rule: nothing if rust-analyzer already offered candidates, or if the context says crates = false (no caller in this repository sets that key; macro_attrs passes sources = false instead, which makes the engine skip every source). It runs a sequence of async steps through a small run/next loop, after the workspace metadata has been loaded for the dependency check; without a root it works with no metadata.'),
    ...code('lua', r'lua/config/crate_import.lua · lines 197-223', r'''
    -- 1. the crate called exactly like the name (a path head: `rand::random()`)
    if name:match("^[a-z][a-z0-9_]*$") and not is_dependency(meta, name) then
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
      end'''),
    ...para('--', r'Step one is the path head. A name that is all lowercase letters, digits and underscores and not a dependency is looked up exactly in the sparse index (index_only, no web API call). A name with underscores also tries the dashed spelling, because crates.io names use both. The result is accepted only if the found crate identifier equals the name, and the note says what was found with its newest version. A miss falls through to the next variant.'),
    ...code('lua', r'lua/config/crate_import.lua · lines 224-252', r'''
    end
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
      end'''),
    ...para('--', r'Step two is for item names. It runs only for names of at least three characters that are not lowercase heads. The search is lowercase; each hit must be usable, must equal the lowercased name or contain it, and must not be a dependency already. Hits are sorted by downloads and cut to three. The note on each candidate says what it is and that it is a guess: the crate name, version and download count, then crates.io search by name, the path is a guess.'),
    ...sec(r'registering the source'),
    ...code('lua', r'lua/config/crate_import.lua · lines 274-282', r'''
local unregister
function M.setup()
  if unregister then
    return
  end
  unregister = require("config.import_engine").register_source(M.source, { async = true })
end

return M'''),
    ...para('--', r'setup registers M.source with the engine once and keeps the unregister function. The source is async, so the engine waits for it for up to its source_wait_ms and then goes on without it; a slow crates.io never holds up the menu. The spec has a case for exactly that (a slow source does not hold resolve beyond source_wait_ms).'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/crate-import_spec.lua stubs crates.io and cargo. It checks that the source fills gaps only, that a lowercase name yields the crate itself, that underscore names also try the dashed one, that item names give guesses ordered by downloads and labelled, that very short names and existing dependencies produce nothing, that offline or failing lookups give no candidates and no error, how the engine lists guesses after rust-analyzer candidates, the bounded wait, a failed add stopping early, an invalid name never reaching cargo, the add-only path, and that crate_add Add crate X command calls add_and_import. A final case is real: it starts from nothing, searches, adds the crate for Uuid, waits for rust-analyzer, imports and runs cargo build.'),
    ...sec(r'history'),
    ...para('--', r'The file has a single commit, b9363cd (2026-10-14), the same commit as crate_add, crate_features and import_engine. It has not been touched in the repository since, which is unusual in this group: the other modules took review, field-test and portability fixes.'),
    ...sec(r'the same file in xyno-crates.nvim'),
    ...para('--', r'On 2026-10-22 it was extracted as lua/xyno_crates/crate_import.lua. A diff shows only renaming: the header drops the plan item reference, crate_meta and code_actions are required from xyno_rust, the engine from xyno_imports.engine, the add from xyno_crates.crate_add, and the extmark namespace is xyno_crate_import. The logic is the same. In the plugin, setup() loads this module only when the import module is on (the default) and only after checking that xyno-imports.nvim is installed.'),
  ],
);
