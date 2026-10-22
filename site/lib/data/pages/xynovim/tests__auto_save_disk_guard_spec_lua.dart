import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/auto-save-disk-guard_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'auto-save-disk-guard_spec.lua — saving automatically without ever overwriting what is on disk'),
    cm('--', r'53 numbered scenarios for the auto-save plugin and the disk guard that stops it'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/plugins/auto-save.lua and lua/config/disk_guard.lua'),
    kv(r'language', r'Lua spec, 1066 lines, 52 it() blocks, 1 pending, 13 describe() blocks'),
    kv(r'needs', r'tmux for the typing test, rust-analyzer for the multi-file rename test; both skip with a message otherwise'),
    kv(r'isolation', r'every file lives in a temp dir; dependency paths are faked with CARGO_HOME and RUSTUP_HOME'),
    kv(r'history', r'4 commits: b2fee5c (2026-10-13), a3d33c8, 3f868dd (2026-10-13), 25086fd (2026-10-14)'),
    ...sec(r'why this file exists'),
    ...para('--', r'Auto-save is a risky feature: a buffer that writes itself can overwrite a newer version of the file that a formatter, git checkout or another editor put on disk, and it can write into a crate in the cargo registry that must stay pristine. The config therefore pairs the auto-save plugin with a disk guard, and the guard is the part this spec cares most about. The test names start with a number, 1 to 23, which are the items of a checklist of behaviours the feature must have; a number that appears twice (3, 6, 13) is the same behaviour tested from several angles.'),
    ...code('lua', r'tests/auto-save-disk-guard_spec.lua · lines 1-4', r'''
-- auto-save (lua/plugins/auto-save.lua) and the disk guard (lua/config/disk_guard.lua).
-- All files live in temp dirs; "dependency" paths are faked with CARGO_HOME /
-- RUSTUP_HOME pointing into one. Needs rust-analyzer only for the multi-file
-- rename test (skipped with a message otherwise).'''),
    ...sec(r'a file that changes behind the buffer'),
    ...para('--', r'Several scenarios need a file to change on disk without the buffer noticing. external_write writes the file and then forces the mtime to a value that differs from every earlier one, by adding 7 seconds per call to a point 100 seconds in the future. The comment says why: no reliance on clock granularity, so the test passes on filesystems with one-second timestamps. stamp_of formats the mtime as sec.nsec with nine digits, the same format the guard records in a buffer variable.'),
    ...code('lua', r'tests/auto-save-disk-guard_spec.lua · lines 25-37', r'''
--- Change a file on disk "behind the buffer's back": new content and an mtime
--- that differs from every earlier one (no reliance on clock granularity).
local function external_write(path, text)
  write(path, text)
  mtime_n = mtime_n + 7
  local t = os.time() + 100 + mtime_n
  assert(vim.uv.fs_utime(path, t, t))
end

local function stamp_of(path)
  local st = assert(vim.uv.fs_stat(path))
  return ("%d.%09d"):format(st.mtime.sec, st.mtime.nsec)
end'''),
    ...sec(r'the guard in four rules'),
    ...para('--', r'The can_save tests are the specification of the guard.'),
    blank,
    ...pt('--', r'A fresh buffer', r'with no stamp yet, can_save records one and returns true; an unchanged mtime returns true silently.'),
    ...pt('--', r'A change on disk', r'returns false and warns once per mtime, with a message that names the file and the two ways out: :w! keeps the buffer, :e! takes the disk version. A newer change warns again.'),
    ...pt('--', r'A write', r'after :w! the stamp is re-recorded and can_save returns true again.'),
    ...pt('--', r'A deleted file', r'returns false with one warning, and the autosave test shows that the file is not recreated and the buffer stays modified.'),
    ...code('lua', r'tests/auto-save-disk-guard_spec.lua · lines 648-701', r'''
    it("11 a change on disk after the stamp: false and one warning per mtime", function()
      local path, buf = open_file()
      local cap = H.capture_notify()
      external_write(path, "changed\n")
      local short = vim.fn.fnamemodify(path, ":~:.")
      local msg = short
        .. " changed on disk while this buffer has unsaved edits: auto-save is paused for it (:w! keeps the buffer, :e! takes the disk version)"
      H.eq(false, dg.can_save(buf))
      H.eq({ msg }, warnings(cap))
      H.eq(false, dg.can_save(buf))
      H.eq(false, dg.can_save(buf))
      H.eq({ msg }, warnings(cap), "not repeated for the same mtime")
      external_write(path, "changed again\n")
      H.eq(false, dg.can_save(buf))
      H.eq({ msg, msg }, warnings(cap), "a newer change warns again")
      cap.restore()
    end)

    it("11 becomes true again once the buffer was written (:w! keeps the buffer)", function()
      local path, buf = open_file()
      external_write(path, "disk\n")
      H.eq(false, dg.can_save(buf))
      set_lines(buf, { "mine" })
      vim.cmd("silent write!")
      H.eq("mine\n", read(path))
      H.eq(true, dg.can_save(buf))
    end)

    it("12 a deleted file: false and one warning", function()
      local path, buf = open_file()
      local cap = H.capture_notify()
      os.remove(path)
      local msg = vim.fn.fnamemodify(path, ":~:.") .. " no longer exists on disk: auto-save is paused for this buffer (:w to recreate it)"
      H.eq(false, dg.can_save(buf))
      H.eq(false, dg.can_save(buf))
      H.eq({ msg }, warnings(cap))
      cap.restore()
    end)

    it("12 autosave does not recreate a deleted file", function()
      local path, buf = open_file()
      local cap = H.capture_notify()
      os.remove(path)
      as().on()
      set_lines(buf, { "edit" })
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
      vim.wait(1800)
      H.eq(nil, vim.uv.fs_stat(path))
      H.ok(vim.bo[buf].modified)
      H.eq(1, #vim.tbl_filter(function(m)
        return m:find("no longer exists on disk", 1, true)
      end, warnings(cap)))
      cap.restore()
    end)'''),
    ...sec(r'the write is guarded twice'),
    ...para('--', r'Checking can_save when the timer starts is not enough, because the file may change during the debounce delay. The AutoSaveWritePre handler checks again, and if the write is not allowed it sets buftype to nowrite and remembers the old value in a buffer variable, so that a write fails by itself instead of silently overwriting; AutoSaveWritePost restores it. The test proves the whole cycle: nowrite during, the file still holding the disk content after a :write attempt, buftype restored after. Another test starts the timer, changes the file inside the window and checks the file keeps the other content, the buffer stays modified, nothing is stuck in nowrite, and the message Do you really want to write never appears: no blocking prompt.'),
    ...code('lua', r'tests/auto-save-disk-guard_spec.lua · lines 710-752', r'''
    it("13 Pre with can_save false switches buftype to nowrite (saved), Post restores it", function()
      local path, buf = open_file()
      local cap = H.capture_notify()
      external_write(path, "disk\n")
      fire("AutoSaveWritePre", buf)
      H.eq("nowrite", vim.bo[buf].buftype)
      H.eq("", vim.b[buf].xynovim_disk_buftype)
      set_lines(buf, { "mine" })
      vim.cmd("silent! write")
      H.eq("disk\n", read(path), "a nowrite buffer cannot be written")
      fire("AutoSaveWritePost", buf)
      H.eq("", vim.bo[buf].buftype)
      H.is_nil(vim.b[buf].xynovim_disk_buftype)
      cap.restore()
    end)

    it("13 Pre with can_save true leaves the buftype alone, Post records the stamp", function()
      local path, buf = open_file()
      fire("AutoSaveWritePre", buf)
      H.eq("", vim.bo[buf].buftype)
      H.is_nil(vim.b[buf].xynovim_disk_buftype)
      external_write(path, "now\n")
      fire("AutoSaveWritePost", buf)
      H.eq(stamp_of(path), vim.b[buf].xynovim_disk_stamp)
    end)

    it("13/14 a file changed inside the debounce window is not overwritten, no W12 prompt, buffer stays modified", function()
      local path, buf = open_file("one\n")
      local cap = H.capture_notify()
      H.clear_messages()
      as().on()
      set_lines(buf, { "mine" })
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf }) -- condition passes: timer starts
      external_write(path, "theirs\n") -- ... then the file changes before the write
      vim.wait(2000)
      H.eq("theirs\n", read(path))
      H.eq(true, vim.bo[buf].modified, "a refused write leaves modified=true")
      H.eq("", vim.bo[buf].buftype)
      H.is_nil(vim.b[buf].xynovim_disk_buftype)
      H.no_match(H.messages(), "Do you really want to write", true)
      H.eq({ "mine" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      cap.restore()
    end)'''),
    ...sec(r'no prompt on external changes'),
    ...para('--', r'nvim normally asks what to do when a file changes under a modified buffer. The FileChangedShell handler replaces the prompt. In the conflict case the test requires that the handler sees reason conflict with choice empty, that exactly one warning is shown with the :e! and :w! advice, that the user unsaved edit is still in the buffer, and that can_save does not repeat the warning. The tests that follow cover a deleted file, other reasons, an unmodified buffer that reloads, and the LazyVim FocusGained checktime that must still exist.'),
    ...code('lua', r'tests/auto-save-disk-guard_spec.lua · lines 796-811', r'''
    it("15 conflict (modified buffer, file changed): no prompt, choice '', one warning, edits kept", function()
      local path, buf = open_file()
      local seen = spy()
      local cap = H.capture_notify()
      set_lines(buf, { "unsaved" })
      external_write(path, "disk\n")
      vim.cmd("checktime")
      H.eq({ { reason = "conflict", choice = "" } }, seen)
      H.eq({
        vim.fn.fnamemodify(path, ":~:.") .. " changed on disk and the buffer has unsaved edits (:e! takes the disk version, :w! keeps the buffer)",
      }, warnings(cap))
      H.eq({ "unsaved" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      H.eq(false, dg.can_save(buf))
      H.eq(1, #warnings(cap), "can_save does not repeat the warning")
      cap.restore()
    end)'''),
    ...sec(r'dependency sources are untouchable'),
    ...para('--', r'Files under CARGO_HOME registry and git, and under RUSTUP_HOME, are dependencies; they open nomodifiable and readonly. The test makes a registry path under a temp CARGO_HOME, opens it, forcibly sets modifiable, edits it, fires TextChanged and BufLeave, waits two seconds and requires the content on disk to be unchanged while the buffer stays modified. Even a user who removes the guard once cannot make auto-save write there. Separate tests check that similar prefixes are not dependencies and that $CARGO_HOME and $RUSTUP_HOME are honoured.'),
    ...code('lua', r'tests/auto-save-disk-guard_spec.lua · lines 365-380', r'''
    it("21 never touches a dependency source, even when it was made modifiable and edited", function()
      local ch = H.tmpdir()
      env("CARGO_HOME", ch)
      local path = ch .. "/registry/src/index-1/crate-1.0.0/src/lib.rs"
      write(path, "pub fn a() {}\n")
      local buf = H.open(path)
      H.eq(false, vim.bo[buf].modifiable)
      vim.cmd("set modifiable")
      as().on()
      set_lines(buf, { "// edited" })
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
      vim.api.nvim_exec_autocmds("BufLeave", { buffer = buf })
      vim.wait(2000)
      H.eq("pub fn a() {}\n", read(path))
      H.ok(vim.bo[buf].modified)
    end)'''),
    ...sec(r'one undo for one insert'),
    ...para('--', r'A field test found that the debounced write closed the undo block, so after typing three words with pauses a single u undid only the last word. The fix is an undojoin in the hook. A unit test cannot show this, because it needs real insert mode and timing, so the test starts a real nvim in tmux on a private socket, types in three steps while waiting for the file to contain each stage, presses Escape, and presses u. The final file must be the original line again. The comment describes the bug in the words of the field test.'),
    ...code('lua', r'tests/auto-save-disk-guard_spec.lua · lines 286-318', r'''
    it("3 an autosave in the middle of an insert does not split the undo block: one u undoes the whole insert", function()
      H.need_tmux()
      -- field test: the debounced write closed the insert-mode undo block, so `u` after
      -- "abc" <pause> "def" <pause> "ghi" removed only " ghi"; the hook now runs :undojoin
      local dir = H.tmpdir()
      local path = dir .. "/undo.txt"
      write(path, "one\n")
      local function pane()
        return H.tmux({ "capture-pane", "-p", "-t", "t" }, "undo").stdout or ""
      end
      local r = H.tmux({ "new-session", "-d", "-s", "t", "-x", "120", "-y", "30", "-c", dir, "nvim " .. path }, "undo")
      H.eq(0, r.code, r.stderr)
      H.wait_for(function()
        return pane():find("one", 1, true)
      end, 60000, "nvim to show the file")
      vim.wait(1500)
      H.tmux({ "send-keys", "-t", "t", "A", " abc" }, "undo")
      H.wait_for(function()
        return read(path) == "one abc\n"
      end, 6000, "first autosave while typing")
      H.tmux({ "send-keys", "-t", "t", " def" }, "undo")
      H.wait_for(function()
        return read(path) == "one abc def\n"
      end, 6000, "second autosave while typing")
      H.tmux({ "send-keys", "-t", "t", " ghi", "Escape" }, "undo")
      H.wait_for(function()
        return read(path) == "one abc def ghi\n"
      end, 6000, "autosave on leaving insert mode")
      H.tmux({ "send-keys", "-t", "t", "u" }, "undo")
      H.wait_for(function()
        return read(path) == "one\n"
      end, 6000, "u undid the whole insert (and the undo was autosaved)")
    end)'''),
    ...sec(r'what autosave must tell the rest of the editor'),
    ...para('--', r'Writes by auto-save run with noautocmd, which suppresses BufWritePost, so the handler for AutoSaveWritePost sends textDocument/didSave to attached clients that support it (and only those), sends none if the buffer is still modified after a refused write, re-emits BufWritePost only while a neotest watcher exists, and routes the event to nvim-lint for non-Rust buffers (Cargo.toml lints had gone stale) and to neotest own rediscovery for Rust ones. Test 23 asserts that didSave is sent although noautocmd suppresses BufWritePost.'),
    ...sec(r'multi-file edits and the 99 guard'),
    ...para('--', r'save_all writes modified file buffers with events and skips unmodified, dependency, externally changed, unloaded, non-file and nomodifiable buffers. The apply_workspace_edit wrapper schedules save_all when an edit touches another file (changes, documentChanges and create/rename/delete kinds), not for an edit confined to the current buffer, and it wraps once however many clients attach. The last block tests the off and on calls that the 99 guard makes; the matching test for the guard turning it back on only if it turned it off is a pending entry that points to agent-99-guard_spec.lua.'),
    ...sec(r'trade-offs'),
    blank,
    ...pt('--', r'Numbers in names', r'a long checklist is easier to trace to a bug report when each test carries its item number.'),
    ...pt('--', r'Fake LSP clients', r'didSave tests use a fake client, so they run without rust-analyzer; only the rename test needs the real one.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created.'),
    ...pt('--', r'a3d33c8 (2026-10-13)', r'the "auto-save undo block" field test fix.'),
    ...pt('--', r'3f868dd, 25086fd (2026-10-13 and 2026-10-14)', r'later field test rounds, including "auto-save lints" in the second.'),
  ],
);
