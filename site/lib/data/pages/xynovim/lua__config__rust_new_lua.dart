import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/rust_new.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust_new.lua — new binaries, libraries, workspaces and members'),
    cm('--', r'cargo new, plus the workspace command cargo does not have, and a text'),
    cm('--', r'editor for the members list that keeps your formatting'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the engine of :RustNewBin, :RustNewLib, :RustNewWorkspace and :RustNewMember'),
    kv(r'language', r'Lua (Neovim 0.12; reuses the coroutine helpers of egui_new.lua)'),
    kv(r'size', r'900 lines, 3 commits (2026-10-16)'),
    kv(r'needs', r'cargo; git is optional'),
    kv(r'option', r'vim.g.xynovim_projects_dir (default ~/projects if it exists, else the cwd)'),
    kv(r'pure part', r'M.name .. M.add_member_path; every command is an argv list, run async'),
    kv(r'also lives in', r'xyno-new.nvim, lua/xyno_new/rust.lua (900 lines)'),
    ...sec(r'why this file exists'),
    ...para('--', r'cargo new makes a binary or a library, and that is all most people need. What it does not do is make a workspace: there is no one-step command, and a workspace needs a root manifest with a members list, shared package metadata and a .gitignore, plus a first member whose manifest inherits from the root. This file does that, and the three commands that go with it, from the dashboard of the editor. The older :RustNew in rust_tasks.lua stays; this file is the fuller replacement behind three dashboard entries.'),
    ...para('--', r'The header explains the workspace recipe, which is the design: a Cargo.toml with [workspace] (members = ["crates/*"]), [workspace.package] with the version and the edition THIS cargo uses for new projects, an empty [workspace.dependencies], a .gitignore with /target, the first member created by cargo new --vcs none crates/<member> whose version and edition then inherit from the workspace, and git init -b main without a commit.'),
    ...code('lua', r'lua/config/rust_new.lua · lines 1-22', r'''
-- New Rust projects: :RustNewBin [name], :RustNewLib [name], :RustNewWorkspace [name],
-- :RustNewMember [name] and the three dashboard entries 'New Rust Binary', 'New Rust Library',
-- 'New Rust Workspace' (lua/plugins/rust-new.lua). The older :RustNew (rust_tasks.lua) stays.
--
-- A binary / library is `cargo new --vcs git` in the chosen parent directory. cargo has no
-- one-step workspace command, so the workspace is built here: <parent>/<name>/Cargo.toml
-- ([workspace] with members = ["crates/*"], [workspace.package] with version and the edition
-- THIS cargo uses for new projects, an empty [workspace.dependencies]), .gitignore (/target),
-- the first member made by `cargo new --vcs none crates/<member>` whose version and edition
-- then inherit from the workspace, and `git init -b main` (no commit).
--
-- Options: vim.g.xynovim_projects_dir (parent directory, default ~/projects if it exists, else the cwd).
--
-- The text functions (M.name .. M.add_member_path) are pure; every external command is an argv
-- list run asynchronously (the coroutine helpers of config.egui_new); nothing is left behind
-- when a step fails.
local E = require("config.egui_new")

local M = {}

local NOTIFY_ID = "xynovim_rust_new"
local LABEL = "RustNew"'''),
    ...sec(r'names'),
    ...para('--', r'Name validation is cargo’s, borrowed from egui_new.lua (E.cargo_name), with one rule added: a name must start with a letter or an underscore as typed. That matters because cargo_name checks the crate form, in which a hyphen has already become an underscore; a name like -foo would look valid there while cargo would take it for an option. The function returns the name as typed and the crate identifier, because a hyphenated library keeps its name on disk and is used as an identifier with underscores in code. lib_note says that in one line only when they differ.'),
    ...code('lua', r'lua/config/rust_new.lua · lines 29-46', r'''
function M.name(raw)
  local name = vim.trim(raw or "")
  local crate, why = E.cargo_name(name)
  if not crate then
    return nil, why
  end
  if not name:match("^[%a_]") then
    return nil, "the name must start with a letter or '_'"
  end
  return name, crate
end

--- The note shown for a library whose name has hyphens, or nil.
function M.lib_note(name, crate)
  if crate ~= name then
    return ("library crate name: %s (use %s in Rust code)"):format(crate, crate)
  end
end'''),
    ...para('--', r'Unlike the egui flow, there are no template restrictions here: a Rust project may be called egui or log. The spec "does not carry the egui template’s own restrictions" pins the difference.'),
    ...sec(r'editions: ask cargo, never assume'),
    ...para('--', r'A workspace manifest has to state an edition, and the right one is whatever the installed cargo gives new projects, not a number remembered in this file. M.cargo_edition runs cargo new --vcs none --bin probe in a temporary directory, reads the edition back from the generated Cargo.toml, deletes the directory and remembers the answer for the session. The resolver follows from the edition: "3" for 2024 and newer, else "2".'),
    ...code('lua', r'lua/config/rust_new.lua · lines 63-98', r'''
--- Edition of the [package] table of a cargo-generated Cargo.toml, or nil.
function M.parse_edition(text)
  local in_package = false
  for line in (text or ""):gmatch("[^\r\n]+") do
    local header = line:match("^%s*%[([^%]]*)%]")
    if header then
      in_package = vim.trim(header) == "package"
    elseif in_package then
      local e = line:match('^%s*edition%s*=%s*"(%d+)"')
      if e then
        return e
      end
    end
  end
end

--- The resolver that goes with an edition: "3" for 2024 and newer, else "2".
function M.resolver(edition)
  return (tonumber(edition) or 0) >= 2024 and "3" or "2"
end

--- The workspace's Cargo.toml.
function M.workspace_toml(edition)
  return table.concat({
    "[workspace]",
    ('resolver = "%s"'):format(M.resolver(edition)),
    'members = ["crates/*"]',
    "",
    "[workspace.package]",
    'version = "0.1.0"',
    ('edition = "%s"'):format(edition),
    "",
    "[workspace.dependencies]",
    "",
  }, "\n")
end'''),
    ...code('lua', r'lua/config/rust_new.lua · lines 350-372', r'''
function M.cargo_edition()
  if edition_cache then
    return edition_cache
  end
  local tmp = vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/xynovim-edition-XXXXXX")
  if not tmp then
    fail("cannot write in " .. vim.uv.os_tmpdir())
  end
  local ok, res = pcall(function()
    cargo({ "new", "--vcs", "none", "--bin", "probe" }, tmp)
    local e = M.parse_edition(read_file(tmp .. "/probe/Cargo.toml") or "")
    if not e then
      fail("could not read the edition cargo uses for new projects")
    end
    return e
  end)
  vim.fn.delete(tmp, "rf")
  if not ok then
    error(res, 0)
  end
  edition_cache = res
  return res
end'''),
    ...para('--', r'The consequence is that this file needs no update when Rust ships a new edition, and a spec stubs cargo to prove the resolver follows the reported edition for 2018 and 2021 as well. The temporary directory is removed whether the probe succeeded or not; the error is re-raised after cleanup with error(res, 0).'),
    ...sec(r'inheriting from the workspace'),
    ...para('--', r'After cargo new creates a member, its manifest holds a literal version and edition. inherit rewrites them to version.workspace = true and edition.workspace = true, touching only those two keys and only inside [package], preserving whatever follows the value on the line (a comment). A which table lets the caller inherit only the keys the workspace actually defines.'),
    ...code('lua', r'lua/config/rust_new.lua · lines 102-122', r'''
function M.inherit(text, which)
  which = which or { version = true, edition = true }
  local out, in_package = {}, false
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    local header = line:match("^%s*%[([^%]]*)%]")
    if header then
      in_package = vim.trim(header) == "package"
    elseif in_package then
      for _, key in ipairs({ "version", "edition" }) do
        if which[key] then
          local indent, rest = line:match("^(%s*)" .. key .. '%s*=%s*"[^"]*"(.*)$')
          if indent then
            line = indent .. key .. ".workspace = true" .. rest
          end
        end
      end
    end
    out[#out + 1] = line
  end
  return table.concat(out, "\n")
end'''),
    ...para('--', r'That last point is used by :RustNewMember. Adding a member to a workspace the user wrote by hand, where [workspace.package] may have no edition, must not write edition.workspace = true into the member (cargo would reject it). workspace_package_keys reads which keys [workspace.package] provides, and the unprovided ones are kept in the member and listed in the final message.'),
    ...sec(r'reading and editing the members array'),
    ...para('--', r'The most careful code in the file is the one that edits a workspace manifest the user owns. There is no TOML parser in Neovim’s Lua, and a rewrite would destroy comments and layout, so members_array scans the text: it finds the [workspace] table, finds the members = [ line, then walks characters to the matching ], collecting quoted strings (with escapes in basic strings), ignoring # comments. It returns the list and the byte range of the brackets, or nil with a reason if the list is not closed or missing.'),
    ...para('--', r'workspace_info turns that into what the commands need: the members, the directory where new members go (the directory of the first dir/* glob, else crates) and which workspace.package keys exist. A members entry may be a glob; member_matches compares an entry with a relative path, using glob2regpat for * ? and [..] so crates/* covers crates/foo.'),
    ...code('lua', r'lua/config/rust_new.lua · lines 192-220', r'''
local function member_matches(entry, path)
  entry = entry:gsub("^%./", "")
  if entry == path then
    return true
  end
  if not is_glob(entry) then
    return false
  end
  return vim.fn.match(path, vim.fn.glob2regpat(entry)) >= 0
end

--- Read what :RustNewMember needs from a workspace root manifest: { members, dir, inherits }.
--- dir: where new members go (the directory of the first `dir/*` glob, else "crates").
--- Returns nil, reason when the manifest has no [workspace] members list.
function M.workspace_info(text)
  local list, range_or_why = members_array(text)
  if not list then
    return nil, range_or_why
  end
  local dir = "crates"
  for _, m in ipairs(list) do
    local d = m:match("^(.+)/%*$")
    if d and not is_glob(d) then
      dir = d:gsub("^%./", "")
      break
    end
  end
  return { members = list, dir = dir, inherits = workspace_package_keys(text) }
end'''),
    ...para('--', r'add_member_path is where a glob member means nothing needs to be done (the member is already covered and the manifest is not touched at all) and where an explicit list gets the new path inserted without reformatting. Both layouts are handled. A one-line list gets ", new" appended before the closing bracket, deciding the separator from what precedes. A multi-line list gets a new line after the last line that holds an entry, with the same indent, and a comma added after the previous entry if it lacked one.'),
    ...code('lua', r'lua/config/rust_new.lua · lines 237-249', r'''
  if not body:find("\n", 1, true) then -- one line: [a, b] -> [a, b, new]
    local trimmed_len = #body:gsub("%s+$", "")
    local head, tail = body:sub(1, trimmed_len), body:sub(trimmed_len + 1)
    local sep
    if head:match("^%s*$") then
      sep = ""
    elseif head:match(",$") then
      sep = " "
    else
      sep = ", "
    end
    return text:sub(1, range.first) .. head .. sep .. quoted .. tail .. text:sub(range.last)
  end'''),
    ...para('--', r'Review commit e166947 made it robust to the cases a real manifest has. A line can hold several entries, so the comma goes after the closing quote of the LAST one, found by scanning with quote state and stopping at a # (a comment can contain quotes). An empty multi-line list is handled and keeps a comment that follows the opening bracket. And a CRLF manifest keeps its line endings: every inserted line carries the same CR.'),
    ...code('lua', r'lua/config/rust_new.lua · lines 275-297', r'''
  local indent = lines[last]:match("^%s*")
  -- the last entry needs a comma before the new one: after the closing quote of the LAST entry
  -- on the line (a line can hold several; a comment can hold quotes)
  local code = lines[last]
  local quote, last_close = nil, nil
  for i = 1, #code do
    local c = code:sub(i, i)
    if quote then
      if c == quote then
        quote, last_close = nil, i
      end
    elseif c == '"' or c == "'" then
      quote = c
    elseif c == "#" then
      break
    end
  end
  if last_close and not code:sub(last_close + 1):gsub("#.*$", ""):find(",", 1, true) then
    code = code:sub(1, last_close) .. "," .. code:sub(last_close + 1)
  end
  lines[last] = code
  table.insert(lines, last + 1, indent .. quoted .. "," .. cr)
  return text:sub(1, range.first) .. table.concat(lines, "\n") .. text:sub(range.last)'''),
    ...sec(r'running cargo, and cleaning up when it fails'),
    ...para('--', r'All three creators have the same shape: validate, check that the target does not exist, create what is missing, run cargo, edit, and on any error remove exactly what this run created. They run inside E.run_async, so a failing step raises and the runner’s callback does the clean-up. The cargo helper wraps E.sys with an argv list and turns a non-zero exit into an error with the first useful stderr line (first_line prefers a line starting with "error", else the first non-empty line).'),
    ...code('lua', r'lua/config/rust_new.lua · lines 333-345', r'''
--- Run cargo (argv) inside run_async; fails with cargo's first stderr line.
local function cargo(args, cwd)
  local cmd = { "cargo" }
  vim.list_extend(cmd, args)
  local ok, o = pcall(E.sys, cmd, { cwd = cwd })
  if not ok then
    fail("cargo could not be started: " .. tostring(o))
  end
  if o.code ~= 0 then
    fail("cargo " .. args[1] .. " failed: " .. M.first_line(o.stderr))
  end
  return o
end'''),
    ...para('--', r'create_project is the simple one: refuse an existing target, create missing parents (remembering them, and removing them again if creating one fails), then cargo new --bin or --lib with --vcs git. The target is flagged as made just before cargo runs, so on error the callback deletes the directory only if it exists, then removes the parents it created while empty.'),
    ...code('lua', r'lua/config/rust_new.lua · lines 421-450', r'''
function M.create_project(p, cb)
  local created, target, target_made = {}, nil, false
  E.run_async(function()
    local name = M.name(p.name)
    if not name then
      fail("invalid name: " .. tostring(p.name))
    end
    if p.kind ~= "binary" and p.kind ~= "library" then
      fail("unknown kind: " .. tostring(p.kind))
    end
    need_cargo()
    target = p.parent .. "/" .. name
    if vim.uv.fs_lstat(target) then
      fail("the target already exists: " .. target)
    end
    created = make_parents(p.parent)
    progress(("cargo new (%s) ..."):format(p.kind))
    target_made = true
    cargo({ "new", kind_flag(p.kind), "--vcs", "git", name }, p.parent)
    return { dir = target, kind = p.kind, name = name, file = target .. "/" .. main_file(p.kind) }
  end, function(err, info)
    if err then
      if target_made and target and vim.uv.fs_lstat(target) then
        vim.fn.delete(target, "rf")
      end
      rmdirs(created)
    end
    cb(err, info)
  end)
end'''),
    ...para('--', r'create_workspace adds the hard part. Order matters: the edition is asked of cargo first (before anything is written), then parents, then the root directory, then Cargo.toml and .gitignore, then the member through cargo new --vcs none, then inherit, then git init -b main. A failure at any step removes the whole root. The result carries the edition, the resolver and a git note for the final message, because a missing or failing git is reported, not fatal.'),
    ...code('lua', r'lua/config/rust_new.lua · lines 473-490', r'''
    progress("asking cargo for the edition of new projects ...")
    local edition = M.cargo_edition()
    created = make_parents(p.parent)
    if not vim.uv.fs_mkdir(root, 493) then
      fail("cannot write in " .. p.parent)
    end
    root_made = true
    write_file(root .. "/Cargo.toml", M.workspace_toml(edition))
    write_file(root .. "/.gitignore", "/target\n")
    progress(("cargo new (%s %s) ..."):format(p.kind, member))
    cargo({ "new", kind_flag(p.kind), "--vcs", "none", "crates/" .. member }, root)
    local mdir = root .. "/crates/" .. member
    local manifest = mdir .. "/Cargo.toml"
    local text = read_file(manifest)
    if not text then
      fail("cargo did not write " .. manifest)
    end
    write_file(manifest, M.inherit(text))'''),
    ...para('--', r'create_member is the one that edits a file it did not create, so it keeps the original text and restores it on error. It reads the manifest, parses it with workspace_info, derives the relative path from the member directory, asks cargo to create the crate, and then puts the manifest back and applies add_member_path itself. The comment gives the reason: cargo adds the path to an explicit list on its own but rewrites the list’s layout, so the file is restored and edited here with the formatting preserved. If the new text equals what is on disk it is not rewritten at all.'),
    ...code('lua', r'lua/config/rust_new.lua · lines 554-566', r'''
    cargo({ "new", kind_flag(p.kind), "--vcs", "none", rel }, p.root)
    -- cargo adds the new path to an explicit list itself, but rewrites the list's layout: the
    -- manifest is put back and the path added here, keeping the formatting
    local edited = M.add_member_path(original, rel)
    if (edited or original) ~= read_file(manifest) then
      write_file(manifest, edited or original)
    end
    local mm = mdir .. "/Cargo.toml"
    local text = read_file(mm)
    if not text then
      fail("cargo did not write " .. mm)
    end
    write_file(mm, M.inherit(text, ws.inherits))'''),
    ...sec(r'the prompts'),
    ...para('--', r'The commands are built from small pieces. ask_name accepts the command argument if it is valid and otherwise shows the reason and asks, taking an optional extra check (used by :RustNewMember to refuse a taken name). parent_check is the parent directory prompt’s validator: existing directory without the target in it, or a missing one after a confirmation. ask_kind uses vim.ui.select for binary or library. A running flag makes a second command refuse while one is in progress.'),
    ...code('lua', r'lua/config/rust_new.lua · lines 781-798', r'''
--- :RustNewBin / :RustNewLib: name, parent directory, then cargo new.
function M.new_project(kind, name_arg)
  if busy() then
    return
  end
  ask_name("Project name: ", name_arg, nil, function(name, crate)
    if kind == "library" then
      local note = M.lib_note(name, crate)
      if note then
        notify(note)
      end
    end
    ask("Parent directory: ", E.default_parent(), parent_check(name), function(parent)
      running = true
      M.create_project({ name = name, parent = parent, kind = kind }, done_with(M.finish_project))
    end)
  end)
end'''),
    ...para('--', r'new_workspace has one extra step. nesting_warning looks at the parent directory and its ancestors for two traps: an enclosing workspace whose members already cover the new directory (cargo would then see two workspace roots and the new one would stop working), and an enclosing git work tree (the new repository would be nested). It asks the user to confirm, defaulting to No. The first member’s default name is the workspace name plus -app or -core, depending on the kind chosen.'),
    ...code('lua', r'lua/config/rust_new.lua · lines 665-687', r'''
function M.nesting_warning(parent, name)
  local dir = require("config.fsutil").slash(parent):gsub("/+$", "")
  while dir ~= "" do
    local rel = (parent:sub(#dir + 1) .. "/" .. name):gsub("^/", "")
    local text = read_file(dir .. "/Cargo.toml")
    local ws = text and M.workspace_info(text)
    if ws then
      for _, m in ipairs(ws.members) do
        if member_matches(m, rel) then
          return ("%s is a workspace whose members cover %s: it would stop working"):format(dir, rel)
        end
      end
    end
    if vim.uv.fs_stat(dir .. "/.git") then
      return ("%s is inside the git repository %s: the new one would be nested"):format(parent, dir)
    end
    local up = dir:match("^(.*)/[^/]*$")
    if not up or up == dir then
      break
    end
    dir = up
  end
end'''),
    ...para('--', r'new_member works from the current buffer. current_workspace finds the cargo root through rust_context, reads the root manifest and requires a [workspace] members list. Before asking the name, it runs cargo metadata --no-deps --offline and collects the package names with hyphens turned to underscores, so a member named foo-bar is refused when foo_bar exists. The question about a name is therefore answered by cargo’s own view of the workspace, not by directory names.'),
    ...code('lua', r'lua/config/rust_new.lua · lines 851-866', r'''
  local root, ws = current_workspace()
  if not root then
    return vim.notify(LABEL .. ": " .. ws, vim.log.levels.ERROR, { title = LABEL })
  end
  running = true
  local taken = {}
  E.run_async(function()
    local o = E.sys({ "cargo", "metadata", "--no-deps", "--offline", "--format-version", "1" }, { cwd = root })
    if o.code == 0 then
      local ok, meta = pcall(vim.json.decode, o.stdout)
      if ok and type(meta) == "table" then
        for _, pkg in ipairs(meta.packages or {}) do
          taken[(pkg.name:gsub("-", "_"))] = true
        end
      end
    end'''),
    ...sec(r'finishing'),
    ...para('--', r'The finish functions enter the new project and print a message built to be useful: the created path, the layout of a new workspace as text (layout), the library crate name when it differs, a next step (cargo run, or cargo test for a library, with -p member inside a workspace), the git note, and for a member the keys the workspace did not provide. M.setup registers the four user commands, each with an optional name argument.'),
    ...sec(r'the dashboard entries'),
    ...para('--', r'The three entries (New Rust Binary on b, New Rust Library on i, New Rust Workspace on w) are not defined here but in lua/plugins/rust-new.lua, which sees this module only through command names. See that page; the plugin file explains how the entries sit before the egui entry whatever order the specs are merged in.'),
    ...sec(r'in xyno-new.nvim'),
    ...para('--', r'The file moved to lua/xyno_new/rust.lua in ~/projects/xyno-plugins/xyno-new.nvim on 2026-10-22 with the same 900 lines. The differences are naming and wiring only. It requires xyno_new.egui instead of config.egui_new for the shared helpers, and fsutil and rust_context come from xyno_rust.*. The projects directory option is vim.g.xyno_new_projects_dir. The temporary edition probe directory is called xyno-new-edition-XXXXXX instead of xynovim-edition-XXXXXX, the notification id is xyno_new_rust, and the next-step hints mention :RustTargets where this file says <leader>rX. The header says the dashboard entries live in xyno_new.dashboard. Everything that touches cargo and TOML is identical.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/rust-new_spec.lua (1114 lines here, 1003 in the plugin) mixes pure tables and real cargo. The pure sections cover names (hyphens kept, shared rules with the egui flow, the extra start rule), first_line, edition parsing and the workspace manifest for 2018, 2021 and 2024, inherit on cargo’s real output as well as on hand text with comments and CRLF, workspace_info and add_member_path (one-line and multi-line lists, a covered path, only [workspace] touched, several entries on a line, an empty list with a comment, CRLF), and nesting_warning.'),
    ...para('--', r'The "real cargo" sections create projects and check them with cargo itself: a binary and a library with a git repository, the installed cargo’s edition, missing parents; a workspace with inherited version and edition, workspace_members in cargo metadata and a clean cargo check with a binary and a library member; glob and explicit-list members, a collision between foo-bar and foo_bar, a manifest without a members list, and the manifest restored when cargo fails. Failure paths use a stub cargo and a read-only parent to show that nothing is left behind, parents included. The last section drives the prompts.'),
    ...sec(r'history'),
    ...pt('--', r'd163480 2026-10-16', r'"New Rust Binary, Library and Workspace entries on the dashboard": the file is added at 848 lines with its spec, the plugin spec and the options.lua call to setup().'),
    ...pt('--', r'e166947 2026-10-16', r'review fixes (61 lines added, 9 removed): the add_member_path cases above, and nesting_warning with its confirmation in new_workspace.'),
    ...pt('--', r'ff1c8fa 2026-10-16', r'portability: the nesting walk uses fsutil.slash so Windows paths work.'),
    ...sec(r'rough edges worth knowing'),
    ...pt('--', r'nesting_warning', r'walks up with a pattern that stops when no slash is left; the filesystem root itself is never examined for a Cargo.toml or .git. In practice it only matters for a project created directly under /.'),
    ...pt('--', r'edition cache', r'the edition is cached for the whole session. If cargo is updated while the editor stays open, a new workspace still gets the older edition until restart (reset_edition exists but only for specs).'),
  ],
);
