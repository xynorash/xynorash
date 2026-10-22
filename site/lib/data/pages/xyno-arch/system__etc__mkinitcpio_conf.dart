import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/mkinitcpio.conf',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'mkinitcpio.conf — the stock file plus two edits'),
    cm('#', 'NVIDIA modules in, the kms hook out'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'recipe for the initramfs that every unified kernel image embeds'),
    kv('language', 'bash, sourced by mkinitcpio; four active assignments'),
    kv('size', '81 lines, about 6 of them code; 1 commit: d552dfd (2026-09-19)'),
    kv('the edits', 'MODULES lists four nvidia modules; HOOKS has no kms'),
    kv('installed by', 'nobody: install.sh prints it, then says to run mkinitcpio -P'),

    ...sec('why this file exists'),
    ...para(
        '#',
        r'Before the real root filesystem can be mounted, something '
        r'has to run that knows how to find it. That something is the '
        r'initramfs: a small filesystem image that the kernel '
        r'unpacks into RAM and starts first. mkinitcpio builds it, '
        r'and this file is the recipe: which kernel modules to put '
        r'inside (MODULES), which extra programs (BINARIES), which '
        r'extra files (FILES), and which scripts to run, in which '
        r'order (HOOKS).'),
    blank,
    ...para(
        '#',
        r'On this machine the initramfs is not a loose file in /boot. '
        r'etc/mkinitcpio.d/linux.preset wraps it, the kernel and the '
        r'command line into a unified kernel image, so this recipe '
        r'ends up inside arch-linux.efi and arch-linux-fallback.efi. '
        r'A mistake in the file is a mistake inside the thing that '
        r'boots, which is why install.sh refuses to copy it.'),

    ...sec('what is stock and what is not'),
    ...para(
        '#',
        r'Most of the 81 lines are comments, and they are the '
        r'comments that ship with the mkinitcpio package. The '
        r'installer states the repo’s changes in one line:'),
    ...code('bash', 'install.sh · what this file changes', r'''
  echo "  system/etc/mkinitcpio.conf     nvidia modules in MODULES, kms hook removed"'''),
    ...para(
        '#',
        r'That is the whole diff against the default, and I can '
        r'confirm it from the file: sourcing it in bash gives an '
        r'empty BINARIES, an empty FILES, the four modules and an '
        r'eleven-hook list. I checked with bash -n and with a '
        r'sourced declare -p. What I cannot do is diff against the '
        r'package’s copy, because I only have the repo. The claim '
        r'that everything else is stock rests on the installer’s '
        r'sentence and on the unchanged look of the comment block.'),

    ...sec('MODULES: the four NVIDIA modules, loaded first'),
    ...code('bash', 'system/etc/mkinitcpio.conf · MODULES', r'''
MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)'''),
    ...para(
        '#',
        r'The comment above the line in the file says modules in '
        r'this array “are loaded before any boot hooks are run”. '
        r'So the proprietary driver is up before the root '
        r'filesystem is even mounted. The four names are the four '
        r'kernel modules of the NVIDIA driver, as I understand '
        r'them:'),
    blank,
    ...pt(
        '#',
        'nvidia',
        r'the core module that talks to the GPU.'),
    ...pt(
        '#',
        'nvidia_modeset',
        r'display mode setting for the driver.'),
    ...pt(
        '#',
        'nvidia_uvm',
        r'unified memory, used by compute workloads (CUDA, OpenCL). '
        r'It is not needed to draw a desktop. The package list '
        r'installs opencl-nvidia-580xx, so the compute side is '
        r'present on the machine.'),
    ...pt(
        '#',
        'nvidia_drm',
        r'the DRM interface that a Wayland compositor such as '
        r'Hyprland uses to put pixels on a screen. The other three '
        r'exist to serve this one.'),
    blank,
    ...para(
        '#',
        r'Why load them this early? The repo gives no reason in a '
        r'comment, and the installer string only says what changed. '
        r'The usual reason, which I recognise from the Arch '
        r'documentation for the NVIDIA driver, is early kernel '
        r'mode setting: the display is brought up once, by the '
        r'right driver, during boot, instead of being initialised '
        r'by a generic framebuffer first and handed over later. '
        r'That gives a cleaner transition to the greeter and avoids '
        r'a mode switch when the compositor starts. It is the '
        r'conventional answer, and I flag it as inference.'),
    blank,
    ...para(
        '#',
        r'One consequence deserves a sentence of its own. The modules '
        r'are copied into the image at build time, so they must '
        r'exist when mkinitcpio runs. The package list installs the '
        r'driver as nvidia-580xx-dkms, which compiles the modules for '
        r'each installed kernel. The order of two package-manager '
        r'steps therefore matters: the DKMS build has to finish '
        r'before the image is rebuilt. On Arch the DKMS hooks are '
        r'numbered to run before the mkinitcpio hook, as far as I '
        r'remember. If a build failed after a kernel upgrade, the '
        r'new image would be missing the modules, and the '
        r'repo records no such incident.'),

    ...sec('HOOKS: eleven steps and one that is missing'),
    ...code('bash', 'system/etc/mkinitcpio.conf · HOOKS', r'''
HOOKS=(base udev autodetect microcode modconf keyboard keymap consolefont block filesystems fsck)'''),
    ...para(
        '#',
        r'Hooks run in the order written, and the file’s own '
        r'comment warns about it: “Order is important, and it is '
        r'recommended that you do not change the order in which '
        r'HOOKS are added.” Read left to right, this line is a '
        r'small boot story:'),
    blank,
    ...pt(
        '#',
        'base',
        r'the skeleton: a minimal userspace and the init script. '
        r'The file says it is required unless you know precisely '
        r'what you are doing.'),
    ...pt(
        '#',
        'udev',
        r'the device manager inside the initramfs. It creates the '
        r'device nodes and symlinks that root=PARTUUID needs (see '
        r'etc/kernel/cmdline). The file calls it required for '
        r'automatic module loading.'),
    ...pt(
        '#',
        'autodetect',
        r'shrinks the image to the modules this machine actually '
        r'uses. It must come before the hooks that add modules '
        r'(microcode through filesystems) so that they are '
        r'filtered. This is the hook the fallback image skips.'),
    ...pt(
        '#',
        'microcode',
        r'puts CPU microcode in front of the image so the CPU is '
        r'patched as early as possible. packages/pacman.txt lists '
        r'amd-ucode, which matches the Ryzen in the README.'),
    ...pt(
        '#',
        'modconf',
        r'carries the modprobe configuration into the image, so '
        r'options for the modules above apply during early boot.'),
    ...pt(
        '#',
        'keyboard, keymap, consolefont',
        r'a working keyboard, the console keymap and the console '
        r'font, so that an emergency shell is usable.'),
    ...pt(
        '#',
        'block',
        r'storage drivers for the disk that holds root.'),
    ...pt(
        '#',
        'filesystems',
        r'the filesystem drivers, here btrfs, so the root can be '
        r'mounted. Required unless the filesystem modules are in '
        r'MODULES.'),
    ...pt(
        '#',
        'fsck',
        r'a filesystem check before mounting. For a btrfs root I '
        r'understand it to do nothing, since btrfs has no routine '
        r'boot-time check; the hook is stock and harmless.'),

    ...sec('the hook that is not there: kms'),
    ...para(
        '#',
        r'The file keeps an example in its comments that shows the '
        r'default shape of a systemd-based initramfs. Compare it with '
        r'the active line above and one word stands out:'),
    ...code('bash', 'system/etc/mkinitcpio.conf · the stock example, kms included', r'''
##   This will create a systemd based initramfs which loads an encrypted root filesystem.
#    HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)'''),
    ...para(
        '#',
        r'Put kms back between modconf and keyboard in the active '
        r'line and you have the shape of the stock default, which is '
        r'what the installer’s words imply: “kms hook removed”. '
        r'What the hook '
        r'does, as I understand it, is add the open-source graphics '
        r'drivers (and the DRM helper modules) for the GPUs it '
        r'detects, so that the display works early. On this machine '
        r'the detected GPU is an NVIDIA card, and the open-source '
        r'driver for NVIDIA is nouveau. Leaving kms in would put '
        r'nouveau into the initramfs, where it could grab the card '
        r'before the proprietary driver loads. The Arch '
        r'documentation advises removing the hook for this exact '
        r'reason, as I remember it. I flag that as recalled, not as '
        r'read from the repo.'),
    blank,
    ...para(
        '#',
        r'There is a detail that makes the removal cost nothing. The '
        r'Ryzen 7 5800X named in the README has no integrated '
        r'graphics, and the README names a single GPU, the GTX 980, '
        r'so the only card the hook could have found is the one '
        r'the proprietary driver already serves. The four modules in '
        r'MODULES do '
        r'the job kms would have done, and do it with the driver '
        r'that will be used afterwards. The two edits are one '
        r'decision seen twice: use the proprietary driver from the '
        r'first moment, and keep the open one out of the image.'),

    ...sec('what the fallback image changes'),
    ...para(
        '#',
        r'This single recipe produces two images. The preset runs '
        r'it once as written and once with the autodetect hook '
        r'skipped:'),
    ...code('bash', 'system/etc/mkinitcpio.d/linux.preset · fallback', r'''
fallback_uki="/boot/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"'''),
    ...para(
        '#',
        r'So the fallback has every module the hooks can offer, '
        r'not just the ones this machine used on the day the image '
        r'was built. The four NVIDIA modules are in both, since '
        r'MODULES is not filtered. The practical meaning is that the '
        r'fallback survives a change of storage controller, which '
        r'the default would not. It does nothing for a missing '
        r'nvidia module, because autodetect never filtered '
        r'MODULES in the first place.'),

    ...sec('what is left at its default'),
    ...para(
        '#',
        r'Everything else is commented out, which means the '
        r'defaults apply. The compression line is the one worth '
        r'knowing:'),
    ...code('bash', 'system/etc/mkinitcpio.conf · compression note', r'''
# is used for Linux ≥ 5.9 and gzip compression is used for Linux < 5.9.
#COMPRESSION="zstd"'''),
    ...para(
        '#',
        r'The note says zstd is the default for modern kernels, and '
        r'the explicit setting is commented out. The image '
        r'is compressed with zstd without anyone asking. Since the '
        r'result is embedded in an EFI binary on a FAT partition, '
        r'the size of the image matters more than it would for a '
        r'file on a root filesystem, but the repo shows no sign '
        r'that it has been a problem. BINARIES and FILES are '
        r'empty, so nothing extra is shipped into early boot.'),

    ...sec('what I checked'),
    ...pt(
        '#',
        'bash -n',
        r'passes: the file is valid shell, which is how mkinitcpio '
        r'reads it.'),
    ...pt(
        '#',
        'sourced values',
        r'MODULES has four entries, HOOKS eleven, BINARIES and FILES '
        r'are empty, as stated above.'),
    ...pt(
        '#',
        'not checked',
        r'I did not build an image. mkinitcpio is an Arch tool and '
        r'was not available, so every statement about what the '
        r'hooks do comes from the file’s own comments and from my '
        r'knowledge of the tool.'),

    ...sec('history, and the order of operations'),
    ...para(
        '#',
        r'One commit, d552dfd on 2026-09-19, the initial one, whose '
        r'body mentions “the boot configuration”. A sibling file, '
        r'linux.preset, was added six minutes later in 208de62. '
        r'The two together are the pair that turns this recipe into '
        r'bootable files, and the installer’s last line is the '
        r'step that connects them to the machine:'),
    ...code('bash', 'install.sh · after merging the five files', r'''
  echo "compare them by hand, then run: sudo mkinitcpio -P"'''),
    ...para(
        '#',
        r'The -P flag rebuilds every preset, so both UKIs are '
        r'regenerated from the recipe on this page. After a '
        r'change here, nothing is different at the next boot until '
        r'that command has been run.'),

    ...sec('limits, and what is next'),
    ...pt(
        '#',
        'DKMS ordering is implicit',
        r'the file depends on the nvidia modules existing at build '
        r'time and says nothing about it. A short comment naming '
        r'the dependency would help the next editor.'),
    ...pt(
        '#',
        'the diff is by hand',
        r'the repo cannot show which lines differ from the package '
        r'default. A diff step in install.sh would make “compare '
        r'them by hand” a command, and would be most valuable for '
        r'this file.'),
    ...pt(
        '#',
        'modeset not tracked',
        r'loading nvidia_drm early is only half of early KMS: the '
        r'driver also has to be told to enable mode setting. No '
        r'tracked file does that (not the kernel command line, not '
        r'a modprobe.d file), so it must come from the driver '
        r'package or from untracked configuration. I could not '
        r'tell which.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
