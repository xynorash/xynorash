import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-crates.nvim/lua/xyno_crates/crate_add.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'crate_add.lua — "rand is not a dependency", then one keystroke to fix it'),
    cm('--', r'a conservative tree-sitter scan, an in-process language server, and cargo add behind pickers'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'unknown-crate hint + "Add crate X" code action + the :CrateAdd flow'),
    kv(r'language', r'Lua (Neovim 0.12+), tree-sitter rust parser'),
    kv(r'size', r'997 lines: scan, diagnostics, cargo add, UI, add_direct, server, setup'),
    kv(r'reaches', r'cargo metadata, crates.io (sparse index and search), cargo add, vim.diagnostic, vim.lsp'),
    kv(r'config', r'debounce_ms 300, max_diagnostics 50, cargo_timeout_ms 180000, max_lines 20000'),
    kv(r'history', r'xynovim b9363cd (2026-10-14), fixes 19f974c, b474307, ff1c8fa; extracted 5cd9905 (2026-10-22)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The flow is inspired by the dependency handling of the JetBrains IDEs, as the README says: write a path whose crate is not in Cargo.toml, get told so, fix it with a keystroke. In Neovim with rust-analyzer that does not exist. xynovim’s assessment (docs/PLAN_MACROS_DEPS.md, gap G3) measured it: with rand absent from the manifest, rust-analyzer returned zero code actions for rand::random::<u8>(), and its unresolved-name diagnostics are off on purpose because the experimental setting gave 82 false errors on a real workspace. The plan’s conclusion is the design of this file: "G3 needs its own, narrower check", and the finished-work row reads "Misses are accepted, false hints are not."'),
    blank,
    ...para('--', r'The file therefore holds two features that share one end. The scan finds path heads that cannot be anything the file refers to, and offers a one-click add. The :CrateAdd flow is the full version: search crates.io, choose features, choose the workspace member and table. Both finish in cargo add, run as an argv list, with every name validated first.'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_add.lua · lines 1-10', r'''
-- Crates from inside the editor:
--   * an unknown-crate check: a treesitter scan of `use` paths and expression /
--     type / attribute paths whose first segment is not known (std, a
--     dependency of the file's package, the own crate, a local module, an
--     import, ...) becomes a HINT diagnostic "crate 'rand' is not a
--     dependency" (namespace xyno-crates, source xyno-crates) with the code
--     action "Add crate rand";
--   * :CrateAdd [query]: search crates.io, pick the features, pick
--     the target, run `cargo add`.
--'''),
    ...sec(r'the scan: a miss is cheap, a false positive is not'),
    ...para('--', r'The comment before M.scan is a specification. Each bullet names a class of path head that is not flagged: std, core, alloc, proc_macro, test; the dependencies of this package only, by alias if renamed, including dev, build and target-specific ones; the own library name; modules (mod x, x.rs, x/mod.rs); local items and macro_rules names; anything bound by a use; uppercase heads (types, variants, Self); lowercase generic parameters; primitives; tool attributes; macro definitions and arguments; and, as whole-file escapes, globs that could bring a module into scope and edition 2015 packages. M.scan returns nil, not an empty list, when the check does not apply, including buffers above max_lines. The cap has a stated reason in xynovim’s changelog: reading or walking the whole buffer took 0.4 s per edit in a 45000-line file.'),
    blank,
    ...para('--', r'walk() is one recursive pass that gathers heads, the names the file binds (use trees, extern crate, type and const parameters) and glob imports. It refuses to look inside macro_definition, token_tree and ERROR nodes. The ERROR rule matters: a half-typed line is the normal state of a buffer being edited, and it must produce nothing instead of garbage.'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_add.lua · lines 270-301', r'''
  for _, g in ipairs(globs) do
    local h = g.head
    local harmless = h == "std" or h == "core" or h == "alloc" or h:match("^%u") ~= nil
    if not harmless and (h == "super" or h == "self") and has_ancestor_mod(g.node) then
      harmless = true
    end
    if not harmless then
      return {}
    end
  end

  local hits, seen = {}, {}
  for _, h in ipairs(heads) do
    local name = text(h, bufnr)
    local r, c, _, ec = h:range()
    if
      not NEVER[name]
      and not known_local[name]
      and not name:match("^%u")
      and cm.valid_name(name)
      and not name:find("-", 1, true)
      and not known(name)
      and not seen[r .. ":" .. c]
    then
      seen[r .. ":" .. c] = true
      hits[#hits + 1] = { name = name, lnum = r, col = c, end_col = ec }
      if #hits >= M.config.max_diagnostics then
        break
      end
    end
  end
  return hits'''),
    ...para('--', r'Before any head is judged, every glob is classified. Globs from std, core, alloc or an uppercase path are harmless; super and self globs only inside an inline mod. Anything else makes the function return an empty list, because the glob might import a module of any name. Commit b474307 added the dependency case after a field test: use predicates::prelude::* brings a module called predicate, and the hint fired on every open of tests/cli.rs. The earlier exception that treated a glob from a dependency as harmless was removed in that commit. Surviving heads then pass a chain of exclusions, the last being known(name), a memoised call to xyno-rust.nvim’s is_known_path_head. A hit carries zero-based row, column and end column so the underline is exactly the head.'),
    blank,
    ...sec(r'from hits to a diagnostic, without racing the user'),
    ...code('lua', r'lua/xyno_crates/crate_add.lua · lines 327-333', r'''
  cm.metadata_async(root, function(meta)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    if vim.api.nvim_buf_get_changedtick(bufnr) ~= tick then
      return M.schedule(bufnr) -- typed meanwhile: the next scan sees the new text
    end'''),
    ...para('--', r'refresh() is asynchronous because the first call in a workspace runs cargo metadata. The changedtick captured before the call is compared on return: if the buffer changed, the result is discarded and a debounced rescan scheduled, so a diagnostic is never put on text that no longer exists. If cargo metadata failed, the comment says the module "says nothing rather than call every crate unknown". Every exit that cannot be sure clears the hint. The diagnostic itself is a HINT in its own namespace, with code unknown-crate and user_data = { xyno_crate = name }, which is how the code action finds it later without parsing a message.'),
    blank,
    ...para('--', r'The debounce keeps one libuv timer per buffer: each event restarts it and the scan runs 300 ms after the last. BufDelete stops and closes the timer. refresh_all() reschedules every loaded Rust buffer, and runs after a manifest write and after cargo add, since a new dependency changes what is unknown everywhere.'),
    blank,
    ...sec(r'cargo add: an argv list, never a shell string'),
    ...code('lua', r'lua/xyno_crates/crate_add.lua · lines 405-409, 424-434', r'''
function M.build_argv(spec)
  -- valid_name allows a leading "-": `cargo add --git` would be a flag
  if not cm.valid_name(spec.name) or spec.name:sub(1, 1) == "-" then
    return nil, "invalid crate name"
  end
...
  if spec.default_features == false then
    argv[#argv + 1] = "--no-default-features"
  end
  if spec.features and #spec.features > 0 then
    for _, f in ipairs(spec.features) do
      if type(f) ~= "string" or not f:match(FEATURE_PAT) then
        return nil, "invalid feature name"
      end
    end
    vim.list_extend(argv, { "-F", table.concat(spec.features, ",") })
  end'''),
    ...para('--', r'build_argv is pure, which is why the spec can attack it. The first check teaches something: valid_name allows a leading dash, but cargo add --git would then read the "name" as a flag, so names starting with one are refused. Package becomes -p, kind becomes --dev or --build, an unticked default becomes --no-default-features, features are validated and joined into one -F, and --offline is appended when the earlier answers came from a cache. The version is left to cargo, which picks the newest release compatible with the package’s rust-version.'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_add.lua · lines 515-522', r'''
    local line = spec.manifest and M.added_line(spec.manifest, spec.name, spec.kind)
    local where = ("[%s]%s"):format(HEADERS[spec.kind or "normal"], spec.package and (" of " .. spec.package) or "")
    local msg = line and ("added %s  (%s)"):format(line, where) or ("added %s to %s"):format(spec.name, where)
    notify(msg)
    -- no BufWritePost ran for this edit: restart bacon-ls (and show "deps resolving") like a
    -- save would, or its stale E0433 / "cannot find derive macro" errors stay for minutes
    pcall(require("xyno_rust.rust_restart").manifest_saved, spec.manifest or (root .. "/Cargo.toml"))
    refresh_all()'''),
    ...para('--', r'run_add runs through cm.exec with a 180-second timeout, invalidates the metadata cache, and on failure shows cargo’s stderr (with an offline hint when it mentions the index). On success it reports the exact line cargo wrote, read back by added_line. The last call has a history: the comment explains that no BufWritePost ran, so bacon-ls would keep stale E0433 and "cannot find derive macro" errors for minutes. It was added in the review commit 19f974c, the day after the feature.'),
    blank,
    ...sec(r'the pickers: a seam, not a dependency'),
    ...code('lua', r'lua/xyno_crates/crate_add.lua · lines 533-541', r'''
M.ui = {}
function M.ui.pick(spec, cb)
  local Snacks = require("xyno_rust.deps").snacks()
  if not Snacks then
    return
  end
  Snacks.picker({
    title = spec.title,
    items = spec.items,'''),
    ...para('--', r'M.ui.pick takes one table and a callback and hides the picker. The specs replace it with a script; the real one uses snacks.nvim. The extraction changed exactly this spot: the original used the Snacks global, the plugin calls require("xyno_rust.deps").snacks() and returns after a one-line error when snacks.nvim is missing. In the multi-select case the confirm callback returns exactly what is ticked, even nothing, because default unticked with no feature ticked means --no-default-features. feature_items preselects default and labels it "on by default: deselect for --no-default-features", teaching the interface where it is used. target_items lists the current member first and marks a dependency that [workspace.dependencies] already has as inheriting it, because cargo add then writes name.workspace = true by itself.'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_add.lua · lines 711-719', r'''
      end
      local stale = list.stale or list.from_cache
      M.ui.pick({
        title = ("crates.io: %s%s  (name, version, downloads)"):format(q, list.stale and "  [cached, offline?]" or ""),
        items = items,
      }, function(sel)
        local name = sel[1].crate.name
        cm.info_async(name, function(info, ierr)
          local offline = (stale or (info and info.stale)) and true or false'''),
    ...para('--', r'In add(), stale is list.stale or list.from_cache, and it becomes the offline flag of cargo add, while the title’s "[cached, offline?]" label uses list.stale alone (19f974c, with the spec "a fresh cached answer is not labelled offline"). So a fresh cache hit is not labelled but still sets --offline. The code shows it plainly; which behaviour was meant is for the author to say.'),
    blank,
    ...sec(r'add_direct: the one-keystroke path'),
    ...code('lua', r'lua/xyno_crates/crate_add.lua · lines 749-766', r'''
function M.add_direct(bufnr, name, cb)
  local file = vim.api.nvim_buf_get_name(bufnr)
  local root = cm.root(file)
  if not root then
    return cb and cb(false, "not in a cargo workspace")
  end
  cm.metadata_async(root, function(meta, err)
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
      end'''),
    ...para('--', r'The code action and the import flow share this function: newest release, no features, the package of the buffer. The one decision is the kind: a file under tests/, benches/ or examples/ gets --dev, anything else the plain table. After success it schedules a rescan in 50 ms so the hint goes quickly.'),
    blank,
    ...sec(r'a language server that is not a process'),
    ...para('--', r'The header argues for it: the action is served "by a tiny in-process LSP server (vim.lsp.config with a cmd function, no process) rather than by wrapping vim.lsp.buf.code_action". Every consumer of the code-action API then sees one more client, nothing is monkey-patched, and it declares codeAction and executeCommand only.'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_add.lua · lines 806-818', r'''
        actions[#actions + 1] = {
          title = "Add crate " .. name,
          kind = "quickfix",
          isPreferred = true,
          diagnostics = { diag },
          command = { title = "Add crate " .. name, command = CMD_ADD, arguments = { { name = name, bufnr = bufnr } } },
        }
        actions[#actions + 1] = {
          title = "Add crate " .. name .. " (choose features and target)",
          kind = "quickfix",
          diagnostics = { diag },
          command = { title = "Add crate " .. name, command = CMD_PICK, arguments = { { name = name, bufnr = bufnr } } },
        }'''),
    ...para('--', r'actions_for turns the LSP range into byte positions, keeps the plugin’s own diagnostics that overlap it, once per crate, and returns two actions: "Add crate rand" (preferred, the default add) and "Add crate rand (choose features and target)", which opens the :CrateAdd flow with the name as the query.'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_add.lua · lines 831-836, 855-866', r'''
  local function close()
    if not closing then
      closing = true
      dispatchers.on_exit(0, 0)
    end
  end
...
    elseif method == "workspace/executeCommand" then
      local arg = params.arguments and params.arguments[1] or {}
      if type(arg.name) == "string" and cm.valid_name(arg.name) and arg.name:sub(1, 1) ~= "-" and type(arg.bufnr) == "number" and vim.api.nvim_buf_is_valid(arg.bufnr) then
        if params.command == CMD_ADD then
          -- one add path for the diagnostic action and the import picker
          require("xyno_crates.crate_import").add_and_import(arg.bufnr, { crate = arg.name })
        elseif params.command == CMD_PICK then
          vim.api.nvim_buf_call(arg.bufnr, function()
            M.add(arg.name)
          end)
        end
      end'''),
    ...para('--', r'The server is a table with request, notify, is_closing and terminate. executeCommand checks its argument before acting: a string, valid, no leading dash, and a buffer that still exists. CMD_ADD calls crate_import.add_and_import, "one add path for the diagnostic action and the import picker". close() reports on_exit exactly once; the comment says why: without it the client "stays in vim.lsp.get_clients() as a stopped entry" (fix b474307).'),
    blank,
    ...sec(r'setup: which events, which key'),
    ...code('lua', r'lua/xyno_crates/crate_add.lua · lines 901-915', r'''
  vim.lsp.config(M.server_name, {
    cmd = M.server,
    filetypes = { "rust" },
    -- one client per package, none for dependency sources and build output
    root_dir = function(bufnr, on_dir)
      local f = vim.api.nvim_buf_get_name(bufnr)
      if enabled() and M.applicable_file(f) then
        local r = vim.fs.root(f, "Cargo.toml")
        if r then
          on_dir(r)
        end
      end
    end,
  })
  vim.lsp.enable(M.server_name)'''),
    ...para('--', r'The first call wins (did_setup). root_dir is the second exclusion of dependency sources: it calls on_dir only when the check is enabled and applicable_file passes, so there is one client per package and none for ~/.cargo/registry or target/. The scan reruns after InsertLeave, TextChanged, BufWritePost and BufReadPost of a .rs file, and everything is rescanned when Cargo.toml or Cargo.lock is written.'),
    blank,
    ...code('lua', r'lua/xyno_crates/crate_add.lua · lines 936-947', r'''
  -- auto-save writes with noautocmd, so BufWritePost never fires for it
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "AutoSaveWritePost",
    callback = function(a)
      local b = a.data and a.data.saved_buffer
      if not (b and vim.api.nvim_buf_is_valid(b)) then
        return
      end
      local base = vim.fs.basename(vim.api.nvim_buf_get_name(b))
      if base == "Cargo.toml" or base == "Cargo.lock" then
        cm.invalidate()'''),
    ...para('--', r'An auto-save plugin that writes with noautocmd never fires BufWritePost, so the module listens to the User event AutoSaveWritePost, with the saved buffer in data; the README documents it. The key is optional and buffer-local in Rust and Cargo.toml buffers only.'),
    blank,
    ...sec(r'how it is tested'),
    ...para('--', r'tests/crate-add_spec.lua (854 lines) is hermetic where it can be: throwaway workspaces with path-only dependencies (cargo metadata needs no registry for them), stubbed pickers, crates.io client and cargo. The scan section is a table of cases taken from the comment list: flagged heads in use paths, expressions, types and attributes; nested lists; the exact range; the never-flagged set; the three glob rules; the line cap; the single on_exit; edition 2015. The flow section checks the argv for each target, the workspace marking, the cargo error path, the offline wording and the defaults fallback. A live test shows the hint within 3 seconds, finds "Add crate rand" through vim.lsp.buf.code_action, applies it and waits for the hint to vanish; another runs a real cargo add itoa and cargo check and skips without network or cargo. On Windows the live test is marked a known issue with the CI run number.'),
    blank,
    ...sec(r'history'),
    ...pt('--', r'b9363cd, 2026-10-14', r'added to xynovim at 973 lines with crate_features, crate_import, the import engine and the specs, in the commit "Macros and dependencies".'),
    ...pt('--', r'19f974c and b474307, 2026-10-15', r'review fixes (the manifest_saved call, the offline label), then field-test fixes (max_lines, the dependency-glob rule, the once-only on_exit).'),
    ...pt('--', r'ff1c8fa, 2026-10-16', r'Windows and macOS portability: slash() in applicable_file, binary mode for the manifest reader.'),
    ...pt('--', r'5cd9905, 2026-10-22', r'extraction: new names (xyno-crates for the namespace, server and diagnostic source, xyno.crateAdd and xyno.crateAddPick for the command ids), setup(opts) with commands and keymap, the snacks check. The diff against the xynovim file is 57 lines (both sides counted) of 997; the changes shown by the diff are renames, the options and the snacks check.'),
  ],
);
