import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/snacks-animated-scrolling-off.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'snacks-animated-scrolling-off.lua — scrolling that just scrolls'),
    cm('--', 'one boolean on one module of folke/snacks.nvim'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'disables the smooth-scroll animation provided by snacks.nvim'),
    kv('language', 'Lua (a lazy.nvim spec that only supplies opts); tab-indented'),
    kv('size', '8 lines, one of them a trailing comment'),
    kv('history', '1 commit, eabb22a (2026-09-02); never changed'),
    kv('pinned', 'snacks.nvim at 882c996 in lazy-lock.json'),
    ...sec('the whole file'),
    ...code('lua', 'lua/plugins/snacks-animated-scrolling-off.lua · the entire file', r'''
return {
  "folke/snacks.nvim",
  opts = {
    scroll = {
      enabled = false, -- Disable scrolling animations
    },
  },
}'''),
    ...para('--',
        r'The file name is a sentence: snacks, animated scrolling, '
        r'off. The only comment in the file, “Disable scrolling '
        r'animations”, repeats it. With a name that complete, the '
        r'comment is the repo’s entire stated rationale, and it '
        r'describes what the line does, not why it was wanted.'),

    ...sec('what it changes'),
    ...para('--',
        r'snacks.nvim is a collection of small modules by folke, each '
        r'with its own opts group. This file reaches into one of '
        r'them, scroll, and flips its enabled flag. Nothing else in '
        r'snacks is touched: the merge described on the '
        r'disable-news-alert.lua page combines this opts table with '
        r'whatever the rest of the config and LazyVim set, key by '
        r'key.'),
    blank,
    ...para('--',
        r'An override that sets enabled = false is only meaningful if '
        r'the module is on without it. That is an inference from the '
        r'existence of the file, not something the repo states, and I '
        r'could not look inside the pinned snacks.nvim or LazyVim to '
        r'confirm the default. The consequence for the reader is '
        r'clear enough from the comment: jumping by a page or a '
        r'half-page moves the view in one step instead of gliding '
        r'there over a few frames.'),

    ...sec('where it sits in the config'),
    ...para('--',
        r'This is the second of the two LazyVim tweaks that the 1.0.0 '
        r'changelog lists in a single line, together with '
        r'disable-news-alert.lua. They have the same history and '
        r'the same tab-indented style, a style that differs from '
        r'the two-space layout stylua.toml asks for. Both facts are '
        r'consistent with the files having arrived from the '
        r'Omarchy defaults and been kept, which is an inference and '
        r'not a statement from the repo.'),

    ...sec('what is not recorded'),
    ...pt('--', 'a reason beyond the comment',
        r'there is no changelog line, commit message or README '
        r'sentence that says why animated scrolling is unwanted. It '
        r'reads as a taste decision, and the file is honest about '
        r'being nothing more.'),
    ...pt('--', 'a measurement',
        r'the startup work in CHANGELOG 1.3.0 measured startup time, '
        r'not scrolling. Nothing says this file affects either, and '
        r'I will not claim a performance benefit.'),
    ...pt('--', 'a test',
        r'the repo has no check that the flag still has an effect. '
        r'If a future snacks renamed the scroll module, the file '
        r'would stay valid Lua and do nothing. The lock file pins '
        r'snacks.nvim at one commit, which is the protection.'),
    blank,
    ...para('--',
        r'To undo it: delete the file, or change false to true. '
        r'Because it is a separate file named after its effect, '
        r'reverting costs one deletion and leaves no trace in any '
        r'other spec, which is the reason the config keeps '
        r'preferences like this one file each.'),
    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
