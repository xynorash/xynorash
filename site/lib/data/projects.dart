import '../models/project.dart';
import 'authoring.dart';
import 'pages_registry.dart';

/// Project directories in explorer order.
const List<String> kProjectOrder = [
  'heaplens',
  'xynovim',
  'xyno-rust.nvim',
  'xyno-crates.nvim',
  'xyno-imports.nvim',
  'xyno-new.nvim',
  'xyno-macros.nvim',
  'xyno-sandbox.nvim',
  'xyno-guard.nvim',
  'xyno-history.nvim',
  'xyno-clipboard.nvim',
  'xyno-scholar',
  'xynorash-pwsh',
  'xyno-arch',
];

final Buffer _welcome =
Buffer(
    id: 'welcome',
    fileName: 'welcome.md',
    icon: '\u{f48a}',
    filetype: 'markdown',
    lines: [
      heading(r'__  ____   ___   _  ___  ___    _   ___ _  _'),
      heading(r'\ \/ /\ \ / / \ | |/ _ \| _ \  /_\ / __| || |'),
      heading(r' >  <  \ V /| .`| | (_) |   / / _ \\__ \ __ |'),
      heading(r'/_/\_\  |_| |_|\_|\___/|_|_\/_/ \_\___/_||_|'),
      blank,
      plain('Every system has an edge.'),
      plain('I like to stand on it, curious, and see what’s past it.'),
      plain('Xynorash isn’t a name — it’s a coordinate.'),
      blank,
      cm('>', 'Nash Tefison · Rust · TypeScript · Dart · PowerShell · Neovim'),
      blank,
      heading('# projects'),
      blank,
      item('-', 'heaplens/', 'live heap inspector for Windows'),
      item('-', 'xynovim/', 'my Neovim, tuned until it disappears'),
      item('-', 'xyno-rust.nvim/', 'Cargo context, targets and routes pickers'),
      item('-', 'xyno-crates.nvim/', 'search crates.io and add crates from the editor'),
      item('-', 'xyno-imports.nvim/', 'auto-import without the completion menu'),
      item('-', 'xyno-new.nvim/', 'new Rust projects from the dashboard'),
      item('-', 'xyno-macros.nvim/', 'completion inside derive and helper attributes'),
      item('-', 'xyno-sandbox.nvim/', 'a coding agent inside a bubblewrap jail'),
      item('-', 'xyno-guard.nvim/', 'auto-save that never touches dependency files'),
      item('-', 'xyno-history.nvim/', 'local history for every save'),
      item('-', 'xyno-clipboard.nvim/', 'yanks that reach the other machine'),
      item('-', 'xyno-scholar/', 'AI research-topic explorer'),
      item('-', 'xynorash-pwsh/', 'a PowerShell cockpit with neon vitals'),
      item('-', 'xyno-arch/', 'my whole Arch desktop, reproducible'),
      blank,
      heading('# how to read this site'),
      blank,
      plain('Every project is a directory. Its files mirror the real'),
      plain('repository, and each page explains the file it is named'),
      plain('after: the approach, the thinking, the dead ends, and'),
      plain('real excerpts of the code. Start at a README.md.'),
      blank,
      heading('# how to drive it'),
      blank,
      plain('Space → menu · Space f → find file · Space o → outline'),
      plain('j/k scroll · gg/G top/bottom · ]] [[ sections · ]b [b tabs'),
      plain(':e <name> open · :bd close tab · : → cmdline'),
      plain('…or just click things. Mice are welcome here too.'),
      blank,
      cm('>', 'Built with Flutter web, styled after my xynovim setup.'),
      link('→ github.com/XNash', 'https://github.com/XNash'),
    ],
  );

final Buffer _about =
Buffer(
    id: 'about',
    fileName: 'about.md',
    icon: '\u{f48a}',
    filetype: 'markdown',
    lines: [
      heading('# Nash Tefison · Xynorash'),
      blank,
      plain('I build tools that watch systems from the inside: heap'),
      plain('inspectors, editor pipelines, terminal cockpits, research'),
      plain('assistants. If it has a feedback loop, I want it faster.'),
      blank,
      heading('# stack'),
      item('-', 'Rust', 'systems, protocols, the serious stuff'),
      item('-', 'TypeScript', 'products and platforms'),
      item('-', 'Dart/Flutter', 'this site, xyno-scholar, the heaplens UI'),
      item('-', 'PowerShell + Lua', 'the environments I live in'),
      item('-', 'Neovim on Omarchy/Arch', 'the cockpit itself, plus nine plugins I published'),
      item('-', 'Hyprland + systemd', 'the desktop around it'),
      blank,
      heading('# principles'),
      plain('Spec first. Measure before believing. File fixes upstream.'),
      plain('Document what was verified, not what was intended.'),
      plain('When a heuristic can be wrong, make the failure a test.'),
      plain('Fail closed. If safety cannot be established, say no.'),
      blank,
      heading('# how this site is built'),
      plain('A Flutter web app dressed as a Neovim session: an explorer'),
      plain('tree, tabs, a Telescope-style finder, an outline overlay,'),
      plain('and a which-key menu. The pages are written from the'),
      plain('repositories themselves — code excerpts are checked'),
      plain('line by line against the real files.'),
      blank,
      heading('# find me'),
      link('→ github.com/XNash', 'https://github.com/XNash'),
      link('→ daily.dev/xynorash', 'https://app.daily.dev/xynorash'),
      blank,
      cm('>', 'Every system has an edge. I like to stand on it, curious.'),
    ],
  );

/// Every page on the site: welcome, the project trees (pages mirror real
/// repository files), then about.
final List<Buffer> kBuffers = _assemble();

List<Buffer> _assemble() {
  final byPath = <String, Buffer>{
    for (final b in kPageBuffers) b.fullPath: b,
  };
  final pages = byPath.values.toList()
    ..sort((a, b) {
      int rank(Buffer x) {
        final i = kProjectOrder.indexOf(x.project ?? '');
        return i < 0 ? 999 : i;
      }

      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.fullPath.compareTo(b.fullPath);
    });
  return [_welcome, ...pages, _about];
}

/// Project names that have a README page, in [kProjectOrder].
List<String> get projectNames => [
      for (final p in kProjectOrder)
        if (kBuffers.any((b) => b.fullPath == '$p/README.md')) p,
    ];
