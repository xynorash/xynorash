import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/home/.config/MangoHud/MangoHud.conf',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'MangoHud.conf — an overlay built to catch a 4 GB card running short'),
    cm('#', 'what the HUD shows, what it merely restates, and why VRAM got a line'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role',     'global config for the MangoHud in-game performance '
    'overlay'),
    kv('language', 'MangoHud config (key=value, bare words are switches)'),
    kv('size', '18 lines, 1 commit (d552dfd, 2026-09-19)'),
    kv('toggle', 'Right Shift + F12'),
    kv('hardware', 'GTX 980, 4 GB VRAM (README)'),
    ...sec('the problem this file answers'),
    ...para('#',
        'An overlay is only useful if it shows the number that '
        'explains the problem you actually have. On this machine the '
        'problem is written in the first two lines of the file, and '
        'they are the best-argued comment in the whole gaming setup:'),
    ...code('ini', 'home/.config/MangoHud/MangoHud.conf · the header', r'''
# Toggle with Shift_R+F12. VRAM is on screen deliberately: this GTX 980 has
# 4 GB against the game's 6 GB minimum, so VRAM is the number to watch.'''),
    ...para('#',
        'The card is a GTX 980 with 4 GB (README, "Built for a Ryzen '
        '7 5800X with a GTX 980"). The comment says the game it was '
        'tuned for lists 6 GB as its minimum. The game is not named, '
        'and the 6 GB figure exists only in that comment, so it is '
        'the author’s number, not something the repo checks. The '
        'reasoning is still sound and general: when a game wants more '
        'video memory than the card has, the driver pushes resources '
        'out to system memory over the PCIe bus, and the cost shows '
        'up as frame-time spikes, not as a lower average. That is why '
        'VRAM is "the number to watch".'),
    ...sec('the metrics block'),
    ...code('ini', 'home/.config/MangoHud/MangoHud.conf · switches', r'''
fps
frametime
frame_timing
gpu_stats
gpu_temp
vram
cpu_stats
cpu_temp
ram
gamemode'''),
    ...para('#',
        'Each bare word turns a readout on. Reading the README’s '
        'parameter table against the file separates the lines that '
        'change something from the lines that restate defaults:'),
    ...pt('#',
        'already on by default',
        'fps, frame_timing, cpu_stats and gpu_stats. The README says '
        'these four "have to be explicitly disabled", so listing them '
        'changes nothing today; frametime is in the same position, '
        'since the upstream example config switches it on too. '
        'Listing them makes the file a complete description of the '
        'HUD and protects it if a default ever changes, the same '
        'habit as the noctalia config.'),
    ...pt('#',
        'added by this file',
        'gpu_temp, cpu_temp, vram, ram and gamemode.'),
    ...para('#',
        'Each addition earns its place from the problem above.'),
    ...pt('#',
        'frametime and frame_timing',
        'frametime prints the last frame’s duration next to the FPS '
        'number; frame_timing draws the history as a line graph. FPS '
        'is an average over a moment, and a stutter is a single long '
        'frame, so the graph is where a VRAM spill shows up.'),
    ...pt('#',
        'vram and ram',
        'the README describes both as "system RAM/VRAM usage". Shown '
        'together they tell a spill story: VRAM pinned at the card’s '
        '4 GB while RAM climbs. One caveat from the same table: vram '
        'is system-wide, so it counts whatever else is using the '
        'card, such as the compositor and the shell. proc_vram, which '
        'shows the game process alone, is not enabled.'),
    ...pt('#',
        'gpu_temp, cpu_temp',
        'readouts to read together with the GPU load. They connect to '
        'another file in this repo: '
        'system/etc/systemd/system/nvidia-powerlimit.service raises '
        'the GPU’s power limit from 180 W to its 225 W maximum, with '
        'the stated aim of letting the GPU "hold its boost clock '
        'under sustained game load instead of power-throttling". The '
        'HUD shows load and temperature, which is part of the '
        'picture. Clocks (gpu_core_clock) and throttling '
        '(throttling_status) are separate switches, and both are off.'),
    ...code('ini', 'system/etc/systemd/system/nvidia-powerlimit.service · the comment the HUD checks', r'''
# Default is 180 W; the board allows up to 225 W. More headroom lets the GPU
# hold its boost clock under sustained game load instead of power-throttling.'''),
    ...pt('#',
        'gamemode',
        'the README: "Show if GameMode is on". It closes a loop with '
        'the next section.'),
    ...sec('the order of the lines is the order on screen'),
    ...para('#',
        'One detail of the file is easy to miss: the sequence is not '
        'arbitrary. MangoHud’s source (src/hud_elements.cpp, read on '
        'its master branch for this page; the packaged version may '
        'differ) has two code paths. The legacy path draws rows in a '
        'fixed order. The other path appends each recognised display '
        'parameter to the draw list as it is read from the config, so '
        'the file order is the screen order. This file turns the '
        'legacy layout off (next section), so reading it top to '
        'bottom predicts the HUD:'),
    ...pt('#',
        'fps, frametime',
        'the headline row.'),
    ...pt('#',
        'frame_timing',
        'the frame-time graph.'),
    ...pt('#',
        'gpu_stats, gpu_temp, vram',
        'GPU load and temperature, then video memory directly under '
        'it.'),
    ...pt('#',
        'cpu_stats, cpu_temp, ram',
        'the CPU equivalents, then system memory directly under them.'),
    ...pt('#',
        'gamemode',
        'the status line, last.'),
    ...para('#',
        'That grouping puts VRAM next to the GPU it belongs to and '
        'RAM next to the CPU, and it keeps the two memory figures one '
        'row apart, which is where you compare them during a spill. '
        'The file does not say the order is deliberate; it is '
        'consistent with a layout someone read top to bottom and '
        'tidied. The temperatures and frametime are not rows of their '
        'own: in the source they are modifiers of the fps, GPU and '
        'CPU rows, which is why they sit beside those lines.'),
    ...sec('gamemode on the HUD, and the bug it sits next to'),
    ...para('#',
        'The repo puts games into GameMode automatically. When a '
        'Steam game window opens, a hook in hyprland.lua calls '
        'home/.local/bin/gamemode-attach with the window’s process '
        'id, which asks the GameMode daemon to register that process. '
        'The HUD line is the visible result: GameMode on, or not.'),
    blank,
    ...para('#',
        'The history of that script has a one-hour bug story, and '
        'MangoHud is a character in it. The initial commit was at '
        '18:28 on 2026-09-19; at 19:28 the same day commit aebd41e '
        'landed with the message "gamemode-attach: leave '
        'self-registered games alone". Its body: a game started '
        'through gamemoderun registers itself; "calling gamemoded -r '
        'on it toggles GameMode back off. Skip processes that have '
        'libgamemodeauto loaded." The part that concerns this overlay '
        'is in the script’s own comment:'),
    ...code('bash', 'home/.local/bin/gamemode-attach · the self-registration guard', r'''
# Launched through gamemoderun, the game registers itself (libgamemodeauto is
# preloaded into it). Calling -r on it would toggle GameMode back off, so leave
# it alone. MangoHud loads plain libgamemode only to query status, so matching
# the "auto" library is specific to self-registration.
sleep 2
grep -q libgamemodeauto "/proc/$pid/maps" 2>/dev/null && exit 0'''),
    ...para('#',
        '"MangoHud loads plain libgamemode only to query status". '
        'That one sentence is the reason for a precise test. A game '
        'launched with gamemoderun gets libgamemodeauto preloaded, '
        'which registers it; MangoHud, when it shows the gamemode '
        'line, loads the plain libgamemode library only to ask '
        'whether GameMode is active. If the script grepped for '
        '"libgamemode" it would see MangoHud’s library in every game '
        'that has the overlay and wrongly skip it. Matching the '
        '"auto" library is specific to self-registration. Four '
        'letters are the whole difference between a script that works '
        'alongside the HUD and one that quietly never fires.'),
    ...para('#',
        'That is the transferable lesson: when two components load '
        'near-identical libraries into one process, a match on the '
        'shared prefix is a bug waiting for the second component to '
        'arrive.'),
    ...sec('the layout lines'),
    ...code('ini', 'home/.config/MangoHud/MangoHud.conf · layout', r'''
legacy_layout=false
position=top-left
font_size=18
background_alpha=0.5
round_corners=8'''),
    ...pt('#',
        'legacy_layout=false',
        'a real change, not a restated default. In MangoHud’s source '
        'the legacy layout starts enabled; the upstream example keeps '
        '"# legacy_layout=0" commented out, and the README notes that '
        'the exec option only works with legacy_layout=0. Turning it '
        'off is what makes the line order above meaningful. One '
        'subtlety in the source: switches are read with strtol, a C '
        'function that turns text into a number. "false" is not a '
        'number, so it reads as 0 and the line works, but "true" '
        'would read as 0 as well. A bare word is stored as 1, and an '
        'explicit 0 or 1 is the spelling that cannot mislead.'),
    ...pt('#',
        'position=top-left',
        'the README lists top-left as the default, so this restates '
        'it. No motive is recorded.'),
    ...pt('#',
        'font_size=18',
        'the README gives 24 as the default, so the text is 25 '
        'percent smaller. The README adds that width and height '
        'follow font_size automatically, so the whole HUD shrinks '
        'with it. On a 1920 by 1080 display with ten switches on, '
        'that is the line that keeps the overlay compact.'),
    ...pt('#',
        'background_alpha=0.5',
        'the upstream example also shows 0.5, so another restatement. '
        'A half-transparent backing keeps the numbers legible on '
        'bright scenes without hiding the scene.'),
    ...pt('#',
        'round_corners=8',
        'the default is 0. This is the one purely cosmetic change. It '
        'is close to the compositor’s rounding = 10 in hyprland.lua, '
        'which may be deliberate; the file does not say.'),
    ...sec('the toggle'),
    ...code('ini', 'home/.config/MangoHud/MangoHud.conf · the last line', r'''
toggle_hud=Shift_R+F12'''),
    ...para('#',
        'toggle_hud=Shift_R+F12 is MangoHud’s default key, and the '
        'README says so. It is written out anyway, and the first '
        'comment line repeats it, so the file answers its own most '
        'likely question. The repo README documents the same binding '
        'as "Right Shift + F12". Three places say it consistently. '
        'That is a cheap form of testing for documentation: if one '
        'changes, the other two are now wrong, and a search for the '
        'key finds all three.'),
    ...sec('where the file sits among MangoHud’s configs'),
    ...para('#',
        'The README lists the lookup order: an application-directory '
        'MangoHud.conf first, then per-application files in '
        '~/.config/MangoHud (<application>.conf for native programs, '
        'wine-<application>.conf for Wine and Proton), and the global '
        'MangoHud.conf last. This file is the global one, installed '
        'as a symlink by install.sh. A per-game file would override '
        'it, and the repo has none, so every game gets this HUD.'),
    ...para('#',
        'Two things the repo does not record. How MangoHud gets '
        'injected into a game (Steam launch options, an environment '
        'variable) is not tracked anywhere. And the overlay’s own '
        'cost in frame time has not been measured; at ten readouts '
        'and a graph it is small but not zero. packages/pacman.txt '
        'installs mangohud and lib32-mangohud, the second for 32-bit '
        'games.'),
    ...sec('limits and ideas'),
    ...pt('#',
        'throttling_status',
        'the upstream example enables it; this file does not. The '
        'README says it is "currently disabled by default for Nvidia '
        'as it causes lag on 3000 series". A GTX 980 is not one, and '
        'it is the readout that speaks most directly to the '
        'power-limit tuning above. Worth trying.'),
    ...pt('#',
        'proc_vram',
        'would separate the game’s memory from the desktop’s, making '
        'the 4 GB budget easier to read.'),
    ...pt('#',
        'logging',
        'MangoHud can record frame times to a file on a hotkey '
        '(README: toggle_logging with output_folder). This file is '
        'set up for glancing, not recording, so none of the repo’s '
        'claims about frame pacing come with data.'),
    ...pt('#',
        'nothing verified here',
        'no screenshot or measurement in the repo shows the HUD on a '
        'game. The reading above is from the config, the README and '
        'the commit history.'),
    blank,
    link('→ github.com/xynorash/xyno-arch', 'https://github.com/xynorash/xyno-arch'),
  ],
);
