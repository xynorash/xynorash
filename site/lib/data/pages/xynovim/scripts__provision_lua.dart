import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/scripts/provision.lua',
  lines: [
    cm(r'--', '──────────────────────────────────────────'),
    cm(r'--', r'scripts/provision.lua'),
    cm(r'--', r'download what LazyVim would fetch on first start, and wait until it is there'),
    cm(r'--', r'treesitter parsers must arrive, Mason tools may fail'),
    cm(r'--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'step 3 of the bootstrap: parsers and language tools, headless'),
    kv(r'language', r'Lua, run as nvim --headless "+luafile scripts/provision.lua" +qa'),
    kv(r'size', r'133 lines, three commits (fc2062a, 24eb6a2, a2e0d5a)'),
    kv(r'exit code', r'1 when a treesitter parser is missing afterwards, 0 otherwise (Mason only warns)'),
    ...sec(r'why this file exists'),
    ...para(r'--', r'LazyVim is lazy about everything, including the things the editor needs to be useful. Treesitter parsers are installed in the background after nvim-treesitter loads, and a language server is installed when you first open a file of its type. That is pleasant interactively and wrong for an unattended machine: the test suite and a first Rust session would both wait on downloads that nothing is waiting for. provision.lua moves all of that to install time and blocks until it is finished.'),
    blank,
    ...para(r'--', r'It was added in fc2062a on 2026-10-14, the commit that made CI pass on a clean machine, and changed twice after it: 24eb6a2 cites a lock-file race seen on macOS and an early exit seen on Windows, and a2e0d5a cites a codelldb install lost on Linux. Much of the file is comments recording problems seen on a specific platform.'),
    blank,
    ...code('lua', r'scripts/provision.lua · lines 1-12', r'''
-- Downloads what LazyVim would otherwise fetch lazily on the first start:
-- treesitter parsers and Mason packages, and waits until they are there.
-- Run by scripts/bootstrap.sh as
--   nvim --headless "+luafile scripts/provision.lua" +qa
-- Exit code 1 when a treesitter parser is missing afterwards (tests need them);
-- Mason failures only warn (they need the network and the specs skip without).
local function say(msg)
  io.stdout:write("provision: " .. msg .. "\n")
end

require("lazy").load({ plugins = { "nvim-treesitter", "mason.nvim", "nvim-lspconfig", "mason-lspconfig.nvim" } })
'''),
    ...para(r'--', r'The header settles the failure policy before any code runs. A missing parser is fatal because the specs need them. A missing Mason package only warns because Mason needs the network and the specs that use its tools skip when the tool is absent. Two different failure severities, one script.'),
    blank,
    ...sec(r'part 1: treesitter parsers'),
    ...code('lua', r'scripts/provision.lua · lines 13-21', r'''
-- 1. treesitter parsers (opts.ensure_installed of LazyVim, its extras and ours)
local TS = require("nvim-treesitter")
local want = LazyVim.opts("nvim-treesitter").ensure_installed or {}
local function absent()
  LazyVim.treesitter.get_installed(true)
  return vim.tbl_filter(function(lang)
    return not LazyVim.treesitter.have(lang)
  end, want)
end
'''),
    ...para(r'--', r'The list comes from LazyVim.opts for nvim-treesitter, so it is the union of LazyVim’s own ensure_installed, the extras the config enables, and this repository’s additions. The script does not keep a second list of languages that could drift from the real one. The helper absent() asks LazyVim itself which of them are not installed, passing true to LazyVim.treesitter.get_installed before each check.'),
    blank,
    ...sec(r'the race it has to avoid'),
    ...code('lua', r'scripts/provision.lua · lines 22-40', r'''
-- Loading nvim-treesitter makes LazyVim start the same installs itself, in the
-- background. A second, concurrent set makes two tree-sitter builds of one
-- parser fight over its lock file ("appears stale", seen on macOS) and ends this
-- script before the first set is done (seen on Windows): let the running
-- installs finish (no progress for 15 s), then install what is still missing.
local function settle(max_ms)
  local last, since = -1, vim.uv.now()
  vim.wait(max_ms, function()
    local n = #absent()
    if n == 0 then
      return true
    end
    if n ~= last then
      last, since = n, vim.uv.now()
    end
    return vim.uv.now() - since > 15000
  end, 1000)
end
settle(900000)
'''),
    ...para(r'--', r'The comment explains a problem found by running on other platforms. Loading nvim-treesitter makes LazyVim start the same installs by itself in the background. If the script immediately started a second set, two tree-sitter builds of one parser fought over a lock file (it appears stale, seen on macOS), and on Windows the script ended before the first set was done. The fix is to let the running installs finish.'),
    blank,
    ...para(r'--', r'settle() polls once per second. It tracks the number of absent parsers and the time that number last changed, and returns when nothing is missing or when there has been no progress for 15 seconds. The wait budget is large (900000 ms, fifteen minutes) but the rule that matters is the no-progress rule: it ends the wait when downloads have stalled or finished, not after a fixed delay.'),
    blank,
    ...code('lua', r'scripts/provision.lua · lines 41-51', r'''
local missing
for round = 1, 3 do
  missing = absent()
  if #missing == 0 then
    break
  end
  say(("installing %d treesitter parsers (round %d): %s"):format(#missing, round, table.concat(missing, ", ")))
  TS.install(missing, { summary = true }):wait(900000)
  settle(300000)
end
local still = absent()
'''),
    ...para(r'--', r'Then up to three rounds of an explicit install of whatever is still missing. Each round prints what it is installing, waits on the install future for as long as 15 minutes, and settles again for up to five. After the loop the script keeps the list of what is still absent in a variable and does not exit yet, because the Mason half should run first and a developer should see both reports.'),
    blank,
    ...sec(r'part 2: Mason packages'),
    ...code('lua', r'scripts/provision.lua · lines 53-73', r'''
-- 2. Mason packages (installed by LazyVim's own ensure_installed hooks once the
--    registry is loaded: wait until nothing is installing any more)
local reg = require("mason-registry")
local refreshed = false
reg.refresh(function()
  refreshed = true
end)
vim.wait(120000, function()
  return refreshed
end, 100)
-- Language servers and tools the README promises. LazyVim only installs the
-- server of a filetype when you first open such a file; do it up front so the
-- specs (and a first Rust session) do not wait for downloads.
local TOOLS = { "bacon-ls", "taplo", "yaml-language-server", "marksman", "lua-language-server", "json-lsp", "codelldb", "wgsl-analyzer", "tree-sitter-cli", "shfmt", "stylua", "markdownlint-cli2", "markdown-toc" }
for _, name in ipairs(TOOLS) do
  local ok, pkg = pcall(reg.get_package, name)
  if ok and not pkg:is_installed() and not pkg:is_installing() then
    say("installing Mason package " .. name)
    pkg:install()
  end
end
'''),
    ...para(r'--', r'The registry is refreshed with a callback and awaited for up to two minutes. The TOOLS list is the set of language servers and tools the README promises: bacon-ls, taplo, yaml-language-server, marksman, lua-language-server, json-lsp, codelldb, wgsl-analyzer, tree-sitter-cli, shfmt, stylua, markdownlint-cli2 and markdown-toc. Every call into the registry is behind pcall, since a package name that does not exist on a platform raises, and a bootstrap must not die for that. A package is started only if it is neither installed nor installing already, to avoid a duplicate.'),
    blank,
    ...code('lua', r'scripts/provision.lua · lines 74-89', r'''
local quiet_since
vim.wait(900000, function()
  local busy = false
  for _, pkg in ipairs(reg.get_all_packages()) do
    if pkg:is_installing() then
      busy = true
      break
    end
  end
  if busy then
    quiet_since = nil
    return false
  end
  quiet_since = quiet_since or vim.uv.now()
  return vim.uv.now() - quiet_since > 5000 -- no new install started for 5 s
end, 200)
'''),
    ...para(r'--', r'Then another idle wait. busy becomes true if any package in the registry is installing; the wait returns when nothing has been installing for five seconds. Again the signal is quiet, not elapsed time, and it also catches the installs LazyVim started by itself.'),
    blank,
    ...sec(r'the retry for aborted Mason installs'),
    ...code('lua', r'scripts/provision.lua · lines 90-118', r'''
-- A package whose install was aborted or lost a race (seen: codelldb on Linux,
-- "Neovim is exiting while packages are still installing") is retried, waiting
-- on the install handles themselves.
for round = 1, 2 do
  local handles = {}
  for _, name in ipairs(TOOLS) do
    local ok, pkg = pcall(reg.get_package, name)
    if ok and not pkg:is_installed() then
      say(("retrying Mason package %s (round %d)"):format(name, round))
      local started, h = pcall(function()
        return pkg:install()
      end)
      if started and h then
        handles[#handles + 1] = h
      end
    end
  end
  if #handles == 0 then
    break
  end
  vim.wait(600000, function()
    for _, h in ipairs(handles) do
      if not h:is_closed() then
        return false
      end
    end
    return true
  end, 200)
end
'''),
    ...para(r'--', r'This block arrived in a2e0d5a (2026-10-21) with the explanation in its own comment: a package whose install was aborted or lost a race, seen with codelldb on Linux with the message Neovim is exiting while packages are still installing, is retried. The retry waits on the install handles themselves rather than on the registry: it collects them into a table and polls until every handle reports closed, up to ten minutes per round. The quiet-period wait above it is unchanged. Two rounds at most; if no handle was started the loop breaks at once.'),
    blank,
    ...sec(r'the report'),
    ...code('lua', r'scripts/provision.lua · lines 119-133', r'''
say("mason packages: " .. table.concat(reg.get_installed_package_names(), ", "))
for _, name in ipairs(TOOLS) do
  local ok, pkg = pcall(reg.get_package, name)
  if not ok then
    say("Mason has no package " .. name .. " (not provided for this platform)")
  elseif not pkg:is_installed() then
    say("Mason package NOT installed: " .. name .. " (see :MasonLog; a Mason failure only warns)")
  end
end

if #still > 0 then
  say("FAILED, treesitter parsers still missing: " .. table.concat(still, ", "))
  vim.cmd("cquit 1")
end
say("done (" .. #want .. " parsers present)")
'''),
    ...para(r'--', r'The last block prints what is installed, then names every tool that is absent. Two cases are distinguished: Mason has no such package at all (not provided for this platform), and a package that exists but did not install, with a pointer to :MasonLog. Only after that does the script act on the earlier parser check: if any parser is still missing it prints FAILED and calls cquit 1, which makes Neovim exit with status 1 and so fails bootstrap.sh under set -e. Otherwise it reports the number of parsers present.'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt(r'--', r'progress over timeouts', r'both waits are defined by lack of change (15 s without a new parser, 5 s without a new install), with a large ceiling. A slow connection is tolerated and a stuck one ends.'),
    ...pt(r'--', r'one source of truth', r'the parser list is read from LazyVim’s options, so adding a language to the config provisions it automatically. The Mason list is a literal table in this file; the comment above it says it holds what the README promises.'),
    ...pt(r'--', r'retry, then report', r'transient failures (a race, a dropped connection) get two more tries; persistent ones are named in the output instead of hidden.'),
    ...sec(r'a small inconsistency'),
    ...para(r'--', r'The header comment says the script is run by scripts/bootstrap.sh. The PowerShell bootstrap runs it too, through a luafile argument with forward slashes. The header was not updated when the PowerShell script was added.'),
    blank,
    ...sec(r'history'),
    ...pt(r'--', r'fc2062a 2026-10-14', r'added with the CI clean-machine fixes.'),
    ...pt(r'--', r'24eb6a2 2026-10-16', r'let LazyVim’s own parser installs finish before starting a second set; report Mason packages that are missing (the settle function and the final report).'),
    ...pt(r'--', r'a2e0d5a 2026-10-21', r'retry of aborted Mason installs (lines 90-118).'),
  ],
);
