import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/remote_clipboard.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'remote_clipboard.lua — yank here, paste there'),
    cm('--', 'one clipboard provider that writes to two places'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'custom g:clipboard for tmux, SSH and herdr sessions'),
    kv('language', 'Lua'),
    kv('size', '103 lines'),
    kv('entry point', 'require("config.remote_clipboard").setup()'),
    kv('history', 'added in eabb22a; gate reordered in f35b4f6'),

    ...sec('the problem'),
    ...para('--',
        'A terminal editor has no clipboard of its own. When the '
        'session is local, Neovim shells out to the desktop '
        'clipboard. When the session lives inside tmux, or is '
        'reached over SSH, the text you yank can end up in the '
        'wrong clipboard: the one on the remote machine, or only '
        'on the machine that runs the editor, not the screen you '
        'are sitting at. The header of this file states the '
        'goal in four sentences:'),
    ...code('lua', 'lua/config/remote_clipboard.lua · intent', r'''
-- Clipboard for sessions whose yanks may need to reach another machine:
-- every copy is emitted as OSC 52 (inside tmux this becomes a tmux buffer,
-- rebroadcast to every attached client, local or SSH). Paste prefers the
-- local Wayland clipboard when one is available, so content copied in other
-- apps remains pasteable; without a display, paste is an OSC 52 query that
-- tmux (or the terminal) answers.'''),
    ...para('--',
        'OSC 52 is a terminal escape sequence that asks the '
        'terminal emulator to write base64 text into the system '
        'clipboard. It travels through any pipe that carries '
        'terminal output, which is exactly why it survives SSH and '
        'tmux: the clipboard write is just bytes in the stream.'),

    ...sec('why Neovim’s own detection is not enough'),
    ...para('--',
        'Neovim ships clipboard providers and picks one by '
        'checking tools in a fixed order. In the runtime at '
        'v0.12.5 that order is, abbreviated: macOS pbcopy, then '
        'wl-copy when WAYLAND_DISPLAY is set, then xsel and xclip '
        'when DISPLAY is set, several others, then tmux when TMUX '
        'is set, and only then OSC 52, and OSC 52 is used just '
        'when the terminal reports support and the clipboard '
        'option is empty. The documentation adds that a terminal '
        'multiplexer can inhibit the automatic detection.'),
    ...para('--',
        'Two consequences make a custom provider worthwhile for '
        'the sessions this module targets. The chain selects '
        'exactly one provider, so on a machine with a Wayland '
        'display a tmux session would copy to the local clipboard '
        'only and an attached SSH client would see nothing. And '
        'LazyVim sets the clipboard option to unnamedplus unless '
        'SSH_CONNECTION is set (its source comment says this is to '
        'keep OSC 52 working over SSH), so OSC 52 is not the '
        'automatic choice in a local tmux session either. The '
        'module resolves both by declaring the provider itself.'),

    ...sec('the design in two rules'),
    ...pt('--', 'copy goes to every place that might need it',
        'when a Wayland display is available the text is written '
        'to the local clipboard with wl-copy, and in addition an '
        'OSC 52 sequence is always emitted so that tmux, and the '
        'terminals attached to it, receive the same text.'),
    ...pt('--', 'paste prefers the nearest source',
        'with a Wayland display, paste reads the local clipboard '
        'with wl-paste, so anything copied in another '
        'application can still be pasted into the editor. With no '
        'display it falls back to an OSC 52 query.'),
    ...para('--',
        'Symmetry is not the goal. A copy is a broadcast and a '
        'paste is a single read, and each side takes the choice '
        'that loses the least.'),

    ...sec('finding herdr: a walk up /proc'),
    ...code('lua', 'lua/config/remote_clipboard.lua · /proc helpers', r'''
local function proc_lines(pid, file)
  local ok, lines = pcall(vim.fn.readfile, "/proc/" .. pid .. "/" .. file)
  return ok and lines or {}
end

local function proc_ppid(pid)
  for _, line in ipairs(proc_lines(pid, "status")) do
    local ppid = line:match("^PPid:%s+(%d+)")
    if ppid then
      return tonumber(ppid)
    end
  end
end'''),
    ...para('--',
        'Three decisions in a few lines. readfile runs under pcall, '
        'because a process can exit between the moment its id is '
        'learned and the moment its file is read, and an error '
        'here would abort startup. A failed read returns an empty '
        'list, so every caller can iterate it without a nil check. '
        'And the parent id comes from the PPid line of '
        '/proc/PID/status, which is plain text on Linux and needs '
        'no external command.'),
    ...code('lua', 'lua/config/remote_clipboard.lua · ancestor walk', r'''
local function ancestor_process_named(name)
  local pid = vim.fn.getpid()

  for _ = 1, 16 do
    local ppid = proc_ppid(pid)
    if not ppid or ppid <= 1 then
      return false
    end

    local comm = proc_lines(ppid, "comm")[1] or ""
    if comm:find(name, 1, true) then
      return true
    end

    pid = ppid
  end

  return false
end'''),
    ...para('--',
        'The loop starts from Neovim’s own pid and climbs at most '
        '16 generations. It stops early when the chain ends '
        '(no parent, or the parent is init) and compares each '
        'ancestor’s comm file with the name. The find call passes '
        'a start position of 1 and the plain flag, so the name is '
        'matched as a substring and not as a Lua pattern. The '
        'cap guards against an unexpected loop. Each iteration '
        'reads two files (status for the next parent, comm for '
        'the name), so the worst case is 32 small reads, although '
        'the comment further down counts the 16 iterations.'),
    ...para('--',
        'Why detect by ancestry at all, when the gate below also '
        'tests the HERDR_PANE_ID variable? The code implies that '
        'the variable is not always inherited. The repository does '
        'not say why, nor what herdr is beyond the fact that the '
        'README groups it with tmux and SSH as an environment '
        'where yanks must reach another machine.'),

    ...sec('deciding whether to activate'),
    ...code('lua', 'lua/config/remote_clipboard.lua · gate', r'''
function M.setup()
  -- Ordered cheapest-first so the /proc ancestor walk (16 process-file
  -- reads) only runs when no env var has already decided the answer.
  local relevant = vim.env.TMUX ~= nil
    or vim.env.SSH_TTY ~= nil
    or vim.env.SSH_CONNECTION ~= nil
    or vim.env.HERDR_PANE_ID ~= nil
    or ancestor_process_named("herdr")

  if not relevant then
    return
  end'''),
    ...para('--',
        'Lua’s or stops evaluating at the first true operand, so '
        'writing the cheap tests first is a performance decision '
        'that costs nothing to read. This is the version from '
        'f35b4f6 (2026-09-03), and the diff shows what it '
        'replaced. The earlier code computed three named booleans '
        'first, among them the line that always evaluated the '
        'walk whenever HERDR_PANE_ID was unset:'),
    plain('  -- eabb22a, replaced in f35b4f6'),
    plain('  local in_tmux = vim.env.TMUX ~= nil'),
    plain('  local in_ssh = vim.env.SSH_TTY ~= nil'),
    plain('        or vim.env.SSH_CONNECTION ~= nil'),
    plain('  local in_herdr = vim.env.HERDR_PANE_ID ~= nil'),
    plain('        or ancestor_process_named("herdr")'),
    plain('  if not (in_tmux or in_ssh or in_herdr) then return end'),
    blank,
    ...para('--',
        'So in the old version a tmux or SSH session still paid '
        'for the walk, and the new one skips it. The gain is '
        'narrower than it first reads. In a plain '
        'local terminal no variable is set, every cheap test '
        'fails, and the walk runs in both versions, up to its cap, '
        'before the function returns without registering '
        'anything. Only sessions that already carry TMUX or SSH '
        'variables, or HERDR_PANE_ID, skip it. The changelog '
        'puts the whole commit at 28.7 ms to about 18 ms and does '
        'not isolate this change.'),
    ...para('--',
        'The early return is itself a design statement: when none '
        'of the markers is present, vim.g.clipboard is never '
        'assigned and Neovim’s ordinary detection decides, so a '
        'plain Wayland desktop session behaves exactly as if the '
        'module did not exist.'),

    ...sec('the copy path'),
    ...code('lua', 'lua/config/remote_clipboard.lua · copy', r'''
  local osc52 = require("vim.ui.clipboard.osc52")
  local has_wayland = vim.env.WAYLAND_DISPLAY ~= nil
    and vim.fn.executable("wl-copy") == 1
    and vim.fn.executable("wl-paste") == 1

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

      if vim.g.omarchy_remote_clipboard_osc52 ~= false then
        emit(lines)
      end
    end
  end'''),
    ...pt('--', 'it reuses Neovim’s emitter',
        'osc52.copy(register) is the same function the built-in '
        'provider uses. It joins the lines with newlines, '
        'base64-encodes them and writes the escape sequence to '
        'the UI, with c as the target for the plus register and p '
        'for the star register. No escape-sequence code is '
        'duplicated here.'),
    ...pt('--', 'the Wayland branch mirrors the built-in call',
        'Neovim’s own wl-copy provider runs wl-copy with type '
        'text/plain, and adds the primary flag for the star '
        'register. This module does the same and adds one flag, '
        'sensitive. As I understand wl-clipboard’s documentation, '
        'that flag asks clipboard managers not to record the '
        'entry in their history. The file gives no reason, so '
        'treat that as my reading.'),
    ...pt('--', 'the escape hatch',
        'vim.g.omarchy_remote_clipboard_osc52 = false turns the '
        'OSC 52 emission off while keeping the local write. It '
        'is not mentioned in the README or the changelog; it is '
        'only discoverable by reading this file.'),
    ...pt('--', 'has_wayland is decided once',
        'at setup time, from the environment and the two '
        'executables. A Wayland session that starts after Neovim '
        'is not noticed.'),

    ...sec('the paste path'),
    ...code('lua', 'lua/config/remote_clipboard.lua · paste', r'''
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
  end'''),
    ...para('--',
        'Without a display the function simply hands back '
        'osc52.paste, Neovim’s own implementation. With one, it '
        'builds a closure around wl-paste. The no-newline flag '
        'matters: by default wl-paste adds a trailing newline, '
        'which would give every paste a stray empty line, and '
        'Neovim’s own wl-copy provider passes the same flag. '
        'Passing the keep-empty argument (the third value) to '
        'systemlist preserves blank lines inside the text. And a '
        'non-zero exit status, which as I understand it wl-paste '
        'returns when nothing has been copied, produces an empty '
        'table, so pasting from an empty clipboard is a quiet '
        'no-op, not an error message.'),

    ...sec('registering the provider'),
    ...code('lua', 'lua/config/remote_clipboard.lua · registration', r'''
  vim.g.clipboard = {
    name = "OmarchyRemoteClipboard",
    copy = { ["+"] = copy("+"), ["*"] = copy("*") },
    paste = { ["+"] = paste("+"), ["*"] = paste("*") },
    cache_enabled = 0,
  }'''),
    ...para('--',
        'This is the dictionary form that the Neovim manual '
        'describes, with functions in place of shell commands. '
        'The name is what Neovim reports as the active provider, '
        'so it is the quickest way to confirm that the module '
        'activated. cache_enabled = 0 states a value that '
        'Neovim 0.12.5’s runtime already uses by default for a '
        'user-supplied dictionary, so the line documents intent '
        'more than it changes behaviour.'),

    ...sec('what can go wrong'),
    ...pt('--', 'paste can block the editor',
        'in Neovim 0.12.5 the OSC 52 paste waits one second for '
        'the terminal to answer, prints “Waiting for OSC 52 '
        'response” and then waits up to nine more before warning '
        'that it timed out. If neither tmux nor the terminal '
        'answers queries, a paste in a display-less session '
        'stalls for up to ten seconds. The header comment says '
        'tmux or the terminal answers; no test in the repository '
        'shows it for the setups in use.'),
    ...pt('--', 'duplicated text in managers',
        'in principle the two writers (the local one and the OSC '
        '52 one) can both reach the same desktop clipboard in a '
        'local tmux session, if the terminal honours the sequence '
        'as well. This is not observed or recorded. The text '
        'would be identical, so the effect would show only in a '
        'clipboard manager that keeps history.'),
    ...pt('--', 'untested by the repository',
        'the CHANGELOG records no verification of this module '
        'beyond the startup change. A headless test could set '
        'TMUX, put fake wl-copy and wl-paste scripts on PATH and '
        'assert what each register produces, and that is the '
        'natural next step.'),
    ...pt('--', 'Linux only',
        'the walk reads /proc, so on any system without it the '
        'herdr test is always false and only the environment '
        'variables can activate the module.'),

    ...sec('what to take from it'),
    ...para('--',
        'The file is short because it composes existing pieces: '
        'Neovim’s OSC 52 functions, wl-clipboard, and the '
        'documented g:clipboard contract. The craft is in three '
        'places: choosing to broadcast copies and localise pastes, '
        'making the cheap tests run first, and returning early so '
        'the common case stays on the built-in path.'),

    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
