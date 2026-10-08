import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/home/.config/noctalia/config.toml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'config.toml — the hand-written layer of the noctalia shell'),
    cm('#', 'bar, widgets, panels and theme templates: the look of a desktop as data'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role',     'declarative config for noctalia: bar, panels, lock '
    'screen, theme templates'),
    kv('language', 'TOML'),
    kv('size', '214 lines, 11 commits, 2026-09-19 to 2026-09-21'),
    kv('layer', 'above built-in defaults, below the GUI state file'),
    kv('installed',     'symlinked to ~/.config/noctalia/config.toml by '
    'install.sh'),
    ...sec('why this file exists'),
    ...para('#',
        'A desktop shell that is configured through a settings window '
        'has a reproducibility problem: the choices are real, but '
        'they land in a state file that nobody commits, and a fresh '
        'machine comes up with defaults. This file is the answer. It '
        'holds, as plain TOML, everything that defines how the '
        'xyno-arch desktop looks and what its bar does. Commit '
        '208de62 (2026-09-19) says so in its message: it moved the '
        'wallpaper, the bar geometry and the lock screen "out of '
        'noctalia’s state file and into the tracked config, so a '
        'fresh machine comes up identical instead of falling back to '
        'defaults".'),
    blank,
    ...para('#',
        'noctalia is the one program that draws the bar, launcher, '
        'notifications, lock screen, OSD and control center (the '
        'README’s "The setup" table). Its upstream README calls it a '
        'native Wayland shell built on OpenGL ES with no Qt or GTK '
        'dependency, which is why there is no second config for a '
        'notification daemon or a lock program anywhere in this repo. '
        'The key bindings that talk to it live in '
        'home/.config/hypr/hyprland.lua; everything else about the '
        'shell is here.'),
    ...sec('three layers, and who wins'),
    ...code('toml', 'home/.config/noctalia/config.toml · the header', r'''
# Omarchy Quattro-inspired look, translated to noctalia + niri.
# Hand-written layer. GUI changes land in ~/.local/state/noctalia/settings.toml
# and override anything here.'''),
    ...para('#',
        'That header describes the arrangement noctalia’s '
        'configuration docs spell out: built-in defaults first, then '
        'every *.toml file in ~/.config/noctalia (merged in '
        'alphabetical order), then the GUI-managed '
        '~/.local/state/noctalia/settings.toml last. Because the '
        'state file loads last, a value changed in the Settings '
        'window silently beats the same value written here. The docs’ '
        'advice when a hand-written value "does not take effect" is '
        'to look at that file, and they add that when Settings saves '
        'a value equal to what the lower layers already say, noctalia '
        'deletes the redundant key instead of keeping it as an '
        'override.'),
    blank,
    ...para('#',
        'The repo’s half is .gitignore, which lists '
        'hypr/noctalia.lua, noctalia/settings.toml and yazi/ as '
        '"Written by noctalia’s theme templates, not by hand". One '
        'detail does not line up: the header here and the docs put '
        'settings.toml under ~/.local/state, outside the repo’s home/ '
        'tree, while .gitignore names the config-dir path. The ignore '
        'line is harmless; what really keeps the state file out of '
        'git is its location.'),
    blank,
    ...para('#',
        'The file reaches the machine through install.sh, which '
        'symlinks every file under home/ into place:'),
    ...code('bash', 'install.sh · the symlink loop', r'''
while IFS= read -r -d '' src; do
  rel=${src#"$repo"/home/}
  dst=$HOME/$rel
  mkdir -p "$(dirname "$dst")"
  backup "$dst"
  ln -s "$src" "$dst"
  echo "  $dst -> $src"
done < <(find "$repo/home" -type f -print0)'''),
    ...para('#',
        'Because the target is a symlink into the repo, editing '
        '~/.config/noctalia/config.toml edits the repository, and the '
        'docs say both config layers are watched and hot-reloaded. '
        'The loop from edit to visible change to "git diff" is short, '
        'which matters for the history further down.'),
    blank,
    ...para('#',
        'One more oddity in the header: the first line says '
        '"translated to noctalia + niri", but the compositor in this '
        'repo is Hyprland (hyprland.lua, README). noctalia supports '
        'both, so nothing is broken. The history simply starts at an '
        '"Initial commit" (2026-09-19, d552dfd) that already contains '
        'the Hyprland setup, so it cannot say when or why niri was '
        'left behind. The likeliest reading is that the look was '
        'first built on niri and the comment was never touched. It is '
        'the first of several comments in this file that describe an '
        'earlier intention rather than the current state; they are '
        'collected under "limits" at the end.'),
    ...sec('shell-wide settings'),
    ...code('toml', 'home/.config/noctalia/config.toml · shell and accessibility (trimmed)', r'''
[shell]
# Quattro leans rounded across bar, menus, notifications and lock screen.
corner_radius_scale = 1.4
font_family = "JetBrainsMono Nerd Font"
polkit_agent = true
# Outline the section cards inside panels.
card_borders = true
...
[accessibility]
# 1x content scale — matches the pinned 1.0 Wayland output scale.
ui_scale = 1.0'''),
    ...pt('#',
        'corner_radius_scale = 1.4',
        'a multiplier on every corner in the shell. The docs give 0 '
        'as square, 1 as default and 2 as extra rounded, so 1.4 sits '
        'well toward round. The comment names the motive: the '
        'reference look "leans rounded across bar, menus, '
        'notifications and lock screen". The bar’s own absolute '
        'radius (14, below) is a separate knob.'),
    ...pt('#',
        'font_family',
        'the same family as the terminal and GTK settings, which '
        'makes it one typeface across three toolkits. '
        'ttf-jetbrains-mono-nerd is in packages/pacman.txt. (The '
        'terminal asks for the "Mono" variant; see '
        'ghostty/config.ghostty.)'),
    ...pt('#',
        'polkit_agent = true',
        'registers noctalia’s own polkit authentication agent; the '
        'docs list the default as false. packages/pacman.txt contains '
        'no standalone agent, so this one line is plausibly what lets '
        'a GUI program ask for an administrator password. That is an '
        'inference; the repo does not say.'),
    ...pt('#',
        'card_borders = true',
        'the docs list true as the default, so the line restates it. '
        'Several lines in this file do: restating a default pins the '
        'look against the day an upstream default changes, though the '
        'file never says that is the intent.'),
    ...pt('#',
        'ui_scale = 1.0',
        'the comment ties it to "the pinned 1.0 Wayland output scale" '
        '(hyprland.lua sets scale = 1 on HDMI-A-1). The docs are '
        'careful that ui_scale is separate from the output scale; it '
        'only multiplies panels and other non-bar surfaces. What '
        'matches is the value, not a mechanism.'),
    ...sec('one palette, rendered into other programs'),
    ...code('toml', 'home/.config/noctalia/config.toml · theme and templates', r'''
[theme]
mode    = "dark"
source  = "builtin"
builtin = "Tokyo-Night"

[theme.templates]
enable_builtin_templates = true
# One palette pushed into everything — the Quattro "theme applies everywhere" idea.
# qt/kcolorscheme omitted: no Qt applications installed on this system.
builtin_ids = [ "hyprland", "ghostty", "gtk3", "gtk4" ]
enable_community_templates = true
# yazi is the file manager here; keep it on the same palette as everything else.
community_ids = [ "yazi" ]'''),
    ...para('#',
        'mode is pinned to "dark" rather than "auto". The docs say '
        'auto switches by sunrise and sunset computed from '
        '[location]; pinning means the location below feeds only the '
        'Night Light tile and the clock card, never the theme. '
        'builtin = "Tokyo-Night" is one of ten palettes compiled into '
        'noctalia (the docs list Ayu, Catppuccin, Dracula, Eldritch, '
        'Gruvbox, Kanagawa, Noctalia, Nord, Rosé Pine and '
        'Tokyo-Night) and an unknown name falls back to "Noctalia", '
        'so the hyphenated spelling is load-bearing.'),
    blank,
    ...para('#',
        'The templates are the point of the whole arrangement. '
        'Whenever the palette changes, noctalia renders it into other '
        'programs’ config files. Four built-ins and one community '
        'template are enabled, and each lands somewhere specific in '
        'this repo:'),
    ...pt('#',
        'hyprland',
        'writes home/.config/hypr/noctalia.lua, which is gitignored. '
        'hyprland.lua loads it as its very last line and says so in '
        'its header.'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · the two ends of the hand-off (trimmed)', r'''
-- Colours come from noctalia.lua, regenerated on every theme change.
...
require("noctalia").apply_theme()'''),
    ...pt('#',
        'ghostty',
        'writes ghostty/themes/noctalia (22 lines, tracked, with its '
        'own page in this tree), selected by "theme = noctalia" in '
        'config.ghostty.'),
    ...pt('#',
        'gtk3, gtk4',
        'per the docs, enabling these writes a noctalia.css, then '
        'runs a shipped apply.sh that imports it into gtk.css and '
        'syncs the adw-gtk3 theme and the GNOME color-scheme setting. '
        'Those generated files are not tracked. The docs name '
        'adw-gtk3 as the theme the templates drive, and neither '
        'packages/pacman.txt nor aur.txt lists adw-gtk-theme. Where '
        'it comes from is an open question the repo does not answer.'),
    ...pt('#',
        'yazi (community)',
        'fetched from api.noctalia.dev and cached under the state '
        'directory (docs); its output under ~/.config/yazi is '
        'gitignored. A consequence worth knowing: on a fresh machine '
        'this one template needs network access, and '
        'shell.offline_mode would block it.'),
    ...para('#',
        'The omission in the comment on line 21 is the first '
        'appearance of a habit this file keeps: "qt/kcolorscheme '
        'omitted: no Qt applications installed on this system." Do '
        'not render a palette into a toolkit nothing here uses.'),
    ...sec('the bar: what is in it and what is left out'),
    ...code('toml', 'home/.config/noctalia/config.toml · the layout comment and the three lanes (trimmed)', r'''
# ── Bar: modelled on Omarchy Quattro's documented layout ──────────────────
#   left   = menu launcher, spacer, workspaces
#   center = clock, media
#   right  = tray, network, audio, display, power
# Widgets Omarchy carries that this box can't use are omitted:
#   bluetooth (bluez not installed), display/brightness (no backlight on the
#   Dell E2314H), battery (desktop), keyboard_layout (single layout),
#   weather (needs location setup), agents/system-update (no equivalent).
...
start  = [ "launcher", "spacer", "workspaces" ]
center = [ "clock", "media" ]
end    = [ "tray", "sysmon_cpu", "sysmon_ram", "sysmon_gpu", "sysmon_net", "keyboard_layout", "volume", "volume_input", "control-center", "session" ]'''),
    ...para('#',
        'The comment is the original design note: a layout modelled '
        'on "Omarchy Quattro’s documented layout", with a list of '
        'widgets that Omarchy carries and this box cannot use, each '
        'with a reason that was checked against the hardware: no '
        'bluez, no backlight on the Dell E2314H, no battery (a '
        'desktop), weather needing a location setup.'),
    blank,
    ...para('#',
        'Two parts of that comment never matched the file. It lists '
        'keyboard_layout as omitted ("single layout"), yet '
        'keyboard_layout is in the end lane, and hyprland.lua sets '
        'kb_layout = "us,fr" with grp:alt_shift_toggle; the README '
        'documents switching between US and French AZERTY. Both facts '
        'are already in the initial commit, so the comment was wrong '
        'from day one rather than staled by later edits. And "right = '
        'tray, network, audio, display, power" describes the '
        'reference layout, not this bar.'),
    blank,
    ...para('#',
        'How the end lane got to its present ten entries is the real '
        'story, and git has it with timestamps:'),
    ...pt('#',
        '2026-09-19 18:28 (d552dfd)',
        'end = tray, custom_button, keyboard_layout, volume, '
        'control-center, session. Center = media, clock. The '
        'custom_button was a static ethernet glyph with the tooltip '
        '"Wired — enp34s0".'),
    ...pt('#',
        '2026-09-21 14:21 (0f56aeb)',
        'CPU, RAM and GPU readouts added before custom_button, "that '
        'open the System tab".'),
    ...pt('#',
        '14:38 (7569527)',
        'custom_button replaced by sysmon_net: the static glyph '
        'becomes a live download speed.'),
    ...pt('#',
        '18:22 (c95eb58)',
        'volume_input, the microphone, added after volume.'),
    ...pt('#',
        '22:32 (0cf06e1)',
        'center reordered from media, clock to clock, media. The last '
        'bar change in the history.'),
    ...para('#',
        'Nine commits touched the bar in one day, between 14:21 and '
        '22:32. The longest silence was 3 hours 44 minutes (14:38 to '
        '18:22); the shortest gap was 2 minutes (c95eb58 to a3411aa). '
        'That pace reads like a desk session with hot reload on, '
        'tuning by looking, not like planned releases. The commit '
        'sizes agree: eight of the nine add 13 lines or fewer.'),
    ...sec('the bar: geometry'),
    ...code('toml', 'home/.config/noctalia/config.toml · [bar.default] geometry', r'''
[bar.default]
position   = "top"
thickness  = 32
scale      = 1.0
font_scale = 0.8
# Quattro ships the bar opaque; transparency is a deliberate toggle, not the default.
background_opacity = 0.96
# Rounded, slightly floating bar.
radius               = 14
radius_top_left      = 14
margin_ends          = 10
concave_edge_corners = false'''),
    ...pt('#',
        'thickness = 32, font_scale = 0.8',
        'font_scale is a text-only multiplier (docs: 1.0 default, '
        'range 0.2 to 2.5), so labels run at 80 percent inside a '
        '32-pixel bar. The same bias toward small type shows up in '
        'the terminal (font-size 7.5) and in GTK (8).'),
    ...pt('#',
        'background_opacity = 0.96',
        'the comment says the reference ships the bar opaque and '
        '"transparency is a deliberate toggle", and 0.96 keeps four '
        'percent of the wallpaper showing. hyprland.lua has no layer '
        'rule for noctalia’s surfaces (the blur rule in noctalia’s '
        'Hyprland docs is not applied here), so nothing is blurred '
        'behind the bar; at 0.96 the effect is a faint tint.'),
    ...pt('#',
        'radius 14, margin_ends 10',
        'margin_ends insets the bar from both ends along its length. '
        'margin_edge is not set; the docs describe positive values as '
        'what "float" the bar from the screen edge, so here the bar '
        'still touches the top edge. "Slightly floating" in the '
        'comment is really "inset left and right".'),
    ...pt('#',
        'radius_top_left = 14',
        'duplicates radius. The docs call radius the global fallback '
        'that per-corner values override, so this line changes '
        'nothing today. The block was added by 208de62, which says it '
        'moved geometry out of the GUI state file; a stray per-corner '
        'key is the kind of thing a GUI would have saved. That is a '
        'guess, not something the commit states.'),
    ...pt('#',
        'concave_edge_corners = false',
        'the docs’ sample block shows true. False keeps all four '
        'corners convex, so the bar reads as a rounded tab and not as '
        'a shape that flares into the screen corners.'),
    ...sec('styling: restraint by default'),
    ...code('toml', 'home/.config/noctalia/config.toml · widget styling (trimmed)', r'''
# ── Widget styling ───────────────────────────────────────────────────────
# Omarchy is restrained: plain icons and text, with the active workspace as
# the one emphasised element. No capsule on the clock.
[widget.spacer]
length = 12

[widget.workspaces]
# No background pill — indicators sit bare on the bar.
capsule = false

[widget.clock]
capsule     = false
font_weight = 500

[widget.media]
capsule = false
...
[widget.launcher]
color = "primary"

[widget.session]
color = "error"'''),
    ...para('#',
        'The comment states the rule: "Omarchy is restrained: plain '
        'icons and text, with the active workspace as the one '
        'emphasised element." In configuration terms that is capsule '
        '= false on workspaces, clock, media and every readout (the '
        'docs list false as the bar default, so these are explicit '
        'rather than necessary), and two colour accents: the launcher '
        'takes the "primary" role and the session (power) button '
        'takes "error".'),
    ...para('#',
        'Both accents are palette roles, not hex values. The docs '
        'recommend exactly that so widget styling "follows the active '
        'palette", and it is the same idea as the templates above: '
        'pick the colours once, upstream of the widgets. The session '
        'button’s red is not decoration; the physical power key was '
        'rebound to the same panel in commit 0dc7770 (hyprland.lua '
        'binds XF86PowerOff to "noctalia msg panel-toggle session", '
        'and system/etc/systemd/logind.conf.d/10-power-key.conf makes '
        'logind ignore the key), so the red button and the hardware '
        'key are one action.'),
    ...para('#',
        'The workspaces widget has only capsule = false; its pill '
        'style and numeric labels are defaults, and hyprland.lua '
        'binds workspaces 1 to 9, so the pills match the keys.'),
    ...sec('readouts: four named sysmon instances'),
    ...code('toml', 'home/.config/noctalia/config.toml · network and CPU readouts (trimmed)', r'''
[widget.sysmon_net]
# Live download speed on the wired link, with the ethernet glyph (no Wi-Fi here).
type          = "sysmon"
stat          = "net_rx"
interface     = "enp34s0"
glyph         = "ethernet"
# Short units (3.9k, 12M) keep the label narrow.
network_speed_compact = true
visualization = "none"
capsule       = false

[widget.sysmon_net.actions]
left = "panel-toggle control-center system"
right = "panel-toggle control-center system"
...
# System resources. One sysmon widget shows one stat, hence three named
# instances; each click opens the Control Center on its System tab.
[widget.sysmon_cpu]
type          = "sysmon"
stat          = "cpu_usage"
visualization = "none"
capsule       = false

[widget.sysmon_cpu.actions]
left = "panel-toggle control-center system"
right = "panel-toggle control-center system"'''),
    ...para('#',
        '"One sysmon widget shows one stat, hence three named '
        'instances" (the comment; the fourth, the network, joined 17 '
        'minutes later). The mechanism is naming: the lane lists '
        'names, and a name that is not itself a built-in type needs '
        '"type = " to say what it is. The same trick makes '
        'volume_input a second volume widget. The stat names '
        '(cpu_usage, ram_pct, gpu_usage, net_rx) come from the docs’ '
        'catalog; visualization = "none" turns the docs’ default '
        'gauge into plain text, and capsule = false keeps them bare.'),
    ...pt('#',
        'the network instance',
        'binds to enp34s0 and keeps the ethernet glyph because, in '
        'the comment’s words, there is "no Wi-Fi here". The name '
        'follows systemd’s predictable-interface scheme: en for '
        'Ethernet, p34 for PCI bus 34, s0 for slot 0. '
        'network_speed_compact turns "3.9 kB/s" into "3.9k" so the '
        'number does not widen the bar as it changes.'),
    ...pt('#',
        'where the numbers come from',
        'one shared sampler thread, with intervals the config leaves '
        'at the docs’ defaults: CPU and RAM every 2 s, network 3 s, '
        'GPU 5 s. For NVIDIA the GPU stats are read through NVML '
        'rather than by running nvidia-smi, and GPU probes only run '
        'while something displays a GPU stat, so a permanent readout '
        'means permanent probing. NVML comes from the driver’s '
        'userspace package (the docs say nvidia-utils); aur.txt lists '
        'nvidia-580xx-utils, and whether that ships libnvidia-ml.so.1 '
        'is not something this repo shows.'),
    ...pt('#',
        'colour as a warning',
        'per the docs, each readout tints toward its highlight_color '
        '(default "error") as the value passes an activity threshold: '
        'CPU 50 and 90 percent, RAM 60 and 90, GPU 50 and 95, '
        'download 1 and 50 MB/s. None of that is configured here, so '
        'a plain 1 MB/s download already starts to tint the network '
        'readout.'),
    ...para('#',
        'The history is a nice small lesson in replacing a '
        'placeholder with the real thing. The first network indicator '
        'was a custom_button whose only job was to show that the link '
        'was wired. Its own comment recorded a trap: a bare "command" '
        'key is "the deprecated spelling" and "raises a Legacy '
        'setting banner in Settings", so the click handler used the '
        'modern actions table. Seventeen minutes after the CPU, RAM '
        'and GPU readouts landed, commit 7569527 deleted the button '
        'and its comment and put a live number in the same slot.'),
    ...sec('actions: noctalia commands, not shell commands'),
    ...code('toml', 'home/.config/noctalia/config.toml · volume and microphone', r'''
# Left click mutes; right click opens the Audio tab.
[widget.volume.actions]
left = "volume-mute"
right = "panel-toggle control-center audio"

# Microphone level, next to the output volume.
[widget.volume_input]
type   = "volume"
device = "input"

[widget.volume_input.actions]
left = "mic-mute"
right = "panel-toggle control-center audio"'''),
    ...para('#',
        'Every clickable widget takes an actions table that binds a '
        'gesture to a command. Eleven of the 16 action lines in this '
        'file open a Control Center tab and the rest mute, play or '
        'skip. The history of how they got their present form '
        'includes a bug fix made four minutes after the code it '
        'fixed. On 2026-09-21 the actions were written in two steps '
        '(18:24 left click mutes, 18:28 right click opens the tab) '
        'with strings like "noctalia msg panel-toggle control-center '
        'system", which is exactly what one types in a terminal or '
        'binds in hyprland.lua. At 18:32 commit 931dc59, "widget '
        'actions take noctalia commands, not shell commands", '
        'stripped the "noctalia msg " prefix from all twelve lines.'),
    blank,
    ...para('#',
        'The docs make the rule explicit. An action is one of three '
        'things: "<command> [arguments]", which runs an IPC command '
        '"exactly as noctalia msg would"; "exec <command line>", '
        'which runs a shell command; or "none". A misspelled command '
        'is logged once with the exact config path and the gesture '
        'does nothing; it is never silently treated as a shell '
        'command. Read against that, the old strings had the shape of '
        'the exec form without the exec word, which an IPC parser '
        'would take as an unknown command called "noctalia". The '
        'commit message records the rule rather than the symptom, so '
        'that reading is mine, not the author’s.'),
    blank,
    ...para('#',
        'The docs add why to prefer the built-in form: it is faster, '
        'reports its own errors and "stays correct when the shell '
        'changes underneath it". The lesson is general: when a config '
        'field takes a command vocabulary and also offers an escape '
        'hatch, find out which one it expects before pasting in a '
        'terminal command that works.'),
    blank,
    ...para('#',
        'The same vocabulary has several entry points in this repo, '
        'which is why the strings look familiar:'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · keys that use the same verbs (trimmed)', r'''
hl.bind("XF86PowerOff", hl.dsp.exec_cmd("noctalia msg panel-toggle session"), { locked = true })
...
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("noctalia msg volume-mute"),    { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("noctalia msg mic-mute"),       { locked = true })
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("noctalia msg media toggle"),   { locked = true })'''),
    ...pt('#',
        'volume-mute, mic-mute',
        'the bar’s left click on the volume widgets, and the '
        'XF86AudioMute and XF86AudioMicMute keys. Mouse and keyboard '
        'agree because they call the same command, and the OSD '
        'appears either way (the hyprland.lua comment: "routed '
        'through noctalia so the OSD shows").'),
    ...pt('#',
        'media toggle',
        'the media widget’s left click and the XF86AudioPlay key.'),
    ...pt('#',
        'panel-toggle session',
        'the session button on the bar and the power key.'),
    ...pt('#',
        'notification-show',
        'not a bar action, but the same IPC reaching in from outside: '
        'gamemode.ini runs "noctalia msg notification-show" when a '
        'game starts and ends (see that page).'),
    ...sec('the media widget: moving a default without losing it'),
    ...code('toml', 'home/.config/noctalia/config.toml · media', r'''
