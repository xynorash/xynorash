import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/coverage.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'coverage.lua — Run with Coverage, as a gutter and a key'),
    cm('--', r'cargo llvm-cov, an lcov file, and a replaced Rust backend'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'plugin spec for andythigpen/nvim-coverage plus the command that produces the data'),
    kv(r'language', r'Lua, a lazy.nvim plugin spec with an inline key function and a config function'),
    kv(r'size', r'82 lines, 6 commits (81e0650 to 0247401, 2026-10-09 to 2026-10-22)'),
    kv(r'keys', r'<leader>tc run and show, <leader>tg toggle signs, <leader>tG summary'),
    kv(r'needs', r'cargo-llvm-cov (cargo-nextest optional), config.rust_context'),
    ...sec(r'why this file exists'),
    ...para('--',
        r'The header gives the idea in one line: code coverage in the gutter, the same idea as "Run '
        r'with Coverage" in the JetBrains IDEs (reworded in 0247401 from a specific IDE). Covered '
        r'lines get one sign and uncovered lines another, so a test run turns into a map of what the '
        r'tests never touch.'),
    blank,
    ...para('--',
        r'The header also fixes a policy: coverage runs on demand only, never per autosave. An '
        r'instrumented build is a separate target tree and takes as long as a full test run. A key '
        r'that the user presses is therefore the only trigger, and the plugin is lazy on its '
        r'commands and keys.'),
    ...sec(r'the shape of the file'),
    ...para('--',
        r'The file has three parts. The keys table holds the command that runs cargo and loads the '
        r'result. The opts table configures nvim-coverage. The config function replaces the plugin’s '
        r'Rust language module, because the stock one expects a different tool. Read in that order, '
        r'each part answers a question the previous one raises.'),
    ...sec(r'lazy loading and keys'),
    ...code('lua', r'lua/plugins/coverage.lua · lines 6-10', r'''
return {
  "andythigpen/nvim-coverage",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "Coverage", "CoverageLoad", "CoverageShow", "CoverageHide", "CoverageToggle", "CoverageSummary", "CoverageClear" },
  keys = {'''),
    blank,
    ...para('--',
        r'The seven commands that nvim-coverage defines are listed, so lazy.nvim creates stubs for '
        r'them and loads the plugin on the first use of any. plenary.nvim is a declared dependency, '
        r'because nvim-coverage uses it for paths and for its summary window. The keys come next: '
        r'<leader>tc, then two small ones at lines 47 and 48.'),
    ...sec(r'the run command, <leader>tc'),
    ...code('lua', r'lua/plugins/coverage.lua · lines 11-29', r'''
    {
      "<leader>tc",
      function()
        local root = require("config.rust_context").root()
        if not root then
          return vim.notify("no Cargo.toml found", vim.log.levels.WARN)
        end
        local nextest = vim.fn.executable("cargo-nextest") == 1
        local cmd = { "cargo", "llvm-cov" }
        if nextest then
          table.insert(cmd, "nextest")
        end
        -- --ignore-run-fail: without it one failing test aborts the run and no
        -- lcov is written (it cannot be combined with --no-fail-fast).
        vim.list_extend(cmd, { "--workspace", "--ignore-run-fail", "--lcov", "--output-path", "target/lcov.info" })
        -- same features/target as the diagnostics (:RustContext)
        local rc = require("config.rust_context")
        vim.list_extend(cmd, rc.cargo_flags(rc.get(root)))
        vim.notify("coverage: running " .. table.concat(cmd, " "))'''),
    blank,
    ...para('--',
        r'The function starts by asking config.rust_context for the workspace root. If there is '
        r'none, it notifies "no Cargo.toml found" at warning level and stops. This is the guard that '
        r'keeps the key harmless in a non-Rust buffer.'),
    blank,
    ...para('--',
        r'The command is built as a list and never as a shell string. It starts with cargo llvm-cov. '
        r'If cargo-nextest is executable, nextest is inserted after llvm-cov, giving cargo llvm-cov '
        r'nextest, which uses nextest as the test runner under the instrumentation. Without nextest '
        r'the plain cargo llvm-cov runs cargo test, as the header says.'),
    blank,
    ...para('--',
        r'Line 25 adds the common arguments: --workspace, --ignore-run-fail, --lcov, --output-path '
        r'and target/lcov.info. The comment above it explains the one that is not obvious. '
        r'--ignore-run-fail keeps one failing test from aborting the run so that the lcov file is '
        r'still written. The comment adds that it cannot be combined with --no-fail-fast. The '
        r'behaviour was added in commit 8779a6e (2026-10-12, "coverage with failing tests").'),
    blank,
    ...para('--',
        r'Lines 26 to 28 reuse the diagnostics context: the same features and target as '
        r':RustContext, through rc.cargo_flags(rc.get(root)). With the default context that is '
        r'--all-features, so coverage measures the same code that clippy and the tests see. The '
        r'tests assert this: "default context: --all-features; nextest when installed", and a stored '
        r'context with features, no default and a target is passed on.'),
    ...sec(r'running it without blocking the editor'),
    ...code('lua', r'lua/plugins/coverage.lua · lines 30-46', r'''
        vim.system(cmd, { cwd = root, text = true }, function(o)
          vim.schedule(function()
            if o.code ~= 0 then
              return vim.notify("coverage run failed:\n" .. (o.stderr or ""):sub(-600), vim.log.levels.ERROR)
            end
            vim.cmd("CoverageLoad")
            vim.cmd("CoverageShow")
            vim.notify("coverage loaded (" .. root .. "/target/lcov.info)")
            -- cargo test: "1 failed;", nextest: "1 failed,"
            if (o.stderr or ""):find("[1-9]%d* failed") or (o.stdout or ""):find("[1-9]%d* failed") then
              vim.notify("coverage: some tests FAILED (the report is still written)", vim.log.levels.WARN)
            end
          end)
        end)
      end,
      desc = "Coverage: run + show",
    },'''),
    blank,
    ...para('--',
        r'vim.system runs the process asynchronously with the root as cwd and text output. Its '
        r'callback is not allowed to call most Neovim functions, so the whole body is wrapped in '
        r'vim.schedule. A non-zero exit code produces an error notification that carries the last '
        r'600 characters of stderr: the tail is where cargo prints the reason, and a full build log '
        r'would flood the message area.'),
    blank,
    ...para('--',
        r'On success the function runs two commands in order: CoverageLoad to read the lcov file and '
        r'CoverageShow to draw signs. It tells the user where the file went. Then comes a last '
        r'check: the stderr and stdout are searched for a pattern [1-9]%d* failed. The comment on '
        r'line 38 documents the two formats it must match: cargo test prints "1 failed;" and nextest '
        r'prints "1 failed,". If it matches, a warning says "some tests FAILED (the report is still '
        r'written)".'),
    blank,
    ...para('--',
        r'That warning is the other half of --ignore-run-fail. Ignoring a failed run would otherwise '
        r'make a red suite look like a clean coverage report. The pattern needs a non-zero digit, so '
        r'"0 failed" never triggers it.'),
    ...sec(r'the other keys'),
    ...code('lua', r'lua/plugins/coverage.lua · lines 47-49', r'''
    { "<leader>tg", "<cmd>CoverageToggle<cr>", desc = "Coverage: toggle signs" },
    { "<leader>tG", "<cmd>CoverageSummary<cr>", desc = "Coverage: summary" },
  },'''),
    blank,
    ...para('--',
        r'<leader>tg toggles the signs, and <leader>tG opens nvim-coverage’s summary table. Both are '
        r'plain commands because there is nothing to compute. Together with <leader>tc they form the '
        r'group that the neotest keys also live in; editing-ui.lua names that group "test" for '
        r'which-key.'),
    ...sec(r'options'),
    ...code('lua', r'lua/plugins/coverage.lua · lines 50-64', r'''
  opts = {
    auto_reload = true,
    commands = true,
    -- Summary float: plenary's default winblend = 15 let the code show
    -- through the table; opaque and smaller (140x28 was most of the screen).
    summary = { window = { winblend = 0 }, width_percentage = 0.6, height_percentage = 0.4 },
    -- the stock rust backend shells out to grcov; read cargo-llvm-cov's lcov instead
    lang = {
      rust = {
        coverage_file = function()
          return (require("config.rust_context").root() or vim.uv.cwd()) .. "/target/lcov.info"
        end,
      },
    },
  },'''),
    blank,
    ...pt('--', r'auto_reload = true',
        r'the signs follow the lcov file when it changes, so a rerun of <leader>tc refreshes an open '
        r'buffer.'),
    ...pt('--', r'commands = true',
        r'the user commands are defined (the lazy spec lists them as triggers).'),
    ...pt('--', r'summary window',
        r'the comment says plenary’s default winblend of 15 let the code show through the table, so '
        r'the summary is opaque (winblend = 0), at 0.6 of the width and 0.4 of the height. The old '
        r'140x28 window was most of the screen.'),
    ...pt('--', r'lang.rust.coverage_file',
        r'a function returning the workspace root plus /target/lcov.info. The comment states why: '
        r'the stock rust backend shells out to grcov, and this setup reads the lcov that '
        r'cargo-llvm-cov writes instead. The root comes from config.rust_context, with the current '
        r'directory as a fallback.'),
    ...sec(r'replacing the Rust backend'),
    ...code('lua', r'lua/plugins/coverage.lua · lines 65-81', r'''
  config = function(_, opts)
    local common = require("coverage.languages.common")
    local Path = require("plenary.path")
    local util = require("coverage.util")
    package.loaded["coverage.languages.rust"] = {
      sign_list = common.sign_list,
      summary = common.summary,
      load = function(callback)
        local p = Path:new(util.get_coverage_file(require("coverage.config").opts.lang.rust.coverage_file))
        if not p:exists() then
          return vim.notify("No coverage file (target/lcov.info); run <leader>tc", vim.log.levels.INFO)
        end
        callback(util.lcov_to_table(p))
      end,
    }
    require("coverage").setup(opts)
  end,'''),
    blank,
    ...para('--',
        r'nvim-coverage selects a backend by language through require("coverage.languages.rust"). '
        r'The config function pre-fills package.loaded for that module name with a small table of '
        r'its own, so the plugin never loads its grcov-based file. The table borrows sign_list and '
        r'summary from coverage.languages.common, so the drawing code is the plugin’s and only the '
        r'loading step is replaced.'),
    blank,
    ...para('--',
        r'load is the new piece. It resolves the file with util.get_coverage_file on the configured '
        r'coverage_file function, checks that it exists, and if not tells the user "No coverage file '
        r'(target/lcov.info); run <leader>tc" at info level, a hint instead of an error. If it '
        r'exists, util.lcov_to_table converts the lcov file into the table the signs are drawn from, '
        r'and the plugin’s own setup is called with the options.'),
    blank,
    ...para('--',
        r'The trade-off is visible: the file reaches into a plugin’s internals (the module name and '
        r'three helper functions). It is a small, contained dependency on nvim-coverage’s layout, '
        r'and the spec pins down the visible parts (the keys and the flags), not the internals.'),
    ...sec(r'the shared dependency: rust_context'),
    ...para('--',
        r'Coverage, the debugger and the task runner all ask the same module which workspace root '
        r'and which cargo flags to use. In this repo that module is lua/config/rust_context.lua (373 '
        r'lines). On 2026-10-22 the Rust tooling was extracted into '
        r'~/projects/xyno-plugins/xyno-rust.nvim, which has its own lua/xyno_rust/rust_context.lua '
        r'(381 lines).'),
    blank,
    ...para('--',
        r'The two files differ in a few places. The extracted version requires xyno_rust.fsutil '
        r'instead of config.fsutil for its atomic rename, loads Snacks through xyno_rust.deps and '
        r'returns early when Snacks is missing, and its setup takes an opts table where commands = '
        r'false skips defining :RustContext. The cargo_flags function that coverage.lua calls is the '
        r'same in both. The plugin has not yet been rewired in this repo; coverage.lua still '
        r'requires config.rust_context.'),
    ...sec(r'how it is tested'),
    ...pt('--', r'tests/dap-neotest-coverage_spec.lua, describe "coverage honours :RustContext"',
        r'line 1076. It loads this file with dofile, takes the <leader>tc function, stubs vim.system '
        r'and captures the command and the cwd. Line 1117: the default context gives --all-features '
        r'and nextest when installed. Line 1130: a stored context is passed on. Line 1140: the '
        r':RustTools coverage entry carries the same flags. Line 1168: the three keys are '
        r'registered.'),
    ...pt('--', r'tests/rust-tasks-tools_spec.lua',
        r'mentions the ignore-run-fail and lcov arguments for the task list (cargo llvm-cov '
        r'--workspace --ignore-run-fail --summary-only is the "coverage report" task in '
        r'rust_tasks.lua line 177).'),
    ...sec(r'history'),
    ...pt('--', r'81e0650, 107ed0f (2026-10-09, "wip-s9a", "wip-s9e")',
        r'the file is created as part of roadmap step 9 (supply chain, coverage, profiling), and the '
        r'HISTORY file records this as done on 2026-10-09.'),
    ...pt('--', r'be73b6c (2026-10-12)',
        r'"default all-features context for tasks/coverage".'),
    ...pt('--', r'8779a6e (2026-10-12)',
        r'"coverage with failing tests".'),
    ...pt('--', r'99acd7e (2026-10-13)',
        r'"Batch 4: editing and UI" touched the file; its message does not say which lines, so none '
        r'are attributed.'),
    ...pt('--', r'0247401 (2026-10-22)',
        r'the header reworded to "same idea as Run with Coverage in the JetBrains IDEs".'),
  ],
);
