import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/home/.config/xdg-desktop-portal/hyprland-portals.conf',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'hyprland-portals.conf — which backend answers which portal'),
    cm('#', 'eight lines that decide who draws dialogs and who captures the screen'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'portal routing table for the Hyprland session'),
    kv('language', 'portals.conf: one [preferred] group of interface=backend pairs'),
    kv('size', '8 lines, 6 interface routes plus a default'),
    kv('history', '1 commit, d552dfd (2026-09-19), never edited since'),
    kv('installed as', '~/.config/xdg-desktop-portal/hyprland-portals.conf (symlink)'),
    ...sec('the problem: several backends, one question'),
    ...para('#',
        r'Applications that want something from the desktop, such as a '
        r'file dialog, a permission prompt, a screen capture or a stored '
        r'password, do not talk to a window system directly. They call '
        r'the xdg-desktop-portal service, which forwards each request to '
        r'a backend that implements the interface. Several backends can '
        r'be installed at once, each implementing a different subset, '
        r'and the service needs a rule to pick between them.'),
    blank,
    ...para('#',
        r'This desktop installs two of them, both listed in '
        r'packages/pacman.txt: xdg-desktop-portal-hyprland, which knows '
        r'how to capture Hyprland’s screen, and xdg-desktop-portal-gtk, '
        r'which provides conventional GTK dialogs. gnome-keyring is '
        r'installed as well. The file on this page is the rule that '
        r'says which of the three answers what.'),
    ...sec('the whole file'),
    ...code('ini', 'home/.config/xdg-desktop-portal/hyprland-portals.conf', r'''
[preferred]
default=gtk;
org.freedesktop.impl.portal.Access=gtk;
org.freedesktop.impl.portal.Notification=gtk;
org.freedesktop.impl.portal.FileChooser=gtk;
org.freedesktop.impl.portal.ScreenCast=hyprland;
org.freedesktop.impl.portal.Screenshot=hyprland;
org.freedesktop.impl.portal.Secret=gnome-keyring;'''),
    ...para('#',
        r'The group name [preferred] and the interface=backend syntax '
        r'belong to the portals.conf format; the trailing semicolon '
        r'marks each value as a list (an ordered list of backends is '
        r'allowed, this file always gives exactly one). Reading it '
        r'top to bottom gives a default and six explicit overrides.'),
    ...sec('why the file is called hyprland-portals.conf'),
    ...para('#',
        r'The portal service chooses its configuration by desktop name. '
        r'The name is taken from XDG_CURRENT_DESKTOP, lower-cased, and '
        r'the file is looked up as <name>-portals.conf in the user’s '
        r'xdg-desktop-portal directory. That is the portals.conf '
        r'convention as generally described, not something the repo '
        r'documents. '
        r'What the repo does show is the other half of the chain: '
        r'hyprland.lua sets the variable explicitly.'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · the variable that selects this file', r'''
hl.env("XDG_CONFIG_HOME", "/home/xynorash/.config")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")'''),
    ...para('#',
        r'With XDG_CURRENT_DESKTOP set to Hyprland, the lower-cased name '
        r'is hyprland, which matches this file name. The session itself '
        r'is started by greetd, whose configuration '
        r'(system/etc/greetd/config.toml) launches the compositor with '
        r'--cmd start-hyprland. Setting the variable inside hyprland.lua, '
        r'rather than trusting whatever the login manager exported, means '
        r'the routing does not depend on how the session was started. '
        r'That reading is an inference; no comment in the repo says it.'),
    ...sec('the routes, one by one'),
    ...pt('#', 'default=gtk;',
        'anything not named below goes to xdg-desktop-portal-gtk. It is '
        'the safety net: a new portal interface, or one this file '
        'forgot, still has an answer.'),
    ...pt('#', 'Access=gtk;',
        'the Access interface is the one portals use to ask the person '
        'for permission ("allow this application to ..."). The GTK '
        'backend draws those prompts.'),
    ...pt('#', 'Notification=gtk;',
        'the portal for applications that post notifications through '
        'the portal instead of the notification daemon. The shell here '
        'is noctalia, which the README lists as the notification '
        'provider, so this route reads as a forwarding hop to the '
        'ordinary notification service. The repo does not explain it.'),
    ...pt('#', 'FileChooser=gtk;',
        'open and save dialogs for portal-aware applications. xdph is '
        'a screen-capture and shortcuts backend and does not draw file '
        'dialogs, so GTK is the natural owner. Naming it explicitly '
        'also pins it even though default would already catch it.'),
    ...pt('#', 'ScreenCast=hyprland;',
        'screen sharing goes to xdph. This is the route that makes '
        'home/.config/hypr/xdph.conf matter: its force_shm and '
        'allow_token_by_default only apply because this line sends '
        'ScreenCast sessions to the hyprland backend.'),
    ...pt('#', 'Screenshot=hyprland;',
        'the Screenshot portal also goes to xdph. The Print key does not '
        'use it: hyprland.lua binds Print, SHIFT+Print and SUPER+Print '
        'to noctalia’s own screenshot commands. This route serves '
        'applications that ask the portal for a screenshot themselves. '
        'What the hyprland backend needs at runtime to fulfil it was '
        'not verified.'),
    ...pt('#', 'Secret=gnome-keyring;',
        'the Secret portal, where sandboxed applications store and '
        'fetch passwords, is answered by gnome-keyring’s own backend.'),
    ...sec('the keyring thread through the repo'),
    ...para('#',
        r'The last route does not stand alone. The login stack was '
        r'extended to unlock the keyring at login, and that is what '
        r'makes a Secret route to gnome-keyring useful: presumably the '
        r'keyring is already open when the first application asks it '
        r'for something. '
        r'The relevant lines are in the PAM file the repo ships for '
        r'greetd. Commit 208de62 ("Track everything needed to reproduce '
        r'the desktop") added that file, and install.sh lists it among '
        r'the system files it does not copy automatically, because it '
        r'replaces a file the system owns.'),
    ...code('ini', 'system/etc/pam.d/greetd · keyring hooks', r'''
auth       optional     pam_gnome_keyring.so
session    optional     pam_gnome_keyring.so auto_start'''),
    ...para('#',
        r'Taken together: pam_gnome_keyring unlocks and starts the '
        r'keyring when the person logs in through greetd, the packages '
        r'list installs gnome-keyring, and this file routes the Secret '
        r'portal to it. Three files in three directories, one feature; '
        r'none of them refers to the others. The only written trace of '
        r'the connection is install.sh’s one-line note that the PAM '
        r'file "adds gnome-keyring unlock at login".'),
    ...sec('how the pieces fit on a screen share'),
    ...pt('#', 'step 1',
        'Chrome asks the portal service for a ScreenCast session.'),
    ...pt('#', 'step 2',
        'this file sends ScreenCast to the hyprland backend.'),
    ...pt('#', 'step 3',
        'xdph reads xdph.conf: shared-memory frames are forced, and the '
        'picker’s "allow a restore token" box starts ticked.'),
    ...pt('#', 'step 4',
        'the frames reach Chrome. If Chrome had asked to remember the '
        'choice, the next share skips the picker.'),
    ...para('#',
        r'Steps 2 and 3 are configuration, and both files are tracked, '
        r'which is the point of the project: the screen-sharing '
        r'behaviour is part of what install.sh reproduces, not something '
        r'discovered by clicking through a settings dialog.'),
    ...sec('what is deliberately not here'),
    ...para('#',
        r'The file does not list a Settings, Inhibit, Background or '
        r'GlobalShortcuts route. By the structure of the format, those '
        r'fall through to default=gtk; whether the GTK backend can '
        r'actually serve each of them is a property of that package '
        r'that was not checked. There is also no comment in the file at '
        r'all. Every route is self-explanatory to someone who knows the '
        r'portal names, and opaque to everyone else, which is the reason '
        r'for the explanations above.'),
    ...sec('history'),
    ...para('#',
        r'One commit touched the file: d552dfd, the initial commit of '
        r'2026-09-19, whose message summarises the project as "Hyprland '
        r'(Lua config) with noctalia as the shell, Ghostty, Yazi and '
        r'greetd". The routes were therefore decided up front and have '
        r'not needed a change in the almost three weeks since. The follow-up '
        r'work on screen sharing went into xdph.conf instead, which is '
        r'the right division: this file says who answers, that file says '
        r'how the answer behaves.'),
    ...sec('limits'),
    ...pt('#', 'one desktop name',
        'the file is named for Hyprland only. A different compositor '
        'would need its own <name>-portals.conf.'),
    ...pt('#', 'untested by construction',
        'there is no check that the backends named here are installed. '
        'The package lists make it likely; nothing enforces it.'),
    ...pt('#', 'gtk as the default',
        'a missing GTK backend would presumably leave every non-listed '
        'interface without an answer, because the default points at it.'),
    blank,
    link('→ github.com/XNash/xyno-arch', 'https://github.com/XNash/xyno-arch'),
  ],
);
