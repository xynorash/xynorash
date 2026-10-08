import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/home/.config/gtk-3.0/settings.ini',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'settings.ini (gtk-3.0) — four preferences for every GTK 3 program'),
    cm('#', 'font, dark preference and cursor, in the file GTK reads when nothing else answers'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role',     'GTK 3 user settings: font, dark preference, cursor '
    'theme'),
    kv('language', 'INI (a GLib key file with one [Settings] group)'),
    kv('size', '5 lines, 2 commits (2026-09-19, 2026-10-08)'),
    kv('twin', 'gtk-4.0/settings.ini, the identical git blob'),
    kv('installed', 'symlink to ~/.config/gtk-3.0/settings.ini'),
    ...sec('the whole file'),
    ...code('ini', 'home/.config/gtk-3.0/settings.ini · all of it', r'''
[Settings]
gtk-font-name = JetBrainsMono Nerd Font 8
gtk-application-prefer-dark-theme = 1
gtk-cursor-theme-name = DotClick
gtk-cursor-theme-size = 32'''),
    ...para('#',
        'Five lines, and each one answers a question that would '
        'otherwise be answered by a default the desktop does not '
        'control. What font should a dialog use? Should this program '
        'prefer a dark variant? Which pointer shape set, at what '
        'size? GTK 3 reads the file when nothing more specific has '
        'already answered, and the answer here is the same one the '
        'rest of the desktop gives.'),
    ...sec('key by key'),
    ...pt('#',
        'gtk-font-name = JetBrainsMono Nerd Font 8',
        'a Pango font description. GTK’s reference says it "uses the '
        'family name and size from this string", and the GTK 4 '
        'reference gives the default as "Sans 10". So this line swaps '
        'the family for the one the shell and terminal already use '
        'and drops two points. Size 8 belongs to a family of small '
        'sizes: the terminal is 7.5 and the bar text runs at 0.8 of '
        'normal.'),
    ...pt('#',
        'gtk-application-prefer-dark-theme = 1',
        'the GTK 3 documentation lists this property as available '
        'since 3.0 and not deprecated: "if a GTK+ theme includes a '
        'dark variant, it will be used instead of the configured '
        'theme". It does nothing for a theme with no dark variant, '
        'which is why colours are not left to it (see below). The GTK '
        '4 twin has a different story.'),
    ...pt('#',
        'gtk-cursor-theme-name = DotClick',
        'the name of a cursor theme folder. DotClick lives in this '
        'repo under home/.local/share/icons/DotClick. The GTK '
        'reference gives the default as NULL, meaning GTK picks its '
        'own.'),
    ...pt('#',
        'gtk-cursor-theme-size = 32',
        'pixels. The reference says 0 means "use the default size". '
        '32 was chosen in the same commit as the cursor theme '
        '(below).'),
    ...sec('how GTK finds this file'),
    ...para('#',
        'The reference for GtkSettings spells out the order of '
        'authority. Settings are normally shared through a settings '
        'portal on Linux desktops or an XSettings manager on X11. "In '
        'the absence of these sharing mechanisms", GTK reads '
        'settings.ini from /etc/gtk-4.0, XDG_CONFIG_DIRS and '
        'XDG_CONFIG_HOME, the last being ~/.config in practice. (The '
        'quotation is from the GTK 4 reference; GTK 3 uses the same '
        'idea in the directory gtk-3.0.) Themes can ship their own '
        'defaults beside their gtk.css, and a program can override '
        'anything at run time.'),
    ...para('#',
        'Two practical consequences. First, this file is a fallback, '
        'not a command: if a portal or an XSettings manager answers '
        'first, that answer is used, and the repo does not record a '
        'test of which one GTK 3 programs actually see here. Second, '
        'because the file is the last resort it is the right place '
        'for things every program should agree on and nobody wants to '
        'depend on a running daemon for, which is exactly the font '
        'and cursor.'),
    ...sec('colours are somewhere else on purpose'),
    ...para('#',
        'Notice what the file does not contain: a theme name or a '
        'colour. Those come from noctalia. noctalia/config.toml '
        'enables the "gtk3" and "gtk4" built-in templates, and the '
        'upstream docs describe what they do: write a noctalia.css, '
        'then run a shipped apply.sh that imports it into gtk.css and '
        'syncs the adw-gtk3 theme and the GNOME color-scheme setting. '
        'So the division of labour is: this file for preferences that '
        'never change with the palette, generated CSS for everything '
        'that does. That split is why switching theme needs no edit '
        'here and why a regenerated palette can never clobber the '
        'font.'),
    ...para('#',
        'One loose end belongs on record. The docs name adw-gtk3 as '
        'the theme those templates drive, and neither '
        'packages/pacman.txt nor packages/aur.txt lists '
        'adw-gtk-theme. The repo does not show where it comes from, '
        'or whether colours reach GTK 3 programs without it.'),
    ...sec('the cursor: set in three places that must agree'),
    ...para('#',
        'The commit that added the last two lines is 6e87679 on '
        '2026-10-08, titled "Cursor: DotClick theme (converted from '
        'the Windows pack) for Hyprland and GTK". Its title lists two '
        'consumers, and the diff shows three places to keep in step.'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · the compositor side', r'''
hl.env("XCURSOR_THEME", "DotClick")
hl.env("XCURSOR_SIZE", "32")'''),
    ...pt('#',
        'hyprland.lua',
        'XCURSOR_THEME and XCURSOR_SIZE are the environment variables '
        'that toolkits using the classic Xcursor library read. Every '
        'program Hyprland starts inherits them, GTK or not, which '
        'makes them the general answer.'),
    ...pt('#',
        'this file',
        'the GTK-specific answer, read by GTK 3 programs directly, in '
        'the form GTK documents. Same theme, same 32.'),
    ...pt('#',
        'the theme itself',
        'a folder with cursors/ and an index.theme:'),
    ...code('ini', 'home/.local/share/icons/DotClick/index.theme · all of it', r'''
[Icon Theme]
Name=DotClick
Comment=DotClick by proviceunity, converted from Windows cursors
Inherits=Adwaita'''),
    ...para('#',
        'The comment records provenance: the cursors are the work of '
        '"proviceunity", converted from a Windows pack, and the repo '
        'credits them in the file that carries the theme. '
        '"Inherits=Adwaita" means any cursor name the converted set '
        'does not provide falls back to Adwaita. The set tracked in '
        'git is 80 files in cursors/ with only 15 distinct contents '
        '(75 files of 4,160 bytes and five of 95,328 bytes: '
        'half-busy, left_ptr_watch, progress, wait and watch, which '
        'look like the animated busy cursors). Each X11 cursor name '
        'is its own regular file here, so one image appears under '
        'many names; n-resize, ns-resize, row-resize and size_ver, '
        'for example, are byte-identical.'),
    ...para('#',
        'When two settings could disagree, the safe design is to make '
        'them agree, and this commit does: the same name and the same '
        'size in both places. The repo does not test which source '
        'wins if they diverge; keeping them equal sidesteps the '
        'question.'),
    ...sec('who actually reads it here'),
    ...para('#',
        'GTK 3 programs, naturally, but one consumer is visible in '
        'the repo. hyprland-portals.conf routes several desktop '
        'portals to the GTK backend, and xdg-desktop-portal-gtk is in '
        'packages/pacman.txt:'),
    ...code('ini', 'home/.config/xdg-desktop-portal/hyprland-portals.conf · routing', r'''
[preferred]
default=gtk;
org.freedesktop.impl.portal.Access=gtk;
org.freedesktop.impl.portal.Notification=gtk;
org.freedesktop.impl.portal.FileChooser=gtk;
org.freedesktop.impl.portal.ScreenCast=hyprland;
org.freedesktop.impl.portal.Screenshot=hyprland;
org.freedesktop.impl.portal.Secret=gnome-keyring;'''),
    ...para('#',
        'The file chooser and access dialogs that applications '
        'request through the portal are drawn by that GTK backend, so '
        'they take their font, dark preference and pointer from files '
        'like this one. Which major version of GTK the backend links '
        'is not recorded in the repo, which is why both directories '
        'carry the settings.'),
    ...sec('history'),
    ...pt('#',
        '2026-09-19 18:28 (d552dfd)',
        'created in the initial commit with the font and the dark '
        'preference; three lines.'),
    ...pt('#',
        '2026-10-08 11:53 (6e87679)',
        'cursor theme name and size added in the same commit that '
        'adds the DotClick theme and, in hyprland.lua, the two '
        'XCURSOR variables. Nothing else has changed.'),
    ...sec('limits'),
    ...pt('#',
        'two copies',
        'gtk-3.0 and gtk-4.0 are separate files that must be edited '
        'together; today they are the same git blob. The obvious '
        'cure, a symlink between them, would not survive install.sh, '
        'whose "find -type f" does not match symlinks.'),
    ...pt('#',
        'no theme name',
        'the file does not pin gtk-theme-name; that is left to '
        'noctalia’s apply.sh by the docs’ account. If the template '
        'were disabled, nothing in this file would choose a theme.'),
    ...pt('#',
        'unverified end to end',
        'nothing in the repo records a check of the result in a '
        'running GTK 3 program. The reading above is from GTK’s '
        'reference and the commit history.'),
    blank,
    link('→ github.com/xynorash/xyno-arch', 'https://github.com/xynorash/xyno-arch'),
  ],
);
