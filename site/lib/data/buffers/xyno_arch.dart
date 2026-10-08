import '../../models/project.dart';
import '../authoring.dart';

final Buffer xynoArchBuffer = Buffer(
  id: 'xyno-arch',
  fileName: 'xyno_arch.sh',
  icon: '\u{f303}',
  filetype: 'bash',
  repo: 'xyno-arch',
  summary: 'Hyprland desktop, reproducible · gaming-tuned',
  fallbackStars: 0,
  fallbackPushed: '2026-10-08',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'xyno-arch — my whole desktop, reproducible'),
    cm('#', 'Hyprland · Tokyo Night · tuned for gaming'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('hardware', 'Ryzen 7 5800X · GTX 980 (4 GB) · 1080p60'),
    kv('compositor', 'Hyprland, Lua config, dwindle layout'),
    kv('shell', 'noctalia — bar, launcher, lock, OSD'),
    kv('terminal', 'Ghostty · Yazi · JetBrainsMono Nerd Font'),
    kv('boot', 'systemd-boot + Unified Kernel Image'),
    kv('storage', 'btrfs + snapper, zram swap'),

    ...sec('the goal'),
    ...para('#',
        'Dotfiles usually capture how a desktop looks. This repo '
        'tries to capture how the machine behaves: user configs, '
        '/etc and /boot files, explicit package lists, a '
        'generated wallpaper and the small scripts that glue it '
        'together — enough to rebuild the box on a fresh Arch '
        'install and get the same system, including the parts '
        'that matter for gaming on an older GPU.'),
    blank,
    ...para('#',
        'Every file that is not obviously self-explanatory '
        'carries the reason it exists. When something is a '
        'workaround for a specific piece of hardware or software, '
        'the comment says which and why, so I do not have to '
        'rediscover it in a year.'),

    ...sec('the installer: safe by default'),
    ...para('#',
        'An installer that overwrites configs is an installer you '
        'are afraid to run. This one never destroys anything:'),
    ...code('bash', 'install.sh (excerpt)', r'''
backup() {
  local target=$1
  if [[ -e $target && ! -L $target ]]; then
    mv "$target" "$target.bak-$stamp"
    echo "  kept old $target as $target.bak-$stamp"
  elif [[ -L $target ]]; then
    rm "$target"
  fi
}

while IFS= read -r -d '' src; do
  rel=${src#"$repo"/home/}
  dst=$HOME/$rel
  mkdir -p "$(dirname "$dst")"
  backup "$dst"
  ln -s "$src" "$dst"
done < <(find "$repo/home" -type f -print0)'''),
    ...para('#',
        'A real file at the destination is moved aside with a '
        'timestamp; an existing symlink (from an earlier run) is '
        'simply replaced, which makes the script idempotent. The '
        'loop reads null-delimited from find, so filenames with '
        'spaces cannot break it. Configs are symlinked, not '
        'copied, so editing ~/.config/... edits the repo and '
        '“git diff” shows exactly what I changed.'),
    blank,
    ...para('#',
        'System files are a different risk class, so the script '
        'treats them differently. Ordinary /etc tuning is '
        'installed with --system, but the files that can stop the '
        'machine booting — mkinitcpio.conf, the kernel cmdline, '
        'loader.conf, the PAM stack — are deliberately NOT '
        'installed. The script prints them and tells me to diff '
        'them by hand and rebuild the initramfs myself. Automation '
        'should stop where a mistake costs a reboot into a rescue '
        'USB.'),

    ...sec('one palette, pushed everywhere'),
    ...para('#',
        'Tokyo Night is chosen once, in noctalia’s config, and '
        'rendered into every tool by template:'),
    ...code('ini', 'home/.config/noctalia/config.toml (excerpt)', r'''
[theme]
mode    = "dark"
source  = "builtin"
builtin = "Tokyo-Night"

[theme.templates]
enable_builtin_templates = true
# One palette pushed into everything.
builtin_ids = [ "hyprland", "ghostty", "gtk3", "gtk4" ]
enable_community_templates = true
community_ids = [ "yazi" ]'''),
    ...para('#',
        'Changing theme is one switch and the terminal, '
        'compositor borders, GTK apps and file manager follow. '
        'The repo tracks the hand-written layer (palette, bar '
        'geometry, lock screen, widgets) and ignores what the '
        'shell generates itself, so generated files cannot fight '
        'the repo. Only per-monitor widget placement stays '
        'untracked, which is honest about what can and cannot be '
        'reproduced.'),
    blank,
    ...para('#',
        'Even the wallpaper is code. A stdlib-only Python script '
        'writes the PNG itself (zlib and struct, no imaging '
        'library): a smooth vertical gradient between palette '
        'stops, a diagonal galactic band built from layered '
        'value noise, and a seeded starfield in palette colours. '
        'The seed and size are two constants, so the sky is '
        'reproducible and changeable.'),
    ...code('python', 'tools/generate-wallpaper.py (excerpt)', r'''
def grad(v):
    """Smooth vertical gradient. Interpolating every stop
    avoids the visible seam a branch between two ranges
    would leave."""
    for i in range(len(STOPS) - 1):
        v0, c0 = STOPS[i]
        v1, c1 = STOPS[i + 1]
        if v <= v1:
            t = (v - v0) / (v1 - v0)
            t = t * t * (3 - 2 * t)      # smoothstep
            return tuple(c0[k] + (c1[k] - c0[k]) * t
                         for k in range(3))'''),

    ...sec('games enter performance mode by themselves'),
    ...para('#',
        'GameMode switches the CPU governor to performance while '
        'a game runs and back afterwards. Normally you set a '
        'launch option per game. That does not scale across a '
        'library, so I made the compositor do it. Proton names '
        'every game window steam_app_<appid>; Hyprland can run '
        'code when a window opens:'),
    ...code('lua', 'home/.config/hypr/hyprland.lua', r'''
hl.on("window.open", function(w)
    if w and w.initial_class
       and w.initial_class:match("^steam_app_%d+$") then
        hl.exec_cmd("/home/xynorash/.local/bin/gamemode-attach "
                    .. w.pid)
    end
end)'''),
    ...para('#',
        'Note what it deliberately does not match: Steam’s own '
        'client window has class “steam”, so opening the store '
        'does not spin the CPU up. The helper that receives the '
        'pid has to be careful, because the GameMode request is '
        'a toggle:'),
    ...code('bash', 'home/.local/bin/gamemode-attach (excerpt)', r'''
# `gamemoded -r PID` toggles, so a game that opens two
# windows from one process would switch itself back off.
# An atomic mkdir lock per PID makes a second call a no-op.
grep -q libgamemodeauto "/proc/$pid/maps" 2>/dev/null && exit 0
lock="${XDG_RUNTIME_DIR:-/tmp}/gamemode-attach.$pid"
mkdir "$lock" 2>/dev/null || exit 0

gamemoded -r "$pid" >/dev/null 2>&1 &
req=$!
while kill -0 "$pid" 2>/dev/null; do sleep 5; done
kill "$req" 2>/dev/null
rmdir "$lock" 2>/dev/null'''),
    ...pt('#', 'mkdir as a lock',
        'mkdir either creates the directory or fails, atomically, '
        'with no race between “check” and “create”. A shell '
        'script has no mutex; this is the portable one.'),
    ...pt('#', 'libgamemodeauto check',
        'a game launched through gamemoderun registers itself. '
        'Registering it again would toggle it OFF, so the script '
        'inspects the process’s mapped libraries and steps aside.'),
    ...pt('#', 'cleanup',
        'the helper blocks while the game runs, then removes its '
        'lock, so a second launch of the same pid works.'),
    ...code('ini', 'home/.config/gamemode.ini', r'''
[general]
; Pin the Ryzen to the performance governor while a game
; runs, then drop back to powersave (amd-pstate active mode).
desiredgov=performance
defaultgov=powersave
inhibit_screensaver=1'''),

    ...sec('tuning an old GPU on purpose'),
    ...para('#',
        'A GTX 980 has 4 GB of VRAM, which makes VRAM, not '
        'compute, the thing to watch — so MangoHud shows it on '
        'screen. Each tweak below exists to remove a specific '
        'source of stutter or latency:'),
    blank,
    ...pt('#', 'power limit',
        'a oneshot systemd unit raises the card from its 180 W '
        'default to the 225 W its board allows, so it holds boost '
        'clocks under sustained load instead of power-throttling.'),
    ...code('ini', 'system/etc/systemd/system/nvidia-powerlimit.service', r'''
[Service]
Type=oneshot
# Default is 180 W; the board allows up to 225 W.
ExecStart=/usr/bin/nvidia-smi -pm 1
ExecStart=/usr/bin/nvidia-smi -pl 225
RemainAfterExit=yes'''),
    ...pt('#', 'scheduler',
        'scx_lavd, a sched_ext scheduler written by Igalia for '
        'the Steam Deck: it finds latency-critical threads '
        '(render, input) and keeps them from being starved by '
        'background work. On a desktop with mains power, '
        'core-compaction is disabled — use every core.'),
    ...pt('#', 'presentation',
        'direct scanout hands fullscreen games straight to the '
        'display, skipping a composite pass; tearing is permitted '
        'globally but a window rule enables immediate '
        'presentation only for steam_app_ windows, so the desktop '
        'stays tear-free.'),
    ...pt('#', 'what is left alone',
        'SDL_VIDEODRIVER is unset on purpose: forcing it breaks '
        'Steam titles. DISPLAY is kept for XWayland because the '
        'Steam client itself is X11-only.'),

    ...sec('network tuning, with the reasoning'),
    ...para('#',
        'The WAN is PPPoE at an MTU of 1492 and the interesting '
        'servers are far away, so the settings answer those two '
        'facts specifically:'),
    ...code('ini', 'system/etc/sysctl.d/99-network-tuning.conf (excerpt)', r'''
# Recover from path-MTU black holes instead of stalling.
net.ipv4.tcp_mtu_probing=1
# BBR paces to measured bottleneck bandwidth instead of
# filling queues until loss; fq is the qdisc it paces through.
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
# Raise the ceiling for apps that size their own buffers.
net.core.rmem_max=33554432
net.core.wmem_max=33554432
# Cap unsent data queued in a socket so latency-sensitive
# traffic isn't stuck behind a bulk upload's backlog.
net.ipv4.tcp_notsent_lowat=131072'''),
    ...para('#',
        'The last line is the interesting one: it trades a little '
        'bulk-transfer throughput for latency, because 128 KB '
        'still fills a 1 Gbps LAN and a ~100 Mbps WAN, while an '
        'unbounded send queue is how a big upload ruins a game or '
        'an SSH session. A small script, intl-speedtest, compares '
        'local and international download speed over fast.com’s '
        'servers, so the tuning can be judged with numbers.'),
    blank,
    ...para('#',
        'Memory follows the same logic. zram is compressed swap '
        'in RAM, so swapping is cheap; vm.swappiness is set to '
        '180 (modern kernels accept up to 200) with page-cluster 0, '
        'so the kernel leans on it early and reads single pages.'),

    ...sec('small scripts that earn their keep'),
    ...para('#',
        'The keybinding cheat sheet cannot go stale because it is '
        'generated from the config it describes — an awk program '
        'reads hyprland.lua, treats the nearest comment above a '
        'bind as its heading, resolves variables like mod, and '
        'pages the result. Super+Shift+/ shows it in a floating '
        'terminal.'),
    ...code('awk', 'home/.config/hypr/keybinds.sh (excerpt)', r'''
# A short -- comment above a bind becomes its section heading.
/^[ \t]*--/ {
    c = trim($0); sub(/^--+[ \t]*/, "", c)
    if (c ~ /^[A-Za-z]/ && length(c) < 40) pending = c
    next
}

/hl\.bind\(/ {
    # Split key expression from dispatcher at the comma
    # before hl.dsp. Must tolerate column alignment.
    if (!match(line, /,[ \t]*hl\.dsp/)) next'''),
    ...para('#',
        'Another: clicking a notification should land on the app '
        'that sent it. Hyprland honours the activation token '
        'noctalia passes, but not every app uses tokens, so '
        'notification-focus watches for the click, finds the '
        'sender in noctalia’s history and focuses its window by '
        'class — with a short grace period so apps that do raise '
        'themselves are not fought.'),

    ...sec('taming windows that fight the tiler'),
    ...para('#',
        'WinApps runs Windows apps in a VM and shows them as '
        'Linux windows (FreeRDP RemoteApp). Their class and title '
        'arrive after the window maps, so static window rules '
        'never match; tiling also resizes the X window while the '
        'server is still repainting, so frame and content '
        'disagree and the app stalls. The answer is to react to '
        'events instead of matching rules:'),
    ...code('lua', 'home/.config/hypr/hyprland.lua (trimmed)', r'''
local function tame_winapps(w)
    if not (w and w.class and w.class:match("^Microsoft ")) then
        return
    end
    if w.title:match("^Administrator: .*powershell%.exe$") then
        -- the VM's helper: park it on a hidden workspace
        hl.dispatch(hl.dsp.window.move({
            workspace = "special:winapps",
            follow = false, window = w }))
    elseif not w.floating then
        hl.dispatch(hl.dsp.window.float({
            action = "enable", window = w }))
    end
end
hl.on("window.open",  tame_winapps)
hl.on("window.class", tame_winapps)
hl.on("window.title", tame_winapps)'''),
    ...para('#',
        'A floating window is resized once, on mouse release, '
        'which is what the remote app can cope with. The same '
        'handler is registered for open, class change and title '
        'change, because any of those can be the moment the '
        'window finally reveals what it is.'),

    ...sec('the point of all of it'),
    ...para('#',
        'A desktop is a pile of decisions. Written as files with '
        'reasons attached, they can be reviewed, diffed and '
        'rebuilt; left as clicks, they are folklore. The repo '
        'also states its own limits — absolute paths assume one '
        'username, boot files are manual, generated state is not '
        'tracked — because a reproducibility claim is only worth '
        'as much as its caveats.'),
    blank,
    link('→ github.com/XNash/xyno-arch', 'https://github.com/XNash/xyno-arch'),
  ],
);
