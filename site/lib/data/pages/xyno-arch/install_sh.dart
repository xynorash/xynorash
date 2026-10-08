import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/install.sh',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'install.sh — the installer that refuses to destroy'),
    cm('#', 'link the home, copy the system, print the dangerous part'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'the only code in the repo that touches the live machine'),
    kv('language', 'bash, set -euo pipefail'),
    kv('size', '84 lines, 4 commits, 63 lines at birth'),
    kv('modes', 'default: link home/  ·  --system: also install and activate /etc'),
    kv('checked here', 'default mode against a throw-away HOME; --system read, not run'),

    ...sec('why this file exists'),
    ...para(
        '#',
        r'Everything else in xyno-arch is data: config files, lists, '
        r'a script or two. This is the one file that turns that '
        r'data into a running machine, which makes it the one place '
        r'where a mistake can destroy something the owner cares '
        r'about. Three rules are visible in the code, and the rest '
        r'of the file follows from them.'),
    blank,
    ...pt(
        '#',
        'never destroy',
        r'an existing file is moved aside to <file>.bak-<timestamp> '
        r'before anything is linked over it. The header comment says '
        r'it in one line: “never overwritten”.'),
    ...pt(
        '#',
        'two risk classes',
        r'user files (home/) are symlinked and need no privileges. '
        r'System files (system/) are copied with sudo and only when '
        r'--system is passed. Different blast radius, different '
        r'ceremony.'),
    ...pt(
        '#',
        'print, do not install, what can stop a boot',
        r'five files that decide whether the machine starts or lets '
        r'anyone log in are listed at the end for the owner to diff '
        r'by hand. Automation stops where a mistake costs a rescue '
        r'USB.'),

    ...sec('the contract, in the header comment'),
    ...code('bash', 'install.sh · header and setup', r'''
#!/usr/bin/env bash
# xyno-arch installer.
#
#   ./install.sh            symlink the home configs
#   ./install.sh --system   also install /etc + /boot files (needs sudo)
#
# Existing files are moved aside to <file>.bak-<timestamp>, never overwritten.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
stamp=$(date +%Y%m%d%H%M%S)
system=0
[[ ${1:-} == --system ]] && system=1'''),
    ...para(
        '#',
        r'Four small decisions live in those lines. The repo path is '
        r'derived from BASH_SOURCE, not from the current directory, '
        r'so the script can be started from anywhere. It is turned '
        r'into an absolute path with cd and pwd, and that matters '
        r'later: every symlink the script makes points at '
        r'$repo/home/..., and a relative target would dangle the '
        r'moment the link is read from another directory.'),
    blank,
    ...para(
        '#',
        r'The timestamp is computed once, before any work, so every '
        r'backup from one run shares a suffix. After a run, a find '
        r'over the home directory for names ending in the printed '
        r'stamp lists exactly what that run displaced, and '
        r'nothing else.'),
    blank,
    ...para(
        '#',
        r'The flag parser is one line. The ${1:-} default is there '
        r'because of set -u; without it, running with no argument '
        r'would abort with an unbound variable. And because the '
        r'test sits in front of an &&, a false result does not '
        r'trip set -e either. Both facts were exercised when the '
        r'script ran with no argument in the experiment below.'),

    ...sec('backup(): three cases, one rule'),
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
    ...para(
        '#',
        r'The function distinguishes what is at the destination. A '
        r'real file the owner made (exists, and is not a link) is '
        r'renamed, never deleted. A symlink is removed without a '
        r'backup, because in the normal case it is the link a '
        r'previous run created and replacing it is the whole point. '
        r'Nothing there means nothing to do, so there is no third '
        r'branch.'),
    blank,
    ...para(
        '#',
        r'The order of the tests matters. -e follows links, so a '
        r'link to a real file passes -e; the "! -L" in the first '
        r'branch is what keeps it out of the rename path and sends '
        r'it to the second. A dangling link fails -e entirely and '
        r'is caught by the -L test.'),
    blank,
    ...para(
        '#',
        r'That second branch is also what makes the script '
        r'idempotent, and I checked it rather than assume it. In a '
        r'throw-away HOME that already held an old .bashrc and an '
        r'old .config/hypr/hyprland.lua, the first run moved both '
        r'aside with their content intact (the stamp in that run '
        r'was 20261008121042) and linked everything. The second run '
        r'printed no "kept old" line at all: it only refreshed '
        r'links.'),
    blank,
    ...para(
        '#',
        r'The cost of the design is in the same branch. A symlink '
        r'that someone else made, pointing somewhere else, is '
        r'deleted without a trace. For a script meant for the '
        r'owner’s own machine that is a fair trade; for a tool '
        r'meant for strangers it would deserve a backup too.'),

    ...sec('the linking loop'),
    ...code('bash', 'install.sh · link every file under home/', r'''
echo "linking home configs"
while IFS= read -r -d '' src; do
  rel=${src#"$repo"/home/}
  dst=$HOME/$rel
  mkdir -p "$(dirname "$dst")"
  backup "$dst"
  ln -s "$src" "$dst"
  echo "  $dst -> $src"
done < <(find "$repo/home" -type f -print0)'''),
    ...pt(
        '#',
        'find -print0 and read -d ""',
        r'file names are passed NUL-delimited, so spaces, newlines '
        r'or backslashes in a name cannot split or mangle it. IFS= '
        r'keeps leading and trailing blanks, -r keeps backslashes.'),
    ...pt(
        '#',
        'process substitution, not a pipe',
        r'the loop is fed with < <(...) so it runs in the current '
        r'shell. With "find | while" it would run in a subshell and '
        r'any variable set inside would be lost. Nothing is set '
        r'inside today; the habit is the point.'),
    ...pt(
        '#',
        'the quoted prefix',
        r'${src#"$repo"/home/} strips the repo prefix. Quoting '
        r'$repo inside the pattern makes any glob characters in the '
        r'checkout path literal.'),
    ...pt(
        '#',
        'the echo is a manifest',
        r'each line prints "destination -> source". In the '
        r'experiment run that was 97 links, one for every file '
        r'under home/. Sixteen are hand-written configs and 81 '
        r'belong to the DotClick cursor theme.'),
    blank,
    ...para(
        '#',
        r'Links are made per file, never per directory. That has '
        r'three consequences worth knowing, and the first was '
        r'confirmed in the experiment: ~/.config/hypr ended up a '
        r'real directory holding a link to hyprland.lua, not a link '
        r'to a directory in the repo.'),
    blank,
    ...pt(
        '#',
        'generated files stay out of the repo',
        r'noctalia writes files such as hypr/noctalia.lua. Because '
        r'the directory is a real one, those files land beside the '
        r'links in $HOME rather than inside the checkout.'),
    ...pt(
        '#',
        'find -type f skips symlinks',
        r'a symlink stored inside home/ would never be installed. '
        r'The cursor theme has 80 names for 15 distinct images; '
        r'git stores them as 80 regular files (no tracked entry '
        r'has symlink mode), so they all install. Whether that is '
        r'by design or just how the conversion tool wrote them, the '
        r'repo does not say.'),
    ...pt(
        '#',
        'rename-on-save replaces a link',
        r'a program that rewrites its config by writing a temp file '
        r'and renaming it over the original swaps the symlink for a '
        r'plain file, and the repo copy quietly stops being the '
        r'source. General behaviour of such programs, not something '
        r'seen in this repo.'),

    ...sec('the wallpaper is copied, not linked'),
    ...code('bash', 'install.sh · the wallpaper', r'''
echo "installing the wallpaper"
mkdir -p "$HOME/Pictures/Wallpapers"
cp -n "$repo/wallpapers/"*.png "$HOME/Pictures/Wallpapers/" 2>/dev/null || true'''),
    ...para(
        '#',
        r'The reason it is a copy into a conventional folder is '
        r'visible in noctalia’s config: the wallpaper entry points '
        r'at /home/xynorash/Pictures/Wallpapers/starry-night-tokyo.png, '
        r'which is exactly where this line puts it. The image is not '
        r'a dotfile, so it lives in wallpapers/, not under home/.'),
    blank,
    ...para(
        '#',
        r'The tail of the line is defensive. Under set -e a failing '
        r'cp would abort the whole install, so errors are swallowed. '
        r'The error cases are real: if wallpapers/ held no PNG the '
        r'glob would stay literal and cp would fail. And cp -n has '
        r'changed meaning across coreutils releases; in the 9.4 '
        r'build used for the experiment it prints “behavior of -n '
        r'is non-portable and may change in future; use '
        r'--update=none instead” and exits 0. The 2>/dev/null hides '
        r'that warning.'),
    blank,
    ...para(
        '#',
        r'There is a trap in the -n. It never overwrites, so '
        r'regenerating the image with tools/generate-wallpaper.py '
        r'and running the installer again does not refresh the copy '
        r'in ~/Pictures/Wallpapers. I confirmed it: a pre-existing '
        r'file there kept its old content after cp -n. To change '
        r'the wallpaper you copy it by hand or delete the old file '
        r'first.'),

    ...sec('--system: copy, do not link'),
    ...code('bash', 'install.sh · the nine system files', r'''
if (( system )); then
  echo "installing system files (sudo)"
  for rel in etc/sysctl.d/99-zram.conf \
             etc/sysctl.d/99-network-tuning.conf \
             etc/security/limits.d/99-realtime-audio.conf \
             etc/modules-load.d/ntsync.conf \
             etc/scx_loader.toml \
             etc/greetd/config.toml \
             etc/systemd/system/nvidia-powerlimit.service \
             etc/systemd/logind.conf.d/10-power-key.conf \
             etc/systemd/resolved.conf.d/10-no-llmnr.conf; do
    sudo install -Dm644 "$repo/system/$rel" "/$rel"
    echo "  /$rel"
  done'''),
    ...para(
        '#',
        r'The word that changes between the two halves of the script '
        r'is install. install -Dm644 creates any missing parent '
        r'directories (-D), sets mode 644, and, running under sudo, '
        r'leaves the file owned by root. It copies. The files in '
        r'/etc are therefore not tied to the checkout: moving or '
        r'deleting ~/xyno-arch does not break the system, and '
        r'editing a file in the repo does nothing until the '
        r'installer runs again.'),
    blank,
    ...para(
        '#',
        r'The repo never states why these are copies. The usual '
        r'reason is that boot-time and service reads (greetd runs '
        r'tuigreet as the unprivileged user greeter) should not '
        r'depend on a home directory being mounted or traversable. '
        r'That is the conventional argument, offered as inference.'),
    blank,
    ...para(
        '#',
        r'The path argument doubles as the mirror rule. The repo '
        r'directory system/etc/sysctl.d/ maps to /etc/sysctl.d/ '
        r'with the same relative path, so the tree under system/ '
        r'reads as an overlay on /. The list itself has grown only '
        r'one line at a time:'),
    blank,
    ...pt(
        '#',
        '2026-09-19, birth',
        r'seven entries: the two sysctl files, realtime limits, '
        r'ntsync, scx_loader, greetd and the nvidia power-limit '
        r'unit.'),
    ...pt(
        '#',
        '2026-09-21, commit 0dc7770',
        r'the logind drop-in that makes the power key a no-op for '
        r'logind so the compositor can bind it.'),
    ...pt(
        '#',
        '2026-10-08, commit 901611a',
        r'the resolved drop-in that turns LLMNR off, in the same '
        r'commit as the notsent_lowat network change.'),

    ...sec('activation: what the installer does after copying'),
    ...code('bash', 'install.sh · activate', r'''
  sudo sysctl --system >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl reload systemd-logind
  sudo systemctl enable --now scx_loader.service nvidia-powerlimit.service'''),
    ...pt(
        '#',
        'sysctl --system',
        r'reloads every sysctl.d file, so the zram and network '
        r'tuning is live without a reboot. Its output is discarded '
        r'because it lists every file it reads.'),
    ...pt(
        '#',
        'daemon-reload',
        r'systemd must re-read unit files before it knows '
        r'nvidia-powerlimit.service exists.'),
    ...pt(
        '#',
        'reload systemd-logind',
        r'added in the same commit as the power-key drop-in, so '
        r'HandlePowerKey=ignore applies on the spot.'),
    ...pt(
        '#',
        'enable --now',
        r'enable so it survives reboots, --now so it runs at once. '
        r'scx_loader.service belongs to the scx packages listed in '
        r'packages/pacman.txt (scx-scheds and scx-tools); the NVIDIA '
        r'unit is the repo’s own and carries '
        r'ConditionPathExists=/usr/bin/nvidia-smi, so on a machine '
        r'without the driver it is skipped instead of failing.'),
    blank,
    ...para(
        '#',
        r'Three of the nine files get no activation here, and '
        r'reading the script that is the honest list of gaps. '
        r'ntsync.conf is read at boot, so the module is not loaded '
        r'until the next start. limits.d is applied through PAM at '
        r'the next login. And there is no restart of '
        r'systemd-resolved after 10-no-llmnr.conf was added, so '
        r'LLMNR stays on until resolved restarts or the machine '
        r'reboots. That last point is my reading of the script; I '
        r'did not run --system.'),

    ...sec('the settings that cannot be files'),
    ...code('bash', 'install.sh · groups, hosts, services', r'''
  echo "group membership"
  for g in gamemode seat docker; do
    getent group "$g" >/dev/null && sudo usermod -aG "$g" "$USER" && echo "  $USER -> $g"
  done

  echo "hostname in /etc/hosts"
  if ! grep -q '127.0.1.1' /etc/hosts; then
    sudo sed -i "/^127.0.0.1[[:space:]]*localhost/a 127.0.1.1        $(hostname).localdomain    $(hostname)" /etc/hosts
    echo "  added 127.0.1.1 $(hostname)"
  fi

  echo "services this setup does not want running"
  for u in cockpit.socket systemd-networkd-wait-online.service; do
    systemctl is-enabled "$u" &>/dev/null && sudo systemctl disable --now "$u" && echo "  disabled $u"
  done'''),
    ...para(
        '#',
        r'Some state is not a file in /etc that can be copied. It is '
        r'a group entry, a line inside an existing file, or the '
        r'enabled flag of a service. These three blocks arrived in '
        r'commit 208de62, six minutes after the first commit, under '
        r'the message “Track everything needed to reproduce the '
        r'desktop”. The point of that commit was that a fresh '
        r'machine should come up the same instead of falling back '
        r'to defaults.'),
    blank,
    ...pt(
        '#',
        'groups',
        r'getent group "$g" is the existence check, so a group whose '
        r'package is not installed is skipped silently. The pattern '
        r'"test && action && echo" would normally worry me under '
        r'set -e; I ran a tiny loop with a nonexistent group and the '
        r'shell survived, because the failing test is not the last '
        r'command in the AND list. The three groups line up with '
        r'the rest of the repo: gamemode.ini asks for renice=10, '
        r'seatd is in the package list, and docker is installed.'),
    ...pt(
        '#',
        'docker is root-equivalent',
        r'membership of the docker group lets a user start a '
        r'container that mounts the host filesystem. The installer '
        r'adds it without comment; on a single-user gaming desktop '
        r'that is a choice, not an accident, but it is a choice.'),
    ...pt(
        '#',
        'the hosts line',
        r'guarded by grep, so a second run adds nothing. The sed '
        r'appends after the "127.0.0.1 localhost" line, and because '
        r'the whole sed program is double-quoted, $(hostname) '
        r'expands in the invoking shell before sudo runs. The guard '
        r'is coarse: any line containing 127.0.1.1 (the dots are '
        r'unescaped, so even near-matches count) suppresses the '
        r'edit. The repo does not record which symptom prompted it.'),
    ...pt(
        '#',
        'services',
        r'is-enabled makes the loop quiet on a second run. '
        r'systemd-networkd-wait-online.service holds boot until the '
        r'network is “online”, which is dead time on a desktop that '
        r'does not need the network to finish starting. '
        r'cockpit.socket is a web admin listener; the cockpit '
        r'package is still in packages/pacman.txt, so the tool is '
        r'kept installed and simply not listening.'),

    ...sec('what it will not do, on purpose'),
    ...code('bash', 'install.sh · the part it prints instead', r'''
  echo
  echo "not installed automatically, they replace files the system owns:"
  echo "  system/etc/pam.d/greetd        adds gnome-keyring unlock at login"
  echo "  system/etc/mkinitcpio.d/linux.preset  builds the fallback UKI as well"
  echo "  system/etc/mkinitcpio.conf     nvidia modules in MODULES, kms hook removed"
  echo "  system/etc/kernel/cmdline      kernel command line baked into the UKI"
  echo "  system/boot/loader/loader.conf systemd-boot (editor disabled, default pinned)"
  echo "compare them by hand, then run: sudo mkinitcpio -P"'''),
    ...para(
        '#',
        r'Nine files are installed, five are printed, and the two '
        r'sets together are exactly the 14 files under system/. Each '
        r'printed file is one whose mistake is expensive, and the '
        r'costs are different in kind:'),
    blank,
    ...pt(
        '#',
        'mkinitcpio.conf',
        r'carries the four NVIDIA modules (nvidia, nvidia_modeset, '
        r'nvidia_uvm, nvidia_drm) in MODULES and a HOOKS list with '
        r'no kms. A wrong initramfs is a machine that does not '
        r'reach userspace.'),
    ...pt(
        '#',
        'kernel/cmdline',
        r'names the root filesystem by PARTUUID. That value belongs '
        r'to one disk. Copied onto another machine it produces a '
        r'kernel that cannot find its root, which is the clearest '
        r'reason in the repo for never automating this file.'),
    ...pt(
        '#',
        'loader.conf and linux.preset',
        r'pin the default boot entry (arch-linux.efi) and build the '
        r'unified kernel images, including a fallback image, under '
        r'/boot/EFI/Linux. They decide what the firmware can start.'),
    ...pt(
        '#',
        'pam.d/greetd',
        r'is the login stack for the greeter. A bad PAM file means '
        r'nobody can log in, at the point where the machine is '
        r'otherwise healthy.'),
    blank,
    ...para(
        '#',
        r'The last echo names the manual follow-up, sudo mkinitcpio '
        r'-P, which rebuilds both UKIs after the owner has merged '
        r'the files. Note the drift this left behind: the README '
        r'tells readers three files are not installed (mkinitcpio.conf, '
        r'kernel/cmdline, loader.conf). The installer prints five. '
        r'The two extra, pam.d/greetd and mkinitcpio.d/linux.preset, '
        r'were added to the installer in 208de62 and never made it '
        r'into the README. The script is the authority.'),

    ...sec('what I ran, and what I did not'),
    ...pt(
        '#',
        'run',
        r'the default mode, against a throw-away HOME in a scratch '
        r'directory, with a pre-seeded .bashrc and hyprland.lua. '
        r'Checked: 97 links, backups with intact content, a clean '
        r'second run, a real ~/.config/hypr directory, and the '
        r'wallpaper copy not being refreshed.'),
    ...pt(
        '#',
        'syntax',
        r'bash -n passes. No shellcheck was available.'),
    ...pt(
        '#',
        'not run',
        r'--system. It needs sudo and would change the host, and '
        r'the statements above about its activation steps are '
        r'read from the code, not observed.'),

    ...sec('history'),
    ...pt(
        '#',
        'd552dfd, 2026-09-19 18:28',
        r'63 lines: the home loop, the wallpaper, seven system '
        r'files, sysctl, daemon-reload, enable, and a three-line '
        r'“not installed” list.'),
    ...pt(
        '#',
        '208de62, 2026-09-19 18:34',
        r'+18 lines: groups, hostname, services, and two more '
        r'entries in the printed list.'),
    ...pt(
        '#',
        '0dc7770, 2026-09-21 01:30',
        r'the logind drop-in and systemd-logind reload.'),
    ...pt(
        '#',
        '901611a, 2026-10-08 11:53',
        r'the resolved drop-in.'),
    blank,
    ...para(
        '#',
        r'The pattern since day one is that the installer changes '
        r'only when the repo gains a system file. It has become a '
        r'manifest with a few activation commands attached, which '
        r'is a healthy shape: the logic that could go wrong stayed '
        r'small and stable while the system grew from seven files '
        r'to fourteen.'),

    ...sec('limits, and what is next'),
    ...pt(
        '#',
        'no package step',
        r'packages/pacman.txt and packages/aur.txt exist but the '
        r'script never reads them. A bare Arch install gets the '
        r'configs but not the programs they configure.'),
    ...pt(
        '#',
        'one username',
        r'the script uses $HOME and $USER correctly, but '
        r'hyprland.lua and noctalia/config.toml contain '
        r'/home/xynorash paths (the repo README says so). Another '
        r'username would link fine and then break at runtime.'),
    ...pt(
        '#',
        'no way back',
        r'there is no uninstall. Undoing means deleting the links '
        r'and renaming the .bak-<stamp> files by hand.'),
    ...pt(
        '#',
        'argument handling',
        r'only the first argument is read, and an unknown one such '
        r'as a mistyped --sytem is ignored silently, which runs the '
        r'home-only install and reports success.'),
    ...pt(
        '#',
        'no dry run, no diff',
        r'the five risky files are listed but not compared. A '
        r'--diff that ran diff against the live copies would turn '
        r'“compare them by hand” into one command.'),
    ...pt(
        '#',
        'partial state',
        r'home is linked before sudo is ever asked for. Declining '
        r'the password leaves a machine with links and no system '
        r'files, with nothing in the output to say so.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
