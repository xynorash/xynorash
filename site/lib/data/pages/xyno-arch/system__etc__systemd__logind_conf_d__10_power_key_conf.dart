import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/systemd/logind.conf.d/10-power-key.conf',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'10-power-key.conf — the power button asks before it acts'),
    cm('#', r'logind steps aside so the desktop can answer first'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'make the power button a request, not an immediate shutdown'),
    kv(r'format', r'systemd drop-in: a [Login] section with two keys'),
    kv(r'size', r'6 lines: 4 comment lines and 2 settings'),
    kv(r'installed', r'/etc/systemd/logind.conf.d/, then systemctl reload systemd-logind'),
    kv(r'history', r'1 commit: 0dc7770 (2026-09-21 01:30)'),

    ...sec(r'why this file exists'),
    ...para('#',
        r'By default, pressing the power button on a Linux machine asks '
        r'logind to power it off, with no question. The commit that '
        r'added this file, 0dc7770, says what it wanted instead: '
        r'“Power button opens the session menu instead of powering '
        r'off”. The menu is noctalia’s session panel, the shell '
        r'this repo uses for the bar, launcher and lock screen. For '
        r'that to be possible, something has to stop logind from '
        r'acting on the key first. This is that something.'),

    ...sec(r'the file, in full'),
    ...code('ini', r'system/etc/systemd/logind.conf.d/10-power-key.conf · lines 1-6', r'''
[Login]
# The compositor owns the power key: it opens noctalia's session menu instead
# of logind powering the machine off with no confirmation.
HandlePowerKey=ignore
# Holding it for ~5 s still powers off, as an escape hatch if the session hangs.
HandlePowerKeyLongPress=poweroff'''),
    ...pt('#', r'HandlePowerKey=ignore',
        r'tells logind to do nothing on a short press. The key event '
        r'still exists and still reaches the desktop; it just has '
        r'no system-level consequence. The comment’s phrase is that '
        r'“the compositor owns the power key”.'),
    ...pt('#', r'HandlePowerKeyLongPress=poweroff',
        r'a separate action for a long press. The comment says about '
        r'five seconds, and calls it “an escape hatch if the session '
        r'hangs”. The commit message agrees: holding the button “still '
        r'forces a poweroff”. The five seconds is the author’s figure; '
        r'the file contains no duration, so the delay is whatever '
        r'systemd uses for a long press.'),

    ...sec(r'the other half is in hyprland.lua'),
    ...code('lua', r'home/.config/hypr/hyprland.lua · line 121', r'''
hl.bind("XF86PowerOff", hl.dsp.exec_cmd("noctalia msg panel-toggle session"), { locked = true })'''),
    ...para('#',
        r'The compositor binds the XF86PowerOff key to a command that '
        r'toggles noctalia’s session panel. The setting locked = true '
        r'lets the bind work while the screen is locked, so the same '
        r'press still reaches the menu there. The two files are one '
        r'feature split across two owners: hyprland.lua says what the '
        r'press does, and this file removes the thing that would '
        r'otherwise do something else at the same time. Take away '
        r'either half and the behaviour breaks. Without the bind the '
        r'button does nothing at all, and without the drop-in the '
        r'machine shuts down on the press while the menu is opening.'),

    ...sec(r'design decisions'),
    ...pt('#', r'a drop-in, not an edit',
        r'the file sits in logind.conf.d, so the distribution’s own '
        r'logind.conf is left alone and the package can still update '
        r'it. The name starts with 10 so it sorts early and later '
        r'drop-ins may override it.'),
    ...pt('#', r'keep a hardware escape',
        r'ignoring the key entirely would leave no way to power off a '
        r'frozen desktop except by cutting the power at the wall. The '
        r'long press covers that, and the file says why.'),
    ...pt('#', r'the key is not suppressed, only delegated',
        r'ignore applies to logind’s handling. The key still arrives '
        r'as an input event, which is what hyprland.lua listens for.'),

    ...sec(r'how it is installed'),
    ...para('#',
        r'The same commit added the file to the list in install.sh and '
        r'added a line after the loop: sudo systemctl reload '
        r'systemd-logind. The reload matters, because logind reads its '
        r'configuration at start, so without a reload or a reboot the '
        r'old behaviour would remain until the next boot. The '
        r'installer and the system file were changed in the same '
        r'commit, which happened again for the resolved drop-in in 901611a.'),

    ...sec(r'failure modes'),
    ...pt('#', r'no compositor bind',
        r'if hyprland.lua is not loaded, for instance at the greeter, '
        r'a short press does nothing. Only the long press works. At '
        r'the login screen the compositor is not running, so there '
        r'is no menu to open. The repo does not say how it handles '
        r'that.'),
    ...pt('#', r'a hung session',
        r'a hung compositor cannot answer the key, and that is exactly '
        r'the case the long press is for.'),
    ...pt('#', r'laptop',
        r'on a portable the same drop-in would hide the key from logind '
        r'in any situation; this repo describes a desktop.'),

    ...sec(r'how I checked it'),
    ...para('#',
        r'The repo has no test. The tracked file is identical to '
        r'/etc/systemd/logind.conf.d/10-power-key.conf on the machine. '
        r'I did not press the power button, so what happens on a press '
        r'is read from the two configurations, not observed.'),

    ...sec(r'history'),
    ...pt('#', r'0dc7770, 2026-09-21 01:30',
        r'“Power button opens the session menu instead of powering '
        r'off”. The commit body: “logind is set to ignore the power '
        r'key so Hyprland can bind it; the bind opens noctalia’s '
        r'session panel. Holding the button for ~5 s still forces a '
        r'poweroff.” Its first change to install.sh added this file '
        r'and the reload. It is the first of the 15 commits made on '
        r'2026-09-21, the busiest day in the repo.'),
  ],
);
