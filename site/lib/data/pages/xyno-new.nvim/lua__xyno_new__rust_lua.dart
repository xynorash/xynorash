import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-new.nvim/lua/xyno_new/rust.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'lua/xyno_new/rust.lua — binaries, libraries, workspaces, members'),
    cm('--', r'the part of cargo that cargo does not have, built carefully'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'four commands, nine pure text functions, three creators that clean up after a failure'),
    kv(r'language', r'Lua, 900 lines; every external command is an argv list'),
    kv(r'commands', r'RustNewBin RustNewLib RustNewWorkspace RustNewMember'),
    kv(r'talks to', r'cargo new, cargo metadata --offline, git init, xyno_rust.rust_context'),
    kv(r'origin', r'lua/config/rust_new.lua in xynovim: d163480 (2026-10-16), fixed in e166947, ported in ff1c8fa'),
    kv(r'tested by', r'tests/rust-new_spec.lua, 51 cases, real cargo'),
    ...sec(r'why this file exists'),
    ...para('--', r'cargo new makes a package. Rust developers who grow past one crate want a workspace, and cargo has no command that makes one: you create a directory, write a manifest with a [workspace] table by hand, then create members and remember to point them at the workspace’s shared version and edition. The point of this module is to do those steps in the right order, with cargo’s own name rules enforced up front, and to leave nothing behind when any step fails.'),
    ...para('--', r'It arrived in xynovim in d163480 on 2026-10-16 as lua/config/rust_new.lua, 848 lines, with a 1,074-line spec and a lazy.nvim spec that added the dashboard entries. Review fixes followed within the hour (e166947, the same day, 70 lines changed in rust_new.lua) and a portability pass for Windows and macOS (ff1c8fa) touched two lines of it. This file is that module under the namespace xyno_new, 900 lines, the same count as xynovim’s lua/config/rust_new.lua has after those two commits.'),
    ...para('--', r'The header comment states the creation plan in prose, and it is worth reading as the contract of the whole file.'),
    ...code('lua', r'lua/xyno_new/rust.lua · lines 1-16', r'''
-- New Rust projects: :RustNewBin [name], :RustNewLib [name], :RustNewWorkspace [name],
-- :RustNewMember [name]. The older :RustNew of xyno_rust.rust_tasks stays. (The dashboard
-- entries are in xyno_new.dashboard.)
--
-- A binary / library is `cargo new --vcs git` in the chosen parent directory. cargo has no
-- one-step workspace command, so the workspace is built here: <parent>/<name>/Cargo.toml
-- ([workspace] with members = ["crates/*"], [workspace.package] with version and the edition
-- THIS cargo uses for new projects, an empty [workspace.dependencies]), .gitignore (/target),
-- the first member made by `cargo new --vcs none crates/<member>` whose version and edition
-- then inherit from the workspace, and `git init -b main` (no commit).
--
-- Options: vim.g.xyno_new_projects_dir (parent directory, default ~/projects if it exists, else the cwd).
--
-- The text functions (M.name .. M.add_member_path) are pure; every external command is an argv
-- list run asynchronously (the coroutine helpers of xyno_new.egui); nothing is left behind
-- when a step fails.'''),
    ...para('--', r'Three decisions are visible. The older :RustNew of xyno_rust.rust_tasks stays (the header comment says so). The workspace is built by hand because cargo has no one-step command. And the commit is deliberately missing: git init -b main makes a repository but commits nothing, and the header comment says “no commit”.'),
    ...sec(r'the name rules'),
    ...code('lua', r'lua/xyno_new/rust.lua · lines 29-39', r'''
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
end'''),
    ...para('--', r'M.name delegates to E.cargo_name, the validator that lives in egui.lua, so the Rust flows and the egui flow share one definition of a legal cargo name (keywords, reserved names, the 64-character limit, non-ASCII characters named whole). Rust adds exactly one rule on top: the name as typed must start with a letter or underscore. The reason is the hyphen: cargo_name converts - to _ before checking, so -foo would pass as _foo, yet cargo new -foo would read the name as an option. Checking the raw name closes that gap, and the spec “does not carry the egui template’s own restrictions” keeps the template-only rules out of the Rust flows.'),
    ...para('--', r'The return convention is (name, crate): the name as typed, because cargo accepts hyphens in package names, and the crate identifier, because that is what Rust code will say. lib_note turns the difference into a message: library crate name: my_lib (use my_lib in Rust code). It is shown for libraries only (finish_project and new_project call it only for kind library).'),
    ...sec(r'reading cargo’s output instead of guessing it'),
    ...code('lua', r'lua/xyno_new/rust.lua · lines 49-61', r'''
function M.first_line(stderr)
  local first
  for line in (stderr or ""):gmatch("[^\r\n]+") do
    line = vim.trim(line)
    if line ~= "" then
      first = first or line
      if line:match("^error") then
        return line
      end
    end
  end
  return first or "no output"
end'''),
    ...para('--', r'first_line is the error-reporting rule for every cargo call: a stderr stream is reduced to the first line starting with error, else the first non-empty line, else the words no output. A failed cargo new then surfaces as cargo new failed: error: … in one notification instead of a wall of text. The spec uses a stub cargo that prints an error line and a second line and checks that only the error line comes through.'),
    ...para('--', r'parse_edition walks the generated Cargo.toml line by line, tracking whether it is inside [package], and returns the first edition = "NNNN" it finds there. It does not use a TOML parser; the input is the manifest cargo has just written, and the in_package flag is the whole reason the function is correct on a manifest where another table has an edition key. The spec reads “the edition of a generated Cargo.toml’s [package] only”.'),
    ...sec(r'the workspace manifest'),
    ...code('lua', r'lua/xyno_new/rust.lua · lines 85-98', r'''
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
    ...para('--', r'The manifest is a table.concat of lines, with the edition and resolver substituted. members = ["crates/*"] is a glob, which is why :RustNewMember later has so little to do on a workspace this plugin created: cargo already counts anything under crates/. [workspace.package] carries version = "0.1.0" and the discovered edition, so members can inherit them. [workspace.dependencies] is present and empty.'),
    ...para('--', r'Resolver 3 belongs to edition 2024 and newer; 2 is correct for the 2021 and 2018 editions. The spec builds manifests for 2018, 2021 and 2024, and a second spec fakes an older cargo with a shell stub that rewrites the edition after cargo new, then checks that the resolver in the manifest follows.'),
    ...sec(r'inheriting: a small state machine'),
    ...code('lua', r'lua/xyno_new/rust.lua · lines 102-122', r'''
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
    ...para('--', r'inherit rewrites version = "0.1.0" into version.workspace = true and edition = "2024" into edition.workspace = true, but only inside [package], and only the keys requested. The which argument defaults to both. The pattern keeps the indentation and whatever follows the string, so a trailing comment survives. Nothing else in the file changes, byte for byte, which the spec checks on text that the installed cargo really writes, not just on a literal in the test file.'),
    ...para('--', r'The which argument is what makes :RustNewMember honest. If the workspace’s [workspace.package] has no edition, inheriting it would make the member fail to build; so create_member passes ws.inherits, computed from the workspace manifest, and the final notification says [workspace.package] has no edition: kept in the member.'),
    ...sec(r'editing the members list without destroying it'),
    ...para('--', r'This is the most careful code in the plugin. :RustNewMember must add a path to the workspace’s members array if the array is an explicit list. cargo adds the path to an explicit list itself but, as a comment in create_member says, rewrites the list’s layout. So the module parses just enough: it finds the array, remembers its byte range, and edits text.'),
    ...code('lua', r'lua/xyno_new/rust.lua · lines 138-167', r'''
        local list, quote, i = {}, nil, first + 1
        local cur
        while i <= #text do
          local c = text:sub(i, i)
          if quote then
            if c == "\\" and quote == '"' then
              cur = cur .. text:sub(i, i + 1)
              i = i + 1
            elseif c == quote then
              list[#list + 1] = cur
              quote, cur = nil, nil
            else
              cur = cur .. c
            end
          elseif c == '"' or c == "'" then
            quote, cur = c, ""
          elseif c == "#" then
            i = (text:find("\n", i, true) or #text) -- a comment up to the end of the line
          elseif c == "]" then
            return list, { first = first, last = i }
          end
          i = i + 1
        end
        return nil, "the members list of [workspace] is not closed"
      end
    end
    pos = eol + 1
  end
  return nil, "no `members = [...]` list in [workspace]"
end'''),
    ...para('--', r'members_array scans line by line for the [workspace] header, finds a line starting members = [, and then walks character by character from the opening bracket. It tracks a quote character (single or double), honours backslash escapes only inside double quotes (TOML literal strings have none), skips from # to end of line, and stops at the closing bracket. It returns the strings and the byte range { first, last } of the brackets. An unclosed list gives a reason string rather than a crash. Because the walk crosses lines, a multi-line array with comments in it is handled by the same code as a one-liner.'),
    ...code('lua', r'lua/xyno_new/rust.lua · lines 225-249', r'''
function M.add_member_path(text, path)
  local list, range = members_array(text)
  if not list then
    return nil, range
  end
  for _, m in ipairs(list) do
    if member_matches(m, path) then
      return text
    end
  end
  local quoted = '"' .. path .. '"'
  local body = text:sub(range.first + 1, range.last - 1)
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
    ...para('--', r'add_member_path has three layouts to preserve and handles each separately. A one-line list [a, b] becomes [a, b, "new"], with the separator chosen from what precedes (nothing, a trailing comma, or neither). A multi-line list gets a new line after the last line that holds an entry, with that line’s indentation, and a comma inserted after the previous last entry only if one is not already there. An empty multi-line list gets the entry on its own line before the closing bracket, keeping a comment after the opening bracket. CRLF files get CRLF in the lines this function writes (the cr variable). All of those were bugs fixed in the review commit e166947: before it, a line with several entries and a comment containing a quote could get its comma in the wrong place, and an empty list with a comment lost the comment.'),
    ...sec(r'plumbing: files, cargo, and the edition probe'),
    ...code('lua', r'lua/xyno_new/rust.lua · lines 358-371', r'''
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
  return res'''),
    ...para('--', r'The edition probe runs cargo new --vcs none --bin probe in a fresh temporary directory from vim.uv.fs_mkdtemp, reads back the Cargo.toml, and caches the answer in a module-level variable. The directory is deleted whether or not the probe worked. The cache is per session, so a user who updates their toolchain mid-session keeps the old answer until restarting Neovim; reset_edition exists for the specs. The spec “asks cargo for the edition once per session” counts invocations with a logging stub: two workspaces cause three cargo calls in total, one probe and two member creations.'),
    ...sec(r'leaving nothing behind'),
    ...para('--', r'Every creator keeps the same books. make_parents walks up from the requested directory to the first one that exists, creates the missing ones top-down and returns the list (removing them again if a mkdir fails midway). rmdirs removes them in reverse with fs_rmdir, which refuses a directory that is not empty: even if something had landed in a parent this run created, the cleanup cannot delete it, and it cannot reach parents that existed before.'),
    ...sec(r'create_project: the simplest transaction'),
    ...para('--', r'The work runs inside E.run_async, the coroutine runner defined in egui.lua. It validates the name and kind, requires cargo, refuses an existing target (fs_lstat, so a dangling symlink counts), makes the parents, and only then sets target_made and runs cargo new --vcs git. On failure the callback deletes the target only if target_made says this run reached cargo, so a target that appeared from elsewhere is never removed by an unrelated early failure.'),
    ...code('lua', r'lua/xyno_new/rust.lua · lines 431-440', r'''
    need_cargo()
    target = p.parent .. "/" .. name
    if vim.uv.fs_lstat(target) then
      fail("the target already exists: " .. target)
    end
    created = make_parents(p.parent)
    progress(("cargo new (%s) ..."):format(p.kind))
    target_made = true
    cargo({ "new", kind_flag(p.kind), "--vcs", "git", name }, p.parent)
    return { dir = target, kind = p.kind, name = name, file = target .. "/" .. main_file(p.kind) }'''),
    ...sec(r'create_workspace: build, then inherit'),
    ...code('lua', r'lua/xyno_new/rust.lua · lines 473-490', r'''
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
    ...para('--', r'The order is chosen so that the expensive and fallible things come first: validate both names and the kind, require cargo, refuse an existing root, and only then ask cargo for the edition. The probe comes before any directory is made, so a broken cargo leaves nothing to clean. The root is made with mkdir, Cargo.toml and .gitignore are written, and the member is created by cargo new with --vcs none and the path crates/<member>, run from the root. Because the root’s Cargo.toml already has a members glob, cargo recognises the new package as a workspace member.'),
    ...para('--', r'Then the member’s own manifest is read back and rewritten through M.inherit, and git init -q -b main runs if git exists. Git trouble is not fatal: a failing init or a missing git becomes git_note, returned in info and shown in the final notification, because a workspace without a repository is still a good workspace. The returned table carries everything the finisher needs: dir, name, kind, member, edition, resolver, the file to open, and the note.'),
    ...para('--', r'The failure callback is the mirror image: if root_made, delete the root recursively, then rmdirs the parents. The spec “a workspace whose member step fails leaves no directory behind” stubs cargo so that only the probe succeeds and then verifies the parent directory is empty again.'),
    ...sec(r'create_member: restore, do not trust'),
    ...code('lua', r'lua/xyno_new/rust.lua · lines 547-560', r'''
    local rel = ws.dir .. "/" .. name
    mdir = p.root .. "/" .. rel
    if vim.uv.fs_lstat(mdir) then
      fail("the target already exists: " .. mdir)
    end
    progress(("cargo new (%s %s) ..."):format(p.kind, name))
    mdir_made = true
    cargo({ "new", kind_flag(p.kind), "--vcs", "none", rel }, p.root)
    -- cargo adds the new path to an explicit list itself, but rewrites the list's layout: the
    -- manifest is put back and the path added here, keeping the formatting
    local edited = M.add_member_path(original, rel)
    if (edited or original) ~= read_file(manifest) then
      write_file(manifest, edited or original)
    end'''),
    ...para('--', r'Here the manifest the user owns is at stake, so the creator keeps the original text in a variable from the start and writes it back on any failure with pcall. It refuses a name whose crate identifier is in p.taken, which the prompt flow fills from cargo metadata so that my-app and my_app count as the same package. cargo new adds the path to an explicit list on its own, but with its own formatting, so the module puts the original text back and applies add_member_path instead, comparing with what is on disk and writing only if they differ. The comment in the code says it in one line: the manifest is put back and the path added here, keeping the formatting.'),
    ...para('--', r'Finally the member’s manifest inherits only the keys the workspace provides. The result lists not_inherited, so the notification can explain why a member kept its own edition.'),
    ...sec(r'finishing: tell the user what happened'),
    ...para('--', r'enter does :cd into the new project and edits the main file. The final notification names the directory, the library note if any, and a next step that points at :RustTargets, a command of the sibling xyno-rust.nvim. In xynovim the same hint named a key; the README lists that as one of the differences made on extraction.'),
    ...sec(r'nesting: the question cargo will not ask'),
    ...code('lua', r'lua/xyno_new/rust.lua · lines 665-687', r'''
function M.nesting_warning(parent, name)
  local dir = require("xyno_rust.fsutil").slash(parent):gsub("/+$", "")
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
    ...para('--', r'The code comment says a workspace created under another workspace’s members makes cargo find two workspace roots, and the warning text says it “would stop working”. The same check covers a git repository inside another. nesting_warning walks upward from the parent directory, reads every Cargo.toml it meets, asks workspace_info for members, checks whether any matches the relative path of the new workspace, and checks for a .git entry. The first problem found is returned as a sentence; the prompt flow turns it into a Yes/No confirm that defaults to No. xyno_rust.fsutil.slash is the one use of the sibling plugin outside root detection: it normalises backslashes on Windows so the same string logic runs everywhere. This function was added in the review commit e166947; the xynovim version had no slash call, which was added in the Windows pass.'),
    ...sec(r'the prompts'),
    ...para('--', r'The prompt layer is thin on purpose. ask passes the label RustNew to E.ask, which calls vim.ui.input, treats nil as a silent cancel, re-asks with the reason in the prompt text on failure and gives up after ten tries; so a user’s input plugin replaces the prompt box with no change here, and the specs replace vim.ui.input and vim.ui.select with stubs. parent_check expands ~, rejects a file, rejects a parent that already holds the target name, and asks vim.fn.confirm (default No) before a missing directory is created. new_workspace chains name, parent, nesting warning, kind and member name; the member name is prefilled with the workspace name plus -app or -core, which is why the kind is asked first. The running flag is set only when work starts, so an open prompt never blocks another command, while busy() refuses a second concurrent creation.'),
    ...sec(r'new_member: ask cargo what is taken'),
    ...code('lua', r'lua/xyno_new/rust.lua · lines 857-866', r'''
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
    ...para('--', r'new_member finds the workspace through xyno_rust.rust_context.root for the current buffer (or the cwd when the buffer has no name), reads its manifest and refuses with a specific message: not inside a cargo project, cannot read the manifest, or not a workspace with a members list. Then, inside the coroutine runner, it asks cargo metadata --no-deps --offline for the packages and records every name with - turned into _. The command is run with --offline and --no-deps. If metadata fails, the table stays empty and the prompt still works; the filesystem check on the target directory in the prompt and in create_member still applies.'),
    ...sec(r'setup'),
    ...code('lua', r'lua/xyno_new/rust.lua · lines 885-892', r'''
function M.setup()
  vim.api.nvim_create_user_command("RustNewBin", function(a)
    M.new_project("binary", a.args)
  end, { nargs = "?", desc = "New Rust binary (cargo new --bin)" })
  vim.api.nvim_create_user_command("RustNewLib", function(a)
    M.new_project("library", a.args)
  end, { nargs = "?", desc = "New Rust library (cargo new --lib)" })
  vim.api.nvim_create_user_command("RustNewWorkspace", function(a)'''),
    ...para('--', r'Four user commands, each nargs = "?" with a description, each a one-line call into the module. Defining them in the module (not in init.lua) is what lets someone use the plugin without the front door: require("xyno_new.rust").setup() is the full activation.'),
    ...sec(r'trade-offs and limits'),
    ...pt('--', r'No TOML parser', r'everything is line and character scanning on the few shapes cargo writes. That is fragile in theory and exhaustively specified in practice (the add_member_path specs cover one-liners, multi-line lists, comments, CRLF, several entries per line, empty lists).'),
    ...pt('--', r'Edition cached per session', r'a toolchain change needs a Neovim restart.'),
    ...pt('--', r'Git is optional', r'a missing git only produces a note.'),
    ...pt('--', r'One project at a time', r'a module-level running flag, not a queue.'),
    ...pt('--', r'Linux and macOS specs only', r'the spec header says xyno-os: linux,macos because it writes sh cargo stubs.'),
    ...sec(r'history'),
    ...pt('--', r'd163480 (2026-10-16, xynovim)', r'rust_new.lua created, 848 lines, with rust-new_spec.lua (1,074 lines) and the dashboard entries.'),
    ...pt('--', r'e166947 (2026-10-16, xynovim)', r'review fixes: CRLF-safe and comment-safe member insertion, the scanner that finds the last closing quote, and nesting_warning.'),
    ...pt('--', r'ff1c8fa (2026-10-16, xynovim)', r'portability pass: two lines of this file changed.'),
    ...pt('--', r'01f8e4c (2026-10-22, here)', r'the module moved in under the namespace xyno_new; the file went from 900 lines to 900 lines.'),
  ],
);
