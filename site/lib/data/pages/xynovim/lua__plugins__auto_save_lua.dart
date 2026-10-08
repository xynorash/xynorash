import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/auto-save.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'auto-save.lua — background saves language servers can live with'),
    cm('--', 'a debounced autosave, and the one notification it must not swallow'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'saves buffers in the background and re-sends textDocument/didSave to LSP clients'),
    kv('language', 'Lua (a lazy.nvim spec for okuuva/auto-save.nvim)'),
    kv('size', '53 lines: 34 of code, 18 of comment, 1 blank'),
    kv('history', '6 commits over 17 days, 2026-08-17 to 2026-09-03; one hack written, regretted, replaced'),
    kv('pinned', 'auto-save.nvim at 9aabcb8 in lazy-lock.json'),
    ...sec('why this file exists'),
    ...para('--',
        r'Two sentences from the CHANGELOG explain the file. 0.2.0 '
        r'(an early Windows-lineage release) added auto-save.nvim “for '
        r'RustRover-style background auto-save”. And 1.3.0 explains why '
        r'it matters to the Rust setup: the auto-save fires about one '
        r'second after typing stops, and that save was what used to '
        r'trigger clippy runs. So the file started as a comfort feature '
        r'and became part of the diagnostics pipeline, which is why 18 '
        r'of its 53 lines are comment.'),
    blank,
    ...para('--',
        r'The plugin is the okuuva fork, not the original. CHANGELOG '
        r'0.2.0 says the original Pocco81/auto-save.nvim “has been '
        r'unmaintained since 2024-05”, and the commit message of '
        r'3dacffb says it has been dead since 2024. The lock file pins '
        r'the fork at commit 9aabcb8.'),
    blank,
    ...para('--',
        r'The spec is eager only in a narrow sense. It loads on the '
        r'first of three events rather than at startup:'),
    ...code('lua', 'lua/plugins/auto-save.lua · the spec header (trimmed)', r'''
return {
  "okuuva/auto-save.nvim",
  event = { "InsertLeave", "TextChanged", "TextChangedI" },
  config = function()
    ...
  end,
}'''),
    ...para('--',
        r'Nothing is saved or loaded until the first edit of a session. '
        r'The third event, TextChangedI, was added by a bug fix on '
        r'2026-08-18 and has its own section below.'),

    ...sec('the setup call: three kinds of trigger'),
    ...code('lua', 'lua/plugins/auto-save.lua · the setup call', r'''
    require("auto-save").setup({
      enabled = true,
      noautocmd = true,
      trigger_events = {
        immediate_save = { "BufLeave", "FocusLost", "QuitPre", "VimSuspend" },
        -- TextChanged only fires for edits made OUTSIDE insert mode; its
        -- insert-mode counterpart is TextChangedI. Without it, the debounced
        -- save (and the didSave notify above that rides on it) never fires
        -- while still actively typing - only once you leave insert mode.
        defer_save = { "InsertLeave", "TextChanged", "TextChangedI" },
        cancel_deferred_save = { "InsertEnter" },
      },
      debounce_delay = 1000,
    })'''),
    ...para('--',
        r'The three lists in trigger_events describe three behaviours.'),
    ...pt('--', 'immediate_save',
        r'leaving a buffer, losing window focus, quitting, or '
        r'suspending Neovim writes at once. These are the moments when '
        r'work could be lost, so there is no waiting.'),
    ...pt('--', 'defer_save',
        r'ordinary edits write only after debounce_delay, here 1000 ms '
        r'of quiet. CHANGELOG 1.3.0 calls it “the ~1s auto-save”.'),
    ...pt('--', 'cancel_deferred_save',
        r'entering insert mode cancels a pending debounced write. '
        r'Combined with TextChangedI re-arming the timer on the next '
        r'change, a burst of typing produces one save at the end of the '
        r'burst, not one per keystroke.'),
    blank,
    ...para('--',
        r'Commit 6d1e9c9 records the property this depends on: the '
        r'debounce “cancels/reschedules per trigger (read auto-save’s '
        r'own source), so this doesn’t flood saves while typing”. '
        r'The behaviour was checked in the plugin’s code, not '
        r'assumed from its README.'),

    ...sec('noautocmd, and what it costs'),
    ...para('--',
        r'noautocmd = true is the line that makes this file '
        r'interesting. The original reason, from the 3dacffb commit '
        r'comment and CHANGELOG 0.2.0, was format-on-save: the plugin '
        r'writes with noautocmd so that BufWritePre and BufWritePost do '
        r'not run, and the formatter therefore does not reformat the '
        r'file every second while typing. Only a manual :w formats. '
        r'It was tested, and CHANGELOG 0.2.0 reports how: “an '
        r'intentionally mis-formatted file survives an autosave '
        r'untouched, then reformats correctly on manual save.”'),
    blank,
    ...para('--',
        r'One honest wrinkle belongs here. Today lua/config/options.lua '
        r'sets vim.g.autoformat = false, LazyVim’s global switch, and '
        r'the README lists “format-on-save off globally” and, a few '
        r'lines earlier, says “manual :w still formats”. Those two '
        r'claims are not obviously compatible with each other, and I '
        r'could not settle from the repo which formatter path the '
        r'manual :w uses now. What is certain is the history: '
        r'noautocmd came from a conform-based Windows setup, and it '
        r'stayed. Its side effect is the reason the rest of this page '
        r'exists.'),

    ...sec('the bug: diagnostics that only moved on :w'),
    ...para('--',
        r'On 2026-08-18 the live-diagnostics loop of the time '
        r'(rust-analyzer with check.command = "clippy") worked after a '
        r'manual :w and not after an autosave. The commits of that '
        r'afternoon read like a debugging log. First, 9a170c2 chased '
        r'the obvious suspect: Neovim’s update_in_insert defaults to '
        r'false, so diagnostics only redraw on InsertLeave, which looks '
        r'like “only updates on save”, since Esc always precedes :w. It '
        r'was set to true, and the symptom stayed.'),
    blank,
    ...para('--',
        r'Then 3ab52cd did what good debugging does: it eliminated the '
        r'healthy parts of the pipeline with evidence, and what was '
        r'left was the answer. The Windows-lineage CHANGELOG entry '
        r'lists the cleared suspects:'),
    ...pt('--', 'didChange',
        r'fires correctly on every edit.'),
    ...pt('--', 'document sync',
        r'correct, verified because hover reflected brand-new code '
        r'within seconds.'),
    ...pt('--', 'pull diagnostics',
        r'Neovim’s own pull-diagnostic refresh is wired automatically '
        r'on attach.'),
    ...pt('--', 'what was left',
        r'a write made with noautocmd skips every autocmd, including '
        r'the LSP client’s BufWritePost handler that sends '
        r'textDocument/didSave. “Confirmed directly: a noautocmd write '
        r'sends zero LSP notifications; a normal write sends '
        r'didSave.”'),
    blank,
    ...para('--',
        r'The comment at the top of the config function keeps that '
        r'conclusion, in its current wording, for the next reader:'),
    ...code('lua', 'lua/plugins/auto-save.lua · why didSave matters', r'''
    -- noautocmd (below) skips BufWritePre/BufWritePost for autosaves so
    -- conform's format-on-save doesn't fire on every debounced autosave -
    -- but that also silently skips the LSP clients' BufWritePost-triggered
    -- `textDocument/didSave` (confirmed directly: `noautocmd write` sends
    -- zero LSP notifications, a normal `write` sends didSave). bacon-ls
    -- relies on didSave to restore its shadow-workspace hardlinks, and any
    -- save-aware LSP behavior needs it.'''),
    ...para('--',
        r'Note how the stated reason changed over time. In 3ab52cd the '
        r'consumer of didSave was rust-analyzer’s on-save clippy '
        r'refresh. After the move to bacon-ls, CHANGELOG 1.1.0 says '
        r'the proxy was “no longer load-bearing for diagnostics '
        r'(bacon-ls listens to didChange, not didSave)”. Then the bacon-ls '
        r'investigation found a different consumer: the server needs '
        r'didSave to restore its shadow workspace, and 1.4.0 patched '
        r'bacon-ls itself because of how didSave was handled '
        r'(see lua/plugins/bacon-ls.lua). A notification that looks '
        r'redundant today can become load-bearing tomorrow, which is '
        r'the argument for sending it correctly instead of '
        r'deleting it.'),

    ...sec('the first fix, and the regression it caused'),
    ...para('--',
        r'The first fix (3ab52cd, 2026-08-18 14:38) had a real '
        r'constraint: auto-save.nvim had no hook for “a save just '
        r'happened”. So the config replaced the global vim.cmd with a '
        r'wrapper that recognised the exact command string the plugin '
        r'builds internally (a Lua pattern beginning with the literal '
        r'noautocmd, then silent! w), called the real vim.cmd, and sent '
        r'didSave to the current buffer’s clients afterwards. It '
        r'verified the result end to end: an error typed, no manual '
        r'save, diagnostic in about 1.5 s. That figure is easy to '
        r'read: a one-second debounce and about half a second for '
        r'everything else, my arithmetic rather than a measured split.'),
    blank,
    ...para('--',
        r'It also broke something. vim.cmd is not a plain function; '
        r'it is a callable table that supports vim.cmd("...") and '
        r'dot-calls like vim.cmd.write() and vim.cmd.helptags(). '
        r'Replacing it with a function removed every dot-call for the '
        r'whole session. 43 minutes later (df3c5ae, 15:21) the '
        r'regression was found in live use, not in a test. The error '
        r'text is in the CHANGELOG: lazy.nvim’s own documentation '
        r'update failed with “attempt to index field ’cmd’ (a '
        r'function value)”. The patch became a proxy built with '
        r'setmetatable: __index forwarded dot-access to the real '
        r'table, and __call intercepted only the string form.'),
    blank,
    ...para('--',
        r'That is two defects in one global replacement, in the same '
        r'afternoon, from a hack that was individually well reasoned. '
        r'The proxy also had a standing cost that 1.3.0 named when it '
        r'was removed: it matched the plugin’s internal command string, '
        r'so it would break silently on an upstream rename, and it put '
        r'a metatable indirection in front of every vim.cmd call in the '
        r'session.'),

    ...sec('the supported hook'),
    ...para('--',
        r'On 2026-09-03 (f35b4f6) the proxy was deleted in favour of '
        r'something the plugin offers deliberately: a User event named '
        r'AutoSaveWritePost, fired after the write, carrying the saved '
        r'buffer in data.saved_buffer. The comment records the '
        r'reasoning: “the User event survives plugin refactors, the '
        r'string match didn’t.”'),
    ...code('lua', 'lua/plugins/auto-save.lua · the hook', r'''
    local group = vim.api.nvim_create_augroup("user_autosave_didsave", { clear = true })
    vim.api.nvim_create_autocmd("User", {
      pattern = "AutoSaveWritePost",
      group = group,
      callback = function(ev)
        local buf = ev.data and ev.data.saved_buffer
        if not (buf and vim.api.nvim_buf_is_valid(buf)) then
          return
        end
        for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
          if client:supports_method("textDocument/didSave", buf) then
            client:notify("textDocument/didSave", {
              textDocument = { uri = vim.uri_from_bufnr(buf) },
            })
          end
        end
      end,
    })'''),
    ...para('--',
        r'Each detail in the callback closes a gap that the proxy '
        r'left open.'),
    ...pt('--', 'clear = true',
        r'the augroup is recreated on each run of the config function, '
        r'so re-sourcing never stacks duplicate handlers. The same '
        r'discipline appears in plugin/after/transparency.lua.'),
    ...pt('--', 'ev.data and ev.data.saved_buffer',
        r'the event hands over which buffer was written. The proxy '
        r'used buffer 0, the current buffer, which is a guess that the '
        r'written buffer and the focused one are the same. With saves '
        r'on BufLeave and FocusLost that is not obviously true; the '
        r'new code stops guessing.'),
    ...pt('--', 'nvim_buf_is_valid',
        r'a debounced event can arrive after the buffer is gone; the '
        r'guard turns that into a quiet return.'),
    ...pt('--', 'vim.lsp.get_clients({ bufnr = buf })',
        r'only clients attached to that buffer, so a Lua language '
        r'server in another window is not told about a Rust file.'),
    ...pt('--', 'supports_method("textDocument/didSave", buf)',
        r'only servers that actually accept the notification receive '
        r'it, and the buffer argument lets capability checks be '
        r'per-buffer.'),
    ...pt('--', 'the payload',
        r'only the document URI, built from the buffer. The '
        r'notification carries no text; presumably the servers already '
        r'hold the content from didChange.'),
    blank,
    ...para('--',
        r'CHANGELOG 1.3.0 reports the verification of the swap: '
        r'“didSave still reaches both LSP clients, BufWritePre '
        r'(format-on-save skip) still suppressed.” Both halves matter. '
        r'The replacement must add the missing notification without '
        r'also bringing back the autocmds that noautocmd was there to '
        r'suppress.'),

    ...sec('what didSave does for bacon-ls now'),
    ...para('--',
        r'The config’s own comment says bacon-ls relies on didSave to '
        r'restore the shadow workspace. That connects this file to the '
        r'upstream-bug story. With checkOnSave off (bacon-ls.lua), a '
        r'didSave no longer starts a run, but it still reaches the '
        r'server. In the unpatched 0.29.0 server, a didSave arriving '
        r'about 200 ms into the final run of a typing burst aborted '
        r'that run, because the auto-save debounce (1000 ms) and the '
        r'server’s debounce (then 800 ms) were separated by exactly '
        r'200 ms. And a didSave landing inside the server’s own debounce '
        r'window cancelled a pending check and replaced it with nothing. '
        r'Both are fixed in the patched build, but both were exposed by '
        r'this file doing its job: saving, and telling the server.'),
    blank,
    ...para('--',
        r'With the current 500 ms server debounce the arithmetic is '
        r'kinder. A run starts at about t0 + 500 ms and, at a median of '
        r'about 60 ms warm, is usually finished before the 1000 ms '
        r'auto-save fires. That is a reading of numbers from '
        r'bacon-ls.lua’s comments, and the patch means the ordering no '
        r'longer decides correctness.'),

    ...sec('TextChangedI: the missing half of an event'),
    ...para('--',
        r'The fix of 6d1e9c9 (2026-08-18 14:45, about six minutes after '
        r'the first didSave fix) is small and instructive. The first '
        r'version of the file had defer_save = InsertLeave, TextChanged. '
        r'The commit message states the catch: TextChanged fires only '
        r'for edits made outside insert mode, and its insert-mode twin '
        r'is TextChangedI. Without it the debounced save, and the '
        r'didSave riding on it, did not run while actively typing; it '
        r'ran only after Esc.'),
    blank,
    ...para('--',
        r'The test design is the good part. It was verified “with '
        r'InsertLeave never fired anywhere in the test”: a diagnostic '
        r'appeared in about 1.5 s from TextChangedI alone. A test that '
        r'still lets the old trigger fire proves nothing about the new '
        r'one, so the old one was taken out of the experiment. '
        r'TextChangedI was added to both the plugin’s lazy-load event '
        r'(line 3) and defer_save.'),

    ...sec('how it grew'),
    cm('--', '  2026-08-17 16:02  3dacffb  17 lines, plain opts: the fork,'),
    cm('--', '                             noautocmd, the three trigger lists'),
    cm('--', '  2026-08-18 14:38  3ab52cd  config function + vim.cmd wrapper'),
    cm('--', '  2026-08-18 14:45  6d1e9c9  TextChangedI'),
    cm('--', '  2026-08-18 15:21  df3c5ae  vim.cmd proxy (the regression fix)'),
    cm('--', '  2026-09-02 23:42  eabb22a  moved to lua/plugins/ in the'),
    cm('--', '                             LazyVim migration, “carried over intact”'),
    cm('--', '  2026-09-03 19:54  f35b4f6  proxy replaced by AutoSaveWritePost'),
    blank,
    ...para('--',
        r'Of the 53 lines today, only the setup call is recognisably '
        r'the original file. Almost everything else is the answer to '
        r'one question, “what does noautocmd take away?”.'),

    ...sec('limits'),
    ...pt('--', 'noautocmd takes away more than didSave',
        r'it suppresses every BufWritePre and BufWritePost listener, '
        r'not just the LSP one. This file compensates for exactly one '
        r'of them. Any other plugin that reacts to a write will not see '
        r'autosaves; I have no evidence of such a plugin in this '
        r'config, but nothing here would notice if there were.'),
    ...pt('--', 'it relies on the fork’s event contract',
        r'that AutoSaveWritePost fires after the write and carries '
        r'data.saved_buffer. The lock file pins one commit, and the '
        r'repo has no automated test that pins the contract; the '
        r'check is the manual one in CHANGELOG 1.3.0.'),
    ...pt('--', 'it can only tell servers about saves it did',
        r'a save made by another means (a plain :w) goes through '
        r'Neovim’s normal path and sends its own didSave.'),
    ...pt('--', 'the formatter question',
        r'see the wrinkle above: global autoformat is off, so the '
        r'noautocmd guard against format-on-save is now defence in '
        r'depth more than a necessity, if I read options.lua '
        r'correctly.'),
    ...sec('what to take from it'),
    ...pt('--', 'eliminate the healthy parts first',
        r'the didSave diagnosis worked because the pipeline was cut '
        r'into pieces and each was shown to be fine.'),
    ...pt('--', 'never replace a global to intercept one call',
        r'the vim.cmd proxy needed two rounds to become correct and '
        r'was still the wrong tool. Look for the supported event '
        r'first.'),
    ...pt('--', 'test the new path alone',
        r'the TextChangedI check took the old trigger out of the '
        r'test.'),
    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
  ],
);
