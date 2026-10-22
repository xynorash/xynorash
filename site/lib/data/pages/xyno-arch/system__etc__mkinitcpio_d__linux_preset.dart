import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/mkinitcpio.d/linux.preset',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'linux.preset — two kernels, one recipe, no loose files'),
    cm('#', 'where the unified kernel images are written, and how'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'tells mkinitcpio which images to build for the linux kernel and where to put them'),
    kv('language', 'bash, sourced by mkinitcpio; 18 lines, 6 of them active'),
    kv('size', '1 commit: 208de62 (2026-09-19 18:34), six minutes after the first'),
    kv('outputs', '/boot/EFI/Linux/arch-linux.efi and arch-linux-fallback.efi'),
    kv('installed by', 'nobody: printed in install.sh as “builds the fallback UKI as well”'),

    ...sec('why this file exists'),
    ...para(
        '#',
        r'A preset is the link between a kernel package and '
        r'mkinitcpio. The recipe for an initramfs lives in '
        r'etc/mkinitcpio.conf; the preset says which kernel to '
        r'build it for, how many variants to make, and where each '
        r'result goes. The file belongs to the linux package '
        r'(its first line says “preset file for the ‘linux’ '
        r'package”) and has been edited here to produce one thing '
        r'that the stock file does not: unified kernel images on '
        r'the EFI system partition, with a fallback next to the '
        r'default.'),
    blank,
    ...para(
        '#',
        r'This is where the boot chain described on the loader.conf '
        r'page gets its two entry points. systemd-boot lists what it '
        r'finds under EFI/Linux, and this file decides what is '
        r'there. If it did not exist, there would be no '
        r'arch-linux.efi for loader.conf to pin as the default.'),

    ...sec('a unified kernel image, in one picture'),
    ...para(
        '#',
        r'A UKI is a single EFI executable made of named sections. '
        r'The names below come from the UKI specification as I '
        r'know it, and I have matched each to the file in this repo '
        r'that supplies its content:'),
    blank,
    plain('  arch-linux.efi'),
    plain('    .linux    the kernel      from /boot/vmlinuz-linux (ALL_kver)'),
    plain('    .initrd   the initramfs   built from etc/mkinitcpio.conf'),
    plain('    .cmdline  boot parameters from etc/kernel/cmdline'),
    plain('    .splash   a bitmap        from default_options --splash'),
    plain('    .osrel    identity        from /etc/os-release'),
    blank,
    ...para(
        '#',
        r'The point of the format is that the firmware, or a '
        r'bootloader, runs one file and every ingredient arrives '
        r'together. Nothing can be mismatched: the initramfs that '
        r'was built for a kernel is welded to that kernel, and the '
        r'command line cannot be swapped for another at the menu. '
        r'That fits the settings in loader.conf, and it is why '
        r'the editor there can be switched off without losing '
        r'much.'),

    ...sec('the file, in full'),
    ...code('bash', 'system/etc/mkinitcpio.d/linux.preset', r'''
# mkinitcpio preset file for the 'linux' package

#ALL_config="/etc/mkinitcpio.conf"
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
    ...para(
        '#',
        r'Eighteen lines, and only six do anything. Sourcing the '
        r'file in bash defines exactly six variables: ALL_kver, '
        r'PRESETS, default_uki, default_options, fallback_uki and '
        r'fallback_options, with PRESETS holding two entries. '
        r'Every other line is a commented-out default, kept as '
        r'documentation of what the preset could set.'),

    ...sec('line by line'),
    ...pt(
        '#',
        'ALL_kver="/boot/vmlinuz-linux"',
        r'the kernel image to bundle. The location tells a lot: '
        r'the kernel is in /boot, and the UKIs are written to '
        r'/boot/EFI/Linux, so /boot is the EFI system partition, '
        r'not a directory on the btrfs root. That is why '
        r'loader.conf lives under system/boot/ in this repo, and '
        r'why it lands in /boot/loader/.'),
    ...pt(
        '#',
        'PRESETS=(default fallback)',
        r'two variants will be built, and the names of the rest of '
        r'the variables are derived from them: every default_ and '
        r'fallback_ line belongs to its preset. The commented '
        r'duplicate on the next line is how the package ships '
        r'the file.'),
    ...pt(
        '#',
        'default_uki=.../arch-linux.efi',
        r'build a UKI, at this path. This is the line that '
        r'loader.conf’s default arch-linux.efi refers to. It is '
        r'also the first of the repo’s changes to the stock file: '
        r'the neighbouring #default_image line is commented, so '
        r'no loose initramfs-linux.img is written. The system boots '
        r'from UKIs only.'),
    ...pt(
        '#',
        'default_options="--splash ..."',
        r'extra arguments for this preset. --splash embeds a '
        r'bitmap that the EFI stub shows while the kernel loads. '
        r'The path is the Arch logo that the systemd package ships '
        r'under /usr/share/systemd/bootctl. It only affects the '
        r'default image.'),
    ...pt(
        '#',
        'fallback_uki=.../arch-linux-fallback.efi',
        r'a second UKI with its own name, so the two coexist in the '
        r'same directory and both appear in the boot menu.'),
    ...pt(
        '#',
        'fallback_options="-S autodetect"',
        r'-S skips a hook, here the one that trims the image to the '
        r'hardware seen at build time. The default image is small '
        r'and specific; the fallback is large and general. It also '
        r'carries no splash, so the two are visually distinguishable '
        r'at boot (my observation of the options, not of a boot).'),

    ...sec('the story of the fallback'),
    ...para(
        '#',
        r'The initial commit (d552dfd, 2026-09-19 18:28) already '
        r'pinned arch-linux.efi as the default in loader.conf and '
        r'already carried mkinitcpio.conf, but not this file. Six '
        r'minutes later the second commit added it. The message '
        r'explains the intent in one clause:'),
    ...code('bash', 'install.sh · the printed hint', r'''
  echo "  system/etc/mkinitcpio.d/linux.preset  builds the fallback UKI as well"'''),
    ...para(
        '#',
        r'“As well” is the interesting phrase. It implies that the '
        r'default image was already being built before this file '
        r'was tracked, and that the new thing in the repo is the '
        r'second variant. My reading is that the machine already '
        r'had a UKI-producing preset, which I guess came from how '
        r'it was installed, and that Nash noticed within minutes '
        r'that his tracked config did not describe the whole boot '
        r'and added the missing file. That is an inference from '
        r'the timestamps and the wording; the commit body says only '
        r'that the preset “builds the fallback UKI”.'),
    blank,
    ...para(
        '#',
        r'Why a fallback at all? The default image is built with '
        r'the autodetect hook, which keeps only the modules this '
        r'machine needed when the image was built. That is the '
        r'right trade for speed and size, and it carries one risk: '
        r'change the storage controller, move the disk to another '
        r'host, add a module you did not need before, and the '
        r'small image may lack it. The fallback is the same '
        r'recipe with that trimming removed. The page for '
        r'packages/aur.txt makes the same point about the NVIDIA '
        r'driver: the fallback guards against a module missing '
        r'from the trimmed image, not against a module that '
        r'fails to build.'),

    ...sec('how the pieces connect'),
    ...pt(
        '#',
        'who runs the preset',
        r'mkinitcpio -P rebuilds every preset, which is what the '
        r'installer tells the owner to run after merging the five '
        r'boot files. When the linux package updates, a pacman hook '
        r'runs the same builder, as far as I know; that is how the '
        r'images stay current without anyone running a command.'),
    ...pt(
        '#',
        'who reads the output',
        r'systemd-boot, per loader.conf. It lists both files; the '
        r'pinned default boots the first.'),
    ...pt(
        '#',
        'where the command line comes from',
        r'neither preset sets one, so both images take the same '
        r'one, from etc/kernel/cmdline, which is how I explain '
        r'why the fallback cannot rescue a bad root= value.'),
    ...pt(
        '#',
        'where the contents come from',
        r'etc/mkinitcpio.conf for both, with the fallback skipping '
        r'autodetect. The commented ALL_config and default_config '
        r'lines show the default path is used.'),

    ...sec('what could go wrong, and what the repo does about it'),
    ...para(
        '#',
        r'The risks of this layout are structural, and I list '
        r'them as readings of the file, not as incidents. The repo '
        r'records none.'),
    blank,
    ...pt(
        '#',
        'one filesystem for everything',
        r'the kernel, both images and the loader share the EFI '
        r'system partition. Two images, one of them with every '
        r'module, plus the kernel, are a lot for a small FAT '
        r'partition. The repo does not say how large it is, so I '
        r'cannot say whether there is room.'),
    ...pt(
        '#',
        'not covered by btrfs snapshots',
        r'/boot is outside the btrfs root. A snapshot of the root '
        r'does not contain the images, and rolling it back would '
        r'not roll them back. snapper is installed but no '
        r'configuration is tracked.'),
    ...pt(
        '#',
        'no signature',
        r'nothing here signs the images, and sbctl is not in '
        r'packages/pacman.txt. Without Secure Boot, the UKI '
        r'is convenient and not tamper-evident.'),
    ...pt(
        '#',
        'a hard-coded path',
        r'the output paths are literals, and the ESP mount point '
        r'is never stated: it can only be inferred from these '
        r'paths and from where loader.conf is filed. Nothing '
        r'checks that the two agree.'),

    ...sec('history'),
    ...pt(
        '#',
        '208de62, 2026-09-19 18:34',
        r'created the file in the repo. The commit message calls '
        r'it “the mkinitcpio preset that builds the fallback UKI”, '
        r'and lists it with the greetd PAM stack and a few other '
        r'files that make the desktop reproducible.'),
    ...pt(
        '#',
        'since',
        r'no change in the remaining history. The file is as stable '
        r'as the loader.conf it pairs with.'),

    ...sec('limits, and what is next'),
    ...para(
        '#',
        r'I did not build an image: mkinitcpio and an EFI system '
        r'partition were not available to me, so the section names '
        r'in the picture, the behaviour of -S and --splash, and '
        r'the existence of the pacman hook are things I know about '
        r'the tools. What I verified is the file itself: it parses '
        r'as shell, and sourcing it yields the six variables '
        r'listed above. A future version could sign the images and '
        r'put the ESP size in a comment; the repo’s own '
        r'installer already points to the hand-merge as the weak '
        r'step.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
