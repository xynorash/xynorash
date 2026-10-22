import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-clipboard.nvim/lua/xyno_clipboard/detect.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'detect.lua — is this a session whose yanks must leave the machine?'),
    cm('--', r'four environment variables, then a bounded walk up /proc'),
    cm('--', r'──────────────────────────────────────────'),
    kv(r'role', r'session detection, returns the reason or nil'),
    kv(r'language', r'Lua'),
    kv(r'size', r'54 lines'),
    kv(r'used by', r'init.lua, once per setup() call'),
    kv(r'history', r'split out of the single xynovim module in faa38b4'),
    ...sec(r'why this file exists'),
    ...para('--', r'Before the provider can be installed, something has to decide whether the session is one '
        r'where a copy may need to reach another machine. In xynovim that logic sat at the top of '
        r'lua/config/remote_clipboard.lua together with the provider. In the extracted plugin it is '
        r'its own module with one public function, which keeps init.lua about the provider and lets '
        r'the specs replace /proc reading in one place. The header says what it answers.'),
    ...code('lua', r'lua/xyno_clipboard/detect.lua · lines 1-3', r'''
-- Decides whether this session is one whose yanks may have to reach another
-- machine. Env vars first; the /proc ancestor walk only when they say nothing.
local M = {}
'''),
    ...sec(r'the /proc helpers'),
    ...code('lua', r'lua/xyno_clipboard/detect.lua · lines 5-17', r'''
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
end
'''),
    ...para('--', r'Three facts about this code. First, proc_lines wraps vim.fn.readfile in pcall and returns '
        r'an empty table on any error. A process can vanish between two reads, a /proc entry can be '
        r'unreadable, and none of that may break startup; an empty list simply produces nil further '
        r'down. Second, proc_ppid scans the lines of /proc/PID/status for the PPid field with a '
        r'pattern anchored at the line start, which is the documented format of that file. Third, '
        r'it returns nil if no such line exists, and the caller treats nil the same as reaching the '
        r'top of the tree.'),
    ...sec(r'the bounded ancestor walk'),
    ...code('lua', r'lua/xyno_clipboard/detect.lua · lines 19-37', r'''
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
end
'''),
    ...para('--', r'The walk starts from vim.fn.getpid() and climbs at most 16 parents. It stops early in two '
        r'cases: the parent cannot be determined, or the parent id is 1 or lower, which is init. '
        r'The comparison is a plain-text find of the name inside /proc/PPID/comm, so a process '
        r'called herdr-server matches a search for herdr. That is intentional and the spec uses '
        r'exactly that name.'),
    ...pt('--', r'Why 16', r'a hard bound turns a pathological /proc (a cycle, a very deep tree) into a finite cost. '
        r'The spec builds a chain that loops without reaching init and asserts that no more than 16 '
        r'status files are read, with a herdr placed at step 17 that must not be seen.'),
    ...pt('--', r'Why stop at init', r'the spec has a case with a herdr process above pid 1 and asserts that no read touches '
        r'/proc/1/. A real session would never put the terminal multiplexer above init, so nothing '
        r'useful lies there.'),
    ...pt('--', r'Why comm, not cmdline', r'comm is a single short line holding the executable name, which makes it cheap to read and '
        r'to match. The file does not discuss this; it is what the code shows.'),
    ...sec(r'reason(): cheapest first'),
    ...code('lua', r'lua/xyno_clipboard/detect.lua · lines 39-52', r'''
--- Returns the reason the provider is wanted ("TMUX", "SSH_TTY",
--- "SSH_CONNECTION", "HERDR_PANE_ID", "herdr ancestor") or nil.
--- Ordered cheapest-first so the /proc walk (16 process-file reads) only
--- runs when no env var has already decided the answer.
function M.reason()
  for _, var in ipairs({ "TMUX", "SSH_TTY", "SSH_CONNECTION", "HERDR_PANE_ID" }) do
    if vim.env[var] ~= nil then
      return var
    end
  end
  if ancestor_process_named("herdr") then
    return "herdr ancestor"
  end
end
'''),
    ...para('--', r'The public function returns a string naming the signal, or nil. The order is the design: '
        r'the four environment variables are tested before anything else, in the order TMUX, '
        r'SSH_TTY, SSH_CONNECTION, HERDR_PANE_ID, and the /proc walk, which costs up to 16 file '
        r'reads for status and comm, runs only when none of them decided. The comment says this '
        r'explicitly. In xynovim the same idea arrived in f35b4f6 (2026-09-03): the '
        r'first version computed all three booleans, including the ancestor walk, on every start, '
        r'and the later one chained them with or so that a tmux session never reads /proc at all. '
        r'The clipboard spec checks it directly: with any of the four variables set it asserts that '
        r'the list of /proc reads is empty.'),
    ...para('--', r'The return values double as the user-facing explanation, since init.lua stores the string '
        r'and :XynoClipboardStatus prints it. That is why the herdr case returns the phrase herdr '
        r'ancestor rather than a boolean.'),
    ...sec(r'edge cases and what the spec says'),
    ...pt('--', r'Unreadable status', r'the first parent’s status unreadable gives no error and no provider.'),
    ...pt('--', r'Missing entry deeper in the chain', r'the same: nil, not an error.'),
    ...pt('--', r'Nothing recognisable', r'a chain of nvim, bash, init returns nil and the default provider detection stays in charge.'),
    ...pt('--', r'Real pids', r'the spec replaces vim.fn.getpid and vim.fn.readfile through rawset on the vim.fn table, '
        r'then restores them in the after hook.'),
    ...sec(r'a limitation worth knowing'),
    ...para('--', r'The walk is Linux specific by construction, because it reads /proc. The caller guards on '
        r'vim.fn.has("linux") before calling it, which is why the platform line in the README is a '
        r'design statement and not an omission. herdr is a name matched as a substring of an '
        r'ancestor’s comm; what herdr is, the repository does not explain, and neither will this '
        r'page.'),
    ...sec(r'history'),
    ...pt('--', r'faa38b4', r'2026-10-22: the module is created from the xynovim original, which contained these '
        r'functions at the top of remote_clipboard.lua (eabb22a, 2026-09-02).'),
  ],
);
