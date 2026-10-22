import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/mkinitcpio.conf',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'mkinitcpio.conf — what goes into the first-stage image'),
    cm('#', r'the stock file with two edits: NVIDIA in, kms out'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'recipe for the initramfs that is packed into the boot image'),
    kv(r'format', r'shell variables, sourced by mkinitcpio'),
    kv(r'size', r'81 lines, almost all of them the distribution’s own comments'),
    kv(r'edits', r'2 lines carry the decisions: MODULES and HOOKS'),
    kv(r'installed', r'never automatically; install.sh --system only prints it'),
    kv(r'history', r'1 commit: d552dfd (2026-09-19)'),

    ...sec(r'why this file exists'),
    ...para('#',
        r'The initramfs is the small filesystem the kernel unpacks before '
        r'it can see the real root. It contains just enough to find the '
        r'disk and mount it. mkinitcpio builds it from this file: MODULES '
        r'are kernel modules to load first, HOOKS are the build and boot '
        r'steps, and the rest is packaging. On Arch the default file is '
        r'already usable. This repository tracks its own copy for two '
        r'reasons that are visible in the diff against the stock text, and '
        r'that the installer states in one line: “nvidia modules in '
        r'MODULES, kms hook removed”.'),

    ...sec(r'edit one: the NVIDIA modules'),
    ...code('sh', r'system/etc/mkinitcpio.conf · lines 2-7', r'''
# MODULES
# The following modules are loaded before any boot hooks are
# run.  Advanced users may wish to specify all system modules
# in this array.  For instance:
#     MODULES=(usbhid xhci_hcd)
MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)'''),
    ...para('#',
        r'Four modules from the proprietary driver are listed so that they '
        r'are loaded in the initramfs, before the root filesystem is '
        r'mounted. The names are the driver’s four pieces: the core '
        r'module, mode setting, the compute (UVM) module and the DRM '
        r'glue that lets a Wayland compositor talk to the card. The file '
        r'gives no reason for loading them this early. The common reason '
        r'is to have the GPU and its console ready sooner, and to keep '
        r'the module set in step with the image; I am inferring that, the '
        r'repo does not say it. What the repo does show is the driver '
        r'choice: packages/aur.txt lists nvidia-580xx-dkms, a '
        r'versioned DKMS driver package (README.md says the card is a '
        r'GTX 980, Maxwell), and DKMS packaging means the '
        r'modules are rebuilt per kernel, which is also why the image '
        r'has to be rebuilt when it changes.'),

    ...sec(r'edit two: the hooks, without kms'),
    ...code('sh', r'system/etc/mkinitcpio.conf · line 55', r'''
HOOKS=(base udev autodetect microcode modconf keyboard keymap consolefont block filesystems fsck)'''),
    ...para('#',
        r'Read left to right, this is the order the hooks run in. base and '
        r'udev are the required core, named as such in the comment above '
        r'the line. autodetect shrinks the image to the modules this '
        r'machine uses. microcode prepends CPU microcode. modconf copies '
        r'modprobe configuration in. keyboard, keymap and consolefont '
        r'make typing and the console usable. block, filesystems and fsck '
        r'find the disk, load the btrfs driver and check it.'),
    blank,
    ...para('#',
        r'The word that is missing is kms. The example hook lines in the '
        r'file’s own comments still contain it (the systemd-based example '
        r'lists autodetect microcode modconf kms keyboard), and, as I '
        r'remember it, the stock Arch file has it in the active line. '
        r'This copy has it removed, and the installer says so: '
        r'“kms hook removed”. The kms hook pulls in the open-source '
        r'graphics drivers for early mode setting. On a machine that '
        r'uses the proprietary NVIDIA modules, which are named in MODULES '
        r'instead, I would expect that hook to be pointless; I take that '
        r'to be the reasoning, though no comment records it.'),

    ...sec(r'what the other 79 lines are'),
    ...para('#',
        r'The rest of the file is the stock documentation: examples of '
        r'hook lists for RAID, LVM and encrypted roots, and a block of '
        r'commented-out COMPRESSION choices. All of that is inactive. '
        r'Notably COMPRESSION is not set, so the default applies; the '
        r'file’s own comment says zstd for kernels 5.9 and later. '
        r'BINARIES and FILES are empty arrays. Keeping the whole stock '
        r'comment text, rather than a trimmed file, is a choice: the '
        r'two active edits stand out against the surrounding text, which '
        r'makes the file easy to compare by hand, and the installer asks '
        r'for exactly that comparison.'),

    ...sec(r'why it is printed, not installed'),
    ...code('bash', r'install.sh · lines 74-80', r'''
  echo "not installed automatically, they replace files the system owns:"
  echo "  system/etc/pam.d/greetd        adds gnome-keyring unlock at login"
  echo "  system/etc/mkinitcpio.d/linux.preset  builds the fallback UKI as well"
  echo "  system/etc/mkinitcpio.conf     nvidia modules in MODULES, kms hook removed"
  echo "  system/etc/kernel/cmdline      kernel command line baked into the UKI"
  echo "  system/boot/loader/loader.conf systemd-boot (editor disabled, default pinned)"
  echo "compare them by hand, then run: sudo mkinitcpio -P"'''),
    ...para('#',
        r'This file decides whether the machine boots. A hook list written '
        r'for different hardware, or a module that does not exist for the '
        r'installed kernel, produces an image that cannot mount the root. '
        r'The installer therefore never overwrites it: you read the '
        r'difference, apply the part you want, and rebuild with '
        r'mkinitcpio -P. Because the package that owns the file also '
        r'ships updates to it, a blind copy could silently revert '
        r'upstream changes too; that is a general property of copying '
        r'over a package-owned file, and not something the repo states.'),

    ...sec(r'failure modes'),
    ...pt('#', r'a module missing for the kernel',
        r'mkinitcpio warns or fails at build time; with DKMS the module '
        r'has to be built before the image is.'),
    ...pt('#', r'edit without rebuild',
        r'nothing changes until mkinitcpio -P runs; the file is only '
        r'read when images are made.'),
    ...pt('#', r'dropped filesystems or block hook',
        r'the image would not be able to find or mount the btrfs root. '
        r'The fallback image is built with -S autodetect (see '
        r'linux.preset), which is the escape hatch for a too-narrow '
        r'autodetect, not for a broken hook list.'),

    ...sec(r'how I checked it'),
    ...para('#',
        r'No test exists for this file. I diffed the tracked copy with '
        r'/etc/mkinitcpio.conf on the machine and they are identical. I '
        r'did not run mkinitcpio, so the claims about what each hook '
        r'does come from the file’s own comments and my knowledge of the '
        r'tool, not from a build I observed.'),

    ...sec(r'history'),
    ...pt('#', r'd552dfd, 2026-09-19',
        r'added with the initial commit, and unchanged since. The '
        r'follow-up commit 208de62 added the preset next to it, which '
        r'is the other half of the boot image story.'),
  ],
);
