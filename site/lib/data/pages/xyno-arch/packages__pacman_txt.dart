import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/packages/pacman.txt',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'pacman.txt — 67 names that describe a machine'),
    cm('#', 'the explicit official-repo packages, one per line'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'the programs the configs in this repo configure'),
    kv('format', 'bare package names, no comments, sorted'),
    kv('size', '67 packages (plus 9 in aur.txt)'),
    kv('history', 'one commit, d552dfd (2026-09-19), never edited since'),
    kv('consumed by', 'nothing: install.sh never reads it'),

    ...sec('what kind of list this is'),
    ...para(
        '#',
        r'The file is a flat list of package names with no comments, '
        r'no versions and no groups. It is sorted in plain byte '
        r'order (checked with LC_ALL=C sort -c, which passes). It '
        r'holds base and linux, but none of their dependencies: no '
        r'glibc, no bash, and not even git, python or curl. '
        r'Together those facts say it is a list of what was '
        r'installed deliberately, the sort of output pacman '
        r'produces for “explicitly installed, from the sync '
        r'repos”. The repo does not name the command, so that part '
        r'is inference. The matching file for packages that came '
        r'from outside the sync repos is packages/aur.txt.'),
    blank,
    ...para(
        '#',
        r'That makes it an unusually honest document. A configuration '
        r'file says what a person intended; an explicit install '
        r'list says what they actually chose to put on the box. '
        r'Read together with the configs, it reveals what the '
        r'desktop depends on, what it quietly does without, and a '
        r'few places where the repo and the list disagree.'),

    ...sec('the machine in eleven groups'),
    ...para(
        '#',
        r'67 names, sorted into the roles they play. The grouping '
        r'is mine; each group cites the file in this repo that '
        r'shows why the package is there.'),
    blank,
    ...pt(
        '#',
        'base and boot (11)',
        r'base, base-devel, linux, linux-firmware, linux-headers, '
        r'mkinitcpio, amd-ucode, efibootmgr, btrfs-progs, snapper, '
        r'sudo.'),
    ...pt(
        '#',
        'memory (1)',
        r'zram-generator.'),
    ...pt(
        '#',
        'NVIDIA support (5)',
        r'dkms, egl-gbm, egl-wayland, egl-x11, vulkan-tools. The '
        r'driver itself is in aur.txt.'),
    ...pt(
        '#',
        'session and desktop (9)',
        r'hyprland, noctalia, greetd, greetd-tuigreet, seatd, '
        r'gnome-keyring, xdg-desktop-portal-gtk, '
        r'xdg-desktop-portal-hyprland, xwayland-satellite.'),
    ...pt(
        '#',
        'audio (7)',
        r'pipewire, pipewire-alsa, pipewire-jack, pipewire-pulse, '
        r'wireplumber, gst-plugin-pipewire, libpulse.'),
    ...pt(
        '#',
        'gaming (7)',
        r'steam, gamemode, lib32-gamemode, mangohud, lib32-mangohud, '
        r'scx-scheds, scx-tools.'),
    ...pt(
        '#',
        'terminal, files, tools (13)',
        r'ghostty, yazi, neovim, fd, fzf, ripgrep, zoxide, jq, '
        r'poppler, ffmpeg, 7zip, github-cli, less.'),
    ...pt(
        '#',
        'fonts (6)',
        r'noto-fonts, noto-fonts-cjk, noto-fonts-emoji, ttf-dejavu, '
        r'ttf-jetbrains-mono-nerd, ttf-liberation.'),
    ...pt(
        '#',
        'services (5)',
        r'docker, tailscale, cockpit, packagekit, udisks2.'),
    ...pt(
        '#',
        'applications (1)',
        r'discord.'),
    ...pt(
        '#',
        'unexplained (2)',
        r'libxslt and xcb-util-keysyms. Nothing else in the repo '
        r'mentions either, and I will not guess why they were '
        r'chosen.'),

    ...sec('base and boot: the list agrees with the boot files'),
    ...code('text', 'packages/pacman.txt · base and boot', r'''
amd-ucode
base
base-devel
btrfs-progs
...
efibootmgr
...
linux
linux-firmware
linux-headers
...
mkinitcpio
...
snapper
...
sudo'''),
    ...para(
        '#',
        r'Most lines here have a counterpart in the boot files, '
        r'which is a good sign that the list and the system were '
        r'captured from the same machine.'),
    blank,
    ...pt(
        '#',
        'amd-ucode',
        r'mkinitcpio.conf has the microcode hook in its list, so '
        r'the CPU microcode is built into the unified kernel image. '
        r'There is no intel-ucode: this is the Ryzen 7 5800X the '
        r'README names.'),
    ...pt(
        '#',
        'btrfs-progs and snapper',
        r'the kernel command line says rootfstype=btrfs and '
        r'rootflags=subvol=@, so the root is a btrfs subvolume. '
        r'snapper is installed and the README calls the filesystem '
        r'“btrfs with snapper”, but no snapper configuration is '
        r'tracked anywhere in the repo.'),
    ...pt(
        '#',
        'mkinitcpio, linux-headers',
        r'the linux.preset file builds the unified kernel images. '
        r'linux-headers plus dkms (below) are what let an '
        r'out-of-tree driver be rebuilt for each kernel.'),
    ...pt(
        '#',
        'efibootmgr',
        r'no bootloader package appears at all, which fits '
        r'systemd-boot: it ships inside systemd. efibootmgr edits '
        r'the UEFI boot entries, and the comments in loader.conf '
        r'show that the firmware entry matters on this machine:'),
    ...code('conf', 'system/boot/loader/loader.conf · the firmware entry', r'''
# Keep the "Reboot Into Firmware Interface" entry — that is how you reach
# Windows, which lives on a separate ESP that systemd-boot cannot chainload.
auto-firmware yes'''),
    ...para(
        '#',
        r'So a second operating system lives beside this one. A '
        r'comment in hyprland.lua mentions “the VM’s TimeSync.ps1 '
        r'helper” for its WinApps rules, so there is a second, '
        r'virtual route to Windows as well. docker is in the list, '
        r'but the repo does not say that it hosts that VM.'),

    ...sec('zram-generator: half a setup is tracked'),
    ...para(
        '#',
        r'The package is listed, and the repo carries the tuning '
        r'that goes with compressed swap: '
        r'system/etc/sysctl.d/99-zram.conf, whose first comment '
        r'reads “zram is RAM-backed compressed swap: swapping is '
        r'cheap, so lean on it early.” The kernel command line also '
        r'switches the older zswap off (zswap.enabled=0), which I '
        r'read as avoiding two stacked compression layers.'),
    blank,
    ...para(
        '#',
        r'What I could not find is the file that tells '
        r'zram-generator to create a device. git ls-files has only '
        r'the sysctl file for zram, and no zram-generator.conf. '
        r'So either the device is configured by hand outside the '
        r'repo, or it relies on package defaults I cannot verify '
        r'from here. For a repo whose claim is reproducibility, '
        r'this is the clearest case of the tuning being tracked '
        r'and the thing being tuned not.'),

    ...sec('NVIDIA support: three EGL libraries, DKMS and a diagnostic'),
    ...code('text', 'packages/pacman.txt · NVIDIA support', r'''
dkms
...
egl-gbm
egl-wayland
egl-x11
...
vulkan-tools'''),
    ...para(
        '#',
        r'The driver is missing from this file on purpose; it is '
        r'in aur.txt (see that page for the 580xx story). What is '
        r'here is everything around it. dkms and linux-headers '
        r'exist so the AUR driver can be compiled against the '
        r'running kernel. The three egl-* packages are NVIDIA’s EGL '
        r'platform libraries for GBM, Wayland and X11, which is my '
        r'background knowledge, not something the repo states. '
        r'vulkan-tools provides vulkaninfo and vkcube, the '
        r'quickest way to ask whether the Vulkan stack works. The '
        r'repo refers to none of them by name.'),
    blank,
    ...para(
        '#',
        r'Their effect shows up in the boot files. mkinitcpio.conf '
        r'puts the four NVIDIA modules (nvidia, nvidia_modeset, '
        r'nvidia_uvm, nvidia_drm) into MODULES, so they load early '
        r'and the display comes up on the proprietary driver:'),
    ...code('conf', 'system/etc/mkinitcpio.conf · early NVIDIA', r'''
MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
BINARIES=()
FILES=()
HOOKS=(base udev autodetect microcode modconf keyboard keymap consolefont block filesystems fsck)'''),
    ...para(
        '#',
        r'HOOKS has no kms entry, which the installer’s printed '
        r'notice also calls out (“kms hook removed”). That is the '
        r'usual companion to loading the NVIDIA modules by hand: '
        r'the kms hook would otherwise pull in the open-source '
        r'drivers as well (outside knowledge). The file itself has '
        r'no comment about it, so the installer’s one-line notice '
        r'is the repo’s only statement of intent.'),

    ...sec('session and desktop: the part that was moved'),
    ...code('text', 'packages/pacman.txt · session and desktop', r'''
gnome-keyring
greetd
greetd-tuigreet
...
hyprland
...
noctalia
...
seatd
...
xdg-desktop-portal-gtk
xdg-desktop-portal-hyprland
xwayland-satellite'''),
    ...pt(
        '#',
        'greetd and tuigreet',
        r'greetd’s config launches the greeter with --cmd '
        r'start-hyprland, so the login screen starts the '
        r'compositor directly. No display manager or desktop '
        r'environment is installed.'),
    ...pt(
        '#',
        'gnome-keyring',
        r'two places use it: the greetd PAM stack (pam_gnome_keyring '
        r'unlocks the keyring at login) and the portal mapping, '
        r'whose Secret entry points at gnome-keyring. Without the '
        r'package both would be dead configuration.'),
    ...pt(
        '#',
        'the two portals',
        r'hyprland-portals.conf routes screen cast and screenshot '
        r'to the Hyprland portal and the file chooser, access and '
        r'notification interfaces to the GTK one. Both backends '
        r'have to be installed for that routing to work.'),
    ...pt(
        '#',
        'seatd',
        r'install.sh adds the user to a group called seat if it '
        r'exists, and this is the package that creates it.'),
    blank,
    ...para(
        '#',
        r'xwayland-satellite is the odd one. It is a separate '
        r'program that lets a Wayland compositor run X11 apps '
        r'without compositor-side XWayland, and it is the '
        r'mechanism niri uses. Hyprland has its own XWayland. Now '
        r'look at the first line of the hand-written noctalia '
        r'config:'),
    ...code('toml', 'home/.config/noctalia/config.toml · line 1', r'''
# Omarchy Quattro-inspired look, translated to noctalia + niri.'''),
    ...para(
        '#',
        r'No niri package is installed, and the compositor is '
        r'Hyprland. My reading is that this machine ran niri '
        r'first, and that this package and this comment are the '
        r'two fossils of that stage. It is an inference from '
        r'two pieces of evidence, with no commit to confirm it, '
        r'because the history of this repo begins after the move.'),

    ...sec('audio: rtkit is absent, and says so'),
    ...para(
        '#',
        r'Seven PipeWire-related names: the daemon, the ALSA, JACK '
        r'and PulseAudio shims, the session manager wireplumber, a '
        r'GStreamer plugin and libpulse. Realtime scheduling is '
        r'normally granted by RealtimeKit, and rtkit is not in '
        r'either list. The repo handles that explicitly:'),
    ...code('conf', 'system/etc/security/limits.d/99-realtime-audio.conf · header', r'''
# PipeWire realtime scheduling without rtkit.
# module-rt falls back to POSIX rlimits when RealtimeKit is unavailable.'''),
    ...para(
        '#',
        r'The absence in the list and the file in system/ are the '
        r'same decision seen from two sides. That is what I mean by '
        r'the list being a useful document: it lets you check that '
        r'a workaround and its precondition were made together.'),

    ...sec('gaming: seven names, two of them 32-bit'),
    ...code('text', 'packages/pacman.txt · gaming', r'''
gamemode
...
lib32-gamemode
lib32-mangohud
...
mangohud
...
scx-scheds
scx-tools
steam'''),
    ...para(
        '#',
        r'This is the shortest group and the most configured. Each '
        r'name has a tracked file behind it: gamemode.ini, '
        r'MangoHud.conf, scx_loader.toml, and the hook that '
        r'attaches games to GameMode (home/.local/bin/'
        r'gamemode-attach). The lib32 pair lets 32-bit processes '
        r'use GameMode and MangoHud too. Steam still ships 32-bit '
        r'components, which is my reading of why they are here.'),
    blank,
    ...para(
        '#',
        r'There is a precondition the repo does not capture. steam '
        r'and the lib32-* packages live in the [multilib] '
        r'repository, which is off in a stock pacman.conf, and '
        r'/etc/pacman.conf is not tracked. A reader following '
        r'the lists on a clean install would hit “target not '
        r'found” on four names (steam, lib32-gamemode, '
        r'lib32-mangohud and, from aur.txt, lib32-nvidia-580xx-'
        r'utils) until multilib is enabled by hand.'),
    blank,
    ...para(
        '#',
        r'What is not there is as telling as what is. No wine, '
        r'lutris, gamescope or protontricks: games run through '
        r'Steam’s own Proton, and the ntsync.conf comment names '
        r'“Wine/Proton” as the consumer of /dev/ntsync, so the '
        r'wine in question is the one Steam ships.'),

    ...sec('terminal, files, tools: yazi’s dependencies'),
    ...code('text', 'packages/pacman.txt · terminal and tools', r'''
7zip
...
fd
ffmpeg
fzf
...
ghostty
github-cli
...
jq
less
...
neovim
...
poppler
...
ripgrep
...
yazi
zoxide'''),
    ...para(
        '#',
        r'Eight of these (7zip, fd, ffmpeg, fzf, jq, poppler, '
        r'ripgrep, zoxide) are, to my knowledge, the optional '
        r'helpers Yazi’s documentation recommends for archive '
        r'handling, video and PDF previews, search and directory '
        r'jumping. That is outside knowledge. The repo-side '
        r'evidence is thinner but consistent: Yazi is the file '
        r'manager (SUPER+E runs ghostty -e yazi), its theme is '
        r'generated by noctalia, and none of the eight is '
        r'referenced anywhere else except jq, which '
        r'notification-focus calls directly.'),
    blank,
    ...para(
        '#',
        r'A related absence: the shell config has no zoxide or '
        r'fzf initialisation. They are installed for Yazi, not '
        r'wired into bash. And neovim is here with no editor '
        r'config in this repo; that configuration is a separate '
        r'project, xynovim.'),

    ...sec('services: what the configs say about each'),
    ...pt(
        '#',
        'docker',
        r'install.sh puts the user in the docker group.'),
    ...pt(
        '#',
        'cockpit',
        r'installed, and install.sh disables cockpit.socket if it '
        r'is enabled. The tool is available; it does not listen.'),
    ...pt(
        '#',
        'tailscale, packagekit, udisks2',
        r'installed, referenced nowhere else in the repo. These '
        r'three are the clearest example of a list recording '
        r'something the configs do not explain.'),
    blank,
    ...para(
        '#',
        r'There is also a networking absence worth pointing out. '
        r'Neither list contains NetworkManager, iwd or dhcpcd. '
        r'The installer disables systemd-networkd-wait-online, '
        r'and system/ has a resolved drop-in, so the stack is '
        r'systemd-networkd with systemd-resolved. The noctalia '
        r'config explains the missing wireless and Bluetooth '
        r'pieces itself:'),
    ...code('toml', 'home/.config/noctalia/config.toml · deliberate absences', r'''
# This box has no wireless adapter and bluez is not installed, so those
# tabs only ever showed a "?" or a crossed-out icon.
# No battery or AC device in /sys/class/power_supply and UPower is not
# installed, so the battery section can never show anything.'''),
    ...para(
        '#',
        r'The repo tracks no .network file, so the wired '
        r'interface’s address configuration is not reproduced '
        r'either; a fresh install would have to come up with '
        r'working networking from its base setup.'),

    ...sec('fonts: one family does the work'),
    ...para(
        '#',
        r'Six font packages. The one the configs name is '
        r'JetBrainsMono Nerd Font: it is the Ghostty font, the '
        r'GTK font and the noctalia shell font. The Noto fonts '
        r'with CJK and emoji fill in glyphs the terminal font '
        r'does not have, ttf-dejavu and ttf-liberation are the '
        r'conventional fallbacks. The ordering of responsibility '
        r'is my reading; the family names the configs reference '
        r'are the evidence.'),

    ...sec('what the list cannot reproduce'),
    ...para(
        '#',
        r'A package list captures programs, not decisions made '
        r'around them. Taking stock of what the repo and the lists '
        r'together still leave to the person doing the install:'),
    blank,
    ...pt(
        '#',
        '/etc/pacman.conf',
        r'multilib has to be switched on for steam and the lib32 '
        r'packages.'),
    ...pt(
        '#',
        'zram-generator.conf, snapper configs',
        r'the packages are listed, their configuration is not.'),
    ...pt(
        '#',
        'networking',
        r'no .network file, no resolved settings beyond LLMNR.'),
    ...pt(
        '#',
        'users and groups',
        r'install.sh adds groups but does not create the user.'),
    ...pt(
        '#',
        'python',
        r'tools/generate-wallpaper.py and home/.local/bin/'
        r'intl-speedtest need Python, which is in neither list. It '
        r'arrives as somebody else’s dependency.'),
    ...pt(
        '#',
        'rust and the android SDK',
        r'.bashrc sources ~/.cargo/env and adds an Android SDK '
        r'directory to PATH, but there is no rust, rustup or '
        r'android-tools here. Both are evidently installed by '
        r'their own installers (an inference from the paths).'),

    ...sec('using the list'),
    ...para(
        '#',
        r'Nothing in the repo consumes this file, so here is my '
        r'reading of how it fits, not a documented procedure. '
        r'Enable multilib, then feed the names to pacman with '
        r'“sudo pacman -S --needed -” reading standard input. '
        r'--needed makes a rerun skip what is current. Then build '
        r'yay by hand, because it is itself in the AUR list, and '
        r'use it for aur.txt. Only after that is it time for '
        r'./install.sh --system.'),
    blank,
    ...para(
        '#',
        r'The order matters because of the dependencies between the '
        r'two lists. The AUR driver needs dkms and linux-headers '
        r'from this file; this file’s egl-* libraries only make '
        r'sense once the driver is in; and install.sh enables a '
        r'service (scx_loader.service) whose package is here.'),

    ...sec('limits, and what is next'),
    ...pt(
        '#',
        'not consumed',
        r'a script that fed the two files to pacman and yay, with a '
        r'multilib check up front, would close the loop between the '
        r'lists and install.sh.'),
    ...pt(
        '#',
        'no why',
        r'the format has no room for a comment. For tailscale, '
        r'packagekit, udisks2, discord, libxslt and '
        r'xcb-util-keysyms nothing else in the repo says why they '
        r'are there. A sidecar file, or a comment convention that '
        r'the consuming command tolerates, would carry the reason '
        r'next to the name.'),
    ...pt(
        '#',
        'frozen',
        r'the file has not changed since the initial commit, '
        r'though the desktop gained a cursor theme, a WinApps '
        r'setup and several widgets since. It is a snapshot from '
        r'2026-09-19, not a maintained record.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
