import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/config/fsutil.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'fsutil.lua — two functions for the places where Windows disagrees'),
    cm('--', r'a retrying rename and a slash normaliser, shared by the Rust modules'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'platform shims: rename-over-open-file and path separators'),
    kv(r'language', r'Lua (Neovim 0.10+ API: vim.uv, vim.fn.has, vim.wait)'),
    kv(r'size', r'33 lines, 1 commit (ff1c8fa, 2026-10-16)'),
    kv(r'exports', r'M.rename(tmp, dest) · M.slash(p)'),
    kv(r'also lives in', r'xyno-rust.nvim as lua/xyno_rust/fsutil.lua, byte-identical'),
    ...sec(r'why this file exists'),
    ...para('--', r'Almost everything written for this configuration was first written and tested on Linux. fsutil.lua appeared in one commit, ff1c8fa on 2026-10-16, whose message is "Windows and macOS: portability fixes, PowerShell bootstrap, portable test runner, OS-aware skips, platforms workflow". That is the moment the config began to be run on Windows and macOS runners, and the file is the place where two classes of Windows-only failure got a single answer instead of being patched at every call site. The header comment says what it is for: "Small file-system helpers whose behaviour differs between platforms." Nothing else is in the file. There are two functions and no state.'),
    ...para('--', r'The file is deliberately tiny. It does not abstract the filesystem. It only covers the two places where the same line of code behaves differently on Windows: renaming a file over another one, and the direction of the slashes in a path.'),
    ...sec(r'M.rename: an atomic replace that survives a busy file'),
    ...para('--', r'Several modules write state with the classic pattern: write a temp file, then rename it over the real one, so a reader never sees half a file. rust_context.lua does this for its per-project state file and crate_meta.lua does it for its cache. The source comment describes the Windows problem: replacing a file that another process holds open fails with a sharing violation, which fails with EPERM, EACCES or EBUSY until the other process lets go. The processes that hold those files open are exactly the ones this config runs all day, rust-analyzer and the editor itself.'),
    ...code('lua', r'lua/config/fsutil.lua · lines 4-21', r'''
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
    ...para('--', r'Read the control flow in order. The first attempt is always a plain vim.uv.fs_rename. If it worked, or if the platform is not Windows, the function returns immediately with exactly what libuv returned, which is true on success or nil plus an error message and error name on failure. So on Linux and macOS the helper costs one function call and changes nothing: a real error (a missing directory, a permission problem) is reported on the first try and is never retried.'),
    ...para('--', r'Only on Windows does it go on. The loop runs up to five more times, and before each attempt it calls vim.wait(60), which blocks for 60 milliseconds while still letting Neovim process events. Five tries at 60 ms is at most 300 ms of extra waiting in the worst case, then the last error is returned unchanged, so the caller still decides what a failure means. The retry is not conditional on the error code even though the comment names the three codes: any failure on Windows gets the same five-attempt treatment. That is a simplification and it is a reasonable one, since the cost of retrying a genuinely hopeless rename is a third of a second.'),
    ...pt('--', r'return ok', r'inside the loop the success path returns only ok, not three values. Callers that care about the extra values only care on failure, so this is harmless, and the doc comment’s promise (returns what fs_rename returns) holds for failures.'),
    ...pt('--', r'vim.wait, not a timer', r'the callers are synchronous code paths (the assert in rust_context.lua wraps the call), so the helper has to block until the answer is known. vim.wait is the way to block without freezing the UI redraw loop.'),
    blank,
    ...sec(r'M.slash: one separator for all comparisons'),
    ...code('lua', r'lua/config/fsutil.lua · lines 23-31', r'''
--- Forward slashes (Windows only; elsewhere the path is returned untouched):
--- buffer names, cwd and LSP roots come back with backslashes there, while the
--- code compares prefixes and matches "/.cargo/registry/" style fragments.
function M.slash(p)
  if p and vim.fn.has("win32") == 1 then
    return (p:gsub("\\", "/"))
  end
  return p
end'''),
    ...para('--', r'This one is about string comparison, not about opening files. Windows accepts forward slashes almost everywhere, so a normalised path still works for I/O. What breaks on Windows is code that does string work on paths coming from three different sources: nvim_buf_get_name, the working directory, and the root_dir an LSP client reports. They can use backslashes while the Lua code looks for fragments like /.cargo/registry/ or checks whether one path begins with another. Normalising once at the boundary makes those prefix and substring checks the same code on every platform.'),
    ...para('--', r'Three details are worth noticing. First, it accepts nil and returns nil (the guard is if p and ...), because callers pass c.config and c.config.root_dir, which may well be nil for a client without a root. Second, the parentheses around p:gsub(...) matter: gsub returns two values, the string and the substitution count, and the extra parentheses truncate that to one so the function returns a clean string. Third, on non-Windows platforms the input is returned as it is, even if it contains a literal backslash, which is a legal character in a Unix file name and must not be rewritten.'),
    ...sec(r'who calls it'),
    ...pt('--', r'rename', r'lua/config/rust_context.lua line 31 (assert(require("config.fsutil").rename(tmp, state_file))), lua/config/crate_meta.lua line 136, crate_features.lua line 1356, import_engine.lua line 120 and macro_tools.lua line 2181, all of them temp-file-then-rename writers.'),
    ...pt('--', r'slash', r'lua/config/lsp_status.lua lines 145, 200 and 212 (client root directories and the buffer name), lua/config/crate_add.lua line 148, lua/config/rust_new.lua line 666 (the parent directory of a new project) and lua/plugins/supply-chain.lua line 46 (matching .github/workflows).'),
    ...sec(r'design decisions and trade-offs'),
    ...pt('--', r'a module of its own', r'both helpers could have been local functions in the file that needs them. Instead they are shared by many modules in the config: rust_context, crate_meta, crate_features, import_engine and macro_tools use rename; lsp_status, crate_add, rust_new and the supply-chain plugin spec use slash. One place to tune the retry count matters more than the 33 lines of duplication it saves.'),
    ...pt('--', r'detect at call time', r'vim.fn.has("win32") is evaluated on every call rather than cached in a module-level constant. It is cheap, and it means a test can exercise both branches without reloading the module.'),
    ...pt('--', r'no attempt at atomicity beyond rename', r'if all six attempts fail the caller gets the error. There is no fallback to copy-and-delete, because that would reintroduce exactly the torn-read problem the temp-file-plus-rename pattern exists to avoid.'),
    ...pt('--', r'ASCII only, no normalising of case or drive letters', r'slash does not lower-case a drive letter or resolve symlinks. That is a separate concern, handled elsewhere: the commit messages of 9641d08 (2026-10-16) and 6524272 (2026-10-21) mention drive-letter case and canonical roots in rust_context, not in this file.'),
    ...sec(r'the same file in xyno-rust.nvim'),
    ...para('--', r'On 2026-10-22 the Rust tooling modules were extracted into standalone plugin repositories. This file is part of that move: xyno-rust.nvim carries it as lua/xyno_rust/fsutil.lua. A diff of the two files is empty, they are byte-identical. The consumers on the plugin side require it as xyno_rust.fsutil, the consumers in this config still require config.fsutil. The configuration here has not yet been switched over to load the plugin copies, so both exist side by side.'),
    ...sec(r'how it is tested'),
    ...para('--', r'There is no spec file named for fsutil. Its behaviour is covered indirectly: the platforms workflow added in the same commit runs the specs on Windows and macOS, and the modules that call it are covered by their own specs, for example tests/rust-context_spec.lua for the state file. A search of tests/ for fsutil or slash finds no direct unit test, so the retry loop itself has no dedicated assertion; this page reports that rather than guessing which spec covers it.'),
    ...sec(r'history'),
    ...pt('--', r'ff1c8fa · 2026-10-16', r'Windows and macOS: portability fixes, PowerShell bootstrap, portable test runner, OS-aware skips, platforms workflow. The only commit that touches this file: it was created in full here and has not changed since.'),
    ...pt('--', r'9641d08 · 2026-10-16 and 6524272 · 2026-10-21', r'follow-up fixes from the first full Windows and macOS runs; they touched rust_context.lua (drive letter in canonical roots, the .exe suffix) rather than this file, so the two helpers needed no change.'),
  ],
);
