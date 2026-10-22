import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/startup-and-options_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'startup-and-options_spec.lua — facts about a fresh start, the lockfile, the extras and the small plugins'),
    cm('--', r'child nvim processes for what only a clean start can show, and exact lists for what must not drift'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for init.lua, lua/config/{lazy,options,autocmds,remote_clipboard}.lua, lazyvim.json, lazy-lock.json and eight small plugin files'),
    kv(r'language', r'Lua spec, 1231 lines, 63 it() blocks, 1 pending, 20 describe() blocks'),
    kv(r'platform', r'Linux only (reads /proc and uses sh stubs for wl-copy and wl-paste)'),
    kv(r'method', r'fresh-start facts come from child nvim processes; everything else runs in the runner own nvim'),
    kv(r'history', r'8 commits, 2026-10-13 to 2026-10-16'),
    ...sec(r'why this file exists'),
    ...para('--', r'The facts that decide whether this configuration is pleasant to use are mostly about startup: that it prints nothing, that it is fast, that only a handful of plugins load, that the plugin set is exactly the one locked, and that the lockfile and the extras file say what the README says. None of those can be tested from the editor that the test runner itself is changing. So the spec starts child nvim processes with the full config for those facts, and for everything else it uses the running editor. The header explains this split.'),
    ...code('lua', r'tests/startup-and-options_spec.lua · lines 1-9', r'''
-- Startup, options, lazy.nvim setup, lockfile, extras and the small plugin
-- spec files (news, scrolling, telescope, ghost text, gitsigns, codelens,
-- harpoon, navigation) plus config/remote_clipboard.lua.
--
-- Facts about a FRESH startup (what is loaded, which messages appeared) come
-- from child nvim processes (`child()`), because the runner's own editor is
-- changed by the earlier tests. Everything else runs in the runner's nvim.
-- xyno-os: linux (reads /proc, uses sh stubs for wl-copy, wl-paste)
local H = require("xynotest.helpers")'''),
    ...sec(r'a child with a script'),
    ...para('--', r'child(body, opts) writes a small Lua script that, after VimEnter and a 300 ms wait for the config scheduled work, runs the given body in xpcall and prints the result as JSON between markers, and quits. The runner then decodes the JSON. Options allow a different environment, a cleared environment, extra arguments and a different executable. This is how the spec asks questions like what is PATH at startup or what are the messages without disturbing itself.'),
    ...code('lua', r'tests/startup-and-options_spec.lua · lines 56-90', r'''
    io.stdout:write("\nXYNO_JSON " .. vim.json.encode({ ok = ok, res = res }) .. "\n")
    vim.cmd("qa!")
  end, 300)
end })
]]):format(body)
  )
  local cmd = { opts.cmd or vim.fn.exepath("nvim"), "--headless" }
  vim.list_extend(cmd, opts.args or {})
  vim.list_extend(cmd, { "-S", script })
  local t0 = vim.uv.hrtime()
  local r = vim.system(cmd, { text = true, env = opts.env, clear_env = opts.clear_env, cwd = dir }):wait(60000)
  local ms = (vim.uv.hrtime() - t0) / 1e6
  local line = ((r.stdout or "") .. (r.stderr or "")):match("XYNO_JSON (%b{})")
  if not line then
    error(("child nvim printed no result (exit %s)\nstdout: %s\nstderr: %s"):format(r.code, r.stdout, r.stderr), 2)
  end
  local out = vim.json.decode(line)
  if not out.ok then
    error("child script failed: " .. tostring(out.res), 2)
  end
  return out.res, r, ms
end

local MESSAGES = [[
  return {
    messages = vim.api.nvim_exec2("messages", { output = true }).output,
    errmsg = vim.v.errmsg,
  }
]]

local function xdg_env()
  local env = {}
  for _, k in ipairs({ "HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "TMPDIR" }) do
    env[k] = vim.env[k]
  end'''),
    ...sec(r'quiet, fast, lazy'),
    ...para('--', r'Fresh startup prints no messages, leaves v:errmsg empty, and has no lazy spec notifications; it reports a start time under 3000 ms by the --startuptime log (its last line must be NVIM STARTED) and a child wall clock under 6000 ms, with the 300 ms wait allowed for in the comment. It loads between 1 and 20 plugins and fewer than half of the total; it has more than 50 plugins and the space key as the leader. A comment records a discrepancy that was found in the README at the time: lazy stats count is the number of plugins in the spec (61 on the author machine, equal to the lockfile), not the 80 the README said.'),
    ...code('lua', r'tests/startup-and-options_spec.lua · lines 160-196', r'''
describe("fresh headless startup", function()
  it("prints no messages, leaves v:errmsg empty and has no lazy spec notifications", function()
    local p = probe()
    H.eq("", vim.trim(p.messages))
    H.eq("", p.errmsg)
    H.eq(0, p.notifs)
    -- the runner's own editor agrees
    H.eq({}, Config.spec.notifs)
  end)

  it("is well under 3000 ms (--startuptime and wall clock)", function()
    local log = H.tmpdir() .. "/startup.log"
    local _, _, ms = child("return {}", { args = { "--startuptime", log } })
    local last = vim.trim(read(log)):match("([^\n]+)$")
    local stamp = tonumber(last:match("^%s*(%d+%.%d+)"))
    H.ok(stamp, "no timestamp in the last startuptime line: " .. last)
    H.match(last, "NVIM STARTED", true)
    -- the child also waits 300 ms in its script before quitting
    H.ok(stamp < 3000, ("--startuptime reports %.1f ms"):format(stamp))
    H.ok(ms < 6000, ("child wall clock %.0f ms (includes 300 ms wait and nvim exit)"):format(ms))
  end)

  it("loads only a handful of plugins at startup", function()
    local p = probe()
    -- README: "~5 of 80 plugins loaded". DISCREPANCY recorded: lazy.stats().count is
    -- the number of plugins in the spec (61 on this machine, equal to the
    -- lockfile), not 80 as the README says.
    H.ok(p.loaded >= 1 and p.loaded <= 20, "loaded " .. p.loaded)
    H.ok(p.loaded < p.count / 2, ("loaded %d of %d"):format(p.loaded, p.count))
  end)

  it("has more than 50 plugins and <Space> as the leader", function()
    local p = probe()
    H.ok(p.count > 50, "count " .. p.count)
    H.eq(" ", p.leader)
    H.eq(" ", vim.g.mapleader)
  end)'''),
    ...sec(r'PATH and a cache that cannot be written'),
    ...para('--', r'The Rust tools live in ~/.cargo/bin, which a non-login start does not have. The test starts a child with PATH set to /usr/bin:/bin and requires the result to be that path with the cargo bin appended, and when the cargo bin is already first, no duplicate. A second test points XDG_CACHE_HOME at an impossible path under /proc and requires that lazy module cache is switched off, that LazyVim was still set up, and that the message E739 never appears: an unwritable cache must not abort init.lua.'),
    ...code('lua', r'tests/startup-and-options_spec.lua · lines 202-213, 283-296', r'''
  it("~/.cargo/bin is appended when a non-login start lacks it (rust-analyzer not found)", function()
    local cargo_bin = vim.uv.os_homedir() .. "/.cargo/bin"
    if vim.fn.isdirectory(cargo_bin) == 0 then
      return require("xynotest.harness").skip("no ~/.cargo/bin on this machine")
    end
    local env = xdg_env()
    env.PATH = "/usr/bin:/bin"
    local res = child("return { path = vim.env.PATH }", { env = env })
    H.eq("/usr/bin:/bin:" .. cargo_bin, res.path)
    env.PATH = cargo_bin .. ":/usr/bin"
    H.eq(cargo_bin .. ":/usr/bin", child("return { path = vim.env.PATH }", { env = env }).path, "not added twice")
  end)
...
  it("an unwritable XDG_CACHE_HOME turns lazy's module cache off instead of aborting init.lua (E739)", function()
    local env = xdg_env()
    env.XDG_CACHE_HOME = "/proc/xyno-unwritable-cache"
    local r = child([[
      return {
        cache = require("lazy.core.config").options.performance.cache.enabled,
        lazyvim = package.loaded["lazyvim.config"] ~= nil,
        messages = vim.api.nvim_exec2("messages", { output = true }).output,
      }
    ]], { env = env })
    H.eq(false, r.cache)
    H.eq(true, r.lazyvim, "LazyVim was set up")
    H.no_match(r.messages, "E739", true)
  end)'''),
    ...sec(r'lazy.lua and options'),
    ...para('--', r'lazy.lua targets stdpath data lazy lazy.nvim with a blobless stable clone, uses LazyVim with the lazyvim.plugins import and the plugins import, defaults lazy = false and version = false, sets the install colourscheme order island-dark, tokyonight, habamax, disables rocks, has the update checker off (and never started), and disables exactly gzip, tarPlugin, tohtml, tutor and zipPlugin of the runtime plugins; the disabled ones did not run while matchparen and netrw did. Options: relativenumber off, autoformat off, rounded borders, pumblend 0; the python3, ruby, perl and node providers are skipped; bacon-ls is selected for Rust diagnostics and rust-analyzer checkOnSave is off; every config module sets up its augroups and commands; autocmds.lua is comments only; and an http buffer has conceallevel 0.'),
    ...sec(r'the extras file and the lockfile'),
    ...para('--', r'lazyvim.json has version 8, install_version 8 and exactly 17 extras under the lazyvim.plugins.extras prefix; the list matches the README; and every extra module exists in the installed LazyVim and is requirable. lazy-lock.json is valid JSON where every entry has a branch and a 40-hex commit; it pins kulala.nvim at v5.3.4 and keeps tokyonight and catppuccin; it has no Omarchy-only theme plugins; it has no entry absent from the plugin spec and covers the whole spec. The strongest test checks every locked plugin on disk.'),
    ...code('lua', r'tests/startup-and-options_spec.lua · lines 489-501, 585-604', r'''
  it("lists exactly the 17 extras, version 8, install_version 8", function()
    local d = extras()
    H.eq(8, d.version)
    H.eq(8, d.install_version)
    local names = {}
    for _, e in ipairs(d.extras) do
      H.eq(prefix, e:sub(1, #prefix), e)
      names[#names + 1] = e:sub(#prefix + 1)
    end
    table.sort(names)
    H.eq(17, #names)
    H.eq(expected, names)
  end)
...
  it("every locked plugin is installed with its git HEAD at the pinned commit", function()
    local dir = vim.fn.stdpath("data") .. "/lazy"
    local bad = {}
    for _, n in ipairs(names) do
      local plugin_dir = (Config.plugins[n] and Config.plugins[n].dir) or (dir .. "/" .. n)
      if vim.fn.isdirectory(plugin_dir) ~= 1 then
        bad[#bad + 1] = n .. ": not installed"
      else
        local r = vim.system({ "git", "-C", plugin_dir, "rev-parse", "HEAD" }, { text = true }):wait(10000)
        if vim.trim(r.stdout or "") ~= lock[n].commit then
          bad[#bad + 1] = ("%s: HEAD %s, pinned %s"):format(n, vim.trim(r.stdout or "?"), lock[n].commit)
        end
      end
    end
    H.eq({}, bad)
    -- kulala sits exactly on its tag
    local r = vim.system({ "git", "-C", dir .. "/kulala.nvim", "describe", "--tags", "--exact-match" }, { text = true })
      :wait(10000)
    H.eq("v5.3.4", vim.trim(r.stdout or ""))
  end)'''),
    ...sec(r'small plugin files'),
    ...para('--', r'Each tiny plugin file gets a few lines of test: the news alert is off in both checks; Snacks scrolling is off and the toggle on leader u S stays; telescope is lazy; ghost text is off for the menu and the cmdline in the options and in the loaded blink config; gitsigns attach_to_untracked works; codelens is enabled and maps leader c c and c C buffer-locally; harpoon uses branch harpoon2, registers lazy keys globally, uses a rounded border on its quick menu (it hardcodes single), and does not claim leader a; navigation configures satellite, trouble call hierarchy keys, the custom mini.surround surroundings S, O, N, D, U (also deleting the right wrapper when the content has its own brackets), and treesj.'),
    ...sec(r'remote clipboard'),
    ...para('--', r'config/remote_clipboard.lua installs a clipboard provider inside tmux, SSH or herdr. The tests: nothing happens outside those, with no herdr ancestor; an ancestor process whose comm contains herdr is detected; the provider is installed for each of TMUX, SSH_CONNECTION, SSH_TTY and HERDR_PANE_ID; without Wayland or wl-copy and wl-paste it copies by OSC52 only and pastes with osc52.paste; with Wayland it runs wl-copy --sensitive --type text/plain (--primary for the star register) and emits OSC52, and wl-paste --no-newline returning an empty table on a non-zero exit; vim.g.xynovim_remote_clipboard_osc52 = false suppresses the emit and an old omarchy_ name is ignored.'),
    ...sec(r'walking a process tree safely'),
    ...para('--', r'Finding a herdr ancestor reads /proc. The last test of the block builds fake process chains through a replaced reader: a chain ending at init never reads process 1 even though it is named herdr; an unreadable status of the first parent gives no provider and no error; a missing entry deeper in the chain is tolerated; and a cycle that never reaches init, with herdr placed at step 17, reads at most 16 status files and never sees it. The walk is bounded, so a corrupt /proc cannot hang startup.'),
    ...code('lua', r'tests/startup-and-options_spec.lua · lines 1148-1184', r'''
  it("the ancestor walk stops at ppid <= 1, is bounded to 16 steps and survives unreadable /proc entries", function()
    -- stops at ppid <= 1: a herdr 'above' init is never looked at
    local chain = {
      [1000] = { ppid = 500, comm = "nvim" },
      [500] = { ppid = 1, comm = "bash" },
      [1] = { ppid = 0, comm = "herdr" },
    }
    with_fake_proc(chain, function(reads)
      H.is_nil(setup({}))
      for _, r in ipairs(reads) do
        H.no_match(r, "/proc/1/", true)
      end
    end)
    -- unreadable status of the first parent: no error, no provider
    with_fake_proc({ [1000] = { ppid = 500, comm = "nvim", unreadable = true } }, function()
      H.is_nil(setup({}))
    end)
    -- a missing /proc entry deeper in the chain
    with_fake_proc({ [1000] = { ppid = 500, comm = "nvim" }, [500] = { ppid = 400, comm = "x" } }, function()
      H.is_nil(setup({}))
    end)
    -- a cycle that never reaches init: at most 16 status reads, herdr at step 17 is not seen
    local cyc = { [1000] = { ppid = 2000, comm = "nvim" } }
    for i = 0, 20 do
      cyc[2000 + i] = { ppid = 2000 + i + 1, comm = i == 17 and "herdr" or "sh" }
    end
    with_fake_proc(cyc, function(reads)
      H.is_nil(setup({}))
      local status = 0
      for _, r in ipairs(reads) do
        if r:match("/status$") then
          status = status + 1
        end
      end
      H.ok(status <= 16, "status reads: " .. status)
    end)
  end)'''),
    ...sec(r'unusual environments'),
    ...para('--', r'Clean startup is checked with TMUX set, with an empty environment (only HOME and the XDG directories) and with a PATH of nvim, git and timeout only and no WAYLAND_DISPLAY, in each case with no messages.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'b2fee5c (2026-10-13)', r'created. 98c9bb4, 3f868dd (2026-10-13), f31e013, 25086fd (2026-10-14) :: field test rounds.'),
    ...pt('--', r'0b0eee8 (2026-10-14)', r'README showcase, which touched the numbers. ff1c8fa, 9641d08 (2026-10-16) :: the Linux-only header and Windows details.'),
  ],
);
