import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/pam.d/greetd',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'greetd (PAM) — who may log in, and what unlocks on the way'),
    cm('#', r'nine lines between a typed password and a running desktop'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'PAM stack for the greetd login service'),
    kv(r'format', r'PAM: type, control, module, in order'),
    kv(r'size', r'9 lines, 7 of them active'),
    kv(r'installed', r'never automatically; install.sh --system only prints it'),
    kv(r'history', r'1 commit: 208de62 (2026-09-19)'),
    kv(r'drift', r'the copy installed on the machine differs from this one'),

    ...sec(r'why this file exists'),
    ...para('#',
        r'When tuigreet hands greetd a password, greetd does not check '
        r'it. It asks PAM, using a service named after the program: '
        r'greetd. PAM looks for /etc/pam.d/greetd and runs the lines in '
        r'it. This file is that stack. The repo tracks it for one '
        r'reason, which the installer’s printed list gives: “adds '
        r'gnome-keyring unlock at login”. The commit that added it says '
        r'the same thing from the other side: it adds “the greetd PAM '
        r'stack”.'),
    blank,
    ...para('#',
        r'The reason it matters is the keyring. Applications on a Linux '
        r'desktop store secrets (browser logins, tokens) in the '
        r'gnome-keyring daemon, and the daemon needs a password to '
        r'unlock. If it is unlocked with the login password at '
        r'login, the user is never asked a second time. PAM is where '
        r'that handoff has to happen, because it is the only place that '
        r'sees the typed password. packages/pacman.txt lists '
        r'gnome-keyring alongside greetd and greetd-tuigreet.'),

    ...sec(r'the stack, line by line'),
    ...code('text', r'system/etc/pam.d/greetd · lines 1-9', r'''
#%PAM-1.0

auth       required     pam_securetty.so
auth       requisite    pam_nologin.so
auth       include      system-local-login
auth       optional     pam_gnome_keyring.so
account    include      system-local-login
session    include      system-local-login
session    optional     pam_gnome_keyring.so auto_start'''),
    ...para('#',
        r'PAM groups its checks by purpose: auth proves who you are, '
        r'account decides whether you may log in now, session sets '
        r'up and tears down the login. The control word says what '
        r'a failure means: required fails the stack at the end, '
        r'requisite fails at once, optional never decides the '
        r'result, and include pulls in another file.'),
    blank,
    ...pt('#', r'auth required pam_securetty.so',
        r'a classic check that root may only log in on a trusted '
        r'terminal. I did not test its behaviour for an ordinary '
        r'user. It exists on this system (pam_securetty.so is in the '
        r'PAM module directory).'),
    ...pt('#', r'auth requisite pam_nologin.so',
        r'if /etc/nologin exists, ordinary users are refused at once.'),
    ...pt('#', r'auth include system-local-login',
        r'the real password check. system-local-login is Arch’s '
        r'stack for local logins, which in turn includes the shared '
        r'system-auth. On the machine, system-auth also carries '
        r'pam_limits in its session section, so the rtprio and memlock '
        r'limits from 99-realtime-audio.conf apply to a session that '
        r'comes through this file as well.'),
    ...pt('#', r'auth optional pam_gnome_keyring.so',
        r'receives the password that the line above verified and '
        r'keeps it so the module can unlock the keyring later. Optional '
        r'means that if the module is missing or fails, login still '
        r'succeeds.'),
    ...pt('#', r'account include system-local-login',
        r'account checks come from the shared stack.'),
    ...pt('#', r'session include system-local-login',
        r'session setup comes from the shared stack.'),
    ...pt('#', r'session optional pam_gnome_keyring.so auto_start',
        r'at session start the module starts the keyring daemon and '
        r'unlocks it with the password it kept. Again optional.'),

    ...sec(r'design decisions'),
    ...pt('#', r'optional, twice',
        r'the keyring is a convenience. A broken keyring must never '
        r'block a login, and optional makes sure of it.'),
    ...pt('#', r'include, not copy',
        r'the file adds only the keyring on top of the distribution’s '
        r'local login stack, so password policy stays where Arch '
        r'maintains it.'),
    ...pt('#', r'not installed for you',
        r'a wrong PAM file can lock every user out of the machine, '
        r'including the one who is trying to fix it. So the installer '
        r'prints it with the others that replace system-owned files '
        r'and expects a manual comparison.'),

    ...sec(r'where the repo and the machine disagree'),
    ...para('#',
        r'Checking the live /etc/pam.d/greetd against the tracked copy '
        r'shows they are not the same. It is the only mismatch among the '
        r'system files I could compare (loader.conf is not present on '
        r'the machine I checked, so that one I could not). The live file has the '
        r'same lines plus two guards, in front of each keyring line: '
        r'pam_succeed_if.so quiet user = greeter, with a comment above '
        r'the first, “skip the keyring module for the greeter user '
        r'(HOME=/, cannot create keyrings)”. In other words, the greeter '
        r'program itself runs as the user greeter, goes through this '
        r'same service, and the keyring module should not try to '
        r'make a keyring for that account.'),
    blank,
    ...para('#',
        r'So the version in git is the earlier one. A fresh install '
        r'from this repo would get a stack without the guards. I do not '
        r'know what that does in practice, whether it is a harmless '
        r'warning in the log or an error; I did not reproduce it. What '
        r'I can say is that the tracked copy lacks lines the live file '
        r'has, so a fresh install from the repo would not reproduce '
        r'this machine.'),

    ...sec(r'how it connects to the other files'),
    ...pt('#', r'system/etc/greetd/config.toml',
        r'runs tuigreet as user greeter; this file is the PAM service '
        r'that greetd consults for the name greetd.'),
    ...pt('#', r'system/etc/security/limits.d/99-realtime-audio.conf',
        r'applies through pam_limits when the session stack includes it.'),
    ...pt('#', r'packages/pacman.txt',
        r'gnome-keyring, greetd and greetd-tuigreet are all listed.'),

    ...sec(r'how I checked it'),
    ...para('#',
        r'There are no tests for PAM here, and I would not run a '
        r'login test against a real stack in a documentation pass. I '
        r'read the live file and the two shared stacks it includes, and '
        r'checked that every module it names exists in the PAM module '
        r'directory (pam_securetty, pam_nologin, pam_gnome_keyring).'),

    ...sec(r'history'),
    ...pt('#', r'208de62, 2026-09-19 18:34',
        r'added six minutes after the initial commit, in the same '
        r'change that also added the mkinitcpio preset. The first commit '
        r'already tracked greetd/config.toml, but not the PAM stack that '
        r'the greeter uses.'),
  ],
);
