import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/scx_loader.toml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'scx_loader.toml — the CPU scheduler is a config file'),
    cm('#', r'scx_lavd in Gaming mode, picked at boot'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'choose and tune the sched_ext scheduler that scx_loader starts'),
    kv(r'format', r'TOML, 14 lines'),
    kv(r'installed', r'/etc/scx_loader.toml by install.sh --system'),
    kv(r'service', r'scx_loader.service, enabled with --now by the same script'),
    kv(r'history', r'1 commit: d552dfd (2026-09-19), never edited'),

    ...sec(r'why this file exists'),
    ...para('#',
        r'Linux has one CPU scheduler built in. sched_ext is a kernel '
        r'feature that lets a different scheduling policy be loaded as a '
        r'program at runtime, and the scx-scheds package ships several '
        r'of them. scx_loader is a small service that picks one at boot '
        r'and starts it. Without this file the service has no opinion '
        r'about which to use; with it, the choice is part of the '
        r'repository, next to the other gaming layers in README.md: '
        r'“sched_ext / scx_lavd as the system scheduler, in gaming '
        r'mode”. Both packages are in packages/pacman.txt (scx-scheds '
        r'and scx-tools).'),

    ...sec(r'the choice'),
    ...code('toml', r'system/etc/scx_loader.toml · lines 1-6', r'''
# sched_ext scheduler loaded at boot by scx_loader.service.
# scx_lavd = Latency-criticality Aware Virtual Deadline, written by Igalia
# for Valve's Steam Deck. It spots latency-critical threads (a game's render
# and input threads) and keeps them from being starved by background load.
default_sched = "scx_lavd"
default_mode  = "Gaming"'''),
    ...para('#',
        r'The comment gives the reasoning: lavd is a scheduler written '
        r'for handheld gaming that tells which threads matter for '
        r'latency and protects them. That is why it fits a desktop that '
        r'also runs games, where a background compile or download '
        r'should not cost a dropped frame. The two active lines are '
        r'then plain: which scheduler (default_sched) and which of its '
        r'modes (default_mode).'),

    ...sec(r'the mode table'),
    ...code('toml', r'system/etc/scx_loader.toml · lines 8-14', r'''
[scheds.scx_lavd]
# Desktop on mains power: no core compaction, use every core.
gaming_mode     = ["--performance"]
auto_mode       = ["--autopilot"]
lowlatency_mode = ["--performance"]
powersave_mode  = ["--powersave"]
server_mode     = ["--balanced"]'''),
    ...para('#',
        r'scx_loader knows five modes by name, and for each scheduler '
        r'this table says which command-line flags to start it with. '
        r'The table is the part of the file that does the tuning. Each '
        r'value is a list of arguments passed to scx_lavd.'),
    blank,
    ...pt('#', r'gaming_mode',
        r'--performance. This is the active mode. The comment above '
        r'the table explains the choice: on a desktop on mains power '
        r'there is no reason to save energy by packing work onto fewer '
        r'cores, so core compaction is off and every core is used.'),
    ...pt('#', r'lowlatency_mode',
        r'also --performance, the same flag as gaming. The repo does '
        r'not say why two modes share a value. The effect is that '
        r'choosing either mode starts the scheduler the same way.'),
    ...pt('#', r'auto_mode',
        r'--autopilot. The repo does not say what it does.'),
    ...pt('#', r'powersave_mode',
        r'--powersave, for the case the comment rules out on this '
        r'desktop. It is written down anyway, so the table is complete '
        r'if the mode is ever switched.'),
    ...pt('#', r'server_mode',
        r'--balanced.'),
    blank,
    ...para('#',
        r'What each flag means inside scx_lavd is not in the repo. The '
        r'only meaning I rely on is the one the comment gives for '
        r'--performance (no core compaction); the others I report as '
        r'configured, not as explained.'),

    ...sec(r'what the install does around it'),
    ...code('bash', r'install.sh · line 56', r'''
  sudo systemctl enable --now scx_loader.service nvidia-powerlimit.service'''),
    ...para('#',
        r'The file is copied to /etc, then the service is enabled and '
        r'started in the same command that enables the GPU power-limit '
        r'unit. enable --now means the scheduler changes without a '
        r'reboot, and survives the next one. Starting it from the '
        r'installer is also how the scheduler is switched on for the '
        r'first time.'),

    ...sec(r'trade-offs and failure modes'),
    ...pt('#', r'kernel support',
        r'sched_ext needs a kernel built with it. If the kernel lacks '
        r'it, scx_loader cannot attach a scheduler and the system '
        r'carries on with the default one, as I understand the design '
        r'of the feature, since the built-in scheduler is the fallback. '
        r'The repo does not test this case.'),
    ...pt('#', r'the scheduler is a program',
        r'if it crashes or is stopped, the kernel drops back to the '
        r'default scheduler. That safety property comes from sched_ext, '
        r'not from this file.'),
    ...pt('#', r'edits need a restart',
        r'the file is read when the service starts; changing it later '
        r'means restarting scx_loader.service.'),
    ...pt('#', r'one machine',
        r'the comment “desktop on mains power” is specific. On a laptop '
        r'the powersave mode would be the one to change to.'),

    ...sec(r'how I checked it'),
    ...para('#',
        r'No test exists. I checked the machine: the tracked file is '
        r'identical to /etc/scx_loader.toml, scx_loader.service is '
        r'enabled, and the kernel reports an active sched_ext scheduler '
        r'whose name starts with lavd (the version string I read was '
        r'lavd_1.1.3 for x86_64). That confirms the intended '
        r'scheduler is the one running. I did not measure frame times, '
        r'so the benefit itself is the author’s claim, not my result.'),

    ...sec(r'history'),
    ...pt('#', r'd552dfd, 2026-09-19',
        r'the initial commit lists “scx_lavd scheduler” among its '
        r'gaming features. The file has had no later edits across the '
        r'22 commits.'),
  ],
);
