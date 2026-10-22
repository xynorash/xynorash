import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/scripts-portable_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'scripts-portable_spec.lua — keeping the Windows scripts honest without a Windows machine'),
    cm('--', r'the PowerShell bootstrap and the Lua test runner must mirror the shell originals, and the OS header must really skip'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for scripts/bootstrap.ps1, scripts/test.lua, scripts/test.ps1 and the xyno-os mechanism of tests/runner.lua'),
    kv(r'language', r'Lua spec, 152 lines, 12 it() blocks, 3 describe() blocks'),
    kv(r'platform', r'runs on every platform (the header says so); the PowerShell parse runs only where pwsh or powershell exists'),
    kv(r'history', r'1 commit, ff1c8fa (2026-10-16)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The configuration was written on Linux. The commit ff1c8fa (2026-10-16, "Windows and macOS: portability fixes, PowerShell bootstrap, portable test runner, OS-aware skips, platforms workflow") added Windows and macOS support. On Windows there is no bash, so scripts/bootstrap.sh needs a PowerShell twin, and scripts/test.sh needs a Lua twin (scripts/test.lua plus a thin test.ps1). Two implementations of the same behaviour drift apart. The spec is the guard against that drift, and because the scripts cannot be run on the machine that develops them, the spec checks them by reading their text, then by asking a real PowerShell parser when one exists. The header describes the strategy in one sentence: table checks on the text, plus a real PowerShell parse when pwsh or powershell is installed, running on every platform.'),
    ...code('lua', r'tests/scripts-portable_spec.lua · lines 1-5', r'''
-- The Windows scripts mirror the shell ones: scripts/bootstrap.ps1 does what
-- scripts/bootstrap.sh does, scripts/test.lua (and the thin test.ps1) what
-- scripts/test.sh does. Table checks on the text, plus a real PowerShell parse
-- when pwsh / powershell is installed. Runs on every platform.
local H = require("xynotest.helpers")'''),
    ...sec(r'reading both versions'),
    ...para('--', r'The spec reads the five files once at load. The bootstrap, test.lua and test.sh are held in locals, and each test asserts that a statement is true for both sides, using H.has on the text. It is a deliberately simple, brittle-in-the-right-way check: if someone renames a step in one script, a test fails and points to the other.'),
    ...code('lua', r'tests/scripts-portable_spec.lua · lines 7-15', r'''
local function read(rel)
  local f = assert(io.open(H.repo .. "/" .. rel, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local sh, ps, tl = read("scripts/bootstrap.sh"), read("scripts/bootstrap.ps1"), read("scripts/test.lua")
local tsh = read("scripts/test.sh")'''),
    ...sec(r'the same three steps in the same order'),
    ...para('--', r'The shell bootstrap runs three steps: install the plugins from the lockfile, restore them to the locked versions, and provision parsers and Mason tools. The test requires the three markers Lazy! install, Lazy! restore and provision.lua in both scripts, compares the positions in the PowerShell one to prove that the order is install, then restore, then provision, and checks the step labels 1/3 and 3/3.'),
    ...code('lua', r'tests/scripts-portable_spec.lua · lines 17-27', r'''
describe("scripts/bootstrap.ps1 mirrors scripts/bootstrap.sh", function()
  it("runs the same three steps in the same order", function()
    for _, step in ipairs({ "Lazy! install", "Lazy! restore", "provision.lua" }) do
      H.has(sh, step)
      H.has(ps, step)
    end
    local a, b, c = ps:find("Lazy! install", 1, true), ps:find("Lazy! restore", 1, true), ps:find("provision.lua", 1, true)
    H.ok(a < b and b < c, "install, then restore, then provision")
    H.has(ps, "step 1/3")
    H.has(ps, "step 3/3")
  end)'''),
    ...sec(r'the lockfile comes back'),
    ...para('--', r'Installing on a new machine must not leave lazy-lock.json changed, because the lockfile is the record of tested versions. The shell script puts it back after the install round and compares it at the end. The PowerShell test looks for the Copy-Item that restores the saved copy, a Get-FileHash comparison, and both outcome messages lazy-lock.json unchanged and lazy-lock.json changed.'),
    ...code('lua', r'tests/scripts-portable_spec.lua · lines 29-34', r'''
  it("puts the lockfile back after the install round and compares it at the end", function()
    H.has(ps, "Copy-Item -LiteralPath $orig -Destination $lock")
    H.has(ps, "Get-FileHash")
    H.has(ps, "lazy-lock.json unchanged")
    H.has(ps, "lazy-lock.json changed")
  end)'''),
    ...sec(r'the same prerequisites'),
    ...para('--', r'The test extracts the tool list from the for-loop of bootstrap.sh with a pattern and requires every tool in the PowerShell script, except the ones Windows does not use: unzip, gzip, and gcc and rust-analyzer, which are handled specially. The C compiler list is spelled out for Windows (gcc, cc, clang, cl, zig), winget is named, the skip switch BOOTSTRAP_SKIP_PREREQS exists in both, and unzip must not appear in the PowerShell script.'),
    ...code('lua', r'tests/scripts-portable_spec.lua · lines 36-50', r'''
  it("checks the same prerequisites (minus unzip / gzip, which Windows does not use) and keeps the skip switch", function()
    local list = sh:match("for tool in ([^;]-); do")
    H.ok(list, "the tool list in bootstrap.sh")
    for tool in list:gmatch("%S+") do
      if tool ~= "unzip" and tool ~= "gzip" and tool ~= "gcc" and tool ~= "rust-analyzer" then
        H.has(ps, "'" .. tool .. "'")
      end
    end
    H.has(ps, "rust-analyzer")
    H.has(ps, "'gcc', 'cc', 'clang', 'cl', 'zig'")
    H.has(ps, "BOOTSTRAP_SKIP_PREREQS")
    H.has(sh, "BOOTSTRAP_SKIP_PREREQS")
    H.has(ps, "winget")
    H.not_ok(ps:find("'unzip'", 1, true), "Windows does not need unzip")
  end)'''),
    ...sec(r'links without administrator rights'),
    ...para('--', r'Windows symlinks need a privilege. The script links the configuration with a junction, mklink /J, which does not. The test requires the junction command, a refusal that says the existing directory is not this checkout (an existing directory is never replaced), and the use of LOCALAPPDATA and XDG_CONFIG_HOME.'),
    ...code('lua', r'tests/scripts-portable_spec.lua · lines 52-57', r'''
  it("links the config with a junction (no administrator rights) and never replaces an existing directory", function()
    H.has(ps, "mklink /J")
    H.has(ps, "is not this checkout")
    H.has(ps, "LOCALAPPDATA")
    H.has(ps, "XDG_CONFIG_HOME")
  end)'''),
    ...sec(r'PowerShell 5.1 syntax only'),
    ...para('--', r'Windows ships PowerShell 5.1. The script must run there before pwsh is installed. The test removes comments with a pattern and then requires that none of the PowerShell 7 constructs appear: the null-coalescing operator, the ternary operator, -Parallel, && and ||. A Linux-only author cannot run PowerShell 5.1 locally, so the rule is kept by text.'),
    ...code('lua', r'tests/scripts-portable_spec.lua · lines 59-64', r'''
  it("uses only PowerShell 5.1 syntax (no ?: ?? && || -Parallel)", function()
    local code = ps:gsub("#[^\n]*", "")
    for _, bad in ipairs({ " ?? ", " ? ", "-Parallel", "&&", "||" }) do
      H.not_ok(code:find(bad, 1, true), "PowerShell 7 only: " .. bad)
    end
  end)'''),
    ...sec(r'a real parse'),
    ...para('--', r'When pwsh or powershell is installed, the spec calls the parser from the .NET assembly, System.Management.Automation.Language.Parser, on both scripts, with -NoProfile and -NonInteractive. It prints the errors and exits 1 if there are any. When neither exists the test skips with a reason. The parse catches what string checks cannot, a syntax error.'),
    ...code('lua', r'tests/scripts-portable_spec.lua · lines 66-78', r'''
  it("parses with the PowerShell parser (when pwsh or powershell exists)", function()
    local exe = vim.fn.executable("pwsh") == 1 and "pwsh" or vim.fn.executable("powershell") == 1 and "powershell" or nil
    if not exe then
      return skip("no pwsh / powershell on this machine")
    end
    for _, f in ipairs({ "scripts/bootstrap.ps1", "scripts/test.ps1" }) do
      local cmd = ("$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile('%s',[ref]$null,[ref]$e); if ($e.Count) { $e | ForEach-Object { $_.ToString() }; exit 1 }"):format(
        H.repo .. "/" .. f
      )
      local r = vim.system({ exe, "-NoProfile", "-NonInteractive", "-Command", cmd }, { text = true }):wait(60000)
      H.eq(0, r.code, f .. ": " .. (r.stdout or "") .. (r.stderr or ""))
    end
  end)'''),
    ...sec(r'the Lua test runner mirrors test.sh'),
    ...para('--', r'The test runner for Windows takes the same options (--list, --timeout, -v) and mentions --coverage, documented as not supported there. It follows the same protocol: XYNO_SPEC, tests/runner.lua, the XYNO_RESULT line, xyno-timeout, the 30 second grace, and the XDG state, cache and test temp variables. test.ps1 only locates nvim and runs test.lua with -l. And --list is tested for real by running nvim --clean -l scripts/test.lua --list and comparing the lines to the sorted list of tests/*_spec.lua.'),
    ...code('lua', r'tests/scripts-portable_spec.lua · lines 81-118', r'''
describe("scripts/test.lua and test.ps1 mirror scripts/test.sh", function()
  it("take the same options", function()
    for _, opt in ipairs({ "--list", "--timeout", "-v" }) do
      H.has(tsh, opt)
      H.has(tl, opt)
    end
    H.has(tl, "--coverage") -- documented as not supported there
  end)

  it("use the same protocol: XYNO_SPEC, the runner, the XYNO_RESULT line, xyno-timeout, the 30 s grace", function()
    for _, w in ipairs({ "XYNO_SPEC", "tests/runner.lua", "XYNO_RESULT", "xyno%-timeout", "30000", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XYNO_TEST_TMP" }) do
      H.ok(tl:find(w) or tl:find(w, 1, true), "test.lua lacks " .. w)
    end
    H.has(tsh, "XYNO_RESULT")
    H.has(tsh, "xyno-timeout")
  end)

  it("test.ps1 only locates nvim and runs test.lua", function()
    local t = read("scripts/test.ps1")
    H.has(t, "scripts")
    H.has(t, "test.lua")
    H.has(t, "-l")
  end)

  it("--list prints the spec files (same list as test.sh --list)", function()
    local nvim = vim.v.progpath
    local r = vim.system({ nvim, "--clean", "-l", H.repo .. "/scripts/test.lua", "--list" }, { text = true }):wait(30000)
    H.eq(0, r.code, r.stderr)
    local got = vim.split(vim.trim(r.stdout), "\r?\n")
    local want = {}
    for name in vim.fs.dir(H.repo .. "/tests") do
      if name:match("_spec%.lua$") then
        want[#want + 1] = "tests/" .. name
      end
    end
    table.sort(want)
    H.eq(want, got)
  end)'''),
    ...sec(r'the OS header really skips'),
    ...para('--', r'The last block tests the mechanism that tests/runner.lua implements. It writes a throwaway spec whose first line says it needs the other platform, runs a real headless nvim on it with the runner, and requires exit code 0, a SKIP line with the exact sentence needs <other>, this is <os>: only there, and XYNO_RESULT passed=0 failed=0 skipped=1. A last test checks the reason format of H.need_os and that H.need_posix skips on Windows and passes elsewhere.'),
    ...code('lua', r'tests/scripts-portable_spec.lua · lines 121-151', r'''
describe("OS-aware skips", function()
  it("a spec with a `-- xyno-os:` header for another platform is skipped with its reason", function()
    local other = H.os == "linux" and "windows" or "linux"
    local dir = H.tmpdir()
    local spec = dir .. "/os_spec.lua"
    local f = assert(io.open(spec, "wb"))
    f:write(("-- xyno-os: %s (only there)\nlocal H = require('xynotest.helpers')\nit('x', function() error('must not run') end)\n"):format(other))
    f:close()
    local r = vim.system({ vim.v.progpath, "--headless", "-S", H.repo .. "/tests/runner.lua" }, {
      text = true,
      env = { XYNO_SPEC = spec },
    }):wait(120000)
    H.eq(0, r.code, r.stdout .. r.stderr)
    H.match(r.stdout, "SKIP os_spec.lua (needs " .. other .. ", this is " .. H.os .. ": only there)", true)
    H.match(r.stdout, "XYNO_RESULT passed=0 failed=0 skipped=1", true)
  end)

  it("H.need_os / H.need_posix skip with the platform in the reason", function()
    local harness = require("xynotest.harness")
    local ok, e = pcall(H.need_os, { "nowhere" }, "because")
    H.eq(false, ok)
    H.ok(harness.is_skip(e))
    H.match(e.reason, "needs nowhere, this is " .. H.os .. ": because", true)
    if H.is_win then
      local ok2, e2 = pcall(H.need_posix, "sh")
      H.eq(false, ok2)
      H.ok(harness.is_skip(e2))
    else
      H.eq(true, pcall(H.need_posix, "sh"))
    end
  end)'''),
    ...sec(r'design notes'),
    blank,
    ...pt('--', r'Text checks have a purpose', r'they are cheap, run everywhere, and fail when the twins diverge. They do not prove that the PowerShell script works. That proof is the platforms workflow (.github/workflows/platforms.yml), which runs bootstrap, a silent start and the spec suite on windows-latest and macOS.'),
    ...pt('--', r'What is not covered', r'this spec cannot know whether the specs that skip on Windows should skip. docs/KNOWN_ISSUES.md lists the evidence of runs 39647013043, 39655339161 and 39660597368 and the specs that skip because no cause was found.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'ff1c8fa (2026-10-16)', r'the only commit; the file arrived with the scripts it guards.'),
  ],
);
