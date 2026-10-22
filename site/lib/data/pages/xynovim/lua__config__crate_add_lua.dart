import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/crate_add.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'crate_add.lua — add a crate without leaving the file'),
    cm('--', r'a conservative unknown-crate hint, "Add crate rand", and :CrateAdd'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'unknown-crate diagnostic, code action and the crates.io add flow'),
    kv(r'language', r'Lua for Neovim 0.12 with treesitter (rust parser), Snacks picker'),
    kv(r'size', r'986 lines, 4 commits (2026-10-14 to 2026-10-16)'),
    kv(r'spec', r'tests/crate-add_spec.lua (841 lines)'),
    kv(r'commands', r':CrateAdd [query], <leader>rA, code action "Add crate X"'),
    kv(r'also lives in', r'xyno-crates.nvim as lua/xyno_crates/crate_add.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'Writing use rand::Rng; in a project that does not depend on rand gives an error far from the cause: rust-analyzer says unresolved import, and the fix lives in a different file and a different language. This module closes the loop in three steps. It notices that the first segment of a path is not a crate you have, it offers Add crate rand in the normal code-action menu, and it provides :CrateAdd to search crates.io, pick features and pick which package and table to edit. The plan items it refers to in its first line are 1.1 and 1.2 (gap G3).'),
    ...code('lua', r'lua/config/crate_add.lua · lines 12-23', r'''
-- with a `cmd` function, no process) rather than by wrapping
-- vim.lsp.buf.code_action: every consumer of the LSP code-action API (<leader>ca,
-- the lightbulb, vim.lsp.buf.code_action with a filter, code_actions.lua)
-- then sees it as one more client, nothing is monkey-patched, and the
-- diagnostics and the actions stay in one place. It declares codeAction and
-- executeCommand only, so it takes part in nothing else (no formatting,
-- hover, completion, semantic tokens).
--
-- False positives are worse than misses: the rule set is conservative, see
-- M.scan. Everything that runs a command uses argv lists, and crate names,
-- feature names and package names are validated before they reach one.
local M = {}'''),
    ...para('--', r'Two decisions in the header shape everything. First, the action is served by a tiny in-process LSP server with a cmd function rather than by wrapping vim.lsp.buf.code_action: every consumer of the code-action API (the menu, the lightbulb, code_actions.lua) then sees it as one more client and nothing is monkey-patched. It declares codeAction and executeCommand only. Second, a sentence that governs the scanner: false positives are worse than misses. A wrong hint that says a crate you already have is missing destroys trust faster than a missed one costs anything.'),
    ...sec(r'the scan: what is a crate head'),
    ...code('lua', r'lua/config/crate_add.lua · lines 27-33, 41-45', r'''
M.config = {
  debounce_ms = 300,
  max_diagnostics = 50, -- per buffer
  cargo_timeout_ms = 180000,
  max_lines = 20000, -- the scan walks the whole tree: larger buffers (generated code) are skipped
}

...
-- #[clippy::...]) and primitive types (u32::MAX)
local NEVER = {}
for _, n in ipairs(vim.split("rustfmt clippy rustc rustdoc miri rust_analyzer diagnostic u8 u16 u32 u64 u128 usize i8 i16 i32 i64 i128 isize f32 f64 bool char str", " ")) do
  NEVER[n] = true
end'''),
    ...para('--', r'The configuration limits work: a 300 ms debounce, 50 diagnostics per buffer, a 3 minute cargo timeout and a 20000-line cap (added in field-test commit b474307: the scan walks the whole tree, so generated files are skipped). NEVER lists first segments that are never crates, tool attributes like rustfmt and clippy and the primitive types, so u32::MAX is not a crate named u32.'),
    ...para('--', r'use_head finds the leftmost segment of a use tree when it is a plain identifier reached through a path: rand in rand::Rng, rand::{a, b}, rand::* and rand::x as y. A bare use foo; and crate, self and super give nothing. This is treesitter node-type handling, because a regular expression cannot tell rand::{a, b::c} from a path inside a macro. use_bound, next to it, collects every name a use tree binds (the alias, or the last segment, with self binding its parent), so use std::io; io::x() is understood and io is not called a crate.'),
    ...para('--', r'applicable_file keeps the check to .rs files of a package. Paths inside the cargo registry, cargo git checkouts and any /target/ directory are excluded, so dependency sources and build output are never annotated. The separator is normalized through fsutil.slash first (ff1c8fa) so the same test works with Windows paths.'),
    ...code('lua', r'lua/config/crate_add.lua · lines 155-170', r'''
--- Scan buffer `bufnr` and return the unknown crate heads:
--- { { name, lnum, col, end_col } ... } (0-based), or nil when the check does
--- not apply (no rust parser, not a member file, edition 2015, a glob import
--- of something that could bring any name into scope).
---
--- NOT flagged (each is a miss in the worst case, never a false error):
---   * std / core / alloc / proc_macro / test, `crate` `self` `super`, and
---     anything crate_meta.is_known_path_head knows: dependencies of THIS
---     package (renames by their alias, dev- and build-dependencies, target-
---     specific ones), the package's own lib name, modules (`mod x`, x.rs,
---     x/mod.rs), local items, macro_rules names
---   * names bound by a `use` anywhere in the file (`use std::io; io::x()`,
---     `use foo as bar`), `extern crate foo [as bar]`
---   * heads starting with an uppercase letter (types, enum variants, Self),
---     lowercase generic parameters, primitive types, tool attributes
---   * everything inside macro_rules! definitions and macro arguments (the'''),
    ...para('--', r'The doc comment of M.scan is the best description of the design, and it is a list of what is NOT flagged: the std crates, keywords, anything crate_meta.is_known_path_head knows (dependencies of this package by alias, its own lib name, modules, local items, macro_rules names); names bound by any use or extern crate; heads that start with an uppercase letter (types, variants, Self); generic parameters; everything inside macro_rules! and macro arguments; edition 2015 packages. Each of these is, in the worst case, a miss and never a false error.'),
    ...para('--', r'The early returns are the first filters: no file that applies, no metadata, too many lines, a file outside every workspace member, any target of edition 2015 (where paths are relative to the crate root), no rust parser. Each returns nil, which the caller reads as the check does not apply here, and clears the diagnostics.'),
    ...code('lua', r'lua/config/crate_add.lua · lines 214-230', r'''
    if t == "use_declaration" then
      local arg = field(n, "argument") or n:named_child(n:named_child_count() - 1)
      if arg then
        use_bound(arg, bufnr, known_local, globs)
        if arg:type() == "use_list" then
          for c in arg:iter_children() do
            if c:named() then
              local h = use_head(c)
              if h then
                heads[#heads + 1] = h
              end
            end
          end
        else
          local h = use_head(arg)
          if h then
            heads[#heads + 1] = h'''),
    ...para('--', r'The walk is one recursive descent over named children. It stops at macro_definition, token_tree and ERROR nodes (macro tokens are not parsed paths, and half-typed code must not be called unknown). A use declaration feeds use_bound and collects heads, either from each item of a use list or from the argument; an extern crate adds a known name; type and const parameters add known names (a lowercase generic); and every scoped identifier whose path is a plain identifier contributes a head.'),
    ...code('lua', r'lua/config/crate_add.lua · lines 264-280', r'''
    if memo[name] == nil then
      memo[name] = cm.is_known_path_head(rootdir, name, { file = file, meta = meta }) ~= nil
    end
    return memo[name]
  end

  for _, g in ipairs(globs) do
    local h = g.head
    local harmless = h == "std" or h == "core" or h == "alloc" or h:match("^%u") ~= nil
    if not harmless and (h == "super" or h == "self") and has_ancestor_mod(g.node) then
      harmless = true
    end
    if not harmless then
      return {}
    end
  end'''),
    ...para('--', r'Before reporting, glob imports are judged. A glob from std, core, alloc or something that starts with an uppercase letter (an enum) is harmless; super or self inside an inline mod is harmless; anything else makes the function return an empty list for the whole file, because use crate::prelude::* or use predicates::prelude::* may bring any module into scope. The dependency case was a field-test fix in b474307: the old code treated a glob from a dependency as harmless, so the file was still scanned and predicate (brought in by use predicates::prelude::*) was flagged; now such a file stays quiet, and the spec case is named after that crate. The last loop applies the filters in one condition, memoizes the is_known_path_head answer per name, de-duplicates by position and stops at max_diagnostics.'),
    ...sec(r'diagnostics and timing'),
    ...code('lua', r'lua/config/crate_add.lua · lines 322-335', r'''
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local root = cm.root(file)
  if not root then
    return cb and cb(nil)
  end
  cm.metadata_async(root, function(meta)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    if vim.api.nvim_buf_get_changedtick(bufnr) ~= tick then
      return M.schedule(bufnr) -- typed meanwhile: the next scan sees the new text
    end
    if not meta then
      -- cargo metadata failed (broken manifest, no network for a first'''),
    ...para('--', r'refresh is careful about three kinds of staleness. The changedtick is read before the asynchronous metadata call and compared after: if the buffer changed meanwhile it reschedules instead of publishing hints for old text. If cargo metadata failed (a broken manifest, no network for a first resolve) it resets the namespace and says nothing, as the comment states, rather than call every crate unknown. And any scan failure is caught with pcall. The diagnostic is a HINT with source xynovim, code unknown-crate and user_data carrying the crate name that the code action reads back.'),
    ...para('--', r'schedule keeps one libuv timer per buffer and restarts it on each call, which is a debounce; the callback checks the buffer is still valid. A BufDelete autocommand stops and closes the timer, so closing buffers does not leak handles.'),
    ...sec(r'building the cargo add command'),
    ...code('lua', r'lua/config/crate_add.lua · lines 405-412', r'''
function M.build_argv(spec)
  -- valid_name allows a leading "-": `cargo add --git` would be a flag
  if not cm.valid_name(spec.name) or spec.name:sub(1, 1) == "-" then
    return nil, "invalid crate name"
  end
  local argv = { "cargo", "add", spec.name }
  if spec.package ~= nil then
    if not cm.valid_name(spec.package) then'''),
    ...para('--', r'build_argv returns an argv list or nil plus a reason, and never a string for a shell. The first check has a comment that names a real hazard: valid_name allows a leading dash, and a name like --git would be a cargo flag, so the leading dash is refused here. Package, kind and every feature name are validated too (features against ^[A-Za-z0-9_.+-]+$). The version is left to cargo, which picks the newest release compatible with the rust-version of the package; the spec asserts the argv for each flag and the refusals.'),
    ...code('lua', r'lua/config/crate_add.lua · lines 498-505', r'''
function M.run_add(root, spec, cb)
  local argv, err = M.build_argv(spec)
  if not argv then
    notify("cannot add: " .. err, vim.log.levels.ERROR)
    return cb and cb(false, err)
  end
  notify("cargo add " .. table.concat(vim.list_slice(argv, 3), " ") .. " ...")
  cm.exec(argv, { cwd = root, timeout = M.config.cargo_timeout_ms }, function(r)'''),
    ...para('--', r'run_add runs cargo add in the workspace root with the 3 minute timeout, invalidates the metadata afterwards, and turns failures into messages: cargo own stderr, with a hint appended when it mentions the index plus resolve, network or download (probably offline). On success it reads back the line cargo wrote (added_line looks in the right dependency table, including target-specific ones) and reports it. The comment before manifest_saved was added in review (19f974c): cargo add edits Cargo.toml without a BufWritePost, so bacon-ls would keep stale E0433 and cannot find derive macro errors for minutes unless it is restarted as a save would. Then every open Rust buffer is rescanned.'),
    ...sec(r'the interactive flow'),
    ...code('lua', r'lua/config/crate_add.lua · lines 546-557', r'''
        end
      end
    end,
    confirm = function(p, item)
      -- multi: exactly what is ticked, also nothing (`default` unticked and no
      -- feature ticked means --no-default-features); a plain pick: the item
      local sel = spec.multi and p:selected() or { item }
      p:close()
      if spec.multi or sel[1] then
        cb(sel)
      end
    end,'''),
    ...para('--', r'The picker is a seam: M.ui.pick is replaced by specs, and the real one is a Snacks picker with the select layout. The confirm function comment is the subtle part: in multi mode it returns exactly what is ticked, including nothing. That matters because for features, default unticked and no feature ticked means --no-default-features. This module uses the global Snacks; the extracted plugin looks it up through a dependency check and returns quietly when it is absent (see the last section).'),
    ...para('--', r'feature_items lists default first and preselected, then the rest alphabetically, each with the list of what it enables, or no dependencies. The label for default tells you what deselecting it does. The features come from the sparse index through crate_meta.info_async, so they are the features of the newest release.'),
    ...code('lua', r'lua/config/crate_add.lua · lines 668-683', r'''
    local features, default_on = {}, false
    for _, it in ipairs(sel) do
      if it.feature == "default" then
        default_on = true
      else
        features[#features + 1] = it.feature
      end
    end
    -- a crate without a `default` feature has nothing to switch off
    if not (info.features and info.features.default) then
      default_on = true
    end
    target_step(features, default_on)
  end)
end'''),
    ...para('--', r'choose_and_add is steps three and four. A crate with no features skips straight to the target pick. Otherwise the multi pick runs and its result is translated: a ticked default means default features stay on, anything else is a feature. The line "a crate without a default feature has nothing to switch off" forces default_on back to true, so a crate with no default does not get a pointless --no-default-features. The target pick lists every member times the three dependency tables, current member first, and target_items marks the normal table with (inherits [workspace.dependencies]) when the workspace root already lists the crate.'),
    ...para('--', r'M.add ties it together and degrades gracefully when offline. It needs a workspace root (from the buffer or the cwd). A search result that was served from the cache marks the whole flow offline, and then cargo add gets --offline. If the feature list cannot be fetched it warns and continues with defaults. In 19f974c the picker title was fixed to use list.stale: a fresh cached answer must not be labelled offline.'),
    ...code('lua', r'lua/config/crate_add.lua · lines 752-768', r'''
    local member = meta and cm.member_of(meta, file)
    if not member then
      notify("cannot add " .. name .. ": " .. tostring(err or "file is not in a workspace member"), vim.log.levels.ERROR)
      return cb and cb(false, err)
    end
    local rel = file:sub(#member.dir + 2)
    local kind = (rel:match("^tests/") or rel:match("^benches/") or rel:match("^examples/")) and "dev" or "normal"
    M.run_add(root, { name = name, kind = kind, package = member.name, manifest = member.manifest_path }, function(ok, msg)
      if ok then
        M.schedule(bufnr, 50)
      end
      if cb then
        cb(ok, msg)
      end
    end)
  end)
end'''),
    ...para('--', r'add_direct is the one-click path used by the diagnostic action: newest release, no features, into the package of the buffer, and into dev-dependencies when the file is under tests/, benches/ or examples/. After success it reschedules the scan for that buffer after 50 ms so the hint disappears. crate_import.add_and_import uses this same function, which is how Add crate rand, the import picker and the import of an unknown name share one add path.'),
    ...sec(r'the in-process server'),
    ...para('--', r'actions_for answers a code-action request from the diagnostics in this module namespace. It converts the LSP range (UTF-16) to byte positions, picks the hints that overlap, and returns two actions for each crate: Add crate rand, marked preferred, which runs xynovim.crateAdd, and Add crate rand (choose features and target), which runs xynovim.crateAddPick and opens the :CrateAdd flow with the name as query. The hint diagnostic is attached to the action so clients can show it as the one it fixes.'),
    ...code('lua', r'lua/config/crate_add.lua · lines 856-868', r'''
          require("config.crate_import").add_and_import(arg.bufnr, { crate = arg.name })
        elseif params.command == CMD_PICK then
          vim.api.nvim_buf_call(arg.bufnr, function()
            M.add(arg.name)
          end)
        end
      end
      reply(cb, nil, vim.NIL)
    else
      reply(cb, nil, vim.NIL)
    end
    return true, id
  end'''),
    ...para('--', r'The server follows the same lifecycle as the one in crate_features: on_exit is reported once from exit or terminate (the stopped-client fix, b474307). executeCommand re-validates the arguments, including the leading dash rule and that the buffer is still valid, before it calls add_and_import or M.add. Every reply goes through vim.schedule so the callback is never synchronous.'),
    ...sec(r'setup and wiring'),
    ...para('--', r'setup registers the server with vim.lsp.config and vim.lsp.enable. Its root_dir function returns a root only for files that pass applicable_file and have a Cargo.toml above them, giving one client per package and none for dependency sources.'),
    ...code('lua', r'lua/config/crate_add.lua · lines 937-946', r'''
      local base = vim.fs.basename(vim.api.nvim_buf_get_name(b))
      if base == "Cargo.toml" or base == "Cargo.lock" then
        cm.invalidate()
        refresh_all()
      elseif vim.bo[b].filetype == "rust" then
        M.schedule(b)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufDelete", {'''),
    ...para('--', r'The autocommands are the interesting part. Auto-save writes with noautocmd, so BufWritePost never fires for it; the User AutoSaveWritePost event is listened to and does a rescan (or a metadata invalidation for Cargo.toml and Cargo.lock). The spec group crate_add follows auto-save covers it.'),
    ...code('lua', r'lua/config/crate_add.lua · lines 958-970', r'''
  vim.api.nvim_create_user_command("CrateAdd", function(a)
    M.add(a.args)
  end, { nargs = "?", desc = "Search crates.io and cargo add (features, target)" })

  -- <leader>rA: buffer-local in Rust and Cargo.toml buffers only (keymaps.lua parks
  -- global "not bound" stubs on every <leader>r key and the specs allow no other global one)
  local function map(buf)
    vim.keymap.set("n", "<leader>rA", "<cmd>CrateAdd<cr>", { buffer = buf, desc = "Add crate (crates.io search)" })
  end
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "rust", "toml" },
    callback = function(a)'''),
    ...para('--', r':CrateAdd is created, and <leader>rA is mapped only buffer-locally in Rust and Cargo.toml buffers. The comment explains the reason: keymaps.lua parks global not bound stubs on every <leader>r key and the specs allow no other global one. The plugin spec lua/plugins/crate-add.lua loads this on the VeryLazy event, with the comment that a virtual lazy.nvim plugin would be one more entry in the plugin count.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/crate-add_spec.lua covers the scan from both sides (what is flagged: use paths, expression paths, types, attributes, nested lists, exact range; what is never flagged: std, dependencies, renames, dev-dependencies, own crate, modules, imports, generics, globs, large buffers, edition 2015, dependency sources), build_argv and its refusals, the :CrateAdd flow with stubbed crates.io and cargo (columns, argv per target, workspaces, offline, error display), the hint and code action in a real editor within 3 seconds, the switch vim.g.xynovim_crate_check = false, the real Snacks picker, auto-save, and one real run that adds itoa to a copy of the deps-lab fixture and builds it.'),
    ...sec(r'history'),
    ...pt('--', r'b9363cd · 2026-10-14', r'added in the dependencies commit'),
    ...pt('--', r'19f974c · 2026-10-15', r'review: bacon-ls restart after cargo add, picker label fix'),
    ...pt('--', r'b474307 · 2026-10-15', r'field test: line cap, dependency globs, client exit'),
    ...pt('--', r'ff1c8fa · 2026-10-16', r'portability: slash-normalized paths, binary-mode reads'),
    ...sec(r'the same file in xyno-crates.nvim'),
    ...para('--', r'On 2026-10-22 this file became lua/xyno_crates/crate_add.lua in xyno-crates.nvim. The scan, the argv builder, the flow and the server are line for line the same. A diff shows these differences. Names move from xynovim to xyno: namespace and client xyno-crates, source xyno-crates, commands xyno.crateAdd and xyno.crateAddPick, switch vim.g.xyno_crate_check, notification id xyno-crates-add. Requires of config.crate_meta, fsutil and rust_restart become xyno_rust.* and the import call becomes xyno_crates.crate_import. The pick uses xyno_rust.deps.snacks() and returns quietly when Snacks is missing, instead of using the global Snacks directly. setup takes opts: the command is created unless commands is false, and the key is bound only when a string is given (buffer-local in Rust and Cargo.toml, default suggestion <leader>rA). The sentence that mentions plan items and the key in the header is shortened.'),
  ],
);