[widget.media]
capsule = false

# Click plays/pauses; right click opens the Media tab; scroll up for the
# previous track, down for the next.
[widget.media.actions]
left        = "media toggle"
right       = "panel-toggle control-center media"
scroll_up   = "media previous"
scroll_down = "media next"'''),
    ...para('#',
        'noctalia’s own docs for the media widget give the defaults: '
        'left click opens the Media tab, right click toggles '
        'play/pause, and the mouse side buttons skip tracks. This '
        'config swaps the first two and adds scrolling: left plays or '
        'pauses, scroll up goes to the previous track, scroll down to '
        'the next.'),
    blank,
    ...para('#',
        'The swap happened in two commits eight minutes apart. '
        '377422e (18:53) added left = "media toggle" and the scroll '
        'bindings under the comment "Click plays/pauses; scroll up '
        'for the previous track, down for the next". That took the '
        'Media tab off the left click. 99ffea8 (19:01) gave the '
        'displaced action a new home: right = "panel-toggle '
        'control-center media", with the comment rewritten to mention '
        'it. Moving a default is a small refactor with the same rule '
        'as a larger one: do not drop the old behaviour while adding '
        'the new, relocate it.'),
    ...para('#',
        'The physical keys XF86AudioPlay, XF86AudioStop, '
        'XF86AudioPrev and XF86AudioNext in hyprland.lua call media '
        'toggle, stop, previous and next, so the mouse, the keyboard '
        'and the media keys all drive the same MPRIS player.'),
    ...sec('the control center: panels that match the machine'),
    ...code('toml', 'home/.config/noctalia/config.toml · [control_center] and the tiles (trimmed)', r'''
