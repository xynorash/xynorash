import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/modules-load.d/ntsync.conf',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'ntsync.conf — one word that loads a kernel driver'),
    cm('#', 'Windows synchronisation, done in the kernel, for Wine'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'asks systemd to load the ntsync kernel module at every boot'),
    kv('language', 'modules-load.d format: one module name per line'),
    kv('size', '4 lines, 1 active; 1 commit: d552dfd (2026-09-19), unchanged'),
    kv('installed as', '/etc/modules-load.d/ntsync.conf by install.sh --system'),
    kv('takes effect', 'next boot: the installer never runs modprobe'),

    ...sec('why this file exists'),
    ...para(
        '#',
        r'Windows games lean hard on the operating system’s '
        r'synchronisation objects: events, semaphores, mutexes, and '
        r'the call that waits on several of them at once. Wine has to '
        r'provide those objects on Linux, and the way it does so has '
        r'a measurable cost in CPU time and in frame-time spikes. '
        r'This file turns on the newest and most direct answer, a '
        r'kernel driver that implements the Windows semantics itself. '
        r'The README lists it under Gaming as “NTSYNC module loaded '
        r'for Wine builds that can use it”, and the hedge in that '
        r'sentence is worth keeping in mind, because the module '
        r'alone does nothing for a Wine that does not look for it.'),

    ...sec('the file, in full'),
    ...code('ini', 'system/etc/modules-load.d/ntsync.conf', r'''
# NT synchronization primitives in the kernel. Wine/Proton use /dev/ntsync
# instead of emulating Windows sync objects in userspace (esync/fsync),
# which cuts CPU overhead and frame-time spikes in heavy DX11/DX12 games.
ntsync'''),
    ...para(
        '#',
        r'Three comment lines and the module name. The comment is '
        r'the repo’s whole explanation, and it makes three '
        r'claims: Wine and Proton talk to a device node called '
        r'/dev/ntsync; that replaces emulating the objects in '
        r'userspace, with esync and fsync named as the old ways; '
        r'and the benefit is less CPU overhead and fewer '
        r'frame-time spikes in heavy DirectX 11 and 12 games. The '
        r'first two are mechanism, the third is an effect that I '
        r'return to under limits.'),

    ...sec('three generations of the same problem'),
    ...para(
        '#',
        r'The comment compresses a history, and the history is what '
        r'makes the file make sense. This is my account of it, from '
        r'general knowledge of Wine, not from the repo:'),
    blank,
    ...pt(
        '#',
        'wineserver',
        r'originally every wait on a Windows object went through a '
        r'round trip to a Wine helper process. Correct, and slow in '
        r'games that wait thousands of times per frame.'),
    ...pt(
        '#',
        'esync',
        r'built the objects from Linux eventfd file descriptors, '
        r'removing the round trip. It runs into limits on open '
        r'file descriptors and is only an approximation of the '
        r'Windows wait semantics.'),
    ...pt(
        '#',
        'fsync',
        r'used a newer futex wait-on-multiple call to do the same '
        r'without file descriptors. Faster, but needed a kernel '
        r'patch for years, and still an emulation.'),
    ...pt(
        '#',
        'ntsync',
        r'a small kernel driver, exposed as /dev/ntsync, that '
        r'implements the NT objects directly with the right wait '
        r'semantics. It was merged into mainline Linux in 6.14, '
        r'as I recall it.'),
    blank,
    ...para(
        '#',
        r'The repo’s package list installs the stock linux kernel '
        r'rather than a distribution-patched or LTS one, so a '
        r'current mainline version is what the module comes '
        r'from. I cannot see the kernel version from the repo; '
        r'the only evidence about the hardware generation is '
        r'that the other pages of this project rely on features '
        r'(sched_ext, Lua configuration in Hyprland) that are '
        r'recent.'),

    ...sec('how a one-word file becomes a loaded module'),
    ...para(
        '#',
        r'At boot, systemd-modules-load reads every .conf file in '
        r'modules-load.d. Each non-comment line is a module name, '
        r'and the service loads it, as if by modprobe. Lines '
        r'starting with # are comments, which is what the three '
        r'explanatory lines are. The directory is the standard one '
        r'for this, which is why the installer can copy the file '
        r'with nothing more than a path.'),
    ...code('bash', 'install.sh · where it is copied', r'''
             etc/modules-load.d/ntsync.conf \
'''),
    ...para(
        '#',
        r'The activation section of the installer runs sysctl, '
        r'reloads systemd, reloads logind and enables two services. '
        r'It does not load modules. So the first boot after '
        r'running --system is the first time the module exists; '
        r'until then, /dev/ntsync is absent and Wine uses whatever '
        r'else it can. The install.sh page makes the same '
        r'observation about this file. A manual modprobe ntsync would '
        r'make it available at once.'),
    blank,
    ...para(
        '#',
        r'A failure mode for readers who copy the file to another '
        r'machine: if the kernel has no ntsync module, as I '
        r'understand it systemd-modules-load logs an error and '
        r'carries on. '
        r'Nothing breaks, and nothing is gained. The file '
        r'fails safe, which is part of why it is on the '
        r'installed list instead of the compare-by-hand one.'),

    ...sec('what the file does not do'),
    ...pt(
        '#',
        'select a Wine',
        r'the driver is only used by Wine builds that were written '
        r'to open /dev/ntsync. Whether the Proton build Steam '
        r'launches does is outside the repo. That is the "can use '
        r'it" in the README’s wording.'),
    ...pt(
        '#',
        'grant access to the device',
        r'no udev rule is tracked. Whether the desktop user can '
        r'open /dev/ntsync depends on what the system’s default '
        r'rules do for that node, and I did not verify that.'),
    ...pt(
        '#',
        'prove anything',
        r'no check in the repo reports whether a running game is '
        r'actually using the device.'),

    ...sec('how the claim could be tested here'),
    ...para(
        '#',
        r'The benefit in the comment is about frame time, and the '
        r'repo already contains the instrument for measuring it. '
        r'MangoHud’s config turns on the frame-time readouts:'),
    ...code('ini', 'home/.config/MangoHud/MangoHud.conf · frame time', r'''
fps
frametime
frame_timing'''),
    ...para(
        '#',
        r'A before and after comparison would load the module on '
        r'and off for the same game and scene, and look at the '
        r'frame-time graph. The repo contains no such '
        r'measurement. The comment’s numbers-free phrasing '
        r'(“cuts CPU overhead and frame-time spikes”) is the '
        r'upstream motivation for the driver, and I treat it as '
        r'that, not as a result obtained on this GTX 980 and Ryzen '
        r'5800X machine. The honest status is: configured, '
        r'plausible, not measured.'),

    ...sec('history'),
    ...para(
        '#',
        r'One commit touches the file, d552dfd, the initial '
        r'commit on 2026-09-19 at 18:28. The commit body lists '
        r'“ntsync” among the system-side pieces, with sysctl '
        r'tuning, greetd and the boot configuration. The file '
        r'has not changed, which is what one would expect: a '
        r'module name has nothing to tune.'),

    ...sec('limits, and what is next'),
    ...pt(
        '#',
        'invisible failure',
        r'the module can fail to load, or Wine can ignore it, and '
        r'the desktop looks the same. A line in the installer '
        r'that prints whether /dev/ntsync exists would close '
        r'the gap.'),
    ...pt(
        '#',
        'no version pin',
        r'the benefit depends on the kernel and the Wine build, '
        r'neither of which this repo pins.'),
    ...pt(
        '#',
        'unmeasured',
        r'see above. The MangoHud setup already gives the means.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
