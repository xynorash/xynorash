import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/home/.config/hypr/xdph.conf',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'xdph.conf — two switches for screen sharing'),
    cm('#', 'one workaround for an NVIDIA driver, one convenience for Chrome'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'configuration of xdg-desktop-portal-hyprland, the screen-capture backend'),
    kv('language', 'xdph config syntax: nested sections of key = value'),
    kv('size', '9 lines, 2 settings, both inside one screencopy section'),
    kv('history', '2 commits, 2 min 19 s apart, both on 2026-09-21'),
    kv('installed as', '~/.config/hypr/xdph.conf, a symlink made by install.sh'),
    ...sec('why this file exists'),
    ...para('#',
        r'On Wayland an application never grabs the screen itself. Chrome '
        r'asks the desktop portal service for a ScreenCast session, the '
        r'portal hands the request to a backend that knows the compositor, '
        r'and the backend streams frames back over PipeWire. On this '
        r'machine the backend is xdg-desktop-portal-hyprland, usually '
        r'shortened to xdph. The routing is decided in '
        r'home/.config/xdg-desktop-portal/hyprland-portals.conf, which '
        r'sends the ScreenCast and Screenshot interfaces to "hyprland"; '
        r'the package itself is listed in packages/pacman.txt next to '
        r'xdg-desktop-portal-gtk.'),
    blank,
    ...para('#',
        r'This file is the backend’s own configuration, a different thing '
        r'from the routing file. It is nine lines long and holds exactly '
        r'two settings. Each of them answers one concrete annoyance that '
        r'was met on this desktop, and each was committed on its own, '
        r'which makes the file easy to read as a story: first the '
        r'stream broke, then the picker got in the way of repeat shares.'),
    ...sec('the whole file'),
    ...code('ini', 'home/.config/hypr/xdph.conf', r'''
# Screen sharing (xdg-desktop-portal-hyprland).
screencopy {
    # Chrome drops the stream while negotiating DMA-BUF buffers on the
    # NVIDIA 580xx driver; hand it shared-memory frames instead.
    force_shm = true
    # Pre-tick "allow a restore token" in the picker, so an app that asks to
    # remember the choice (Chrome does) skips the picker on later shares.
    allow_token_by_default = true
}'''),
    ...para('#',
        r'Both settings sit in the screencopy section, which is the part of '
        r'xdph that deals with getting pixels out of the compositor. Note '
        r'that each setting carries a comment naming the application and '
        r'the driver involved. That habit is the most reusable thing in the '
        r'file and the page returns to it at the end.'),
    ...sec('setting one: force_shm'),
    ...para('#',
        r'The commit that created the file is 8cc1177, dated 2026-09-21 '
        r'19:52:12 (+0300), titled "Screen sharing: shared-memory frames '
        r'so Chrome keeps the stream on NVIDIA". It has no body; the '
        r'two-line comment above the setting is the explanation, and it '
        r'is precise: Chrome drops the stream while negotiating DMA-BUF '
        r'buffers on the NVIDIA 580xx driver. By its wording the symptom '
        r'is a stream that is dropped, and the moment it drops is the '
        r'DMA-BUF negotiation.'),
    blank,
    ...para('#',
        r'Two ways of delivering a frame are in play. A DMA-BUF is a '
        r'handle to memory that stays on the GPU, so the consumer can use '
        r'it without a copy; it is the efficient path. Shared memory '
        r'(shm) is ordinary '
        r'system RAM: the compositor copies the frame into it and the '
        r'consumer reads it from there. Forcing shm means the efficient '
        r'path is never offered, so there is nothing to negotiate and '
        r'nothing to get wrong. Note that the comment describes a '
        r'detour, not a repair: "hand it shared-memory frames instead". '
        r'The DMA-BUF path is not fixed, only avoided.'),
    blank,
    ...para('#',
        r'The price is a copy per frame. As a back-of-envelope figure '
        r'(not a measurement from the repo, and assuming four bytes '
        r'per pixel): a 1920x1080 frame is 8,294,400 bytes, about 7.9 MiB, '
        r'so a 60 Hz stream is roughly 475 MiB per second of memory '
        r'traffic. The README gives the machine as a Ryzen 7 5800X at '
        r'1080p and 60 Hz, which is a plausible place to spend that '
        r'traffic; the repo contains no measurement of what it actually '
        r'costs, so treat the number as a scale, not a result.'),
    ...sec('why NVIDIA 580xx is the relevant detail'),
    ...para('#',
        r'The driver named in the comment is a specific branch, not "the '
        r'NVIDIA driver". packages/aur.txt lists nvidia-580xx-dkms, '
        r'nvidia-580xx-utils, lib32-nvidia-580xx-utils and '
        r'opencl-nvidia-580xx, and the README describes the build as '
        r'"tuned for gaming on older NVIDIA hardware" with a GTX 980 '
        r'(Maxwell, 4 GB). The package names suggest that this is a '
        r'pinned legacy driver branch kept for an older card; the repo '
        r'does not say why that branch was chosen, so that part is an '
        r'inference from the names.'),
    blank,
    ...para('#',
        r'What the comment buys is scope. Because it names the driver '
        r'branch, a future reader knows which condition makes the '
        r'workaround necessary. If the machine ever moves to a different '
        r'driver, the question to ask is whether Chrome still drops the '
        r'stream, and force_shm can be deleted if it does not. A bare '
        r'"force_shm = true" with no comment would be a line nobody dares '
        r'to remove.'),
    ...sec('setting two: allow_token_by_default'),
    ...para('#',
        r'Two minutes and nineteen seconds later, at 19:54:31, commit '
        r'6d97060 added the second setting under the title "Screen '
        r'sharing: remember the picked source for apps that ask". Again '
        r'no body; again the comment carries the reasoning.'),
    blank,
    ...para('#',
        r'The mechanism is a restore token. In the ScreenCast portal an '
        r'application can ask to have the user’s choice persisted; if it '
        r'does, the portal returns a token, and presenting that token on '
        r'the next session restores the same source without showing the '
        r'picker. The picker in xdph carries a checkbox for this, and the '
        r'comment says what the setting does to it: it pre-ticks "allow a '
        r'restore token". The comment also says which application '
        r'motivated it: "Chrome does" ask to remember the choice. Without '
        r'the pre-tick the box would have to be ticked by hand for each '
        r'share, and the point of the setting is that nobody has to '
        r'remember to.'),
    blank,
    ...para('#',
        r'The effect is narrow. Applications that do not ask '
        r'for a restore token are unaffected, since the setting only '
        r'changes the default state of a checkbox. And because the '
        r'wording is "pre-tick", the box can still be unticked for a '
        r'single share; nothing is hidden from the person at the keyboard.'),
    blank,
    ...para('#',
        r'There is a real trade-off and the repo does not discuss it. '
        r'Once a token has been granted, the application can restart '
        r'capture of that source without the picker, so the picker stops '
        r'being a fresh consent step for those applications. On a single '
        r'user desktop that is arguably a reasonable exchange for not '
        r're-picking a window at the start of every call, but it is a '
        r'choice, and '
        r'it is made globally for every application that asks.'),
    ...sec('how the file reaches the machine'),
    ...para('#',
        r'install.sh walks every regular file under home/ and symlinks '
        r'it to the same relative path under $HOME, moving any existing '
        r'file aside as a .bak-<timestamp> copy first. That is the whole '
        r'deployment story for this file.'),
    ...code('bash', 'install.sh · the link loop', r'''
echo "linking home configs"
while IFS= read -r -d '' src; do
  rel=${src#"$repo"/home/}
  dst=$HOME/$rel
  mkdir -p "$(dirname "$dst")"
  backup "$dst"
  ln -s "$src" "$dst"
  echo "  $dst -> $src"
done < <(find "$repo/home" -type f -print0)'''),
    ...para('#',
        r'The result is ~/.config/hypr/xdph.conf pointing back into the '
        r'repository, next to hyprland.lua. xdph reads its configuration '
        r'from the Hyprland config directory; that lookup rule comes '
        r'from xdph’s own documentation and from where the file lives, '
        r'not from anything written in this repo, and the relevant '
        r'documentation section could not be retrieved to quote it. '
        r'Whether a running xdph has '
        r'to be restarted to pick up an edit is likewise not stated '
        r'anywhere here.'),
    ...sec('what the repo does not contain'),
    ...pt('#', 'no evidence of the failure itself',
        'there is no log, no Chrome version, no bug link. The only '
        'record of the DMA-BUF problem is the comment and the commit '
        'title.'),
    ...pt('#', 'no measurement',
        'nothing records the CPU cost of shm frames, or whether other '
        'applications than Chrome were ever affected.'),
    ...pt('#', 'no test',
        'a screen share cannot be unit tested. The practical check, '
        'which the repo does not describe, is to start a share in '
        'Chrome and see whether it survives past the first seconds.'),
    ...pt('#', 'no per-application scoping',
        'as written, force_shm applies to every client of the '
        'backend, not only to Chrome.'),
    ...sec('what the file teaches'),
    ...para('#',
        r'The pattern worth keeping is "name the failure in the comment": '
        r'which program, which driver branch, at which phase it breaks. '
        r'A workaround written that way documents the bug, tells you '
        r'when it can be retired, and makes review possible for someone '
        r'who was not there. The second lesson is smaller: a default is '
        r'also a decision. allow_token_by_default changes nothing about '
        r'what is possible, only about what the person does not have to '
        r'remember, and it is still worth a commit of its own.'),
    blank,
    link('→ github.com/XNash/xyno-arch', 'https://github.com/XNash/xyno-arch'),
  ],
);