# ─── Control Center ──────────────────────────────────────────────────────
[control_center]
width                = 700
sidebar              = "compact"
show_shortcut_labels = true
show_session_button  = true
# This box has no wireless adapter and bluez is not installed, so those
# tabs only ever showed a "?" or a crossed-out icon.
# No battery or AC device in /sys/class/power_supply and UPower is not
# installed, so the battery section can never show anything.
hidden_tabs = [ "network", "bluetooth", "power" ]
...
[[control_center.shortcuts]]
type = "audio"

[[control_center.shortcuts]]
type = "mic_mute"
...
[[control_center.shortcuts]]
type = "wallpaper"

[[control_center.shortcuts]]
type = "session"
'''),
    ...para('#',
        'width = 700, sidebar = "compact", show_shortcut_labels and '
        'show_session_button all equal the defaults in the docs’ '
        'table, so again they are pinned rather than chosen. '
        'hidden_tabs is the real decision, and its comments carry the '
        'evidence: the box has no wireless adapter and no bluez, so '
        'those tabs "only ever showed a "?" or a crossed-out icon"; '
        'there is no battery or AC device in /sys/class/power_supply '
        'and UPower is not installed, "so the battery section can '
        'never show anything". The docs add that the Power tab only '
        'opens when UPower or power-profiles-daemon exists and that '
        'the Network tab is NetworkManager-backed, so hiding them is '
        'housekeeping rather than a workaround.'),
    blank,
    ...para('#',
        'It also explains an earlier choice. The readouts and volume '
        'widgets open the System and Audio tabs, never Network: the '
        'Network tab is hidden, and the System tab (docs: CPU, RAM, '
        'GPU and network graphs) is where a network readout belongs.'),
    blank,
    ...para('#',
        'The tiles are the Home tab’s shortcut buttons. The docs’ '
        'default set is wifi, bluetooth, caffeine, nightlight, '
        'notification, power_profile. This config drops the three '
        'that cannot work here (wifi, bluetooth, power_profile; '
        '"replaced with things that actually do something here") and '
        'adds audio, mic_mute, clipboard, wallpaper and session. The '
        'clipboard tile has a keyboard twin, SUPER+CTRL+V (commit '
        '608f2d1).'),
    ...para('#',
        'One thing to check: the docs say "Up to 6 shortcuts are '
        'shown", and eight are declared, so on a version that '
        'enforces that limit the last two (wallpaper and session) '
        'would never appear. The repo does not pin the noctalia '
        'version and the limit comes from the current docs, so this '
        'is a suspicion, not a finding.'),
    ...sec('location, panels, wallpaper, lock screen'),
    ...code('toml', 'home/.config/noctalia/config.toml · location (trimmed)', r'''
