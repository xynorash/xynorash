import '../models/project.dart';

// Authoring helpers. `p` is the filetype's line-comment leader.
CodeLine _cm(String p, String t) => CodeLine([Span('$p $t', Tok.comment)]);
const CodeLine _blank = CodeLine([Span(' ', Tok.plain)]);
CodeLine _plain(String t) => CodeLine([Span(t, Tok.plain)]);
CodeLine _heading(String t) => CodeLine([Span(t, Tok.heading)]);
CodeLine _link(String label, String url) =>
    CodeLine([Span(label, Tok.link, url: url)]);
CodeLine _kv(String k, String v) => CodeLine([
      Span(k, Tok.keyword),
      Span(' = ', Tok.punct),
      Span('"$v"', Tok.string),
      Span(';', Tok.punct),
    ]);
CodeLine _decl(String kw, String name, [String trail = '']) => CodeLine([
      Span(kw, Tok.keyword),
      Span(' ', Tok.plain),
      Span(name, Tok.fn),
      if (trail.isNotEmpty) Span(trail, Tok.punct),
    ]);
CodeLine _item(String p, String head, String rest) => CodeLine([
      Span('$p ', Tok.comment),
      Span(head, Tok.type),
      Span(' — $rest', Tok.comment),
    ]);

// Word-wraps `text` to `width` columns.
List<String> _wrap(String text, int width) {
  final out = <String>[];
  var cur = '';
  for (final w in text.split(' ')) {
    if (cur.isEmpty) {
      cur = w;
    } else if (cur.length + 1 + w.length <= width) {
      cur = '$cur $w';
    } else {
      out.add(cur);
      cur = w;
    }
  }
  if (cur.isNotEmpty) out.add(cur);
  return out;
}

// A wrapped comment paragraph.
List<CodeLine> _para(String p, String text, {int width = 62}) =>
    [for (final l in _wrap(text, width)) _cm(p, l)];

// A wrapped "head — rest" bullet; the head is highlighted, the tail wraps
// with a hanging indent.
List<CodeLine> _pt(String p, String head, String rest, {int width = 62}) {
  final ls = _wrap('$head — $rest', width);
  return [
    CodeLine([
      Span('$p ', Tok.comment),
      Span(head, Tok.type),
      Span(ls.first.substring(head.length), Tok.comment),
    ]),
    for (final l in ls.skip(1)) _cm(p, '  $l'),
  ];
}

// A blank line followed by a section heading.
List<CodeLine> _sec(String title) => [_blank, _heading('# $title')];

