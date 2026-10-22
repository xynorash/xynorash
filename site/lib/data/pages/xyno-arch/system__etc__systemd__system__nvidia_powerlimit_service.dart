import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/systemd/system/nvidia-powerlimit.service',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'nvidia-powerlimit.service — 45 more watts, once per boot'),
    cm('#', r'a oneshot unit that raises the GTX 980 to its maximum'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'raise the GPU power limit at boot'),
    kv(r'format', r'systemd unit: [Unit], [Service], [Install]'),
    kv(r'size', r'15 lines, 2 commands'),
    kv(r'installed', r'/etc/systemd/system/, then enable --now by install.sh --system'),
    kv(r'history', r'1 commit: d552dfd (2026-09-19), never edited'),

    ...sec(r'why this file exists'),
    ...para('#',
        r'A graphics card has a power budget. Under a sustained load '
        r'it may hit the budget and lower its clocks to stay inside '
        r'it, which shows up in a game as lower frame rates. The '
        r'budget is a setting, not a hardware wall, and this unit '
        r'moves it. README.md lists it in the gaming section: “NVIDIA '
        r'power limit raised from 180 W to the card’s 225 W maximum '
        r'by a systemd unit, so it holds boost clocks under load”. '
        r'The unit exists because the setting does not survive a '
        r'reboot: it has to be applied again at every boot.'),

    ...sec(r'the unit, in full'),
    ...code('ini', r'system/etc/systemd/system/nvidia-powerlimit.service · lines 1-15', r'''
[Unit]
Description=Raise GTX 980 power limit to its 225 W maximum
After=multi-user.target
ConditionPathExists=/usr/bin/nvidia-smi

[Service]
Type=oneshot
# Default is 180 W; the board allows up to 225 W. More headroom lets the GPU
# hold its boost clock under sustained game load instead of power-throttling.
ExecStart=/usr/bin/nvidia-smi -pm 1
ExecStart=/usr/bin/nvidia-smi -pl 225
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target'''),

    ...sec(r'the [Unit] section'),
    ...pt('#', r'Description',
        r'names the card and the target figure, which is how it '
        r'appears in systemctl status.'),
    ...pt('#', r'After=multi-user.target',
        r'start later than the point where the system is up for '
        r'normal use. The idea is that by then the NVIDIA driver is '
        r'loaded and nvidia-smi can talk to it. The unit is wanted by '
        r'that same target, so it is ordered after the thing it is '
        r'part of. systemd allows that: the order is only a hint '
        r'about when to run, so it runs near the end of boot.'),
    ...pt('#', r'ConditionPathExists=/usr/bin/nvidia-smi',
        r'if the tool is missing, the unit is skipped quietly '
        r'instead of failing. This is a guard for a machine without '
        r'the driver utilities: the same repo could be installed '
        r'there and the boot would not show a failed unit.'),

    ...sec(r'the [Service] section'),
    ...pt('#', r'Type=oneshot',
        r'the unit is a command that runs and finishes, not a daemon. '
        r'systemd waits for each command to end before it considers '
        r'the unit started.'),
    ...pt('#', r'ExecStart=… -pm 1',
        r'persistence mode on. Without it, the driver may unload its '
        r'state when no program uses the card, and settings made by '
        r'nvidia-smi can be lost with it. Turning it on first is '
        r'what makes the next line stick. That ordering is my '
        r'reading of what the two commands are for; the file does '
        r'not comment on -pm.'),
    ...pt('#', r'ExecStart=… -pl 225',
        r'set the power limit to 225 watts. The comment above the two '
        r'commands gives the numbers: “Default is 180 W; the board '
        r'allows up to 225 W”, and the reason: more headroom lets the '
        r'GPU “hold its boost clock under sustained game load '
        r'instead of power-throttling”. A oneshot unit may list '
        r'several ExecStart lines; they run in order and the unit '
        r'fails if one does.'),
    ...pt('#', r'RemainAfterExit=yes',
        r'after the commands finish, the unit stays “active”. For a '
        r'oneshot that is the usual way to make status show that the '
        r'work was done, and it lets systemctl treat the setting as '
        r'applied.'),

    ...sec(r'the [Install] section'),
    ...para('#',
        r'WantedBy=multi-user.target is what systemctl enable acts on: '
        r'it links the unit into that target, so it runs at every '
        r'boot. install.sh does enable and start in one command: '
        r'sudo systemctl enable --now scx_loader.service '
        r'nvidia-powerlimit.service. --now means the limit goes up '
        r'when you run the installer, without waiting for a reboot.'),

    ...sec(r'what the numbers mean, checked'),
    ...para('#',
        r'The comment claims 180 W is the default and 225 W the '
        r'maximum. I did not need to trust it: on the machine, '
        r'nvidia-smi reports a default power limit of 180.00 W, a '
        r'minimum of 120.00 W and a maximum of 225.00 W, and the '
        r'current limit is 225.00 W. The unit is enabled. So the file '
        r'does what it says on the machine it describes, and its '
        r'numbers are the card’s own. I did not measure clocks under '
        r'a game, so the claimed effect on boost behaviour is the '
        r'comment’s, not mine.'),

    ...sec(r'trade-offs'),
    ...pt('#', r'more heat, more draw',
        r'a higher limit lets the card use more power, which is the '
        r'point and the cost. The cooler and the power supply have to '
        r'cope. The card’s own maximum is a manufacturer limit, so '
        r'the file stays inside it.'),
    ...pt('#', r'hardcoded to one card',
        r'the description, the 225 and the unit name are for a GTX '
        r'980. On a different GPU the -pl value could be rejected or '
        r'wrong.'),
    ...pt('#', r'a unit instead of a udev rule or a tool',
        r'a oneshot service is the plain way to run a command once '
        r'at boot, and easy to read. The price is the ordering '
        r'assumption in After=.'),

    ...sec(r'failure modes'),
    ...pt('#', r'driver not ready',
        r'if nvidia-smi runs before the driver, a command fails and '
        r'the unit shows failed. After=multi-user.target makes that '
        r'unlikely.'),
    ...pt('#', r'value out of range',
        r'nvidia-smi refuses a limit outside the board’s range. A '
        r'value above 225 would fail.'),
    ...pt('#', r'driver reload',
        r'if the driver is reloaded while the machine is running, a '
        r'persisted setting may be lost until the unit is started '
        r'again; that is my understanding of how the driver works.'),

    ...sec(r'history'),
    ...pt('#', r'd552dfd, 2026-09-19',
        r'the initial commit: “NVIDIA power limit raised to the card '
        r'maximum”, named among the gaming features. No later commit '
        r'changed the unit.'),
  ],
);
