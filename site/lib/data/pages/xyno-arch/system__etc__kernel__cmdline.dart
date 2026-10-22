import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/kernel/cmdline',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'cmdline — one line that tells the kernel where the system is'),
    cm('#', r'baked into the boot image, so nobody can edit it at the menu'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'kernel command line for the Unified Kernel Image'),
    kv(r'format', r'a single line of space-separated parameters, 105 characters'),
    kv(r'size', r'1 line, 1 commit: d552dfd (2026-09-19), never edited since'),
    kv(r'installed', r'never automatically; install.sh --system only prints it'),
    kv(r'machine bound', r'yes: it names one disk partition by PARTUUID'),

    ...sec(r'why this file exists'),
    ...para('#',
        r'On a classic Linux install the command line lives in the boot '
        r'loader entry, where you can change it with a text editor or, in '
        r'a pinch, at the boot menu. This machine boots a Unified Kernel '
        r'Image instead (see linux.preset and loader.conf). A UKI is one '
        r'EFI file that carries the kernel, the initramfs and the command '
        r'line together, so the command line has to come from somewhere at '
        r'build time. This file is that somewhere. As I understand '
        r'mkinitcpio, it reads /etc/kernel/cmdline when it assembles a '
        r'UKI; the installer says the same thing in its own words: '
        r'“kernel command line baked into the UKI”.'),
    blank,
    ...para('#',
        r'The consequence is the interesting part. Changing a boot '
        r'parameter is no longer an edit to a boot entry. It is an edit '
        r'to this file followed by a rebuild, which is exactly what the '
        r'installer tells you to do at the end: “compare them by hand, '
        r'then run: sudo mkinitcpio -P”.'),

    ...sec(r'the file, in full'),
    ...code('text', r'system/etc/kernel/cmdline · line 1', r'''
root=PARTUUID=49a7c1a3-ff9d-4bbf-b68f-ab105487c35f zswap.enabled=0 rootflags=subvol=@ rw rootfstype=btrfs'''),
    ...para('#', r'Five parameters. Taking them one at a time:'),
    blank,
    ...pt('#', r'root=PARTUUID=49a7c1a3-…',
        r'which partition to mount as /. A PARTUUID is the identifier '
        r'stored in the partition table, not in the filesystem, so it '
        r'survives re-formatting the partition but not replacing the '
        r'disk. It is also the reason this file cannot be copied to '
        r'another computer: the value is one partition on one drive.'),
    ...pt('#', r'zswap.enabled=0',
        r'turns the kernel’s zswap cache off. The file does not give a '
        r'reason. What the rest of the repo shows is that swap is meant '
        r'to be zram: README.md says “zram swap”, packages/pacman.txt '
        r'lists zram-generator, and sysctl.d/99-zram.conf opens with '
        r'“zram is RAM-backed compressed swap”. My reading is that two '
        r'compressed layers in front of the same swap would be redundant, '
        r'but that motive is an inference, not something written down.'),
    ...pt('#', r'rootflags=subvol=@',
        r'mount options for the root filesystem. The root is a btrfs '
        r'subvolume named @. README.md lists “btrfs with snapper” in its '
        r'setup table, which fits a layout with named subvolumes, but the '
        r'repo does not track the snapper configuration.'),
    ...pt('#', r'rw',
        r'mount the root read-write from the start instead of waiting for '
        r'a remount.'),
    ...pt('#', r'rootfstype=btrfs',
        r'tell the kernel the root filesystem type up front, so it does '
        r'not have to probe for it.'),

    ...sec(r'what is not on the line'),
    ...para('#',
        r'The absences are as informative as the parameters. There is no '
        r'quiet and no splash, so the kernel messages are not hidden. '
        r'There is no nvidia_drm.modeset option, even though this is an '
        r'NVIDIA machine; a search of the whole repository for modeset '
        r'finds nothing, so the repo does not show where, or whether, that '
        r'is set. The NVIDIA modules are instead pulled into the '
        r'initramfs by mkinitcpio.conf. And there is no resume= parameter, '
        r'which is consistent with swap being RAM-backed zram that cannot '
        r'hold a hibernation image, though nothing in the repo says '
        r'hibernation was ruled out on purpose.'),

    ...sec(r'one line for two images'),
    ...para('#',
        r'linux.preset builds two images, a default UKI and a fallback '
        r'UKI. Neither preset section sets its own command line, so as far '
        r'as the repo shows both get this same line. That is a quiet '
        r'trade-off. The fallback image exists to rescue a bad initramfs, '
        r'and it does, but it cannot rescue a bad command line, because it '
        r'inherits it. If the PARTUUID is wrong, both entries fail the '
        r'same way.'),
    blank,
    ...para('#',
        r'Recovery from that situation is made harder, on purpose, by '
        r'loader.conf. Its editor setting is off, with a comment that '
        r'explains why: otherwise anyone at the keyboard could press e at '
        r'the menu and append init=/bin/bash. So the menu cannot be used '
        r'to repair a wrong line. The way back is a rescue USB, or booting '
        r'an entry from the firmware. The installer’s decision not to '
        r'copy this file automatically is the matching safety: a command '
        r'line written for another machine is the one mistake that can '
        r'leave no bootable entry at all.'),

    ...sec(r'failure modes'),
    ...pt('#', r'wrong PARTUUID',
        r'the kernel cannot find the root. Both UKIs fail; the editor is '
        r'disabled; use a rescue medium.'),
    ...pt('#', r'edit without a rebuild',
        r'the file is only read when the image is built. Changing it and '
        r'rebooting changes nothing until sudo mkinitcpio -P is run.'),
    ...pt('#', r'subvolume renamed',
        r'rootflags=subvol=@ points at a subvolume by name; if the name '
        r'changes (for example after a restore), the mount fails.'),
    ...pt('#', r'copied to another machine',
        r'the PARTUUID is the one value that must be replaced first.'),

    ...sec(r'how I checked it'),
    ...para('#',
        r'The repo has no tests for system files. What I did was compare: '
        r'on the machine this repo describes, /proc/cmdline holds exactly '
        r'this string, parameter for parameter, and /etc/kernel/cmdline '
        r'is byte-identical to the tracked file. That confirms the file '
        r'matches what is booted. It does not prove the file is what '
        r'caused it, since I did not rebuild an image.'),

    ...sec(r'history'),
    ...pt('#', r'd552dfd, 2026-09-19',
        r'the initial commit added the file, as part of the boot '
        r'configuration alongside mkinitcpio.conf and loader.conf. It has '
        r'not been changed in any later commit, across all 22.'),
    blank,
    ...sec(r'related files'),
    ...pt('#', r'system/etc/mkinitcpio.d/linux.preset',
        r'where the UKI is built and where it lands.'),
    ...pt('#', r'system/etc/mkinitcpio.conf',
        r'what goes into the initramfs half of the image.'),
    ...pt('#', r'system/boot/loader/loader.conf',
        r'which image boots by default and why the menu cannot edit this '
        r'line.'),
    ...pt('#', r'system/etc/sysctl.d/99-zram.conf',
        r'the swap this line steps aside for.'),
  ],
);
