import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-clipboard.nvim/lua/xyno_clipboard/init.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'init.lua — one g:clipboard provider that writes to two places'),
    cm('--', r'copy goes to the local Wayland clipboard and to the terminal; paste reads the local one'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'the whole plugin: setup(), status() and the :XynoClipboardStatus command'),
    kv(r'language', r'Lua (Neovim 0.12+, uses vim.ui.clipboard.osc52)'),
    kv(r'size', r'99 lines'),
    kv(r'entry point', r'require("xyno_clipboard").setup(opts)'),
    kv(r'history', r'added in faa38b4 (2026-10-22), extracted from lua/config/remote_clipboard.lua of xynovim'),
    ...sec(r'why this file exists'),
    ...para('--', r'A terminal editor has no clipboard of its own. When the session is local Neovim shells '
        r'out to a desktop tool, but when the session lives inside tmux, or is reached over SSH, '
        r'the text you yank can land in the wrong place: the machine that runs the editor rather '
        r'than the screen you sit at. This file is the answer the author wrote for their own setup. '
        r'It began as lua/config/remote_clipboard.lua in the xynovim config (added in eabb22a on '
        r'2026-09-02, in the commit that migrated xynovim to a LazyVim base) and was published on '
        r'its own as xyno-clipboard.nvim on 2026-10-22. The header comment states the contract in '
        r'six lines and everything below implements it.'),
    ...code('lua', r'lua/xyno_clipboard/init.lua · lines 1-6', r'''
-- Clipboard for sessions whose yanks may need to reach another machine:
-- every copy is emitted as OSC 52 (inside tmux this becomes a tmux buffer,
-- rebroadcast to every attached client, local or SSH). Paste prefers the
-- local Wayland clipboard when one is available, so content copied in other
-- apps remains pasteable; without a display, paste is an OSC 52 query that
-- tmux (or the terminal) answers.
'''),
    ...para('--', r'Read as a spec, that comment makes three promises. Every copy is emitted as OSC 52, an '
        r'escape sequence that rides in the terminal output stream. Inside tmux the sequence becomes a tmux buffer that is '
        r'rebroadcast to every attached client. And paste is deliberately asymmetric: with a '
        r'Wayland display it reads the local clipboard, so what you copied in a browser is still '
        r'pasteable, and without one it falls back to an OSC 52 query.'),
    ...sec(r'module state and the options table'),
    ...code('lua', r'lua/xyno_clipboard/init.lua · lines 7-26', r'''
local M = {}

local state = { active = false, reason = nil, skipped = nil }

local defaults = {
  commands = true, -- register :XynoClipboardStatus
  osc52 = true, -- emit OSC 52 on copy (also switchable at runtime with vim.g.xyno_clipboard_osc52 = false)
}

local function status_lines()
  if state.active then
    return { "xyno-clipboard: active (" .. state.reason .. "), vim.g.clipboard = " .. vim.g.clipboard.name }
  end
  return { "xyno-clipboard: inactive (" .. (state.skipped or "setup() has not run") .. ")" }
end

--- The current state: { active = bool, reason = string|nil, skipped = string|nil }.
function M.status()
  return vim.deepcopy(state)
end
'''),
    ...para('--', r'Three small decisions are visible here. The module keeps one private table, state, with '
        r'three fields: whether the provider is active, the reason it was installed, and the reason '
        r'it was skipped. Nothing outside can mutate it, because status() hands back vim.deepcopy '
        r'of it. The options are tiny on purpose: commands decides whether the user command exists '
        r'and osc52 whether copy emits the escape sequence. And status_lines() branches on the state: when the plugin is active it reads vim.g.clipboard.name, and when it '
        r'is not it prints either the stored skip reason or the literal text setup() has not run, '
        r'which is what state.skipped holds before the first call.'),
    ...code('lua', r'lua/xyno_clipboard/init.lua · lines 24-26', r'''
function M.status()
  return vim.deepcopy(state)
end
'''),
    ...para('--', r'status() returns a copy and not the table itself, which is a defensive choice: the spec '
        r'asserts the exact shape with H.eq on the returned value, and a caller that edited the '
        r'result would not corrupt the plugin.'),
    ...sec(r'setup(): reset, command, platform gate, detection'),
    ...code('lua', r'lua/xyno_clipboard/init.lua · lines 28-50', r'''
function M.setup(opts)
  opts = vim.tbl_deep_extend("force", defaults, opts or {})
  state = { active = false }

  if opts.commands then
    vim.api.nvim_create_user_command("XynoClipboardStatus", function()
      vim.notify(table.concat(status_lines(), "\n"))
    end, { desc = "Show whether xyno-clipboard installed its provider" })
  end

  -- Linux only: the herdr detection walks /proc, and OSC 52 paste would replace
  -- the native providers (win32yank, pbcopy) with a query many terminals never answer.
  if vim.fn.has("linux") ~= 1 then
    state.skipped = "not Linux"
    return
  end

  local reason = require("xyno_clipboard.detect").reason()
  if not reason then
    state.skipped = "no tmux, ssh or herdr session detected"
    return
  end

'''),
    ...para('--', r'The order in setup() is chosen so that the diagnostic command exists even when the '
        r'provider does not get installed. The state is reset first, so calling setup() twice '
        r'cannot leave a stale active flag behind. The user command is registered before the '
        r'platform gate, which is why :XynoClipboardStatus can explain a skip on macOS or in a '
        r'plain terminal instead of simply not existing. The spec registers the command with '
        r'commands = false and checks that vim.fn.exists returns 0, then calls setup again and '
        r'expects 2, which is Vim’s answer for a complete user command.'),
    ...pt('--', r'Linux gate', r'the comment gives two reasons in the code itself: the herdr detection walks /proc, and '
        r'OSC 52 paste would replace native providers such as win32yank or pbcopy with a query many '
        r'terminals never answer. In xynovim this early return was added later, in ff1c8fa '
        r'(2026-10-16, the Windows and macOS portability commit), so the guard was made explicit '
        r'when the config started to run on other systems.'),
    ...pt('--', r'Fail closed on detection', r'if detect.reason() returns nil nothing is installed and state.skipped records why, so '
        r'default provider detection stays untouched. A plain terminal session pays for four '
        r'environment-variable reads and then the bounded /proc walk.'),
    ...pt('--', r'The reason is kept', r'reason is the name of the variable (or herdr ancestor) that decided, and it is reported '
        r'by :XynoClipboardStatus. A provider that silently chooses itself is hard to debug; this '
        r'one tells you which signal fired.'),
    ...sec(r'deciding whether Wayland is usable'),
    ...code('lua', r'lua/xyno_clipboard/init.lua · lines 52-54', r'''
  local has_wayland = vim.env.WAYLAND_DISPLAY ~= nil
    and vim.fn.executable("wl-copy") == 1
    and vim.fn.executable("wl-paste") == 1
'''),
    ...para('--', r'has_wayland is computed once, at setup time, and requires all three conditions: a '
        r'WAYLAND_DISPLAY in the environment, wl-copy executable, and wl-paste executable. '
        r'Requiring both tools matters, because the spec has a case where WAYLAND_DISPLAY is set '
        r'but the tools are missing from PATH, and expects the OSC 52 paste function instead of a '
        r'half-working wl-paste one. The consequence of computing it once is that a session that '
        r'exports WAYLAND_DISPLAY later does not change behaviour until setup() runs again. The '
        r'code does not hide this; it is a trade of flexibility for a provider that does no '
        r'environment probing on the copy path.'),
    ...sec(r'the copy side'),
    ...code('lua', r'lua/xyno_clipboard/init.lua · lines 56-72', r'''
  local function copy(register)
    local emit = osc52.copy(register)

    return function(lines)
      if has_wayland then
        local cmd = { "wl-copy", "--sensitive", "--type", "text/plain" }
        if register == "*" then
          cmd[#cmd + 1] = "--primary"
        end
        vim.fn.system(cmd, lines)
      end

      if opts.osc52 and vim.g.xyno_clipboard_osc52 ~= false then
        emit(lines)
      end
    end
  end
'''),
    ...para('--', r'copy(register) is a factory: it asks the stdlib osc52 module for its emitter for that '
        r'register once, then returns the function Neovim will call with the lines being yanked. '
        r'The local copy happens first and the escape sequence second, so a failure or delay in the '
        r'terminal path cannot prevent the local clipboard from being filled.'),
    ...pt('--', r'--sensitive', r'passed to wl-copy so that clipboard managers are asked not to record the content. The '
        r'spec checks the exact argument list.'),
    ...pt('--', r'--type text/plain', r'pins the MIME type, so that wl-copy does not guess from the content.'),
    ...pt('--', r'--primary for the star register', r'the star register is the primary selection on Wayland; the plus register is the regular '
        r'clipboard. The spec expects the arguments --sensitive, --type, text/plain for plus and '
        r'the same with --primary appended for star.'),
    ...pt('--', r'the OSC 52 gate', r'two switches, both consulted on every copy: the opts.osc52 value captured by the closure '
        r'at setup, and vim.g.xyno_clipboard_osc52 read live. That is why the README can promise '
        r'that setting the global to false stops the emit at runtime without reinstalling anything, '
        r'and why the spec flips the variable between two copies and observes the emit stop and '
        r'resume.'),
    ...para('--', r'Notice what is not here: no pcall around vim.fn.system and no check of its exit status. A '
        r'missing wl-copy cannot happen because has_wayland required it to be executable; a wl-copy '
        r'that fails at run time is ignored and the OSC 52 emit still runs. That is a reasonable '
        r'failure mode for a clipboard (the escape sequence is the path that reaches other '
        r'machines) but the file does not say it is deliberate, and nothing reports the failure.'),
    ...sec(r'the paste side'),
    ...code('lua', r'lua/xyno_clipboard/init.lua · lines 74-88', r'''
  local function paste(register)
    if not has_wayland then
      return osc52.paste(register)
    end

    return function()
      local cmd = { "wl-paste", "--no-newline" }
      if register == "*" then
        cmd[#cmd + 1] = "--primary"
      end

      local lines = vim.fn.systemlist(cmd, "", 1)
      return vim.v.shell_error == 0 and lines or {}
    end
  end
'''),
    ...para('--', r'Paste is where the asymmetry lives. Without Wayland, osc52.paste(register) is returned as '
        r'it is, so the provider falls back to the terminal query that tmux or the terminal has to '
        r'answer, and the spec checks that it is literally the same function with rawequal. With '
        r'Wayland the function runs wl-paste --no-newline (adding --primary for the star register) '
        r'and returns its lines.'),
    ...para('--', r'The detail that makes this robust is the call vim.fn.systemlist(cmd, "", 1). The third '
        r'argument asks for keepempty, so blank lines in the clipboard are preserved rather than '
        r'collapsed. And the final line returns the lines only when vim.v.shell_error is 0, '
        r'otherwise an empty table. The spec forces a non-zero exit through an environment variable '
        r'read by its fake wl-paste and expects an empty table for both registers. An empty result '
        r'is the right neutral answer: Neovim pastes nothing instead of raising an error in the '
        r'middle of a put.'),
    ...para('--', r'The reason for reading from the local clipboard at all, instead of always asking the '
        r'terminal, is stated in the file header: content copied in other apps must remain '
        r'pasteable. The comment on the Linux guard says that an OSC 52 paste is a query many '
        r'terminals never answer, which fits the query being only the fallback.'),
    ...sec(r'installing the provider'),
    ...code('lua', r'lua/xyno_clipboard/init.lua · lines 90-97', r'''
  vim.g.clipboard = {
    name = "XynoClipboard",
    copy = { ["+"] = copy("+"), ["*"] = copy("*") },
    paste = { ["+"] = paste("+"), ["*"] = paste("*") },
    cache_enabled = 0,
  }
  state.active, state.reason = true, reason
end
'''),
    ...para('--', r'vim.g.clipboard is Neovim’s documented hook for a custom provider, with a name, copy and '
        r'paste tables keyed by register, and cache_enabled. Setting cache_enabled to 0 is the '
        r'important part: it turns off the plugin-side cache of the register, so every paste calls '
        r'the paste function and sees what is in the clipboard now, instead of what this Neovim '
        r'last copied. Without it a copy made in another application would be invisible. The name '
        r'XynoClipboard is what status_lines() prints and what the spec asserts. The two flags in '
        r'state are set last, in one assignment, so state never claims active before '
        r'vim.g.clipboard exists.'),
    ...sec(r'design decisions in one place'),
    ...pt('--', r'Zero dependencies', r'the file requires only Neovim built-ins and its sibling detect.lua. The README says so, '
        r'and CI installs nothing but Neovim.'),
    ...pt('--', r'Closures over the environment', r'the Wayland probe and options are captured at setup(); the only live read is the runtime switch.'),
    ...pt('--', r'Opt out of everything by default', r'no keymaps, no autocmds. The plugin integrates through the ordinary plus and star registers.'),
    ...pt('--', r'Honest status', r'status() and the command report the exact reason for being on or off.'),
    ...sec(r'how it is tested'),
    ...para('--', r'The behaviour above is pinned by tests/specs/clipboard_spec.lua: detection for each '
        r'variable, the herdr ancestor walk, both Wayland and non-Wayland paths, the runtime '
        r'switch, the options and the status output. The Wayland tools are replaced by shell stubs '
        r'written into a temp dir that is put first on PATH, and the stubs record their arguments, '
        r'which is how the exact flags are asserted. The OSC 52 module is replaced through '
        r'package.loaded with a recorder. See that page for the details.'),
    ...sec(r'history'),
    ...pt('--', r'faa38b4', r'2026-10-22, Add the clipboard provider module: this file and detect.lua, with the changes '
        r'from the xynovim version listed in the README (the provider name, the runtime switch '
        r'variable, and setup(opts), status() and the command as new surface).'),
    ...pt('--', r'origin', r'eabb22a (2026-09-02) added the original in xynovim; f35b4f6 (2026-09-03) reordered the '
        r'gate cheapest-first; e874f9f (2026-10-13) renamed the switch and provider when Omarchy '
        r'support was removed; ff1c8fa (2026-10-16) added the Linux-only guard.'),
  ],
);
