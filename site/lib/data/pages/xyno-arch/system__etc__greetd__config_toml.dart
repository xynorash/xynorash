import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/greetd/config.toml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'config.toml — the login screen, as one long command'),
    cm('#', 'greetd runs tuigreet; tuigreet starts Hyprland'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'greetd configuration: which greeter runs on boot and what it launches'),
    kv('language', 'TOML, 6 lines, one of them 560 characters long'),
    kv('size', '1 commit: d552dfd (2026-09-19), never edited since'),
    kv('installed as', '/etc/greetd/config.toml by install.sh --system (copy, mode 644)'),
    kv('parsed here', 'tomllib reads it; the command splits into 38 shell words'),

    ...sec('why this file exists'),
    ...para(
        '#',
        r'A display manager has to do three things: show something '
        r'to log in with, check the password, and start a session. '
        r'greetd splits those jobs on purpose. The daemon owns '
        r'authentication and session start; the greeter is a '
        r'separate, unprivileged program that only draws the screen '
        r'and talks to the daemon over a socket. This file picks the '
        r'greeter. Here that is tuigreet, a terminal-UI greeter, and '
        r'the README table reads “greetd + tuigreet, matrix '
        r'background”.'),
    blank,
    ...para(
        '#',
        r'The whole login path across the repo is:'),
    blank,
    plain('  systemd starts greetd.service'),
    plain('    -> greetd runs the greeter as user "greeter" on VT 1'),
    plain('    -> tuigreet draws the screen (flags in this file)'),
    plain('    -> the typed password goes to PAM, service "greetd"'),
    plain('       (system/etc/pam.d/greetd, unlocks gnome-keyring)'),
    plain('    -> greetd starts: start-hyprland, as the new user'),
    plain('    -> hyprland.lua, then noctalia on hyprland.start'),
    blank,

    ...sec('the file, in full'),
    ...code('toml', 'system/etc/greetd/config.toml · structure', r'''
[terminal]
vt = 1

[default_session]
user = "greeter"'''),
    ...para(
        '#',
        r'The three structural lines are small. vt = 1 puts greetd on '
        r'the first virtual terminal, the one a text login would '
        r'otherwise use. [default_session] is the session greetd '
        r'runs when nobody is logged in yet, and user = "greeter" is '
        r'the unprivileged account it runs the greeter as. The '
        r'account is created by the greetd package; the repo does not '
        r'create it. The interesting line is the command, and the '
        r'rest of the page takes it apart.'),

    ...sec('the command, in four groups'),
    ...para(
        '#',
        r'The command is one TOML string. I split it with a '
        r'shell-words parser to check how many arguments it has: '
        r'38, starting with tuigreet. Grouped by what they do, they '
        r'are the look, the clock, the memory, and the launch.'),
    blank,
    ...para('#', r'1. The look: a matrix rain behind the form.'),
    ...code('toml', 'system/etc/greetd/config.toml · background and theme', r'''
tuigreet --background matrix --matrix-colors '#7dcfff,#7aa2f7,#bb9af7' --matrix-length 6,20
--theme 'border=lightblue;title=lightblue;text=white;time=lightblue;greet=lightmagenta;prompt=lightcyan;input=white;action=darkgray;button=lightmagenta;container=black'
--window-padding 2 --container-padding 2 --prompt-padding 1 --width 60'''),
    ...para(
        '#',
        r'This excerpt is cut from the single line and shown on '
        r'three lines for reading; in the file it is one string. The '
        r'rain colours are hex values, and they are the Tokyo Night '
        r'palette used everywhere else in the repo:'),
    ...code('ini', 'home/.config/ghostty/themes/noctalia · the same three colours', r'''
palette = 4=#7aa2f7
palette = 5=#bb9af7
palette = 6=#7dcfff'''),
    ...para(
        '#',
        r'#7dcfff is Tokyo Night’s cyan, #7aa2f7 its blue and #bb9af7 '
        r'its purple, which are palette slots 6, 4 and 5 in the '
        r'Ghostty theme that noctalia generates. The login screen '
        r'is therefore the first thing in the session that matches '
        r'the desktop it leads to, even though noctalia is not '
        r'running yet. The matrix flags are the unusual part of the '
        r'string. I know the upstream tuigreet options for time, '
        r'greeting, padding and theme, and did not find the matrix '
        r'ones in the flag set I remember, so the installed '
        r'release must be newer than my knowledge of it. I could not '
        r'check that here.'),
    blank,
    ...para(
        '#',
        r'The --theme string is the other half of the look. It names '
        r'colours (lightblue, lightmagenta, darkgray) instead of '
        r'giving hex. I believe tuigreet’s theme option accepts '
        r'terminal colour names, which would explain why hex is used '
        r'only for the matrix and names everywhere else. That is an '
        r'inference about the tool, not something the file says. The '
        r'choice of names tracks the same palette: light blue for '
        r'borders, title and clock, light magenta for the greeting '
        r'and button, light cyan for the prompt.'),
    blank,
    ...para('#', r'2. The clock and the greeting.'),
    ...code('toml', 'system/etc/greetd/config.toml · time and greeting', r'''
--time --time-format '%A %d %B  ·  %H:%M' --greeting 'xynogamer' --greet-align center'''),
    ...para(
        '#',
        r'The time format is a strftime pattern: weekday name, '
        r'two-digit day, month name, a middle dot between two '
        r'spaces on each side, then 24-hour time. On the day I '
        r'wrote this page it would render as “Thursday 08 October  ·  '
        r'11:53”. I computed that from the pattern, I did not see it '
        r'on a screen. The greeting is the string xynogamer, centred. '
        r'The repo does not say what it names; it reads like the '
        r'machine’s handle, and it matches the tagline of the whole '
        r'project, a desktop tuned for gaming.'),
    blank,
    ...para('#', r'3. What it remembers and who it shows.'),
    ...code('toml', 'system/etc/greetd/config.toml · remembering', r'''
--asterisks --asterisks-char '•' --remember --remember-session --user-menu --user-menu-min-uid 1000'''),
    ...pt(
        '#',
        '--asterisks, --asterisks-char',
        r'echo each typed password character as a bullet instead of '
        r'showing nothing. A cosmetic choice, with a small '
        r'usability payoff: you can tell the keystroke registered.'),
    ...pt(
        '#',
        '--remember, --remember-session',
        r'remember the last user name and the last session, so a '
        r'normal boot is “type the password”. As I understand '
        r'tuigreet, these are stored in a cache directory '
        r'writable by the greeter user.'),
    ...pt(
        '#',
        '--user-menu, --user-menu-min-uid 1000',
        r'show a menu of accounts instead of a free-text field, '
        r'listing only users whose uid is 1000 or more. On Linux '
        r'the first regular user gets uid 1000, so this hides '
        r'system accounts without hard-coding a name.'),
    blank,
    ...para('#', r'4. Power and the launch.'),
    ...code('toml', 'system/etc/greetd/config.toml · power and launch', r'''
--power-shutdown 'systemctl poweroff' --power-reboot 'systemctl reboot' --cmd start-hyprland"'''),
    ...para(
        '#',
        r'The two power flags give tuigreet the commands to run '
        r'from its own power menu, so the machine can be shut down '
        r'from the greeter without logging in. They are the same '
        r'idea as the compositor’s session menu, in a place where '
        r'no compositor is running; see etc/systemd/logind.conf.d/'
        r'10-power-key.conf for what the power button does after '
        r'login.'),
    blank,
    ...para(
        '#',
        r'--cmd start-hyprland is the line that matters most. It is '
        r'the command greetd runs once the password is accepted, '
        r'and it runs as the logged-in user. start-hyprland is a '
        r'launcher that ships with Hyprland; naming it, instead of '
        r'Hyprland directly, is what the project recommends in '
        r'recent releases, as far as I know. The repo’s own '
        r'comment dates the config format: hyprland.lua says that the '
        r'older hyprlang format “is deprecated as of Hyprland '
        r'0.55”, so this is a recent Hyprland and the launcher '
        r'name fits. Because the command is fixed, there is no '
        r'session picker: one account, one desktop, and the menu '
        r'would only get in the way. That reading is mine.'),

    ...sec('what a mistake here costs'),
    ...para(
        '#',
        r'The file is installed automatically (it is in the nine-file '
        r'loop in install.sh), and nothing restarts greetd afterwards, '
        r'so a new version takes effect the next time the service '
        r'starts. That is a deliberate-looking omission: restarting a '
        r'display manager from a running desktop would end the '
        r'session that is running the installer. If the command is '
        r'wrong, the failure is at the next boot, and it is loud and '
        r'recoverable: no greeter appears, a text console is still '
        r'there, and the file can be corrected from it.'),
    blank,
    ...para(
        '#',
        r'There is one gap I could find. install.sh enables '
        r'scx_loader.service and nvidia-powerlimit.service and '
        r'nothing else, so greetd.service itself is not enabled by '
        r'the repo. The packages list installs greetd and '
        r'greetd-tuigreet, and the README says the login is greetd, '
        r'so the service is enabled somewhere, but not in anything '
        r'tracked. A fresh machine would need that done by hand.'),

    ...sec('history'),
    ...pt(
        '#',
        'd552dfd, 2026-09-19',
        r'the initial commit already had the whole command, the '
        r'matrix background included. The login screen was not '
        r'built up in steps; it arrived finished.'),
    ...pt(
        '#',
        '208de62, 2026-09-19',
        r'six minutes later the PAM file for the same service was '
        r'added, with the gnome-keyring lines. The two files describe '
        r'one login from two sides: this one the screen and the '
        r'launch, the other the authentication.'),
    blank,
    ...para(
        '#',
        r'Since then the file has not changed. Of 21 commits touching '
        r'the repo after the first, none edit it.'),

    ...sec('limits, and what is next'),
    ...pt(
        '#',
        'one 560-character line',
        r'TOML offers multi-line strings, and the command would be '
        r'far easier to review split at the flag groups above. The '
        r'cost of the long line is that a diff of any change shows '
        r'the whole string as modified.'),
    ...pt(
        '#',
        'colours in two languages',
        r'hex for the rain and names for the theme: the palette '
        r'lives in three places now (this file, the Ghostty theme, '
        r'noctalia’s config), and only the last is generated.'),
    ...pt(
        '#',
        'unverified flags',
        r'the matrix options are not in the tuigreet flag set I '
        r'know. I trust the README that they work on the installed '
        r'version, and I could not confirm the version here.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
