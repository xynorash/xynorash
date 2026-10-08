import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/home/.config/gtk-4.0/settings.ini',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'settings.ini (gtk-4.0) — the same four lines, one major version later'),
    cm('#', 'identical to the GTK 3 file, with one key that GTK 4 has since deprecated'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role',     'GTK 4 user settings: font, dark preference, cursor '
    'theme'),
    kv('language', 'INI (a GLib key file with one [Settings] group)'),
    kv('size', '5 lines, 2 commits (2026-09-19, 2026-10-08)'),
    kv('twin', 'gtk-3.0/settings.ini, the identical git blob'),
    kv('git blob', 'same for both files at every commit'),
    ...sec('the whole file'),
    ...code('ini', 'home/.config/gtk-4.0/settings.ini · all of it', r'''
[Settings]
gtk-font-name = JetBrainsMono Nerd Font 8
gtk-application-prefer-dark-theme = 1
gtk-cursor-theme-name = DotClick
gtk-cursor-theme-size = 32'''),
    ...para('#',
        'Byte for byte this is the file in gtk-3.0: git stores the '
        'two as the same object at every commit (79cc9e6 before the '
        'cursor commit on 2026-10-08, 8a8cbc3 after it). The '
        'interesting questions about it are therefore not what the '
        'lines say (the GTK 3 page covers the font, the cursor and '
        'the portals) but why a second copy exists and what has '
        'changed under the one key that GTK 4 treats differently.'),
    ...sec('why a second, identical copy'),
    ...para('#',
        'GTK reads settings.ini from a directory named for its major '
        'version. GTK 4’s reference lists /etc/gtk-4.0, '
        'XDG_CONFIG_DIRS and XDG_CONFIG_HOME as the places, and a GTK '
        '4 program never looks in gtk-3.0. A desktop that wants one '
        'font and one cursor for both toolkits has to say it in both '
        'directories, and the author did, from the first commit '
        '(d552dfd, 2026-09-19) through the cursor addition.'),
    ...para('#',
        'The duplication is a small, honest cost, and the repo shows '
        'why it was not removed. The obvious fix is one real file and '
        'one symlink to it, but install.sh creates links with "find '
        '-type f", which does not match symlinks, so a symlink inside '
        'home/ would be skipped on install. The alternative, a second '
        'regular file with the same contents, needs only discipline. '
        'The discipline has held for 19 days and two commits; nothing '
        'enforces it.'),
    ...sec('the key GTK 4 deprecated'),
    ...pt('#',
        'gtk-application-prefer-dark-theme = 1',
        'the GTK 4 reference marks the property "Deprecated since: '
        '4.20" and points to "GtkCssProvider properties instead". Its '
        'description is unchanged from GTK 3: "if a GTK theme '
        'includes a dark variant, it will be used instead of the '
        'configured theme".'),
    ...para('#',
        'The same reference page lists the modern pieces. A new '
        'settings property, gtk-interface-color-scheme (available '
        'since 4.20), "communicates the system-wide preference", and '
        'the colour scheme actually applied to CSS is a property of '
        'GtkCssProvider, prefers-color-scheme. The old boolean was a '
        'request to the theme; the new pair separates what the system '
        'prefers from what the stylesheet does about it.'),
    blank,
    ...para('#',
        'What this means here depends on a fact the repo does not '
        'record: the installed GTK version. If it is older than 4.20, '
        'this line is the documented route. If it is newer, the '
        'property should still be honoured until it is removed, but '
        'it is no longer the documented way and something else may be '
        'deciding. There is a candidate. noctalia’s GTK templates, by '
        'the upstream docs, run an apply.sh that syncs '
        'org.gnome.desktop.interface.color-scheme alongside the '
        'theme, and that GSettings key is how GNOME-style desktops '
        'tell GTK 4 and libadwaita programs to go dark. On that '
        'reading the line is a belt-and-braces fallback and the '
        'template does the real work. The commit history cannot '
        'settle it: the line has not changed since the initial '
        'commit.'),
    ...sec('GTK 4 and the tools that fight over it'),
    ...code('toml', 'home/.config/noctalia/config.toml · which templates noctalia is told to run', r'''
builtin_ids = [ "hyprland", "ghostty", "gtk3", "gtk4" ]'''),
    ...para('#',
        '"gtk4" in that list is one of the more contested names in '
        'the whole setup. noctalia’s docs include a warning in the '
        'GTK section: when using the nwg-look tool, the GTK4 box must '
        'be unchecked, because "leaving GTK4 checked can prevent GTK4 '
        'applications from using Noctalia’s color scheme", and if a '
        'custom GTK 4 theme was applied before you may have to clear '
        'it first. In other words more than one tool wants to write '
        'the gtk-4.0 directory, and when two do the result is a '
        'stylesheet fight that is hard to see.'),
    ...para('#',
        'That explains the repo’s restraint. The only file it tracks '
        'in gtk-4.0 is this settings.ini, which holds nothing a '
        'theming tool would want to rewrite. The generated side '
        '(noctalia.css, imported into gtk.css) is left to noctalia '
        'and does not appear in git. A settings file that only says '
        'font, flag and cursor can sit beside a generated stylesheet '
        'without either touching the other.'),
    ...sec('cursor and font in GTK 4'),
    ...para('#',
        'The cursor lines are the same as in GTK 3 and for the same '
        'reason: commit 6e87679 added "gtk-cursor-theme-name = '
        'DotClick" and "gtk-cursor-theme-size = 32" to both files on '
        '2026-10-08, alongside XCURSOR_THEME and XCURSOR_SIZE in '
        'hyprland.lua and the DotClick theme folder. The GTK 4 '
        'reference defaults the theme name to NULL and the size to 0, '
        '"use the default size". Where GTK 4 reads the toolkit '
        'setting and where it honours the environment variables is '
        'not something the repo tests; setting both to the same value '
        'sidesteps the question.'),
    ...para('#',
        'gtk-font-name takes a Pango font description. GTK uses the '
        'family and the size in it, and the GTK 4 reference gives '
        '"Sans 10" as the built-in default. The file’s "JetBrainsMono '
        'Nerd Font 8" is the family from noctalia/config.toml '
        '(font_family) at the same small scale as the terminal and '
        'the bar.'),
    ...sec('history'),
    ...pt('#',
        '2026-09-19 18:28 (d552dfd)',
        'initial commit: the font and the dark preference.'),
    ...pt('#',
        '2026-10-08 11:53 (6e87679)',
        'cursor theme and size. One commit touches both GTK '
        'directories and the cursor theme at once.'),
    ...sec('limits'),
    ...pt('#',
        'version unknown',
        'the repo does not pin or record the GTK 4 version, so '
        'whether the dark flag is live or merely tolerated cannot be '
        'told from the files.'),
    ...pt('#',
        'adw-gtk3',
        'the GTK templates are documented as driving the adw-gtk3 '
        'theme, and no package list names it. See the noctalia config '
        'page for the same open question.'),
    ...pt('#',
        'nothing checks the twins',
        'a one-line test comparing the two files would turn an '
        'unenforced habit into a rule. There is no CI in the repo to '
        'run one; for a five-line file that is a proportionate gap.'),
    blank,
    link('→ github.com/xynorash/xyno-arch', 'https://github.com/xynorash/xyno-arch'),
  ],
);
