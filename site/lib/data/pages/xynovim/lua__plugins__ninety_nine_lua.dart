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
    kv('size', '283 lines (79 until 2026-10-09)'),
    kv('history', '13 commits, 2026-08-17 to 2026-10-21 (the first two under lua/config/plugins/): a local clone, a lazy GitHub spec, then a guarded sandboxed provider'),
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
        r'completion in 99’s prompt buffer; the comment says only '
        r'that blink.compat is “required by 99’s blink completion '
        r'source”.'),
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
      provider = Guarded,
      model = "claude-sonnet-5",
      provider_extra_args = { "--effort", "medium" },'''),
    ...pt('--', 'provider',
        r'no longer the stock ClaudeCodeProvider. Since 625b48d '
        r'(2026-10-09) it is Guarded, a metatable wrapper around that '
        r'provider (see “the guarded provider” below).'),
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
        level = _99.INFO,
        path = vim.fn.stdpath("state") .. "/99.log",
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
        r'The path used to be computed from the working directory, as '
        r'/tmp/<dirname>.99.debug at DEBUG level, so two projects with the '
        r'same directory name shared a log. It now points at '
        r'stdpath("state") .. "/99.log" at INFO: one stable file in '
        r'Neovim’s state directory that survives reboots. The change '
        r'is recorded in tests/agent-99-guard_spec.lua (“logs to '
        r'stdpath(’state’)/99.log at INFO with print_on_error”) and a '
        r'README-claims case that checks the path ~/.local/state/nvim/'
        r'99.log.'),
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

    ...sec('the guarded provider'),
    ...para('--',
        r'Most of the file’s growth is one idea. 99 drives claude with '
        r'--dangerously-skip-permissions, so a request can do anything '
        r'the user can. The config therefore replaces the provider with a '
        r'wrapper that adds guards. The comment at the top of the '
        r'block names them: checkpoint the worktree as a git ref before '
        r'every request, keep auto-save from writing the agent’s edits '
        r'straight to disk while requests are in flight, and run claude '
        r'inside bubblewrap.'),
    ...code('lua', 'lua/plugins/ninety-nine.lua · lines 51-57', r'''
    -- Safety wrapper around the stock Claude Code provider (see README
    -- roadmap step 5): checkpoint the worktree as a git ref before every
    -- request, keep auto-save from writing the agent's edits straight to disk
    -- while requests are in flight, and run claude inside bubblewrap.
    local Claude = _99.Providers.ClaudeCodeProvider
    local Guarded = setmetatable({}, { __index = Claude })
    local inflight, we_disabled_autosave = 0, false'''),
    ...para('--',
        r'Guarded is an empty table whose __index is the stock provider, '
        r'so every method it does not override falls through. Only '
        r'fetch_models, _build_command and make_request are replaced.'),
    ...sec('auto-save off while the agent works'),
    ...code('lua', 'lua/plugins/ninety-nine.lua · lines 59-89', r'''
    -- One token per request; release() is idempotent so the counter drops
    -- exactly once however the request ends (on_complete, sync throw, or a
    -- cancel that never reaches on_complete).
    local function acquire()
      if inflight == 0 then
        local ok, as = pcall(require, "auto-save")
        we_disabled_autosave = ok and as.enabled() == true
        if we_disabled_autosave then
          as.off()
        end
      end
      inflight = inflight + 1
      return { done = false }
    end

    local function release(token)
      if token.done then
        return
      end
      token.done = true
      inflight = math.max(0, inflight - 1)
      if inflight == 0 and we_disabled_autosave then
        we_disabled_autosave = false
        -- Only undo our own change: if the user switched auto-save back on
        -- meanwhile, there is nothing to restore.
        local ok, as = pcall(require, "auto-save")
        if ok and as.enabled() ~= true then
          as.on()
        end
      end
    end'''),
    ...para('--',
        r'This is a reference count with an owner flag. The first request '
        r'turns auto-save off, remembering whether it was on; later '
        r'requests only increment. When the last one releases, auto-save '
        r'comes back only if this code turned it off and nobody has '
        r'switched it on in the meantime. The token makes release '
        r'idempotent, which matters because a request can end three ways '
        r'(on_complete, a synchronous throw, or a cancel that never reaches '
        r'on_complete). The reason for the whole mechanism is the '
        r'auto-save page: an autosave a second after the agent edits a '
        r'file would write the agent’s half-finished work to disk. '
        r'tests/agent-99-guard_spec.lua has cases for it, '
        r'among them “a duplicate completion after cancel does not '
        r'double-decrement” and “does not touch auto-save the user '
        r'switched on meanwhile”.'),
    ...sec('fail closed, then checkpoint, then start'),
    ...code('lua', 'lua/plugins/ninety-nine.lua · lines 112-134', r'''
    function Guarded.make_request(self, query, context, observer)
      -- Fail closed before anything else happens (no snapshot, no auto-save
      -- toggle, no process): claude runs with --dangerously-skip-permissions.
      local st = require("config.agent_sandbox").status()
      if st.mode == "refused" then
        local msg = "99 refused to start: "
          .. st.reason
          .. ". The agent only runs sandboxed (Linux with bubblewrap, or WSL2 with bubblewrap). To run it anyway"
          .. " set vim.g.xynovim_99_allow_unsandboxed = true: claude --dangerously-skip-permissions then runs"
          .. " with your full privileges."
        vim.notify(msg, vim.log.levels.ERROR)
        pcall(observer.on_start)
        pcall(observer.on_complete, "failed", msg)
        return nil
      elseif st.mode == "unsandboxed" then
        vim.notify(
          "99 runs claude --dangerously-skip-permissions WITHOUT a sandbox ("
            .. st.reason
            .. "): the whole filesystem, your credentials and the network are reachable.",
          vim.log.levels.WARN
        )
      end'''),
    ...para('--',
        r'440d781 (2026-10-16, “Agent sandbox fails closed when no sandbox '
        r'backend is available”) added this gate. config.agent_sandbox '
        r'reports a mode: a working backend, unsandboxed (only through an '
        r'explicit opt-in), or refused. When refused, the request never '
        r'starts: the observer is told it started and failed, so the 99 UI '
        r'does not hang, and the message names the opt-in variable. The '
        r'ordering is stated in the comment: nothing happens first, no '
        r'snapshot, no auto-save toggle, no process. See the page for '
        r'lua/config/agent_sandbox.lua for the sandbox itself, and the '
        r'standalone xyno-sandbox.nvim plugin (xyno_sandbox/init.lua and '
        r'run.lua), which holds the same idea as a reusable module.'),
    ...code('lua', 'lua/plugins/ninety-nine.lua · lines 167-181', r'''
      -- The agent must not start before the checkpoint holds the pre-request
      -- state (a fast agent rewrote files while the snapshot was still
      -- reading them): start from the snapshot's `done`, or after 15 s.
      local path = vim.api.nvim_buf_get_name(0)
      if path ~= "" and vim.fs.root(path, ".git") then
        vim.defer_fn(start, 15000)
        require("config.local_history").snapshot({
          path = path,
          force = true,
          label = "before 99 request",
          done = start,
        })
      else
        start()
      end
      return result'''),
    ...para('--',
        r'The checkpoint is a call into the local history module (the '
        r'config.local_history page): a forced snapshot labelled “before '
        r'99 request”. The agent starts from the snapshot’s done callback. '
        r'The fallback timer of 15 seconds came in 98c9bb4 after a field '
        r'finding recorded in the comment: a fast agent rewrote files '
        r'while the snapshot was still reading them, so starting '
        r'in parallel was wrong. start() is guarded by a started flag and '
        r'by token.done, so whichever of the callback and the timer fires '
        r'second does nothing, and a cancel before the checkpoint is '
        r'finished never starts the agent.'),
    ...sec('wrapping the command, and the model list'),
    ...code('lua', 'lua/plugins/ninety-nine.lua · lines 91-110', r'''
    -- The Claude provider's model list is static (the CLI cannot list models)
    -- and predates claude-sonnet-5, the model set below.
    function Guarded.fetch_models(callback)
      Claude.fetch_models(function(models, err)
        if models then
          table.insert(models, 1, "claude-sonnet-5")
        end
        callback(models, err)
      end)
    end

    function Guarded._build_command(self, query, context)
      local cmd = Claude._build_command(self, query, context)
      local project = vim.fs.root(0, ".git") or vim.uv.cwd()
      local wrapped, err = require("config.agent_sandbox").wrap(cmd, project, tmp_dir)
      if not wrapped then
        error("99 sandbox: " .. tostring(err), 0)
      end
      return wrapped
    end'''),
    ...para('--',
        r'fetch_models prepends the model the config uses to the static '
        r'list so the <leader>9m picker shows it (99acd7e). _build_command '
        r'takes the command the stock provider would run and passes it, '
        r'with the project root (git root or cwd) and the temp directory, to '
        r'agent_sandbox.wrap, which returns the bubblewrap command line or '
        r'nil plus a reason. A nil result is raised as an error, again '
        r'failing closed. Tests assert that the command starts with bwrap, '
        r'ends with claude, drops GITHUB_TOKEN, and, in a real run, that the '
        r'token is actually invisible to the wrapped process.'),
    ...sec('the provider picker cannot bypass the guard'),
    ...code('lua', 'lua/plugins/ninety-nine.lua · lines 213-226', r'''
    -- The <leader>9P picker (and anything else) swaps the provider with
    -- _99.set_provider. The stock providers of the other CLIs run with no
    -- sandbox, no checkpoint and no auto-save guard, so only the guarded
    -- provider may be selected unless the sandbox was switched off explicitly.
    local set_provider = _99.set_provider
    -- allow_unsandboxed only counts when no backend exists (status().via);
    -- with a working bwrap only sandbox = false opts out.
    local function allowed(provider)
      if provider == Guarded or vim.g.xynovim_99_sandbox == false then
        return true
      end
      local st = require("config.agent_sandbox").status()
      return st.mode == "unsandboxed" and st.via == "allow_unsandboxed"
    end'''),
    ...para('--',
        r'a2e0d5a and af6ca87 (both 2026-10-21, “Cross-platform: review '
        r'fixes”) closed a hole. 99 ships providers for other CLIs, and '
        r'the <leader>9P picker could select any of them, which would run '
        r'with no sandbox, checkpoint or auto-save guard. set_provider is '
        r'now overridden: only Guarded is accepted, unless the sandbox '
        r'was switched off with vim.g.xynovim_99_sandbox = false, or no '
        r'backend exists and vim.g.xynovim_99_allow_unsandboxed = true. '
        r'The comment spells out a subtle rule: allow_unsandboxed only '
        r'counts when no backend exists, so with a working bubblewrap only '
        r'sandbox = false opts out.'),
    ...code('lua', 'lua/plugins/ninety-nine.lua · lines 227-258', r'''
    -- The opt-in is re-checked on EVERY request, not only at selection: a
    -- provider chosen under it must not keep running once it is revoked, and
    -- each unsandboxed request warns.
    local proxies = {}
    local function checked(provider)
      if provider == Guarded or provider == nil then
        return provider
      end
      if not proxies[provider] then
        proxies[provider] = setmetatable({
          _xyno_inner = provider,
          make_request = function(self, query, context, observer)
            if not allowed(provider) then
              local msg = "99 refused to start: this provider runs without the sandbox, checkpoint and auto-save"
                .. " guard, and the opt-in (vim.g.xynovim_99_sandbox = false or vim.g.xynovim_99_allow_unsandboxed"
                .. " = true) is not set any more. Select the Claude Code provider (<leader>9P)."
              vim.notify(msg, vim.log.levels.ERROR)
              pcall(observer.on_start)
              pcall(observer.on_complete, "failed", msg)
              return nil
            end
            vim.notify(
              "99 runs this provider WITHOUT a sandbox, checkpoint or auto-save guard: the whole filesystem,"
                .. " your credentials and the network are reachable.",
              vim.log.levels.WARN
            )
            return provider.make_request(self, query, context, observer)
          end,
        }, { __index = provider })
      end
      return proxies[provider]
    end'''),
    ...para('--',
        r'Checking at selection time is not enough: a user could select '
        r'another provider under the opt-in, later revoke it, and the '
        r'selection would still be live. So any non-guarded provider is '
        r'wrapped in a cached proxy that re-checks allowed() on every '
        r'make_request, fails with the same observer protocol as above, '
        r'and warns on every unsandboxed run. The proxies table is keyed '
        r'by provider so repeated selections reuse one proxy.'),
    ...code('lua', 'lua/plugins/ninety-nine.lua · lines 259-281', r'''
    function _99.set_provider(provider)
      if not allowed(provider) then
        vim.notify(
          "99: only the guarded Claude Code provider can be selected (the other providers run without the"
            .. " sandbox, checkpoint and auto-save guard). Set vim.g.xynovim_99_sandbox = false or"
            .. " vim.g.xynovim_99_allow_unsandboxed = true to allow them.",
          vim.log.levels.ERROR
        )
        return _99
      end
      return set_provider(checked(provider))
    end
    -- the picker announces "Provider set" after its call: skip that when refused
    local pickers = require("99.extensions.pickers")
    local on_selected = pickers.on_provider_selected
    function pickers.on_provider_selected(name, lookup)
      local provider = lookup[name]
      if provider and not allowed(provider) then
        _99.set_provider(provider) -- prints the refusal
        return
      end
      return on_selected(name, lookup)
    end'''),
    ...para('--',
        r'The last override patches the picker’s own callback. Without '
        r'it the picker would print “Provider set” after set_provider '
        r'had refused, which is a lie; with it a refusal prints exactly '
        r'one message. tests/agent-failclosed_spec.lua checks the 99 '
        r'provider is guarded and that make_request refuses where no '
        r'sandbox exists; its other cases cover that only the two '
        r'explicit booleans lead to an unsandboxed run.'),
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
    cm('--', '  2026-10-09  625b48d  Guarded provider, snapshot, auto-save token'),
    cm('--', '  2026-10-12  0494b52  idempotent acquire/release, cancel handling'),
    cm('--', '  2026-10-13  99acd7e  fetch_models adds claude-sonnet-5'),
    cm('--', '  2026-10-13  98c9bb4  15 s start timer behind the snapshot'),
    cm('--', '  2026-10-16  440d781  fail closed without a sandbox backend'),
    cm('--', '  2026-10-21  a2e0d5a  provider picker guarded (af6ca87 follow-up)'),
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
        r'The first versions were verified by hand, as the changelog '
        r'describes. That is no longer the whole story: '
        r'tests/agent-99-guard_spec.lua covers lazy loading, the eleven '
        r'keys (each asserted to call the right function with the right '
        r'description), the absolute tmp_dir, the 7-day prune, the setup '
        r'arguments, fetch_models, command wrapping, make_request, the '
        r'auto-save token and the logger, and tests/agent-failclosed_spec.lua covers the refusal '
        r'paths.'),

    ...sec('limits'),
    ...pt('--', 'permissions',
        r'the provider still passes --dangerously-skip-permissions. What '
        r'changed is the sandbox around it. With the opt-in variables '
        r'set, it runs with the user’s full privileges, and the config '
        r'says so in every warning.'),
    ...pt('--', 'the model is hard-coded',
        r'claude-sonnet-5 is a string in the file; it has already '
        r'changed once (from claude-sonnet-4-5).'),
    ...pt('--', 'pruning is silent',
        r'there is no log line when files are deleted, and only plain '
        r'files in the top level of the directory are considered.'),
    ...pt('--', 'monkey-patching a plugin',
        r'set_provider and pickers.on_provider_selected are replaced '
        r'in place. An update to 99 that renames either would let the '
        r'guard fall away, which is the failure mode of this design; the '
        r'spec tests are the early warning.'),
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
    link('→ github.com/xynorash/xynovim', 'https://github.com/xynorash/xynovim'),
    link('→ github.com/ThePrimeagen/99', 'https://github.com/ThePrimeagen/99'),
  ],
);
