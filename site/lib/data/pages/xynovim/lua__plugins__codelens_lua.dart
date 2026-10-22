import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/codelens.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'codelens.lua — one option, one file, and a reason for both'),
    cm('--', r'rust-analyzer’s run / debug / references lenses, switched on'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'LazyVim option override: turns the LSP code lens feature on'),
    kv(r'language', r'Lua, a lazy.nvim plugin spec'),
    kv(r'size', r'6 lines, 1 commit (01475c4, 2026-10-09)'),
    kv(r'touches', r'opts.codelens.enabled of neovim/nvim-lspconfig'),
    kv(r'keys it enables', r'<leader>cc runs the lens, <leader>cC refreshes (both LazyVim’s)'),
    ...sec(r'why this file exists'),
    ...para('--',
        r'rust-analyzer can report code lenses: small annotations that sit above a function or a '
        r'test and say Run, Debug, or N references. In the editor this is the "gutter play button" '
        r'workflow. LazyVim ships the feature off, and the file’s own header says so: "LazyVim ships '
        r'codelens off". This file is the one-line answer to that default.'),
    blank,
    ...para('--',
        r'The whole file is a plugin spec. It names the plugin it configures, neovim/nvim-lspconfig, '
        r'and gives it an opts table. LazyVim’s LSP module reads opts.codelens.enabled when it sets '
        r'up the language server attach logic, so there is no code in this repo that renders or '
        r'requests lenses. The spec only flips the switch that LazyVim already provides.'),
    ...sec(r'the whole file'),
    ...code('lua', r'lua/plugins/codelens.lua · lines 1-6', r'''
-- rust-analyzer's run/debug/references lenses (virtual text above fns).
-- LazyVim ships codelens off; <leader>cc runs the lens, <leader>cC refreshes.
return {
  "neovim/nvim-lspconfig",
  opts = { codelens = { enabled = true } },
}'''),
    blank,
    ...para('--',
        r'Line 1 and 2 are the comment. Line 1 states what the lenses are, in the file’s words: run '
        r'/ debug / references lenses shown as virtual text above functions. Line 2 states the '
        r'default being overridden and names the two keys the option brings with it: <leader>cc runs '
        r'the lens under the cursor and <leader>cC refreshes the lenses. Those keys are not defined '
        r'in this repo; the comment documents them for the reader.'),
    blank,
    ...para('--',
        r'Lines 3 to 6 are the spec. Because the spec has no config function and no keys, lazy.nvim '
        r'merges the opts table into whatever other specs say about nvim-lspconfig. That matters in '
        r'this repo, because the same plugin is also configured by domain.lua (a wgsl_analyzer '
        r'server) and editing-ui.lua (diagnostic and taplo settings). Every one of these files '
        r'contributes a separate opts table and lazy.nvim deep-merges them, so each concern stays in '
        r'its own file.'),
    ...sec(r'design decisions'),
    ...pt('--', r'one file per concern',
        r'codelens is a Rust workflow feature, so it has its own file rather than being folded into '
        r'a general LSP file. The commit that added it (01475c4, 2026-10-09, "Roadmap step 2") '
        r'enabled several LazyVim extras at once, dap, test, overseer, toml, yaml, json, markdown '
        r'and git, and this file was the small piece that was not an extra but an option.'),
    ...pt('--', r'opts, not config',
        r'an opts table is merged; a config function would have replaced the behaviour of other '
        r'specs. Choosing opts is what lets three other files extend nvim-lspconfig without knowing '
        r'about each other.'),
    ...pt('--', r'no extra keymaps',
        r'the file does not define a key. The two it mentions come with the option, so there is '
        r'nothing to keep in sync here.'),
    ...sec(r'how it is tested'),
    ...para('--',
        r'The behaviour is tested in tests/rust-analyzer-config_spec.lua. Its test number 11 is '
        r'named "codelens: textDocument/codeLens succeeds, <leader>cc is mapped and runs a lens". It '
        r'reads the merged opts of nvim-lspconfig through lazy.core.plugin and asserts that '
        r'codelens.enabled is true (line 452), and it checks the request against a real '
        r'rust-analyzer, not only the option.'),
    blank,
    ...para('--',
        r'tests/startup-and-options_spec.lua has a block called plugins/codelens.lua. One test '
        r'asserts the option, and another maps <leader>cc and <leader>cC buffer-locally in a buffer '
        r'that has a code-lens-capable client. The client there is a fake LSP server started with '
        r'vim.lsp.start under the name xyno-fake-codelens, so the key wiring is verified without a '
        r'real language server.'),
    blank,
    ...para('--',
        r'Test 19 in the rust-analyzer spec covers the other half: a debug lens resolves to '
        r'rust-analyzer.debugSingle with nvim-dap loaded. That is why the lenses and the debugging '
        r'setup in dap.lua belong together. Clicking a Debug lens with the mouse is listed as '
        r'pending in tests/dap-neotest-coverage_spec.lua (line 1438), with the reason "needs a '
        r'mouse-driven UI session".'),
    ...sec(r'history'),
    ...pt('--', r'01475c4 (2026-10-09)',
        r'the only commit that touches the file: "Roadmap step 2: enable '
        r'dap/test/overseer/toml/yaml/json/markdown/git extras, codelens". The file has not changed '
        r'since, which fits a file with one option.'),
    ...pt('--', r'be73b6c (2026-10-12)',
        r'not a change to this file, but related: its message lists "Debug codelens" among the Rust '
        r'workflow robustness items, next to the lldb formatters and the rust_panic stop that '
        r'dap.lua implements.'),
    ...sec(r'is it in xyno-plugins?'),
    ...para('--',
        r'No. This is a configuration file for an upstream plugin and nothing in the extracted Rust '
        r'plugins under xyno-plugins duplicates it, so there is nothing to compare. The extraction '
        r'on 2026-10-22 did not touch it.'),
  ],
);
