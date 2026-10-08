import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/boot/loader/loader.conf',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'loader.conf — four decisions for the boot menu'),
    cm('#', 'pin the default, keep the menu short, lock the editor'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'systemd-boot configuration: what boots, and what the menu allows'),
    kv('language', 'loader.conf(5): key value pairs, # comments'),
    kv('size', '18 lines, 4 settings, 1 commit: d552dfd (2026-09-19)'),
    kv('lands at', '/boot/loader/loader.conf (the UKI paths imply the ESP is /boot)'),
    kv('installed by', 'nobody: install.sh --system prints it and leaves it to a human'),

    ...sec('why this file exists'),
    ...para(
        '#',
        r'This is the first configuration file the machine reads that '
        r'belongs to Nash instead of to a package. The firmware starts '
        r'systemd-boot from the EFI system partition, systemd-boot '
        r'reads loader.conf, and everything after it, the kernel, the '
        r'initramfs, the login screen, is reached through the choices '
        r'made here. It is only four settings, but each one is a '
        r'decision with a reason, and three of the four carry a '
        r'comment that states it.'),
    blank,
    ...para(
        '#',
        r'The page also has a second job. The 14 files under system/ '
        r'form a chain, and this is its head, so the whole chain is '
        r'laid out below. The other pages in this directory zoom into '
        r'one link each.'),

    ...sec('the boot chain, in order'),
    plain('  UEFI firmware'),
    plain('    -> systemd-boot, on the ESP      reads loader.conf (this page)'),
    plain('    -> menu entry arch-linux.efi     a UKI, built by mkinitcpio'),
    plain('    -> systemd-stub, inside the UKI  hands over kernel + initramfs'),
    plain('    -> initramfs                     contents: etc/mkinitcpio.conf'),
    plain('    -> kernel command line           etc/kernel/cmdline, baked in'),
    plain('    -> root on btrfs subvolume @     rootflags=subvol=@'),
    plain('    -> systemd, then greetd          etc/greetd/config.toml'),
    plain('    -> tuigreet -> PAM -> start-hyprland   the desktop'),
    blank,
    ...para(
        '#',
        r'Only the first two arrows are this file. The rest is what the '
        r'entry points at. The evidence for the shape is spread over '
        r'the repo: the default entry named below is arch-linux.efi; '
        r'etc/mkinitcpio.d/linux.preset says that file is a unified '
        r'kernel image (UKI) written to /boot/EFI/Linux; the README '
        r'table says “systemd-boot with a Unified Kernel Image” and '
        r'“btrfs with snapper, zram swap”. A UKI is one EFI executable '
        r'that carries the kernel, the initramfs, the command line and '
        r'an optional splash bitmap, so the boot menu has nothing to '
        r'assemble: it lists the files it finds under EFI/Linux and '
        r'starts the chosen one. That last sentence is how I '
        r'understand systemd-boot’s automatic entry discovery, not '
        r'something the repo spells out.'),

    ...sec('the file, in full'),
    ...code('ini', 'system/boot/loader/loader.conf', r'''
# Pin the default rather than relying on sort-key ordering, so a new UKI
# can never silently take over the default slot.
default      arch-linux.efi
timeout      3

# Use the largest console mode the firmware offers — the menu renders at
# 1080p instead of a tiny 80x25 box.
console-mode max

# SECURITY: without this, anyone at the keyboard can press 'e' at the menu,
# append init=/bin/bash to the kernel command line and get a root shell with
# no password. Your disk is not encrypted, so this is the only thing standing
# between physical access and root.
editor       no

# Keep the "Reboot Into Firmware Interface" entry — that is how you reach
# Windows, which lives on a separate ESP that systemd-boot cannot chainload.
auto-firmware yes'''),
    ...para(
        '#',
        r'Every setting is paired with a comment, and the comments '
        r'are written as warnings to a future editor: “can never '
        r'silently”, “SECURITY”, “that is how you reach Windows”. The '
        r'file is a list of things that would be easy to change '
        r'without noticing what they protect.'),

    ...sec('default arch-linux.efi: a name that must match another file'),
    ...para(
        '#',
        r'The comment gives the reason: “Pin the default rather than '
        r'relying on sort-key ordering, so a new UKI can never '
        r'silently take over the default slot.” There are two UKIs on '
        r'this machine, and they are named in another file:'),
    ...code('bash', 'system/etc/mkinitcpio.d/linux.preset · UKI names', r'''
default_uki="/boot/EFI/Linux/arch-linux.efi"
fallback_uki="/boot/EFI/Linux/arch-linux-fallback.efi"'''),
    ...para(
        '#',
        r'So the default is a file name, and that file name is '
        r'written in two places that nothing keeps in sync: the preset '
        r'creates it, loader.conf selects it. If the preset were ever '
        r'edited to rename the image, the pin would point at nothing. '
        r'What systemd-boot does then I have not verified, and I '
        r'would not rely on it; my understanding is that it falls '
        r'back to its own ordering, which is exactly the situation '
        r'the pin was written to avoid. The coupling is the price of '
        r'a deterministic default, and it is a good argument for '
        r'treating loader.conf and linux.preset as a pair.'),
    blank,
    ...para(
        '#',
        r'There is also a safety angle I read into the pin. The '
        r'second image, arch-linux-fallback.efi, is a recovery '
        r'image built with the autodetect step skipped. A '
        r'default that depends on ordering could, in principle, '
        r'promote the recovery image to the normal boot. Naming the '
        r'default file keeps the recovery entry a deliberate choice '
        r'in the menu.'),

    ...sec('timeout 3 and console-mode max'),
    ...pt(
        '#',
        'timeout 3',
        r'the menu waits three seconds and then boots the default. '
        r'That is long enough to press a key and choose the fallback '
        r'entry, short enough that a normal boot is not slowed by '
        r'it. The repo does not state a reason for the number; this '
        r'is my reading of the trade-off.'),
    ...pt(
        '#',
        'console-mode max',
        r'asks the firmware for its highest text-mode resolution. '
        r'The comment’s claim is the effect: the menu renders at '
        r'1080p instead of “a tiny 80x25 box”. The monitor in '
        r'hyprland.lua is a 1920x1080 panel, so max is a resolution '
        r'that suits it. The firmware decides what max means, so '
        r'on other hardware the same line gives a different result.'),

    ...sec('editor no: a threat model in four lines'),
    ...para(
        '#',
        r'The comment is the most explicit security statement in the '
        r'repo, so it is worth taking apart. The attack it describes '
        r'is short: at the menu, press e, append init=/bin/bash to '
        r'the command line, boot, and the kernel starts a root shell '
        r'with no password. The editor lets whoever is at the keyboard '
        r'rewrite the kernel command line for one boot, and root '
        r'filesystems are mounted read-write by default here (the '
        r'command line says rw), so nothing stops the shell.'),
    blank,
    ...para(
        '#',
        r'The comment’s premise, “your disk is not encrypted”, is '
        r'what makes it matter: with full-disk encryption the same '
        r'trick would stop at the passphrase prompt. Nothing in the '
        r'repo configures encryption, and the mkinitcpio hook list '
        r'has no encrypt hook, so the premise holds.'),
    blank,
    ...para(
        '#',
        r'The claim “the only thing standing between physical access '
        r'and root” is strong, and I would soften it. This setting '
        r'closes the menu path. Someone who can boot a USB stick, '
        r'or open the machine, still reaches the unencrypted disk. '
        r'The option is a lock on one door of an unlocked building, '
        r'and the comment is honest about why the building is '
        r'unlocked. Without a firmware password it also does not '
        r'stop a person from choosing another boot device. That '
        r'caveat is my commentary, not the file’s.'),
    blank,
    ...para(
        '#',
        r'The setting has a cost that the comment does not '
        r'mention. With the editor gone, the legitimate uses of the '
        r'same feature go with it: booting once into '
        r'systemd.unit=rescue.target, or adding a debug parameter to '
        r'diagnose a boot problem. Because the kernel command line '
        r'is baked into each UKI (see etc/kernel/cmdline), the '
        r'remedy for a bad parameter is to boot something else, '
        r'rebuild, and reboot. Both UKIs read the same command '
        r'line, so the fallback entry helps with a missing module '
        r'and does not help with a bad root= or rootflags= value. '
        r'The preset sets no command line of its own for either '
        r'image, which is what makes me think so.'),

    ...sec('auto-firmware yes: the way to Windows'),
    ...para(
        '#',
        r'The comment states the dual-boot design in one clause: '
        r'Windows lives on its own EFI system partition, and '
        r'systemd-boot, which only sees the ESP it was installed on, '
        r'cannot chainload it. The practical result is that the '
        r'systemd-boot menu has no Windows entry. The “Reboot Into '
        r'Firmware Interface” entry is the door: choose it, then pick '
        r'the Windows disk in the firmware’s boot menu.'),
    blank,
    ...para(
        '#',
        r'As I read the loader.conf manual, yes is already the '
        r'default for this option, so the line restates a default, '
        r'in the same spirit as the repeated defaults in gamemode.ini. '
        r'Its value is the comment: it records why the entry '
        r'matters, so nobody tidies it away. efibootmgr, which is '
        r'in packages/pacman.txt, is the command-line tool for the '
        r'same firmware entries. The repo does not say what '
        r'it is used for, so treat that pairing as a hint.'),

    ...sec('why this file is never installed automatically'),
    ...para(
        '#',
        r'install.sh --system copies nine system files and prints a '
        r'list of five that it leaves alone. This is one of the '
        r'five:'),
    ...code('bash', 'install.sh · the printed list', r'''
  echo "not installed automatically, they replace files the system owns:"
  echo "  system/etc/pam.d/greetd        adds gnome-keyring unlock at login"
  echo "  system/etc/mkinitcpio.d/linux.preset  builds the fallback UKI as well"
  echo "  system/etc/mkinitcpio.conf     nvidia modules in MODULES, kms hook removed"
  echo "  system/etc/kernel/cmdline      kernel command line baked into the UKI"
  echo "  system/boot/loader/loader.conf systemd-boot (editor disabled, default pinned)"
  echo "compare them by hand, then run: sudo mkinitcpio -P"'''),
    ...para(
        '#',
        r'The rule behind the split, as I read the two lists, is '
        r'additive versus replacing. The nine installed files are '
        r'new drop-ins in directories that read every file '
        r'(sysctl.d, limits.d, modules-load.d, the systemd drop-in '
        r'directories) or standalone service files. The five printed '
        r'ones overwrite a file that already exists and that the '
        r'machine needs in order to start. A bad sysctl line costs '
        r'one setting; a bad loader.conf or mkinitcpio.conf costs a '
        r'machine that does not boot, and the person has to repair it '
        r'from outside. The split is not perfect: etc/greetd/config.toml '
        r'is installed automatically, and I believe the greetd package '
        r'ships a default of the same name, which would make it a '
        r'replacement too. A broken greeter config is cheap to fix '
        r'from a text console, which may be the difference.'),
    blank,
    ...para(
        '#',
        r'The README says only three files are skipped (mkinitcpio.conf, '
        r'kernel/cmdline, loader.conf), while the installer prints five. '
        r'pam.d/greetd and mkinitcpio.d/linux.preset were added to the '
        r'printed list in 208de62, six minutes after the initial '
        r'commit, and the README text was not updated. The script is '
        r'the authority.'),

    ...sec('history'),
    ...pt(
        '#',
        'd552dfd, 2026-09-19 18:28',
        r'the initial commit contained the whole file. The commit '
        r'body lists “the boot configuration” among the system-side '
        r'files.'),
    ...pt(
        '#',
        'since then',
        r'no change. git log shows one commit for this path. The '
        r'file has been stable for the 19 days of '
        r'history that exist, which fits a file that records '
        r'decisions instead of tuning values.'),

    ...sec('how I would check it, and what I could not'),
    ...para(
        '#',
        r'The right tool is bootctl from systemd. bootctl status '
        r'shows the loader and the ESP it found, and bootctl list '
        r'prints each entry with its id and marks the default. Those '
        r'two commands would confirm the pin and the discovery of '
        r'both UKIs. I did not run them: the machine this page '
        r'describes is an Arch box and I only had the repository, '
        r'so everything above about systemd-boot’s behaviour is '
        r'documentation knowledge applied to the file, not an '
        r'observation of this boot.'),

    ...sec('limits, and what is next'),
    ...pt(
        '#',
        'no Secure Boot',
        r'nothing in the repo signs the UKIs or enrols keys. The '
        r'comment’s phrase “anyone at the keyboard” would change if '
        r'it did. A signed UKI would also make the baked-in command '
        r'line tamper-evident, which suits the editor setting.'),
    ...pt(
        '#',
        'no automation',
        r'the five boot files are compare-by-hand. A --diff mode in '
        r'install.sh would turn that sentence into a command, as '
        r'the install.sh page also suggests.'),
    ...pt(
        '#',
        'one name, two files',
        r'arch-linux.efi appears here and in linux.preset. A check '
        r'that the default exists under /boot/EFI/Linux would catch '
        r'the one failure this pin can cause.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
