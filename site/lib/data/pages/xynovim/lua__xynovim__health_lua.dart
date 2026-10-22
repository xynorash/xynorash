import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/xynovim/health.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'lua/xynovim/health.lua — :checkhealth xynovim'),
    cm('--', r'23 external tools, 3 rustup checks, one honest answer'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'health check for everything the config shells out to'),
    kv(r'language', r'Lua; defines M.check() for :checkhealth xynovim'),
    kv(r'size', r'138 lines, 8 commits (2026-10-09 to 2026-10-16)'),
    kv(r'sections', r'"xynovim: external tools" and "xynovim: rust toolchain"'),
    kv(r'tested by', r'tests/health-bootstrap-ci_spec.lua (vim.health stubbed)'),
    ...sec(r'why this file exists'),
    ...para('--', r'A Neovim configuration for Rust leans on a long list of programs that are not Neovim: cargo and rust-analyzer, bacon-ls for clippy, codelldb for debugging, cargo-nextest for tests, a C compiler for tree-sitter, git and curl for the plugin manager. When one is missing the symptom is rarely "tool X is missing". It is a key that does nothing, or a feature that silently falls back. Neovim has a standard place for this problem: any plugin that provides lua/<name>/health.lua with a check() function gets a :checkhealth <name> page. This file is that page, for the name xynovim.'),
    ...para('--', r'Its header says what the page is: the external tools the Rust workflow in this config relies on, and what each one is used for. The second half of that sentence is the design. Every row says why the tool is there, so a missing tool arrives with its purpose and the key that needs it.'),
    ...sec(r'the table of tools'),
    ...code('lua', r'lua/xynovim/health.lua · lines 31-44', r'''
-- { binary, purpose, check Mason too, version args, severity when missing }
local TOOLS = {
  -- what scripts/bootstrap.sh and lazy/Mason need to bring the config up
  { "git", "plugin manager (lazy.nvim clones and checks out the lockfile)", false, { "--version" }, "error" },
  { "curl", "Mason downloads, tree-sitter parsers", false, { "--version" }, "warn" },
  { "tar", "Mason and tree-sitter archives", false, { "--version" }, "warn" },
  { "unzip", "Mason package archives", false, { "-v" }, "warn" },
  { "gzip", "Mason unpacks .gz archives", false, { "--version" }, "warn" },
  { "gcc", "compiles tree-sitter parsers", false, { "--version" }, "warn" },
  { "tree-sitter", "CLI nvim-treesitter builds parsers with (Mason supplies it as tree-sitter-cli)", true, { "--version" }, "warn" },
  { "node", "Mason's npm tools and yaml-language-server", false, { "--version" }, "warn" },
  { "cargo", "builds, clippy, tests (every Rust key)", false, { "--version" }, "error" },
  { "rust-analyzer", "language server (rustaceanvim)", false, { "--version" }, "error" },
  { "bacon-ls", "clippy diagnostics tier", true, { "--version" }, "error" },'''),
    ...para('--', r'The table is the data and M.check() is the loop. The first comment names the five fields of a row: the binary, the purpose, whether Mason’s bin directory should be searched too, the arguments that print a version, and the severity when the tool is missing. Keeping it as a table of rows with positional fields is a deliberate economy: adding a tool is one line, and the spec can count them. The spec does count: "has 23 entries with the documented severities".'),
    blank,
    ...pt('--', r'three tiers of severity', r'git, cargo, rust-analyzer and bacon-ls are errors: without them the config or its Rust workflow does not work. Everything else is a warning, because the editor still starts and the missing feature degrades. The tiers are the same words that vim.health uses (error, warn), so the code can call vim.health[level](...) with the field directly.'),
    ...pt('--', r'Mason or PATH', r'tools such as bacon-ls, codelldb, taplo, wgsl-analyzer and tree-sitter are installed by Mason, not by the system. For those rows the third field is true and find() looks in stdpath("data")/mason/bin first. The others, like cargo-nextest or lazygit, are expected on PATH, so Mason is not consulted.'),
    ...pt('--', r'purpose strings with keys', r'some purposes point at features: "(every Rust key)" for cargo, "(<leader>gg)" for lazygit, "(<leader>tc)" for coverage. When the tool is missing, that text is what tells the user which key will not work.'),
    ...pt('--', r'a few rows describe the bootstrap', r'git, curl, tar, unzip, gzip, gcc, node and npm are not Rust tools. The comment above them says they are "what scripts/bootstrap.sh and lazy/Mason need to bring the config up". Most were added on 2026-10-13 with the fresh-install work (commit da1d829); gzip and tree-sitter followed in the two rounds after.'),
    blank,
    ...code('lua', r'lua/xynovim/health.lua · lines 45-57', r'''
  { "codelldb", "debugger (dap.core)", true, nil, "warn" },
  { "taplo", "Cargo.toml LSP/formatter (lang.toml)", true, { "--version" }, "warn" },
  { "wgsl-analyzer", "WGSL / Bevy shader LSP (plugins/domain.lua)", true, { "--version" }, "warn" },
  { "cargo-nextest", "test runner (neotest, :RustTargets, coverage)", false, { "--version" }, "warn" },
  { "cargo-deny", "supply-chain diagnostics (supply-chain.lua)", false, { "--version" }, "warn" },
  { "cargo-expand", "full macro expansion (cargo expand; <leader>rm covers the rest)", false, { "--version" }, "warn" },
  { "lazygit", "git UI (<leader>gg)", false, { "--version" }, "warn" },
  { "delta", "diff pager (git config)", false, { "--version" }, "warn" },
  { "mold", "fast linker (~/.cargo/config.toml)", false, { "--version" }, "warn" },
  { "clang", "linker driver for mold (~/.cargo/config.toml)", false, { "--version" }, "warn" },
  { "npm", "Mason installs markdownlint-cli2, markdown-toc, yaml-language-server", false, { "--version" }, "warn" },
  { "bwrap", "bubblewrap sandbox for the 99 agent (Linux only; without it 99 refuses to run unless vim.g.xynovim_99_allow_unsandboxed = true)", false, { "--version" }, "warn" },
}'''),
    ...para('--', r'Notice codelldb: its version-args field is nil, because the debug adapter has no useful --version, so the loop only checks that the binary exists. And the last row records a security decision. The bwrap entry, rewritten on 2026-10-16 (commit 440d781, "Agent sandbox fails closed when no sandbox backend is available"), now says that without bubblewrap the 99 agent refuses to run unless a global is set to allow it. The health page is where a user learns that the agent integration is off and why.'),
    ...sec(r'finding a binary'),
    ...code('lua', r'lua/xynovim/health.lua · lines 5-29', r'''
local function first_line(cmd)
  local ok, o = pcall(function()
    return vim.system(cmd, { text = true }):wait(5000)
  end)
  if not ok or o.code ~= 0 then
    return nil
  end
  return vim.split(o.stdout ~= "" and o.stdout or o.stderr, "\n")[1]:sub(1, 80)
end

--- Mason's bin dir first (installed by `ensure_installed`), then PATH.
local function find(bin, mason)
  if mason then
    for _, ext in ipairs(vim.fn.has("win32") == 1 and { "", ".cmd", ".exe" } or { "" }) do
      local p = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", bin .. ext)
      if vim.fn.executable(p) == 1 then
        return p, "Mason"
      end
    end
  end
  local p = vim.fn.exepath(bin)
  if p ~= "" then
    return p, "PATH"
  end
end'''),
    ...para('--', r'Two small helpers carry the robustness of the page. first_line() runs a command and returns the first line of its output cut to 80 characters, or nil on failure. It is wrapped in pcall because vim.system itself can throw if the executable cannot be spawned, and it waits at most 5 seconds so a hanging program cannot freeze :checkhealth. It prefers stdout and falls back to stderr, which matters because some tools print their version to stderr.'),
    ...para('--', r'find() returns the path and where it was found, so the report can say "(Mason)" or "(PATH)". The Mason branch was rewritten on 2026-10-16 for Windows (commit ff1c8fa). The earlier version built the path with string concatenation and a slash; the new one uses vim.fs.joinpath and, on Windows, tries the bare name, then .cmd, then .exe, because Mason there creates cmd shims. Returning nothing, implicitly, is the "not found" case.'),
    ...sec(r'the loop and its three outcomes'),
    ...code('lua', r'lua/xynovim/health.lua · lines 83-98', r'''
    local v = path and vargs and first_line(vim.list_extend({ path }, vargs))
    if path and vargs and not v then
      -- e.g. rustup's rust-analyzer proxy when the component is not installed
      vim.health[level](
        ("%s found (%s: %s) but `%s` fails: %s"):format(bin, where, path, table.concat(vargs, " "), purpose),
        bin == "rust-analyzer" and "rustup component add rust-analyzer" or "reinstall it"
      )
    elseif path then
      vim.health.ok(("%s (%s)%s: %s"):format(bin, where, v and (" " .. v) or "", purpose))
    else
      local hint = mason and "install it with :Mason or put it on PATH" or "install it and put it on PATH"
      if bin == "rust-analyzer" then
        hint = "rustup component add rust-analyzer (or put a rust-analyzer binary on PATH)"
      end
      vim.health[level](("%s not found: %s"):format(bin, purpose), hint)
    end'''),
    ...para('--', r'There are three outcomes, not two, and the middle one is the clever one. Found and runs: an ok line with the path source, the version line and the purpose. Not found: the severity from the table, the purpose, and a hint that depends on whether Mason can supply it. But there is a third case, found but failing. The comment gives the example: rustup installs a rust-analyzer proxy on PATH even when the component is not installed, and running it prints an error and exits non-zero. A check that only tested whether the binary exists would report a green line for a tool that does not work. Running --version and looking at the exit code catches it, and the advice for that exact case is the rustup command.'),
    ...para('--', r'The spec has a describe block for each outcome: found tools, broken tools and a minimal PATH. It uses a fake PATH directory of shell stubs, with vim.health replaced by a recorder, so it can assert the exact message and advice strings, such as "install it with :Mason or put it on PATH" for Mason-supplied tools and "install it and put it on PATH" for the rest.'),
    ...sec(r'Windows'),
    ...code('lua', r'lua/xynovim/health.lua · lines 59-82', r'''
-- Not needed (or not available) on Windows: Mason there unpacks with PowerShell / tar,
-- mold is a Linux linker, bubblewrap is Linux only (99 then refuses to run).
local WIN_SKIP = { unzip = true, gzip = true, mold = true, clang = true, bwrap = true }
-- A C compiler for tree-sitter parsers: gcc, or any of these on Windows.
local WIN_CC = { "cc", "clang", "cl", "zig" }

function M.check()
  vim.health.start("xynovim: external tools")
  local win = vim.fn.has("win32") == 1
  for _, t in ipairs(TOOLS) do
    local bin, purpose, mason, vargs, level = t[1], t[2], t[3], t[4], t[5]
    local path, where = find(bin, mason)
    if win and bin == "gcc" and not path then
      for _, cc in ipairs(WIN_CC) do
        if vim.fn.exepath(cc) ~= "" then
          bin, path, where = cc, vim.fn.exepath(cc), "PATH"
          vargs = nil
          break
        end
      end
    end
    if win and WIN_SKIP[bin] then
      goto continue
    end'''),
    ...para('--', r'Commit ff1c8fa (2026-10-16) made the page portable. Rows that make no sense on Windows are skipped with a goto continue (a Lua idiom, since the language has no continue statement), and a C compiler is looked for under several names: gcc is the row, but on Windows the first of cc, clang, cl or zig that is on PATH stands in for it, and since compilers like cl do not take --version, vargs is cleared so only existence is reported. The spec has a Windows-aware skip for these.'),
    ...para('--', r'There is a bug in the substitution, and it is easy to see once you read the two blocks together. When gcc is missing on Windows and clang is the compiler found, the code rewrites bin to "clang". The next statement then asks WIN_SKIP[bin], and clang is in that table, because the same name is also the linker-driver row that Windows does not need. The result is that the loop jumps to the label before it reports anything, and the C compiler that was found is never mentioned. The case where no compiler is found at all still prints the gcc warning, so the page does not lie, it only omits a positive finding. This comes from reading lines 74 and 80, and was not run on Windows.'),
    ...sec(r'the Rust toolchain section'),
    ...code('lua', r'lua/xynovim/health.lua · lines 102-123', r'''
  vim.health.start("xynovim: rust toolchain")
  if vim.fn.executable("rustup") == 0 then
    vim.health.warn("rustup not found", "components cannot be checked; install rustup")
    return
  end
  local out = vim.system({ "rustup", "component", "list", "--toolchain", "stable", "--installed" }, { text = true })
    :wait(10000)
  if out.code ~= 0 then
    vim.health.warn("stable toolchain not installed", "rustup toolchain install stable")
    return
  end
  local comps = out.stdout
  for _, c in ipairs({
    { "clippy", "clippy", "clippy tier and rust-analyzer lints" },
    { "llvm%-tools", "llvm-tools", "cargo-llvm-cov coverage (<leader>tc)" },
  }) do
    if comps:find("\n" .. c[1]) or comps:find("^" .. c[1]) then
      vim.health.ok(("stable has %s: %s"):format(c[2], c[3]))
    else
      vim.health.warn(("stable lacks %s: %s"):format(c[2], c[3]), "rustup component add --toolchain stable " .. c[2])
    end
  end'''),
    ...para('--', r'The second section is about rustup components, which no PATH lookup can see: clippy and llvm-tools are installed into a toolchain, not on their own. The code asks rustup for the installed components of stable, early-returns with a warning if rustup or the toolchain is missing, and then looks for each component name at the start of a line. The pattern is written twice because a Lua find with "\n" cannot match the first line of the output, so the beginning of the string is tested separately. The first element of each row is a Lua pattern (llvm%-tools escapes the hyphen), the second is the name used in messages and in the fix command.'),
    ...code('lua', r'lua/xynovim/health.lua · lines 124-138', r'''
  -- :RustContext's target step lists the installed targets: web/WASM crates need this one
  local targets = vim.system({ "rustup", "target", "list", "--toolchain", "stable", "--installed" }, { text = true }):wait(10000)
  if targets.code == 0 then
    if (targets.stdout or ""):find("wasm32-unknown-unknown", 1, true) then
      vim.health.ok("stable has the wasm32-unknown-unknown target: web/WASM crates (:RustContext target)")
    else
      vim.health.warn(
        "stable lacks the wasm32-unknown-unknown target: web/WASM crates (:RustContext target)",
        "rustup target add --toolchain stable wasm32-unknown-unknown"
      )
    end
  end
end

return M'''),
    ...para('--', r'The last check follows a feature. :RustContext lists installed targets for web and WASM crates, and one of them, wasm32-unknown-unknown, is needed to build for the browser. The check is quieter than the others: if rustup cannot list targets at all, it says nothing (the spec: "nothing when rustup cannot list"). The find call passes true as its fourth argument, a plain-text search, so the hyphens and dots in the target name are not treated as pattern characters.'),
    ...sec(r'what is not here'),
    ...para('--', r'On 2026-10-22 the Rust tooling modules (rust navigation, crate metadata, supply-chain checks, routes, the sandbox and more) were extracted to standalone plugin repositories under ~/projects/xyno-plugins: xyno-clipboard, xyno-crates, xyno-guard, xyno-history, xyno-imports, xyno-macros, xyno-new, xyno-rust and xyno-sandbox. This health file did not move with them. It still lives in the configuration, still checks the same 23 tools and still names this repository’s files in some purposes (plugins/domain.lua, supply-chain.lua). The extracted plugins have no health module of their own that I could find under their lua directories, apart from references to health in xyno-macros tools. So :checkhealth xynovim remains the one page for the whole machine.'),
    ...sec(r'history'),
    ...pt('--', r'bdd0225, f11cb84 (2026-10-09)', r'"Roadmap step 11 wip" and the finished step: the file is created in the roadmap step that also brought the statusline, UX, health and CI work. The original row set is not reproduced here.'),
    ...pt('--', r'ac38272 (2026-10-09)', r'"Fix review findings: sandbox hardening, local history, 99 guard, npm, README accuracy". The npm row is added.'),
    ...pt('--', r'da1d829 (2026-10-13)', r'"Batch 5: fresh install, CI and docs": the bootstrap prerequisites (git, curl, tar, unzip, gcc, node, cargo) are added to the table and the found-but-failing outcome is introduced.'),
    ...pt('--', r'98c9bb4, a3d33c8 (2026-10-13)', r'round 1 adds gzip, wgsl-analyzer, cargo-expand and the wasm32 target check; round 2 adds the tree-sitter row.'),
    ...pt('--', r'440d781 (2026-10-16)', r'the bwrap row learns that the 99 agent fails closed.'),
    ...pt('--', r'ff1c8fa (2026-10-16)', r'Windows and macOS: Mason shims, vim.fs.joinpath, WIN_SKIP and WIN_CC.'),
    ...sec(r'tests'),
    ...para('--', r'tests/health-bootstrap-ci_spec.lua tests this file with vim.health stubbed. It runs a real :checkhealth xynovim once and rejects "Failed to run healthcheck". Then it runs M.check() with a controlled PATH made of stub scripts and a fresh data directory: all tools missing (23 records with the documented severities and exact hints), tools found, tools that exist but fail, a minimal PATH, and the rustup section including the argument log that proves the two exact rustup invocations. A separate block, "README prerequisites vs health TOOLS and bootstrap", keeps the documentation, the script and this table in agreement.'),
  ],
);