# ─── Location ────────────────────────────────────────────────────────────
# Derived from the system timezone (Indian/Antananarivo) so the clock card
# stops reading "No location set". Change if that's not where you are.
[location]'''),
    ...para('#',
        'The coordinates are a city-level value taken from the system '
        'timezone; the comment says so and says the point was to stop '
        'the clock card reading "No location set". Per the docs '
        '[location] is the single source of location for the whole '
        'shell, feeding weather, Night Light and (in auto mode) the '
        'theme, and manual coordinates are used when auto-locate and '
        'address are off. With the theme pinned to dark, the Night '
        'Light tile and the clock card are what consume it. It is a '
        'city, not a street address.'),
    ...code('toml', 'home/.config/noctalia/config.toml · panels', r'''
# ─── Panels ──────────────────────────────────────────────────────────────
# "glass" made the Control Center melt into whatever was behind it. Solid
# plus an outline and a drop shadow reads as its own surface.
[shell.panel]
transparency_mode = "solid"
borders           = true
shadow            = true
floating_offset   = 10
# Attached panels are borderless by design, so the Control Center floats:
# that is what lets the outline and shadow actually draw around it.
control_center_placement = "floating"'''),
    ...para('#',
        'This block is a small chain of reasoning, readable straight '
        'from the comments. "glass" made the Control Center "melt '
        'into whatever was behind it", so the panels are solid. A '
        'solid panel wants an outline and a shadow to read as its own '
        'surface. But attached panels are borderless by design (the '
        'docs agree: attached panels "stay borderless so they remain '
        'visually clean against the bar"), so the Control Center is '
        'switched to floating, which is the only way the outline and '
        'shadow can draw. Floating then needs a gap from the bar, '
        'which is floating_offset = 10 (docs sample: 8).'),
    ...code('toml', 'home/.config/noctalia/config.toml · wallpaper and lock screen', r'''
