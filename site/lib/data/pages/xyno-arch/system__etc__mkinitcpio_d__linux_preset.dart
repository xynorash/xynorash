import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/mkinitcpio.d/linux.preset',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'linux.preset — two boot images, each one a single EFI file'),
    cm('#', r'a normal image and a wide-net fallback, built as UKIs'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'tells mkinitcpio which images to build for the linux kernel'),
    kv(r'format', r'shell variables, 18 lines, 6 of them active'),
    kv(r'outputs', r'/boot/EFI/Linux/arch-linux.efi and arch-linux-fallback.efi'),
    kv(r'installed', r'never automatically; install.sh --system only prints it'),
    kv(r'history', r'1 commit: 208de62 (2026-09-19), six minutes after the first'),

    ...sec(r'why this file exists'),
    ...para('#',
        r'mkinitcpio does not decide by itself what to build. For each '
        r'kernel package there is a preset: a list of named presets and, '
        r'for each one, where its output goes. Arch ships a preset for '
        r'the linux package that builds a classic initramfs file for '
        r'a separate kernel file. This repository replaces it, because '
        r'this machine does not boot a kernel plus an initramfs. It boots '
        r'Unified Kernel Images, one EFI file each, and the preset is '
        r'where that is declared.'),
    blank,
    ...para('#',
        r'The file arrived in the second commit, not the first. The '
        r'message of 208de62 says it adds “the mkinitcpio preset that '
        r'builds the fallback UKI”. The first commit had the boot '
        r'configuration but not this file, and the follow-up shows the '
        r'repo noticing the gap within six minutes (18:28, then 18:34, on '
        r'2026-09-19).'),

    ...sec(r'the active lines'),
    ...code('sh', r'system/etc/mkinitcpio.d/linux.preset · lines 4-18', r'''
ALL_kver="/boot/vmlinuz-linux"
#ALL_kerneldest="/boot/vmlinuz-linux"

PRESETS=('default' 'fallback')
#PRESETS=('default' 'fallback')

#default_config="/etc/mkinitcpio.conf"
#default_image="/boot/initramfs-linux.img"
default_uki="/boot/EFI/Linux/arch-linux.efi"
default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"

#fallback_config="/etc/mkinitcpio.conf"
##fallback_image="/boot/initramfs-linux-fallback.img"
fallback_uki="/boot/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"'''),
    ...para('#', r'What each active line does:'),
    blank,
    ...pt('#', r'ALL_kver',
        r'the kernel image to read the version from and to embed. One '
        r'path is shared by every preset.'),
    ...pt('#', r'PRESETS=(default fallback)',
        r'two presets are built on every run: the one that boots and the '
        r'one that rescues.'),
    ...pt('#', r'default_uki',
        r'the output path of the normal image. Naming a *_uki variable, '
        r'instead of the commented-out *_image one just above it, is the '
        r'switch that turns the output into a Unified Kernel Image. '
        r'Everything else about the image (kernel, initramfs, command '
        r'line) ends up inside that one file.'),
    ...pt('#', r'default_options',
        r'extra flags for the build; here a splash bitmap from the '
        r'systemd boot tooling, /usr/share/systemd/bootctl/'
        r'splash-arch.bmp.'),
    ...pt('#', r'fallback_uki',
        r'the output path of the second image, next to the first.'),
    ...pt('#', r'fallback_options="-S autodetect"',
        r'the one line that makes the fallback a fallback. -S skips a '
        r'named hook when building. Skipping autodetect means the image '
        r'is not trimmed to this machine’s hardware, so it carries a '
        r'full module set and has a better chance to boot after a '
        r'hardware change or a broken autodetect.'),

    ...sec(r'where the two files meet the rest of the repo'),
    ...para('#',
        r'The two output names are not arbitrary. loader.conf pins the '
        r'default entry to the first of them: “default arch-linux.efi”, '
        r'with a comment that this is done “so a new UKI can never '
        r'silently take over the default slot”. The fallback UKI is not '
        r'pinned and so sits in the boot menu as the second choice, '
        r'timeout 3 seconds. The two files in /boot/EFI/Linux are '
        r'found by systemd-boot without a loader entry per image, which '
        r'is how UKIs are discovered; the repo has no entry files, which '
        r'is consistent with that.'),
    blank,
    ...para('#',
        r'Both images are built from /etc/mkinitcpio.conf (the *_config '
        r'lines are commented, so the default path is used) and from '
        r'/etc/kernel/cmdline. That is the part to remember: the fallback '
        r'differs only in its hook set, not in its kernel command line.'),

    ...sec(r'trade-offs'),
    ...pt('#', r'a UKI is bigger and rebuilt as a whole',
        r'every change to the command line, the hooks or the microcode '
        r'means regenerating a complete EFI file, which is what '
        r'sudo mkinitcpio -P at the end of install.sh does.'),
    ...pt('#', r'the fallback shares the cmdline',
        r'it rescues from a bad initramfs, not from a bad cmdline.'),
    ...pt('#', r'the fallback is bigger on purpose',
        r'skipping autodetect trades disk space on the EFI system '
        r'partition for the chance to boot.'),
    ...pt('#', r'no signing',
        r'the file sets no signing options, so these are plain, '
        r'unsigned images. Secure Boot is not part of this repo.'),

    ...sec(r'failure modes'),
    ...pt('#', r'ESP too small',
        r'two full UKIs, one of them untrimmed, have to fit in '
        r'/boot/EFI/Linux. The repo does not record the partition size.'),
    ...pt('#', r'package update replaces the file',
        r'the preset is owned by the linux package; keeping a modified '
        r'copy risks a conflict on updates, which is part of why the '
        r'installer prints it for a manual diff.'),
    ...pt('#', r'a changed kernel path',
        r'ALL_kver is an absolute path; another kernel package would '
        r'need its own preset.'),

    ...sec(r'how I checked it'),
    ...para('#',
        r'No tests exist for system files. I compared the tracked preset '
        r'to /etc/mkinitcpio.d/linux.preset on the machine and they are '
        r'identical. I did not run mkinitcpio, and I could not read the '
        r'EFI system partition, so I did not look at the built images.'),

    ...sec(r'history'),
    ...pt('#', r'208de62, 2026-09-19 18:34',
        r'“Track everything needed to reproduce the desktop” adds the '
        r'preset. It is the only commit that touches the file.'),
  ],
);
