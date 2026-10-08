import '../models/project.dart';
import 'authoring.dart';
import 'buffers/heaplens.dart';
import 'buffers/xyno_arch.dart';
import 'buffers/xyno_scholar.dart';
import 'buffers/xynorash_pwsh.dart';
import 'buffers/xynovim.dart';

/// Every page on the site, in explorer order. Project pages live in
/// `buffers/`; their indices are relied on by the dashboard shortcuts.
final List<Buffer> kBuffers = [
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
      plain('Solving problems at the edge of impossible.'),
      plain('Xynorash isn’t a name — it’s a coordinate.'),
      blank,
      cm('>', 'Nash Tefison · Rust · TypeScript · Dart · PowerShell · Neovim'),
      blank,
      heading('# projects'),
      blank,
      item('-', 'heaplens.rs', 'live heap inspector for Windows'),
      item('-', 'xynovim.lua', 'my Neovim, tuned until it disappears'),
      item('-', 'xyno_scholar.dart', 'AI research-topic explorer'),
      item('-', 'xynorash.ps1', 'a PowerShell cockpit with neon vitals'),
      item('-', 'xyno_arch.sh', 'my whole Arch desktop, reproducible'),
      blank,
      heading('# how to drive this site'),
      blank,
      plain('Space → menu · Space f → find project · : → cmdline'),
      plain('j/k scroll · gg/G top/bottom · [b ]b switch buffer'),
      plain('…or just click things. Mice are welcome here too.'),
      blank,
      cm('>', 'Built with Flutter web, styled after my xynovim setup.'),
      link('→ github.com/XNash', 'https://github.com/XNash'),
    ],
  ),
  heaplensBuffer,
  xynovimBuffer,
  xynoScholarBuffer,
  xynorashPwshBuffer,
  xynoArchBuffer,
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
      item('-', 'Dart/Flutter', 'this site, xyno-scholar'),
      item('-', 'PowerShell + Lua', 'the environments I live in'),
      item('-', 'Neovim on Omarchy/Arch', 'the cockpit itself'),
      item('-', 'Hyprland + systemd', 'the desktop around it'),
      blank,
      heading('# principles'),
      plain('Spec first. Measure before believing. File fixes upstream.'),
      plain('Document what was verified, not what was intended.'),
      blank,
      heading('# find me'),
      link('→ github.com/XNash', 'https://github.com/XNash'),
      link('→ daily.dev/xynorash', 'https://app.daily.dev/xynorash'),
      blank,
      cm('>', 'Solving problems at the edge of impossible.'),
    ],
  ),
];
