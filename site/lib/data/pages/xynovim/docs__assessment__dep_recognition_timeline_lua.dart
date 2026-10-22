import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/docs/assessment/dep-recognition-timeline.lua',
  lines: [
    cm('--', 'dep-recognition-timeline.lua: how long until a new dependency is recognised?'),
    cm('--', 'A probe, not a test: it never fails, it prints what both diagnostic tiers'),
    cm('--', 'and a hover say, every three seconds, after rand = 0.9 is written to'),
    cm('--', 'Cargo.toml from inside nvim.'),
    blank,
    ...para('--', 'This is the probe behind gap G5 of the macros and dependencies plan: after adding a dependency, rust-analyzer knew it within seconds, but the clippy tier kept reporting a missing crate for as long as anyone looked. The script is 26 lines, written to be run once with nvim headless against a throwaway crate, and it produced the 61-second observation in the plan.'),
    blank,
    kv('role', 'measurement script; prints timings, asserts nothing'),
    kv('language', 'Lua for Neovim, run with nvim --headless -S'),
    kv('size', '26 lines, most of them long one-liners'),
    kv('input', 'a crate with src/main.rs and Cargo.toml in the working directory'),
    kv('output', 'lines starting T: with bacon, ra and hover columns'),
    kv('created', '42558fa, 2026-10-14'),
    blank,
    ...sec('why this file exists'),
    ...para('--', 'The plan describes the effect as a false red error right after a dependency is added. The script turns that into a timeline. It reproduces the situation exactly: open the crate, wait for rust-analyzer, put a use of rand in main.rs so there is an error, then add the dependency to Cargo.toml from nvim and watch which source stops complaining first. The observation, in the plan, is that rust-analyzer resolved it in about 10 seconds while bacon-ls kept the error until a FocusGained event restarted it.'),
    ...sec('the output helper and the setup'),
    ...code('lua', r'docs/assessment/dep-recognition-timeline.lua · lines 1-5', r'''
local function out(...) local t={} for i=1,select('#',...) do t[#t+1]=tostring((select(i,...))) end io.stdout:write(table.concat(t," ").."\n") io.stdout:flush() end
vim.cmd("edit src/main.rs"); vim.cmd("doautocmd User VeryLazy")
vim.wait(60000, function() return #vim.lsp.get_clients({bufnr=0,name="rust-analyzer"})>0 end, 200)
local c = vim.lsp.get_clients({bufnr=0,name="rust-analyzer"})[1]
vim.wait(20000)'''),
    ...para('--', 'Line 1 defines out(), which writes one line to stdout and flushes, so that each result line reaches stdout at once, even if the run is killed later. Lines 2 and 3 open main.rs, fire User VeryLazy by hand because that event never fires headless and the configuration attaches things on it, then wait up to 60 seconds for rust-analyzer to attach. Line 5 waits another 20 seconds before anything is measured.'),
    ...sec('creating the error'),
    ...code('lua', r'docs/assessment/dep-recognition-timeline.lua · lines 6-9', r'''
local main = vim.api.nvim_get_current_buf()
local lines = vim.api.nvim_buf_get_lines(main,0,-1,false)
for i, l in ipairs(lines) do if l:find("Ok(())", 1, true) then table.insert(lines, i, "    let _r: u8 = rand::random();"); break end end
vim.api.nvim_buf_set_lines(main,0,-1,false,lines); vim.cmd("silent write")'''),
    ...para('--', 'The script finds the line containing Ok(()), inserts a statement before it that calls rand::random, writes the buffer and saves. At this point rand is not a dependency, so the source is wrong on purpose. Using plain string find with the init argument 1 and the plain flag avoids pattern surprises in the search.'),
    ...sec('the probes'),
    ...code('lua', r'docs/assessment/dep-recognition-timeline.lua · lines 10-13', r'''
local function bacon_msgs() local t={} for _,d in ipairs(vim.diagnostic.get(main)) do if d.source=="bacon-ls" then t[#t+1]=d.message:match("^[^\n]*"):sub(1,80) end end return table.concat(t," || ") end
local function ra_msgs() local t={} for _,d in ipairs(vim.diagnostic.get(main)) do if d.source=="rust-analyzer" then t[#t+1]=d.message:match("^[^\n]*"):sub(1,60) end end return table.concat(t," || ") end
local l0 for i,s in ipairs(vim.api.nvim_buf_get_lines(main,0,-1,false)) do if s:find("rand::random",1,true) then l0=i-1 end end
local function hover() local r=c:request_sync("textDocument/hover",{textDocument=vim.lsp.util.make_text_document_params(main),position={line=l0,character=24}},8000,main); local h=r and r.result; return h and (h.contents.value or ""):gsub("%s+"," "):sub(1,60) or "nil" end'''),
    ...para('--', 'Three small functions turn editor state into columns. bacon_msgs() collects the first line of every diagnostic whose source is bacon-ls, cut to 80 characters; ra_msgs() does the same for rust-analyzer; hover() locates the position of the random call and asks the rust-analyzer client for textDocument/hover synchronously, with an 8 second budget, returning the first 60 characters flattened to one line. Together they give the three signals that matter: what the clippy tier thinks, what the instant tier thinks, and whether the language server can actually resolve the name.'),
    ...para('--', 'The hover is a separate signal from the diagnostics: it is a fresh request to the rust-analyzer client at the time of each sample, so it shows whether that server can resolve the name now.'),
    ...sec('baseline, then the change'),
    ...code('lua', r'docs/assessment/dep-recognition-timeline.lua · lines 14-18', r'''
vim.wait(25000, function() return bacon_msgs():find("rand") ~= nil end, 500)
out("T: BEFORE adding dep: bacon=", bacon_msgs(), " ra=", ra_msgs(), " hover=", hover())
vim.cmd("edit Cargo.toml")
vim.api.nvim_buf_set_lines(0,-1,-1,false,{'rand = "0.9"'}); vim.cmd("silent write")
local t0=vim.uv.now(); vim.cmd("buffer "..main)'''),
    ...para('--', 'Line 14 waits up to 25 seconds for bacon-ls to complain about rand, so there is a baseline. Line 15 prints the BEFORE line with all three columns. Then the script edits Cargo.toml, appends rand = 0.9 on a new line at the end of the file (the throwaway crate is assumed to end in its dependencies table), writes it, records the start time with the libuv clock, and switches back to the main buffer so that diagnostics for it are the ones sampled.'),
    ...sec('the sampling loop'),
    ...code('lua', r'docs/assessment/dep-recognition-timeline.lua · lines 19-26', r'''
local fired=false
for step=1,40 do
  vim.wait(3000)
  local s=(vim.uv.now()-t0)/1000
  out(string.format("T: t=%3.0fs bacon=[%s] ra=[%s] hover=%s", s, bacon_msgs():sub(1,110), ra_msgs():sub(1,60), hover()))
  if step==20 and not fired then fired=true; out("T: -- doautocmd FocusGained"); vim.cmd("doautocmd FocusGained") end
  if not bacon_msgs():find("rand") and hover():find("rand") then out("T: RECOGNISED at", s); break end
end'''),
    ...para('--', 'The loop runs up to 40 times and waits three seconds per step, so it can observe up to 120 seconds. Each step prints the elapsed time, the clippy tier’s messages (110 characters), the instant tier’s (60) and the hover. At step 20, which is about 60 seconds in, it fires FocusGained by hand and prints a marker line, unless the loop has already ended. The plan’s G5 row says the stale error was cleared by a FocusGained event within 3 s and that a terminal that does not report focus never gets that event. The loop breaks as soon as bacon-ls no longer mentions rand and the hover does, and prints RECOGNISED with the time.'),
    ...sec('what the numbers meant and what was done'),
    ...para('--', 'The values in the plan are the output of this script: hover empty at 6 s and resolved at 10 s, bacon-ls still red at 61 s, cleared within 3 s after the focus event. They led directly to items 0.1 and 0.2 of the plan: restart bacon-ls 500 ms after a saved Cargo.toml or Cargo.lock, and show deps resolving in the statusline until rust-analyzer finishes reloading. The tests for those fixes are deps-freshness and server-supervision-statusline, with the 120 second ceiling checked by a shimmed timer, not by waiting.'),
    ...para('--', 'The PLAN status table notes honestly that the 61 s timeline probe was not re-run end to end after the fix. The script is therefore evidence for the problem, not for the cure.'),
    ...sec('edge cases and limits'),
    ...pt('--', 'Hard-coded sleeps', '60 s, 20 s, 25 s and 3 s steps are fixed in the code; a slower machine may need larger values.'),
    ...pt('--', 'Single dependency', 'only rand is tried, with a version string; features and workspaces are not covered.'),
    ...pt('--', 'Cargo.toml edit by append', 'works only when the file ends inside the dependencies table.'),
    ...pt('--', 'Assumes cwd is the crate', 'there is no argument handling and no cleanup.'),
    ...sec('how it is tested'),
    ...para('--', 'Not tested. The script is a probe, kept for reproducibility. The regression coverage for the behaviour it measured is in deps-freshness_spec.lua, which uses a real rust-analyzer, and the statusline timers are in server-supervision-statusline_spec.lua.'),
    ...sec('history'),
    ...pt('--', '2026-10-14', '42558fa adds it with the other four probes. It has not changed since.'),
    blank,
  ],
);
