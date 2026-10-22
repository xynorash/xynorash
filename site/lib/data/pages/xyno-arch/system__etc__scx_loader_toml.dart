import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/scx_loader.toml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'scx_loader.toml — a different CPU scheduler at boot'),
    cm('#', 'scx_lavd, in gaming mode, loaded as a BPF program'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'chooses the sched_ext scheduler and its mode for scx_loader.service'),
    kv('language', 'TOML; 14 lines, 7 active settings'),
    kv('size', '1 commit: d552dfd (2026-09-19), unchanged since'),
    kv('installed as', '/etc/scx_loader.toml by install.sh --system, then enabled --now'),
    kv('packages', 'scx-scheds and scx-tools, both in packages/pacman.txt'),

    ...sec('why this file exists'),
    ...para(
        '#',
        r'The CPU scheduler decides which thread runs on which core '
        r'and for how long. On Linux it is normally part of the '
        r'kernel and cannot be swapped without rebuilding it. '
        r'sched_ext changes that: it lets a scheduler be written as '
        r'a BPF program and loaded at runtime, replacing the kernel’s '
        r'own for the whole machine. scx_loader is the small service '
        r'from the scx tools that loads one at boot and lets you '
        r'switch between them. This file tells it which scheduler '
        r'and which mode.'),
    blank,
    ...para(
        '#',
        r'The README gives the motive in one bullet: “sched_ext / '
        r'scx_lavd as the system scheduler, in gaming mode.” The '
        r'first comment in the file gives the mechanism, in two '
        r'sentences about why a scheduler matters to a game.'),

    ...sec('the file, in full'),
    ...code('toml', 'system/etc/scx_loader.toml', r'''
# sched_ext scheduler loaded at boot by scx_loader.service.
# scx_lavd = Latency-criticality Aware Virtual Deadline, written by Igalia
# for Valve's Steam Deck. It spots latency-critical threads (a game's render
# and input threads) and keeps them from being starved by background load.
default_sched = "scx_lavd"
default_mode  = "Gaming"

[scheds.scx_lavd]
# Desktop on mains power: no core compaction, use every core.
gaming_mode     = ["--performance"]
auto_mode       = ["--autopilot"]
lowlatency_mode = ["--performance"]
powersave_mode  = ["--powersave"]
server_mode     = ["--balanced"]'''),
    ...para(
        '#',
        r'Parsing the file as TOML gives two top-level strings and '
        r'one table with five keys. That is the whole configuration: '
        r'which scheduler, which mode, and what each mode means in '
        r'command-line flags for that scheduler.'),

    ...sec('lavd: what the comment says it is for'),
    ...para(
        '#',
        r'The name expands in the comment: Latency-criticality '
        r'Aware Virtual Deadline. The comment credits Igalia as '
        r'the author and Valve’s Steam Deck as the target. The '
        r'idea that it states is the interesting one. A fair '
        r'scheduler treats threads alike. A game is not alike: the '
        r'few threads that render a frame and read input decide '
        r'whether the game feels smooth, while the many threads of '
        r'a compiler, a browser or a download only decide how '
        r'long those things take. lavd tries to work out which '
        r'threads are latency-critical and to keep them from being '
        r'starved by the rest. The phrase in the comment is “spots '
        r'latency-critical threads”.'),
    blank,
    ...para(
        '#',
        r'The same idea appears elsewhere in this project at '
        r'a different level. The GameMode setup changes the CPU '
        r'governor and priorities for the game process; the '
        r'scheduler changes how every thread on the machine '
        r'competes. They are complementary, and only one of them '
        r'is conditional on a game running.'),

    ...sec('default_sched and default_mode'),
    ...pt(
        '#',
        'default_sched = "scx_lavd"',
        r'the scheduler that scx_loader starts. The installed '
        r'scx-scheds package contains several; naming one makes the '
        r'choice explicit.'),
    ...pt(
        '#',
        'default_mode = "Gaming"',
        r'the mode applied at boot. Of the five modes in the '
        r'table below, this one picks which flags are used. The '
        r'other four are inert until something switches to them.'),
    blank,
    ...para(
        '#',
        r'This is the decision that makes the scheduler a '
        r'system-wide, always-on choice. gamemode.ini does not '
        r'switch the scheduler mode when a game starts: its only '
        r'hooks show notifications. So scx_lavd runs in Gaming mode '
        r'at the desktop, in the browser and in the compiler, not '
        r'only inside games. The README’s wording, “as the system '
        r'scheduler”, says the same. It is a bet that a '
        r'latency-first scheduler is acceptable for everything this '
        r'machine does.'),

    ...sec('the five modes'),
    ...para(
        '#',
        r'scx_loader defines five named modes and lets each '
        r'scheduler map them to its own flags. This file maps all '
        r'five for lavd:'),
    blank,
    ...pt(
        '#',
        'gaming_mode = --performance',
        r'the one in use. The comment above it explains the '
        r'flag: “Desktop on mains power: no core compaction, use '
        r'every core.”'),
    ...pt(
        '#',
        'lowlatency_mode = --performance',
        r'identical flags to gaming. On lavd the two modes are '
        r'therefore indistinguishable, which is worth knowing '
        r'before expecting a difference from switching.'),
    ...pt(
        '#',
        'auto_mode = --autopilot',
        r'by name, a mode where the scheduler decides for itself.'),
    ...pt(
        '#',
        'powersave_mode = --powersave',
        r'the opposite end: favour energy over speed.'),
    ...pt(
        '#',
        'server_mode = --balanced',
        r'a middle setting for throughput work.'),
    blank,
    ...para(
        '#',
        r'The last four are dormant on a machine that boots in '
        r'Gaming mode and never switches. I read the full table as '
        r'completeness more than need: having all five defined '
        r'means a later switch with the scx tools works without '
        r'editing the file. The repo does not say whether it has '
        r'ever been switched.'),

    ...sec('“no core compaction”: a power feature with no use here'),
    ...para(
        '#',
        r'Core compaction, as the comment uses it, means packing '
        r'work onto fewer cores so the rest can sleep, saving power '
        r'at some cost in speed. --performance turns it off. The '
        r'comment’s justification is that this is a desktop on '
        r'mains power, and the noctalia config backs the premise '
        r'from a different angle:'),
    ...code('toml', 'home/.config/noctalia/config.toml · the machine has no battery', r'''
# No battery or AC device in /sys/class/power_supply and UPower is not'''),
    ...para(
        '#',
        r'A machine with nothing in the power-supply class is '
        r'not running on a battery. Power saving has no '
        r'benefit that outweighs spreading load across all cores. '
        r'The CPU in the README is a Ryzen 7 5800X, which has eight '
        r'cores. Where compaction would idle some of them to save a '
        r'few watts, performance mode keeps all eight available. '
        r'That reasoning is the comment’s, restated.'),

    ...sec('how it is installed and started'),
    ...code('bash', 'install.sh · activation', r'''
  sudo systemctl enable --now scx_loader.service nvidia-powerlimit.service'''),
    ...para(
        '#',
        r'The file is copied by the nine-file loop. The service '
        r'comes from the scx packages in packages/pacman.txt: '
        r'scx-scheds carries the schedulers themselves and '
        r'scx-tools the loader and its command line, as I '
        r'understand the split. '
        r'enable --now makes it start at every boot and starts it '
        r'immediately, so the switch happens during the install, '
        r'before any reboot.'),
    blank,
    ...para(
        '#',
        r'There is a sharp edge in how that line interacts with the '
        r'script’s set -e. If scx_loader cannot start, for example '
        r'because the running kernel was built without sched_ext, '
        r'enable --now returns a failure and the script stops there. '
        r'The group-membership and /etc/hosts steps that follow '
        r'would be skipped. This is my reading of the shell code, not '
        r'something I ran, and it needs a kernel without the '
        r'feature, which I do not expect of Arch’s stock kernel.'),

    ...sec('a safety net I did not build, but rely on'),
    ...para(
        '#',
        r'Replacing the scheduler for the entire machine sounds '
        r'dangerous. A property of sched_ext, as I understand its '
        r'design, is that it is built to fail safe: if a BPF '
        r'scheduler stops running tasks within a time limit, or '
        r'exits, the kernel throws it out and goes back to its '
        r'default scheduler. A bad scheduler therefore costs '
        r'responsiveness, not the machine. The repo does not '
        r'mention this property; it is part of why a configuration '
        r'file like this one is a low-risk thing to install '
        r'automatically.'),

    ...sec('how I would check it, and what I could not'),
    ...para(
        '#',
        r'The check is to ask the system which scheduler is active. '
        r'scx_loader exposes a command line tool (scxctl) for this, '
        r'and the kernel publishes the active scheduler under '
        r'/sys/kernel/sched_ext. I ran neither: my sandbox has no '
        r'sched_ext (that directory does not exist there), and the '
        r'machine the file describes was out of reach. What I did '
        r'verify is '
        r'the file: it parses as TOML, and the table keys are '
        r'exactly the five mode names above.'),

    ...sec('history'),
    ...para(
        '#',
        r'One commit, d552dfd, the initial one on 2026-09-19. Its '
        r'body lists “scx_lavd scheduler” among the gaming features. '
        r'No later edit, so no mode has been tried and abandoned in '
        r'the history that exists. If Nash experimented, the '
        r'experiments are not in the repo.'),

    ...sec('limits, and what is next'),
    ...pt(
        '#',
        'no measurement',
        r'the repo contains no benchmark or frame-time capture '
        r'that compares scx_lavd to the default scheduler. The '
        r'claim rests on the scheduler’s design goals as the comment '
        r'states them. MangoHud is configured, so the means exist.'),
    ...pt(
        '#',
        'flags are version-bound',
        r'--performance, --autopilot and the others are options of '
        r'one scheduler release. A future version that renames one '
        r'could make a mode fail to apply, and a table full of '
        r'dormant modes would hide it until someone switched.'),
    ...pt(
        '#',
        'always on',
        r'nothing returns the machine to the default scheduler '
        r'when no game is running. If that ever matters, the '
        r'GameMode start and end hooks are the natural place to '
        r'switch modes.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
