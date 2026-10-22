import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-guard.nvim/tests/guard_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'guard_spec.lua — the guard tested against a real auto-save plugin'),
    cm('--', r'temp dirs, faked cargo roots, a fake language server, real debounce timers'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'the only spec file, 797 lines, 40 tests in several describe groups'),
    kv(r'language', r'Lua on the repository’s own harness'),
    kv(r'run with', r'nvim --headless --clean -l tests/run.lua'),
    kv(r'needs', r'okuuva/auto-save.nvim for the tests that drive it; they skip without it'),
    kv(r'history', r'added in 9c10c91 (2026-10-22); one test added in 9c3e9ec'),
    ...sec(r'why this file exists'),
    ...para('--', r'The guard sits between an editor and a plugin that writes files on a timer, so a test '
        r'that only calls can_save would miss the most important failures: the interleaving of an '
        r'external write, a debounce timer and an autocmd. This spec therefore exists in two '
        r'layers. Unit-style tests call the API directly with files in temp directories. '
        r'Integration tests set up the real okuuva/auto-save.nvim with the guard as its condition '
        r'and drive it with real events and real waiting. The header says how the two relate.'),
    ...code('lua', r'tests/guard_spec.lua · lines 1-6', r'''
-- xyno-guard: the guard itself (lua/xyno_guard/init.lua) and its use with a real
-- auto-save plugin (okuuva/auto-save.nvim, see tests/run.lua for where it is
-- looked for; those tests skip when it is absent).
-- All files live in temp dirs; "dependency" paths are faked with CARGO_HOME /
-- RUSTUP_HOME pointing into one.
local H = require("xynotest.helpers")
'''),
    ...sec(r'no real cargo, no real home'),
    ...code('lua', r'tests/guard_spec.lua · lines 53-60', r'''
local env_undo = {}
local function env(name, value)
  local old = vim.env[name]
  vim.env[name] = value
  env_undo[#env_undo + 1] = function()
    vim.env[name] = old
  end
end
'''),
    ...para('--', r'Every path is faked. A dependency source is just a file below a temp directory that '
        r'CARGO_HOME or RUSTUP_HOME points at, and the guard’s own is_dependency honours those '
        r'variables, so the spec never needs ~/.cargo. The helper that sets variables records an '
        r'undo closure, and after_each plays them back in reverse order, so a failing test cannot '
        r'leak an environment variable into the next.'),
    ...sec(r'the env helper and the auto-save setup'),
    ...code('lua', r'tests/guard_spec.lua · lines 148-158', r'''
-- The plugin is set up once the way the README shows; every test starts with
-- auto-save off (tests that need it switch it on) so a debounce timer cannot
-- fire in the middle of a unit test.
if have_autosave then
  require("auto-save").setup({
    enabled = true,
    noautocmd = true,
    condition = dg.can_save,
    debounce_delay = 1000,
  })
end
'''),
    ...code('lua', r'tests/guard_spec.lua · lines 161-179', r'''
  before_each(function()
    if have_autosave then
      as().off()
    end
  end)
  after_each(function()
    if have_autosave then
      as().off()
    end
    for i = #env_undo, 1, -1 do
      env_undo[i]()
    end
    env_undo = {}
    pcall(function()
      for _, c in ipairs(vim.lsp.get_clients()) do
        c:stop(true)
      end
    end)
    vim.cmd("silent! %bwipeout!")
'''),
    ...para('--', r'The plugin is set up once, the way the README shows it: noautocmd writes, the condition '
        r'set to can_save, and a debounce delay of 1000 milliseconds. Every test starts with '
        r'auto-save switched off, so that a timer left over from one test cannot fire in the middle '
        r'of another; tests that need the plugin turn it on. The after_each hook (lines 166-179) '
        r'also stops every LSP client and wipes all buffers.'),
    ...sec(r'a language server that only listens'),
    ...code('lua', r'tests/guard_spec.lua · lines 86-119', r'''
local function fake_lsp(buf, name, save)
  local log = {}
  local cmd = function()
    local closing = false
    return {
      request = function(method, _, cb)
        if method == "initialize" then
          cb(nil, { capabilities = { textDocumentSync = { openClose = true, change = 1, save = save } } })
        elseif method == "shutdown" then
          cb(nil, nil)
        end
        return true, 1
      end,
      notify = function(method, params)
        log[#log + 1] = { method = method, params = params }
        return true
      end,
      is_closing = function()
        return closing
      end,
      terminate = function()
        closing = true
      end,
    }
  end
  local id = vim.lsp.start({ name = name, cmd = cmd, root_dir = vim.fs.dirname(vim.api.nvim_buf_get_name(buf)) }, {
    bufnr = buf,
  })
  H.wait_for(function()
    local c = vim.lsp.get_client_by_id(id)
    return c and c.initialized
  end, 5000, "fake LSP " .. name)
  return log, vim.lsp.get_client_by_id(id)
end
'''),
    ...para('--', r'fake_lsp is a language server written as a function. It answers initialize with '
        r'textDocumentSync capabilities (the save capability is a parameter of the helper), '
        r'shutdown, and records every notification it receives. The test can then count '
        r'textDocument/didSave and didChange messages with the small count helper below it. This is '
        r'how the spec proves that a write really happens with events, since the header of save_all '
        r'says that didSave must be heard.'),
    ...sec(r'the dependency rules'),
    ...code('lua', r'tests/guard_spec.lua · lines 232-250', r'''
    it("21 never touches a dependency source, even when it was made modifiable and edited", function()
      need_autosave()
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
    end)
  end)

'''),
    ...para('--', r'This test carries the strongest claim about dependency sources. The buffer is first '
        r'confirmed nomodifiable, then the test types set modifiable, turns auto-save on, edits the '
        r'buffer, fires TextChanged and BufLeave, waits two seconds, and asserts that the file on '
        r'disk is unchanged and the buffer is still modified. The guard’s lock is thus not the only '
        r'line of defence; can_save refuses dependency files even when somebody unlocks the buffer.'),
    ...sec(r'external changes'),
    ...code('lua', r'tests/guard_spec.lua · lines 394-420', r'''
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
'''),
    ...para('--', r'Two tests describe the contract of an external change. The first changes the file under '
        r'the buffer and expects can_save to return false and exactly one warning, then two more '
        r'calls with no new warning, then a second external write and a second warning: the key is '
        r'the mtime. The second shows the way out: after :w! the buffer’s content is on disk and '
        r'can_save is true again, because writing re-recorded the stamp. The message strings are '
        r'asserted in full, so the instructions a user sees (:w! keeps the buffer, :e! takes the '
        r'disk version) are part of the tested contract.'),
    ...code('lua', r'tests/guard_spec.lua · lines 422-448', r'''
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
      need_autosave()
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
    end)
'''),
    ...para('--', r'A deleted file gives false and one warning, and the integration test checks the '
        r'consequence that matters: after the file is removed and auto-save fires, the path still '
        r'does not exist, the buffer is still modified, and the warning was shown exactly once.'),
    ...sec(r'the debounce window'),
    ...code('lua', r'tests/guard_spec.lua · lines 483-500', r'''
    it("13/14 a file changed inside the debounce window is not overwritten, no W12 prompt, buffer stays modified", function()
      need_autosave()
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
      H.is_nil(vim.b[buf].xyno_guard_buftype)
      H.no_match(H.messages(), "Do you really want to write", true)
      H.eq({ "mine" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      cap.restore()
    end)
'''),
    ...para('--', r'This is the test the whole AutoSaveWritePre design exists for. TextChanged starts the '
        r'timer, and condition passes because nothing has changed yet. Then the test writes to the '
        r'file from outside, and waits two seconds for the debounce to fire. The expectations: the '
        r'file still holds the other writer’s text, the buffer is still modified, its buftype is '
        r'restored to empty, the guard’s temporary buftype variable is cleared, the message log '
        r'never contains the W12 text, and the buffer keeps the user’s text. Each assertion '
        r'corresponds to one half of the nowrite trick in init.lua.'),
    ...code('lua', r'tests/guard_spec.lua · lines 502-531', r'''
    it("14 a listener on AutoSaveWritePost tells a refused write by `modified` still being set", function()
      need_autosave()
      local path, buf = open_file("one\n")
      local cap = H.capture_notify()
      local seen = {}
      local g = vim.api.nvim_create_augroup("spec_post_listener", { clear = true })
      vim.api.nvim_create_autocmd("User", {
        group = g,
        pattern = "AutoSaveWritePost",
        callback = function(ev)
          seen[#seen + 1] = vim.bo[ev.data.saved_buffer].modified
        end,
      })
      as().on()
      set_lines(buf, { "mine" })
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
      external_write(path, "theirs\n")
      vim.wait(2000)
      H.eq({ true }, seen, "refused: still modified")
      -- take the buffer's side with :w!, then an autosave goes through
      vim.cmd("silent write!")
      set_lines(buf, { "mine again" })
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
      H.wait_for(function()
        return read(path) == "mine again\n"
      end, 4000, "autosave after :w!")
      H.eq({ true, false }, seen, "written: no longer modified")
      pcall(vim.api.nvim_del_augroup_by_name, "spec_post_listener")
      cap.restore()
    end)
'''),
    ...para('--', r'The companion test registers its own listener on AutoSaveWritePost and records the '
        r'modified flag at each event. The first write is refused, so the listener sees true. Then '
        r'the test takes the buffer’s side with write!, edits again, waits for the file to equal '
        r'the new text and expects the second observation to be false. That sequence is the '
        r'documentation promise that a listener can tell a refused write by modified being set.'),
    ...sec(r'workspace edits'),
    ...code('lua', r'tests/guard_spec.lua · lines 671-720', r'''
    describe("wrapping apply_workspace_edit (18)", function()
      local orig_save_all
      before_each(function()
        orig_save_all = dg.save_all
        local calls = 0
        dg.save_all = function()
          calls = calls + 1
        end
        dg._calls = function()
          return calls
        end
      end)
      after_each(function()
        dg.save_all = orig_save_all
        dg._calls = nil
      end)

      -- the wrapper's captured original, via its upvalue
      local function orig_of(wrapper)
        local i = 1
        while true do
          local n, v = debug.getupvalue(wrapper, i)
          if not n then
            return nil
          end
          if n == "orig" then
            return v, i
          end
          i = i + 1
        end
      end

      local function attach_fake(name)
        local path, buf = open_file("x\n")
        fake_lsp(buf, name, false)
        return path, buf
      end

      it("18 wraps once after the first LspAttach, and stays wrapped once however many attach", function()
        attach_fake("fake-1")
        local w = vim.lsp.util.apply_workspace_edit
        local orig = orig_of(w)
        H.ok(orig, "wrapper found")
        H.ok(debug.getinfo(orig, "S").source:find("xyno_guard/init.lua", 1, true) == nil, "original is not a wrapper")
        attach_fake("fake-2")
        vim.api.nvim_exec_autocmds("LspAttach", { buffer = vim.api.nvim_get_current_buf(), data = { client_id = 1 } })
        H.ok(vim.lsp.util.apply_workspace_edit == w, "not wrapped again")
        H.ok(debug.getinfo(orig_of(w), "S").source:find("xyno_guard/init.lua", 1, true) == nil)
      end)

'''),
    ...code('lua', r'tests/guard_spec.lua · lines 721-770', r'''
      it("18 a changes edit on another file schedules save_all", function()
        local path, buf = attach_fake("fake-1")
        local other = vim.uri_from_fname(vim.fs.dirname(path) .. "/other.txt")
        vim.lsp.util.apply_workspace_edit({ changes = { [other] = {} } }, "utf-16")
        H.eq(0, dg._calls(), "scheduled, not synchronous")
        H.wait_for(function()
          return dg._calls() == 1
        end, 2000, "save_all")
        H.ok(buf)
      end)

      it("18 a documentChanges edit on another file, and create/rename/delete kinds, schedule save_all", function()
        local path = attach_fake("fake-1")
        local dir = vim.fs.dirname(path)
        local other = vim.uri_from_fname(dir .. "/other.txt")
        vim.lsp.util.apply_workspace_edit({
          documentChanges = { { textDocument = { uri = other, version = vim.NIL }, edits = {} } },
        }, "utf-16")
        H.wait_for(function()
          return dg._calls() == 1
        end, 2000, "save_all after documentChanges")
        local created = dir .. "/new.txt"
        vim.lsp.util.apply_workspace_edit({ documentChanges = { { kind = "create", uri = vim.uri_from_fname(created) } } }, "utf-16")
        H.wait_for(function()
          return dg._calls() == 2
        end, 2000, "save_all after create")
        H.ok(vim.uv.fs_stat(created), "the create was applied")
        local renamed = dir .. "/renamed.txt"
        vim.lsp.util.apply_workspace_edit({
          documentChanges = { { kind = "rename", oldUri = vim.uri_from_fname(created), newUri = vim.uri_from_fname(renamed) } },
        }, "utf-16")
        H.wait_for(function()
          return dg._calls() == 3
        end, 2000, "save_all after rename")
        vim.lsp.util.apply_workspace_edit({ documentChanges = { { kind = "delete", uri = vim.uri_from_fname(renamed) } } }, "utf-16")
        H.wait_for(function()
          return dg._calls() == 4
        end, 2000, "save_all after delete")
      end)

      it("18 an edit confined to the current buffer does not schedule save_all", function()
        local _, buf = attach_fake("fake-1")
        local cur = vim.uri_from_bufnr(buf)
        vim.lsp.util.apply_workspace_edit({ changes = { [cur] = {} } }, "utf-16")
        vim.lsp.util.apply_workspace_edit({
          documentChanges = { { textDocument = { uri = cur, version = vim.NIL }, edits = {} } },
        }, "utf-16")
        vim.wait(300)
        H.eq(0, dg._calls())
      end)
'''),
    ...para('--', r'The describe group for the LSP wrapper checks four things. The wrapper is installed once '
        r'however many clients attach. An edit under changes keyed on another file schedules '
        r'save_all. Edits under documentChanges to another file, and the create, rename and delete '
        r'kinds, do too. And an edit confined to the current buffer does not; the original’s return '
        r'value is preserved. The spec calls vim.lsp.util.apply_workspace_edit directly with small '
        r'hand-made edit tables, so no language server is needed for this group.'),
    ...sec(r'buffers that existed before setup'),
    ...code('lua', r'tests/guard_spec.lua · lines 786-797', r'''
    it("20 buffers loaded before setup() are recorded by setup()", function()
      local path, buf = open_file()
      vim.b[buf].xyno_guard_stamp = nil
      dg.setup()
      H.eq(stamp_of(path), vim.b[buf].xyno_guard_stamp)
      -- and the events still work afterwards
      external_write(path, "z\n")
      vim.cmd("silent write!")
      H.eq(stamp_of(path), vim.b[buf].xyno_guard_stamp)
    end)
  end)
end)
'''),
    ...para('--', r'The last test removes the stamp by hand, calls setup again, and expects the stamp to be '
        r'recorded; then it checks that the events still work afterwards by writing from outside '
        r'and writing with write! and expecting the stamp to follow the file. That covers the loop '
        r'at the end of setup and the claim in the README that setup can be called again safely.'),
    ...sec(r'what is not covered'),
    ...para('--', r'The Windows and macOS branch of the path normalization is not exercised on those systems '
        r'from this repository; the README says that the specs have not been run there and treats '
        r'both as unverified. The Rust-only dependency roots are tested only as far as the three '
        r'fixed ones and the two variables.'),
    ...sec(r'history'),
    ...pt('--', r'9c10c91', r'2026-10-22, Add the specs and a small headless runner.'),
    ...pt('--', r'9c3e9ec', r'2026-10-22: adds the test named 8 setup() locks a dependency buffer that was loaded '
        r'before it ran, which creates a buffer, deletes the xyno_guard augroup to simulate a guard '
        r'that was not loaded yet, opens a dependency file, then calls setup and expects '
        r'nomodifiable and readonly.'),
  ],
);
