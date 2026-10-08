import '../models/project.dart';
import 'authoring.dart';
import 'buffers/heaplens.dart';
import 'buffers/xyno_arch.dart';
import 'buffers/xyno_scholar.dart';
import 'buffers/xynorash_pwsh.dart';
import 'buffers/xynovim.dart';

// TEMPORARY: stand-ins for project pages the content workflow has not
// written yet. Deleted before release.
Buffer _readme(String project, Buffer old) => makePage(
      '$project/README.md',
      repo: old.repo,
      summary: old.summary,
      fallbackStars: old.fallbackStars,
      fallbackPushed: old.fallbackPushed,
      lines: old.lines,
    );

final List<Buffer> kInterimPages = [
  _readme('heaplens', heaplensBuffer),
  _readme('xynovim', xynovimBuffer),
  _readme('xyno-scholar', xynoScholarBuffer),
  _readme('xynorash-pwsh', xynorashPwshBuffer),
  _readme('xyno-arch', xynoArchBuffer),
  makePage('heaplens/crates/heaplens-alloc/src/ring.rs',
      lines: [cm('//', 'placeholder'), ...sec('placeholder')]),
  makePage('heaplens/crates/heaplens-alloc/src/guard.rs',
      lines: [cm('//', 'placeholder'), ...sec('placeholder')]),
  makePage('heaplens/crates/heaplens-daemon/src/graph.rs',
      lines: [cm('//', 'placeholder'), ...sec('placeholder')]),
  makePage('xyno-arch/home/.config/hypr/hyprland.lua',
      lines: [cm('--', 'placeholder'), ...sec('placeholder')]),
  makePage('xyno-arch/system/etc/scx_loader.toml',
      lines: [cm('#', 'placeholder'), ...sec('placeholder')]),
];
