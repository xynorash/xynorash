import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-rust.nvim/tests/fsutil_spec.lua',
  lines: [
    cm('--', r'──────────────────────────────────────────'),
    cm('--', r'tests/fsutil_spec.lua — the two platform shims, checked on whatever you run'),
    cm('--', r'rename over an existing file, and slash() that only acts on Windows'),
    cm('--', r'──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/xyno_rust/fsutil.lua (33 lines, two functions)'),
    kv(r'language', r'Lua, run by tests/run.lua'),
    kv(r'size', r'36 lines, 4 tests, 1 commit in this repo (7c1d2d9)'),
    kv(r'platform', r'written for Linux; the Windows branches are only exercised on Windows'),
    kv(r'helpers', r'H.tmpdir, H.eq, H.ok, H.is_nil, H.match'),
    ...sec(r'why this file exists'),
    ...para('--', r'fsutil.lua is the smallest module of the plugin and the one with the strangest reason to '
        r'exist: two functions whose behaviour depends on the operating system. rename(tmp, dest) '
        r'wraps vim.uv.fs_rename and retries a few times on Windows, where replacing a file that '
        r'another process holds open fails with a sharing violation until the other process lets '
        r'go. slash(p) turns backslashes into forward slashes on Windows and does nothing anywhere '
        r'else.'),
    ...para('--', r'Both are used where a mistake would be expensive and quiet. rename is the last step of '
        r'two atomic writers: rust_context.lua write_all (line 31) writes the per-workspace state '
        r'file aside and renames it into place so a second Neovim never reads a half-written file, '
        r'and crate_meta.lua write_file (line 136) does the same for its cache files. slash is '
        r'called from lsp_status.lua (lines 145, 200, 212) before root directories and buffer names '
        r'are compared by prefix. If either misbehaved, the symptom would be a lost context choice '
        r'or a status line that never recognises its project, and nobody would look at a 33-line '
        r'file first.'),
    ...para('--', r'This spec is the way to look at it first. It is one of the specs written for this '
        r'repository rather than lifted from xynovim (see the history section), and it is short '
        r'because the module is.'),
    ...sec(r'the file under test'),
    ...code('lua', r'lua/xyno_rust/fsutil.lua · lines 1-33', r'''
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
end

--- Forward slashes (Windows only; elsewhere the path is returned untouched):
--- buffer names, cwd and LSP roots come back with backslashes there, while the
--- code compares prefixes and matches "/.cargo/registry/" style fragments.
function M.slash(p)
  if p and vim.fn.has("win32") == 1 then
    return (p:gsub("\\", "/"))
  end
  return p
end

return M
'''),
    ...sec(r'the rename tests'),
    ...code('lua', r'tests/fsutil_spec.lua · lines 1-22', r'''
-- xyno_rust.fsutil: rename over an existing file and slash().
local H = require("xyno_rust_test.helpers")
local fs = require("xyno_rust.fsutil")

describe("fsutil.rename", function()
  it("moves a file over an existing one", function()
    local dir = H.tmpdir()
    vim.fn.writefile({ "new" }, dir .. "/a.tmp")
    vim.fn.writefile({ "old" }, dir .. "/a")
    H.ok(fs.rename(dir .. "/a.tmp", dir .. "/a"))
    H.eq({ "new" }, vim.fn.readfile(dir .. "/a"))
    H.eq(0, vim.fn.filereadable(dir .. "/a.tmp"))
  end)

  it("returns nil + error for a missing source (and does not retry off Windows)", function()
    local dir = H.tmpdir()
    local ok, err = fs.rename(dir .. "/nope", dir .. "/b")
    H.is_nil(ok)
    H.match(err, "ENOENT", true)
  end)
end)

'''),
    ...para('--', r'Four things are pinned here.'),
    ...pt('--', r'the happy path', r'a file named a.tmp with the content new is moved over an existing file a with the content '
        r'old. Afterwards a contains new and a.tmp is gone (filereadable is 0). That is the whole '
        r'contract that write_all and write_file rely on: after the call the destination holds the new content and the temporary name does not linger. The spec does not test atomicity itself.'),
    ...pt('--', r'success is truthy', r'H.ok(fs.rename(...)). On success vim.uv.fs_rename returns true and the function returns '
        r'it, so callers can write assert(rename(...)) as rust_context does.'),
    ...pt('--', r'the failure shape', r'for a source that does not exist the function returns nil and an error string. The spec '
        r'checks nil for the first value and finds the text ENOENT in the second, with the plain '
        r'flag so that no pattern characters are involved. A caller never gets an exception from '
        r'rename, it gets a value it can test.'),
    ...pt('--', r'no retry off Windows', r'the test title says so, and the module has the guard (vim.fn.has("win32") ~= 1 returns '
        r'the first answer straight away). The assertion itself only checks nil and ENOENT. It does '
        r'not time the call, so a retry loop on Linux would not make this test fail by itself. The '
        r'title states the intent; the code of the module is what enforces it.'),
    ...para('--', r'H.tmpdir creates a fresh spec-XXXXXX directory under XYNO_TEST_TMP or the system temp '
        r'directory, and registers it so that the runner removes it at the end. On macOS and '
        r'Windows it is passed through realpath first, because /var is /private/var on macOS and '
        r'Windows has 8.3 short names.'),
    ...sec(r'the slash tests'),
    ...code('lua', r'tests/fsutil_spec.lua · lines 24-36', r'''
  it("passes nil and plain paths through", function()
    H.is_nil(fs.slash(nil))
    H.eq("/a/b", fs.slash("/a/b"))
  end)

  it("turns backslashes into slashes on Windows only", function()
    if vim.fn.has("win32") == 1 then
      H.eq("C:/a/b", fs.slash("C:\\a\\b"))
    else
      H.eq("a\\b", fs.slash("a\\b"))
    end
  end)
end)
'''),
    ...para('--', r'slash has two behaviours and the spec has one test for each, written so that the same '
        r'file passes on every platform.'),
    ...pt('--', r'nil and plain paths', r'slash(nil) is nil and slash("/a/b") is "/a/b". The nil case matters: lsp_status.lua '
        r'passes c.config and c.config.root_dir, which is nil for a client without a root, and then '
        r'tests the result with not r.'),
    ...pt('--', r'the platform split', r'on Windows the test feeds "C:\\a\\b" and expects "C:/a/b". Elsewhere it feeds "a\\b" and '
        r'expects it back unchanged. That second half is the interesting one. On Linux a backslash '
        r'is a legal file name character, so rewriting it would corrupt a real path. The module '
        r'rewrites only when vim.fn.has("win32") is 1, and the test proves the other branch by '
        r'checking that a backslash survives.'),
    ...para('--', r'Only one of the two branches runs on a given machine. The Windows assertion is written '
        r'but, in this repository, nothing runs it: the README says the Windows guards of the '
        r'original code are kept but there is no evidence for them from this repository.'),
    ...sec(r'design decisions'),
    ...pt('--', r'one file per module is the pattern', r'every module of the plugin has a spec named after it or after the group it belongs to '
        r'(routes_spec, rust-nav_spec, init_spec), so fsutil_spec follows the same shape and uses '
        r'the same helpers.'),
    ...pt('--', r'no mocking of win32', r'the spec does not fake vim.fn.has to run the Windows branch on Linux. The spec tests the branch that runs on the current machine and nothing else.'),
    ...pt('--', r'the tests share nothing', r'each test makes its own directory, so they can run in any order and one failure cannot '
        r'hide the next.'),
    ...sec(r'what a failure here means'),
    ...para('--', r'If the first test fails, an atomic write is no longer atomic or no longer replaces: the '
        r'state file of :RustContext and the crate metadata cache would not update. If the second '
        r'fails with something other than ENOENT, the module is raising or returning another shape, '
        r'and the callers that turn the result into a boolean (crate_meta) or assert on it '
        r'(rust_context) would behave differently. If a slash test fails on Linux, paths containing '
        r'a backslash are being rewritten.'),
    ...sec(r'gaps'),
    ...para('--', r'The Windows retry loop (five attempts, vim.wait(60) between them) is never exercised, '
        r'because no test holds a file open against a rename.'),
    ...para('--', r'rename is only called with a destination that exists or a missing source. A destination '
        r'in a directory that does not exist is not tested.'),
    ...sec(r'where it came from'),
    ...para('--', r'The module was added to xynovim in ff1c8fa on 2026-10-16, in the commit titled Windows '
        r'and macOS: portability fixes, PowerShell bootstrap, portable test runner, OS-aware skips, '
        r'platforms workflow. No xynovim spec mentions fsutil by name. This repository adds the '
        r'direct spec at the first commit of the tests (7c1d2d9, 2026-10-22), when fsutil became '
        r'part of a plugin that has to stand alone.'),
  ],
);
