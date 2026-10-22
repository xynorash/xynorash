import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/supply-chain.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'supply-chain.lua — advisories, unused dependencies and CI lint as diagnostics'),
    cm('--', r'cargo-deny, cargo-machete, actionlint and zizmor, wired into nvim-lint'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'nvim-lint sources for dependency advisories, unused crates and GitHub workflow problems'),
    kv(r'language', r'Lua, one plugin spec with two hand-written linters and their parsers'),
    kv(r'size', r'207 lines, 12 commits (81e0650, 2026-10-09 to 0247401, 2026-10-22)'),
    kv(r'runs on', r'the LazyVim lint events: save, read, InsertLeave'),
    kv(r'tools', r'cargo-deny, cargo-machete, actionlint, zizmor'),
    kv(r'roadmap', r'step 9'),
    ...sec(r'why this file exists'),
    ...para('--',
        r'The header lists what it covers: supply-chain and CI diagnostics as nvim-lint sources, '
        r'namely advisory scanning, unused dependencies and workflow lint. The mapping is short. '
        r'Cargo.toml and Cargo.lock go to cargo-deny (advisories and bans) and cargo-machete (unused '
        r'dependencies, manifest only). Files under .github/workflows go to actionlint and zizmor.'),
    blank,
    ...para('--',
        r'The idea is that a problem in a manifest should look like any other problem in the editor: '
        r'a line with a diagnostic, in the same list as rust-analyzer errors. A vulnerability notice '
        r'on the line of the dependency that causes it is more useful than the same text in a '
        r'terminal that nobody reads. The last paragraph of the header says the cost model: '
        r'everything is skipped unless its precondition holds, so ordinary projects pay nothing.'),
    ...sec(r'small helpers'),
    ...code('lua', r'lua/plugins/supply-chain.lua · lines 7-13', r'''
local function basename(f)
  return vim.fs.basename(f)
end

local function manifest_dir(file)
  return vim.fs.dirname(file)
end'''),
    blank,
    ...para('--',
        r'basename and manifest_dir are one-line wrappers over vim.fs. The linters need both many '
        r'times, once to decide whether to run (the file name) and once to decide where (the '
        r'directory that cargo or cargo-machete is pointed at).'),
    ...sec(r'finding the line of a dependency'),
    ...code('lua', r'lua/plugins/supply-chain.lua · lines 15-24', r'''
--- Line of `name = ...` / `name.workspace = true` / `[dependencies.name]` in a Cargo.toml buffer (0-based), else 0.
local function dep_line(bufnr, name)
  local esc = vim.pesc(name)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if l:match("^%s*" .. esc .. "%s*[.=]") or l:match('^%s*"' .. esc .. '"%s*[.=]') or l:match("^%s*%[.*dependencies%." .. esc .. "%]") then
      return i - 1
    end
  end
  return 0
end'''),
    blank,
    ...para('--',
        r'Neither tool reports a line number that is useful in the buffer. dep_line is the solution. '
        r'It scans the Cargo.toml buffer for the dependency name and returns a zero-based line, or 0 '
        r'when nothing matches. Three shapes are recognised: name = ... and name.workspace = true '
        r'(the pattern [.=] after the name), a quoted key "name" = ..., and a table header like '
        r'[dependencies.name] or [dev-dependencies.name]. The name is passed through vim.pesc so '
        r'that a dash or a dot in a crate name is not read as a pattern character.'),
    blank,
    ...para('--',
        r'The test for this is called "dotted and quoted dependency keys (serde.workspace = true) '
        r'get their own line, not line 1". The fallback of line 0 is explicit: a dependency that is '
        r'not in this manifest, for example one declared in a workspace parent, lands on the first '
        r'line, not nowhere.'),
    ...sec(r'finding the line in a lockfile'),
    ...code('lua', r'lua/plugins/supply-chain.lua · lines 26-36', r'''
--- Line (0-based) of `name = "<name>"` of the `[[package]]` with this version in
--- a Cargo.lock buffer, else nil. (cargo-deny's own label points at a synthetic
--- rendering of the lockfile: it is not the line of this file.)
local function lock_line(bufnr, name, version)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, l in ipairs(lines) do
    if l == ('name = "%s"'):format(name) and (not version or lines[i + 1] == ('version = "%s"'):format(version)) then
      return i - 1
    end
  end
end'''),
    blank,
    ...para('--',
        r'Cargo.lock is a different problem. The comment at line 28 explains that cargo-deny’s own '
        r'label points at a synthetic rendering of the lockfile, which is not the line of this file. '
        r'So lock_line looks for the exact line name = "<name>" of a [[package]] block and, when a '
        r'version is given, requires the next line to be version = "<version>". Two versions of the '
        r'same crate (a common thing in a lockfile) are therefore told apart. The return value is '
        r'nil when nothing is found, which lets the caller fall back to the label.'),
    ...sec(r'severities and the workflow condition'),
    ...code('lua', r'lua/plugins/supply-chain.lua · lines 38-47', r'''
local deny_severity = {
  error = vim.diagnostic.severity.ERROR,
  warning = vim.diagnostic.severity.WARN,
  note = vim.diagnostic.severity.INFO,
  help = vim.diagnostic.severity.HINT,
}

local function in_workflows(ctx)
  return require("config.fsutil").slash(ctx.filename):find("/%.github/workflows/") ~= nil
end'''),
    blank,
    ...para('--',
        r'cargo-deny speaks in error, warning, note and help; Neovim in ERROR, WARN, INFO and HINT. '
        r'The table maps them one to one, and the parser later uses WARN for anything unknown.'),
    blank,
    ...para('--',
        r'in_workflows decides whether actionlint and zizmor run. It normalises the path to forward '
        r'slashes with config.fsutil.slash and looks for /.github/workflows/. The slash '
        r'normalisation is there for Windows paths: the platform fixes of 2026-10-21 (commit '
        r'cd602fd, "drive-letter fix in supply-chain") are about this file, among others. The test '
        r'is "only runs under /.github/workflows/" for both tools.'),
    ...sec(r'the spec and the routing'),
    ...code('lua', r'lua/plugins/supply-chain.lua · lines 49-58', r'''
return {
  "mfussenegger/nvim-lint",
  opts = {
    linters_by_ft = {
      toml = { "cargo_deny", "cargo_machete" },
      yaml = { "actionlint", "zizmor" },
    },
    linters = {
      actionlint = { condition = in_workflows },
      zizmor = { condition = in_workflows },'''),
    blank,
    ...para('--',
        r'The file returns one spec for mfussenegger/nvim-lint. linters_by_ft routes by filetype: '
        r'toml to cargo_deny and cargo_machete, yaml to actionlint and zizmor. Since any TOML or '
        r'YAML file would match those filetypes, the filetype alone is far too wide; the condition '
        r'functions are what keep the linters off pyproject.toml, docker-compose.yml and every other '
        r'file. actionlint and zizmor only take the shared in_workflows condition; the Cargo-related '
        r'ones define their own.'),
    ...sec(r'cargo-deny: when and how it runs'),
    ...code('lua', r'lua/plugins/supply-chain.lua · lines 60-87', r'''
      -- Needs a deny.toml (`cargo deny init`) next to the manifest or in
      -- .cargo/. --offline: never hit the network from an editor event (uses
      -- the cached advisory DB; refresh it with `cargo deny fetch`, :RustTools).
      cargo_deny = {
        condition = function(ctx)
          local name = basename(ctx.filename)
          return (name == "Cargo.toml" or name == "Cargo.lock")
            and vim.fs.find({ "deny.toml", ".cargo/deny.toml" }, { path = ctx.dirname, upward = true })[1] ~= nil
        end,
        cmd = "cargo",
        stdin = false,
        append_fname = false, -- the checks are positional args; the manifest goes via --manifest-path
        stream = "stderr",
        ignore_exitcode = true,
        args = {
          "deny",
          "--manifest-path",
          function()
            local f = vim.api.nvim_buf_get_name(0)
            return manifest_dir(f) .. "/Cargo.toml"
          end,
          "--offline",
          "--format",
          "json",
          "check",
          "advisories",
          "bans",
        },'''),
    blank,
    ...para('--',
        r'The comment at lines 60 to 62 sets two rules. It needs a deny.toml next to the manifest or '
        r'in .cargo/, found by walking upward from the file’s directory; without one the linter does '
        r'nothing. And it passes --offline: never hit the network from an editor event. The advisory '
        r'database is the cached copy, refreshed explicitly with cargo deny fetch (the :RustTools '
        r'menu has an entry for it).'),
    blank,
    ...para('--',
        r'The command is cargo deny --manifest-path <dir>/Cargo.toml --offline --format json check '
        r'advisories bans. stdin = false (the buffer is not piped in). append_fname = false because '
        r'the checks are positional arguments: nvim-lint’s default of appending the file name would '
        r'put it after "bans" as an extra check name. stream = "stderr" selects the stream the '
        r'parser reads; the JSON records arrive there. ignore_exitcode = true because a finding '
        r'exits non-zero, which is the normal case here and must not be treated as a crash.'),
    blank,
    ...para('--',
        r'The manifest path is computed by a function and not a string. nvim-lint evaluates function '
        r'arguments when the linter runs, and the function reads the current buffer’s name (line '
        r'78). The manifest is the directory of the buffer plus Cargo.toml, so the same command '
        r'works when the open file is Cargo.lock.'),
    ...sec(r'the parser, line by line'),
    ...code('lua', r'lua/plugins/supply-chain.lua · lines 88-111', r'''
        parser = function(output, bufnr)
          local file = vim.api.nvim_buf_get_name(bufnr)
          local is_lock = basename(file) == "Cargo.lock"
          local out = {}
          local failed -- one "cargo-deny failed" per run: a broken manifest logged it twice
          for line in vim.gsplit(output, "\n", { plain = true, trimempty = true }) do
            local ok, d = pcall(vim.json.decode, line)
            if not (ok and type(d) == "table") then -- also JSON `null` (vim.NIL is truthy)
              d = {}
            end
            local f = d.type == "diagnostic" and d.fields
            if d.type == "log" and type(d.fields) == "table" and d.fields.level == "ERROR" and not failed then
              failed = true
              -- a broken deny.toml, an unreachable crate source...: no
              -- diagnostics follow, which looked the same as a clean result
              out[#out + 1] = {
                lnum = 0,
                col = 0,
                severity = vim.diagnostic.severity.WARN,
                source = "cargo-deny",
                code = "deny-failed",
                message = "cargo-deny failed: " .. tostring(d.fields.message),
              }
            end'''),
    blank,
    ...para('--',
        r'cargo-deny emits one JSON object per line. The parser walks the output with vim.gsplit and '
        r'decodes each line inside pcall, so a line that is not JSON is skipped. Line 95 handles a '
        r'subtle case: a JSON null decodes to vim.NIL, which is truthy in Lua, and indexing it would '
        r'crash. Anything that is not a table is replaced by an empty table. The test is "a JSON '
        r'null line (vim.NIL is truthy) does not crash the parser".'),
    blank,
    ...para('--',
        r'The first branch handles log records. If the record is a log with level ERROR, the parser '
        r'adds one warning on line 0 with the code deny-failed and the message "cargo-deny failed: '
        r'...". The comment gives the reason: a broken deny.toml or an unreachable crate source '
        r'produces no diagnostics after it, which looked the same as a clean result. A failed flag '
        r'makes it one warning per run, not one per log line; the comment at line 92 says a broken '
        r'manifest logged it twice. The integration test "a broken deny.toml gives a deny-failed '
        r'diagnostic instead of silence" checks it against the real tool.'),
    ...sec(r'choosing the position'),
    ...code('lua', r'lua/plugins/supply-chain.lua · lines 112-143', r'''
            if f and not (is_lock and f.code == "wildcard") then
              local label = f.labels and f.labels[1]
              local lnum, col = 0, 0
              -- `wildcard` (bans) labels the `dep = "*"` line of a Cargo.toml:
              -- skipped on the lockfile (not a Cargo.lock coordinate), and on
              -- the manifest the label gives the line (it used to land on
              -- line 1: the graph's crate is the package, not the dependency).
              local on_manifest = f.code == "wildcard" and label and label.line
              local krate = f.graphs and f.graphs[1] and f.graphs[1].Krate
              if is_lock then
                local at = krate and lock_line(bufnr, krate.name, krate.version)
                if at then
                  lnum = at
                elseif label then
                  lnum, col = (label.line or 1) - 1, (label.column or 1) - 1
                end
              elseif on_manifest then
                -- the label may belong to another manifest (a virtual workspace
                -- root has fewer lines than the member's): stay inside the buffer
                lnum = math.min(label.line - 1, math.max(vim.api.nvim_buf_line_count(bufnr) - 1, 0))
                col = (label.column or 1) - 1
              else
                lnum = krate and dep_line(bufnr, krate.name) or 0
              end
              out[#out + 1] = {
                lnum = lnum,
                col = col,
                severity = deny_severity[f.severity] or vim.diagnostic.severity.WARN,
                source = "cargo-deny",
                code = f.code,
                message = f.message .. (label and label.message and (" - " .. label.message) or ""),
              }'''),
    blank,
    ...para('--',
        r'Each diagnostic record becomes an entry with a line and a column. The wildcard code is '
        r'special: it is the ban on dep = "*". On a lockfile it is skipped completely (line 112), '
        r'because a lockfile has no wildcard coordinate. On the manifest the label of the record '
        r'carries the line of the offending dependency, and the comment at line 115 says it used to '
        r'land on line 1, since the graph’s crate is the package and not the dependency.'),
    blank,
    ...para('--',
        r'For other records the position depends on the file. In a Cargo.lock the parser takes the '
        r'first graph’s Krate (name and version) and looks it up with lock_line; if that fails it '
        r'uses the label’s line and column minus one. In a Cargo.toml it uses dep_line with the '
        r'crate name, and 0 when there is no graph. The message is the record’s message, with " - " '
        r'and the label’s message appended when there is one.'),
    blank,
    ...para('--',
        r'The clamp at line 131 is easy to miss. The comment says the label may belong to another '
        r'manifest: a virtual workspace root has fewer lines than the member’s, so a label line '
        r'could be past the end of the buffer. math.min with the buffer’s last line keeps the '
        r'diagnostic inside the buffer. A test covers it: "a wildcard label past the end of a short '
        r'manifest (virtual workspace root) is clamped".'),
    ...sec(r'several wildcards in one record'),
    ...code('lua', r'lua/plugins/supply-chain.lua · lines 144-160', r'''
              -- several wildcard dependencies: one label (one line) each
              if on_manifest then
                for i = 2, #f.labels do
                  local l = f.labels[i]
                  if l.line then
                    local extra = vim.deepcopy(out[#out])
                    extra.lnum = math.min(l.line - 1, math.max(vim.api.nvim_buf_line_count(bufnr) - 1, 0))
                    extra.col = (l.column or 1) - 1
                    extra.message = f.message .. (l.message and (" - " .. l.message) or "")
                    out[#out + 1] = extra
                  end
                end
              end
            end
          end
          return out
        end,'''),
    blank,
    ...para('--',
        r'One record can carry several labels, one for each wildcard dependency. The first label has '
        r'been turned into a diagnostic already; the loop from index 2 copies it with vim.deepcopy, '
        r'sets the line, the column and the message from the additional label, and adds it. The '
        r'result: two wildcard dependencies produce two diagnostics, each on its own line, as the '
        r'test "two wildcard dependencies (two labels) give two diagnostics on their lines" asserts.'),
    ...sec(r'cargo-machete'),
    ...code('lua', r'lua/plugins/supply-chain.lua · lines 163-204', r'''
      -- Unused dependencies. Only on Cargo.toml; heuristic (regex based), so
      -- it can false-positive on macro-only or build-script-only deps - ignore
      -- those with [package.metadata.cargo-machete] ignored = ["name"].
      cargo_machete = {
        condition = function(ctx)
          return basename(ctx.filename) == "Cargo.toml"
        end,
        cmd = "cargo-machete",
        stdin = false,
        -- the directory is the argument: nvim-lint's default also appended
        -- the file name, which ran cargo-machete twice (every finding doubled)
        append_fname = false,
        ignore_exitcode = true,
        args = {
          function()
            return manifest_dir(vim.api.nvim_buf_get_name(0))
          end,
        },
        parser = function(output, bufnr)
          local file = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
          local dir = manifest_dir(file)
          local out, current = {}, nil
          for line in vim.gsplit(output, "\n", { plain = true, trimempty = true }) do
            local path = line:match("^%S+ %-%- (.+):$")
            if path then
              -- relative to the scanned dir, or absolute when given an absolute dir
              local full = (path:sub(1, 1) == "/" or path:match("^%a:[/\\]")) and path or (dir .. "/" .. path:gsub("^%./", ""))
              current = vim.fs.normalize(full) == file
            elseif current and line:match("^\t%S+$") then
              local dep = vim.trim(line)
              out[#out + 1] = {
                lnum = dep_line(bufnr, dep),
                col = 0,
                severity = vim.diagnostic.severity.WARN,
                source = "cargo-machete",
                message = "unused dependency `" .. dep .. "`",
              }
            end
          end
          return out
        end,
      },'''),
    blank,
    ...para('--',
        r'The comment names the limits: it runs only on Cargo.toml, and it is heuristic (regex '
        r'based), so it can false-positive on macro-only or build-script-only dependencies. The way '
        r'out is part of the comment: ignore them with [package.metadata.cargo-machete] ignored = '
        r'["name"].'),
    blank,
    ...para('--',
        r'The comment at lines 172 and 173 records a bug from the field test: nvim-lint’s default '
        r'also appended the file name, which ran cargo-machete twice and doubled every finding. '
        r'append_fname = false and an argument that is the manifest directory fix it.'),
    blank,
    ...para('--',
        r'Its output has a header line like "name -- path:" followed by tab-indented dependency '
        r'names. The parser matches the header with ^%S+ %-%- (.+):$, builds the full path '
        r'(accepting relative, ./-prefixed, absolute and Windows drive-letter paths), and compares '
        r'the normalised path with the buffer’s own file. current is therefore true only for the '
        r'section that belongs to this buffer, so a workspace scan that mentions several crates '
        r'reports only this manifest’s findings. The following lines that match a tab and a name '
        r'become "unused dependency `name`" warnings on dep_line. Tests: "two crates, relative ./ '
        r'paths: only this buffer’s manifest", "absolute paths: matches own manifest, ignores a '
        r'sibling’s", and "a single section is not doubled".'),
    ...sec(r'design decisions'),
    ...pt('--', r'the line, not the file',
        r'every diagnostic is anchored to the dependency’s line, which the tools themselves do not '
        r'give. This is the main piece of code in the file.'),
    ...pt('--', r'offline by default',
        r'cargo-deny never fetches from an editor event. The cost is a stale advisory database until '
        r'cargo deny fetch is run.'),
    ...pt('--', r'a failure is visible',
        r'deny-failed turns a broken configuration into a warning. A silent linter looks clean.'),
    ...pt('--', r'conditions over filetypes',
        r'the linters are attached to toml and yaml, and the conditions narrow them to the files '
        r'that matter.'),
    ...sec(r'edge cases the tests pin down'),
    ...para('--',
        r'The tests pin down these cases: null JSON lines, duplicated ERROR logs, short '
        r'virtual-workspace manifests, lockfiles with a wildcard code, dotted keys, sibling '
        r'manifests with absolute paths, and sections that must not be doubled.'),
    ...para('--',
        r'The tests also run the real tools: cargo-deny on RUSTSEC-2020-0071 for the time crate '
        r'(line 755 of the spec), cargo-machete in a scratch crate (line 810), and this repository’s '
        r'own .github/workflows/ci.yml, which has to be clean under actionlint and zizmor (line '
        r'915).'),
    ...sec(r'how it is tested'),
    ...pt('--', r'tests/git-lint-supply-chain_spec.lua',
        r'describe blocks "supply-chain linters_by_ft" (222), "actionlint / zizmor condition" (231), '
        r'"cargo_deny condition" (248), "cargo_deny config" (278), "cargo_deny parser" (301), '
        r'"cargo_machete" (572) and the integration blocks (750, 809, 844). The parser tests build '
        r'their output by hand and call the parser directly.'),
    ...sec(r'history'),
    ...pt('--', r'81e0650, 85a7016, 3cfba54, bc74318 (2026-10-09, "wip-s9a" to "wip-s9d")',
        r'the file is built in four steps as roadmap step 9.'),
    ...pt('--', r'99acd7e (2026-10-13)',
        r'Batch 4: editing and UI.'),
    ...pt('--', r'98c9bb4 (2026-10-13)',
        r'round 1 of the field test; its message lists "cargo-deny log/lock lines": the log record '
        r'and the lockfile line handling.'),
    ...pt('--', r'f31e013 (2026-10-14)',
        r'"deny fallback and parser".'),
    ...pt('--', r'b474307 (2026-10-15)',
        r'"Macros and dependencies: field test fixes".'),
    ...pt('--', r'ff1c8fa (2026-10-16), cd602fd (2026-10-21)',
        r'Windows and macOS portability, including the drive-letter fix in this file.'),
    ...pt('--', r'0247401 (2026-10-22)',
        r'positioning commit.'),
    ...sec(r'is it in xyno-plugins?'),
    ...para('--',
        r'Not as a whole. xyno-crates.nvim and xyno-rust.nvim carry the Rust dependency and task '
        r'tooling, but nothing in them defines nvim-lint sources for cargo-deny, cargo-machete, '
        r'actionlint or zizmor. The file depends on config.fsutil.slash; xyno-rust.nvim has its own '
        r'fsutil.lua in the extracted tree.'),
  ],
);
