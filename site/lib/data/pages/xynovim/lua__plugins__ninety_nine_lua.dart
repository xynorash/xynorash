import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/lua/plugins/ninety-nine.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'ninety-nine.lua — an AI assistant, with the footguns fixed'),
    cm('--', 'ThePrimeagen’s 99 on the Claude Code provider, lazy-loaded'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'configures ThePrimeagen/99 to use the claude CLI, and binds its 11 keymaps'),
    kv('language', 'Lua (a lazy.nvim spec with a keys table and a config function)'),
    kv('size', '79 lines: 60 of code, 17 of comment, 2 blank'),
    kv('history', '5 commits since 2026-08-17, from a local clone to a lazy-loaded GitHub spec'),
    kv('pinned', '99 at c174224 and blink.compat at 2ed6d9a in lazy-lock.json'),
    ...sec('why this file exists'),
    ...para('--',
        r'99 is ThePrimeagen’s AI plugin for Neovim. This file points '
        r'it at the Claude Code command line instead of a hosted API: '
        r'provider ClaudeCodeProvider, model claude-sonnet-5, with '
        r'--effort medium on every request. The README describes the '
        r'flow it enables: a search whose results land in the quickfix '
        r'list, a visual-selection replace, and telescope pickers for '
        r'model and provider, all under <leader>9.'),
    blank,
    ...para('--',
        r'Most of the 79 lines are not about what the assistant does. '
        r'They are about three ways a correct-looking configuration '
        r'fails silently, and how to keep it from doing so: a temp '
        r'directory that two programs resolve differently, a logger '
        r'that logs nowhere, and a plugin that is loaded long before '
        r'anyone presses a key. The README calls these “hard-won '
        r'configuration notes”.'),

    ...sec('the spec: dependencies and keys'),
    ...code('lua', 'lua/plugins/ninety-nine.lua · the spec header', r'''
return {
  "ThePrimeagen/99",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    -- required by 99's blink completion source
    { "saghen/blink.compat", version = "2.*" },
  },
  -- Everything is reached through these keymaps, so lazy-load on them
  -- instead of eager-loading 99 + telescope + blink.compat at startup.
  keys = {'''),
    ...para('--',
        r'Two dependencies come with the plugin. telescope.nvim powers '
        r'the model and provider pickers. blink.compat is there for '
        r'completion in 99’s prompt buffer: 99’s completion source '
        r'speaks the older nvim-cmp protocol, and blink.compat lets '
        r'LazyVim’s blink.cmp engine consume it (the comment says only '
        r'that blink.compat is “required by 99’s blink completion '
        r'source”; the nvim-cmp detail is my gloss).'),
    blank,
    ...para('--',
        r'The keys table is the lazy-loading trigger. This config sets '
        r'defaults.lazy = false in lua/config/lazy.lua, with the '
        r'comment that user plugins otherwise “load during startup”. '
        r'So until commit f35b4f6 (2026-09-03) 99, telescope and '
        r'blink.compat all loaded on every launch. Declaring keys is '
        r'what makes lazy.nvim defer the plugin until the first '
        r'keypress. CHANGELOG 1.3.0 lists this among the changes that '
        r'took startup from 28.7 ms to about 18 ms. It does not break '
        r'out a number for 99 alone, so I will not either.'),
    ...code('lua', 'lua/plugins/ninety-nine.lua · three of the eleven keys', r'''
    { "<leader>9s", function() require("99").search() end, desc = "99: Search" },
    { "<leader>9v", function() require("99").vibe() end, desc = "99: Vibe" },
    { "<leader>9vv", function() require("99").visual() end, mode = "v", desc = "99: Visual" },'''),
    ...para('--',
        r'The require happens inside each callback, not at the top of '
        r'the spec, so evaluating the spec costs nothing. That is the '
        r'same rule the harpoon page explains in detail. Note also that '
        r'<leader>9v (normal mode, vibe) is a prefix of '
        r'<leader>9vv (visual mode, replace the selection). The two '
        r'do not conflict because they live in different modes: the '
        r'longer one is declared with mode = "v", the shorter is '
        r'normal-mode only.'),
    blank,
    cm('--', '  key              mode  action'),
    cm('--', '  ---------------  ----  --------------------------------'),
    cm('--', '  <leader>9s       n     search (results to quickfix)'),
    cm('--', '  <leader>9v       n     vibe'),
    cm('--', '  <leader>9vv      v     replace the visual selection'),
    cm('--', '  <leader>9o       n     open last interaction'),
    cm('--', '  <leader>9l       n     view logs'),
    cm('--', '  <leader>9c       n     clear previous requests'),
    cm('--', '  <leader>9x       n     stop all requests'),
    cm('--', '  <leader>9w       n     worker search'),
    cm('--', '  <leader>9W       n     worker set work'),
    cm('--', '  <leader>9m       n     select model (telescope)'),
    cm('--', '  <leader>9P       n     select provider (telescope)'),
    blank,
    ...para('--',
        r'The provider picker is capital P and the comment on it gives '
        r'the reason: “capitalized: keeps the provider picker grouped '
        r'with the model picker”. An earlier comment, in the Windows '
        r'lineage, explained the same choice differently (leaving a '
        r'lowercase <leader>9p free for a future prev/next-style '
        r'binding), a small example of a rationale that was rewritten '
        r'when the surrounding config changed.'),

    ...sec('the model, and the option that is not a patch'),
    ...para('--',
        r'The setup call opens with three lines, and one of them has '
        r'changed over the file’s life:'),
    ...code('lua', 'lua/plugins/ninety-nine.lua · provider and model', r'''
    _99.setup({
      provider = _99.Providers.ClaudeCodeProvider,
      model = "claude-sonnet-5",
      provider_extra_args = { "--effort", "medium" },'''),
    ...pt('--', 'model',
        r'the first commit (2026-08-17) used claude-sonnet-4-5. The '
        r'second commit that day bumped it to claude-sonnet-5.'),
    ...pt('--', 'provider_extra_args',
        r'added in the same commit. CHANGELOG 0.2.0 explains the '
        r'choice of mechanism: the effort level is set “via 99’s own '
        r'provider_extra_args setup option (not a source patch, so it '
        r'isn’t lost on plugin updates)”. Use the knob the plugin '
        r'provides; never edit code that a plugin update will '
        r'overwrite.'),
    blank,
    ...para('--',
        r'The model name is a plain string in the file. Changing it '
        r'means editing the file, or picking another one at runtime '
        r'with <leader>9m.'),

    ...sec('the bug that looked like a broken tool'),
    ...para('--',
        r'CHANGELOG 1.2.0 opens with the symptom: 99’s responses were '
        r'always empty. The entry is a good example of how to write '
        r'down a root cause, so it is worth retelling in full.'),
    blank,
    ...para('--',
        r'99 works by giving the agent a placeholder file to fill in. '
        r'It chooses a path under tmp_dir, the agent writes its answer '
        r'there, and the plugin reads that file back. The two programs '
        r'are different processes that each have to agree where the '
        r'file is. The default tmp_dir was relative, and the two '
        r'sides resolved it differently:'),
    ...pt('--', '99',
        r'resolves a relative tmp_dir against Neovim’s working '
        r'directory.'),
    ...pt('--', 'claude',
        r'is agentic and works inside the project, so it resolves the '
        r'same relative TEMP_FILE path against the project directory.'),
    blank,
    ...para('--',
        r'Start Neovim as nvim Projects/foo/ from the home directory '
        r'and the two directories differ. In the entry’s words, claude '
        r'“faithfully wrote every answer to Projects/foo/tmp/99-*” '
        r'while 99 “read the empty placeholder in ~/tmp/99-*”. Then the '
        r'sentence that makes this a good story: “generation worked '
        r'the whole time; the completed responses were found sitting '
        r'unread on disk.”'),
    blank,
    ...para('--',
        r'The plugin’s own README warns about this, but the working '
        r'directory dependence is easy to miss, and an earlier '
        r'attempt the same day got it half right. The CHANGELOG '
        r'records that an earlier same-day fix to ./tmp, never '
        r'pushed, handled a system-temp case and still broke whenever '
        r'Neovim’s directory was not the project root. The shipped '
        r'fix removes the dependence on any working directory:'),
    ...code('lua', 'lua/plugins/ninety-nine.lua · the absolute tmp_dir', r'''
      -- MUST be absolute. 99 resolves a relative tmp_dir against nvim's cwd,
      -- but claude resolves the same relative TEMP_FILE against the project
      -- it's working in - launch nvim from outside the project (e.g.
      -- `nvim Projects/foo/` from ~) and the answer lands where 99 never
      -- reads, so every response comes back empty. An absolute path is
      -- unambiguous for both sides; writing outside claude's cwd is fine
      -- because the provider passes --dangerously-skip-permissions.
      tmp_dir = tmp_dir,'''),
    ...para('--',
        r'The value, ~/.cache/nvim/99 (vim.fn.stdpath("cache") plus /99), '
        r'is computed once near the top of the config function, so the '
        r'pruning code below and the setup call cannot disagree about '
        r'where the directory is. The entry reports verification '
        r'“end-to-end twice”: a real visual-mode request rewrote the '
        r'buffer correctly with the working directory inside the '
        r'project and with it at the home directory, “mimicking the '
        r'real launch shape”. Testing both shapes is the point. A '
        r'fix that works from the project root would have passed the '
        r'broken setup too.'),
    blank,
    ...para('--',
        r'The last clause of the comment is a security trade-off worth '
        r'stating plainly. Writing into a directory outside the '
        r'project is only possible because the provider passes '
        r'--dangerously-skip-permissions to claude, so the agent runs '
        r'without permission prompts. The config relies on that and '
        r'says so; the flag is the plugin’s choice, not this file’s. '
        r'It means every 99 request runs with the agent allowed to act '
        r'on your files without asking.'),

    ...sec('a logger that logs nowhere'),
    ...code('lua', 'lua/plugins/ninety-nine.lua · the logger', r'''
      display_errors = true,
      logger = {
        -- type = "file" is required for path to take effect; without it the
        -- logger silently uses a void sink (the README example omits it).
        type = "file",
        level = _99.DEBUG,
        path = "/tmp/" .. vim.fs.basename(vim.uv.cwd() or "nvim") .. ".99.debug",
        print_on_error = true,
      },'''),
    ...para('--',
        r'CHANGELOG 1.2.0 says Logger:configure needs type = "file" '
        r'before path means anything, that the plugin’s README example '
        r'leaves it out, and that anything else falls through to a '
        r'void sink. Then it adds the detail that ties this to the '
        r'previous section: “this log was what exposed the tmp_dir '
        r'mismatch”. The order matters: the logger had to work before '
        r'the mismatch could be seen, and the log then showed where '
        r'the answers were being written.'),
    blank,
    ...para('--',
        r'Two details of the path expression are worth reading. It is '
        r'computed once, when the config function runs. Because 99 is '
        r'lazy-loaded, that is the first <leader>9 key press, so the '
        r'log is named after the working directory at that moment and '
        r'does not follow a later :cd. And the fallback "nvim" covers a nil '
        r'current directory. The result is one log file per project '
        r'name, in /tmp: /tmp/foo.99.debug for a project directory '
        r'named foo. Two projects with the same directory name would '
        r'share a log; that is a limitation of the scheme and is not '
        r'addressed anywhere.'),
    blank,
    ...para('--',
        r'display_errors and print_on_error are the other half of '
        r'observability. Both belong to the “current recommended shape” '
        r'the 1.2.0 entry mentions, and by their names they make a '
        r'failure visible when it happens rather than only in a file.'),

    ...sec('pruning a cache the plugin never cleans'),
    ...code('lua', 'lua/plugins/ninety-nine.lua · the prune loop', r'''
    -- 99 never cleans its tmp_dir, so request files accumulate forever.
    -- Prune anything older than 7 days when 99 first loads in a session.
    local tmp_dir = vim.fn.stdpath("cache") .. "/99"
    if vim.uv.fs_stat(tmp_dir) then
      local cutoff = os.time() - 7 * 24 * 3600
      for name, kind in vim.fs.dir(tmp_dir) do
        if kind == "file" then
          local path = tmp_dir .. "/" .. name
          local stat = vim.uv.fs_stat(path)
          if stat and stat.mtime.sec < cutoff then
            vim.uv.fs_unlink(path)
          end
        end
      end
    end'''),
    ...para('--',
        r'CHANGELOG 1.3.0 gives the reason as a symptom: “99’s tmp dir '
        r'(~/.cache/nvim/99) grew forever”. The loop is short and '
        r'cautious. It does nothing unless the directory exists '
        r'(fs_stat). It looks only at plain files, never at '
        r'subdirectories. It compares each file’s modification time '
        r'against a cutoff of seven days, written as 7 * 24 * 3600 so '
        r'the unit is visible. Only then does it unlink. The '
        r'stat-then-check inside the loop guards a file that '
        r'disappears between listing and statting.'),
    blank,
    ...para('--',
        r'Putting the loop in the config function has a consequence '
        r'that follows from the lazy-loading: pruning happens when '
        r'99 first loads in a session, which is the first time a '
        r'<leader>9 key is pressed. A session that never uses 99 '
        r'never prunes, and that is fine because it never adds '
        r'files either. The seven-day threshold is a constant in '
        r'the code, not an option.'),

    ...sec('completion in the prompt buffer'),
    ...code('lua', 'lua/plugins/ninety-nine.lua · completion source', r'''
      completion = {
        -- #rules / @files completion in the prompt buffer via LazyVim's
        -- completion engine (default is the plugin's own "native" source).
        source = "blink",
      },'''),
    ...para('--',
        r'The prompt buffer understands #rules and @files references, '
        r'and by default 99 completes them with its own native source. '
        r'Switching to blink makes the same completion popup appear '
        r'that LazyVim shows everywhere else, and it is the reason '
        r'blink.compat is a dependency. This is the one setting in the '
        r'file that is pure comfort rather than a fix.'),

    ...sec('how it grew'),
    cm('--', '  2026-08-17  1c496fd  a local clone (dir = "~/personal/99"),'),
    cm('--', '                       model claude-sonnet-4-5, 5 keymaps'),
    cm('--', '  2026-08-17  3dacffb  model claude-sonnet-5, --effort medium'),
    cm('--', '  2026-09-02  eabb22a  loads from GitHub with a telescope'),
    cm('--', '                       dependency; keymaps gain desc labels'),
    cm('--', '  2026-09-03  07993a4  absolute tmp_dir, file logger,'),
    cm('--', '                       display_errors, blink completion,'),
    cm('--', '                       and the newer keymaps (v, o, l, c, w, W)'),
    cm('--', '  2026-09-03  f35b4f6  keymaps moved into lazy keys; pruning'),
    blank,
    ...para('--',
        r'The move from a local clone to a GitHub spec in 1.0.0 is a '
        r'quiet but real improvement: the old spec pointed at '
        r'~/personal/99, which, as that changelog puts it, “doesn’t '
        r'exist on this machine”. A config that depends on a '
        r'directory that only exists on one laptop is not portable. '
        r'The current spec can be rebuilt from the lock file alone.'),

    ...sec('how it was checked'),
    ...pt('--', 'tmp_dir',
        r'verified end-to-end twice, from two working directories '
        r'(1.2.0), as above.'),
    ...pt('--', 'keymaps',
        r'“all mapped functions verified to exist after setup”. This '
        r'is the check that matters for the newer API names (vibe, '
        r'view_logs, Worker) which came from the plugin’s current '
        r'recommended shape.'),
    ...pt('--', 'lazy-loading',
        r'startup improved from 28.7 ms to about 18 ms across a '
        r'bundle of changes that includes this one (1.3.0).'),
    blank,
    ...para('--',
        r'There is no automated test in the repository for any of '
        r'this. The verification is manual, described in the '
        r'changelog, and was done against the real plugin and the '
        r'real claude CLI. That is the honest status.'),

    ...sec('limits'),
    ...pt('--', 'permissions',
        r'the provider passes --dangerously-skip-permissions. The '
        r'assumption is that you trust the model and the prompt. The '
        r'config cannot change that.'),
    ...pt('--', 'one log per directory name',
        r'two projects named alike share /tmp/<name>.99.debug, and the '
        r'path is fixed when 99 first loads, as above.'),
    ...pt('--', 'the model is hard-coded',
        r'claude-sonnet-5 is a string in the file; it has already '
        r'changed once (from claude-sonnet-4-5).'),
    ...pt('--', 'pruning is silent',
        r'there is no log line when files are deleted, and only plain '
        r'files in the top level of the directory are considered.'),
    ...pt('--', 'tied to a plugin API',
        r'the Extensions.Worker keys and the logger options exist in '
        r'the version the lock file pins. A plugin update may change '
        r'them; the lock file is the guard.'),
    blank,
    ...para('--',
        r'What carries over from this file is how its comments are '
        r'written. Each one states the failure it prevents and how '
        r'it shows up (“every response comes back empty”, “silently '
        r'uses a void sink”, “accumulate forever”), which turns a '
        r'configuration file into a list of things that once went '
        r'wrong and are now impossible.'),
    blank,
    link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
    link('→ github.com/ThePrimeagen/99', 'https://github.com/ThePrimeagen/99'),
  ],
);
