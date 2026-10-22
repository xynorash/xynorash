import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/.github/ci/diag-lsp.lua',
  lines: [
    cm(r'--', '──────────────────────────────────────────'),
    cm(r'--', r'.github/ci/diag-lsp.lua'),
    cm(r'--', r'a diagnostic that only prints'),
    cm(r'--', r'what attaches to a fresh crate, and what the LSP log says when something does not'),
    cm(r'--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'CI debugging aid for the Windows job'),
    kv(r'language', r'Lua, run as nvim --headless "+luafile .github/ci/diag-lsp.lua"'),
    kv(r'size', r'45 lines, two commits (6524272 created it, af6ca87 added the Mason block, both 2026-10-21)'),
    kv(r'effect', r'prints; creates a temporary crate; always ends with qa!'),
    ...sec(r'why this file exists'),
    ...para(r'--', r'On a CI runner nothing can be inspected interactively. The header says what this probe is for: which language clients attach to a fresh crate, and what the LSP log says when one does not. It sets up the smallest situation and prints facts that could explain a missing client: where the executables are, whether Mason’s bin is on the PATH, which clients exist, and what the tail of the language-server log says.'),
    blank,
    ...code('lua', r'.github/ci/diag-lsp.lua · lines 1-2', r'''
-- Diagnostic for the platforms workflow: which language clients attach to a
-- fresh crate, and what the LSP log says when one does not. Prints only.
'''),
    ...para(r'--', r'The header calls it a diagnostic for the platforms workflow and promises it prints only. The workflow runs it with if: always(), so it reports even after a failed bootstrap.'),
    blank,
    ...sec(r'building the smallest crate'),
    ...para(r'--', r'The probe builds a Cargo project of its own: a directory under the system temp folder named with the process id, a src folder, a Cargo.toml with a package of edition 2021 and a main.rs with an empty main. It never touches the checkout and cannot collide with a second run. Using a project the file creates itself rules out any dependence on the repository content.'),
    blank,
    ...code('lua', r'.github/ci/diag-lsp.lua · lines 3-6', r'''
local dir = vim.fs.joinpath(vim.uv.os_tmpdir(), "xyno-diag-" .. vim.uv.os_getpid())
vim.fn.mkdir(dir .. "/src", "p")
vim.fn.writefile({ '[package]', 'name = "diag"', 'version = "0.1.0"', 'edition = "2021"' }, dir .. "/Cargo.toml")
vim.fn.writefile({ "fn main() {}" }, dir .. "/src/main.rs")
'''),
    ...sec(r'what is on the PATH'),
    ...code('lua', r'.github/ci/diag-lsp.lua · lines 7-26', r'''
print("exepath bacon-ls: " .. vim.fn.exepath("bacon-ls"))
print("exepath bacon: " .. vim.fn.exepath("bacon"))
print("exepath rust-analyzer: " .. vim.fn.exepath("rust-analyzer"))
do
  local bin = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin")
  local sep = vim.fn.has("win32") == 1 and ";" or ":"
  local on_path = false
  for _, d in ipairs(vim.split(vim.env.PATH or "", sep, { plain = true })) do
    if vim.fs.normalize(d):lower() == vim.fs.normalize(bin):lower() then
      on_path = true
    end
  end
  print("mason bin: " .. bin .. " on PATH: " .. tostring(on_path))
  local names = {}
  for name in vim.fs.dir(bin) do
    names[#names + 1] = name
  end
  table.sort(names)
  print("mason bin contents: " .. table.concat(names, " "))
end
'''),
    ...para(r'--', r'It prints the exepath of bacon-ls, bacon and rust-analyzer: if one is empty, the editor cannot find it. The next block, added by af6ca87 the same day as the first version, checks whether Mason’s bin directory is on the PATH. It builds the path from stdpath data, picks the path separator by platform (semicolon on Windows, colon elsewhere), and compares each entry after normalising it and lower-casing both sides. The code does not say why it lower-cases; it does so on every platform. Then it lists the contents of the bin directory, sorted, so that a missing shim (an .exe or .cmd) is visible at a glance.'),
    blank,
    ...sec(r'attaching a client'),
    ...code('lua', r'.github/ci/diag-lsp.lua · lines 27-31', r'''
vim.cmd.edit(dir .. "/src/main.rs")
vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
vim.wait(90000, function()
  return #vim.lsp.get_clients({ name = "bacon_ls" }) > 0
end, 500)
'''),
    ...para(r'--', r'The probe opens main.rs and fires the VeryLazy user event by hand, so that the plugins LazyVim defers to that event load; the file does not say why it has to be done by hand. Then it waits up to 90 seconds, polling every 500 ms, until a client named bacon_ls exists. The wait is a ceiling and not a delay; on a working machine it returns at once.'),
    blank,
    ...code('lua', r'.github/ci/diag-lsp.lua · lines 32-34', r'''
for _, c in ipairs(vim.lsp.get_clients()) do
  print(("client %s id=%d root=%s cmd=%s initialized=%s"):format(c.name, c.id, tostring(c.root_dir), vim.inspect(c.config.cmd), tostring(c.initialized)))
end
'''),
    ...para(r'--', r'Then every client is printed with name, id, root directory, command and whether it has finished initialising, which are the facts that separate the failure modes: no client at all, a client with the wrong root, a client whose command points to the wrong executable, and a client that started but never completed the handshake.'),
    blank,
    ...sec(r'the log and the messages'),
    ...code('lua', r'.github/ci/diag-lsp.lua · lines 35-45', r'''
local log = vim.lsp.log.get_filename()
print("lsp log: " .. log)
if vim.uv.fs_stat(log) then
  local lines = vim.fn.readfile(log)
  for i = math.max(1, #lines - 40), #lines do
    print((lines[i]:gsub("\r", "")):sub(1, 300))
  end
end
local m = vim.trim(vim.api.nvim_exec2("messages", { output = true }).output)
print("messages: " .. m)
vim.cmd("qa!")
'''),
    ...para(r'--', r'The tail of the language-server log, 40 lines, each cut to 300 characters and with carriage returns removed, is printed with the file name. Then :messages is captured and printed, and the editor quits without saving anything. The output is meant to be read in the Actions log, which is why lines are trimmed and nothing is formatted.'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt(r'--', r'print, never assert', r'the script contains no assertion and no exit code of its own, only print calls; its header says it prints only.'),
    ...pt(r'--', r'self-contained', r'its own crate, its own temp directory, no dependence on fixtures.'),
    ...pt(r'--', r'cheap to remove', r'it lives in .github/ci, outside the configuration and the tests, and only the Windows job in platforms.yml refers to it.'),
    ...sec(r'history'),
    ...pt(r'--', r'6524272 2026-10-21', r'created in the commit with the fixes from run 39640256853, listed in its title as the LSP diagnostic step (28 lines at that point).'),
    ...pt(r'--', r'af6ca87 2026-10-21', r'the commit titled cross-platform review fixes; in this file it adds the Mason bin and PATH block.'),
  ],
);
