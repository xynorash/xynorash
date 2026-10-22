import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-new.nvim/lua/xyno_new/egui.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'lua/xyno_new/egui.lua — a project from the live eframe_template'),
    cm('--', r'a careful downloader, a careful unpacker, and text edits that change as little as they must'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'download, verify, unpack and personalise emilk/eframe_template (:EguiNew)'),
    kv(r'language', r'Lua, 1,048 lines: the largest module, and the shared toolbox of the plugin'),
    kv(r'shared with rust.lua', r'cargo_name, run_async, sys, ask, default_parent, expand_dir'),
    kv(r'shells out to', r'curl, unzip (tar on Windows), git, rustc; never to the template'),
    kv(r'origin', r'lua/config/egui_new.lua in xynovim: ddc51eb (2026-10-15) through ff1c8fa (2026-10-16)'),
    kv(r'tested by', r'tests/egui-new_spec.lua, 63 cases, 1,419 lines'),
    ...sec(r'why this file exists'),
    ...para('--', r'eframe_template (github.com/emilk/eframe_template) is the template this module starts egui projects from. Starting from it means downloading it, then renaming the crate, which the spec’s fixture shows appearing in Cargo.toml, Cargo.lock, assets/sw.js, index.html and a GitHub Pages workflow; the header comment says the module personalises the way the template’s README and fill_template.sh describe. This module does the job inside Neovim, with the template fetched fresh each time, so the project starts from the template as it is today rather than from a copy that aged inside a plugin.'),
    ...para('--', r'The header says it in a sentence: the CURRENT template, downloaded as a ZIP, never a copy kept here, personalised the way the template’s README and fill_template.sh describe.'),
    ...code('lua', r'lua/xyno_new/egui.lua · lines 1-17', r'''
-- :EguiNew [name]: a new project
-- from the CURRENT https://github.com/emilk/eframe_template (downloaded as a
-- ZIP, never a copy kept here), personalised the way the template's README and
-- fill_template.sh describe: crate name, authors, window / page title, the web
-- build file names in assets/sw.js.
--
-- Options (all optional; setup() sets them from projects_dir, egui_template, egui_build_after_new):
--   vim.g.xyno_new_projects_dir              parent directory (default ~/projects if it exists, else the cwd)
--   vim.g.xyno_new_egui_template             { repo = "emilk/eframe_template", ref = "main", base_url = "https://github.com" }
--   vim.g.xyno_new_egui_build_after_new      true: run `cargo build` in a terminal afterwards
--
-- The template's rust-toolchain file is never copied (it would make rustup install one exact
-- toolchain); its Cargo.toml rust-version stays as the minimum, and a warning says when rustc is older.
--
-- The text edits (M.validate_name .. M.readme) are pure functions; every
-- external command is an argv list, nothing from the template is executed.
local M = {}'''),
    ...para('--', r'Two promises close the header: the text edits are pure functions, and nothing from the template is executed. The second is a security stance. A downloaded repository contains scripts (fill_template.sh, fill_template.ps1, a rust-toolchain file); the module reads and rewrites text files, deletes the two scripts and the toolchain pin, and runs none of them.'),
    ...sec(r'the story of the toolchain pin'),
    ...para('--', r'The most instructive history in this file is a reversal. ddc51eb (2026-10-15 12:53, 921 lines) shipped :EguiNew with an option to keep or drop the template’s rust-toolchain file. The template pinned channel 1.95.0 then, and rustup installs a pinned toolchain without the rust-analyzer component, so a project that kept the pin opened in Neovim with no language server. b020526, two hours later, answered with machinery: after creating the project, in the background, run rustup toolchain install with the components and targets read from the pin file, then restart the Rust servers. The commit touched 245 lines of this module and added 330 to its spec.'),
    ...para('--', r'The next morning, 0cfb739 (2026-10-16 09:56) deleted all of it: 353 lines of this module changed, 573 of its spec, and the options for preparing and keeping the pin along with them. Its changelog entry gives the new rule: the pin is always removed, the rust-version field of Cargo.toml is kept as the minimum, and at the end of the flow rustc --version, run inside the new project, is compared with it. An older rustc produces one warning and nothing is installed or downloaded. The lesson shows in the shape of the code today: a 36-line check_rust_version in place of a toolchain installer. The less the plugin does to your machine, the less it can get wrong.'),
    ...sec(r'the name rules, shared with the Rust flows'),
    ...code('lua', r'lua/xyno_new/egui.lua · lines 52-78', r'''
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
    ...para('--', r'cargo_name encodes what cargo new enforces. The keyword list is cargo’s restricted_names::is_keyword, reproduced from the comment’s name; RESERVED adds the names that clash with standard crates and with the artifact directories of target/. The check on bad characters is subtle: the pattern [^%w_%-][\128-\191]* matches one offending byte plus any UTF-8 continuation bytes after it, so the error names the whole character (a review fix, 59cc11b, which changed the pattern from a single offending byte to the byte plus its continuation bytes). The crate identifier is the name with hyphens as underscores; it is what the keyword, length and reserved checks run on, since cargo checks the identifier.'),
    ...para('--', r'validate_name is the egui-specific layer on top: the name may not be eframe_template itself, nor the name of a dependency of the template (a library named egui cannot compile). The first list of dependency names is built into the file; M.dependency_names later reads the real Cargo.toml the download contains, so a dependency added to the template next month is caught at run time. The Rust flows deliberately skip validate_name, a distinction the spec “does not carry the egui template’s own restrictions” pins down.'),
    ...sec(r'author fields that cannot break a file'),
    ...sec(r'replacing the crate name, except where it is a credit'),
    ...code('lua', r'lua/xyno_new/egui.lua · lines 135-160', r'''
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
    ...para('--', r'The token eframe_template appears in code (the crate name) and in links to the template (a deps.rs badge in the spec’s fixture README, for example). Replacing it everywhere would break the links. in_template_url asks whether the occurrence is directly preceded by one of four URL prefixes, such as github.com/emilk/, and keeps the original text there. The replacement uses plain-text find with the init position, not patterns, so a crate name with characters that are special in Lua patterns is inserted literally (the spec “treats the crate name as plain text”). The window and page title token eframe template (with a space) is replaced separately and unconditionally by a readable title: weather_panel becomes weather panel.'),
    ...sec(r'Cargo.toml: edit two keys, keep every byte'),
    ...code('lua', r'lua/xyno_new/egui.lua · lines 180-200', r'''
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
      end'''),
    ...para('--', r'edit_cargo_toml walks the file line by line with an in_pkg flag and acts only inside [package]. A name line is rewritten with the pattern capturing the text before and after the quoted value, so a trailing comment stays. An authors line, even a multi-line array that runs to its closing bracket, is replaced whole by one line, or dropped when there are no authors. If the file had no authors line and there are authors now, one is inserted after name. CRLF is preserved by remembering whether the original line ended in a carriage return.'),
    ...sec(r'Cargo.lock: a rename that respects sorting'),
    ...code('lua', r'lua/xyno_new/egui.lua · lines 271-299', r'''
  if not hit then
    return text
  end
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
  end
  table.remove(blocks, hit)
  table.remove(names, hit)
  local at = #blocks + 1
  for k = 1, #blocks do
    if names[k] and names[k] > crate then
      at = k
      break
    end
  end
  table.insert(blocks, at, renamed)
  local body = table.concat(blocks, "\n\n")
  if tail then
    return head .. body .. "\n\n" .. tail
  end
  return head .. body .. "\n"'''),
    ...para('--', r'The lockfile has an entry for the template’s own package, and it must be renamed too, otherwise cargo build --locked wants to rewrite the file. The comment explains the subtlety: cargo keeps package entries sorted by name, so after a rename the entry may belong somewhere else. The function splits the file into [[package]] blocks, finds the template’s block, and compares the new name with its neighbours. If the order still holds it substitutes in place, leaving every other byte alone; otherwise it removes the block and inserts it at its sorted position, taking care of a [metadata] or [[patch.unused]] table that may follow the last package. The two spec cases, “renames only the template’s own package” and “moves the entry to its sorted place (cargo --locked wants the order)”, are the pair that justify the extra code.'),
    ...sec(r'the README is regenerated, not patched'),
    ...code('lua', r'lua/xyno_new/egui.lua · lines 304-330, 333-350', r'''
function M.md_section(md, pat)
  local out, level, fence = nil, nil, false
  for _, line in ipairs(vim.split(md or "", "\n", { plain = true })) do
    if line:match("^%s*```") then
      fence = not fence
    end
    local hashes, title = nil, nil
    if not fence then
      hashes, title = line:match("^(#+)%s+(.-)%s*$")
    end
    if hashes then
      if out and #hashes <= level then
        break
      end
      if not out and title:lower():find(pat:lower(), 1, true) then
        out, level = {}, #hashes
      end
    elseif out then
      out[#out + 1] = line
    end
  end
  if not out then
    return nil
  end
  local body = vim.trim(table.concat(out, "\n"))
  return body ~= "" and body or nil
end
...
function M.readme(o)
  local run = M.md_section(o.template_readme, "testing locally")
    or "`cargo run --release`\n\nOn Linux the egui / eframe build needs the usual system packages (xcb, xkbcommon, openssl and pkg-config headers): see the template's README."
  local web = M.md_section(o.template_readme, "web locally")
    or "Install the target and Trunk, then serve:\n\n"
      .. "1. `rustup target add wasm32-unknown-unknown`\n2. `cargo install --locked trunk`\n"
      .. "3. `trunk serve` (open `http://127.0.0.1:8080/index.html#dev`)\n\n`trunk build --release` writes the site to `dist/`."
  local parts = {
    "# " .. o.title,
    "An [egui](https://github.com/emilk/egui) app that runs natively and in the browser, generated from "
      .. "[emilk/eframe_template](https://github.com/emilk/eframe_template) by xyno-new.nvim's `:EguiNew`.",
    "## Run natively\n\n" .. run,
    "## Run on the web\n\n" .. web,
  }
  parts[#parts + 1] = "## License\n\nThe template is dual licensed (MIT OR Apache-2.0), see `LICENSE-MIT` and `LICENSE-APACHE`; "
    .. "`Cargo.toml` keeps its `license` field."
  return M.replace_token(table.concat(parts, "\n\n") .. "\n", o.crate)
end'''),
    ...para('--', r'A README full of the template’s Getting started instructions about renaming package.name would be wrong for the new project. So personalise generates a new one: a title, a sentence crediting the template and :EguiNew, a run-natively section, a run-on-the-web section, and a licence note. The two instruction sections are taken from the template’s own README by md_section, which finds a heading containing a phrase (“testing locally”, “web locally”) and returns its body up to the next heading of the same or higher level, ignoring # lines inside code fences. If the template’s README changes shape and a section is missing, readme falls back to generic text for the native build and the Trunk steps. The result still passes through replace_token, so the crate name is right.'),
    ...sec(r'personalise: walk, skip, rewrite, delete'),
    ...code('lua', r'lua/xyno_new/egui.lua · lines 421-449', r'''
function M.personalise(dir, o)
  local res = { changed = {} }
  local template_readme = read_file(dir .. "/README.md")
  for _, rel in ipairs(walk(dir)) do
    local base = vim.fs.basename(rel)
    local path = dir .. "/" .. rel
    local st = vim.uv.fs_stat(path)
    local skip = not st
      or st.size > MAX_TEXT
      or rel == "README.md" -- regenerated below
      or base:match("^LICEN[CS]E") ~= nil
      or base:match("^COPYING") ~= nil
    local text = not skip and read_file(path) or nil
    if text and not text:find("\0", 1, true) then
      local new
      if base == "Cargo.lock" then
        new = M.edit_cargo_lock(text, o.crate)
      else
        new = M.replace_title(M.replace_token(text, o.crate), o.title)
        if rel == "Cargo.toml" then
          new = M.edit_cargo_toml(new, o.crate, o.authors)
        end
      end
      if new ~= text then
        write_file(path, new)
        res.changed[#res.changed + 1] = rel
      end
    end
  end'''),
    ...para('--', r'Every regular file below the unpacked directory is considered, except .git. A file is skipped if it is larger than 1 MiB, if it is README.md (regenerated later) or if its name starts with LICEN(S|C)E or COPYING, so the licence texts stay byte for byte. A file containing a NUL byte is treated as binary and untouched. Cargo.lock gets its special function; everything else gets the token and title replacement; Cargo.toml additionally gets edit_cargo_toml. A file is written only if the text changed, and its name goes into res.changed.'),
    ...para('--', r'The design choice worth noticing is that no file list is written down. The earlier lists in the template (src/main.rs, assets/sw.js, the pages workflow) are discovered by walking, so a file the template adds later that mentions eframe_template is handled too; the spec “does not depend on today’s file list” adds one and checks it. After rewriting, the function deletes fill_template.sh, fill_template.ps1, rust-toolchain and rust-toolchain.toml.'),
    ...sec(r'the download: trust nothing from the network'),
    ...code('lua', r'lua/xyno_new/egui.lua · lines 469-493', r'''
local function cfg()
  local c = vim.tbl_extend("force", {
    repo = "emilk/eframe_template",
    ref = "main",
    base_url = "https://github.com",
  }, vim.g.xyno_new_egui_template or {})
  if type(c.repo) ~= "string" or not c.repo:match("^[%w_.-]+/[%w_.-]+$") then
    return nil, "vim.g.xyno_new_egui_template.repo must look like owner/name"
  end
  if type(c.ref) ~= "string" or not c.ref:match("^[%w_][%w_./-]*$") or c.ref:find("..", 1, true) then
    return nil, "vim.g.xyno_new_egui_template.ref is not a valid branch, tag or commit"
  end
  local base = type(c.base_url) == "string" and c.base_url:gsub("/+$", "") or ""
  local scheme = base:match("^(%a+)://[^%s]+$")
  if scheme ~= "https" and scheme ~= "http" and scheme ~= "file" then
    return nil, "vim.g.xyno_new_egui_template.base_url must be an https://, http:// or file:// URL"
  end
  local proto = scheme == "https" and "=https" or scheme == "http" and "=http,https" or "=file"
  return {
    url = ("%s/%s/archive/%s.zip"):format(base, c.repo, c.ref),
    proto = proto,
    repo = c.repo,
    ref = c.ref,
  }
end'''),
    ...para('--', r'cfg merges the user’s vim.g.xyno_new_egui_template over the defaults and validates every key before a URL is built: repo must look like owner/name; ref must start with an alphanumeric or underscore, contain only safe characters and no ..; base_url must be https, http or file. The scheme becomes a curl --proto restriction, so a redirect from https to something else is refused. The file scheme is for the specs (and for anyone with a mirror on disk).'),
    ...code('lua', r'lua/xyno_new/egui.lua · lines 520-545', r'''
--- vim.system inside run_async: yields until the command finished.
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
end'''),
    ...para('--', r'fetch builds an argv for curl with a stack of safety flags: --fail, --proto and --proto-redir limited to the scheme, --max-time 60, --max-filesize 30000000, a user agent naming the plugin, and --dump-header to capture the ETag. If a cached copy exists for the same URL with an ETag, the request carries If-None-Match; a 304 answer returns the cache without downloading. The cache is a ZIP and a small JSON file in the stdpath cache directory, written through a .new file and a rename so a crash cannot leave half a ZIP.'),
    ...para('--', r'A 200 answer is not proof of a ZIP: a captive portal answers 200 with HTML. When a cache exists the new file is listed with unzip -Z1 (or tar -tf) first, and a failure there keeps the old cache; the spec “a 200 answer that is not a ZIP never replaces the cached template” covers it. A cached ETag is only used if it is a single printable line of at most 200 bytes. When the network fails and a cache exists, the module warns that the template may be out of date and carries on, so :EguiNew still works on a plane; with no cache the error says which URL failed.'),
    ...sec(r'the unpacker: a ZIP is a list of paths from a stranger'),
    ...code('lua', r'lua/xyno_new/egui.lua · lines 641-651, 661-663', r'''
  local l = tool == "unzip" and sys({ "unzip", "-Z1", zip }) or sys({ "tar", "-tf", zip })
  if l.code ~= 0 then
    fail("the template archive is not a valid ZIP file")
  end
  for name in (l.stdout or ""):gmatch("[^\n]+") do
    if name:sub(1, 1) == "/" or name:find("\\", 1, true) or name:match("^%.%.$") or name:match("^%.%./")
      or name:find("/%.%./") or name:match("/%.%.$")
    then
      fail("the template archive has an unsafe entry: " .. name)
    end
  end
...
  if bytes and bytes > 300 * 1024 * 1024 then
    fail("the template archive unpacks to more than 300 MB")
  end'''),
    ...para('--', r'unpack lists the archive before extracting and refuses any entry that is absolute, contains a backslash, or contains a .. component, then compares the declared uncompressed size against a 300 MB limit. After extraction check_tree walks the result and rejects any symlink, any .. entry and any type other than regular file or directory. Finally there must be exactly one top-level directory, which is renamed to the crate name. This is the classic zip-slip defence and it is applied twice, on the listing and on the result. The spec “rejects archives whose entries escape the target or are symlinks” builds such archives with Python.'),
    ...sec(r'a minimum Rust version, compared not enforced'),
    ...code('lua', r'lua/xyno_new/egui.lua · lines 761-781', r'''
  local ok = pcall(vim.system, { "rustc", "--version" }, { text = true, cwd = dir, timeout = 20000 }, function(o)
    vim.schedule(function()
      local have = o.code == 0 and M.parse_rustc(o.stdout) or nil
      if o.code ~= 0 then
        rv_notify(("could not run rustc to check the minimum Rust version (%s) this project needs"):format(need_s), vim.log.levels.WARN)
        return done("missing")
      end
      if not have then
        rv_notify(("could not read the rustc version; this project needs Rust >= %s"):format(need_s), vim.log.levels.WARN)
        return done("unparsable")
      end
      if M.older(have, need) then
        rv_notify(
          ("this project needs Rust >= %s (you have %d.%d.%d): run rustup update stable"):format(need_s, have[1], have[2], have[3]),
          vim.log.levels.WARN
        )
        return done("old")
      end
      done("ok")
    end)
  end)'''),
    ...para('--', r'Versions are parsed into {major, minor, patch} with missing components as zero and a pre-release suffix ignored, as cargo does for rust-version. rustc runs inside the new directory so a project-local rustup override counts. The states returned to the optional done callback, nofield, badfield, ok, old, missing, unparsable, exist so the specs can assert exactly which path ran without scraping messages. A missing or garbage rustc is a note, not a failure.'),
    ...sec(r'the transaction'),
    ...code('lua', r'lua/xyno_new/egui.lua · lines 831-839, 861-875', r'''
    tmp = vim.uv.fs_mkdtemp(p.parent .. "/.egui-new-XXXXXX")
    if not tmp then
      fail("cannot write in " .. p.parent)
    end
    local zip = fetch(tmp)
    progress("unpacking ...")
    local top = unpack(zip, tmp)
    local proj = tmp .. "/" .. crate
    if not vim.uv.fs_rename(top, proj) then
...
    if vim.uv.fs_lstat(target) then
      fail("the target already exists: " .. target)
    end
    if not vim.uv.fs_rename(proj, target) then
      fail("could not move the project to " .. target)
    end
    vim.fn.delete(tmp, "rf")
    tmp = nil
    created = {} -- the parents stay: the project lives in them
    return { dir = target, git_note = git_note }
  end, function(err, info)
    cleanup()
    cb(err, info)
  end)
end'''),
    ...para('--', r'create is the assembly line. It validates, refuses an existing target, creates missing parents (remembering them), makes a temporary directory inside the parent (.egui-new-XXXXXX, which keeps the final rename on one filesystem), fetches, unpacks, renames the top directory, personalises, runs git init -b main with an optional note, and then moves the finished project to its place with one fs_rename. The completion callback calls cleanup on every path: the temp directory is deleted recursively and the created parents are removed with fs_rmdir, which only succeeds while empty. On success created is cleared first, because the parents now hold the project.'),
    ...sec(r'the prompts and finish'),
    ...sec(r'what to read in the spec'),
    ...para('--', r'tests/egui-new_spec.lua embeds a trimmed copy of the template’s files as fixtures (dated 2026-10-15 in a comment), builds ZIPs with Python, serves them through file:// or a tiny TCP server written with vim.uv that answers 200, 304 or 500 and records If-None-Match. It is a good example of testing network behaviour without a network.'),
    ...sec(r'history'),
    ...pt('--', r'ddc51eb (2026-10-15)', r'created, 921 lines, with a 1,244-line spec.'),
    ...pt('--', r'59cc11b (2026-10-15)', r'review fixes: whole-character error for non-ASCII names, ZIP check before replacing the cache.'),
    ...pt('--', r'b020526 (2026-10-15)', r'toolchain preparation, +245 lines.'),
    ...pt('--', r'0cfb739 (2026-10-16)', r'toolchain preparation removed, pin always dropped, rustc version check added.'),
    ...pt('--', r'd163480 (2026-10-16)', r'the day rust_new.lua was written, cargo_name was split out of validate_name, and sys, run_async, default_parent and ask (with a label argument) were exported for it: this is how the egui module became the plugin’s toolbox.'),
    ...pt('--', r'ff1c8fa (2026-10-16)', r'portability: zip_tool picks unzip or, on Windows, tar (bsdtar), and the size check parses tar -tv output.'),
    ...pt('--', r'01f8e4c (2026-10-22, here)', r'moved in as xyno_new.egui.'),
  ],
);
