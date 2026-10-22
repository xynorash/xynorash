import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/pam.d/greetd',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'greetd — the login stack that unlocks the keyring'),
    cm('#', 'two optional lines added to a stock PAM service'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'PAM service used when someone logs in through greetd'),
    kv('language', 'PAM configuration: type, control, module, arguments'),
    kv('size', '9 lines, 7 active; 1 commit: 208de62 (2026-09-19 18:34)'),
    kv('the addition', 'pam_gnome_keyring.so twice: once in auth, once in session'),
    kv('installed by', 'nobody: printed as “adds gnome-keyring unlock at login”'),

    ...sec('why this file exists'),
    ...para(
        '#',
        r'Logging in on a Linux desktop does two jobs that look like '
        r'one. It proves who you are, and it hands the session '
        r'a secret: your password, typed once. Programs that keep '
        r'tokens, Wi-Fi keys or browser logins need a place to '
        r'store them, the secret service, and a place to store '
        r'secrets must itself be unlocked with something. If the '
        r'login password unlocks it, nobody sees a second prompt. '
        r'That is the entire purpose of this file: a PAM stack for '
        r'greetd that passes the password to gnome-keyring at the '
        r'moment of login.'),
    blank,
    ...para(
        '#',
        r'The repo supports the point from two sides. The package '
        r'list installs gnome-keyring, and the xdg-desktop-portal '
        r'configuration names it as the provider of the Secret '
        r'interface:'),
    ...code('ini', 'home/.config/xdg-desktop-portal/hyprland-portals.conf · the secret provider', r'''
org.freedesktop.impl.portal.Secret=gnome-keyring;'''),
    ...para(
        '#',
        r'Applications that ask the portal for a secret reach '
        r'gnome-keyring. Without the PAM lines the keyring would '
        r'start locked and ask for its own password the first '
        r'time something needed it. With them, it is unlocked by '
        r'the login and the question never appears.'),

    ...sec('the file, in full'),
    ...code('text', 'system/etc/pam.d/greetd', r'''
#%PAM-1.0

auth       required     pam_securetty.so
auth       requisite    pam_nologin.so
auth       include      system-local-login
auth       optional     pam_gnome_keyring.so
account    include      system-local-login
session    include      system-local-login
session    optional     pam_gnome_keyring.so auto_start'''),
    ...para(
        '#',
        r'PAM configuration is read as a table. Each line has a '
        r'type (which question is being asked), a control flag '
        r'(what a failure means), a module and optional '
        r'arguments. The file name is the PAM service name, which '
        r'is how greetd finds this file: as I understand greetd, it '
        r'authenticates the person typing in the greeter through '
        r'a service called greetd.'),

    ...sec('what is stock and what was added'),
    ...para(
        '#',
        r'Seven of the nine lines (the header, the blank line and '
        r'five rules) are, as far as I can tell, the stack that '
        r'the greetd package installs: a securetty check, a '
        r'nologin check, and three lines that hand the real work '
        r'to the system-local-login service. I am '
        r'recalling that stock file from the Arch package and '
        r'could not diff it. The two lines that are Nash’s are '
        r'the pam_gnome_keyring.so lines, and the installer’s hint '
        r'says exactly that: “adds gnome-keyring unlock at login”. '
        r'They follow the pattern in the Arch documentation for '
        r'gnome-keyring, one line at the end of the auth '
        r'section and one with auto_start at the end of the '
        r'session section.'),
    blank,
    ...pt(
        '#',
        'auth required pam_securetty.so',
        r'restricts root logins to terminals listed in a file. For '
        r'ordinary users it does not get in the way.'),
    ...pt(
        '#',
        'auth requisite pam_nologin.so',
        r'refuses logins while /etc/nologin exists. requisite '
        r'means the stack stops at once on failure instead of '
        r'continuing.'),
    ...pt(
        '#',
        'auth include system-local-login',
        r'pull in another file: the distribution’s login rules, '
        r'where the password is actually checked. Every line with '
        r'include, in all three sections, defers to the same file.'),
    ...pt(
        '#',
        'auth optional pam_gnome_keyring.so',
        r'the first addition. In the auth stage it takes the '
        r'password that was just typed and remembers it for the '
        r'session stage. It sits after the include, so it runs '
        r'only once the real check has passed.'),
    ...pt(
        '#',
        'session optional pam_gnome_keyring.so auto_start',
        r'the second addition. When the session opens, it starts '
        r'the keyring daemon if it is not running and unlocks the '
        r'login keyring with the remembered password. auto_start is '
        r'the argument that makes it launch the daemon.'),

    ...sec('why optional, and why those positions'),
    ...para(
        '#',
        r'The control flag is the safety of the whole design. PAM '
        r'optional means a module’s result only matters if it is '
        r'the only module of its type. Here it is not, so if '
        r'gnome-keyring is missing, crashes, or cannot unlock the '
        r'keyring, login still succeeds. A secrets problem is '
        r'allowed to degrade to “you will be asked for a password '
        r'later”, never to “you cannot log in”. That is the right '
        r'ranking for a convenience feature bolted onto the one '
        r'service that gates the whole desktop.'),
    blank,
    ...para(
        '#',
        r'The positions matter too. In the auth section the '
        r'keyring line comes after the include, because it needs a '
        r'password that has already been validated. In the session '
        r'section it comes after the include of the standard '
        r'session setup, so the user’s environment exists when '
        r'the daemon starts. Order in a PAM file is order of '
        r'execution, so swapping those lines would change behaviour.'),

    ...sec('the chain at login'),
    plain('  tuigreet reads the password          (greetd/config.toml)'),
    plain('    -> greetd asks PAM, service "greetd"   (this file)'),
    plain('    -> system-local-login checks it        (stock)'),
    plain('    -> pam_gnome_keyring keeps the password'),
    plain('    -> session opens, keyring daemon starts, login keyring unlocks'),
    plain('    -> start-hyprland runs as the user'),
    plain('    -> a portal asks for a secret          (hyprland-portals.conf)'),
    blank,
    ...para(
        '#',
        r'There is a precondition the file cannot enforce. The login '
        r'keyring can only be unlocked by the login password if the '
        r'keyring was created with that same password. If the '
        r'passwords differ, the daemon starts and stays locked, '
        r'and applications prompt as before. The repo documents '
        r'no step that sets it up.'),

    ...sec('why this file is not installed automatically'),
    ...para(
        '#',
        r'The nine system files the installer copies are all drop-ins '
        r'or standalone files. This one replaces a file that the '
        r'greetd package owns, and its failure mode, however '
        r'unlikely with these two optional lines, is the worst of '
        r'its kind: nobody can log in at the greeter. The installer '
        r'puts it on the printed list and says to compare by hand. '
        r'A text console would still allow a repair, but the '
        r'machine would not reach the desktop in the meantime.'),
    ...code('bash', 'install.sh · the printed entry', r'''
  echo "  system/etc/pam.d/greetd        adds gnome-keyring unlock at login"'''),
    ...para(
        '#',
        r'That the greetd configuration file is auto-installed and '
        r'the PAM one is not shows how the installer ranks '
        r'consequences. A wrong greeter command leaves a login '
        r'screen that does not start. A wrong PAM stack can lock '
        r'every login. The installer’s caution is proportional to '
        r'the second.'),

    ...sec('history'),
    ...pt(
        '#',
        '208de62, 2026-09-19 18:34',
        r'the file arrives, six minutes after the initial commit '
        r'(the first commit has the greetd configuration, but not '
        r'its PAM side). The commit message names it: “the greetd '
        r'PAM stack”, in a list of things added so the desktop '
        r'reproduces on another machine.'),
    ...pt(
        '#',
        'since',
        r'unchanged.'),

    ...sec('limits, and what is next'),
    ...pt(
        '#',
        'stock text recalled, not diffed',
        r'I believe the first seven lines are the package’s. If '
        r'the package changes its default, this copy would not '
        r'follow, because it replaces the file rather than layers '
        r'on it. PAM has no drop-in directory for this; the '
        r'closest alternative is a small include file.'),
    ...pt(
        '#',
        'password sync is manual',
        r'see above: the keyring password must match the login '
        r'password, and nothing here arranges it.'),
    ...pt(
        '#',
        'lock screen is separate',
        r'the lock screen is a separate component. This file '
        r'concerns the greeter login only, and the repo says '
        r'nothing about how the lock screen authenticates.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
