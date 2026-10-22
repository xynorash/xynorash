import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/kernel/cmdline',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'cmdline — five words that find the root filesystem'),
    cm('#', 'one line, baked into every unified kernel image'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'the kernel command line that mkinitcpio embeds in each UKI'),
    kv('format', 'one line, five space-separated parameters, 106 bytes'),
    kv('size', '1 line, 1 commit: d552dfd (2026-09-19), never edited since'),
    kv('installed by', 'nobody: install.sh prints it as a manual, machine-specific file'),
    kv('checked here', 'split on spaces: root, zswap, rootflags, rw, rootfstype'),

    ...sec('why this file exists'),
    ...para(
        '#',
        r'A kernel needs to be told where its root filesystem is, '
        r'and with a unified kernel image (UKI) there is no '
        r'bootloader config to put that in: the command line is '
        r'part of the image. mkinitcpio builds the image, and, as I '
        r'understand its documentation, takes the command line from '
        r'a file named /etc/kernel/cmdline when no option gives one. '
        r'This file is that source. The installer’s own words for '
        r'it are “kernel command line baked into the UKI”.'),
    blank,
    ...para(
        '#',
        r'Two consequences follow from “baked in”, and both shape '
        r'the rest of the system. Changing the file changes nothing '
        r'until the images are rebuilt, which is why the installer’s '
        r'last line says to run mkinitcpio -P. And the loader can '
        r'not be used to change it for one boot, because loader.conf '
        r'sets editor no. The command line is therefore a build '
        r'input, not a runtime knob.'),

    ...sec('the file, parameter by parameter'),
    ...para(
        '#',
        r'The file is a single line. To keep a disk identifier out '
        r'of this page I show the parameters as fragments; every '
        r'fragment below is copied from the file.'),
    ...code('text', 'system/etc/kernel/cmdline · the four readable parameters', r'''
zswap.enabled=0
rootflags=subvol=@
rw
rootfstype=btrfs'''),
    ...para(
        '#',
        r'The remaining parameter is root=PARTUUID=<a 36-character '
        r'GUID>. I will come to it first, because it is the one that '
        r'makes the file unportable.'),

    ...sec('root=PARTUUID=...: naming the partition by identity'),
    ...para(
        '#',
        r'There are several ways to say which partition holds the '
        r'root filesystem: a device node (/dev/nvme0n1p2), a '
        r'filesystem UUID, a label, or a PARTUUID. A device node can '
        r'change when a disk is added or the controller enumerates in '
        r'a different order. A PARTUUID is stored in the GPT '
        r'partition table, so it follows the partition, and, unlike '
        r'a filesystem UUID, it survives reformatting that '
        r'partition. The repo gives no reason for choosing it. The '
        r'reasons above are my own, and they are the standard '
        r'arguments.'),
    blank,
    ...para(
        '#',
        r'What the repo does record is the consequence. The value '
        r'belongs to one disk. Copied to another machine, this file '
        r'produces a kernel that cannot find its root and stops in '
        r'the initramfs emergency shell. That is the clearest '
        r'reason in the project for not installing the file '
        r'automatically, and install.sh agrees: it lists the file '
        r'among the five it will not touch.'),
    ...code('bash', 'install.sh · why it is on the manual list', r'''
  echo "  system/etc/kernel/cmdline      kernel command line baked into the UKI"'''),
    ...para(
        '#',
        r'As I understand it, the initramfs resolves root=PARTUUID '
        r'through its udev hook. That is another link in the chain: '
        r'etc/mkinitcpio.conf has udev in HOOKS, and the parameter '
        r'relies on udev having enumerated the partition tables of '
        r'the block devices by the time root is mounted. It is a '
        r'quiet dependency between two files in different '
        r'directories.'),

    ...sec('rootflags=subvol=@, rootfstype=btrfs, rw'),
    ...para(
        '#',
        r'These three describe how to mount the root once it is '
        r'found, and they read as a single sentence: mount it as '
        r'btrfs, mount the subvolume named @ rather than the top of '
        r'the filesystem, mount it read-write.'),
    blank,
    ...pt(
        '#',
        'rootfstype=btrfs',
        r'the filesystem type is declared, so the early boot does '
        r'not have to probe for it. The README table says “btrfs '
        r'with snapper”, and packages/pacman.txt lists btrfs-progs '
        r'and snapper, which agree.'),
    ...pt(
        '#',
        'rootflags=subvol=@',
        r'a btrfs filesystem can hold many subvolumes, each a '
        r'separately snapshot-able tree. The name @ for the root '
        r'subvolume is the widespread convention for layouts that '
        r'use snapshots. The repo shows only this one name. It does '
        r'not say what the other subvolumes are (a home subvolume '
        r'is common) or whether any exist, and no snapper '
        r'configuration is tracked.'),
    ...pt(
        '#',
        'rw',
        r'mount read-write from the start. Linux defaults to '
        r'mounting root read-only at first, so that it can be '
        r'checked before it is written, and many setups say ro here '
        r'and remount later. For btrfs there is no boot-time '
        r'check to wait for, which is a reasonable argument for rw. '
        r'The mkinitcpio hook list still has fsck; for a btrfs '
        r'root I understand it to do nothing.'),
    blank,
    ...para(
        '#',
        r'The pairing of subvolume and snapper gives a design '
        r'implication worth saying out loud, as inference. The '
        r'kernel and the UKIs live in /boot, which per linux.preset '
        r'is the EFI system partition, a FAT filesystem outside the '
        r'btrfs. Rolling back the @ subvolume to an older snapshot '
        r'would roll back /usr/lib/modules and the packages, but not '
        r'the UKI sitting on the ESP. The repo does not address '
        r'that, and it tracks no snapshot-on-upgrade hook (there is '
        r'no snap-pac in packages/pacman.txt).'),

    ...sec('zswap.enabled=0: one compressed swap, not two'),
    ...para(
        '#',
        r'This is the only parameter that is not about the root. '
        r'zswap is a kernel feature that compresses pages in RAM '
        r'on their way to a swap device. The system also uses zram, '
        r'which is itself compressed swap kept in RAM, tuned by '
        r'etc/sysctl.d/99-zram.conf and installed through the '
        r'zram-generator package. Running both would compress '
        r'pages twice and route them through two layers for no '
        r'benefit. Switching zswap off leaves zram as the single '
        r'layer. The repo does not state this reasoning; I take it '
        r'from the pairing, and the pacman.txt page reads it the '
        r'same way.'),
    blank,
    ...para(
        '#',
        r'A caution that the same pairing raises. The setting '
        r'only makes sense if the zram device really exists, and the '
        r'repo does not track the zram-generator configuration '
        r'that would create it. With zswap off and no zram device, '
        r'swap would simply be absent.'),

    ...sec('what is not on the line'),
    ...para(
        '#',
        r'Reading a short command line tells as much by omission. '
        r'These are the common parameters it does not contain. Each '
        r'item is an observation about the file, with a note on what '
        r'it may mean.'),
    blank,
    ...pt(
        '#',
        'quiet, splash, loglevel',
        r'none, so the kernel prints its boot messages. The repo '
        r'gives no reason either way.'),
    ...pt(
        '#',
        'nvidia_drm.modeset=1',
        r'absent. The NVIDIA modules are loaded early through '
        r'mkinitcpio.conf, and Wayland compositors on the '
        r'proprietary driver need kernel modesetting. It may be '
        r'enabled by a modprobe option from the driver package '
        r'instead of the command line. I cannot tell which from '
        r'the repo, and I flag it as a gap.'),
    ...pt(
        '#',
        'amd_pstate',
        r'absent. gamemode.ini says the CPU runs in amd-pstate '
        r'active mode and switches governors, yet nothing on this '
        r'line selects that mode. It is either the kernel’s '
        r'default for this CPU or set elsewhere.'),
    ...pt(
        '#',
        'resume=',
        r'absent, so there is no hibernation; swap is zram, which '
        r'cannot hold a hibernation image across a power cycle.'),
    ...pt(
        '#',
        'mitigations, nowatchdog, tuning flags',
        r'absent. The performance work in this repo is in sysctl '
        r'and the scheduler, not in boot flags.'),

    ...sec('history'),
    ...para(
        '#',
        r'git log has one commit for this path, d552dfd, on '
        r'2026-09-19 at 18:28, the initial commit. Its body lists '
        r'“the boot configuration” as part of the system side. There '
        r'is no later edit, so the line has survived the whole '
        r'history unchanged, which is the expected behaviour for a '
        r'file that points at a partition: it changes when the '
        r'disk layout does.'),

    ...sec('how I would verify it, and what I could not'),
    ...para(
        '#',
        r'On the machine, three observations settle everything on '
        r'this page: the contents of /proc/cmdline after boot (it '
        r'should match this file), findmnt / (it should show btrfs '
        r'with subvol=/@), and swapon --show (zram only, no zswap '
        r'file). I did not run them. What I did check is the '
        r'file’s shape: it is one line of five parameters, with a '
        r'trailing newline and no stray characters.'),

    ...sec('limits, and what is next'),
    ...pt(
        '#',
        'unportable by design',
        r'the PARTUUID is machine-specific, which is why the '
        r'installer never touches the file. A script could '
        r'generate the line from findmnt output instead, which '
        r'would make the file reproducible too.'),
    ...pt(
        '#',
        'no recovery path',
        r'both UKIs share this line, and the editor is off. A '
        r'typo here is repaired from a live USB.'),
    ...pt(
        '#',
        'zram half-tracked',
        r'zswap is switched off here, yet the zram device it '
        r'relies on is not defined in the repo.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
