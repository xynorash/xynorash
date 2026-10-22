import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-guard.nvim/lua/xyno_guard/init.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'init.lua — the guard that stands in front of every automatic write'),
    cm('--', r'dependency sources, files changed behind your back, multi-file edits'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'the whole plugin: setup(), can_save(), is_dependency(), save_all()'),
    kv(r'language', r'Lua (Neovim 0.12+), no dependencies'),
    kv(r'size', r'258 lines'),
    kv(r'entry points', r'can_save as an auto-save condition; setup() for the autocmds'),
    kv(r'history', r'b7b715d (2026-10-22) extracted from xynovim lua/config/disk_guard.lua; 9c3e9ec adds '
        r'locking of already-loaded buffers'),
    ...sec(r'why this file exists'),
    ...para('--', r'An auto-save plugin writes while you are not looking, which is exactly what makes it '
        r'dangerous in three situations the header lists in four bullets. It must not write into '
        r'dependency or standard-library sources that you were only reading. It must not overwrite '
        r'a file that changed on disk behind the buffer’s back, through git checkout, an agent, sed '
        r'-i or cargo fmt in another pane. And after a rename that touches many files, it must not '
        r'leave them unsaved. The module is the author’s answer to all three, written for a Rust '
        r'workflow, and it began in xynovim as lua/config/disk_guard.lua.'),
    ...code('lua', r'lua/xyno_guard/init.lua · lines 1-17', r'''
-- What auto-save must never do: write into dependency/std sources, overwrite a
-- file that changed on disk behind the buffer's back (git checkout, an agent,
-- `sed -i`, cargo fmt in another pane), or leave the files a multi-file
-- rename touched unsaved.
--   * Dependency and std buffers (~/.cargo/registry, ~/.cargo/git, ~/.rustup)
--     are nomodifiable (`:set modifiable` to hack on one deliberately).
--   * auto-save's `condition` (can_save): the disk mtime recorded when the
--     buffer was read/written must still match, else the save is skipped and
--     the user is warned once. nvim itself would stop at a blocking W12 "Do you
--     really want to write to it (y/n)?" that swallows keystrokes.
--   * FileChangedShell never prompts: an unmodified buffer is reloaded, a
--     modified one (or a deleted file) is left alone with one warning. (Detecting
--     the change is up to nvim: `:checktime`, or a distribution's FocusGained autocmd.)
--   * Workspace edits touching other files (rename, file rename, code
--     actions) are followed by a write of every modified buffer that passes
--     can_save: undo/disk stay consistent without waiting for :wa.
local M = {}
'''),
    ...para('--', r'The header also records a fact about Neovim that explains the design: without this guard, '
        r'Neovim itself would stop at a blocking W12 prompt, Do you really want to write to it, '
        r'which swallows keystrokes. A prompt in the middle of typing is the real failure being '
        r'avoided, more than the lost data.'),
    ...sec(r'the origin in xynovim'),
    ...para('--', r'Reading the history of disk_guard.lua in xynovim: it arrived in b65284f (2026-10-13) in a '
        r'batch of data-safety changes whose commit message lists the auto-save disk guard and '
        r'dependency buffers and save after multi-file edits; 3f868dd (2026-10-13) fixed can_save '
        r'for non-file buffers in a later round of field-test bugs; and ff1c8fa (2026-10-16) was '
        r'the Windows and macOS portability commit. The case-folding at the top of this file is '
        r'consistent with that portability work, though the file does not say so. In the extracted '
        r'repository, 9c3e9ec adds one more behaviour, locking dependency buffers that were already '
        r'loaded when setup runs.'),
    ...sec(r'path handling that works on three systems'),
    ...code('lua', r'lua/xyno_guard/init.lua · lines 19-28', r'''
local home = vim.uv.os_homedir()

-- Windows and macOS file systems are case-insensitive by default, and nvim
-- hands out backslash paths on Windows: compare normalized and lowercased.
local fold = vim.fn.has("win32") == 1 or vim.fn.has("mac") == 1
local function norm(p)
  local slash = p:sub(-1) == "/" or p:sub(-1) == "\\" -- normalize() drops a trailing slash, a root needs it
  p = vim.fs.normalize(p) .. (slash and "/" or "")
  return fold and p:lower() or p
end
'''),
    ...para('--', r'fold is true on Windows and macOS, whose file systems are case-insensitive by default, '
        r'and norm lowercases there so comparisons succeed. The comment also notes that Neovim '
        r'hands out backslash paths on Windows. The slash handling in norm is a small fix for a '
        r'real quirk: vim.fs.normalize drops a trailing slash, but a root such as the registry '
        r'directory needs it so that the prefix test below does not match a sibling directory '
        r'called registry-old. norm remembers whether the input ended in a separator and puts one '
        r'back.'),
    ...sec(r'what counts as a dependency'),
    ...code('lua', r'lua/xyno_guard/init.lua · lines 30-54', r'''
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
end
'''),
    ...para('--', r'dep_roots builds the list on every call and does not cache it. The three fixed roots are '
        r'under the home directory: .cargo/registry, .cargo/git and .rustup. Then CARGO_HOME and '
        r'RUSTUP_HOME are honoured if set, with their trailing slashes stripped and the suffix '
        r're-added, and everything is normalized. Not caching means a test, or a user, can change '
        r'CARGO_HOME at runtime and the next call sees it, and the cost is a handful of string '
        r'operations. is_dependency is a plain prefix comparison against those roots. The spec '
        r'checks the corners: that similar prefixes and project files do not match, and that both '
        r'environment variables are honoured.'),
    ...para('--', r'The Rust-specific roots are a stated limit in the README: other languages’ dependency '
        r'directories are not covered.'),
    ...sec(r'the mtime stamp'),
    ...code('lua', r'lua/xyno_guard/init.lua · lines 56-77', r'''
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
    vim.b[buf].xyno_guard_stamp = stamp(vim.api.nvim_buf_get_name(buf))
  end
end

local function warn_once(buf, key, msg)
  if vim.b[buf].xyno_guard_warned ~= key then
    vim.b[buf].xyno_guard_warned = key
    vim.notify(msg, vim.log.levels.WARN)
  end
end
'''),
    ...para('--', r'The guard’s memory is one buffer variable, xyno_guard_stamp, holding the file’s '
        r'modification time formatted as seconds and nanoseconds, with the nanoseconds zero-padded '
        r'to nine digits. stamp returns nil if the file '
        r'does not exist, which is how deletion is detected. is_file_buf says a buffer is a real '
        r'file: valid, buftype empty, and a non-empty name. warn_once keeps the last warning key in '
        r'another buffer variable and notifies only when the key differs, so a buffer that is '
        r'checked a hundred times produces one message per distinct cause.'),
    ...sec(r'can_save: the decision'),
    ...code('lua', r'lua/xyno_guard/init.lua · lines 79-117', r'''
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
  local was = vim.b[buf].xyno_guard_stamp
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
end
'''),
    ...para('--', r'The order of the checks is the policy. Invalid buffers, any buffer with a buftype and any '
        r'readonly buffer are refused first. The comment names the case that made this necessary: '
        r'the 99 prompt is an acwrite buffer, and writing it raised a blocking readonly prompt '
        r'(this is the fix from xynovim commit 3f868dd). Then a buffer that is not a file at all, '
        r'which can only mean a no-name buffer here, is allowed. Dependency files are refused. Then '
        r'the stamp logic.'),
    ...pt('--', r'No stamp yet', r'the buffer was never read or written by this Neovim, or was opened before the guard ran. '
        r'There is nothing to compare, so the stamp is recorded now and the save is allowed. This '
        r'is the guard giving the benefit of the doubt exactly once.'),
    ...pt('--', r'File gone', r'the stamp exists but stat finds no file: one warning with the key gone, and no save. '
        r'Auto-save will not recreate a file the user or a tool deleted. The message tells the user '
        r'the way out, :w.'),
    ...pt('--', r'Mtime differs', r'the file changed on disk after the buffer last saw it: one warning, keyed by the new '
        r'mtime, and no save. A second external change produces a second warning, and the spec '
        r'checks that the same mtime is never repeated. The message names both exits: :w! keeps the '
        r'buffer and :e! takes the disk version.'),
    ...pt('--', r'Otherwise', r'true.'),
    ...para('--', r'It is a pure predicate with two side effects, a recorded stamp and a warning, and no '
        r'write. That is what lets it be used as the condition of any auto-save plugin.'),
    ...sec(r'save_all'),
    ...code('lua', r'lua/xyno_guard/init.lua · lines 119-135', r'''
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
'''),
    ...para('--', r'Writing every modified buffer is the guard’s own save. It requires the buffer to be '
        r'loaded, a file buffer, modified, modifiable and to pass can_save, so the same protections '
        r'apply. The write is the full silent! write, not noautocmd, and the comment says why: '
        r'didSave, local history and neotest all hear about it. The call runs inside nvim_buf_call '
        r'so that the right buffer is current. The spec checks that it skips unloaded, non-file and '
        r'nomodifiable buffers as well as dependency and externally changed ones.'),
    ...sec(r'watching workspace edits'),
    ...code('lua', r'lua/xyno_guard/init.lua · lines 137-167', r'''
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
end
'''),
    ...para('--', r'touches_other_files looks at the two shapes of an LSP WorkspaceEdit. The older changes '
        r'map is keyed by uri; the newer documentChanges list holds either text document edits or '
        r'file operations, which carry a kind (create, rename, delete). Anything that is not the '
        r'current buffer, or any operation with a kind, counts. wrap_workspace_edit replaces '
        r'vim.lsp.util.apply_workspace_edit with a wrapper that calls the original, keeps its '
        r'result, and schedules save_all if the edit reaches other files. The wrapped flag makes it '
        r'idempotent, so many language servers attaching do not wrap it again, and the wrapper '
        r'returns the original’s value, which the spec checks. Scheduling matters: the original has '
        r'finished applying the edit before the saves run.'),
    ...sec(r'setup: the autocmds'),
    ...code('lua', r'lua/xyno_guard/init.lua · lines 169-178', r'''
--- Install the guard's autocmds. Takes no options yet; safe to call again.
--- @param _opts? table
function M.setup(_opts)
  local group = vim.api.nvim_create_augroup("xyno_guard", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "BufFilePost", "FileChangedShellPost" }, {
    group = group,
    callback = function(ev)
      record(ev.buf)
    end,
  })
'''),
    ...para('--', r'All autocmds go in one group created with clear = true, which is what makes setup safe to '
        r'call twice, and the spec counts the autocmds to prove there is one set. The stamp is '
        r'recorded on four events: BufReadPost, BufWritePost, BufFilePost (a rename of the buffer) '
        r'and FileChangedShellPost (after Neovim reloaded the file).'),
    ...sec(r'the second check, right before the write'),
    ...code('lua', r'lua/xyno_guard/init.lua · lines 179-211', r'''
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
        vim.b[buf].xyno_guard_buftype = vim.bo[buf].buftype
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
      local bt = vim.b[buf].xyno_guard_buftype
      if bt ~= nil then
        vim.bo[buf].buftype = bt
        vim.b[buf].xyno_guard_buftype = nil
      else
        record(buf)
      end
    end,
  })
'''),
    ...para('--', r'Auto-save checks its condition when the event fires but writes up to a second later, '
        r'because it debounces. The file can change in that window. So the guard listens to '
        r'AutoSaveWritePre, the user event of okuuva/auto-save.nvim, and asks can_save again. If '
        r'the answer is no, it stores the buffer’s buftype and '
        r'sets it to nowrite. A nowrite buffer cannot be written, so the write fails with E382, '
        r'which auto-save’s silent! hides. The refusal uses only the plugin’s Pre event and an ordinary buffer option. In AutoSaveWritePost the type is restored, and if nothing was refused the '
        r'stamp is recorded, because auto-save writes with noautocmd and BufWritePost never fires. '
        r'A listener of AutoSaveWritePost can tell a refused write apart because modified is still '
        r'set; the spec has a test for exactly this, and another one for a file changed inside the '
        r'debounce window where it asserts the content on disk is still the other writer’s, the '
        r'buffer keeps its edits, and no W12 text appears in the messages.'),
    ...sec(r'locking dependency buffers'),
    ...code('lua', r'lua/xyno_guard/init.lua · lines 212-223', r'''
  local function lock_dependency(buf)
    if M.is_dependency(vim.api.nvim_buf_get_name(buf)) then
      vim.bo[buf].modifiable = false
      vim.bo[buf].readonly = true
    end
  end
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(ev)
      lock_dependency(ev.buf)
    end,
  })
'''),
    ...para('--', r'Dependency buffers are made nomodifiable and readonly when they are read. The helper '
        r'lock_dependency was extracted in 9c3e9ec, the last commit, so that the same code can '
        r'serve the buffers that already existed when setup ran. Before that commit a plugin that '
        r'loaded late left such a buffer editable, which the README now documents: use event = '
        r'VeryLazy if you open dependency sources right at startup. The lock is a convenience on '
        r'top of the actual guard, since can_save refuses dependency files even when someone runs '
        r':set modifiable.'),
    ...sec(r'FileChangedShell: never prompt'),
    ...code('lua', r'lua/xyno_guard/init.lua · lines 224-241', r'''
  vim.api.nvim_create_autocmd("FileChangedShell", {
    group = group,
    callback = function(ev)
      local reason = vim.v.fcs_reason
      if reason == "conflict" or reason == "deleted" then
        vim.v.fcs_choice = ""
        vim.b[ev.buf].xyno_guard_warned = stamp(ev.file) or "gone" -- can_save need not repeat it
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
  })
'''),
    ...para('--', r'When Neovim notices that a file changed, it asks the user. This handler answers on the '
        r'user’s behalf. For the two dangerous reasons, conflict (the buffer has edits and the file '
        r'changed) and deleted, fcs_choice is set to the empty string, which means do nothing: the '
        r'edits are kept. It also writes the warned key so that can_save does not warn a second '
        r'time about the same cause, and shows one message. For every other reason the answer is '
        r'reload when autoread is on, otherwise ask. The detecting of the change is left to Neovim '
        r'(:checktime, or a distribution’s FocusGained autocmd) as the header says. The spec covers '
        r'the four cases, including that with autoread Neovim reloads without the event.'),
    ...sec(r'wiring LSP, and the buffers that existed before'),
    ...code('lua', r'lua/xyno_guard/init.lua · lines 242-256', r'''
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    once = true,
    callback = wrap_workspace_edit,
  })
  -- buffers opened before this ran
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      record(buf)
      if is_file_buf(buf) then
        lock_dependency(buf)
      end
    end
  end
end
'''),
    ...para('--', r'The wrap is installed once, on the first LspAttach, with once = true, so no LSP code runs '
        r'for a session that never starts a server. The last loop handles buffers already loaded at '
        r'setup time: it records their stamps (the spec for this is the last one in the file) and, '
        r'since 9c3e9ec, locks the dependency ones.'),
    ...sec(r'design decisions'),
    ...pt('--', r'One mechanism per hazard', r'stamps for external change, a root list for dependencies, a wrapper for workspace edits. '
        r'Each one can fail without the others.'),
    ...pt('--', r'Warn once', r'a guard that nags becomes noise. Two buffer variables remember the last reason.'),
    ...pt('--', r'No options', r'setup takes an argument that is accepted and ignored, documented as there for later. The '
        r'README says the same.'),
    ...pt('--', r'Fail by refusing', r'when unsure, the guard declines to write. The only exception is the case of no stamp, '
        r'which it cannot judge.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/guard_spec.lua has 40 it() blocks (the README says 39; 9c3e9ec added one test and did not touch that count), with feature numbers in their names (for example 11 for '
        r'an external change and 12 for a deleted file). Those that drive a real auto-save plugin '
        r'look for okuuva/auto-save.nvim and skip when it is absent.'),
    ...sec(r'history'),
    ...pt('--', r'b7b715d', r'2026-10-22, Add the guard module, extracted from xynovim.'),
    ...pt('--', r'9c3e9ec', r'2026-10-22, Lock dependency buffers that are already loaded when setup runs: adds '
        r'lock_dependency, the call in the final loop, the spec numbered 8 for it, and the README '
        r'and help text about it.'),
  ],
);
