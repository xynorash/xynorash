import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/disk_guard.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'disk_guard.lua — what auto-save must never do'),
    cm('--', r'no writes into dependencies, no overwriting a file that changed behind the buffer'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'safety net around auto-save: can_save condition, dependency lock, FileChangedShell policy'),
    kv(r'language', r'Lua (Neovim API, autocmds, vim.uv.fs_stat)'),
    kv(r'size', r'250 lines, 3 commits (b65284f, 3f868dd, ff1c8fa)'),
    kv(r'used by', r'options.lua (setup) and plugins/auto-save.lua line 79 (condition = can_save)'),
    kv(r'also lives in', r'xyno-guard.nvim, lua/xyno_guard/init.lua (258 lines)'),
    ...sec(r'why this file exists'),
    ...para('--', r'This config turns on auto-save: the buffer is written about a second after a text change. That is convenient and it is dangerous in four specific ways, which the header comment lists as the things "auto-save must never do". It must not write into the sources of a dependency or of the standard library that you opened with go-to-definition. It must not overwrite a file that changed on disk behind the buffer’s back (git checkout, an agent, sed -i, cargo fmt in another pane). It must not leave the files touched by a multi-file rename unsaved. And Neovim’s own answer to a conflict, a blocking W12 prompt "Do you really want to write to it (y/n)?", is itself a failure mode because it swallows keystrokes.'),
    ...para('--', r'disk_guard.lua is the module that answers all four. It exists because the commit b65284f (2026-10-13, "Batch 3: data safety") added auto-save and the safety was designed together with it. The file was refined in the same week and then made portable on 2026-10-16.'),
    ...sec(r'what counts as a dependency'),
    ...code('lua', r'lua/config/disk_guard.lua · lines 19-54', r'''
local home = vim.uv.os_homedir()

-- Windows and macOS file systems are case-insensitive by default, and nvim
-- hands out backslash paths on Windows: compare normalized and lowercased.
local fold = vim.fn.has("win32") == 1 or vim.fn.has("mac") == 1
local function norm(p)
  local slash = p:sub(-1) == "/" or p:sub(-1) == "\\" -- normalize() drops a trailing slash, a root needs it
  p = vim.fs.normalize(p) .. (slash and "/" or "")
  return fold and p:lower() or p
end

local function dep_roots()
  local roots = { home .. "/.cargo/registry/", home .. "/.cargo/git/", home .. "/.rustup/" }
  for _, v in ipairs({ { "CARGO_HOME", "/registry/" }, { "CARGO_HOME", "/git/" }, { "RUSTUP_HOME", "/" } }) do
    local base = vim.env[v[1]]
    if base and base ~= "" then
      roots[#roots + 1] = vim.fs.normalize(base):gsub("/+$", "") .. v[2]
    end
  end
  for i, r in ipairs(roots) do
    roots[i] = norm(r)
  end
  return roots
end

--- @param name string
--- @return boolean
function M.is_dependency(name)
  name = norm(name)
  for _, r in ipairs(dep_roots()) do
    if name:sub(1, #r) == r then
      return true
    end
  end
  return false
end'''),
    ...para('--', r'A dependency is a path that begins with one of up to six roots: the registry, the git checkouts and the rustup toolchains under the home directory, plus the same three under $CARGO_HOME and $RUSTUP_HOME if those are set. The match is a plain prefix test on a normalised string, which is why every root ends in a slash: without it ~/.cargo/registry-notes/ would be mistaken for a dependency. The spec checks exactly this: "does not match similar prefixes or project files".'),
    ...para('--', r'The norm helper is the part added by the portability commit ff1c8fa. On Windows and macOS the default file systems are case-insensitive, and Windows hands out backslash paths, so both sides of the comparison are normalised with vim.fs.normalize and lower-cased on those two platforms. On Linux the case is kept, because there it is meaningful. The first line of norm is a small piece of care: vim.fs.normalize drops a trailing slash, and a root such as the rustup directory needs it, so the function remembers whether the input ended in a separator and puts one back.'),
    ...para('--', r'dep_roots() is recomputed on every call rather than cached. The environment variables can change in a session (the spec sets CARGO_HOME with and without a trailing slash), and the cost is six string operations.'),
    ...sec(r'can_save: the condition handed to auto-save'),
    ...code('lua', r'lua/config/disk_guard.lua · lines 56-117', r'''
--- mtime of the file behind `buf` as "sec.nsec" (nil: no such file).
local function stamp(name)
  local st = vim.uv.fs_stat(name)
  return st and ("%d.%09d"):format(st.mtime.sec, st.mtime.nsec) or nil
end

local function is_file_buf(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= ""
end

local function record(buf)
  if is_file_buf(buf) then
    vim.b[buf].xynovim_disk_stamp = stamp(vim.api.nvim_buf_get_name(buf))
  end
end

local function warn_once(buf, key, msg)
  if vim.b[buf].xynovim_disk_warned ~= key then
    vim.b[buf].xynovim_disk_warned = key
    vim.notify(msg, vim.log.levels.WARN)
  end
end

--- auto-save's `condition`: may this buffer be written to disk now?
--- @param buf integer
--- @return boolean
function M.can_save(buf)
  -- Non-file buffers (the 99 prompt is an acwrite buffer) and readonly ones are
  -- never written: `:write` on them raised a blocking "'readonly' option is set" prompt.
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" or vim.bo[buf].readonly then
    return false
  end
  if not is_file_buf(buf) then
    return true
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if M.is_dependency(name) then
    return false
  end
  local was = vim.b[buf].xynovim_disk_stamp
  local now = stamp(name)
  if was == nil then
    -- never read or written by this nvim (new file, or opened before the guard
    -- ran): nothing to compare against
    record(buf)
    return true
  end
  local short = vim.fn.fnamemodify(name, ":~:.")
  if now == nil then
    warn_once(buf, "gone", short .. " no longer exists on disk: auto-save is paused for this buffer (:w to recreate it)")
    return false
  end
  if now ~= was then
    warn_once(
      buf,
      now,
      short .. " changed on disk while this buffer has unsaved edits: auto-save is paused for it (:w! keeps the buffer, :e! takes the disk version)"
    )
    return false
  end
  return true
end'''),
    ...para('--', r'The trick of the whole module is the stamp. Every time the buffer is read or written, the guard records the file’s modification time as a string "sec.nsec" in a buffer variable. Before a save, can_save compares the recorded stamp with the current one. If they differ, someone else wrote the file after this buffer last saw it, and writing now would silently destroy their change. The nanosecond field is included because second resolution would miss two writes in the same second, which is exactly what a formatter in another pane does.'),
    ...para('--', r'Read the function as a ladder of rejections. An invalid buffer, a buffer with any buftype, or a readonly buffer returns false at once. The comment gives the motive for the last two: the prompt buffer of the 99 agent plugin is an acwrite buffer, and a :write on a readonly buffer raised a blocking "’readonly’ option is set" prompt, the same class of keystroke-swallowing bug the module exists to prevent. Next, a buffer with no name gets true (the spec title says of this case that the plugin handles it; this module has nothing to compare it against). Then dependencies are refused. Then comes the stamp test: no stamp yet means the guard has nothing to compare, so it records one and allows the save (a new file, or a buffer opened before the guard was set up). A missing file and a changed stamp each return false with a warning.'),
    ...para('--', r'The warning is rate-limited by warn_once. Its key for a changed file is the new stamp itself, and for a deleted one the string "gone". So a file that changes once warns once; if it changes again, the key differs and the user hears about it again; but every one-second tick of auto-save does not produce a new message. The way out is printed in the message: :w! keeps the buffer and overwrites the disk, :e! takes the disk version.'),
    ...sec(r'closing the debounce window'),
    ...code('lua', r'lua/config/disk_guard.lua · lines 169-209', r'''
function M.setup()
  local group = vim.api.nvim_create_augroup("xynovim_disk_guard", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "BufFilePost", "FileChangedShellPost" }, {
    group = group,
    callback = function(ev)
      record(ev.buf)
    end,
  })
  -- auto-save checks `condition` when the event fires but writes up to a second
  -- later (debounce): the file may change in between. So check again right
  -- before the write, and turn a refused write into a harmless one: a "nowrite"
  -- buffer cannot be written (E382, silenced by auto-save's `silent!`).
  -- Whoever listens to AutoSaveWritePost can tell by `modified` still being set.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "AutoSaveWritePre",
    callback = function(ev)
      local buf = ev.data and ev.data.saved_buffer
      if buf and vim.api.nvim_buf_is_valid(buf) and not M.can_save(buf) then
        vim.b[buf].xynovim_disk_buftype = vim.bo[buf].buftype
        vim.bo[buf].buftype = "nowrite"
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "AutoSaveWritePost", -- auto-save writes with noautocmd: no BufWritePost
    callback = function(ev)
      local buf = ev.data and ev.data.saved_buffer
      if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        return
      end
      local bt = vim.b[buf].xynovim_disk_buftype
      if bt ~= nil then
        vim.bo[buf].buftype = bt
        vim.b[buf].xynovim_disk_buftype = nil
      else
        record(buf)
      end
    end,
  })'''),
    ...para('--', r'Checking a condition when an event fires is not enough, because auto-save then waits (a debounce of a second, per the spec’s "configuration" test) before writing. In that window the file can change. The second check is the most inventive part of the file. auto-save fires a user event, AutoSaveWritePre, just before the write. The handler asks can_save again, and if the answer is no it temporarily sets the buffer’s buftype to "nowrite". A nowrite buffer refuses to be written with error E382, and auto-save runs its write under silent!, so the refusal is invisible. The previous buftype is saved in a buffer variable and restored in AutoSaveWritePost. If the write was allowed, the Post handler instead records a fresh stamp, because auto-save writes with noautocmd and therefore BufWritePost never fires. The comment adds the contract for others: whoever listens to AutoSaveWritePost can tell a refused write because the buffer is still modified.'),
    ...para('--', r'The alternative would have been to patch or wrap auto-save, or to cancel the write from the Pre event. A cancel is not offered by that event; flipping an option that makes the write fail harmlessly is. It is a small hack that depends on the plugin silencing the error, and the file says so in its comment instead of hiding it.'),
    ...sec(r'FileChangedShell: never prompt'),
    ...code('lua', r'lua/config/disk_guard.lua · lines 219-236', r'''
  vim.api.nvim_create_autocmd("FileChangedShell", {
    group = group,
    callback = function(ev)
      local reason = vim.v.fcs_reason
      if reason == "conflict" or reason == "deleted" then
        vim.v.fcs_choice = ""
        vim.b[ev.buf].xynovim_disk_warned = stamp(ev.file) or "gone" -- can_save need not repeat it
        local short = vim.fn.fnamemodify(ev.file, ":~:.")
        vim.notify(
          reason == "deleted" and (short .. " was deleted on disk (the buffer is kept)")
            or (short .. " changed on disk and the buffer has unsaved edits (:e! takes the disk version, :w! keeps the buffer)"),
          vim.log.levels.WARN
        )
      else
        vim.v.fcs_choice = vim.o.autoread and "reload" or "ask"
      end
    end,
  })'''),
    ...para('--', r'When Neovim notices (via :checktime, which LazyVim runs on FocusGained) that a file changed under an open buffer, it asks the user a question in the command line. This config takes the question away. For a conflict (the buffer is modified and the disk changed) or a deleted file, the handler sets fcs_choice to the empty string, which means do nothing, keeps the buffer as it is, and issues one warning. For every other reason the choice is reload if autoread is set and otherwise ask, i.e. Neovim’s own default. So an unmodified buffer follows the disk, and a modified one is never replaced silently.'),
    ...para('--', r'There is one detail that connects this to can_save. The handler writes the new stamp into the same xynovim_disk_warned variable that warn_once uses, with a comment, "can_save need not repeat it". The user has already been told about this exact change, so the next auto-save tick, which will refuse the write, does not say it a second time.'),
    ...sec(r'saving after a multi-file edit'),
    ...code('lua', r'lua/config/disk_guard.lua · lines 119-167', r'''
--- Write every modified buffer that may be written. `write` (not noautocmd):
--- didSave, local history and neotest all hear about it.
function M.save_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_loaded(buf)
      and is_file_buf(buf)
      and vim.bo[buf].modified
      and vim.bo[buf].modifiable
      and M.can_save(buf)
    then
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("silent! write")
      end)
    end
  end
end

--- Does a WorkspaceEdit touch anything but the current buffer?
local function touches_other_files(edit)
  local cur = vim.uri_from_bufnr(0)
  for uri in pairs(edit.changes or {}) do
    if uri ~= cur then
      return true
    end
  end
  for _, c in ipairs(edit.documentChanges or {}) do
    if c.kind or (c.textDocument and c.textDocument.uri ~= cur) then
      return true
    end
  end
  return false
end

local wrapped = false
local function wrap_workspace_edit()
  if wrapped then
    return
  end
  wrapped = true
  local orig = vim.lsp.util.apply_workspace_edit
  vim.lsp.util.apply_workspace_edit = function(edit, ...)
    local res = orig(edit, ...)
    if type(edit) == "table" and touches_other_files(edit) then
      vim.schedule(M.save_all)
    end
    return res
  end
end'''),
    ...para('--', r'A rename in rust-analyzer can change a dozen files. LSP applies those edits to buffers and leaves them modified, which means undo history and disk disagree until someone types :wa. The module wraps vim.lsp.util.apply_workspace_edit once, after the first LspAttach (the autocmd is registered with once = true, and a wrapped flag makes a second call harmless). The wrapper calls the original, then, if the edit touches any file other than the current buffer, schedules save_all. touches_other_files looks at both shapes of a WorkspaceEdit: the older changes map keyed by URI, and the documentChanges array, where any entry with a kind (create, rename, delete) or a different document counts.'),
    ...para('--', r'save_all is careful in two ways. It uses a normal :write rather than noautocmd, and the comment gives the reason: "didSave, local history and neotest all hear about it", i.e. the language server, the local-history snapshot (see local_history.lua) and the test runner all learn about the save. And every candidate still has to pass can_save, so a dependency or a file changed on disk is skipped here as well. The spec lists exactly this: "skips unmodified, dependency and externally changed ones", and "skips unloaded, non-file and nomodifiable buffers".'),
    ...sec(r'what is the same, what differs in xyno-guard.nvim'),
    ...para('--', r'On 2026-10-22 this module was extracted into the standalone plugin xyno-guard.nvim (lua/xyno_guard/init.lua). The logic is the same. The differences, from a diff of the two files:'),
    ...pt('--', r'names', r'buffer variables xynovim_disk_stamp / _warned / _buftype become xyno_guard_stamp / _warned / _buftype, and the augroup xynovim_disk_guard becomes xyno_guard.'),
    ...pt('--', r'setup(_opts)', r'takes an options table that is ignored for now (the comment says "Takes no options yet; safe to call again").'),
    ...pt('--', r'already-open dependency buffers', r'the plugin factors the dependency lock into lock_dependency(buf) and, in the loop at the end of setup, also locks buffers that are already loaded when setup runs. In this config, the lock is applied only by the BufReadPost autocmd, so a dependency file that was already open before setup ran would not be made nomodifiable by it. Everything else, including can_save, is unchanged.'),
    ...pt('--', r'comment', r'the plugin no longer says that :checktime on FocusGained is LazyVim’s: it only says that detecting a change is up to Neovim or a distribution’s own autocmd.'),
    ...para('--', r'This config has not switched to the plugin yet: options.lua calls require("config.disk_guard").setup() and auto-save’s condition requires config.disk_guard directly.'),
    ...sec(r'edge cases handled'),
    ...pt('--', r'file deleted while open', r'can_save returns false with a "no longer exists" warning, and auto-save does not recreate the file. The spec has a test named "autosave does not recreate a deleted file".'),
    ...pt('--', r'readonly or special buffers', r'refused first of all, before any filesystem access.'),
    ...pt('--', r'never saw the file', r'a buffer with no stamp is recorded and allowed; the guard never blocks on missing information.'),
    ...pt('--', r'repeated warnings', r'one per distinct disk state.'),
    ...pt('--', r'case-insensitive disks', r'lower-cased comparison on Windows and macOS only.'),
    ...pt('--', r'a dependency that was made modifiable on purpose', r'the header says ":set modifiable to hack on one deliberately"; can_save still refuses to auto-save it. The test is called "never touches a dependency source, even when it was made modifiable and edited".'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/auto-save-disk-guard_spec.lua has 52 it() blocks and one pending entry, and its test names are numbered after the behaviours the design lists (1 to 23). They cover the plugin configuration, the debounce and undo-block behaviour of auto-save, is_dependency (including CARGO_HOME and RUSTUP_HOME), can_save and its stamps, the Pre/Post pair, FileChangedShell for conflict, deleted and other reasons, save_all, and the wrapping of apply_workspace_edit. One test is gated on having rust-analyzer: "multi-file rename (needs rust-analyzer)" checks that a rename leaves no modified buffers and everything on disk.'),
    ...sec(r'history'),
    ...pt('--', r'b65284f · 2026-10-13', r'Batch 3: data safety. The file is created with auto-save, dependency buffers, neotest watch and the save after multi-file edits.'),
    ...pt('--', r'3f868dd · 2026-10-13', r'Final loop round 3: the commit message lists "can_save non-file buffers", which is the readonly and buftype branch at the top of can_save.'),
    ...pt('--', r'ff1c8fa · 2026-10-16', r'Windows and macOS portability: the norm helper, the case folding and the normalised CARGO_HOME.'),
  ],
);
