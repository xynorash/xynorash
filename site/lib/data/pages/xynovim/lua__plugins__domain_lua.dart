import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/domain.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'domain.lua — SQL, HTTP and shaders next to the Rust'),
    cm('--', r'a pinned REST client, two parsers, one language server'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'domain-specific extras: kulala (HTTP client), sql and wgsl parsers, wgsl-analyzer'),
    kv(r'language', r'Lua, a lazy.nvim plugin spec list (four specs)'),
    kv(r'size', r'39 lines, 6 commits (527f350 to 25086fd, 2026-10-09 to 2026-10-14)'),
    kv(r'roadmap', r'step 10'),
    kv(r'related', r'util.rest extra enabled in lazyvim.json'),
    ...sec(r'why this file exists'),
    ...para('--',
        r'The header names the scope: domain-specific extras (roadmap step 10): treesitter parsers '
        r'for the SQL injection and the HTTP / shader files, and wgsl-analyzer for Bevy shaders. A '
        r'Rust project often contains SQL inside sqlx macros, HTTP requests for a service it '
        r'exposes, and WGSL shaders if it renders with Bevy or wgpu. This file adds the tools for '
        r'each, without touching the Rust setup.'),
    blank,
    ...para('--',
        r'The rest extra (kulala.nvim) is enabled through lazyvim.json, not here. This file only '
        r'adjusts how that plugin is installed.'),
    ...sec(r'kulala, pinned on purpose'),
    ...code('lua', r'lua/plugins/domain.lua · lines 5-20', r'''
  {
    -- Pinned to the last 5.x release. From v6.0.0 kulala.nvim needs a separate
    -- kulala-core binary (v6.32+ behind a license token, and the public
    -- GitHub release it used to fetch is gone, 404), so v6 cannot send a
    -- request without an account. 5.x talks to curl directly.
    -- submodules = false: the repo has a v6 submodule (fmt/); lazy's
    -- `--recurse-submodules` checkout of the pinned tag failed on a fresh
    -- install ("gitfile does not point to a valid repository") and left
    -- v6 checked out.
    "mistweaverco/kulala.nvim",
    tag = "v5.3.4",
    submodules = false,
    -- the "what's new" popup would come with every update of a pinned plugin; grpcurl and websocat
    -- (`:checkhealth kulala` errors) are only needed for gRPC / WebSocket requests
    opts = { disable_news_popup = true },
  },'''),
    blank,
    ...para('--',
        r'This is the part of the file where a decision was reversed more than once. The git log '
        r'shows the sequence: d8a7462 pinned v6.31.1, 48ccd48 pinned v5.3.4 instead (both on '
        r'2026-10-09), and da1d829 (2026-10-13) added submodules = false. The comment gives the '
        r'reasons, and this page repeats only what the comment says.'),
    blank,
    ...pt('--', r'the pin',
        r'from v6.0.0 kulala.nvim needs a separate kulala-core binary (v6.32 and later behind a '
        r'license token), and the public GitHub release it used to fetch is gone (404). So v6 cannot '
        r'send a request without an account. 5.x talks to curl directly, and the file pins the last '
        r'5.x release, v5.3.4.'),
    ...pt('--', r'submodules = false',
        r'the repository has a v6 submodule in a directory called fmt/. lazy.nvim’s checkout of the '
        r'pinned tag with --recurse-submodules failed on a fresh install with "gitfile does not '
        r'point to a valid repository" and left v6 checked out. Turning submodules off lets the '
        r'pinned tag check out cleanly. This was found by the fresh-install work (commit da1d829, '
        r'"Batch 5: fresh install, CI and docs").'),
    ...pt('--', r'disable_news_popup = true',
        r'a pinned plugin would show its "what’s new" popup with every update of the pin. The '
        r'comment adds that grpcurl and websocat (reported by :checkhealth kulala as errors) are '
        r'needed only for gRPC and WebSocket requests. Commit 25086fd '
        r'(2026-10-14) added the option.'),
    ...sec(r'parsers and the language server'),
    ...code('lua', r'lua/plugins/domain.lua · lines 21-28', r'''
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "sql", "wgsl" } },
  },
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "wgsl-analyzer" } },
  },'''),
    blank,
    ...para('--',
        r'Two treesitter parsers are added to ensure_installed: sql (for the SQL injection in Rust '
        r'strings) and wgsl. Both are plain list additions, merged with the parsers other files and '
        r'LazyVim request. Mason is asked for wgsl-analyzer in the same way, an ensure_installed '
        r'entry that makes the binary part of the fresh-install bootstrap.'),
    ...sec(r'the server definition'),
    ...code('lua', r'lua/plugins/domain.lua · lines 29-38', r'''
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- prebuilt binary from Mason; filetype `wgsl` is built into Neovim.
        -- ron-lsp is not in Mason (see README), RON only gets its parser.
        wgsl_analyzer = {},
      },
    },
  },'''),
    blank,
    ...para('--',
        r'servers.wgsl_analyzer = {} with an empty table is the idiom for "enable this server with '
        r'the default configuration". The comment says why nothing else is needed: the binary is a '
        r'prebuilt one from Mason, and the filetype wgsl is built into Neovim, so the server '
        r'attaches without a filetype registration.'),
    blank,
    ...para('--',
        r'The same comment records a negative result: ron-lsp is not in Mason, so RON files only get '
        r'their parser. That is the stated reason RON has no language server in this setup. '
        r'docs/HISTORY.md adds that wgsl-analyzer logs "Project discovery failed" on every start in '
        r'a Cargo crate and that the message was judged harmless; the code in this file does not try '
        r'to silence it.'),
    ...sec(r'design decisions'),
    ...pt('--', r'one file per domain',
        r'the four specs target four different plugins (kulala, treesitter, mason, lspconfig), but '
        r'they share a purpose, so they live together. Anyone removing shader support removes one '
        r'line from three of the specs and the last spec.'),
    ...pt('--', r'pin over upgrade',
        r'the choice to stay on 5.x costs updates and avoids a plugin that cannot work without an '
        r'account. The comment documents what would have to change before the pin can move.'),
    ...pt('--', r'config left to the extras',
        r'the REST client’s keymaps are not set here. In editing-ui.lua the <leader>R key stub from '
        r'the kulala extra is switched off and the which-key group is named instead.'),
    ...sec(r'how it is tested'),
    ...pt('--', r'tests/rust-analyzer-config_spec.lua',
        r'test 15 is named "domain.lua: kulala pinned to v5.3.4 without submodules, parsers, Mason '
        r'package, server entry". It checks the kulala plugin spec, disable_news_popup, the wgsl '
        r'parser, the Mason ensure_installed entry and that servers.wgsl_analyzer is an empty table '
        r'(line 699).'),
    ...pt('--', r'same file, tests 15b and 16',
        r'wgsl-analyzer attaches to a .wgsl file and reports a type mismatch; in a Cargo crate it '
        r'still attaches ("Project discovery failed" is harmless). Both skip when Mason’s binary is '
        r'not installed.'),
    ...pt('--', r'tests/health-bootstrap-ci_spec.lua',
        r'line 605: a fresh XDG install ends with exit 0, an unchanged lockfile and kulala on '
        r'v5.3.4, which is the test for the submodules = false problem. Line 989 asserts that this '
        r'file contains ensure_installed = { "wgsl-analyzer" } and that :checkhealth checks the '
        r'binary.'),
    ...pt('--', r'tests/keymaps-global_spec.lua',
        r'line 449: the <leader>R group and the Rb and Rr keys exist in an .http buffer.'),
    ...pt('--', r'tests/snippets-completion-injections_spec.lua',
        r'line 426 covers the SQL injection into the strings of the sqlx macros, the use of the sql '
        r'parser.'),
    ...sec(r'history'),
    ...pt('--', r'527f350 (2026-10-09)',
        r'"Roadmap step 10 wip: rest extra, domain plugin, routes, sql injection, unsafe hl". The '
        r'file is created.'),
    ...pt('--', r'd8a7462, 48ccd48 (2026-10-09)',
        r'pin kulala to v6.31.1, then to v5.3.4.'),
    ...pt('--', r'7df30ba (2026-10-09)',
        r'mason wgsl-analyzer.'),
    ...pt('--', r'da1d829 (2026-10-13)',
        r'submodules = false, in the fresh-install batch.'),
    ...pt('--', r'25086fd (2026-10-14)',
        r'disable_news_popup.'),
    ...sec(r'is it in xyno-plugins?'),
    ...para('--',
        r'No. Nothing in xyno-plugins deals with SQL, HTTP or shaders; the extracted plugins are the '
        r'Rust-specific ones (clipboard, crates, guard, history, imports, macros, new, rust, '
        r'sandbox).'),
  ],
);
