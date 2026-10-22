import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-clipboard.nvim/tests/specs/clipboard_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'clipboard_spec.lua — a clipboard plugin tested without a clipboard'),
    cm('--', r'fake /proc, fake wl-copy, fake OSC 52: every external is replaced'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'the only spec file: 11 tests in 2 describe groups'),
    kv(r'language', r'Lua, on the repo’s own describe/it harness'),
    kv(r'size', r'319 lines'),
    kv(r'run with', r'nvim -l tests/run.lua'),
    kv(r'history', r'added in 46a5b14 (2026-10-22, Add specs and CI)'),
    ...sec(r'why this file exists'),
    ...para('--', r'A clipboard provider is hard to test honestly. Its inputs are the process tree, the '
        r'environment and two external programs, and its outputs are escape sequences written to a '
        r'terminal and bytes written into a Wayland compositor. A test that needed a real tmux, a '
        r'real SSH login or a real compositor could not run in CI, and one that ran against the '
        r'developer’s own session would depend on it. This spec solves it by replacing each '
        r'external with a small recorder, so that what is asserted is what the plugin asked the '
        r'outside world to do. The first line of the file already shows the cost of that choice.'),
    ...code('lua', r'tests/specs/clipboard_spec.lua · lines 1-3', r'''
-- xyno-os: linux (reads /proc, uses sh stubs for wl-copy, wl-paste)
-- Specs for the provider: detection, Wayland and OSC 52 paths, the ancestor walk.
local H = require("xynotest.helpers")
'''),
    ...para('--', r'The header comment is not decoration. tests/run.lua reads the first 15 lines of every '
        r'spec looking for a line of the form xyno-os, and skips the whole file on a platform that '
        r'is not listed. This spec depends on /proc and on sh stubs, so it declares linux and says '
        r'why in parentheses.'),
    ...sec(r'fake process trees'),
    ...code('lua', r'tests/specs/clipboard_spec.lua · lines 11-48', r'''
describe("xyno_clipboard", function()
  local ENV = { "TMUX", "SSH_TTY", "SSH_CONNECTION", "HERDR_PANE_ID", "WAYLAND_DISPLAY", "PATH", "XYNO_FAKE_RC" }
  local saved
  local real_osc52

  -- fake ancestor chain: { [pid] = { ppid = n, comm = "x" } }
  local function with_fake_proc(chain, fn)
    local real_readfile, real_getpid = vim.fn.readfile, vim.fn.getpid
    local reads = {}
    rawset(vim.fn, "getpid", function()
      return 1000
    end)
    rawset(vim.fn, "readfile", function(path, ...)
      local pid, file = tostring(path):match("^/proc/(%d+)/(%a+)$")
      if not pid then
        return real_readfile(path, ...)
      end
      reads[#reads + 1] = path
      local e = chain[tonumber(pid)]
      if not e then
        error("E484: Can't open file " .. path)
      end
      if file == "status" then
        if e.unreadable then
          error("E484: Can't open file " .. path)
        end
        return { "Name:\t" .. e.comm, "PPid:\t" .. e.ppid }
      end
      return { e.comm }
    end)
    local ok, err = pcall(fn, reads)
    rawset(vim.fn, "readfile", nil)
    rawset(vim.fn, "getpid", nil)
    if not ok then
      error(err, 0)
    end
  end

'''),
    ...para('--', r'with_fake_proc takes a table keyed by pid, each entry holding a parent pid and a name, '
        r'and for the duration of one function replaces vim.fn.getpid and vim.fn.readfile. It uses '
        r'rawset on the vim.fn table, which is the trick that makes the replacement stick for a '
        r'table that Neovim fills lazily; afterwards the same table is cleared with rawset(..., '
        r'nil) so the real functions come back. Reads that are not under /proc/PID/ pass through to '
        r'the real readfile, so loading anything else still works. Every /proc read is recorded in '
        r'a list handed to the test, which is how the cheapest-first order is proven: a test can '
        r'assert that the list is empty. A missing pid raises the same error text Vim would give, '
        r'and an entry marked unreadable raises only for the status file, which lets the test '
        r'separate a missing process from an unreadable one. The restore happens through pcall and '
        r'a re-raise, so a failing test cannot leave the fakes installed for the next one.'),
    ...sec(r'the setup helper and the saved environment'),
    ...code('lua', r'tests/specs/clipboard_spec.lua · lines 49-64', r'''
  --- Run setup() with the given env and return vim.g.clipboard.
  local function setup(env, opts)
    for _, k in ipairs({ "TMUX", "SSH_TTY", "SSH_CONNECTION", "HERDR_PANE_ID" }) do
      vim.env[k] = nil
    end
    for k, v in pairs(env or {}) do
      vim.env[k] = v
    end
    vim.g.clipboard = nil
    require("xyno_clipboard").setup(opts)
    return vim.g.clipboard
  end

  local plain_chain = { [1000] = { ppid = 500, comm = "nvim" }, [500] = { ppid = 400, comm = "bash" }, [400] = { ppid = 1, comm = "init" } }

  before_each(function()
'''),
    ...code('lua', r'tests/specs/clipboard_spec.lua · lines 69-82', r'''
    real_osc52 = package.loaded["vim.ui.clipboard.osc52"]
  end)

  after_each(function()
    rawset(vim.fn, "readfile", nil)
    rawset(vim.fn, "getpid", nil)
    for _, k in ipairs(ENV) do
      vim.env[k] = saved[k]
    end
    package.loaded["vim.ui.clipboard.osc52"] = real_osc52
    vim.g.xyno_clipboard_osc52 = saved.flag
    vim.g.clipboard = saved.g
  end)

'''),
    ...para('--', r'setup(env, opts) first clears the four detection variables so nothing leaks in from the '
        r'shell running the tests, then applies the case, resets vim.g.clipboard and runs the real '
        r'setup. It returns vim.g.clipboard, so that most assertions are about the value the '
        r'provider left behind. The before_each and after_each hooks save and restore the clipboard '
        r'global, the runtime switch, every environment variable the plugin looks at, and the osc52 '
        r'module that package.loaded holds. Restoring package.loaded matters because other tests '
        r'replace it.'),
    ...sec(r'the two recorders'),
    ...code('lua', r'tests/specs/clipboard_spec.lua · lines 83-116', r'''
  --- A recording replacement for vim.ui.clipboard.osc52.
  local function fake_osc52()
    local rec = { emitted = {}, paste = {} }
    package.loaded["vim.ui.clipboard.osc52"] = {
      copy = function(reg)
        return function(lines)
          rec.emitted[#rec.emitted + 1] = { reg = reg, lines = lines }
        end
      end,
      paste = function(reg)
        local f = function()
          return { "osc52 " .. reg }
        end
        rec.paste[reg] = f
        return f
      end,
    }
    return rec
  end

  --- A directory with fake wl-copy / wl-paste recording their calls.
  local function fake_wl()
    local dir = H.tmpdir()
    write(
      dir .. "/wl-copy",
      ("#!/bin/sh\nprintf '%%s\\n' \"$@\" > %s/copy.args\ncat > %s/copy.stdin\n"):format(dir, dir)
    )
    write(
      dir .. "/wl-paste",
      ("#!/bin/sh\nprintf '%%s\\n' \"$@\" > %s/paste.args\nprintf 'one\\ntwo'\nexit ${XYNO_FAKE_RC:-0}\n"):format(dir)
    )
    vim.fn.system({ "chmod", "+x", dir .. "/wl-copy", dir .. "/wl-paste" })
    return dir
  end
'''),
    ...para('--', r'fake_osc52 puts a table into package.loaded under the module name that init.lua requires. '
        r'Its copy function returns an emitter that appends the register and the lines to a list, '
        r'and its paste returns a closure that is remembered so a test can compare it with rawequal '
        r'later. fake_wl builds a temporary directory holding two shell scripts. The wl-copy stub '
        r'writes its argument vector to copy.args, one per line, and its standard input to '
        r'copy.stdin. The wl-paste stub records its arguments, prints two lines, and exits with the '
        r'code in XYNO_FAKE_RC. Putting that directory at the front of PATH is all that is needed, '
        r'because init.lua resolves the tools with vim.fn.executable and runs them by name.'),
    ...para('--', r'The argument recording is what turns a behaviour into an assertion: the real question for '
        r'the Wayland path is not whether text arrived somewhere but which flags the plugin passed.'),
    ...sec(r'detection tests'),
    ...code('lua', r'tests/specs/clipboard_spec.lua · lines 118-152', r'''
  it("does nothing outside tmux/ssh/herdr when no ancestor is herdr", function()
    with_fake_proc(plain_chain, function()
      H.is_nil(setup({}))
    end)
  end)

  it("detects an ancestor process whose comm contains 'herdr'", function()
    local chain = {
      [1000] = { ppid = 500, comm = "nvim" },
      [500] = { ppid = 400, comm = "herdr-server" },
      [400] = { ppid = 1, comm = "init" },
    }
    with_fake_proc(chain, function()
      local c = setup({})
      H.ok(c, "no clipboard provider although an ancestor is herdr")
      H.eq("XynoClipboard", c.name)
    end)
  end)

  it("installs the provider for each of TMUX, SSH_CONNECTION, SSH_TTY and HERDR_PANE_ID", function()
    for _, var in ipairs({ "TMUX", "SSH_CONNECTION", "SSH_TTY", "HERDR_PANE_ID" }) do
      with_fake_proc(plain_chain, function(reads)
        local c = setup({ [var] = "x" })
        H.ok(c, var .. ": no clipboard provider")
        H.eq("XynoClipboard", c.name, var)
        H.eq(0, c.cache_enabled, var)
        for _, reg in ipairs({ "+", "*" }) do
          H.eq("function", type(c.copy[reg]), var .. " copy " .. reg)
          H.eq("function", type(c.paste[reg]), var .. " paste " .. reg)
        end
        H.eq(0, #reads, var .. ": the /proc walk must be skipped when an env var decides")
      end)
    end
  end)

'''),
    ...para('--', r'Three tests cover detection. The first proves that a plain chain of nvim, bash and init '
        r'gives no provider. The second builds a chain whose middle process is called herdr-server '
        r'and expects the provider to exist, which proves the substring match. The third loops over '
        r'all four variables and asserts for each that the provider has the expected name, that '
        r'cache_enabled is zero, that both registers have both functions, and that no /proc file '
        r'was read. That last assertion is the executable form of the ordering comment in '
        r'detect.lua.'),
    ...sec(r'the non-Wayland and Wayland paths'),
    ...code('lua', r'tests/specs/clipboard_spec.lua · lines 153-204', r'''
  it("without a Wayland display or wl-copy/wl-paste: OSC52 copy only, paste is osc52.paste", function()
    local rec = fake_osc52()
    local wl = fake_wl()
    -- (a) no WAYLAND_DISPLAY although the tools exist
    vim.env.PATH = wl .. ":" .. saved.PATH
    vim.env.WAYLAND_DISPLAY = nil
    local c = setup({ TMUX = "x" })
    c.copy["+"]({ "hi", "there" })
    H.eq({ { reg = "+", lines = { "hi", "there" } } }, rec.emitted)
    H.eq(0, vim.fn.filereadable(wl .. "/copy.args"), "wl-copy must not run without WAYLAND_DISPLAY")
    H.ok(rawequal(rec.paste["+"], c.paste["+"]), "paste + is not osc52.paste")
    H.ok(rawequal(rec.paste["*"], c.paste["*"]), "paste * is not osc52.paste")
    -- (b) WAYLAND_DISPLAY but no wl-copy/wl-paste on PATH
    rec.emitted = {}
    vim.env.WAYLAND_DISPLAY = "wayland-fake"
    vim.env.PATH = H.tmpdir()
    c = setup({ TMUX = "x" })
    c.copy["*"]({ "x" })
    H.eq({ { reg = "*", lines = { "x" } } }, rec.emitted)
    H.ok(rawequal(rec.paste["*"], c.paste["*"]), "paste * is not osc52.paste without wl-paste")
  end)

  it("with Wayland: copy runs wl-copy --sensitive --type text/plain (--primary for *) and emits OSC52", function()
    local rec = fake_osc52()
    local wl = fake_wl()
    vim.env.PATH = wl .. ":" .. saved.PATH
    vim.env.WAYLAND_DISPLAY = "wayland-fake"
    local c = setup({ TMUX = "x" })
    c.copy["+"]({ "a", "b" })
    H.eq({ "--sensitive", "--type", "text/plain" }, vim.fn.readfile(wl .. "/copy.args"))
    H.eq({ "a", "b" }, vim.fn.readfile(wl .. "/copy.stdin"))
    c.copy["*"]({ "c" })
    H.eq({ "--sensitive", "--type", "text/plain", "--primary" }, vim.fn.readfile(wl .. "/copy.args"))
    H.eq(2, #rec.emitted)
    H.eq("*", rec.emitted[2].reg)
  end)

  it("with Wayland: paste runs wl-paste --no-newline (--primary for *), {} on a non-zero exit", function()
    fake_osc52()
    local wl = fake_wl()
    vim.env.PATH = wl .. ":" .. saved.PATH
    vim.env.WAYLAND_DISPLAY = "wayland-fake"
    local c = setup({ TMUX = "x" })
    H.eq({ "one", "two" }, c.paste["+"]())
    H.eq({ "--no-newline" }, vim.fn.readfile(wl .. "/paste.args"))
    H.eq({ "one", "two" }, c.paste["*"]())
    H.eq({ "--no-newline", "--primary" }, vim.fn.readfile(wl .. "/paste.args"))
    vim.env.XYNO_FAKE_RC = "1"
    H.eq({}, c.paste["+"]())
    H.eq({}, c.paste["*"]())
  end)

'''),
    ...para('--', r'The first of these tests has two halves for two different ways of lacking Wayland: the '
        r'tools are present but WAYLAND_DISPLAY is unset, and the display is set but the tools are '
        r'not on PATH. In both, a copy produces exactly one OSC 52 emit, no wl-copy file appears, '
        r'and the paste functions are the very ones osc52.paste returned. The Wayland tests then '
        r'pin the flags. The copy test expects --sensitive --type text/plain for the plus register '
        r'and the same plus --primary for the star register, with the lines on standard input. The '
        r'paste test expects --no-newline, with --primary for star, and a pair of lines back; when '
        r'the stub exits 1 both registers must return an empty table.'),
    ...sec(r'the runtime switch'),
    ...code('lua', r'tests/specs/clipboard_spec.lua · lines 205-218', r'''
  it("vim.g.xyno_clipboard_osc52 = false suppresses the OSC52 emit", function()
    local rec = fake_osc52()
    local wl = fake_wl()
    vim.env.PATH = wl .. ":" .. saved.PATH
    vim.env.WAYLAND_DISPLAY = "wayland-fake"
    local c = setup({ TMUX = "x" })
    vim.g.xyno_clipboard_osc52 = false
    c.copy["+"]({ "quiet" })
    H.eq({}, rec.emitted)
    H.eq({ "quiet" }, vim.fn.readfile(wl .. "/copy.stdin"), "the local copy still happens")
    vim.g.xyno_clipboard_osc52 = nil
    c.copy["+"]({ "loud" })
    H.eq(1, #rec.emitted, "unsetting the variable emits again")
  end)
'''),
    ...para('--', r'A single provider instance sees the variable change under it. The test sets '
        r'vim.g.xyno_clipboard_osc52 to false, copies, and asserts that the recorder is empty but '
        r'wl-copy still received the text, then sets it back to nil and asserts the next copy '
        r'emits. Setting nil and not true is deliberate: only the value false disables, so an unset '
        r'variable means on.'),
    ...sec(r'the ancestor walk limits'),
    ...code('lua', r'tests/specs/clipboard_spec.lua · lines 220-257', r'''
  it("the ancestor walk stops at ppid <= 1, is bounded to 16 steps and survives unreadable /proc entries", function()
    -- stops at ppid <= 1: a herdr 'above' init is never looked at
    local chain = {
      [1000] = { ppid = 500, comm = "nvim" },
      [500] = { ppid = 1, comm = "bash" },
      [1] = { ppid = 0, comm = "herdr" },
    }
    with_fake_proc(chain, function(reads)
      H.is_nil(setup({}))
      for _, r in ipairs(reads) do
        H.no_match(r, "/proc/1/", true)
      end
    end)
    -- unreadable status of the first parent: no error, no provider
    with_fake_proc({ [1000] = { ppid = 500, comm = "nvim", unreadable = true } }, function()
      H.is_nil(setup({}))
    end)
    -- a missing /proc entry deeper in the chain
    with_fake_proc({ [1000] = { ppid = 500, comm = "nvim" }, [500] = { ppid = 400, comm = "x" } }, function()
      H.is_nil(setup({}))
    end)
    -- a cycle that never reaches init: at most 16 status reads, herdr at step 17 is not seen
    local cyc = { [1000] = { ppid = 2000, comm = "nvim" } }
    for i = 0, 20 do
      cyc[2000 + i] = { ppid = 2000 + i + 1, comm = i == 17 and "herdr" or "sh" }
    end
    with_fake_proc(cyc, function(reads)
      H.is_nil(setup({}))
      local status = 0
      for _, r in ipairs(reads) do
        if r:match("/status$") then
          status = status + 1
        end
      end
      H.ok(status <= 16, "status reads: " .. status)
    end)
  end)
end)
'''),
    ...para('--', r'This is the longest test and it is the safety net of detect.lua. A herdr above pid 1 must '
        r'not be found and no read may touch /proc/1/. A first parent whose status file cannot be '
        r'read must give nil without an error. A chain with a missing deeper entry must not error '
        r'either. And a cycle of 21 processes where herdr sits at index 17 must produce nil, with '
        r'at most 16 status reads counted by matching the path suffix. The cycle is not a true '
        r'loop; it is a long chain that never reaches init, which is enough to prove the bound.'),
    ...sec(r'options, status and the command'),
    ...code('lua', r'tests/specs/clipboard_spec.lua · lines 259-319', r'''
describe("xyno_clipboard opts, status and command", function()
  local saved_g, saved_tmux
  before_each(function()
    saved_g, saved_tmux = vim.g.clipboard, vim.env.TMUX
    pcall(vim.api.nvim_del_user_command, "XynoClipboardStatus")
  end)
  after_each(function()
    vim.g.clipboard = saved_g
    vim.env.TMUX = saved_tmux
    pcall(vim.api.nvim_del_user_command, "XynoClipboardStatus")
  end)

  it("opts.osc52 = false never emits OSC 52", function()
    local real = package.loaded["vim.ui.clipboard.osc52"]
    local emitted = 0
    package.loaded["vim.ui.clipboard.osc52"] = {
      copy = function()
        return function()
          emitted = emitted + 1
        end
      end,
      paste = function()
        return function() end
      end,
    }
    vim.env.TMUX = "x"
    vim.g.clipboard = nil
    require("xyno_clipboard").setup({ osc52 = false })
    vim.g.clipboard.copy["+"]({ "x" })
    package.loaded["vim.ui.clipboard.osc52"] = real
    H.eq(0, emitted)
  end)

  it("registers :XynoClipboardStatus by default, not with commands = false", function()
    vim.env.TMUX = "x"
    require("xyno_clipboard").setup({ commands = false })
    H.eq(0, vim.fn.exists(":XynoClipboardStatus"))
    require("xyno_clipboard").setup()
    H.eq(2, vim.fn.exists(":XynoClipboardStatus"))
  end)

  it("status() reports the reason when active and the cause when inactive", function()
    local C = require("xyno_clipboard")
    for _, k in ipairs({ "SSH_TTY", "SSH_CONNECTION", "HERDR_PANE_ID" }) do
      vim.env[k] = nil
    end
    vim.env.TMUX = "x"
    C.setup()
    H.eq({ active = true, reason = "TMUX" }, C.status())
    local msg
    local real = vim.notify
    vim.notify = function(m)
      msg = m
    end
    vim.cmd("XynoClipboardStatus")
    vim.notify = real
    H.match(msg, "active (TMUX)", true)
    H.match(msg, "XynoClipboard", true)
  end)
end)

'''),
    ...para('--', r'The second describe block moves from detection to the surface. With osc52 = false in the '
        r'options, even a provider with a fake emitter never emits. The command exists by default '
        r'and does not with commands = false, checked through vim.fn.exists. And status() returns '
        r'exactly the table with active and reason, while the notification text produced by the '
        r'command contains both the reason and the provider name; vim.notify is swapped for a '
        r'capture function and restored afterwards.'),
    ...sec(r'what the spec does not cover'),
    ...para('--', r'Nothing here runs an actual terminal, so whether OSC 52 sequences reach tmux, or whether '
        r'a query is answered, is outside the tests; the fake replaces the standard module, so a '
        r'change inside Neovim’s own osc52 module would not be noticed. The README and help file '
        r'say the same about other platforms: nothing is tested on Windows or macOS because the '
        r'plugin returns early there.'),
    ...sec(r'history'),
    ...pt('--', r'46a5b14', r'2026-10-22, Add specs and CI: the spec, the harness, the helpers, the runner and the '
        r'workflow arrive together.'),
    ...pt('--', r'b162212', r'2026-10-22, the runner’s summary line gets a RESULT prefix. That change touches only tests/run.lua.'),
  ],
);
