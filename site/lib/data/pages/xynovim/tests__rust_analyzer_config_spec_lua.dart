import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/rust-analyzer-config_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust-analyzer-config_spec.lua — the settings the server really gets, measured, not read'),
    cm('--', r'schema-checked defaults, a process scan for a cargo child that must not exist, and the extras around the Rust stack'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/plugins/rustaceanvim.lua, editing-ui.lua and domain.lua: effective rust-analyzer settings, two diagnostic tiers, codelens, inlay hints, taplo, wgsl-analyzer, kulala, bigfile'),
    kv(r'language', r'Lua spec, 841 lines, 32 it() blocks, 4 describe() blocks'),
    kv(r'platform', r'Linux only (it scans /proc and runs python3 http.server)'),
    kv(r'needs', r'rust-analyzer and cargo, run with TEST_TIMEOUT=600; Mason taplo or wgsl-analyzer, network, curl and python3 where those tests need them'),
    kv(r'history', r'6 commits, 2026-10-13 to 2026-10-16'),
    ...sec(r'why this file exists'),
    ...para('--', r'A configuration option that rust-analyzer does not know is ignored without a word. A setting that a plugin overwrites after the config set it is also silent. The only way to know what the server runs with is to ask it. This spec does so in two ways: it checks the declared defaults against the config schema of the installed binary, and it attaches a real server and reads the settings that arrived. The test names carry numbers (1 to 21 with letters for the second view of the same item) which are the items of a checklist of the behaviours the Rust setup promises.'),
    ...code('lua', r'tests/rust-analyzer-config_spec.lua · lines 1-8', r'''
-- rust-analyzer configuration (lua/plugins/rustaceanvim.lua, editing-ui.lua,
-- domain.lua): the effective settings the server really gets, the two
-- diagnostic tiers, codelens/inlay hints, taplo, wgsl-analyzer, kulala.
-- Needs rust-analyzer and cargo (run with TEST_TIMEOUT=600); tests that need Mason's taplo / wgsl-analyzer,
-- the network, curl or python3 skip with a message when those are missing.
-- xyno-os: linux (scans /proc and runs python3 http.server)
local H = require("xynotest.helpers")
local harness = require("xynotest.harness")'''),
    ...sec(r'defaults checked against the schema'),
    ...para('--', r'Test 7 runs rust-analyzer --print-config-schema, collects every property name, and walks the default_settings table of the plugin. A key is accepted when it is a documented leaf, or a table whose path is a prefix of documented keys; anything else is collected into a list of unknown keys and the test requires the list to be empty. Two legacy names are exempted by name: cargo.allFeatures and cargo.loadOutDirsFromCheck, which the schema no longer lists but the server still honours; the comment says that no warning is sent (item 7b) and that allFeatures still switches the features on. The exception list is short, explicit and justified by a second test, so a typo like cargo.allFeature would be caught.'),
    ...code('lua', r'tests/rust-analyzer-config_spec.lua · lines 218-262', r'''
  it("7. every default_settings key is a key of the installed binary's config schema", function()
    H.need_rust()
    local r = vim.system({ "rust-analyzer", "--print-config-schema" }, { text = true }):wait(20000)
    H.eq(0, r.code, "rust-analyzer --print-config-schema")
    local schema = vim.json.decode(r.stdout)
    -- a list of { title, properties = { ["rust-analyzer.x.y"] = {...} } }
    local known = {}
    for _, section in ipairs(schema) do
      for k in pairs(section.properties or {}) do
        known[k] = true
      end
    end
    H.ok(next(known), "could not read keys from the schema")
    local function is_prefix(path)
      for k in pairs(known) do
        if k:sub(1, #path + 1) == path .. "." then
          return true
        end
      end
    end
    local unknown = {}
    local function walk(tbl, path)
      for key, v in pairs(tbl) do
        local p = path .. "." .. key
        if known[p] then
          -- a documented leaf (arrays and free-form objects like snippets.custom included)
        elseif type(v) == "table" and not vim.islist(v) and is_prefix(p) then
          walk(v, p)
        else
          unknown[#unknown + 1] = p
        end
      end
    end
    walk(ra_opts().default_settings["rust-analyzer"], "rust-analyzer")
    -- Legacy names (set by LazyVim's rust extra and config.rust_context) that
    -- the schema no longer lists but the server still honours: no warning is
    -- sent (7b) and allFeatures still switches the features on (the
    -- all-features test below).
    local legacy = { ["rust-analyzer.cargo.allFeatures"] = true, ["rust-analyzer.cargo.loadOutDirsFromCheck"] = true }
    unknown = vim.tbl_filter(function(k)
      return not legacy[k]
    end, unknown)
    table.sort(unknown)
    H.eq({}, unknown, "keys rust-analyzer does not know")
  end)'''),
    ...sec(r'postfix snippets'),
    ...para('--', r'Test 6 states the nine custom postfix snippets as data: ok, err, some, pinbox, arc, rc, refcell, mutex and arcmutex, each with body, required imports and scope expr. The arcmutex entry requires two imports. The test fails on an extra postfix as well as on a missing one, so the list in the config and the list in the spec are the same list. Test 6b then checks that the snippets reach the server.'),
    ...code('lua', r'tests/rust-analyzer-config_spec.lua · lines 189-216', r'''
  it("6. completion.snippets.custom: exactly the 9 postfix snippets", function()
    local custom = ra_opts().default_settings["rust-analyzer"].completion.snippets.custom
    local want = {
      ok = { "Ok(${receiver})" },
      err = { "Err(${receiver})" },
      some = { "Some(${receiver})" },
      pinbox = { "Box::pin(${receiver})", "std::boxed::Box" },
      arc = { "Arc::new(${receiver})", "std::sync::Arc" },
      rc = { "Rc::new(${receiver})", "std::rc::Rc" },
      refcell = { "RefCell::new(${receiver})", "std::cell::RefCell" },
      mutex = { "Mutex::new(${receiver})", "std::sync::Mutex" },
      arcmutex = { "Arc::new(Mutex::new(${receiver}))", { "std::sync::Arc", "std::sync::Mutex" } }, -- both imports
    }
    local seen, n = {}, 0
    for _, snip in pairs(custom) do
      n = n + 1
      local w = want[snip.postfix]
      H.ok(w, "unexpected postfix " .. tostring(snip.postfix))
      seen[snip.postfix] = true
      H.eq(w[1], snip.body, snip.postfix .. " body")
      H.eq(w[2], snip.requires, snip.postfix .. " requires")
      H.eq("expr", snip.scope, snip.postfix .. " scope")
    end
    H.eq(9, n)
    for k in pairs(want) do
      H.ok(seen[k], "missing postfix " .. k)
    end
  end)'''),
    ...sec(r'the cargo test child that must not exist'),
    ...para('--', r'rustaceanvim, by default, starts cargo test --no-run --all-targets after the attach, to discover debuggables. The config turns that off (dap autoload_configurations false). Test 3 proves it from outside: it attaches, waits four seconds, scans /proc for processes whose command line contains --no-run, and for each walks the parent chain up to ten steps to see whether it belongs to this nvim. The result list must be empty. A child belonging to another nvim is not counted, so the test is robust on a busy machine.'),
    ...code('lua', r'tests/rust-analyzer-config_spec.lua · lines 312-347', r'''
  it("3. no `cargo test --no-run --all-targets` child after attach (dap autoload off)", function()
    basic()
    vim.wait(4000) -- rustaceanvim would start it right after the attach
    local pid = tostring(vim.uv.os_getpid())
    local children = {}
    local function ppid(p)
      local f = io.open("/proc/" .. p .. "/stat")
      if not f then
        return
      end
      local s = f:read("*a")
      f:close()
      return s:match("^%d+ %b() %S (%d+)")
    end
    for _, name in ipairs(vim.fn.readdir("/proc")) do
      if name:match("^%d+$") then
        local f = io.open("/proc/" .. name .. "/cmdline")
        local cmd = f and f:read("*a") or ""
        if f then
          f:close()
        end
        if cmd:find("--no-run", 1, true) then
          -- belongs to this nvim when it is in its process tree
          local p, depth = name, 0
          while p and p ~= "1" and depth < 10 do
            if p == pid then
              children[#children + 1] = cmd:gsub("%z", " ")
              break
            end
            p, depth = ppid(p), depth + 1
          end
        end
      end
    end
    H.eq({}, children)
  end)'''),
    ...sec(r'effective settings, measured'),
    ...para('--', r'Test 4 reads client.settings[’rust-analyzer’] from the attached client and compares a long list of values with literals: cachePriming.numThreads 4, numThreads 8, allFeatures true, build scripts enabled, check.command clippy with --no-deps, checkOnSave false, snippets fill_arguments, term search on, the file watcher set to client, the exact list of excluded folders (.direnv, .git, .jj, .github, .gitlab, bin, node_modules, target, venv, .venv), the import granularity and prefix, the inlay hint modes, procMacro on, and excludeImports and excludeTests true for references. A change of any value in the plugin file fails here and forces the author to update both, so settings never drift unnoticed.'),
    ...code('lua', r'tests/rust-analyzer-config_spec.lua · lines 349-379', r'''
  it("4. effective client.settings['rust-analyzer'] (measured)", function()
    local ra = ra_settings()
    H.eq(4, ra.cachePriming.numThreads)
    H.eq(8, ra.numThreads)
    H.eq(true, ra.cargo.allFeatures)
    H.eq(true, ra.cargo.buildScripts.enable)
    H.eq(true, ra.cargo.loadOutDirsFromCheck)
    H.eq(true, ra.cargo.targetDir)
    H.eq("clippy", ra.check.command)
    H.eq({ "--no-deps" }, ra.check.extraArgs)
    H.eq(false, ra.checkOnSave)
    H.eq("fill_arguments", ra.completion.callable.snippets)
    H.eq(true, ra.completion.fullFunctionSignatures.enable)
    H.eq(true, ra.completion.termSearch.enable)
    H.eq(true, ra.diagnostics.enable)
    H.eq("client", ra.files.watcher)
    local excl = vim.deepcopy(ra.files.exclude)
    table.sort(excl)
    local want = { ".direnv", ".git", ".jj", ".github", ".gitlab", "bin", "node_modules", "target", "venv", ".venv" }
    table.sort(want)
    H.eq(want, excl)
    H.eq("module", ra.imports.granularity.group)
    H.eq("self", ra.imports.prefix)
    H.eq("with_block", ra.inlayHints.closureReturnTypeHints.enable)
    H.eq("never", ra.inlayHints.expressionAdjustmentHints.enable)
    H.eq("skip_trivial", ra.inlayHints.lifetimeElisionHints.enable)
    H.eq(true, ra.inlayHints.lifetimeElisionHints.useParameterNames)
    H.eq(true, ra.procMacro.enable)
    H.eq(true, ra.references.excludeImports)
    H.eq(true, ra.references.excludeTests)
  end)'''),
    ...sec(r'two tiers, codelens, inlay hints'),
    ...para('--', r'The instant tier test: a native rust-analyzer E0308 appears quickly when warm. Codelens: textDocument/codeLens succeeds, leader c c is mapped and runs a lens; the debug codelens resolves to rust-analyzer.debugSingle with nvim-dap loaded, and the debugSingle client command is advertised to the server even though dap was loaded before the client. Inlay hints: the capability, the leader u h toggle and hints for typed lets. Type hierarchy is unsupported by the server, so the test records that gI (goto implementation) is the substitute. A related test, 4b, checks allFeatures with a workspace whose features exclude each other: both are on.'),
    ...sec(r'renaming a module renames the code too'),
    ...para('--', r'Item 21 is a field test finding. The test writes a crate with pub mod util; in lib.rs and util.rs with a helper function, opens lib.rs, waits until rust-analyzer knows it, and requires that the client does not advertise willRename. It puts the cursor on util in the mod declaration and asks textDocument/rename for the name utils. It waits until the answer contains a file rename (the answer lacks it until the file is known to the server), and requires exactly one file rename and at least two text edits, for mod util; and util::helper(). The rest of the test applies the answer through the editor path.'),
    ...code('lua', r'tests/rust-analyzer-config_spec.lua · lines 563-607', r'''
  it("21. renaming a module through LSP updates `mod` and the paths, not only the file (willRename not advertised)", function()
    H.need_rust()
    local dir = H.tmpdir()
    local function write(path, text)
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.fn.writefile(vim.split(text, "\n"), path)
    end
    write(dir .. "/Cargo.toml", '[package]\nname = "renm"\nversion = "0.1.0"\nedition = "2021"\n')
    write(dir .. "/src/lib.rs", "pub mod util;\n\npub fn go() -> i32 {\n    util::helper()\n}\n")
    write(dir .. "/src/util.rs", "pub fn helper() -> i32 {\n    1\n}\n")
    local buf = H.open(dir .. "/src/lib.rs")
    local client = H.wait_lsp("rust-analyzer", buf)
    H.eq(false, client.config.capabilities.workspace.fileOperations.willRename, "willRename must not be advertised")
    H.wait_for(function()
      local res = vim.lsp.buf_request_sync(buf, "textDocument/documentSymbol", { textDocument = vim.lsp.util.make_text_document_params(buf) }, 5000)
      for _, r in pairs(res or {}) do
        for _, sym in ipairs(r.result or {}) do
          if sym.name == "go" then
            return true
          end
        end
      end
    end, 90000, "rust-analyzer to know lib.rs")
    vim.api.nvim_win_set_cursor(0, { 1, 9 }) -- on `util` of `pub mod util;`
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    params.newName = "utils"
    -- until the file is known to rust-analyzer the answer lacks the file rename
    local res, edits, renames
    H.wait_for(function()
      res, edits, renames = nil, 0, 0
      local r = vim.lsp.buf_request_sync(buf, "textDocument/rename", params, 20000)
      for _, x in pairs(r or {}) do
        res = x.result
      end
      for _, ch in ipairs(res and res.documentChanges or {}) do
        if ch.kind == "rename" then
          renames = renames + 1
        elseif ch.edits then
          edits = edits + #ch.edits
        end
      end
      return renames > 0
    end, 90000, "a rename answer with the file rename")
    H.eq(1, renames, "the file rename: " .. vim.inspect(res))
    H.ok(edits >= 2, "text edits for `mod util;` and `util::helper()` came with it (got " .. edits .. "): " .. vim.inspect(res))'''),
    ...sec(r'taplo, wgsl-analyzer, kulala, bigfile'),
    ...para('--', r'Taplo has root markers and the Cargo.toml schema association; it is not started for Cargo.lock, because it answered this document has been excluded; a lone Cargo.toml without a .git is rooted and reports a typo such as edtion (optional, needs the network). wgsl-analyzer attaches to a .wgsl file and reports a type mismatch, and in a Cargo crate it still attaches, where Project discovery failed is harmless. kulala is pinned to v5.3.4 without submodules, with parsers, the Mason package and the server entry; leader R s, R e, R c exist only in .http buffers, R b is global; a GET against a local python http.server returns 200. Snacks bigfile is enabled with the 1.5 MB default limit, and a Rust file over that gets the bigfile treatment and no LSP.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created. 98c9bb4, a3d33c8, 25086fd :: field test rounds (module rename willRename, taplo Cargo.lock).'),
    ...pt('--', r'ff1c8fa, 9641d08 (2026-10-16)', r'the Linux-only header and the Windows drive letter.'),
  ],
);
