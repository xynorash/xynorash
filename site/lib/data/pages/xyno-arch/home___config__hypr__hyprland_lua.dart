import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/home/.config/hypr/hyprland.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', 'hyprland.lua — the whole compositor in one Lua file'),
    cm('--', 'display, input, keys, gaming hooks, and a tamer for Windows apps'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv('role', 'the Hyprland configuration: everything the compositor is told'),
    kv('language', 'Lua, written against Hyprland’s hl.* config API'),
    kv('size', '243 lines, 56 of them comments, 46 hl.bind calls (62 binds at runtime)'),
    kv('history', '6 commits, 2026-09-19 to 2026-10-08; 207 lines at the start, 0 lines ever deleted'),
    kv('generated sibling', 'noctalia.lua, gitignored, required on the last line'),
    kv('helpers it launches', 'gamemode-attach, notification-focus, keybinds.sh'),
    ...sec('why this file exists'),
    ...para('--',
        r'xyno-arch is a desktop you can rebuild from a git clone, and '
        r'the compositor is the part everything else hangs off: the '
        r'monitor, the keyboard, which program starts at login, how a '
        r'window is drawn and which key does what. Hyprland has two '
        r'configuration formats, and the file’s own second line says '
        r'which one this is: "Lua config. hyprlang (.conf) is deprecated '
        r'as of Hyprland 0.55." The README repeats the note. So the '
        r'whole desktop policy lives in a program rather than in a list '
        r'of settings, and that matters for two sections below, where '
        r'the file uses real functions and event handlers.'),
    blank,
    ...para('--',
        r'The header also names the look it is chasing, "Omarchy '
        r'Quattro-style", and the same name recurs in the animation '
        r'curve, in the SUPER+F commit message and throughout '
        r'config.toml. Omarchy is the reference; this file is one '
        r'person’s translation of it onto an older NVIDIA machine.'),
    blank,
    ...para('--',
        r'Nearly a quarter of the file, 56 of 243 lines, is comments, '
        r'and most '
        r'of them give a reason rather than a description. That is the '
        r'quality that makes the rest worth reading: nearly every '
        r'non-obvious value comes with the sentence that justifies it, '
        r'and the commit messages carry the rest. This page leans on '
        r'both, and says plainly where neither speaks.'),
    ...sec('a map of the file'),
    ...pt('--', 'lines 1-5',
        'header and the one local variable, mod = "SUPER".'),
    ...pt('--', 'lines 7-14, display',
        'one monitor, pinned to 1920x1080 at 60 Hz and scale 1.'),
    ...pt('--', 'lines 16-31, environment',
        'twelve hl.env calls: session identity, Wayland for every '
        'toolkit, the cursor theme.'),
    ...pt('--', 'lines 33-39, autostart',
        'noctalia (the shell) and notification-focus.'),
    ...pt('--', 'lines 41-98, layout and look',
        'one big hl.config: gaps, borders, dwindle, rounding, blur, '
        'shadow, misc, keyboard layouts.'),
    ...pt('--', 'lines 100-107, animations',
        'two bezier curves, four animated leaves.'),
    ...pt('--', 'lines 109-180, keybinds',
        'apps, help, focus, move, window state, workspaces, mouse, '
        'screenshots, audio and media.'),
    ...pt('--', 'lines 182-198, gaming performance',
        'direct scanout, new render scheduling, tearing, and an '
        'immediate-present rule for Steam games.'),
    ...pt('--', 'lines 200-209, GameMode',
        'a window.open hook that attaches a game process to GameMode.'),
    ...pt('--', 'lines 211-218, window rules',
        'the floating cheat sheet.'),
    ...pt('--', 'lines 220-241, WinApps',
        'a handler and three event hooks that float Windows apps and '
        'hide a PowerShell helper.'),
    ...pt('--', 'line 243',
        'require("noctalia").apply_theme(), the generated colours.'),
    ...sec('display: one monitor, pinned'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · display', r'''
-- ─── Display ─────────────────────────────────────────────────────────────
-- Dell E2314H. Pinned to 1x so the scale can't drift.
hl.monitor({
    output   = "HDMI-A-1",
    mode     = "1920x1080@60",
    position = "0x0",
    scale    = 1,
})'''),
    ...para('--',
        r'Everything here is explicit. The connector (HDMI-A-1), the mode '
        r'and refresh rate, the position and the scale are all spelled '
        r'out, where Hyprland would happily pick preferred values for '
        r'a monitor it recognised. The comment gives the reason for the '
        r'last one: pinned to 1x "so the scale can’t drift". The README '
        r'states the target as "1080p @ 60 Hz", and the noctalia '
        r'config.toml has a matching line, ui_scale = 1.0, annotated '
        r'"matches the pinned 1.0 Wayland output scale". So the 1x '
        r'decision is shared across two files, and this page is where '
        r'it starts.'),
    blank,
    ...para('--',
        r'The cost of precision is portability. The rule names one '
        r'physical connector. On a machine where the screen hangs off '
        r'another port the rule would describe an output that does not '
        r'exist; what Hyprland does then is untested here, but the '
        r'README at least warns that the config is personal (absolute '
        r'paths, one username).'),
    ...sec('environment: Wayland first, X11 where it has to be'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · environment', r'''
-- Wayland-first for every toolkit. DISPLAY is left alone: the Steam client
-- is X11-only and needs XWayland.
hl.env("XDG_CONFIG_HOME", "/home/xynorash/.config")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("GDK_BACKEND", "wayland")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")
hl.env("XCURSOR_THEME", "DotClick")
hl.env("XCURSOR_SIZE", "32")
-- SDL_VIDEODRIVER deliberately unset — forcing it breaks Steam titles.'''),
    ...para('--',
        r'hl.env sets a variable for the compositor and the programs it '
        r'starts. The twelve calls fall into four groups.'),
    ...pt('--', 'who we are (lines 19-22)',
        'XDG_CONFIG_HOME, XDG_CURRENT_DESKTOP, XDG_SESSION_TYPE and '
        'XDG_SESSION_DESKTOP. XDG_CURRENT_DESKTOP is not decorative: '
        'xdg-desktop-portal derives the name of its routing file from '
        'it, so the value "Hyprland" is what makes '
        'xdg-desktop-portal/hyprland-portals.conf apply (see that '
        'page). XDG_CONFIG_HOME is what keybinds.sh reads to find '
        'this very file.'),
    ...pt('--', 'toolkits told to use Wayland (23-27)',
        'GDK, Qt, Clutter, Mozilla and Electron each get their own '
        'switch, because each reads a different variable.'),
    ...pt('--', 'a Java workaround (28)',
        '_JAVA_AWT_WM_NONREPARENTING is the long-standing hint that '
        'stops Java GUI toolkits from assuming a reparenting window '
        'manager. This repo has JetBrains Toolbox bound to SUPER+ALT+J, '
        'which is presumably why it is here; no comment says so.'),
    ...pt('--', 'the cursor (29-30)',
        'XCURSOR_THEME = DotClick and XCURSOR_SIZE = 32. The theme is '
        'in the repo under home/.local/share/icons/DotClick, and its '
        'index.theme says "DotClick by proviceunity, converted from '
        'Windows cursors". GTK gets the same pair from the settings.ini '
        'files (gtk-cursor-theme-name = DotClick, gtk-cursor-theme-size '
        '= 32), so Wayland-native and X11 clients agree.'),
    blank,
    ...para('--',
        r'Two comments mark things that are deliberately not set. The '
        r'first, above the block, says DISPLAY is left alone because '
        r'"the Steam client is X11-only and needs XWayland". The X11 '
        r'apps on this desktop are the Steam client and, as we will '
        r'see, the WinApps windows, so XWayland has to stay in play. '
        r'The second comment, at the bottom, is an explicit '
        r'non-decision: "SDL_VIDEODRIVER deliberately unset — forcing '
        r'it breaks Steam titles." A variable that is absent can look '
        r'like an oversight; this line makes the absence a recorded '
        r'choice, which is how a future edit avoids undoing it.'),
    blank,
    ...para('--',
        r'A bit of history that the commit log makes visible: the last '
        r'two lines, the cursor, were not added in the commit titled '
        r'"Cursor: DotClick theme (converted from the Windows pack) for '
        r'Hyprland and GTK" (6e87679). That commit touched the GTK '
        r'settings and added the icon theme, and nothing in the '
        r'hypr directory. The two hl.env lines arrived in the next '
        r'commit, 2f34af7, whose title is about WinApps. All three '
        r'commits carry the same timestamp, 2026-10-08 11:53:16 +0300, '
        r'so they were evidently created in one batch from a single '
        r'working tree, and the split between them was not perfectly '
        r'clean.'),
    ...sec('autostart and the notification story'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · autostart', r'''
-- ─── Autostart ───────────────────────────────────────────────────────────
hl.on("hyprland.start", function()
    hl.exec_cmd("noctalia")
    -- Notification clicks land on the sending app even if it ignores the
    -- activation token.
    hl.exec_cmd("/home/xynorash/.local/bin/notification-focus")
end)'''),
    ...para('--',
        r'The session has exactly two things to start. noctalia is the '
        r'shell, and the README lists what it provides: bar, launcher, '
        r'notifications, lock screen, OSD. Every shell action in this '
        r'file is a call back into it: 15 of the 46 hl.bind lines run '
        r'"noctalia msg ...", for the launcher, clipboard history, '
        r'lock, session menu, screenshots, volume and media keys.'),
    blank,
    ...para('--',
        r'The second line is the interesting one, and it has a twin '
        r'in the look-and-feel block. The goal, from the commit '
        r'message of 0ae2015 ("Notification clicks jump to the sending '
        r'app’s window and workspace"), is that clicking a notification '
        r'takes you to the program that sent it. Two layers cooperate.'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · layer one, in misc', r'''
        -- Clicking a notification (toast or Control Center) hands the app an
        -- activation token; honour it so Hyprland jumps to that window.
        focus_on_activate        = true,'''),
    ...para('--',
        r'Layer one is Hyprland’s own mechanism. noctalia passes an '
        r'activation token with the click; an application that uses it '
        r'asks the compositor for focus, and focus_on_activate = true '
        r'tells Hyprland to grant it, switching workspace if needed. '
        r'Layer two exists because "not every app uses the token", '
        r'as the header of home/.local/bin/notification-focus puts it. '
        r'That script watches the D-Bus ActionInvoked signal, looks up '
        r'the sender in noctalia’s notification history, waits 0.4 '
        r'seconds to give the app a chance to raise itself, and if the '
        r'active window is still not the sender, focuses a window whose '
        r'class matches case-insensitively. The compositor-side half '
        r'is the single misc line above; the script-side half is the '
        r'exec_cmd. Neither is enough alone, and both were added in '
        r'the same commit.'),
    blank,
    ...para('--',
        r'One more detail: both launches use an absolute path, '
        r'/home/xynorash/.local/bin/... There are four such paths in the '
        r'file (lines 19, 38, 127 and 207), and the README admits it: '
        r'"Paths inside hyprland.lua ... are absolute. Adjust them for '
        r'another username." The reason is not written down. One '
        r'plausible cause is in .bashrc: it adds ~/.local/bin to PATH, '
        r'but only after an early return for non-interactive shells, so '
        r'a compositor started by greetd would not obviously see it. '
        r'That is an inference; how the session environment is built '
        r'was not traced.'),
    ...sec('layout and look'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · general, dwindle', r'''
hl.config({
    general = {
        layout           = "dwindle",
        gaps_in          = 5,
        gaps_out         = 10,
        border_size      = 2,
        resize_on_border = true,
        allow_tearing    = false,
    },

    dwindle = {
        preserve_split = true,
        smart_split    = false,
    },'''),
    ...para('--',
        r'The layout is dwindle: every new window splits the focused '
        r'one in half, alternating direction, so windows form a binary '
        r'tree. Gaps are 5 pixels between windows and 10 around the '
        r'screen edge, borders are 2 pixels, and resize_on_border lets '
        r'a drag on the border resize the window without a modifier key. '
        r'preserve_split = true keeps a split’s orientation when its '
        r'neighbours come and go, and smart_split = false turns off the '
        r'mode where the split direction follows the mouse position '
        r'inside the window; the manual control is the SUPER+S '
        r'"togglesplit" bind below, which the README describes as '
        r'"Flip split direction (dwindle)".'),
    blank,
    ...para('--',
        r'The allow_tearing = false line is worth a second look. It '
        r'is the default-off statement of a setting that a later block '
        r'sets to true (see "gaming performance"). The file executes '
        r'top to bottom, so the later value should be the effective '
        r'one; the earlier line works as the readable baseline from '
        r'which the gaming section deviates on purpose.'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · decoration', r'''
    decoration = {
        rounding         = 10,
        rounding_power   = 2,
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        blur = {
            enabled = true,
            size    = 6,
            passes  = 3,
        },

        shadow = {
            enabled      = true,
            range        = 30,
            render_power = 3,
        },
    },'''),
    ...para('--',
        r'Corners are rounded with a radius of 10, a number that '
        r'sits next to the noctalia bar’s radius of 14 and the '
        r'corner_radius_scale of 1.4 in config.toml: the shell and the '
        r'compositor both lean round, a stated Quattro trait ("Quattro '
        r'leans rounded across bar, menus, notifications and lock '
        r'screen"). Windows are fully opaque, active and inactive both '
        r'at 1.0, so no window is dimmed by focus. Blur runs 3 passes '
        r'at size 6 and the shadow has a range of 30. Blur only shows '
        r'through surfaces that are themselves translucent, and the '
        r'translucent ones here come from elsewhere: Ghostty is set to '
        r'background-opacity = 0.92 with background-blur = true, and the '
        r'noctalia bar to 0.96. That connection is a reading of '
        r'the two config files; neither file states it.'),
    blank,
    ...para('--',
        r'What is missing is colour. No border colour appears anywhere '
        r'in this file. The header says so in one line: "Colours come '
        r'from noctalia.lua, regenerated on every theme change." That '
        r'file is listed in .gitignore under the comment "Written by '
        r'noctalia’s theme templates, not by hand", and the last line of '
        r'hyprland.lua pulls it in. So the repo tracks that the '
        r'palette is Tokyo Night (config.toml: builtin = "Tokyo-Night", '
        r'with "hyprland" among the template ids) but not the '
        r'resulting hex values.'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · misc', r'''
    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,'''),
    ...para('--',
        r'The three misc lines remove everything Hyprland would draw '
        r'on its own: the logo, the splash text, and the default '
        r'wallpaper. The wallpaper belongs to noctalia, whose '
        r'config.toml points at ~/Pictures/Wallpapers/'
        r'starry-night-tokyo.png, the image install.sh copies out of '
        r'wallpapers/. '
        r'The fourth line in the block, focus_on_activate, is the '
        r'notification mechanism described above.'),
    ...sec('input'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · input', r'''
    input = {
        -- us + classic AZERTY (plain `fr`, the pre-AFNOR layout).
        -- Both Shift keys + either Alt cycle between them.
        kb_layout          = "us,fr",
        kb_options         = "grp:alt_shift_toggle",
        follow_mouse       = 1,
        numlock_by_default = true,
        touchpad = {
            natural_scroll = true,
        },
    },'''),
    ...para('--',
        r'Two layouts are loaded, US and the classic French AZERTY. The '
        r'comment is careful about which French: plain fr, "the '
        r'pre-AFNOR layout", not the newer standard. The switch is the '
        r'XKB option grp:alt_shift_toggle, and the README lists the '
        r'chord as "Alt + Shift: Switch keyboard layout (US / French '
        r'AZERTY)". follow_mouse = 1 means focus follows the pointer, '
        r'and numlock_by_default puts the numeric keypad in number mode '
        r'at start. One setting looks out of place: touchpad '
        r'natural_scroll on a desktop with a Ryzen 7 5800X and no '
        r'battery. It reads as harmless carry-over from the '
        r'reference setup; the repo does not say.'),
    blank,
    ...para('--',
        r'Two layouts mean a keysym can differ between them, and the '
        r'file records one consequence: the cheat sheet is bound twice, '
        r'to slash and to question, because "shift+slash reports as '
        r'`question` on some layouts". An aside that belongs to '
        r'another file: config.toml has a comment listing '
        r'keyboard_layout among the widgets omitted for a "single '
        r'layout", while its bar list does include keyboard_layout. '
        r'With two layouts configured here the widget makes sense; '
        r'the stale comment is outside this page.'),
    ...sec('animations'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · animations', r'''
hl.curve("omarchy", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })
hl.curve("snap",    { type = "bezier", points = { {0.2, 1.0},  {0.2, 1.0}  } })

hl.animation({ leaf = "windows",    enabled = true, speed = 4, bezier = "omarchy" })
hl.animation({ leaf = "border",     enabled = true, speed = 8, bezier = "snap" })
hl.animation({ leaf = "fade",       enabled = true, speed = 4, bezier = "snap" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "omarchy" })'''),
    ...para('--',
        r'Two named curves and four animated properties. A cubic bezier '
        r'is defined by two control points; the first curve, "omarchy", '
        r'uses (0.05, 0.9) and (0.1, 1.05). The second control point '
        r'has a y value above 1, which in a cubic bezier means the '
        r'animation overshoots its target slightly before settling, so '
        r'windows and workspaces arrive with a small bounce. The '
        r'second curve, "snap", uses the same point twice, (0.2, 1.0), '
        r'which rises quickly and never exceeds 1, so it has no '
        r'overshoot. It is attached to the border and the fade, '
        r'where a bounce would have nothing sensible to do; that '
        r'pairing is a reading; the file does not explain it.'),
    blank,
    ...para('--',
        r'The speeds are 4 for windows, fade and workspaces and 8 for '
        r'the border. Hyprland’s documentation gives the unit as '
        r'deciseconds, so 4 would be 400 ms and 8 would be 800 ms; that '
        r'is a fact about Hyprland taken from its docs and not from '
        r'this repo. What is visible in the code regardless '
        r'of unit is the ratio: the border gets 8 where everything '
        r'else gets 4. If the number is a duration, the border change '
        r'takes twice as long as a window move, which would make a '
        r'colour change a gentle fade rather than a flash; the file '
        r'does not state that intent.'),
    ...sec('keybinds: the shape of the table'),
    ...para('--',
        r'The binds are written as a flat list of hl.bind calls, one '
        r'per line, grouped under short comments. That layout is '
        r'deliberate and has a second reader: keybinds.sh parses this '
        r'section to produce the SUPER+SHIFT+/ cheat sheet (see its '
        r'page). The conventions that script relies on are exactly the '
        r'ones the file follows. The modifier is a local string, '
        r'mod = "SUPER", one bind sits on one line, a short comment '
        r'above a group names it, and loops are written with ".. i".'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · apps and the power button', r'''
-- Apps
hl.bind(mod .. " + T", hl.dsp.exec_cmd("ghostty"))
hl.bind(mod .. " + D", hl.dsp.exec_cmd("noctalia msg panel-toggle launcher"))
hl.bind(mod .. " + CTRL + V", hl.dsp.exec_cmd("noctalia msg panel-toggle clipboard"))
hl.bind(mod .. " + E", hl.dsp.exec_cmd("ghostty -e yazi"))
hl.bind(mod .. " + ALT + J", hl.dsp.exec_cmd("jetbrains-toolbox"))
hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + SHIFT + E", hl.dsp.exit())
hl.bind(mod .. " + ALT + L", hl.dsp.exec_cmd("noctalia msg session lock"))
-- Physical power button opens the session menu (same as the bar's power icon)
-- rather than powering off. logind is set to ignore the key so this wins.
hl.bind("XF86PowerOff", hl.dsp.exec_cmd("noctalia msg panel-toggle session"), { locked = true })'''),
    ...para('--',
        r'The first group is the app launcher layer: Ghostty on T, the '
        r'noctalia launcher on D, Yazi in a Ghostty window on E, '
        r'JetBrains Toolbox on ALT+J. SUPER+Q closes a window, and '
        r'SUPER+SHIFT+E exits Hyprland outright, with no confirmation '
        r'step in the bind itself. SUPER+CTRL+V, the clipboard history, '
        r'was a later addition (608f2d1, 2026-09-21).'),
    blank,
    ...para('--',
        r'The power button deserves its own story, because it spans '
        r'three files. Commit 0dc7770 ("Power button opens the session '
        r'menu instead of powering off", 2026-09-21 01:30) explains: '
        r'"logind is set to ignore the power key so Hyprland can bind '
        r'it; the bind opens noctalia’s session panel. Holding the '
        r'button for ~5 s still forces a poweroff." The logind half is '
        r'system/etc/systemd/logind.conf.d/10-power-key.conf, with '
        r'HandlePowerKey=ignore and HandlePowerKeyLongPress=poweroff, '
        r'installed by install.sh --system, which also reloads '
        r'systemd-logind. The logind file’s own comment names what is '
        r'being avoided: logind "powering the machine off with no '
        r'confirmation". The hold-to-poweroff line is the escape '
        r'hatch for a hung session. The bind’s '
        r'{ locked = true } option is Hyprland’s flag for binds that '
        r'still work while the session is locked, which is the same '
        r'flag the media keys use.'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · workspaces and the mouse', r'''
-- Workspaces
for i = 1, 9 do
    hl.bind(mod .. " + " .. i,          hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + CTRL + " .. i,   hl.dsp.window.move({ workspace = i }))
end
hl.bind(mod .. " + U", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + I", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Mouse drag
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })'''),
    ...para('--',
        r'This is where Lua pays for itself. In hyprlang the nine '
        r'workspace binds and their nine move-window twins would be '
        r'eighteen lines; here a for loop writes them, and the cheat '
        r'sheet knows to print the pair as "1..9". The relative binds '
        r'use "e+1" and "e-1", Hyprland’s notation for the next and '
        r'previous existing workspace, on U, I and the scroll wheel. '
        r'The mouse pair is the classic floating-window gesture: '
        r'SUPER with the left button (code 272) drags, with the right '
        r'button (273) resizes, and { mouse = true } marks them as '
        r'mouse binds. Focus moves on both the vim keys and the '
        r'arrows; adding CTRL moves the window instead, but only on '
        r'the vim keys, since the arrows have no move twin.'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · window state and media keys', r'''
-- Window state
hl.bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mod .. " + P", hl.dsp.window.pseudo())
hl.bind(mod .. " + S", hl.dsp.layout("togglesplit"))

-- Audio / media — routed through noctalia so the OSD shows
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("noctalia msg volume-up"),      { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("noctalia msg volume-down"),    { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("noctalia msg volume-mute"),    { locked = true })'''),
    ...para('--',
        r'SUPER+F uses the maximize flavour of fullscreen, '
        r'mode = "maximized", not true fullscreen. The commit message '
        r'(b22bf50) says only "SUPER+F maximizes the window (Omarchy '
        r'full width)"; presumably the bar stays visible, but the '
        r'repo does not say. The media keys are the other half of the '
        r'noctalia story. The comment says they are "routed through '
        r'noctalia so the OSD shows", which implies that bypassing '
        r'it would change the volume with no on-screen display. The '
        r'flags tell the rest: volume up and down are { locked, '
        r'repeating }, so holding the key keeps stepping and the keys '
        r'work on the lock screen, while mute and the transport keys are '
        r'only locked. Mic mute, play, stop, previous and next are '
        r'in the file as well, in the same pattern.'),
    ...sec('gaming performance: scanout, scheduling and tearing'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · gaming performance', r'''
-- For Noctalia Color templates
-- ─── Gaming performance ──────────────────────────────────────────────────
hl.config({
    -- Fullscreen games that ask for it are handed straight to the display,
    -- skipping a composite pass (less GPU work, less latency).
    render  = { direct_scanout = 2, new_render_scheduling = true },
    -- Only permits tearing; the rule below opts Steam games in. Desktop apps
    -- stay tear-free.
    general = { allow_tearing = true },
})
hl.window_rule({
    name      = "steam-games-immediate",
    match     = { class = "^steam_app_" },
    -- Present frames immediately instead of waiting for vblank: lower input
    -- latency, and a GPU below 60 fps never stalls for the next refresh.
    immediate = true,
})'''),
    ...para('--',
        r'This block is the compositor’s share of the project’s tagline, '
        r'"tuned for gaming", and the initial commit message summarises '
        r'it: "direct scanout and tearing for games only". Three '
        r'separate mechanisms are at work.'),
    ...pt('--', 'direct scanout',
        'normally the compositor draws every frame into its own '
        'buffer before showing it. If a single fullscreen window can '
        'be put on screen as-is, that composite pass is skipped, '
        'which the comment credits with "less GPU work, less latency". '
        'The value is 2, not true. Hyprland’s docs describe 2 as an '
        'automatic mode that engages for windows whose content type is '
        'game, and the comment’s wording, "games that ask for it", '
        'fits that; this is background knowledge that the repo does not '
        'confirm.'),
    ...pt('--', 'new_render_scheduling',
        'turned on in the same table with no comment and no mention in '
        'any commit message. Where it sits is clear; what it does '
        'for this machine is not documented.'),
    ...pt('--', 'tearing',
        'allow_tearing = true is a master switch; it does not tear '
        'anything by itself. The comment is exact: "Only permits '
        'tearing; the rule below opts Steam games in." The opt-in '
        'is the rule: windows whose class starts with steam_app_ get '
        'immediate = true, which presents frames without waiting for '
        'vertical blank.'),
    blank,
    ...para('--',
        r'The reasoning for immediate is stated, and it is worth '
        r'unpacking. "Lower input latency" is the obvious half. The '
        r'second half, "a GPU below 60 fps never stalls for the next '
        r'refresh", is about the monitor in the Display section: a '
        r'60 Hz panel refreshes every 16.7 ms. With plain '
        r'double-buffered vsync, general background rather than '
        r'anything in the repo, a frame that takes 20 ms misses a '
        r'refresh and waits for the next one, so the player sees '
        r'30 fps steps instead of 50. This machine has a GTX 980 with '
        r'4 GB, and MangoHud.conf notes "the game’s 6 GB minimum" '
        r'against it, so a card that sometimes cannot hold 60 fps is '
        r'the situation the rule is written for. The repo does not '
        r'name the games. The trade is tearing, accepted only for '
        r'Steam games.'),
    blank,
    ...para('--',
        r'Hyprland’s own tearing documentation, in the summary that '
        r'could be retrieved for this page, adds a condition this file '
        r'cannot show: tearing only happens when '
        r'the game is fullscreen and the only thing visible on the '
        r'screen. That fits the README’s claim that the desktop stays '
        r'tear-free. It also means the master switch being on '
        r'everywhere is harmless for ordinary windows.'),
    blank,
    ...para('--',
        r'One imprecision between the README and the code: the README '
        r'says "Direct scanout and tearing for Steam windows only". '
        r'Tearing is scoped by the rule as described. Direct scanout '
        r'is not scoped by anything in this file; it is global and '
        r'left to the compositor to engage when it applies. The '
        r'behaviour is probably what was intended, but the README '
        r'sentence is a little broader than the code.'),
    blank,
    ...para('--',
        r'Also visible in the excerpt: the stray comment "-- For '
        r'Noctalia Color templates" sits directly above the section '
        r'banner and has nothing under it. It is not used by the code. '
        r'It reads as a leftover marker, and doubles as an example of '
        r'the cheat sheet’s heading rule: a short comment above what '
        r'follows would be taken as a heading if a bind came next, and '
        r'here none does.'),
    blank,
    ...para('--',
        r'The repo contains no measurements of any of this: no frame '
        r'times, no latency numbers, no before-and-after. The justification '
        r'is the reasoning in the comments. The rest of the gaming '
        r'stack lives in other files: gamemode.ini (governor), '
        r'MangoHud.conf (the overlay), scx_loader.toml (the scx_lavd '
        r'scheduler), nvidia-powerlimit.service (180 W to 225 W), '
        r'ntsync.conf, and Steam’s steam_dev.cfg download tweaks.'),
    ...sec('gamemode: attaching by window class'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · the GameMode hook', r'''
-- ─── GameMode, automatically ─────────────────────────────────────────────
-- Proton names every Steam game window steam_app_<appid>. When one opens,
-- its process joins GameMode (Ryzen -> performance governor, screensaver
-- inhibited). It drops back to powersave ~20 s after the game exits.
-- Steam's own client window is class "steam" and deliberately not matched.
hl.on("window.open", function(w)
    if w and w.initial_class and w.initial_class:match("^steam_app_%d+$") then
        hl.exec_cmd("/home/xynorash/.local/bin/gamemode-attach " .. w.pid)
    end
end)'''),
    ...para('--',
        r'GameMode is Feral’s daemon that switches the CPU into a '
        r'performance profile while a game runs. The usual way to use '
        r'it is a launch option per game, gamemoderun %command% in '
        r'Steam. This hook removes the per-game step: the compositor '
        r'sees the game window open and enrolls its process.'),
    blank,
    ...para('--',
        r'The match is tight in three ways. The Lua pattern '
        r'^steam_app_%d+$ requires digits after steam_app_ and '
        r'anchors both ends, so only a Proton window named for an '
        r'app id passes. The hook reads initial_class, the class the '
        r'window had when it opened, instead of the current class, '
        r'presumably to make the decision immune to a later '
        r'rename. And the '
        r'comment records the exclusion that matters most: Steam’s '
        r'own client window has the class steam and is deliberately '
        r'not matched, presumably so that the launcher alone does not '
        r'trigger performance mode. The guard if w and w.initial_class and ... also '
        r'protects against a nil window or a nil class.'),
    blank,
    ...para('--',
        r'Compare this with the rule in the previous section, which '
        r'matches class = "^steam_app_" with a regular expression. '
        r'Two pattern languages meet in this file: window rules take '
        r'regular expressions, Lua’s :match takes Lua patterns. The '
        r'two fragments mean nearly the same thing, but the hook '
        r'is stricter (digits and an end anchor), presumably because a '
        r'wrong match there launches a process, where a wrong match in '
        r'the rule only toggles a presentation mode.'),
    ...code('bash', 'home/.local/bin/gamemode-attach · why the helper is careful', r'''
# `gamemoded -r PID` toggles, so a game that opens two windows from one
# process would switch itself back off. An atomic mkdir lock per PID
# makes a second call a no-op. The -r helper also blocks forever, so we
# wait for the game to exit and then clean it up.'''),
    ...para('--',
        r'The hook does not call gamemoded itself, because registering '
        r'a process is a toggle and window.open fires once per window, '
        r'while a process can own several. That is why the compositor '
        r'hands the PID to a '
        r'script. The script has its own page; one fact from its '
        r'history belongs here because it explains why the hook is so '
        r'plain: the initial commit (2026-09-19 18:28) attached every '
        r'game, and an hour later aebd41e '
        r'("gamemode-attach: leave self-registered games alone") '
        r'taught the helper to step aside for processes that '
        r'gamemoderun had already registered, since "calling '
        r'gamemoded -r on it toggles GameMode back off". The repo '
        r'keeps the hook simple and the helper smart, and the '
        r'helper’s page tells the rest.'),
    blank,
    ...para('--',
        r'The comment in the hook promises a tail: the process '
        r'"drops back to powersave ~20 s after the game exits". The '
        r'governors are in home/.config/gamemode.ini: '
        r'desiredgov=performance and defaultgov=powersave, with a '
        r'comment naming amd-pstate active mode, and notifications '
        r'"Performance mode on" and "Performance mode off" sent '
        r'through noctalia. The 20 second figure is the comment’s; '
        r'the helper itself polls every 5 seconds, and no second '
        r'source for the 20 turned up in the repo.'),
    ...sec('window rules: the floating cheat sheet'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · the keybinds rule', r'''
-- ─── Window rules ────────────────────────────────────────────────────────
hl.window_rule({
    name   = "keybinds-cheatsheet",
    match  = { class = "^(com\\.hypr\\.Keybinds)$" },
    float  = true,
    size   = "900 820",
    center = true,
})'''),
    ...para('--',
        r'This is a static rule, and it can be one because Ghostty '
        r'sets its class from --class at creation. The Lua string needs '
        r'doubled backslashes so that the regular expression receives '
        r'a single escape for each dot. The rule floats the window at '
        r'900 by 820 and centres it. The page for keybinds.sh covers '
        r'the other end. What matters here is the contrast with the '
        r'next section: this rule can be static because the class is '
        r'known at map time. The WinApps class is not.'),
    ...sec('winapps: what the repo contains, and what it does not'),
    ...para('--',
        r'WinApps is a way to run Windows applications from a Linux '
        r'desktop, each application in a window of its own next to '
        r'native ones. This part of the file deserves an inventory of '
        r'what the repository actually holds. Every tracked file was '
        r'searched for winapps, freerdp, timesync and remoteapp, case '
        r'insensitively. The only file that matches is hyprland.lua. '
        r'The README does not mention WinApps. Neither package list '
        r'names winapps or freerdp.'),
    blank,
    ...para('--',
        r'So everything known here comes from one comment block, one '
        r'function and three registration lines, added by a single '
        r'commit. What the file supports:'),
    ...pt('--', 'the transport',
        'the windows are "FreeRDP RemoteApp windows (xfreerdp3 under '
        'XWayland)". Each remote application appears as an X11 window '
        'of its own.'),
    ...pt('--', 'the naming',
        'every window of an app "shares the class Microsoft <App> '
        '(set by /wm-class)". /wm-class is a FreeRDP command-line '
        'option, so the class is chosen by whoever builds the command '
        'line, and a class such as "Microsoft Word" would fit the '
        'pattern, although the repo names no real application.'),
    ...pt('--', 'the helper',
        'the VM runs a TimeSync.ps1 script "in a visible PowerShell '
        'window". The name suggests keeping the VM’s clock right; that '
        'is a guess, since the script is not in the repo.'),
    blank,
    ...para('--',
        r'And what the repository does not hold, so that nothing here '
        r'is mistaken for evidence of more:'),
    ...pt('--', 'no VM, no WinApps config',
        'the Windows virtual machine, its image, its setup and the '
        'WinApps configuration are not tracked. Docker is installed '
        '(it is in pacman.txt and install.sh adds the user to the '
        'docker group) but nothing in the repo ties it to WinApps, and '
        'this page will not guess how the VM is run.'),
    ...pt('--', 'no FreeRDP command line',
        'xfreerdp3 and /wm-class are named in a comment. The actual '
        'invocation is not present.'),
    ...pt('--', 'no TimeSync.ps1',
        'the script that opens the PowerShell window lives inside the '
        'VM, outside this repository.'),
    ...pt('--', 'no earlier attempts',
        'there is one commit about WinApps. Failed rule experiments, '
        'if there were any, were not committed.'),
    ...sec('winapps: why static rules fail'),
    ...para('--',
        r'The commit that added the block, 2f34af7 ("WinApps: float '
        r'RemoteApp windows and park the PowerShell helper window", '
        r'2026-10-08), has a one-sentence body, and it is the argument '
        r'in full: "Class and title arrive after the XWayland window '
        r'maps, so static window rules never match; hook '
        r'window.open/class/title instead."'),
    blank,
    ...para('--',
        r'Read it as a chain of three steps. A window rule is checked '
        r'when the window appears, against what the window has said '
        r'about itself by then; for a Proton game that is steam_app_ '
        r'plus an id, and for the cheat sheet it is the class given on '
        r'the command line. A RemoteApp window appears first and '
        r'learns what it is afterwards: the commit says the class and '
        r'the title arrive after the window maps. At the moment the '
        r'rule is evaluated, there is nothing to match, and a rule '
        r'like class = "^Microsoft " therefore never fires. The remedy '
        r'is to stop matching once and instead look again every time '
        r'the information changes. Hyprland offers events for exactly '
        r'that.'),
    blank,
    ...para('--',
        r'The part that cannot be supplied is the experiment that '
        r'led here. '
        r'The commit states the conclusion, and a developer who has '
        r'been through this would recognise the sequence: write a '
        r'rule, see no effect, discover why. The history does not keep '
        r'the rule that was tried, so the claim "never match" is the '
        r'author’s finding, reported in one sentence, not something '
        r'the repo can reproduce.'),
    ...sec('winapps: three hooks, one handler'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · the handler', r'''
-- WinApps: FreeRDP RemoteApp windows (xfreerdp3 under XWayland). Every window
-- of an app shares the class "Microsoft <App>" (set by /wm-class) and its
-- class and title arrive after the window maps, so static window rules never
-- match; these hooks run on every class/title change instead.
--  * float: tiling resizes the X window while the server is still repainting,
--    so frame and content disagree and the app stalls. A floating window is
--    resized once, when you release the drag.
--  * the VM's TimeSync.ps1 helper runs in a visible PowerShell window; park it
--    on a hidden special workspace instead of letting it cover the screen.
local function tame_winapps(w)
    if not (w and w.class and w.class:match("^Microsoft ")) then return end
    if w.title:match("^Administrator: .*powershell%.exe$") then
        if not (w.workspace and w.workspace.name == "special:winapps") then
            hl.dispatch(hl.dsp.window.move({ workspace = "special:winapps", follow = false, window = w }))
        end
    elseif not w.floating then
        hl.dispatch(hl.dsp.window.float({ action = "enable", window = w }))
    end
end
hl.on("window.open",  tame_winapps)
hl.on("window.class", tame_winapps)
hl.on("window.title", tame_winapps)'''),
    ...para('--',
        r'The three registrations at the bottom bind the same function '
        r'to three moments in a window’s life.'),
    ...pt('--', 'window.open',
        'the window has just mapped. By the commit message the class '
        'and title are probably not known yet, so this call often does '
        'nothing; it is there for windows that already know who they '
        'are.'),
    ...pt('--', 'window.class',
        'the class changed. This is when "Microsoft <App>" arrives, and '
        'when an ordinary RemoteApp window first passes the filter and '
        'is floated.'),
    ...pt('--', 'window.title',
        'the title changed. This is when "Administrator: ... '
        'powershell.exe" arrives for the helper, and it fires again '
        'whenever an application changes its title, for example when a '
        'document is renamed.'),
    blank,
    ...para('--',
        r'What makes it safe to use one handler for three events is '
        r'that the function never asks which event woke it. It looks '
        r'at the window’s present state and moves toward the desired '
        r'one. Engineers call this level-triggered, in contrast to '
        r'edge-triggered code that reacts to a specific transition, '
        r'and the benefit is that the handler can be called too often '
        r'without harm. The guards are what keep it harmless: a window '
        r'that already floats is left alone, and a helper already on '
        r'special:winapps is not moved again. Without them, every '
        r'title change of a busy application would issue a fresh '
        r'dispatch.'),
    blank,
    ...para('--',
        r'Walk through the possible orders. If the class arrives and '
        r'the title is still empty, the window is not the helper, so '
        r'it is floated. If the title then reads "Administrator: '
        r'...powershell.exe", the next call moves it to the special '
        r'workspace, still floating, which is harmless. If the title '
        r'arrives first, the class check returns early and nothing '
        r'happens until the class does; the helper is then moved '
        r'without ever having been floated. The end states differ in '
        r'that one flag, floating or not, which is invisible while the '
        r'window is hidden. Every other RemoteApp window ends '
        r'floating whatever the order, and every helper ends on '
        r'special:winapps, which is the property you want from '
        r'handlers that race.'),
    blank,
    ...para('--',
        r'Written out as a decision table, the whole handler is five '
        r'cases, and every call of it lands in exactly one:'),
    ...pt('--', 'class missing or not "Microsoft "',
        'return at once. Native windows, Proton games and a RemoteApp '
        'window that has not yet received its class all stop here.'),
    ...pt('--', 'Microsoft class, helper title, not yet parked',
        'move the window to special:winapps without following it.'),
    ...pt('--', 'Microsoft class, helper title, already parked',
        'do nothing, so repeated title events cost one pattern match '
        'each.'),
    ...pt('--', 'Microsoft class, any other title, not floating',
        'enable floating.'),
    ...pt('--', 'Microsoft class, any other title, already floating',
        'do nothing.'),
    blank,
    ...para('--',
        r'Two API details are visible in the code. Inside a bind you '
        r'give hl.bind a dispatcher object built by hl.dsp; inside an '
        r'event handler you must run one yourself, hence '
        r'hl.dispatch(hl.dsp...). And both dispatchers pass '
        r'window = w, which targets the window the event is about. '
        r'That matters because the focused window is usually a '
        r'different one: a helper window opens in the background, and '
        r'without window = w the dispatcher would act on whatever has '
        r'focus.'),
    blank,
    ...para('--',
        r'One thing the code does not guard: the filter checks w, '
        r'w.class and the Microsoft prefix, but the next line calls '
        r'w.title:match without checking the title. It works as long '
        r'as Hyprland hands over a string, empty or not, for a window '
        r'with no title yet. The handler was committed as working, so '
        r'Hyprland presumably does; the type was not confirmed.'),
    ...sec('winapps: floating'),
    ...para('--',
        r'The first behaviour is in the comment, and it is the most '
        r'concrete piece of engineering evidence in the block: "tiling '
        r'resizes the X window while the server is still repainting, '
        r'so frame and content disagree and the app stalls. A floating '
        r'window is resized once, when you release the drag."'),
    blank,
    ...para('--',
        r'The comment says what happens, not why, so the mechanism '
        r'below is a reading of its wording. In the dwindle layout any '
        r'change to the tree, a window opening, closing or a split '
        r'flipping, recomputes geometry and resizes the neighbours. '
        r'For a RemoteApp window the X window is a view of a remote '
        r'session, so a resize presumably has to reach the Windows '
        r'side and return as repainted pixels; while that is in '
        r'flight the frame has its new size and the content still has '
        r'the old one. "Frame and content disagree" is the symptom '
        r'named in the comment, "the app stalls" the consequence. A '
        r'floating window avoids the storm, because its geometry '
        r'only changes when the person drags a border and lets go: '
        r'one resize, not a stream.'),
    blank,
    ...para('--',
        r'The solution trades one thing for another. Windows apps can '
        r'no longer be tiled; they always float. There is a visible '
        r'interaction with SUPER+V, the toggle-float bind: if you '
        r'tile a RemoteApp window by hand, the next class or title '
        r'event finds it not floating and floats it again, and since '
        r'many applications retitle themselves often, that would '
        r'happen quickly. That follows from the code; it was not '
        r'tried here.'),
    blank,
    ...para('--',
        r'The block also leaves placement alone. There is no size or '
        r'centre rule for these windows, unlike the cheat sheet, so '
        r'a floating RemoteApp window opens wherever Hyprland puts a '
        r'new floating window, subject to whatever geometry the '
        r'application asks for.'),
    ...sec('winapps: parking the PowerShell helper'),
    ...para('--',
        r'The second behaviour handles a nuisance, again in the '
        r'comment: "the VM’s TimeSync.ps1 helper runs in a visible '
        r'PowerShell window; park it on a hidden special workspace '
        r'instead of letting it cover the screen." The structure of '
        r'the handler implies that the helper window carries a class '
        r'starting with "Microsoft " like any real application, since '
        r'the title test sits behind the class filter; nothing '
        r'distinguishes it from the others except its title.'),
    blank,
    ...para('--',
        r'The title test is w.title:match("^Administrator: '
        r'.*powershell%.exe$"). In a Lua pattern the %. is a literal '
        r'dot, .* is any run of characters, and the anchors make it '
        r'match the whole title. Windows prefixes a console title '
        r'with "Administrator: " when the process is elevated and '
        r'then shows the path of the executable, so the pattern '
        r'accepts any path ending in powershell.exe. The prefix '
        r'suggests the helper runs elevated; again that is Windows '
        r'behaviour, not something the repo shows.'),
    blank,
    ...para('--',
        r'The destination is a special workspace named winapps. '
        r'Special workspaces in Hyprland are scratchpad-style spaces '
        r'that stay out of sight unless toggled in, so the window is '
        r'still alive and still running, just not on any ordinary '
        r'workspace. "Park", the comment’s word, is accurate: the '
        r'window is not closed. follow = false means the view stays '
        r'where it is instead of jumping to the new workspace, which '
        r'would defeat the purpose.'),
    blank,
    ...para('--',
        r'Here is a small finding about the whole config: no bind '
        r'anywhere references special:winapps. The helper is hidden '
        r'and there is no key that brings it back. If its output ever '
        r'needed reading, you would have to toggle the special '
        r'workspace through hyprctl or add a bind. The omission '
        r'suggests nobody was expected to look at the window, which '
        r'is a reading and not a stated reason; a bind would also be '
        r'a possible next step.'),
    ...sec('winapps: limits'),
    ...pt('--', 'language-dependent title',
        'the helper test depends on the English "Administrator:" '
        'prefix. A VM with another display language would presumably '
        'produce a different title, the helper would be floated like any other '
        'window, and the PowerShell window would cover the screen '
        'again.'),
    ...pt('--', 'only classes that start with "Microsoft "',
        'the filter is a case-sensitive prefix with a trailing space. '
        'A RemoteApp launched with another /wm-class is not tamed at '
        'all.'),
    ...pt('--', 'a workaround, not a fix',
        'the stall comes from tiling a remote window, and floating '
        'avoids it. Nothing here makes tiling work.'),
    ...pt('--', 'no tests, no logs',
        'the handler does not log what it did. The only way to see it '
        'work is to open a RemoteApp and look.'),
    ...pt('--', 'unrecorded environment',
        'versions of Hyprland, FreeRDP and WinApps are not recorded '
        'anywhere in the repo, so the behaviour described in the '
        'comment is pinned to a setup that is not written down.'),
    ...sec('the theme hook-up'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · the last line', r'''
require("noctalia").apply_theme()'''),
    ...para('--',
        r'The file ends by loading a module that is not in the '
        r'repository. noctalia.lua is generated and gitignored, and '
        r'the call suggests it returns a table with an apply_theme '
        r'function, presumably the one that applies the palette. '
        r'Putting the call last means it runs after everything above, '
        r'and a theme change in noctalia can rewrite noctalia.lua '
        r'without touching the hand-written file. The cost: on a fresh '
        r'clone the file does not exist until noctalia has generated '
        r'it, so the require would raise a Lua error; what Hyprland '
        r'does with that error was not checked, and the repo does not '
        r'say how the first run is handled.'),
    ...sec('how the file grew'),
    ...para('--',
        r'Six commits touched the file. In total it gained 36 lines '
        r'after the first commit and lost none: every change is an '
        r'insertion.'),
    ...pt('--', '2026-09-19 18:28, d552dfd',
        'initial commit, 207 lines. Already complete: display, '
        'environment, autostart, look, animations, every bind except '
        'three, the gaming block, the GameMode hook and the cheat sheet '
        'rule.'),
    ...pt('--', '2026-09-21 01:30, 0dc7770 (+3)',
        'the power button opens the session menu.'),
    ...pt('--', '2026-09-21 19:21, 0ae2015 (+6)',
        'notification clicks jump to the sender: the autostart line '
        'and focus_on_activate.'),
    ...pt('--', '2026-09-21 20:10, 608f2d1 (+1)',
        'SUPER+CTRL+V opens the clipboard history.'),
    ...pt('--', '2026-09-22 19:35, b22bf50 (+1)',
        'SUPER+F maximizes.'),
    ...pt('--', '2026-10-08 11:53, 2f34af7 (+25)',
        'the cursor environment (2 lines) and the WinApps handler '
        '(23 lines), the largest change since the start.'),
    blank,
    ...para('--',
        r'Nothing was ever rewritten. Settings were added next to '
        r'their neighbours and the structure did not move. A fair '
        r'reading is that this is partly the nature of three weeks of '
        r'a young setup and partly a sign that the initial layout, one '
        r'section per concern with a banner, was good enough to absorb '
        r'every later feature without refactoring.'),
    ...sec('how it is checked'),
    ...para('--',
        r'There is no test suite and no CI in the repository. The '
        r'checks are indirect. The cheat sheet script reads the file '
        r'every time it is invoked, so a malformed bind would probably '
        r'show up as a missing or garbled line. Anything about gaming '
        r'performance or WinApps behaviour is checked by using the '
        r'machine. The honest summary is that this file is validated '
        r'by living with it.'),
    ...sec('limits and what is next'),
    ...pt('--', 'personal paths',
        'four absolute /home/xynorash paths, as the README says. A '
        'second user needs to edit the file.'),
    ...pt('--', 'one monitor',
        'the display rule hard-codes HDMI-A-1.'),
    ...pt('--', 'no measurements',
        'every performance setting rests on reasoning in a comment.'),
    ...pt('--', 'unexplained settings',
        'new_render_scheduling and the touchpad block have no stated '
        'reason.'),
    ...pt('--', 'colours are untracked',
        'the generated noctalia.lua is not in git, so the exact '
        'border colours cannot be reproduced from the repository '
        'alone.'),
    ...pt('--', 'next steps the code suggests',
        'a bind to toggle special:winapps, a dispatcher entry for '
        'fullscreen in the cheat sheet, and a log line from the '
        'WinApps handler.'),
    ...sec('what rests on Hyprland’s docs, not on this repo'),
    ...para('--',
        r'For honesty, these statements rest on general Hyprland '
        r'knowledge, not on evidence in xyno-arch: the unit of '
        r'animation speed, the meaning of direct_scanout = 2, that '
        r'tearing needs a fullscreen game alone on screen, what '
        r'special workspaces are, what "e+1" means, the meaning of '
        r'the locked, repeating and mouse bind flags, and what '
        r'resize_on_border, preserve_split, smart_split and '
        r'follow_mouse do. Only a summary of the tearing '
        r'documentation could be retrieved while writing this page; '
        r'the others are from memory and should be checked against '
        r'the current docs. The same goes '
        r'for two Windows facts used in the WinApps section: the '
        r'"Administrator:" console title prefix and the existence of '
        r'FreeRDP’s /wm-class option.'),
    blank,
    link('→ github.com/XNash/xyno-arch', 'https://github.com/XNash/xyno-arch'),
  ],
);
