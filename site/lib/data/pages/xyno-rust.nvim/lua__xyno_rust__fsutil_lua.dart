import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/lua/xyno_rust/fsutil.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'fsutil.lua - two helpers for the operating systems that disagree'),
    cm('--', r'rename over an open file, and forward slashes'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'portable file-system helpers'),
    kv(r'language', r'Lua'),
    kv(r'size', r'33 lines'),
    kv(r'public', r'rename(tmp, dest), slash(path)'),
    kv(r'tested by', r'tests/fsutil_spec.lua'),
    ...sec(r'why this file exists'),
    ...para('--', r'Several modules write a state or cache file by writing a temporary file next to it and renaming it into place, so that another Neovim never sees a half-written file. On Linux and macOS that is a single uv.fs_rename. On Windows renaming over a file that another process has open fails with a sharing violation, and the processes with files open in this plugin are exactly the long-lived ones: rust-analyzer and other editors. The same applies to paths: on Windows buffer names, the working directory and LSP roots come back with backslashes while the code compares prefixes such as /.cargo/registry/. fsutil.lua keeps both platform differences out of the logic of every other module.'),
    ...sec(r'rename'),
    ...code('lua', r'lua/xyno_rust/fsutil.lua · lines 1-22', r'''
-- Small file-system helpers whose behaviour differs between platforms.
local M = {}

--- uv.fs_rename(tmp, dest) that survives Windows' sharing violations: renaming
--- over a file another process holds open (rust-analyzer, an editor) fails
--- with EPERM/EACCES/EBUSY until it lets go, so retry a few times there.
--- Returns what fs_rename returns (true, or nil + error).
function M.rename(tmp, dest)
  local ok, err, name = vim.uv.fs_rename(tmp, dest)
  if ok or vim.fn.has("win32") ~= 1 then
    return ok, err, name
  end
  for _ = 1, 5 do
    vim.wait(60)
    ok, err, name = vim.uv.fs_rename(tmp, dest)
    if ok then
      return ok
    end
  end
  return ok, err, name
end'''),
    ...para('--', r'On every platform except Windows the function is the plain call: it returns whatever fs_rename returned, and the branch ends at the first line. On Windows it makes up to five more attempts with a 60 ms wait between them, so the total patience is about 300 ms, and still returns the error triple if all fail. The comment names the errors that mean "someone has it open": EPERM, EACCES and EBUSY. It uses vim.wait rather than a sleep, so Neovim keeps processing events during the pause. The retry is bounded: if all attempts fail, the caller (which asserts or reports) gets the real error triple back.'),
    ...para('--', r'It is used by rust_context (write_all, for rust-context.json) and by crate_meta (line 136, atomic cache writes). The rust_context caller uses it through write_all, which asserts that the rename succeeded.'),
    ...sec(r'slash'),
    ...code('lua', r'lua/xyno_rust/fsutil.lua · lines 24-33', r'''
--- buffer names, cwd and LSP roots come back with backslashes there, while the
--- code compares prefixes and matches "/.cargo/registry/" style fragments.
function M.slash(p)
  if p and vim.fn.has("win32") == 1 then
    return (p:gsub("\\", "/"))
  end
  return p
end

return M'''),
    ...para('--', r'slash is deliberately a no-op outside Windows. A path on Linux may legally contain a backslash, and rewriting it there would corrupt a valid name; the function therefore checks vim.fn.has("win32") before it substitutes. It is also nil-tolerant (p and ...), because the callers pass client.config.root_dir, which can be absent. lsp_status uses it on both sides of its root comparisons.'),
    ...sec(r'how it is tested'),
    ...para('--', r'tests/fsutil_spec.lua is the shortest spec in the repository (36 lines). Its cases: moves a file over an existing one; returns nil plus an error for a missing source and does not retry off Windows; slash passes nil and plain paths through; slash turns backslashes into slashes on Windows only. Windows-only behaviour cannot run in the Linux CI of this repository, so the Windows branches are kept as ported and, as the README says, there is no evidence for them from this repository alone.'),
    ...sec(r'history'),
    ...para('--', r'In xynovim the helper arrived with the portability work of ff1c8fa ("Windows and macOS: portability fixes, PowerShell bootstrap, portable test runner, OS-aware skips, platforms workflow", 2026-10-16). It was copied unchanged into this repository in c1c7958.'),
  ],
);
