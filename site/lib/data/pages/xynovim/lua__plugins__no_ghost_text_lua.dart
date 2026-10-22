import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/no-ghost-text.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'no-ghost-text.lua — completion that never writes ahead of you'),
    cm('--', r'ghost_text disabled for the menu and for the cmdline'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'turns blink.cmp ghost text off, in insert mode and in the cmdline'),
    kv(r'language', r'Lua, a lazy.nvim plugin spec'),
    kv(r'size', r'10 lines, 1 commit (8891f17, 2026-10-12)'),
    kv(r'decision', r'deliberate; the header refers to the README'),
    ...sec(r'why this file exists'),
    ...para('--',
        r'Ghost text is the grey preview of the selected completion item, drawn inline after the '
        r'cursor as if it were already typed. The header of the file calls its absence deliberate: '
        r'"No inline / ghost-text completion anywhere (deliberate, see README)". The file gives no '
        r'further reason, and this page does not guess one beyond the header.'),
    blank,
    ...para('--',
        r'What the file does give is the mechanism. LazyVim’s blink extra turns ghost text on in two '
        r'places: for the selected item in the cmdline menu, and when vim.g.ai_cmp is set. Because '
        r'of those two paths it is not enough to leave a default alone. The file forces both off.'),
    ...sec(r'the whole file'),
    ...code('lua', r'lua/plugins/no-ghost-text.lua · lines 1-10', r'''
-- No inline / ghost-text completion anywhere (deliberate, see README).
-- LazyVim's blink extra turns ghost text on for the selected item in the
-- cmdline menu and when vim.g.ai_cmp is set; force both off.
return {
  "saghen/blink.cmp",
  opts = {
    completion = { ghost_text = { enabled = false } },
    cmdline = { completion = { ghost_text = { enabled = false } } },
  },
}'''),
    blank,
    ...para('--',
        r'The target is saghen/blink.cmp, the completion engine, and the change is two nested '
        r'options in opts. completion.ghost_text.enabled = false covers the normal insert-mode menu. '
        r'cmdline.completion.ghost_text.enabled = false covers the command line, where LazyVim’s '
        r'extra enables the preview for the selected item.'),
    blank,
    ...para('--',
        r'Both are set explicitly instead of one. That is the whole point of the second half of the '
        r'header: a spec that only disabled the insert-mode option would leave the cmdline preview '
        r'that LazyVim turns on. Writing out both makes the file independent of what LazyVim’s extra '
        r'decides.'),
    ...sec(r'edge cases'),
    ...pt('--', r'vim.g.ai_cmp',
        r'the header names it as the second trigger. When it is set, LazyVim enables ghost text on '
        r'its own. Forcing the option to false in opts overrides the value the extra computes, since '
        r'the repo’s opts are merged after it.'),
    ...pt('--', r'no other completion source',
        r'this repo has an AI agent (99) and a claudecode integration, and neither of them is '
        r'configured through ghost text here. The file does not discuss them.'),
    ...sec(r'how it is tested'),
    ...pt('--', r'tests/startup-and-options_spec.lua',
        r'describe "plugins/no-ghost-text.lua" at line 646. One test reads the spec opts and asserts '
        r'both options are false. A second test (line 653) reads the loaded blink.cmp config and '
        r'asserts the same two values at runtime, so a later spec that overrides the setting would '
        r'be caught.'),
    ...pt('--', r'tests/snippets-completion-injections_spec.lua',
        r'line 289: "ghost text is disabled in insert mode and in the cmdline". This spec lists '
        r'lua/plugins/no-ghost-text.lua in its header, next to the snippet provider wiring from '
        r'editing-ui.lua.'),
    ...sec(r'history'),
    ...pt('--', r'8891f17 (2026-10-12)',
        r'"Disable blink.cmp ghost text everywhere". It added this file, a CHANGELOG line and a '
        r'README edit, three files in total, so the decision and its documentation arrived together. '
        r'It is the only commit that touches the file.'),
    ...sec(r'is it in xyno-plugins?'),
    ...para('--',
        r'No. It is a configuration file for an upstream plugin, not a Rust-specific tool, and it '
        r'was not part of the extraction on 2026-10-22.'),
  ],
);
