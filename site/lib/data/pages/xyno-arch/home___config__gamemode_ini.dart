import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/home/.config/gamemode.ini',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'gamemode.ini — what a running game changes'),
    cm('#', 'two real overrides, four restated defaults, two hooks'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'per-user config for gamemoded, Feral’s GameMode daemon'),
    kv('language', 'ini (inih dialect, ; comments)'),
    kv('size', '13 lines, one commit: d552dfd (2026-09-19)'),
    kv('installed as', '~/.config/gamemode.ini, a symlink made by install.sh'),
    kv('checked here', 'every key against upstream’s example file and 1.8.2 source'),

    ...sec('why this file exists'),
    ...para(
        '#',
        r'A game on this machine does not need a launch option. A '
        r'Hyprland hook notices the window, hands its PID to '
        r'home/.local/bin/gamemode-attach, and that script asks '
        r'GameMode to switch the machine into gaming mode. This '
        r'file is the other half of that conversation: it says what '
        r'“gaming mode” means on a Ryzen 7 5800X with a GTX 980, and '
        r'what to tell the desktop when it starts and stops.'),
    blank,
    ...para(
        '#',
        r'The whole chain, in the order things happen, is:'),
    blank,
    plain('  steam_app_<id> window opens'),
    plain('    -> hyprland.lua window.open hook'),
    plain('    -> gamemode-attach <pid>'),
    plain('    -> gamemoded (this file decides what it does)'),
    plain('    -> governor, renice, ioprio, screensaver, custom hooks'),
    plain('    -> noctalia toast "Performance mode on"'),
    blank,
    ...para(
        '#',
        r'The file arrived in the initial commit with the rest of '
        r'the gaming work. The commit body lists the feature under “Gaming: '
        r'GameMode attached automatically to Steam windows, scx_lavd '
        r'scheduler, NVIDIA power limit raised to the card maximum, '
        r'direct scanout and tearing for games only, MangoHud with '
        r'VRAM readout”. It has not been edited since.'),

    ...sec('the file, in full'),
    ...code('ini', 'home/.config/gamemode.ini', r'''
[general]
; Pin the Ryzen to the performance governor while a game runs,
; then drop back to powersave (amd-pstate active mode) afterwards.
desiredgov=performance
defaultgov=powersave
renice=10
ioprio=0
softrealtime=off
inhibit_screensaver=1

[custom]
start=noctalia msg notification-show "GameMode" "Performance mode on"
end=noctalia msg notification-show "GameMode" "Performance mode off"'''),

    ...sec('key by key, against the defaults'),
    ...para(
        '#',
        r'The daemon layers its configuration. In the 1.8.2 source '
        r'the files are loaded in a fixed order, “arrays merge and '
        r'values overwrite”: the shipped default, then /etc, then '
        r'$XDG_CONFIG_HOME or ~/.config, then the current directory. '
        r'So this file only has to name what differs from upstream. '
        r'Reading it against upstream’s example gamemode.ini shows '
        r'that less differs than the file suggests.'),
    blank,
    ...pt(
        '#',
        'desiredgov=performance',
        r'upstream’s default. The example says the desired governor '
        r'is used instead of “performance”, and the daemon code '
        r'falls back to the string performance when the key is '
        r'empty. Restated, not changed.'),
    ...pt(
        '#',
        'defaultgov=powersave',
        r'a real override. Upstream leaves this commented out, and '
        r'then restores whatever governor it read on entry. See the '
        r'next section.'),
    ...pt(
        '#',
        'renice=10',
        r'a real override. Upstream’s default is 0, meaning no '
        r'change. Per the example, the value is negated and applied '
        r'as a nice value, so 10 means nice -10 for the registered '
        r'process. Needs the gamemode group.'),
    ...pt(
        '#',
        'ioprio=0',
        r'upstream’s default: best-effort class, highest level. '
        r'Restated.'),
    ...pt(
        '#',
        'softrealtime=off',
        r'upstream’s default, and the example notes that SCHED_ISO '
        r'is not supported by upstream kernels anyway. Restated.'),
    ...pt(
        '#',
        'inhibit_screensaver=1',
        r'upstream’s default (“Defaults to 1”). Restated.'),
    blank,
    ...para(
        '#',
        r'Four of six keys repeat the default. The repo gives no '
        r'reason, so what follows is my reading: writing the whole '
        r'[general] block makes the intent readable in one place and '
        r'keeps it stable if a future version changes a default. '
        r'The cost is that a reader must compare with upstream to '
        r'learn which two lines matter.'),

    ...sec('the decision: defaultgov=powersave'),
    ...para(
        '#',
        r'The two-line comment at the top states the machine: the '
        r'Ryzen runs amd-pstate in active mode, and the governor it '
        r'returns to is powersave. I take the comment’s word for the '
        r'mode; the repo has no other record of it. In active mode '
        r'the kernel offers essentially these two governors, as I '
        r'understand the amd-pstate documentation, which would '
        r'explain why the choice is binary.'),
    blank,
    ...para(
        '#',
        r'Why pin the exit value at all? The 1.8.2 source of the '
        r'daemon answers it. On entering GameMode it reads the '
        r'current governor and stores it; on leaving it uses the '
        r'configured defaultgov if the key is non-empty and the '
        r'stored value otherwise. With no key, GameMode restores '
        r'“what it saw”. If it ever sees performance on entry, for '
        r'example because a previous session was cut short or the '
        r'governor was changed by hand, it would faithfully restore '
        r'performance and the desktop would idle hot. Pinning '
        r'powersave makes the end state a property of this file '
        r'instead of a property of history. That is my inference '
        r'about the intent; the code makes the behaviour certain.'),
    blank,
    ...para(
        '#',
        r'One more fact from the same source is worth knowing: the '
        r'daemon does not write the governor itself. It runs '
        r'pkexec on a helper called cpugovctl, so governor changes '
        r'depend on the polkit policy the gamemode package installs.'),

    ...sec('renice=10 and the gamemode group'),
    ...para(
        '#',
        r'Raising a process’s priority (a negative nice value) is a '
        r'privileged operation. Upstream’s example says that to use '
        r'renice the user must be added to the gamemode group and '
        r'then reboot. That requirement is already handled in this '
        r'repo, in the installer’s system mode:'),
    ...code('bash', 'install.sh · group membership', r'''
  echo "group membership"
  for g in gamemode seat docker; do
    getent group "$g" >/dev/null && sudo usermod -aG "$g" "$USER" && echo "  $USER -> $g"
  done'''),
    ...para(
        '#',
        r'The commit that added the loop, 208de62, says in its body '
        r'that “install.sh --system now also joins the '
        r'gamemode/seat/docker groups”. It was made six minutes after '
        r'the initial commit, which suggests the group was noticed '
        r'as missing right after the first version. The loop skips '
        r'a group that does not exist, so on a machine without the '
        r'gamemode package the line is a no-op rather than an error.'),
    blank,
    ...para(
        '#',
        r'There is a catch that I found while reading the daemon '
        r'source for the sibling page, home/.local/bin/gamemode-attach. '
        r'Renice and ioprio are applied per registered client '
        r'process, and the attach script registers a helper '
        r'process, not the game, as I explain there. On that reading '
        r'the governor and the screensaver inhibition, which are '
        r'global, work as intended, while renice=10 and ioprio=0 '
        r'land on the helper. I did not run a real gamemoded, so '
        r'this stays a reading of the source and not a measurement.'),

    ...sec('the hooks'),
    ...para(
        '#',
        r'The [custom] section runs a command through the shell '
        r'when GameMode becomes active and when it stops. Both '
        r'commands use noctalia’s command line, the same interface '
        r'that every key binding in hyprland.lua uses:'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · the same CLI', r'''
hl.bind(mod .. " + D", hl.dsp.exec_cmd("noctalia msg panel-toggle launcher"))
hl.bind(mod .. " + CTRL + V", hl.dsp.exec_cmd("noctalia msg panel-toggle clipboard"))'''),
    ...para(
        '#',
        r'The visible effect is a pair of notifications, “GameMode / '
        r'Performance mode on” and “... off”, so the machine tells '
        r'you that the attach worked instead of leaving you to guess '
        r'from the fan. In the 1.8.2 source the end scripts run '
        r'inside the leave path, after the governor has been reset. '
        r'Upstream’s example lists a default script timeout of 10 '
        r'seconds, far longer than a toast needs.'),
    blank,
    ...para(
        '#',
        r'The timing of “off” is worth a sentence. GameMode ends when '
        r'its last client disappears. The attach script polls for '
        r'the game every 5 seconds before it removes its helper, and '
        r'the daemon’s reaper thread checks for dead clients every '
        r'5 seconds (reaper_freq in the example). The code alone '
        r'accounts for up to about 10 seconds of lag. The comment '
        r'in hyprland.lua records “~20 s” after the game exits; the '
        r'rest of the gap is not explained anywhere in the repo.'),
    blank,
    ...para(
        '#',
        r'MangoHud closes the loop from the other side. Its config '
        r'contains a bare gamemode line, which as I understand the '
        r'option puts the GameMode state in the overlay. And the '
        r'attach script’s own comment says MangoHud loads plain '
        r'libgamemode only to query status, which is why the script '
        r'tells it apart from libgamemodeauto.'),

    ...sec('what the file does not do, and why that fits'),
    ...pt(
        '#',
        'no GPU tuning',
        r'upstream’s [gpu] section can set NVIDIA power-mizer modes '
        r'and clock offsets, behind an “accept-responsibility” key. '
        r'The daemon source also refuses [gpu] options that come '
        r'from a user-level file: it logs that the section “is not '
        r'configurable from unsafe config files” and suggests '
        r'/etc/gamemode.ini. The power limit in this repo is done '
        r'by a systemd unit instead (system/etc/systemd/system/'
        r'nvidia-powerlimit.service). Whether the unit was chosen '
        r'because of this restriction is not stated.'),
    ...pt(
        '#',
        'no core parking or pinning',
        r'the upstream comment says autodetection only understands '
        r'the Ryzen 7900X3D and 7950X3D and Intel parts with E- and '
        r'P-cores. The README names a Ryzen 7 5800X, which is none '
        r'of those, so leaving the [cpu] section alone is consistent '
        r'with the hardware.'),
    ...pt(
        '#',
        'no filter',
        r'no whitelist or blacklist, so any process that registers '
        r'is accepted. Combined with the Hyprland hook matching only '
        r'steam_app_<id> windows, the filtering is done on the '
        r'compositor side.'),
    ...pt(
        '#',
        'disable_splitlock untouched',
        r'upstream’s example says the split-lock mitigation is '
        r'disabled while GameMode is active by default (“Defaults '
        r'to 1”). This file does not change that, so it applies '
        r'here, even though nothing in the repo mentions it.'),

    ...sec('the scheduler is a separate layer'),
    ...para(
        '#',
        r'GameMode changes the governor and process priorities. The '
        r'kernel scheduler is a different choice, made in '
        r'system/etc/scx_loader.toml, and it does not depend on '
        r'GameMode at all:'),
    ...code('toml', 'system/etc/scx_loader.toml · the scheduler', r'''
default_sched = "scx_lavd"
default_mode  = "Gaming"'''),
    ...para(
        '#',
        r'The two layers stack. sched_ext with scx_lavd is always '
        r'on, in its Gaming mode, from boot. GameMode adds a '
        r'governor flip and a nice value only while a game is '
        r'running. The README lists them as separate bullets for '
        r'that reason.'),

    ...sec('how it was checked'),
    ...pt(
        '#',
        'upstream example',
        r'I fetched FeralInteractive/gamemode’s example/gamemode.ini '
        r'and compared each of the eight keys. The statements about '
        r'defaults above come from its comments.'),
    ...pt(
        '#',
        'daemon source',
        r'I read gamemoded.c, gamemode-context.c and '
        r'gamemode-config.c at the 1.8.2 tag. The governor fallback, '
        r'the per-client renice, the config order, the [gpu] '
        r'restriction and the default script timeout of 10 come '
        r'from there. I do not know which version your Arch package '
        r'tracks, so treat the line-level details as 1.8.2.'),
    ...pt(
        '#',
        'not run',
        r'this sandbox has no gamemoded, no cpufreq and no '
        r'noctalia, so nothing here was observed on a live '
        r'system. The toasts, the governor switch and the 20 second '
        r'tail are the repo’s claims, not mine.'),

    ...sec('limits and what is next'),
    ...para(
        '#',
        r'The file cannot say whether it works. It would be worth a '
        r'small test: start a game, run gamemoded -s to print the '
        r'status, read the governor from sysfs, check the nice '
        r'value of the game’s PID and compare with the helper’s. '
        r'That one experiment would settle the question raised in '
        r'the renice section and would turn this page from a '
        r'reading of source into a measurement.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
