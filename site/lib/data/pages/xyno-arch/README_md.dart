import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/README.md',
  summary: 'a reproducible Hyprland desktop, tuned for gaming',
  repo: 'xyno-arch',
  fallbackStars: 0,
  fallbackPushed: '2026-10-08',
  lines: [
    heading('# xyno-arch'),
    blank,
    ...text('A git repository that is a computer. xyno-arch holds '
        'everything needed to rebuild one Arch Linux desktop: a '
        'Hyprland session configured in Lua, the noctalia shell for '
        'the bar, launcher, notifications and lock screen, one '
        'Tokyo Night palette pushed to every program from a single '
        'place, system tuning for a Ryzen 7 5800X with a GTX 980, '
        'and a gaming layer that switches itself on when a Steam '
        'game opens a window. There is no framework. There is a '
        'directory that mirrors the home directory, a directory that mirrors /, '
        'two package lists, a wallpaper generator and an 84-line '
        'installer whose first rule is that it never overwrites '
        'anything.'),
    blank,
    kv('what', 'dotfiles and system config for one Arch desktop'),
    kv('compositor', 'Hyprland, Lua config (hyprlang is deprecated)'),
    kv('shell', 'noctalia: bar, launcher, notifications, lock, OSD'),
    kv('hardware', 'Ryzen 7 5800X, GTX 980 (4 GB), 1080p @ 60 Hz'),
    kv('history', '22 commits, 2026-09-19 to 2026-10-08, on 4 days'),
    kv('files', '118 tracked: 97 in home/, 14 in system/'),
    kv('installer', 'install.sh, 84 lines, link / copy / print'),
    kv('tests', 'none; the check is living on it'),

    ...sec('the problem, and why it is interesting'),
    ...text('A desktop is hundreds of small decisions spread across '
        'dozens of places, almost all of them outside any '
        'repository: a sysctl value in /etc, a line in a boot '
        'entry, a group membership, a window rule, a package you '
        'installed once and forgot. Reinstall and you remember '
        'perhaps half. The failure is quiet. The machine comes up, '
        'it works, and a month later you notice that games '
        'stutter because a power limit is back at its default, or '
        'that a click on a notification goes nowhere.'),
    blank,
    ...text('So the goal is stated in the commit that closed the '
        'first big gap, 208de62, “Track everything needed to '
        'reproduce the desktop”: “so a fresh machine comes up '
        'identical instead of falling back to defaults”. That '
        'sentence is the specification. Three questions follow '
        'from it, and the repository is organised around the '
        'answers.'),
    ...bullet('what is safe to automate?',
        'user files can be linked and undone. Files that decide '
        'whether the machine boots, or whether anyone can log in, '
        'cannot. The installer has three behaviours for the three '
        'kinds of file, and the line between them is the most '
        'important design decision in the repo.'),
    ...bullet('how do you make gaming tuning invisible?',
        'the Steam launch-option approach needs a change for every '
        'game and is invisible when forgotten. Here the compositor '
        'watches for game windows and attaches GameMode by itself, '
        'and desktop tearing stays off while Steam windows get it.'),
    ...bullet('how do generated and tracked files coexist?',
        'noctalia writes some of its own files. The repo tracks the '
        'ones that define the look and ignores the ones the shell '
        'regenerates, so that a GUI change does not fight a commit.'),

    ...sec('the setup'),
    ...text('This is the table from the README, restated. Every row '
        'has a file in the repo that configures it.'),
    ...bullet('Compositor', 'Hyprland, Lua config, dwindle layout '
        '(home/.config/hypr/hyprland.lua).'),
    ...bullet('Shell', 'noctalia (home/.config/noctalia/config.toml).'),
    ...bullet('Terminal', 'Ghostty (home/.config/ghostty/).'),
    ...bullet('File manager', 'Yazi, started by Super+E; its theme is '
        'written by noctalia and ignored by git.'),
    ...bullet('Login', 'greetd with tuigreet and a matrix background '
        '(system/etc/greetd/config.toml).'),
    ...bullet('Boot', 'systemd-boot loading a Unified Kernel Image '
        '(system/boot/loader/loader.conf, system/etc/mkinitcpio.d/'
        'linux.preset).'),
    ...bullet('Filesystem', 'btrfs with snapper and zram swap '
        '(system/etc/kernel/cmdline names the subvolume).'),
    ...bullet('Theme and font', 'Tokyo Night and JetBrainsMono Nerd '
        'Font, pushed by noctalia templates to Hyprland, Ghostty, '
        'GTK and Yazi.'),
    blank,
    ...text('Parts of the look and some of the tuning are '
        'borrowed from Omarchy, another Arch-based setup. The '
        'repo says so in several places: hyprland.lua opens with '
        '“Omarchy Quattro-style”, the network sysctl file is '
        '“carried over from Omarchy’s 99-omarchy-sysctl.conf”, and '
        'commit b22bf50 is titled “SUPER+F maximizes the window '
        '(Omarchy full width)”. home/.local/bin/intl-speedtest even '
        'suggests running it from an Omarchy live USB to compare.'),

    ...sec('how the session comes up'),
    plain('  firmware'),
    plain('    -> systemd-boot, default entry pinned (loader.conf)'),
    plain('    -> Unified Kernel Image: cmdline + initramfs in one file'),
    plain('    -> greetd runs tuigreet on vt 1'),
    plain('    -> tuigreet starts: start-hyprland'),
    plain('    -> Hyprland reads hyprland.lua'),
    plain('         hl.on("hyprland.start"):'),
    plain('           noctalia            the shell'),
    plain('           notification-focus  D-Bus listener'),
    plain('    -> a steam_app_<id> window opens'),
    plain('         gamemode-attach <pid> -> gamemoded -> governor'),
    blank,
    ...text('The login screen even has a name: the tuigreet greeting '
        'in system/etc/greetd/config.toml is the string “xynogamer”. '
        'The session command is start-hyprland, not an interactive '
        'bash, so the compositor should not read ~/.bashrc; that '
        'fits the absolute paths used for its helper scripts, '
        'though the repo never states the connection.'),

    ...sec('tour of the tree'),
    ...text('The repository has five top-level directories and '
        'three top-level files. The README draws the layout in '
        'five lines:'),
    ...code('text', 'README.md · layout', r'''
home/       dotfiles, symlinked into $HOME
system/     /etc and /boot files, copied by --system
wallpapers/ generated wallpaper (referenced by config.toml)
tools/      wallpaper generator
packages/   explicit pacman and AUR package lists'''),
    ...text('Each directory exists because its contents have a '
        'different way of reaching the machine, and a different '
        'cost if they go wrong.'),
    ...sec('home/ (97 files, linked)'),
    ...text('A mirror of the home directory. Whatever path a file has under '
        'home/ is the path it has in your home directory, so there '
        'is no manifest to maintain: install.sh walks the tree with '
        'find and links each file. Adding a config means dropping '
        'the file in the right place. What is there:'),
    ...bullet('.config/hypr/', 'hyprland.lua (243 lines, the '
        'compositor), keybinds.sh (the cheatsheet printer, bound to '
        'Super+Shift+/) and xdph.conf (screen sharing).'),
    ...bullet('.config/noctalia/config.toml', '214 lines: palette, bar '
        'geometry and widgets, wallpaper, lock screen. Tracked on '
        'purpose, see below.'),
    ...bullet('.config/ (the rest)', 'ghostty/ (terminal and theme), '
        'gtk-3.0/ and gtk-4.0/ (GTK settings), MangoHud/ (the '
        'in-game overlay), xdg-desktop-portal/ (portal selection).'),
    ...bullet('.config/gamemode.ini', 'what GameMode does when a game '
        'is running.'),
    ...bullet('.local/bin/', 'three small programs: gamemode-attach, '
        'notification-focus, intl-speedtest.'),
    ...bullet('.local/share/', 'the Steam download settings and the '
        'DotClick cursor theme, which alone is 81 of the 97 files.'),
    ...bullet('.bashrc', 'the shell, nearly stock.'),
    ...sec('system/ (14 files, copied or printed)'),
    ...text('A mirror of / for the parts under /etc and /boot. These '
        'files are root-owned, read early in boot, and some of them '
        'can stop the machine from starting. They are copied with '
        'sudo install -Dm644, not linked. Why copy instead of link '
        'is my reading, not a stated reason: a root-owned file that '
        'is a symlink into a user’s clone is only as safe as that '
        'clone, and a boot file that points into /home may not be '
        'readable when it is needed.'),
    ...bullet('installed by --system (9)', 'sysctl.d/99-zram.conf, '
        'sysctl.d/99-network-tuning.conf, security/limits.d/99-'
        'realtime-audio.conf, modules-load.d/ntsync.conf, '
        'scx_loader.toml, greetd/config.toml, systemd/system/'
        'nvidia-powerlimit.service, logind.conf.d/10-power-key.conf, '
        'resolved.conf.d/10-no-llmnr.conf.'),
    ...bullet('printed, never installed (5)', 'pam.d/greetd, '
        'mkinitcpio.d/linux.preset, mkinitcpio.conf, kernel/cmdline '
        'and boot/loader/loader.conf. They replace files the system '
        'owns and decide whether you can boot or log in.'),
    ...sec('packages/ (2 files, documentation)'),
    ...text('pacman.txt lists 67 packages, aur.txt lists 9. They '
        'are the explicit installs, bare names, sorted. install.sh '
        'never reads them: I searched the script for pacman, yay '
        'and the directory name and found none. They record the '
        'machine and do not build it. The nvidia-580xx choice, the '
        'reason a GTX 980 is the centre of so many comments, is in '
        'aur.txt.'),
    ...sec('tools/ and wallpapers/'),
    ...text('tools/generate-wallpaper.py is a standard-library '
        'script that renders a 1920 by 1080 starry sky in the Tokyo '
        'Night palette from a fixed seed, 7749. Its output is '
        'wallpapers/starry-night-tokyo.png, 1,856,346 bytes, which '
        'is committed so that nobody needs Python to get the same '
        'picture. The installer copies it to ~/Pictures/Wallpapers '
        'with cp -n, so an existing file is never replaced, and '
        'noctalia’s config points at that absolute path. The '
        'generator lives apart from the picture because one is '
        'source and one is a build product that is worth keeping.'),
    ...sec('the root'),
    ...bullet('install.sh', 'the only code that touches the live '
        'machine.'),
    ...bullet('README.md', 'this file; last edited on the first day.'),
    ...bullet('.gitignore', 'six lines that keep noctalia’s '
        'generated files and *.bak backups out of git.'),

    ...sec('link, copy, print: the installer’s three behaviours'),
    ...text('The separation of home/ from system/ would be only '
        'folder structure if the installer did not honour it. It '
        'does, and it honours it three ways.'),
    ...bullet('link, with a safety net',
        'every file in home/ becomes a symlink. If something '
        'already sits at that path, it is moved to '
        '<file>.bak-<timestamp>. The timestamp is taken once, so '
        'one run leaves one suffix.'),
    ...bullet('copy, only on request',
        'with --system the nine safe system files are copied with '
        'sudo, sysctl is reloaded, systemd is told, and the '
        'scheduler and power-limit units are enabled.'),
    ...bullet('print, never touch',
        'five files are listed with a one-line reason each, and the '
        'script tells you to compare them by hand and then run '
        'sudo mkinitcpio -P.'),
    ...code('bash', 'install.sh · backup()', r'''
backup() {
  local target=$1
  if [[ -e $target && ! -L $target ]]; then
    mv "$target" "$target.bak-$stamp"
    echo "  kept old $target as $target.bak-$stamp"
  elif [[ -L $target ]]; then
    rm "$target"
  fi
}'''),
    ...text('A real file is moved aside. A symlink is removed with '
        'no backup and relinked, which makes a second run '
        'idempotent. It also means a symlink you made by hand at one '
        'of those paths is replaced; only regular files are kept. '
        'The .gitignore patterns *.bak and *.bak-* are the other '
        'half of the promise: the backups the installer creates '
        'cannot be committed by accident.'),
    ...code('bash', 'install.sh · what it will not install', r'''
  echo "not installed automatically, they replace files the system owns:"
  echo "  system/etc/pam.d/greetd        adds gnome-keyring unlock at login"
  echo "  system/etc/mkinitcpio.d/linux.preset  builds the fallback UKI as well"
  echo "  system/etc/mkinitcpio.conf     nvidia modules in MODULES, kms hook removed"
  echo "  system/etc/kernel/cmdline      kernel command line baked into the UKI"
  echo "  system/boot/loader/loader.conf systemd-boot (editor disabled, default pinned)"
  echo "compare them by hand, then run: sudo mkinitcpio -P"'''),
    ...text('Every line there is a reason to stop. A wrong PAM stack '
        'locks you out; a wrong initramfs or command line means no '
        'boot. Automation stops where a mistake costs a rescue '
        'USB. This is a design principle worth stealing: separate '
        'what is reversible from what is not, and give each its own '
        'ceremony. The system/ list inside the script is explicit, '
        'not a find, which is why two later commits (0dc7770 and '
        '901611a) each touched install.sh as well as adding a file.'),

    ...sec('the gaming stack, layer by layer'),
    ...text('The README lists six gaming features. Each is a file in '
        'the tree, and each file carries its own reason in a '
        'comment. From the hardware up:'),
    ...bullet('driver: nvidia-580xx-dkms',
        'the GTX 980 is a Maxwell card; packages/aur.txt carries '
        'four 580xx packages, the legacy branch. egl-wayland and '
        'friends are in pacman.txt for Wayland on NVIDIA.'),
    ...bullet('power: 225 W',
        'a oneshot unit raises the limit from the default 180 W.'),
    ...bullet('scheduler: scx_lavd in Gaming mode',
        'sched_ext, loaded at boot by scx_loader.'),
    ...bullet('kernel: ntsync',
        'loaded as a module for Wine builds that can use it.'),
    ...bullet('memory: zram tuning',
        'swappiness 180 and related values; swapping is cheap when '
        'swap is compressed RAM.'),
    ...bullet('network: BBR with fq, bigger buffers, a capped unsent '
        'queue', 'for a long path; Steam download settings sit '
        'beside it.'),
    ...bullet('compositor: direct scanout and tearing',
        'tearing is allowed globally but only Steam windows opt in '
        'with an immediate rule; the desktop stays tear-free.'),
    ...bullet('GameMode: automatic',
        'a window.open hook plus gamemode-attach plus gamemode.ini.'),
    ...bullet('overlay: MangoHud',
        'with VRAM on screen, because 4 GB is the number to watch.'),
    blank,
    ...text('Two of those comments, quoted, show the standard of '
        'explanation that the repo sets for itself:'),
    ...code('ini', 'system/etc/systemd/system/nvidia-powerlimit.service', r'''
# Default is 180 W; the board allows up to 225 W. More headroom lets the GPU
# hold its boost clock under sustained game load instead of power-throttling.
ExecStart=/usr/bin/nvidia-smi -pm 1
ExecStart=/usr/bin/nvidia-smi -pl 225'''),
    ...code('ini', 'system/boot/loader/loader.conf', r'''
# SECURITY: without this, anyone at the keyboard can press 'e' at the menu,
# append init=/bin/bash to the kernel command line and get a root shell with
# no password. Your disk is not encrypted, so this is the only thing standing
# between physical access and root.
editor       no'''),
    ...text('Neither says what the setting is; both say what it '
        'is for and what happens without it. The files in the '
        'pages for each of these carry the detail.'),

    ...sec('generated files and tracked files'),
    ...text('noctalia writes some of its own state. The .gitignore '
        'names what the shell regenerates: noctalia.lua under '
        'hypr/, settings.toml under noctalia/, and the Yazi theme '
        'directory. Everything that defines the look is in '
        'config.toml, which the README calls tracked on purpose: '
        '“palette, bar geometry, wallpaper, lock screen, widgets”. '
        'Per-monitor widget placement is the one thing left '
        'untracked.'),
    blank,
    ...text('The second commit is the history of this decision. '
        'Its body says it moved the wallpaper, bar geometry and '
        'lock screen “out of noctalia’s state file and into the '
        'tracked config”. Before that move a fresh machine would '
        'have fallen back to defaults for those three, which is '
        'the failure the commit message names.'),

    ...sec('timeline'),
    ...text('Twenty-two commits in twenty days, on four distinct '
        'days. All times are +0300.'),
    ...bullet('2026-09-19 18:28  d552dfd',
        'initial commit: 29 files and 1,147 lines in one go. '
        'Hyprland Lua config, noctalia, Ghostty, greetd, the '
        'whole gaming layer, sysctl and boot files, the installer, '
        'the wallpaper generator.'),
    ...bullet('2026-09-19 18:34  208de62',
        'six minutes later: “Track everything needed to reproduce '
        'the desktop”. Wallpaper, bar and lock screen move into '
        'tracked config; .bashrc, the Steam settings, the greetd '
        'PAM stack and the mkinitcpio preset are added; the '
        'installer learns group membership, the hosts entry and '
        'which services to disable.'),
    ...bullet('2026-09-19 19:28  aebd41e',
        'the first bug fix: gamemode-attach leaves '
        'self-registered games alone.'),
    ...bullet('2026-09-21  15 commits',
        'the daily-driver day. Power button opens the session '
        'menu (01:30). Nine bar commits make the bar interactive: '
        'CPU, RAM and GPU readouts, live network speed, a second '
        'volume for the microphone, mute on click, media controls, '
        'and widget actions that call noctalia commands. '
        'Notification clicks focus the sender (19:21). Two screen '
        'sharing commits: shared-memory frames so Chrome keeps the '
        'stream on NVIDIA, and a remembered source. A clipboard '
        'bind. Android platform-tools on PATH (22:02).'),
    ...bullet('2026-09-22  b22bf50',
        'Super+F maximizes the window.'),
    ...bullet('2026-10-08 11:53  three commits',
        'the DotClick cursor theme with its GTK settings; float '
        'rules for WinApps RemoteApp windows; network tuning '
        '(a capped unsent TCP queue) and LLMNR turned off. All '
        'three carry the same second as their time.'),
    blank,
    ...text('The shape is typical of a personal system: one big '
        'import, a short burst where the first hour reveals what '
        'the import missed, a very busy day of use, then quiet '
        'until something else needs changing. The first hour is '
        'the instructive part. Two of the first three commits '
        'exist because the repo found its own gaps.'),

    ...sec('how to build and run it'),
    ...code('bash', 'README.md · install', r'''
git clone https://github.com/xynorash/xyno-arch.git ~/xyno-arch
cd ~/xyno-arch
./install.sh            # symlink the home configs
./install.sh --system   # also the /etc bits (sudo)'''),
    ...text('Order of operations for a new machine, as I read the '
        'repo: install the packages (nothing automates it; use the '
        'lists), run ./install.sh, run ./install.sh --system, '
        'diff the five printed files against what is on the '
        'machine and apply the ones you want, run sudo mkinitcpio '
        '-P, log out and back in. The group changes apply at the '
        'next login. To change the wallpaper, edit SEED, W or H in '
        'tools/generate-wallpaper.py and run it; the docstring '
        'gives a one-line recipe.'),
    blank,
    ...text('Before any of that, replace the home directory name. '
        'hyprland.lua and noctalia/config.toml contain absolute '
        'paths under /home/xynorash, and the README says so in its '
        'last note.'),

    ...sec('what I checked, and how'),
    ...bullet('the installer, default mode',
        'run against an empty throw-away HOME that already had a '
        'skeleton .bashrc. It made 97 symlinks, one per tracked '
        'file in home/, moved the old .bashrc to '
        '.bashrc.bak-<timestamp> and pointed the new one at the '
        'clone.'),
    ...bullet('the small programs',
        'gamemode-attach with a stand-in gamemoded, '
        'notification-focus with a real dbus-monitor on a private '
        'bus, intl-speedtest against the live fast.com '
        'endpoints without downloading. The pages for each give '
        'the results.'),
    ...bullet('the cursor theme',
        'all 80 cursor files parsed as Xcursor images: 15 distinct '
        'images, two of them animated.'),
    ...bullet('not run',
        '--system, Hyprland, noctalia, GameMode itself, the boot '
        'files. This sandbox has none of them, so anything about '
        'live behaviour on those rests on the repo’s comments.'),

    ...sec('key numbers'),
    ...bullet('22', 'commits; 2026-09-19 to 2026-10-08.'),
    ...bullet('118', 'tracked files: 97 in home/ (80 of them cursors), '
        '14 in system/, 2 package lists, 1 tool, 1 wallpaper, 3 at '
        'the root.'),
    ...bullet('9 / 5', 'system files installed by --system / printed '
        'for manual review.'),
    ...bullet('67 + 9', 'packages in pacman.txt and aur.txt.'),
    ...bullet('243', 'lines in hyprland.lua; 214 in config.toml; 123 '
        'in keybinds.sh; 84 in install.sh; 150 in the generator.'),
    ...bullet('225 W', 'the GPU power limit, up from 180 W.'),
    ...bullet('~20 s', 'the lag, according to a comment in '
        'hyprland.lua, between a game exiting and the governor '
        'going back to powersave.'),
    ...bullet('0', 'tests and CI. Verification is daily use.'),

    ...sec('honest limits'),
    ...bullet('the README is behind the repo',
        'it was last edited on 2026-09-19, and 20 commits have '
        'followed. Its key table omits Super+F, Super+Ctrl+V '
        '(clipboard) and the power key; it does not mention '
        'notification-focus, the cursor theme, the WinApps rules '
        'or the newest network tuning. Its note on files that are '
        'not installed automatically names three, while the '
        'installer prints five.'),
    ...bullet('a stale comment',
        'the first line of config.toml still says “translated to '
        'noctalia + niri”, though the compositor is Hyprland.'),
    ...bullet('tied to one machine',
        'the GTX 980, the 580xx branch, a PPPoE line with MTU '
        '1492, a monitor on HDMI-A-1 and a disk identified by '
        'PARTUUID in kernel/cmdline. Another machine needs those '
        'edited, and the README says to.'),
    ...bullet('packages are a record, not an input',
        'nothing installs them. The lists also hold things the '
        'installer then switches off (cockpit.socket), and name '
        'tools with no tracked configuration, such as snapper, '
        'tailscale and docker. zram has kernel tuning here but '
        'no tracked zram-generator configuration.'),
    ...bullet('unreproducible shell lines',
        '.bashrc sources ~/.cargo/env and sets an Android SDK '
        'path for software the lists never install.'),
    ...bullet('one open question in the gaming path',
        r'gamemode-attach calls gamemoded -r "$pid" with a space. '
        'For that option the PID must be attached to the flag, so '
        'the call registers the helper process and not the game. '
        'The governor switch still works, as it is global; '
        'renice and ioprio would miss the game. I confirmed the '
        'argument parsing with a test program and read the '
        'daemon source, but I did not run GameMode.'),

    ...sec('what is next'),
    ...text('These are my suggestions after reading, not plans the '
        'repo states:'),
    ...bullet('bring the README up to date',
        'it is the front door and it is 20 commits old.'),
    ...bullet('make the packages executable',
        'a one-line pacman -S --needed fed from pacman.txt, plus '
        'yay for aur.txt, would turn a record into an input.'),
    ...bullet('take the username out',
        'one variable in place of /home/xynorash would remove the '
        'README’s last caveat.'),
    ...bullet('guard the cargo line',
        'a file test in front of the source in .bashrc.'),
    ...bullet('settle the gamemode question',
        'attach the PID to the flag, or measure what is registered '
        'and renice the game.'),
    ...bullet('write down why for the undocumented lines',
        'steam_dev.cfg has no comment and its purpose is known '
        'only from a commit message.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
