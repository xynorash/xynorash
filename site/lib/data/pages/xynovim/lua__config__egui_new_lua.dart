import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/egui_new.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'egui_new.lua — a new egui project from the template as it is today'),
    cm('--', r':EguiNew downloads emilk/eframe_template, makes it yours, and cleans up'),
    cm('--', r'after itself on every path'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the :EguiNew command and the engine behind the New egui Project dashboard entry'),
    kv(r'language', r'Lua (Neovim 0.12: vim.system, vim.uv, coroutines, vim.ui.input)'),
    kv(r'size', r'1048 lines, 7 commits (2026-10-15 to 2026-10-16)'),
    kv(r'needs', r'curl, and unzip (or tar on Windows); git is optional'),
    kv(r'options', r'vim.g.xynovim_projects_dir, xynovim_egui_template, xynovim_egui_build_after_new'),
    kv(r'pure part', r'M.validate_name .. M.readme are plain functions; nothing from the template runs'),
    kv(r'also lives in', r'xyno-new.nvim, lua/xyno_new/egui.lua (1048 lines, same length)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The egui project to start from is the eframe_template repository, and its own README tells you how to personalise it: run fill_template.sh, which edits the crate name, authors and titles in place. Starting a project that way means cloning, running a script you did not write, and deleting history. This file does the same personalisation from inside Neovim, as a non-interactive flow with prompts: it fetches the CURRENT template as a ZIP, edits the text files with pure functions, and writes the result into a fresh directory.'),
    ...para('--', r'The header comment makes the central choices explicit. The template is downloaded each time it is needed and never copied into this repository, so it cannot go stale in the config. The personalisation follows the template’s README and fill_template.sh: crate name, authors, the window and page title, and the web build file names in assets/sw.js. The pure text edits are functions you can test without a network; every external command is an argv list; and nothing from the template is executed.'),
    ...code('lua', r'lua/config/egui_new.lua · lines 1-17', r'''
-- :EguiNew [name] and the "New egui Project" dashboard entry: a new project
-- from the CURRENT https://github.com/emilk/eframe_template (downloaded as a
-- ZIP, never a copy kept here), personalised the way the template's README and
-- fill_template.sh describe: crate name, authors, window / page title, the web
-- build file names in assets/sw.js.
--
-- Options (all optional):
--   vim.g.xynovim_projects_dir              parent directory (default ~/projects if it exists, else the cwd)
--   vim.g.xynovim_egui_template             { repo = "emilk/eframe_template", ref = "main", base_url = "https://github.com" }
--   vim.g.xynovim_egui_build_after_new      true: run `cargo build` in a terminal afterwards
--
-- The template's rust-toolchain file is never copied (it would make rustup install one exact
-- toolchain); its Cargo.toml rust-version stays as the minimum, and a warning says when rustc is older.
--
-- The text edits (M.validate_name .. M.readme) are pure functions; every
-- external command is an argv list, nothing from the template is executed.
local M = {}'''),
    ...sec(r'names: what cargo accepts, and what the template forbids'),
    ...para('--', r'A project name becomes a crate name, so the rules are cargo’s. cargo_name returns the identifier (hyphens turned into underscores) and a note when it converted something. It names the whole offending UTF-8 character in its error (the pattern takes a lead byte plus its continuation bytes), enforces a 64 character limit, a letter-or-underscore start, refuses a lone underscore, Rust keywords (the list is cargo’s restricted_names) and the names cargo and the standard library reserve.'),
    ...code('lua', r'lua/config/egui_new.lua · lines 52-78', r'''
function M.cargo_name(raw)
  local name = vim.trim(raw or "")
  if name == "" then
    return nil, "the name is empty"
  end
  local bad = name:match("[^%w_%-][\128-\191]*") -- the whole UTF-8 character
  if bad then
    return nil, ("'%s' is not allowed: use letters, digits, '_' and '-'"):format(bad)
  end
  local crate = name:gsub("-", "_")
  if #crate > 64 then
    return nil, "the name is longer than 64 characters"
  end
  if not crate:match("^[%a_]") then
    return nil, "the name must start with a letter or '_'"
  end
  if crate == "_" then
    return nil, "'_' alone is not a valid name"
  end
  if KEYWORDS[crate] then
    return nil, ("'%s' is a Rust keyword"):format(crate)
  end
  if RESERVED[crate] then
    return nil, ("'%s' is reserved by cargo / the standard library"):format(crate)
  end
  return crate, nil, crate ~= name and ("crate name: " .. crate) or nil
end'''),
    ...para('--', r'validate_name layers the template’s own restrictions on top: the project may not be called eframe_template (the token the replacement works on) and may not share a name with a dependency of the template, such as egui, eframe, log or serde, since a package with that name would shadow the dependency. In the flow the dependency list is read again from the real downloaded Cargo.toml (dependency_names), so a dependency the static list does not know is also caught. The split matters later: cargo_name was extracted in commit d163480 so that rust_new.lua could share it without inheriting the template-specific rules.'),
    ...code('lua', r'lua/config/egui_new.lua · lines 82-94', r'''
function M.validate_name(raw)
  local crate, why, note = M.cargo_name(raw)
  if not crate then
    return nil, why
  end
  if crate == TOKEN then
    return nil, "'eframe_template' is the template's own name: pick another"
  end
  if DEPENDENCIES[crate] then
    return nil, ("'%s' is the name of a dependency of the template"):format(crate)
  end
  return crate, nil, note
end'''),
    ...para('--', r'Author fields are checked too. check_author refuses control characters, double quotes, backslashes and angle brackets, because the value ends up inside a TOML string (authors = ["Name <mail>"]) and a format("Name <email>"). An e-mail may not contain spaces. format_author returns nil when both are empty, which means the authors line is removed.'),
    ...sec(r'editing text without breaking it'),
    ...para('--', r'The text functions are written for exactness, since a template change should not make them damage a file. replace_token replaces eframe_template with the crate name everywhere except in links to the template: an occurrence preceded by github.com/emilk/, emilk.github.io/, deps.rs/repo/github/emilk/ or emilk/ is left alone, because that is a credit or a link and not a name. The search is plain (no patterns), so a crate name with pattern characters cannot confuse it. The same shape with the title token turns "eframe template" into the readable title.'),
    ...code('lua', r'lua/config/egui_new.lua · lines 135-160', r'''
local URL_PREFIXES = { "github.com/emilk/", "emilk.github.io/", "deps.rs/repo/github/emilk/", "emilk/" }

local function in_template_url(text, s)
  for _, p in ipairs(URL_PREFIXES) do
    if s > #p and text:sub(s - #p, s - 1) == p then
      return true
    end
  end
  return false
end

--- 'eframe_template' -> crate everywhere except inside links to the template.
function M.replace_token(text, crate)
  local out, pos = {}, 1
  while true do
    local s, e = text:find(TOKEN, pos, true)
    if not s then
      break
    end
    out[#out + 1] = text:sub(pos, s - 1)
    out[#out + 1] = in_template_url(text, s) and TOKEN or crate
    pos = e + 1
  end
  out[#out + 1] = text:sub(pos)
  return table.concat(out)
end'''),
    ...para('--', r'edit_cargo_toml works line by line and only inside [package]. It replaces the name value while keeping what follows it on the line, replaces a multi-line authors array whole (it advances to the line holding the closing bracket), and, when authors are wanted but absent, inserts the line right after the name. A trailing CR is preserved so a CRLF file stays CRLF; everything else is kept byte for byte.'),
    ...code('lua', r'lua/config/egui_new.lua · lines 180-216', r'''
function M.edit_cargo_toml(text, crate, authors)
  local lines = vim.split(text, "\n", { plain = true })
  local out, in_pkg, name_at, has_authors = {}, false, nil, false
  local i = 1
  while i <= #lines do
    local line = lines[i]
    local header = line:match("^%s*(%[.-%])%s*") -- [package] possibly followed by a comment
    if header then
      in_pkg = header == "[package]"
      out[#out + 1] = line
    elseif in_pkg and line:match("^%s*name%s*=") then
      local pre, post = line:match('^(%s*name%s*=%s*)"[^"]*"(.*)$')
      out[#out + 1] = pre and (pre .. '"' .. crate .. '"' .. post) or line
      name_at = #out
    elseif in_pkg and line:match("^%s*authors%s*=") then
      has_authors = true
      -- a multi-line array runs to its closing bracket
      local j = i
      while not lines[j]:find("]", 1, true) and j < #lines do
        j = j + 1
      end
      local cr = line:sub(-1) == "\r" and "\r" or ""
      if authors then
        out[#out + 1] = ('authors = ["%s"]%s'):format(authors, cr)
      end
      i = j
    else
      out[#out + 1] = line
    end
    i = i + 1
  end
  if authors and not has_authors and name_at then
    local cr = out[name_at]:sub(-1) == "\r" and "\r" or ""
    table.insert(out, name_at + 1, ('authors = ["%s"]%s'):format(authors, cr))
  end
  return table.concat(out, "\n")
end'''),
    ...para('--', r'Cargo.lock is the subtle file. cargo keeps [[package]] entries sorted by name, so renaming the template’s own entry in place could leave the lock out of order, and then cargo build --locked would want to rewrite it. edit_cargo_lock splits the file into package blocks, finds the entry named eframe_template, renames it, and decides: if the new name still sorts between its neighbours it is a plain substitution that keeps every other byte, otherwise the block is moved to its sorted place and the blocks are rejoined (a trailing [metadata] or patch table is kept as a tail). The spec checks both branches.'),
    ...code('lua', r'lua/config/egui_new.lua · lines 274-284', r'''
  local renamed = blocks[hit]:gsub('\nname = "' .. TOKEN .. '"', function()
    return '\nname = "' .. crate .. '"'
  end, 1)
  local prev, nxt = names[hit - 1], names[hit + 1]
  local sorted = (not prev or prev <= crate) and (not nxt or nxt >= crate)
  if sorted then -- stays where it is: a plain substitution keeps every other byte
    local s = starts[hit]
    local before = text:sub(1, s - 1)
    local old = blocks[hit]
    return before .. renamed .. text:sub(s + #old)
  end'''),
    ...para('--', r'The README is regenerated, not edited. md_section extracts a section of the template’s README by a heading match (case-insensitive, ignoring "#" lines inside code fences, stopping at the next heading of the same or higher level). readme builds the new file from the template’s "testing locally" and "web locally" sections, with plain fallback text if the template changes its headings, plus the generated licence note. The generated README credits :EguiNew and links back to the template.'),
    ...sec(r'walking the unpacked template'),
    ...para('--', r'personalise walks every regular file of the unpacked tree. It skips .git, files over 1 MB, the template README (regenerated at the end), anything named LICENSE or COPYING, and anything containing a NUL byte, so images are never rewritten. Cargo.lock goes to the lock editor, everything else gets the token and title replacement, and Cargo.toml additionally gets the manifest edit. A file is written only if its text changed, and the list of changed files is returned.'),
    ...code('lua', r'lua/config/egui_new.lua · lines 450-465', r'''
  -- the template's own personalisation scripts are obsolete now
  for _, f in ipairs({ "fill_template.sh", "fill_template.ps1" }) do
    if vim.uv.fs_stat(dir .. "/" .. f) then
      vim.uv.fs_unlink(dir .. "/" .. f)
    end
  end
  -- the toolchain pin is never copied (it forces rustup to install one exact toolchain); the
  -- Cargo.toml rust-version, the minimum, stays
  for _, f in ipairs({ "rust-toolchain", "rust-toolchain.toml" }) do
    if vim.uv.fs_lstat(dir .. "/" .. f) then
      vim.uv.fs_unlink(dir .. "/" .. f)
    end
  end
  write_file(dir .. "/README.md", M.readme({ title = o.title, crate = o.crate, template_readme = template_readme }))
  return res
end'''),
    ...para('--', r'Two removals happen here deliberately. fill_template.sh and fill_template.ps1 are deleted because personalisation is done, and leaving them would invite running them again. And rust-toolchain and rust-toolchain.toml are deleted: the pin would make rustup install one exact toolchain on first use, which is a surprising side effect of creating a project. The Cargo.toml rust-version field is left untouched as the minimum.'),
    ...sec(r'fetching: a conditional download with an offline cache'),
    ...para('--', r'cfg validates the template option against what it can inject into a command: the repo must look like owner/name, the ref a branch, tag or commit name without .., and the base URL an https, http or file URL. The scheme also selects which protocols curl may use for the request and for redirects (=https, =http,https or =file), so a redirect cannot downgrade the scheme.'),
    ...para('--', r'fetch is the download and the cache logic. The first request carries If-None-Match when a cached ZIP and a valid ETag exist for this exact URL; a 304 returns the cached file without downloading. The curl call has a 60 second limit and a 30 MB cap, fails on HTTP errors, follows redirects, and records headers so the ETag of the final response (not of a redirect) can be stored. The cache is the ZIP plus a small JSON file naming the URL and the ETag, under stdpath("cache") .. "/xynovim", and a cache for a different URL is never used.'),
    ...code('lua', r'lua/config/egui_new.lua · lines 573-601', r'''
  if vim.fn.executable("curl") ~= 1 then
    fail("curl not found")
  end
  local cdir, czip, cmeta = cache_paths()
  local have, etag = cached(c.url)
  progress(("%s %s/%s ..."):format(have and etag and "checking" or "downloading", c.repo, c.ref))
  local out, hdr = tmp .. "/download.zip", tmp .. "/headers.txt"
  local cmd = {
    "curl", "--silent", "--show-error", "--fail", "--location",
    "--proto", c.proto, "--proto-redir", c.proto,
    "--max-time", "60", "--max-filesize", "30000000",
    "--user-agent", UA,
    "--dump-header", hdr, "--output", out, "--write-out", "%{http_code}",
  }
  if have and etag then
    vim.list_extend(cmd, { "--header", "If-None-Match: " .. etag })
  end
  vim.list_extend(cmd, { "--url", c.url })
  local r = sys(cmd)
  if r.code == 0 and vim.trim(r.stdout or "") == "304" and have then
    return have
  end
  local st = r.code == 0 and vim.uv.fs_stat(out) or nil
  if st and st.size > 0 and zip_tool() and have then
    -- a captive portal or proxy can answer 200 with HTML: never replace the cache with that
    if (zip_tool() == "unzip" and sys({ "unzip", "-Z1", out }) or sys({ "tar", "-tf", out })).code ~= 0 then
      st = nil
      r.stderr = "the download is not a ZIP file"
    end'''),
    ...para('--', r'A subtle defence follows: when a cached copy exists and the download "succeeded", the new file is listed with unzip -Z1 (or tar -tf) first. A captive portal or a proxy can answer 200 with an HTML page; without the listing it would replace the good cache. If the listing fails the download is discarded and the cache stays. The ETag itself is validated (printable ASCII, a single line, up to 200 characters) before it is trusted, by valid_etag.'),
    ...para('--', r'The offline behaviour is explicit. If the request fails and a cached template exists, the user gets a warning that names the URL and says the cached template may be out of date, and the flow continues with it. Without a cache the error says there is no cached copy to fall back on. A flow that quietly reused an old template would produce an out-of-date project; a flow that refused to work offline would be hostile; this does the third thing, which is to work and say so.'),
    ...sec(r'unpacking an archive you did not make'),
    ...para('--', r'The ZIP comes from the network, so the unpack step treats it as hostile. It lists the entries first and refuses any that start with /, contain a backslash, or contain a .. segment in any position. It then reads the total uncompressed size (unzip -Zt, or the sizes column of tar -tvf) and refuses more than 300 MB. After extracting into a private directory, check_tree walks the result and rejects symbolic links, .. entries and anything that is not a plain file or directory. Finally there must be exactly one top-level directory, which is the project.'),
    ...para('--', r'On Windows there is no unzip, but bsdtar (tar.exe in System32) reads ZIP files; zip_tool picks the tool and every command has a tar form. That arrived in the portability commit ff1c8fa on 2026-10-16.'),
    ...sec(r'async without callbacks'),
    ...para('--', r'The flow has a dozen external commands and wants to read like a script. The file implements a tiny coroutine runner: sys runs vim.system and yields; when the process ends it schedules the coroutine’s resume on the main loop. run_async creates the coroutine, steps it, and calls the callback with an error string if the body raised or with its return value when it finished. Errors are raised with error(msg, 0), which keeps the message free of file and line, and are caught by the runner. The two helpers are exported as M.sys and M.run_async because rust_new.lua reuses them.'),
    ...code('lua', r'lua/config/egui_new.lua · lines 521-548', r'''
local function sys(cmd, opts)
  local co = assert(coroutine.running())
  vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {}), function(o)
    vim.schedule(function()
      steppers[co](o)
    end)
  end)
  return coroutine.yield()
end

local function run_async(fn, cb)
  local co = coroutine.create(fn)
  local function step(...)
    local ok, res = coroutine.resume(co, ...)
    if not ok then
      steppers[co] = nil
      cb(tostring(res))
    elseif coroutine.status(co) == "dead" then
      steppers[co] = nil
      cb(nil, res)
    end
  end
  steppers[co] = step
  step()
end

M.sys = sys
M.run_async = run_async'''),
    ...sec(r'creating the project'),
    ...para('--', r'M.create is the whole sequence in one function and its comment states the invariant: the temporary directory is gone on every path. It validates the name and authors, refuses an existing target, creates missing parent directories (remembering which ones it made), makes a private temp directory inside the parent (.egui-new-XXXXXX, so the final rename stays on the same filesystem), fetches, unpacks, renames the unpacked directory to the crate name, re-checks the dependency names against the real Cargo.toml, personalises, runs git init -b main if git is present, re-checks that the target still does not exist, and renames the project into place.'),
    ...code('lua', r'lua/config/egui_new.lua · lines 796-835', r'''
  local function cleanup()
    if tmp then
      vim.fn.delete(tmp, "rf")
    end
    for i = #created, 1, -1 do
      vim.uv.fs_rmdir(created[i]) -- only what this run created, and only while empty
    end
  end
  run_async(function()
    local crate = M.validate_name(p.crate)
    if not crate then
      fail("invalid crate name: " .. tostring(p.crate))
    end
    for _, f in ipairs({ { p.author_name, false }, { p.author_email, true } }) do
      local why = M.check_author(vim.trim(f[1] or ""), f[2])
      if why then
        fail("invalid author: " .. why)
      end
    end
    local target = p.parent .. "/" .. crate
    if vim.uv.fs_lstat(target) then
      fail("the target already exists: " .. target)
    end
    -- missing parent directories (the caller asked the user before)
    local missing, d = {}, p.parent
    while d ~= "/" and not vim.uv.fs_stat(d) do
      table.insert(missing, 1, d)
      d = vim.fs.dirname(d)
    end
    for _, m in ipairs(missing) do
      if not vim.uv.fs_mkdir(m, 493) then
        fail("could not create " .. m)
      end
      created[#created + 1] = m
    end
    tmp = vim.uv.fs_mkdtemp(p.parent .. "/.egui-new-XXXXXX")
    if not tmp then
      fail("cannot write in " .. p.parent)
    end
    local zip = fetch(tmp)'''),
    ...para('--', r'cleanup is attached to the runner’s callback, so it runs whether the body returned or raised. It deletes the temp directory and removes the parent directories that this run created, only while empty (fs_rmdir fails on a non-empty directory, which is exactly the safety needed). The spec "creates missing parent directories and removes them again when the run fails" pins it. A missing git is not an error: the result carries a note and the project is still created.'),
    ...sec(r'prompts, defaults and finishing'),
    ...para('--', r'M.new asks for the name, the author name, the e-mail and the parent directory in sequence, with the git config values prefilled and the parent defaulting to the projects directory option, else ~/projects if it exists, else the working directory. A cancelled prompt (Escape) ends everything silently. An invalid answer notifies and asks again with the reason in the prompt, up to ten retries. The parent prompt checks that the path is a directory (or does not exist and the user confirms creating it) and that the project directory does not exist inside it.'),
    ...code('lua', r'lua/config/egui_new.lua · lines 937-957', r'''
--- Ask in sequence; a cancelled prompt (nil) ends everything silently.
local function ask(prompt, default, check, cb, tries, label)
  tries = tries or 0
  label = label or "EguiNew"
  vim.ui.input({ prompt = prompt, default = default }, function(v)
    if v == nil then
      return
    end
    local value, why = check(v)
    if why then
      vim.notify(label .. ": " .. why, vim.log.levels.WARN, { title = label })
      if tries >= MAX_RETRIES then
        return
      end
      local base = prompt:gsub(" %(.-%):", ":"):gsub(":%s*$", "")
      return ask(base .. " (" .. why .. "): ", v, check, cb, tries + 1, label)
    end
    cb(value)
  end)
end
M.ask = ask'''),
    ...para('--', r'A name passed on the command line (:EguiNew weather_panel) skips the first prompt if it is valid and, if not, shows the reason and prompts with the argument prefilled. A running flag prevents two projects being created at once. The ask function takes a label and is exported (M.ask, M.expand_dir, M.default_parent) so the Rust project flow uses the same prompts.'),
    ...para('--', r'M.finish changes into the new directory, opens src/main.rs (or Cargo.toml), prints what to do next, and then checks the Rust version. The check is a notification only: it reads the rust-version from the generated Cargo.toml, runs rustc --version in the new project directory (so a project-local override counts) and warns if the installed compiler is older. Nothing is installed or downloaded. parse_version handles "1.95", "1.95.0" and pre-release suffixes, and the result is passed to an optional done callback for the specs.'),
    ...code('lua', r'lua/config/egui_new.lua · lines 751-761', r'''
function M.check_rust_version(dir, done)
  done = done or function() end
  local need_s = M.parse_rust_version(read_file(dir .. "/Cargo.toml"))
  if not need_s then
    return done("nofield")
  end
  local need = M.parse_version(need_s)
  if not need then
    return done("badfield")
  end
  local ok = pcall(vim.system, { "rustc", "--version" }, { text = true, cwd = dir, timeout = 20000 }, function(o)'''),
    ...para('--', r'If vim.g.xynovim_egui_build_after_new is true and snacks is loaded, cargo build runs in a bottom terminal. Setup registers the :EguiNew command with an optional argument.'),
    ...sec(r'what the history says'),
    ...pt('--', r'ddc51eb 2026-10-15', r'the file is added (921 lines) with the dashboard entry, the spec (1244 lines) and the README and CHANGELOG sections.'),
    ...pt('--', r'59cc11b, b020526, d2ac9a4 2026-10-15', r'review fixes, then a toolchain preparation step: the template pins a toolchain with a rust-toolchain file, and the flow prepared that pinned toolchain (the rust-analyzer component) in advance.'),
    ...pt('--', r'0cfb739 2026-10-16', r'that preparation is removed again (353 lines changed here, 573 in the spec). The changelog gives the reason: the pin made rustup install exactly one toolchain, so it is now always deleted from the generated project, and rust-version stays as a minimum with a warning when rustc is older. The options for preparing and keeping the pin disappeared with it.'),
    ...pt('--', r'd163480 2026-10-16', r'cargo_name is split out of validate_name, and sys, run_async, ask and default_parent are exported, so the Rust project flow can reuse them.'),
    ...pt('--', r'ff1c8fa 2026-10-16', r'Windows and macOS: zip_tool and the bsdtar forms of every archive command.'),
    ...sec(r'the same module in xyno-new.nvim'),
    ...para('--', r'The file became lua/xyno_new/egui.lua in ~/projects/xyno-plugins/xyno-new.nvim on 2026-10-22 and is the same length, 1048 lines. A line diff shows only the names changed. The options become vim.g.xyno_new_projects_dir, xyno_new_egui_template and xyno_new_egui_build_after_new, now also settable through setup() as projects_dir, egui_template and egui_build_after_new. The cache directory is stdpath("cache")/xyno-new, the user agent and notification id carry the new name, the generated README credits xyno-new.nvim, and the next-step hint says :RustTargets where this file says <leader>rX. The dashboard entry is no longer in the module: it moved to xyno_new/dashboard.lua and is opt-in. Behaviour is otherwise identical.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/egui-new_spec.lua (1498 lines here, 1419 in the plugin) is organised by function. Pure parts first: name rules (a table of inputs including non-ASCII), titles, author formatting and rejection, token and title replacement (links to the template kept, several occurrences per line, crate names with pattern characters), the Cargo.toml and Cargo.lock edits (both branches of the sorted move, a trailing metadata table), markdown section extraction and the README fallback.'),
    ...para('--', r'Then a fake template served as file:// and over http://127.0.0.1: download, personalise and move into place; executable bits kept; toolchain pins removed in every form while rust-version is kept byte for byte; new template files handled without code changes; failure cases (an existing target, a bad ZIP, no or two top-level directories, entries that escape or are symlinks, curl failure with and without a cache); and the ETag logic (conditional request, download only on change, offline fallback, a 200 that is not a ZIP never replaces the cache, a cache for another template never used, an ETag that is not one printable line ignored). Last, the prompts: a full run asks name, author, e-mail and parent, creates the project, cds and opens main.rs.'),
    ...sec(r'rough edges worth knowing'),
    ...pt('--', r'double validation', r'in M.new, check_name is called twice for an invalid argument (once to test, once to get the reason). It is pure, so the only cost is repetition.'),
    ...pt('--', r'next-step hint', r'finish prints "<leader>rX lists the cargo targets", a key that lives in another module of this config; the plugin version replaced it with the :RustTargets command, which exists on its own.'),
  ],
);