# ─── Wallpaper ───────────────────────────────────────────────────────────
[wallpaper.default]
path = "/home/xynorash/Pictures/Wallpapers/starry-night-tokyo.png"

# ─── Lock screen ─────────────────────────────────────────────────────────
# Widgets on (clock, media, session buttons). Their on-screen positions are
# per-monitor and stay in noctalia's own state file.
[lockscreen_widgets]
enabled = true'''),
    ...para('#',
        'The wallpaper path is absolute (/home/xynorash/...), which '
        'the README calls out as something to adjust for another '
        'username. The image itself is generated by '
        'tools/generate-wallpaper.py (stdlib only, seed 7749, 1920 by '
        '1080) and copied into place by install.sh with cp -n.'),
    ...para('#',
        'Notice the direction of the dependency. noctalia can derive '
        'a palette from the wallpaper (the docs’ source = '
        '"wallpaper"), but this config uses the built-in Tokyo-Night '
        'palette and the wallpaper script takes its colours from that '
        'palette: its docstring says "Colours are taken from the '
        'Tokyo Night palette so the wallpaper matches the rest of the '
        'desktop". Palette first, image second.'),
    ...para('#',
        'For the lock screen only the on/off switch is tracked. The '
        'comment says widget positions are per-monitor and stay in '
        'noctalia’s own state file, which matches the docs: each '
        'lock-screen widget carries an output name and coordinates, '
        'and GUI edits go to settings.toml. The README names this as '
        'the one thing the repo does not reproduce.'),
    ...sec('history, and how it is checked'),
    ...pt('#',
        '2026-09-19 18:28',
        'd552dfd initial commit: theme, lanes, control center, '
        'location and panels already present.'),
    ...pt('#',
        '2026-09-19 18:34',
        '208de62 geometry, wallpaper path and lock-screen switch move '
        'in from the state file.'),
    ...pt('#',
        '2026-09-21 14:21-14:38',
        '0f56aeb and 7569527 the four readouts.'),
    ...pt('#',
        '2026-09-21 18:22-18:32',
        'c95eb58, a3411aa, e63abc2 microphone and click behaviour; '
        '931dc59 bare noctalia commands.'),
    ...pt('#',
        '2026-09-21 18:53-19:01',
        '377422e and 99ffea8 media gestures.'),
    ...pt('#',
        '2026-09-21 22:32',
        '0cf06e1 clock before media. Unchanged since.'),
    blank,
    ...para('#',
        'There are no tests and no CI in the repo, and for this kind '
        'of file that is an honest state of affairs: the check is '
        'looking at the screen. The evidence of method is the commit '
        'rhythm above, which hot reload makes possible.'),
    ...para('#',
        'noctalia ships a validator that would catch a class of '
        'mistakes the eye misses. "noctalia config validate" prints '
        'every problem as file:line:column with a dotted config path, '
        'reports unknown or obsolete keys and values outside their '
        'range as warnings, and exits 1 only for real errors. Run by '
        'hand or from a pre-commit hook it would have flagged the old '
        'command strings. Nothing in this repo runs it today; that is '
        'a suggestion, not a description.'),
    ...sec('limits and what is next'),
    ...pt('#',
        'stale comments',
        'niri in line 1; keyboard_layout listed as omitted while '
        'present; the reference "right =" lane quoted as if it were '
        'this bar. Fixing them is free and removes three small lies.'),
    ...pt('#',
        'tiles over the limit',
        'eight shortcut tiles against a documented maximum of six. '
        'Worth checking in the running shell.'),
    ...pt('#',
        'absolute paths',
        'the wallpaper path is tied to the username, so a second user '
        'needs an edit; the README says so.'),
    ...pt('#',
        'silent overrides',
        'any setting changed in the GUI wins over this file without a '
        'warning. The remedy in the docs is to inspect or delete the '
        'state file; "noctalia config export" shows the merged '
        'result.'),
    ...pt('#',
        'unanswered questions',
        'where adw-gtk3 comes from for the GTK templates, and whether '
        'a template run rewrites the ghostty theme through its '
        'symlink. Both are covered where they arise.'),
    ...pt('#',
        'docs versus installed version',
        'noctalia is a single unpinned line in packages/pacman.txt, '
        'and the behaviour quoted here comes from the current '
        'upstream docs. Where a sentence says "the docs", it may not '
        'describe the exact build on the machine.'),
    ...pt('#',
        'not reproduced',
        'per-monitor lock-screen widget placement, notification '
        'history and any GUI-only state, as the README admits.'),
    blank,
    link('→ github.com/xynorash/xyno-arch', 'https://github.com/xynorash/xyno-arch'),
  ],
);
