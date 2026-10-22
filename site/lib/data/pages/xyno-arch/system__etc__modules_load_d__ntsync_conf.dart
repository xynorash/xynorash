import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/modules-load.d/ntsync.conf',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'ntsync.conf — one word that loads a kernel module at boot'),
    cm('#', r'Windows synchronisation objects, done in the kernel'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'load the ntsync kernel module on every boot'),
    kv(r'format', r'modules-load.d: one module name per line, # for comments'),
    kv(r'size', r'4 lines: 3 comment lines and 1 module name'),
    kv(r'installed', r'/etc/modules-load.d/ntsync.conf by install.sh --system'),
    kv(r'history', r'1 commit: d552dfd (2026-09-19), never edited'),

    ...sec(r'why this file exists'),
    ...para('#',
        r'Wine and Proton run Windows games on Linux, and Windows games '
        r'lean heavily on Windows synchronisation objects: events, '
        r'mutexes, semaphores, waiting on several at once. Emulating '
        r'those in userspace is possible, and the file’s own comment '
        r'names the two older approaches (esync and fsync). The newer '
        r'one moves the objects into the kernel as a device, /dev/ntsync, '
        r'and this one-word file is how that device gets created on this '
        r'machine.'),

    ...sec(r'the file, in full'),
    ...code('text', r'system/etc/modules-load.d/ntsync.conf · lines 1-4', r'''
# NT synchronization primitives in the kernel. Wine/Proton use /dev/ntsync
# instead of emulating Windows sync objects in userspace (esync/fsync),
# which cuts CPU overhead and frame-time spikes in heavy DX11/DX12 games.
ntsync'''),
    ...para('#',
        r'The comment states the whole case in three lines: what the '
        r'module is, who uses it, and what it buys. The claims it makes '
        r'are “cuts CPU overhead” and “frame-time spikes”, specifically '
        r'in “heavy DX11/DX12 games”. I did not measure either, and the '
        r'repo records no measurement, so they are the author’s '
        r'reasoning, not a result I can confirm.'),
    blank,
    ...para('#',
        r'The last line is the entire mechanism. systemd reads every '
        r'*.conf file in the modules-load.d directories at boot and loads '
        r'each module named in them. Nothing else is configured: no '
        r'module options, no dependency, no condition.'),

    ...sec(r'how it connects'),
    ...para('#',
        r'The module is only half of the arrangement. A game has to be '
        r'run by a Wine or Proton build that knows how to use '
        r'/dev/ntsync; README.md words it carefully, “NTSYNC module '
        r'loaded for Wine builds that can use it”. So this file makes '
        r'the capability available, and it is up to the runner to use '
        r'it. A runner that does not know about the device ignores it, '
        r'and one that does can use it without any per-game launch '
        r'option. That fits the repo’s wider approach to gaming: the '
        r'compositor attaches GameMode to Steam game windows by itself, '
        r'so the tuning is set once at the system level rather than '
        r'game by game.'),
    blank,
    ...para('#',
        r'The kernel has to provide the module. The repo does not pin a '
        r'kernel: packages/pacman.txt lists the stock linux package '
        r'plus headers, and the preset targets /boot/vmlinuz-linux. The '
        r'file would do nothing on a kernel that lacks ntsync, and on '
        r'such a kernel the load would fail at boot, as I understand '
        r'systemd, with a logged error rather than a stopped boot.'),

    ...sec(r'trade-offs'),
    ...pt('#', r'always loaded',
        r'the module is loaded whether or not a game is running. The '
        r'cost is a small kernel module; the benefit is that nothing '
        r'has to be done when a game starts.'),
    ...pt('#', r'copied, not linked',
        r'install.sh lists this file among the nine it copies with '
        r'sudo install -Dm644, because /etc files are read by root '
        r'early in boot, not from a user’s clone.'),
    ...pt('#', r'effective next boot',
        r'the installer does not run modprobe; it copies the file and '
        r'does not load the module in the running session. A reboot, or '
        r'a manual modprobe ntsync, is needed for the first load.'),

    ...sec(r'how I checked it'),
    ...para('#',
        r'The repo has no test for it. On the machine the repo describes '
        r'I looked at the result instead: the ntsync module is loaded '
        r'(lsmod shows it, 20480 bytes, no users) and /dev/ntsync '
        r'exists. That shows the file or an equivalent did its job there. '
        r'I did not run a game, so I did not see Wine use the device.'),

    ...sec(r'history'),
    ...pt('#', r'd552dfd, 2026-09-19',
        r'the initial commit: “system side covers sysctl tuning (zram, '
        r'network), realtime audio limits, ntsync, greetd and the boot '
        r'configuration”. It has not been touched since.'),
  ],
);
