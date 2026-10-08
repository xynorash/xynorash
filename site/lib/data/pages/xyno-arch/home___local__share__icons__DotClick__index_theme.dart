import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/home/.local/share/icons/DotClick/index.theme',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'index.theme — a cursor theme in four lines'),
    cm('#', 'the label on a box of 80 binary files'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'registers the DotClick cursor theme with the desktop'),
    kv('language', 'freedesktop icon theme descriptor (ini)'),
    kv('size', '4 lines, 109 bytes, next to 80 cursor files'),
    kv('history', 'one commit: 6e87679 (2026-10-08), the newest theme in the repo'),
    kv('checked here', 'parsed all 80 cursor files, rendered two, checked the names'),

    ...sec('what this file is for'),
    ...para(
        '#',
        r'A cursor theme is a directory with a descriptor and a '
        r'cursors/ folder. The folder holds the pictures; the '
        r'descriptor gives the theme a name, a credit and a fallback. '
        r'Everything that matters visually is in the 80 binary '
        r'files beside it. Everything that matters to whether the '
        r'desktop can find and use them is in these four lines.'),
    ...code('ini', 'home/.local/share/icons/DotClick/index.theme', r'''
[Icon Theme]
Name=DotClick
Comment=DotClick by proviceunity, converted from Windows cursors
Inherits=Adwaita'''),
    ...pt(
        '#',
        '[Icon Theme]',
        r'the section header the freedesktop specification '
        r'requires. Without it the directory is not recognised as a '
        r'theme.'),
    ...pt(
        '#',
        'Name=DotClick',
        r'the identifier that other files refer to. Three places '
        r'in this repo do: see “three places name it” below.'),
    ...pt(
        '#',
        'Comment=...',
        r'the attribution. It names the pack’s author, '
        r'proviceunity, and says how the files came to be: '
        r'“converted from Windows cursors”. The converter is not '
        r'named anywhere in the repo.'),
    ...pt(
        '#',
        'Inherits=Adwaita',
        r'the fallback chain. Any cursor name that DotClick does not '
        r'supply is looked up in Adwaita instead, GTK’s own default.'),
    blank,
    ...para(
        '#',
        r'There is no Directories line, which a full icon theme '
        r'would have. A cursor-only theme does not need one; '
        r'libXcursor looks in cursors/ by file name.'),

    ...sec('what is in the folder'),
    ...para(
        '#',
        r'I parsed every file in cursors/ as an Xcursor image '
        r'file (the format begins with the four bytes “Xcur” and '
        r'a table of contents). The inventory is more modest than '
        r'80 files suggests:'),
    ...pt(
        '#',
        '80 names, 15 distinct images',
        r'an md5 over the files finds 15 different contents. All '
        r'80 are separate regular files in git (mode 100644), not '
        r'symlinks, so every alias is a full copy.'),
    ...pt(
        '#',
        'one size',
        r'every image is 32 by 32 pixels. Each file has a single '
        r'nominal size.'),
    ...pt(
        '#',
        '13 static, 2 animated',
        r'the animated ones have 23 frames at 33 ms each, about '
        r'0.76 seconds per loop. They serve five names: half-busy, '
        r'left_ptr_watch, progress, wait and watch.'),
    ...pt(
        '#',
        '788,640 bytes stored, 244,736 distinct',
        r'75 files of 4,160 bytes and 5 of 95,328, against 13 and 2 '
        r'distinct ones. The duplication is a factor of about 3.2. '
        r'It costs little here, and it is the price of copying '
        r'instead of linking.'),
    blank,
    ...para(
        '#',
        r'The sizes are not arbitrary and they check out. A static '
        r'file of 4,160 bytes is a 16 byte file header, a 12 byte '
        r'table-of-contents entry, a 36 byte image header and '
        r'32 x 32 x 4 = 4,096 bytes of pixels. The animated files '
        r'are 16 + 23 x 12 + 23 x (36 + 4,096) = 95,328 bytes. '
        r'Every file matches this exactly, so each one is a '
        r'well-formed Xcursor with no extra chunks.'),

    ...sec('the aliases'),
    ...para(
        '#',
        r'Why 80 names for 15 pictures? Because toolkits ask for a '
        r'cursor by name and disagree about the names. Old X11 '
        r'applications ask for left_ptr, hand2, xterm and watch. '
        r'Modern toolkits ask for the CSS names: default, pointer, '
        r'text, wait, not-allowed. The conversion filled in every '
        r'spelling. The biggest groups are:'),
    blank,
    plain('  11  top_side bottom_side n-resize s-resize ns-resize ...'),
    plain('  10  left_side right_side e-resize w-resize ew-resize ...'),
    plain('   8  grab grabbing openhand closedhand fleur move ...'),
    plain('   7  hand hand1 hand2 pointer pointing_hand link alias'),
    plain('   7  nw-resize se-resize nwse-resize size_fdiag ...'),
    plain('   7  ne-resize sw-resize nesw-resize size_bdiag ...'),
    plain('   5  arrow default left_arrow left_ptr top_left_arrow'),
    plain('   5  circle crossed_circle forbidden no-drop not-allowed'),
    plain('   3  ibeam text xterm'),
    blank,
    ...para(
        '#',
        r'The grouping is the design in outline: the theme has '
        r'one arrow, one hand, one forbidden sign, one vertical and '
        r'one horizontal resize, two diagonals, one I-beam, one '
        r'cross, one help, one pencil, two busy animations and a '
        r'small up arrow (center_ptr, up_arrow). One image serves '
        r'grab, grabbing, move and the four-way scroll together. '
        r'The hand and the arrow are different files, but they '
        r'render alike at the resolution of the drawing below.'),

    ...sec('what it looks like'),
    ...para(
        '#',
        r'I decoded the pixels of the default cursor and drew its '
        r'alpha channel as text. The name DotClick is literal: '
        r'a dot. # is nearly opaque, + is partly transparent, '
        r'. is a faint halo and H marks the hotspot, the pixel '
        r'that counts as the click point:'),
    blank,
    plain('                ....'),
    plain('             ..........'),
    plain('           ..............'),
    plain('          ................'),
    plain('          ................'),
    plain('         ......+####+......'),
    plain('         .....##++++##.....'),
    plain('        .....+#+####+#+....'),
    plain('        .....#+######+#.....'),
    plain('        ....+#+##H###+#.....'),
    plain('        ....+#+######+#.....'),
    plain('        .....#+######+#.....'),
    plain('        .....+#+####+#+....'),
    plain('         .....##++++##.....'),
    plain('         ......+####+......'),
    plain('          ................'),
    plain('          ................'),
    plain('           ..............'),
    plain('             ..........'),
    plain('                ....'),
    blank,
    ...para(
        '#',
        r'The hotspot is at (15, 15) of 32, the middle of the dot. '
        r'That is a deliberate property of a symmetric pointer: the '
        r'click lands where the eye sees the centre. Most of the '
        r'other images keep a hotspot near the middle too, for example '
        r'(16, 15) for the resize arrows and (14, 15) for the grab '
        r'hand. The exceptions follow their shapes: the I-beam '
        r'(text, ibeam, xterm) has its hotspot at (4, 8), and the '
        r'forbidden family at (3, 2). The I-beam is 46 non-transparent '
        r'pixels, a thin vertical bar with serifs, so the text '
        r'cursor is a bar and not a dot.'),

    ...sec('three places name it'),
    ...para(
        '#',
        r'Installing the files is half of using a theme. Programs '
        r'must also be told its name, and two families of programs '
        r'read it from two different places. The commit that added '
        r'the theme, 6e87679 at 11:53 on 2026-10-08, changed the GTK '
        r'side:'),
    ...code('ini', 'home/.config/gtk-3.0/settings.ini · cursor', r'''
gtk-cursor-theme-name = DotClick
gtk-cursor-theme-size = 32'''),
    ...para(
        '#',
        r'The same two lines are in gtk-4.0/settings.ini. The '
        r'other family is everything that uses the X cursor '
        r'library, including XWayland clients and the compositor. '
        r'It reads environment variables:'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · the environment', r'''
hl.env("XCURSOR_THEME", "DotClick")
hl.env("XCURSOR_SIZE", "32")'''),
    ...para(
        '#',
        r'Here history is a little out of step with the message. '
        r'The commit says “for Hyprland and GTK”, but its diff '
        r'touches only the two GTK files and the theme; the '
        r'XCURSOR lines arrived in the next commit, 2f34af7, whose '
        r'subject is about WinApps and whose same-second timestamp '
        r'suggests the three latest commits were made together. A '
        r'search of the history for the string XCURSOR_THEME finds '
        r'only that one. Nothing is wrong with the result, but '
        r'anyone reading the log for “how did the cursor change” '
        r'has to look one commit later.'),
    blank,
    ...para(
        '#',
        r'The size 32 appears twice more, once per family, and it '
        r'matches the single size inside every file. That alignment '
        r'matters: with only one nominal size available the library '
        r'cannot choose a better fit, so a different configured '
        r'size would mean scaling. Keeping all of them at 32 avoids '
        r'it. The cost is four places to edit to rename the theme.'),

    ...sec('the fallback, and the gaps it covers'),
    ...para(
        '#',
        r'DotClick supplies 80 names. The CSS specification '
        r'defines 34 cursor keywords; I checked the list against '
        r'the folder and 28 are covered. The six that are not are '
        r'context-menu, cell, vertical-text, copy, zoom-in and '
        r'zoom-out. For those, a program asks the theme, finds '
        r'nothing, and the Inherits line sends the lookup to '
        r'Adwaita. Without that line the search for those six '
        r'would end inside DotClick.'),
    blank,
    ...para(
        '#',
        r'One thing I could not see: whether Adwaita is installed '
        r'on the machine. packages/pacman.txt does not name an '
        r'Adwaita package. It is a common dependency of GTK '
        r'software, and the GTK portal is in the list, so I expect '
        r'it is present, but the repo does not guarantee it. I '
        r'also could not test the lookup on a live desktop.'),

    ...sec('how it reaches the machine'),
    ...para(
        '#',
        r'install.sh links every file under home/ individually, '
        r'so on a throw-away HOME it created 81 symlinks under '
        r'~/.local/share/icons/DotClick, one for index.theme and one '
        r'for each cursor. That directory is on the standard icon '
        r'search path, which is why no extra configuration is '
        r'needed. The 80 binary files are tracked as ordinary '
        r'blobs; their addition is why the 6e87679 diff stat is '
        r'dominated by lines saying “Bin 0 -> 4160 bytes”.'),

    ...sec('attribution and limits'),
    ...pt(
        '#',
        'credit',
        r'the Comment line is the repo’s only record of where the '
        r'pack comes from. There is no licence file for it, and '
        r'a Windows cursor pack carries its own terms; I do not '
        r'know them.'),
    ...pt(
        '#',
        'one resolution',
        r'a single 32-pixel image per name would have to be '
        r'scaled on a high-density display. hyprland.lua pins the '
        r'monitor, a Dell E2314H, to scale 1, so here the images '
        r'are used at their native size.'),
    ...pt(
        '#',
        'copies, not links',
        r'80 files for 15 images works, but a fix to one picture '
        r'must be repeated for every alias.'),
    ...pt(
        '#',
        'not rendered live',
        r'I read the files; I did not see them drawn by a '
        r'compositor.'),

    ...sec('lessons'),
    ...para(
        '#',
        r'A tiny text file can carry an outsized share of the '
        r'correctness: the name, the credit and the fallback all '
        r'live here, and the fallback is what turns a theme that '
        r'covers 28 of 34 modern names into one that never leaves a '
        r'gap. Check a converted asset by decoding it, not by '
        r'trusting the converter; 15 distinct images in 80 files '
        r'is exactly what the page of aliases predicts.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
