import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/rust_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust_spec.lua — real rust-analyzer against the fixtures'),
    cm('--', r'55 lines that attach, analyse, and report a real type error'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'end-to-end proof that rust-analyzer works with this config on the fixture crates'),
    kv(r'language', r'Lua spec, 55 lines, 3 it() blocks, 1 describe() blocks'),
    kv(r'needs', r'cargo and a real rust-analyzer (skips with a reason otherwise)'),
    kv(r'fixtures', r'basic, broken, standalone.rs'),
    ...sec(r'why this file exists'),
    ...para('--', r'Most Rust specs stub the language server to stay fast and deterministic. This one does not: it opens real crates, starts the real rust-analyzer through rustaceanvim and checks what a user would see. It is the canary for the whole Rust setup, from the attach logic to the diagnostics pipeline.'),
    ...code('lua', r'tests/rust_spec.lua · lines 1-10', r'''
-- Needs rust-analyzer and cargo (skipped with a message otherwise).
local H = require("xynotest.helpers")

describe("rust-analyzer on the fixtures", function()
  before_each(function()
    H.need_rust()
  end)

  it("attaches to the basic crate and reports no errors", function()
    local _, buf = H.open_fixture("basic", "src/lib.rs")'''),
    ...sec(r'attached is not analysed'),
    ...para('--', r'The first test opens src/lib.rs of the basic crate and waits for the client. The comment in the middle is the lesson: attached is not analysed. A client attaches long before it has loaded the project, and diagnostics would be empty simply because nothing has been analysed yet. So the test waits, for up to 60 seconds, until a documentSymbol request lists a symbol named answer. Only then does it assert that there are no ERROR diagnostics.'),
    ...code('lua', r'tests/rust_spec.lua · lines 11-31', r'''
    H.wait_lsp("rust-analyzer", buf)
    -- attached is not analysed: wait until it answers with the crate's symbols
    H.wait_for(function()
      local res = vim.lsp.buf_request_sync(
        buf,
        "textDocument/documentSymbol",
        { textDocument = vim.lsp.util.make_text_document_params(buf) },
        5000
      )
      for _, r in pairs(res or {}) do
        for _, sym in ipairs(r.result or {}) do
          if sym.name == "answer" then
            return true
          end
        end
      end
    end, 60000, "documentSymbol to list `answer`")
    H.eq(
      {},
      vim.tbl_filter(function(d)
        return d.severity == vim.diagnostic.severity.ERROR'''),
    ...sec(r'the type error of the broken crate'),
    ...para('--', r'The second test opens the broken crate and waits for an E0308 diagnostic. The comment explains the tolerant matching: either tier (rust-analyzer or the bacon-ls tier) may answer first, the wording differs per rust-analyzer version, and bacon-ls has no code. So the test accepts the code E0308, the text mismatched types, or a message matching expected, found. It is robust to tool versions while still requiring a real type error to be reported.'),
    ...code('lua', r'tests/rust_spec.lua · lines 33-46', r'''
    )
  end)

  it("reports the type error of the broken crate", function()
    local _, buf = H.open_fixture("broken", "src/main.rs")
    H.wait_lsp("rust-analyzer", buf)
    -- Either tier may answer first, and the wording differs per rust-analyzer
    -- version ("mismatched types", "expected i32, found &'static str") and per
    -- tier (bacon-ls has no code): accept any rendering of E0308.
    H.wait_for(function()
      for _, d in ipairs(H.diagnostics(nil, buf)) do
        if tostring(d.code) == "E0308" or d.message:find("mismatched types", 1, true) or d.message:find("expected .*, found") then
          return d
        end'''),
    ...sec(r'standalone files'),
    ...para('--', r'The last test opens a lone .rs file with no Cargo.toml and waits for rust-analyzer to attach, covering the detached mode that smoke_spec mentions.'),
    ...code('lua', r'tests/rust_spec.lua · lines 48-55', r'''
    end, 60000, "an E0308 type error diagnostic in the broken crate")
  end)

  it("attaches to a standalone file", function()
    local _, buf = H.open_fixture("standalone.rs")
    H.wait_lsp("rust-analyzer", buf)
  end)
end)'''),
    ...sec(r'skipping'),
    ...para('--', r'before_each calls H.need_rust(), which skips with a precise reason: XYNO_TEST_SKIP_RUST, missing cargo, missing rust-analyzer, or a rustup proxy without the component. That keeps CI green on machines that cannot run it and honest in the log.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'cf2b8e1 (2026-10-13)', r'created with the test infrastructure.'),
    ...pt('--', r'fc2062a (2026-10-14)', r'"CI: make the suite pass on a clean machine (... rust-analyzer wording tolerant ...)"; the commit message names the wording tolerance, which is the E0308 matching above.'),
  ],
);