final List<Buffer> kBuffers = [
  Buffer(
    id: 'welcome',
    fileName: 'welcome.md',
    icon: '\u{f48a}',
    filetype: 'markdown',
    lines: [
      _heading(r'__  ____   ___   _  ___  ___    _   ___ _  _'),
      _heading(r'\ \/ /\ \ / / \ | |/ _ \| _ \  /_\ / __| || |'),
      _heading(r' >  <  \ V /| .`| | (_) |   / / _ \\__ \ __ |'),
      _heading(r'/_/\_\  |_| |_|\_|\___/|_|_\/_/ \_\___/_||_|'),
      _blank,
      _plain('Solving problems at the edge of impossible.'),
      _plain('Xynorash isn’t a name — it’s a coordinate.'),
      _blank,
      _cm('>', 'Nash Tefison · Rust · TypeScript · Dart · PowerShell · Neovim'),
      _blank,
      _heading('# projects'),
      _blank,
      _item('-', 'heaplens.rs', 'live heap inspector for Windows'),
      _item('-', 'xynovim.lua', 'my Neovim, tuned until it disappears'),
      _item('-', 'xyno_scholar.dart', 'AI research-topic explorer'),
      _item('-', 'xynorash.ps1', 'a PowerShell cockpit with neon vitals'),
      _item('-', 'xyno_arch.sh', 'my whole Arch desktop, reproducible'),
      _blank,
      _heading('# how to drive this site'),
      _blank,
      _plain('Space → menu · Space f → find project · : → cmdline'),
      _plain('j/k scroll · gg/G top/bottom · [b ]b switch buffer'),
      _plain('…or just click things. Mice are welcome here too.'),
      _blank,
      _cm('>', 'Built with Flutter web, styled after my xynovim setup.'),
      _link('→ github.com/XNash', 'https://github.com/XNash'),
    ],
  ),
  Buffer(
    id: 'heaplens',
    fileName: 'heaplens.rs',
    icon: '\u{e7a8}',
    filetype: 'rust',
    repo: 'heaplens',
    fallbackStars: 0,
    fallbackPushed: '2026-07-28',
    lines: [
      _cm('//', '──────────────────────────────────────────'),
      _cm('//', 'heaplens — a live heap inspector for native Windows'),
      _cm('//', 'see what your allocator sees, as it happens'),
      _cm('//', '──────────────────────────────────────────'),
      _blank,
      _kv('lang', 'Rust (system + daemon) · Dart/Flutter (UI)'),
      _kv('target', 'Windows x86_64 native processes'),
      _kv('shape', '7-crate Cargo workspace + Flutter desktop app'),
      _kv('method', 'spec → plan → tests → code, docs in the repo'),
      ..._sec('what it is'),
      ..._para('//',
          'Heap tooling is usually printf or a full profiler. heaplens '
          'is the middle: it watches every allocation a program makes, '
          'rebuilds who-owns-what as a live graph, flags the leaks while '
          'the program is still running, and draws it all in a desktop '
          'app. Your program is slowed by a lock-free ring buffer, not '
          'by graph building, symbol lookup or UI traffic.'),
      ..._sec('the pipeline'),
      _plain(r'  target process'),
      _plain(r'    └─ heaplens-alloc | heaplens-hook   (capture)'),
      _plain(r'         └─ named pipe, binary frames'),
      _plain(r'              └─ heaplens-daemon        (model)'),
      _plain(r'                   └─ WebSocket, JSON diffs @ ~33 ms'),
      _plain(r'                        └─ heaplens_flutter  (view)'),
      _blank,
      ..._para('//',
          'Exactly two seams couple the units: the binary frame '
          'protocol and the JSON diff protocol. Nothing else is shared, '
          'and each contract is defined in one place.'),
      ..._sec('the crates'),
      ..._pt('//', 'heaplens-protocol',
          'pure data: AllocEvent, frame codec, GraphDiff/NodeDto. No '
          'threads, no I/O, no logic.'),
      ..._pt('//', 'heaplens-alloc',
          'a #[global_allocator] wrapper that records every alloc, '
          'dealloc and realloc without blocking the host.'),
      ..._pt('//', 'heaplens-hook',
          'a cdylib that does the same job by inline-hooking a '
          'running process — no recompile, no relink.'),
      ..._pt('//', 'heaplens-injector',
          'loads the hook into a target by pid, with a safety gate '
          'that refuses sensitive processes first.'),
      ..._pt('//', 'heaplens-daemon',
          'ingest, ownership graph, anomaly detection, SQLite history '
          'and the WebSocket server.'),
      ..._pt('//', 'heaplens-launcher',
          'single-exe entry point: starts the daemon in a Job Object, '
          'waits for its port, then opens the UI.'),
      ..._pt('//', 'h1-harness',
          'the benchmark rig that measures detection latency from '
          'the daemon’s own recorded timestamps.'),
      ..._pt('//', 'heaplens_flutter',
          'the Windows desktop UI. Knows JSON only — no Rust, no '
          'pointers, no daemon internals.'),
      ..._sec('wire protocol'),
      ..._para('//',
          'AllocEvent is a #[repr(C)] 104-byte record: kind, pointer, '
          'old pointer (realloc), size, a monotonic timestamp and up to '
          '8 raw return addresses of the call stack. Frames are '
          'length-prefixed and typed — HANDSHAKE (pid + name), EVENTS '
          '(batched) and SYMBOLS (address → name, sent once per '
          'address). The producer flushes every 64 events or 1 ms.'),
      _blank,
      ..._para('//',
          'The streaming FrameDecoder survives partial reads and '
          'resynchronises on corruption instead of dying — it is tested '
          'against truncated, multi-frame and garbled input, not just '
          'the happy path.'),
      ..._sec('capture: the allocator'),
      ..._para('//',
          'Ten rules are written down as invariants. The ones that '
          'shape the code: the hot path never heap-allocates, never '
          'locks and never panics (a panic inside alloc would abort '
          'the host). The ring buffer’s backing store comes straight '
          'from System, not the global allocator. A writer thread '
          'drains the ring to the pipe and permanently holds a '
          'thread-local recursion guard, so heaplens never records '
          'its own allocations.'),
      _blank,
      ..._para('//',
          'Symbolization happens in the producer; the daemon only '
          'joins address → name. Calls into dbghelp are serialized, '
          'because Windows documents it as not thread-safe. Capture '
          'is opt-in: a heaplens-linked binary does nothing unless '
          'HEAPLENS_ENABLE is set — it is never attached by accident.'),
      ..._sec('capture: attach without recompiling'),
      ..._para('//',
          'heaplens-hook installs inline (trampoline) hooks with '
          'minhook on ntdll’s RtlAllocateHeap / RtlReAllocateHeap / '
          'RtlFreeHeap — the common sink under CRT malloc and direct '
          'Win32 allocators alike, so nothing is double-counted.'),
      _blank,
      ..._pt('//', 'why not IAT hooks',
          'they miss static CRTs, function pointers and delayed '
          'imports. On third-party binaries that is a silent '
          'undercount, which is worse than a visible limit.'),
      ..._pt('//', 'why not HeapAlloc',
          'hooking kernelbase!HeapAlloc crashed on first call even '
          'though every setup step reported success. A control probe '
          'on a trivial export proved the technique sound, which '
          'isolated the fault to that prologue; one layer down is '
          'stable. The design doc records the dead end.'),
      ..._pt('//', 'reversible',
          'attach and detach are explicit exported entry points, not '
          'DllMain, so the hook can be removed and the DLL unloaded.'),
      _blank,
      ..._para('//',
          'Before touching a process, the injector runs three '
          'read-only checks and refuses on any match: Protected '
          'Process / PPL status (no name list needed), loaded vendor '
          'modules that fingerprint anti-cheat, VPN and AV software, '
          'and a process-name denylist. None of them opens an '
          'injection-capable handle first.'),
      ..._sec('the daemon'),
      ..._para('//',
          'One single-owner task per concern, connected by channels — '
          'no locks on any hot path, and no graph, anomaly or SQLite '
          'work on the ingest path. It listens on the named pipe '
          '\\\\.\\pipe\\heaplens, serves ws://127.0.0.1:9999 and sends '
          'a full snapshot on connect, then only diffs.'),
      _blank,
      _decl('enum', 'NodeState', ' {'),
      _item('    //', 'Healthy', 'live, owned or legitimately rooted'),
      _item('    //', 'Orphan', 'owner freed, child still live past tau'),
      _item('    //', 'Hot', 'cluster growing past a threshold'),
      _item('    //', 'Freed', 'gone; removed in the next diff'),
      const CodeLine([Span('}', Tok.punct)]),
      _blank,
      ..._pt('//', 'orphan sweep',
          'a live node whose owner was freed and which is older than '
          'tau (default 5 s) is a leak candidate.'),
      ..._pt('//', 'hot clusters',
          'a connected component whose bytes grow past 20 % within '
          'a 10 s window.'),
      ..._pt('//', 'alloc storms',
          'one call site exceeding 1000 allocations per second.'),
      _blank,
      ..._para('//',
          'Every threshold is a config value (env vars or heaplens'
          '.toml), never a magic number in the logic. Allocation '
          'history goes to SQLite on its own task, batched every '
          '~100 ms, and can be queried by window.'),
      ..._sec('φ — ownership inference'),
      ..._para('//',
          'The model is GrapheTas = (N, A, φ). φ decides which live '
          'allocation owns a new one: the most recent live node whose '
          'enclosing function appears in the new allocation’s call '
          'stack. Matching is by function, not instruction, because '
          'exact-address matching produced zero edges against a real '
          'compiled binary. Machinery frames are filtered out.'),
      _blank,
      ..._para('//',
          'It is a heuristic and the repo says so. Recency is the only '
          'tie-break, so overlapping access from two threads can '
          'credit a child to the newer owner. That failure is pinned '
          'by a named test instead of hidden. Release builds keep '
          'debug info on purpose: without it every internal call site '
          'collapsed onto one exported symbol and φ went blind.'),
      ..._sec('the app'),
      ..._pt('//', 'force graph',
          'owners and children as springs, node radius on a log curve '
          'of size, orphans in a distinct state colour. Pure-Dart '
          'layout with its own simulation tests.'),
      ..._pt('//', 'memory map',
          'every live node as one grid cell ordered by address, with '
          'size, orphan-only and symbol-search filters.'),
      ..._pt('//', 'insights',
          'deterministic rules over the live graph, no AI: grouped '
          'orphan leaks by call site, dominant consumers over 20 % of '
          'live bytes. Selecting an insight selects its node.'),
      ..._pt('//', 'process picker',
          'lists running processes with architecture, validates, then '
          'asks the daemon to attach — one target at a time.'),
      ..._pt('//', 'status',
          'a target banner and diagnostics panel, pause/resume, node '
          'detail with symbol, size, owner and edges. Riverpod state.'),
      ..._sec('demo programs'),
      ..._para('//',
          'chaos_orphan, chaos_hot and chaos_storm each plant one '
          'flaw. checkout_service pretends to be a real e-commerce '
          'backend and, every 15 s, cycles healthy → connection-pool '
          'leak → order-queue growth → metrics log storm, in modules '
          'with realistic names. It runs as plain console, an iced '
          'GUI or a ratatui TUI.'),
      ..._sec('measured, not claimed'),
      ..._para('//',
          'Detection latency is measured by h1-harness from the '
          'daemon’s own SQLite timestamps, never from a proxy. The '
          'definition takes whichever condition completes last — '
          'owner freed or age past tau — so the age window cannot be '
          'mistaken for lag. 20 runs per setting:'),
      _item('//', 'tau = 5 ms', 'median 9 µs, worst case ~20 ms'),
      _item('//', 'tau = 500 ms', 'median 2.6 ms after tau elapses'),
      _blank,
      ..._para('//',
          'The ~20 ms worst case is one sweep tick: the structural '
          'transition is near-instant, and a sweep is when it is '
          'observed.'),
      ..._sec('tested where it hurts'),
      ..._para('//',
          '100+ Rust tests and 140+ Dart tests. Beyond unit suites: '
          'multi-thread allocator stress, cross-process wire tests '
          'over a real pipe, and hook tests for the failure modes — '
          'owner freed while children live, process exit without '
          'detach, self-load from a spawned thread, and a targeted '
          'repro hunting a fiber-local-storage teardown hazard.'),
      ..._sec('read the design'),
      ..._para('//',
          'docs/ holds the build spec, UML diagrams, a 48 KB design '
          'doc for injection (dead ends included) and the per-stage '
          'plans and specs.'),
      _blank,
      _link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
    ],
  ),
  Buffer(
    id: 'xynovim',
    fileName: 'xynovim.lua',
    icon: '\u{e620}',
    filetype: 'lua',
    repo: 'xynovim',
    fallbackStars: 1,
    fallbackPushed: '2026-09-04',
    lines: [
      _cm('--', '──────────────────────────────────────────'),
      _cm('--', 'xynovim — the config this site is cosplaying'),
      _cm('--', 'LazyVim on Omarchy/Arch, tuned for Rust'),
      _cm('--', '──────────────────────────────────────────'),
      _blank,
      _kv('base', 'LazyVim · extras: lang.rust, neo-tree'),
      _kv('platform', 'Linux — Omarchy / Arch'),
      _kv('startup', '~18 ms (down from 29)'),
      _kv('releases', '1.0.0 → 1.4.1, every change in CHANGELOG.md'),
      ..._sec('philosophy'),
      ..._para('--',
          'One spec per concern, nothing configured twice, and every '
          'notable change logged with what was verified and how — the '
          'changelog records measurements and tests, not intentions. '
          'It began as a from-scratch Windows config; v1.0.0 was a '
          'deliberate platform switch to LazyVim on Linux, and the '
          'old tree lives on the windows-legacy branch.'),
      ..._sec('two-tier rust diagnostics'),
      ..._para('--',
          'The goal: type-level errors as you type, full clippy depth '
          'before you ever save, and neither fighting the other.'),
      _blank,
      ..._pt('--', 'instant tier',
          'rust-analyzer’s in-memory diagnostics — type errors and '
          'unresolved names in 150–250 ms warm, with no cargo run.'),
      ..._pt('--', 'depth tier',
          'clippy through bacon-ls’ cargo backend: it mirrors the '
          'workspace into a hardlinked shadow and re-runs clippy on '
          'every buffer change (500 ms debounce), ~0.56 s median warm.'),
      _blank,
      ..._para('--',
          'checkOnSave is deliberately OFF. With a 1 s auto-save it '
          'became a second cargo pipeline: runs cancelled each other '
          'and queued on cargo’s build-dir lock — 5.6 s from edit to '
          'diagnostic versus sub-second with one pipeline. '
          'updateOnInsert must stay ON, or bacon-ls advertises no '
          'document sync and diagnostics never refresh. The only '
          'overlap left is cosmetic: a type error may show twice.'),
      ..._sec('a patched bacon-ls, filed upstream'),
      ..._para('--',
          'Upstream aborts its debounce task even after the sleep has '
          'elapsed — at which point the task IS the in-flight cargo '
          'run. Any keystroke, or auto-save’s didSave, silently '
          'killed it: progress tokens never closed (stacked '
          '“checking…” rows) and diagnostics went stale. Three fixes:'),
      _blank,
      ..._pt('--', '1. run supersession',
          'the debounce task drops its own handle once its sleep is '
          'over, so abort() can only cancel a still-sleeping trigger; '
          'in-flight runs are superseded via CancelRunning, which '
          'closes tokens properly.'),
      ..._pt('--', '2. save inside debounce',
          'with checkOnSave off, didSave no longer cancels a pending '
          'live trigger — a save mid-window used to skip the check.'),
      ..._pt('--', '3. dirty buffer close',
          'orphaned diagnostics are cleared, and the shadow file is '
          'restored by copy (fresh mtime), so cargo re-checks instead '
          'of replaying the dirty build’s cached warnings.'),
      _blank,
      ..._para('--',
          'Verified by a 35-check headless end-to-end suite, kept '
          'clippy-clean (the fix adds no struct field, so upstream’s '
          'large_enum_variant lint stays quiet), passing upstream’s '
          'own 124 tests, and filed as a pull request. The local '
          'override is dropped once it merges.'),
      _link('→ bacon-ls PR #139', 'https://github.com/crisidev/bacon-ls/pull/139'),
      ..._sec('rust tuning'),
      ..._pt('--', 'rustaceanvim',
          'inlay hints for closure return types and elided lifetimes, '
          'fill-arguments snippets, full signatures, module-grouped '
          'auto-imports.'),
      ..._pt('--', 'targetDir = true',
          'rust-analyzer’s build scripts get their own target subdir, '
          'so they never contend with a terminal cargo run or test.'),
      ..._pt('--', 'build speed',
          'mold linker via clang and line-tables-only debuginfo: '
          'backtraces kept, link and compile time cut for every cycle.'),
      ..._pt('--', 'tooling',
          'crates.nvim in Cargo.toml, codelldb debugging, neotest, '
          'blink.cmp on its native Rust fuzzy matcher (checked, since '
          'the Lua fallback is silent).'),
      ..._sec('99 — an AI assistant in the editor'),
      ..._para('--',
          'ThePrimeagen’s 99 on the Claude Code provider, with a '
          'search → quickfix flow, visual-selection replace and a '
          'telescope model and provider picker, all under <leader>9. '
          'Two hard-won notes: tmp_dir must be an absolute path (a '
          'relative one resolves against different roots in nvim and '
          'claude, so replies land where nothing reads them), and the '
          'file logger needs an explicit type or logs vanish.'),
      ..._sec('editor behaviour'),
      ..._pt('--', 'auto-save',
          '~1 s debounce, including while typing. Autosaves skip '
          'format-on-save, and a hook re-sends didSave so LSP '
          'save-triggered work still happens. Manual :w formats.'),
      ..._pt('--', 'harpoon',
          'fast file marks, lazy-loaded on its keymaps.'),
      ..._pt('--', 'remote clipboard',
          'every yank is an OSC 52 sequence, so copies cross tmux and '
          'SSH; paste prefers the local Wayland clipboard. It only '
          'activates inside tmux, SSH or herdr.'),
      ..._sec('omarchy integration'),
      ..._para('--',
          'When the OS theme changes, nvim follows live: the theme '
          'module is unloaded, highlights cleared, background reset '
          'and the new colorscheme applied — then transparency is '
          're-applied on every ColorScheme event. The same trick '
          'drives :theme on this site.'),
      ..._sec('startup budget'),
      ..._para('--',
          '29 ms → ~18 ms by removing work, not adding cleverness: '
          'harpoon’s keys became a static table (it was force-loading '
          'the plugin and plenary at spec time), 99, telescope and '
          'blink.compat load on their keymaps, the /proc ancestry walk '
          'short-circuits behind env checks, lazy.nvim’s background '
          'update checker is off (it re-fetched every plugin on a '
          'timer), unused remote-plugin providers are disabled, and '
          '99’s week-old cache is pruned on load.'),
      ..._sec('layout'),
      _plain('lua/config/    options, keymaps, autocmds, clipboard'),
      _plain('lua/plugins/   one spec per concern'),
      _plain('plugin/after/  transparency'),
      _blank,
      _link('→ github.com/XNash/xynovim', 'https://github.com/XNash/xynovim'),
    ],
  ),
  Buffer(
    id: 'xyno-scholar',
    fileName: 'xyno_scholar.dart',
    icon: '\u{e798}',
    filetype: 'dart',
    repo: 'xyno-scholar',
    fallbackStars: 0,
    fallbackPushed: '2026-08-06',
    lines: [
      _cm('//', '──────────────────────────────────────────'),
      _cm('//', 'xyno-scholar — research-topic discovery for scholars'),
      _cm('//', 'Flutter web · pure client-side · no backend'),
      _cm('//', '──────────────────────────────────────────'),
      _blank,
      _kv('purpose', 'refine interdisciplinary research topics'),
      _kv('fields', 'History · Theology · Art History — user-editable'),
      _kv('model', 'mistral-large-latest, JSON mode'),
      _blank,
      _heading('# the interesting bits'),
      _cm('//', 'Mistral’s endpoint doesn’t reliably answer browser CORS'),
      _cm('//', 'preflights, so calls route through a minimal stateless'),
      _cm('//', 'Cloudflare Worker relay — no keys server-side, ever.'),
      _blank,
      _cm('//', 'JSON mode only guarantees syntax, not shape — the exact'),
      _cm('//', 'response schema is also spelled out in the system prompt.'),
      _blank,
      _heading('# key handling'),
      _cm('//', 'the API key is typed in-app at runtime. It lives in memory'),
      _cm('//', 'for the session (sessionStorage only if you opt in, never'),
      _cm('//', 'localStorage). Close the tab, it’s gone. Nothing is baked'),
      _cm('//', 'into the build.'),
      _blank,
      _cm('//', 'deploys as static files — Netlify drop or GitHub Pages.'),
      _blank,
      _link('→ github.com/XNash/xyno-scholar',
          'https://github.com/XNash/xyno-scholar'),
    ],
  ),
  Buffer(
    id: 'xynorash-pwsh',
    fileName: 'xynorash.ps1',
    icon: '\u{ebc7}',
    filetype: 'powershell',
    repo: 'xynorash-pwsh',
    fallbackStars: 0,
    fallbackPushed: '2026-06-07',
    lines: [
      _cm('#', '──────────────────────────────────────────'),
      _cm('#', 'xynorash-pwsh — a cockpit for PowerShell 7'),
      _cm('#', 'gamer/dev/hacker terminal for Windows Terminal'),
      _cm('#', '──────────────────────────────────────────'),
      _blank,
      _kv('shell', 'PowerShell 7+ on Windows 10/11'),
      _kv('prompt', 'oh-my-posh, custom 374-line theme'),
      _kv('palette', 'neon cyan · magenta · amber on near-black'),
      _kv('install', 'one command, safe to re-run'),
      ..._sec('the 3-line prompt'),
      _plain('╭─ 󰪞 user@host ~/path ▸  main ~2 +1 ▸'),
      _plain('│  󰍛 12% ▸  47% ▸ 󰋊 C:48% ▸ ⬆ 1d 4h ▸ 󰩟 192.168.1.x'),
      _plain('╰─ Mon 07 Jun  23:41 ❯'),
      _blank,
      ..._pt('#', 'line 1',
          'identity and location: OS, session, path, and git — '
          'branch, ahead/behind, staged, modified, untracked, stash.'),
      ..._pt('#', 'line 2',
          'live vitals: CPU, RAM, disk, uptime, IP, process count — '
          'always visible — and language runtimes that appear only '
          'when the folder needs them.'),
      ..._pt('#', 'line 3',
          'execution time, clock, exit status, then the prompt '
          'symbol. After Enter the whole cockpit collapses to a '
          'single ❯ (transient prompt), so scrollback stays clean.'),
      _blank,
      ..._para('#',
          'Admin and SSH indicators show only when relevant. Over '
          '30 runtime segments are auto-detected — Rust, Go, Python, '
          'Node, Java, .NET, Flutter, Dart, Zig and more.'),
      ..._sec('vitals without the lag'),
      ..._para('#',
          'A prompt that polls the system on every keypress is a '
          'slow prompt, so each number is fetched as cheaply as it '
          'can be and handed to oh-my-posh as an environment '
          'variable:'),
      _blank,
      ..._pt('#', 'CPU',
          'one PerformanceCounter, seeded at startup, read as the '
          'delta since the last prompt — no WMI, no sleep.'),
      ..._pt('#', 'uptime',
          'pure arithmetic on TickCount64. Free.'),
      ..._pt('#', 'disks',
          'refreshed every 5th prompt — usage barely moves.'),
      ..._pt('#', 'IP',
          'refreshed every 20th prompt, with loopback and '
          'link-local filtered out.'),
      ..._sec('layered, not forked'),
      ..._para('#',
          'The repo is built on a stock community PowerShell '
          'profile and never edits it. It plugs in through the '
          'profile’s Get-Theme_Override hook and a separate profile '
          'file, so upstream updates do not collide with the '
          'customisation. The prompt function is wrapped, not '
          'replaced: oh-my-posh renders, the wrapper only feeds it '
          'data and tints the profile-load timing line.'),
      ..._sec('typing experience'),
      ..._pt('#', 'carapace',
          'annotated completions — flags, subcommands and argument '
          'values — for 1000+ CLIs, bridging zsh, fish and bash '
          'completers so even obscure tools complete.'),
      ..._pt('#', 'PSReadLine',
          'history and plugin predictions, Shift+Enter for a '
          'newline without submitting, syntax colours in the same '
          'neon palette as the prompt.'),
      ..._pt('#', 'zoxide + icons',
          'smart cd that learns your directories; Terminal-Icons '
          'on listings.'),
      ..._pt('#', 'helpers',
          'pgrep / pkill / k9, git shortcuts (gs, ga, gp, gcom, '
          'lazyg), ll and la, uptime, and a Show-Help that lists '
          'them all.'),
      ..._sec('on every new tab'),
      ..._para('#',
          'fastfetch prints system info with custom XYNORASH ASCII '
          'art, using its own config.'),
      ..._sec('the installer'),
      ..._para('#',
          'install.ps1 runs five visible steps — winget tools '
          '(oh-my-posh, fastfetch, carapace, zoxide), PowerShell '
          'modules, JetBrainsMono Nerd Font (bundled in the repo '
          'and registered per-user), config files, and Windows '
          'Terminal settings. It checks before it installs, so '
          'running it twice is safe, and it needs no system-wide '
          'changes beyond winget packages and fonts.'),
      _blank,
      ..._para('#',
          'Everything lives beside the profile, so moving to a new '
          'machine is: clone, run the script, open a new tab.'),
      _blank,
      _plain(r'git clone https://github.com/XNash/xynorash-pwsh.git'),
      _plain(r'.\install.ps1   # fonts, tools, config — one command'),
      _blank,
      _link('→ github.com/XNash/xynorash-pwsh',
          'https://github.com/XNash/xynorash-pwsh'),
    ],
  ),
  Buffer(
    id: 'xyno-arch',
    fileName: 'xyno_arch.sh',
    icon: '\u{f303}',
    filetype: 'bash',
    repo: 'xyno-arch',
    fallbackStars: 0,
    fallbackPushed: '2026-10-08',
    lines: [
      _cm('#', '──────────────────────────────────────────'),
      _cm('#', 'xyno-arch — my whole desktop, reproducible'),
      _cm('#', 'Hyprland · Tokyo Night · tuned for gaming'),
      _cm('#', '──────────────────────────────────────────'),
      _blank,
      _kv('hardware', 'Ryzen 7 5800X · GTX 980 (4 GB) · 1080p60'),
      _kv('compositor', 'Hyprland, Lua config, dwindle layout'),
      _kv('shell', 'noctalia — bar, launcher, lock, OSD'),
      _kv('terminal', 'Ghostty · Yazi · JetBrainsMono Nerd Font'),
      _kv('boot', 'systemd-boot + Unified Kernel Image'),
      _kv('storage', 'btrfs + snapper, zram swap'),
      ..._sec('what it is'),
      ..._para('#',
          'A dotfiles-and-system repo that rebuilds the machine, not '
          'just the look: user configs, /etc and /boot files, '
          'explicit package lists, and a generated wallpaper. The '
          'brief was a modern Wayland desktop that is also a serious '
          'game box on older NVIDIA hardware.'),
      ..._sec('install'),
      _plain('./install.sh            # symlink the home configs'),
      _plain('./install.sh --system   # also /etc bits (sudo)'),
      _blank,
      ..._para('#',
          'Existing files are moved to .bak-<timestamp>, never '
          'overwritten. The boot-critical files — mkinitcpio.conf, '
          'the kernel cmdline, loader.conf — are NOT installed '
          'automatically: they are tied to one machine’s boot setup, '
          'so you diff them first and rebuild the initramfs by hand.'),
      ..._sec('layout'),
      _plain('home/        dotfiles, symlinked into HOME'),
      _plain('system/      /etc and /boot, copied by --system'),
      _plain('packages/    pacman and AUR lists, explicit'),
      _plain('tools/       the wallpaper generator'),
      _plain('wallpapers/  generated, referenced by the shell'),
      ..._sec('one palette, pushed everywhere'),
      ..._para('#',
          'Tokyo Night is defined once. noctalia’s templates render '
          'it into Hyprland, Ghostty, GTK and Yazi, so changing the '
          'theme is one switch. Generated files are gitignored so '
          'they cannot fight the repo; the tracked config.toml holds '
          'everything that defines the look — palette, bar geometry, '
          'lock screen, widgets. Only per-monitor widget placement '
          'stays untracked.'),
      _blank,
      ..._para('#',
          'The wallpaper is code: a pure-stdlib Python script writes '
          'the PNG with zlib and struct — smooth gradient through '
          'palette stops, a seeded starfield in palette colours — so '
          'the sky is reproducible and tweakable by seed or size.'),
      ..._sec('gaming'),
      ..._pt('#', 'automatic GameMode',
          'a window.open hook in hyprland.lua matches Proton’s '
          'steam_app_<id> windows and puts the game’s process into '
          'GameMode: performance governor while it runs, back to '
          'powersave about 20 s after exit. No launch options.'),
      ..._pt('#', 'gamemode-attach',
          'the helper behind it. gamemoded -r toggles, so a game with '
          'two windows would switch itself off; an atomic mkdir lock '
          'per pid makes repeats a no-op, and games that registered '
          'themselves (libgamemodeauto in their maps) are left alone.'),
      ..._pt('#', 'scx_lavd scheduler',
          'sched_ext, written by Igalia for the Steam Deck: spots '
          'latency-critical render and input threads and keeps them '
          'from being starved. Gaming mode, all cores on mains power.'),
      ..._pt('#', 'GPU headroom',
          'a systemd unit lifts the GTX 980 from 180 W to its 225 W '
          'limit so it holds boost clocks under sustained load.'),
      ..._pt('#', 'low latency',
          'direct scanout, plus tearing and immediate presentation '
          'for Steam windows only — the desktop stays tear-free.'),
      ..._pt('#', 'MangoHud + NTSYNC',
          'VRAM on the overlay, because 4 GB makes it the number '
          'that matters; the NTSYNC module for Wine builds that can '
          'use it. SDL_VIDEODRIVER is deliberately unset: forcing it '
          'breaks Steam titles.'),
      ..._sec('system tuning, with reasons'),
      ..._pt('#', 'network',
          'BBR with fq pacing; MTU probing because the WAN is '
          'PPPoE at 1492; socket buffers raised to 32 MB for '
          'high-latency paths; unsent data capped per socket so '
          'games and SSH are not queued behind a bulk upload.'),
      ..._pt('#', 'memory',
          'zram swap with swappiness 180 — swapping is cheap '
          'when it is compressed RAM.'),
      ..._pt('#', 'audio',
          'PipeWire realtime scheduling through rlimits, so it '
          'works without rtkit.'),
      ..._pt('#', 'smaller things',
          'LLMNR off in resolved, the power key opens the session '
          'menu instead of powering off, and greetd with tuigreet '
          'handles login.'),
      ..._sec('small tools that earn their keep'),
      ..._pt('#', 'keybind cheat sheet',
          'Super+Shift+/ pages a list parsed straight out of '
          'hyprland.lua, so it cannot go stale.'),
      ..._pt('#', 'notification-focus',
          'clicking a notification focuses the app that sent it; '
          'for apps that ignore activation tokens, it reads '
          'noctalia’s history and finds the window by class.'),
      ..._pt('#', 'intl-speedtest',
          'compares local and international download speed over '
          'fast.com servers, to settle ISP arguments with data.'),
      ..._pt('#', 'WinApps windows',
          'FreeRDP RemoteApp windows shift class and title after '
          'they map, so static rules never match; event hooks float '
          'them and park the VM’s helper window on a hidden '
          'workspace.'),
      ..._sec('notes'),
      ..._para('#',
          'hyprland.lua uses the Lua config format, because '
          'hyprlang is deprecated as of Hyprland 0.55. The NVIDIA '
          'driver is the legacy 580xx branch. Layouts switch '
          'between US and French AZERTY with Alt+Shift. Paths '
          'assume one username.'),
      _blank,
      _link('→ github.com/XNash/xyno-arch', 'https://github.com/XNash/xyno-arch'),
    ],
  ),
  Buffer(
    id: 'about',
    fileName: 'about.md',
    icon: '\u{f48a}',
    filetype: 'markdown',
    lines: [
      _heading('# Nash Tefison · Xynorash'),
      _blank,
      _plain('I build tools that watch systems from the inside: heap'),
      _plain('inspectors, editor pipelines, terminal cockpits, research'),
      _plain('assistants. If it has a feedback loop, I want it faster.'),
      _blank,
      _heading('# stack'),
      _item('-', 'Rust', 'systems, protocols, the serious stuff'),
      _item('-', 'TypeScript', 'products and platforms'),
      _item('-', 'Dart/Flutter', 'this site, xyno-scholar'),
      _item('-', 'PowerShell + Lua', 'the environments I live in'),
      _item('-', 'Neovim on Omarchy/Arch', 'the cockpit itself'),
      _item('-', 'Hyprland + systemd', 'the desktop around it'),
      _blank,
      _heading('# principles'),
      _plain('Spec first. Measure before believing. File fixes upstream.'),
      _plain('Document what was verified, not what was intended.'),
      _blank,
      _heading('# find me'),
      _link('→ github.com/XNash', 'https://github.com/XNash'),
      _link('→ daily.dev/xynorash', 'https://app.daily.dev/xynorash'),
      _blank,
      _cm('>', 'Solving problems at the edge of impossible.'),
    ],
  ),
];
