import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/packages/aur.txt',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'aur.txt — nine packages, four of them a pinned GPU driver'),
    cm('#', 'what had to come from outside the official repositories'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'the explicit packages that are not in the sync repos'),
    kv('size', '9 names: 4 NVIDIA 580xx, 2 yay, 3 applications'),
    kv('hardware', 'GTX 980 (Maxwell, 4 GB), Ryzen 7 5800X'),
    kv('history', 'one commit, d552dfd (2026-09-19), never edited since'),
    kv('consumed by', 'nothing: install.sh never reads it'),

    ...sec('what this file is'),
    ...code('text', 'packages/aur.txt', r'''
google-chrome
jetbrains-toolbox
lib32-nvidia-580xx-utils
nvidia-580xx-dkms
nvidia-580xx-utils
opencl-nvidia-580xx
spotify
yay
yay-debug'''),
    ...para(
        '#',
        r'The sibling of pacman.txt: the same bare format, sorted '
        r'the same way, covering what pacman cannot find in the '
        r'sync repositories. The split between the two files is '
        r'itself information. It matches the usual way of '
        r'separating “installed from the repos” from “installed '
        r'from elsewhere” (my inference; the repo does not name '
        r'the command), and it means anyone who reads only '
        r'pacman.txt gets a machine with no proprietary GPU driver.'),
    blank,
    ...para(
        '#',
        r'The list falls into three roles. Four packages are the '
        r'GPU driver. Two are the tool that builds AUR packages. '
        r'Three are applications. The driver is the part with a '
        r'story, so most of this page is about it.'),

    ...sec('the 580xx stack'),
    ...pt(
        '#',
        'nvidia-580xx-dkms',
        r'the kernel modules, compiled on the machine by DKMS.'),
    ...pt(
        '#',
        'nvidia-580xx-utils',
        r'the userspace driver: GL, Vulkan, nvidia-smi and the rest.'),
    ...pt(
        '#',
        'lib32-nvidia-580xx-utils',
        r'the 32-bit half, so 32-bit games and Steam’s own '
        r'32-bit components can use the GPU.'),
    ...pt(
        '#',
        'opencl-nvidia-580xx',
        r'the OpenCL implementation. Nothing in the repo uses '
        r'OpenCL, so I cannot say what asked for it.'),
    blank,
    ...para(
        '#',
        r'The suffix is the point. These are not the stock '
        r'nvidia packages. They pin a specific driver branch, '
        r'580, and the repo mentions that number exactly once, in '
        r'a comment about screen sharing, quoted below. The README '
        r'says only that the setup is “tuned for gaming on older '
        r'NVIDIA hardware” and names the card: a GTX 980, Maxwell, '
        r'4 GB.'),
    blank,
    ...para(
        '#',
        r'Why a pinned branch for that card is not stated anywhere '
        r'in the repo, so this paragraph is outside knowledge and '
        r'labelled as such. To my knowledge NVIDIA’s 580 series is '
        r'the last driver branch that supports Maxwell-generation '
        r'GPUs, and newer branches dropped them; the AUR packages '
        r'named nvidia-580xx-* exist to keep that branch '
        r'installable on Arch after the main packages moved on. I '
        r'could not verify this from inside the repo, so please '
        r'treat it as the likely reason, not an established one.'),

    ...sec('what depends on the driver'),
    ...para(
        '#',
        r'Swapping the driver would not be a one-line change. Five '
        r'other files in the repo assume it, and walking through '
        r'them shows how far a single package choice reaches.'),
    blank,
    ...pt(
        '#',
        'system/etc/mkinitcpio.conf',
        r'puts nvidia, nvidia_modeset, nvidia_uvm and nvidia_drm in '
        r'MODULES, so the proprietary modules are in the initramfs. '
        r'They come from nvidia-580xx-dkms.'),
    ...pt(
        '#',
        'system/etc/systemd/system/nvidia-powerlimit.service',
        r'calls /usr/bin/nvidia-smi, which only exists once the '
        r'utils package is installed. The unit guards itself with '
        r'ConditionPathExists, so without the driver it is '
        r'skipped.'),
    ...pt(
        '#',
        'home/.config/MangoHud/MangoHud.conf',
        r'asks for gpu_stats, gpu_temp and vram, readings the '
        r'driver has to supply.'),
    ...pt(
        '#',
        'home/.config/hypr/xdph.conf',
        r'works around a Chrome bug that appears on this exact '
        r'driver branch (next section).'),
    ...pt(
        '#',
        'packages/pacman.txt',
        r'holds dkms, linux-headers and the three egl-* libraries '
        r'that the driver needs around it.'),
    blank,
    ...para(
        '#',
        r'Two absences are informative. The kernel command line '
        r'carries no NVIDIA parameter, only root, zswap and '
        r'filesystem options. And hyprland.lua sets none of the '
        r'environment variables that Wayland-on-NVIDIA guides '
        r'usually list (I searched for GBM_BACKEND, __GLX, LIBVA, '
        r'WLR_ and NVD_ and found none). Either the driver and '
        r'the egl-* libraries make them unnecessary on this '
        r'branch, or they were never needed here. The repo has no '
        r'comment either way.'),

    ...sec('the one place the branch is named'),
    ...code('conf', 'home/.config/hypr/xdph.conf · screen sharing', r'''
# Screen sharing (xdg-desktop-portal-hyprland).
screencopy {
    # Chrome drops the stream while negotiating DMA-BUF buffers on the
    # NVIDIA 580xx driver; hand it shared-memory frames instead.
    force_shm = true
    # Pre-tick "allow a restore token" in the picker, so an app that asks to
    # remember the choice (Chrome does) skips the picker on later shares.
    allow_token_by_default = true
}'''),
    ...para(
        '#',
        r'The story is told by two commits two minutes apart on '
        r'2026-09-21. At 19:52, 8cc1177: “Screen sharing: '
        r'shared-memory frames so Chrome keeps the stream on '
        r'NVIDIA”. At 19:54, 6d97060: “remember the picked source '
        r'for apps that ask”. The first fixes a bug. The second, '
        r'by the config comment, lets an app that asks to remember '
        r'its choice (Chrome does) skip the picker on later '
        r'shares.'),
    blank,
    ...para(
        '#',
        r'The mechanism is worth stating plainly. Screen capture '
        r'through the portal can pass frames as DMA-BUF handles, '
        r'which stay in GPU memory, or as plain shared-memory '
        r'copies. The comment says Chrome gives up on the stream '
        r'while negotiating the first kind on this driver. '
        r'force_shm = true trades the zero-copy path for a copy '
        r'through system memory and gets a stream that survives. I '
        r'did not measure what that costs. As an order of '
        r'magnitude, one 1080p frame at four bytes per pixel is '
        r'8.3 MB, so about 500 MB/s at 60 frames a second, small '
        r'against a desktop’s memory bandwidth. A screen share '
        r'that works is a reasonable thing to buy with that. The '
        r'commit gives no symptom beyond the comment, so I will '
        r'not invent one.'),
    blank,
    ...para(
        '#',
        r'The detail I like is that the comment names the driver '
        r'branch, not just “NVIDIA”. A workaround written down '
        r'with the condition under which it is needed is a '
        r'workaround that can be retired. If aur.txt ever stops '
        r'saying 580xx, this file says what to retest.'),

    ...sec('the card on the other end of the pins'),
    ...para(
        '#',
        r'Two more files show how hard this repo leans on the '
        r'specific GPU rather than treating it as generic. The '
        r'power limit unit encodes the board’s numbers:'),
    ...code('conf', 'system/etc/systemd/system/nvidia-powerlimit.service · the limit', r'''
# Default is 180 W; the board allows up to 225 W. More headroom lets the GPU
# hold its boost clock under sustained game load instead of power-throttling.
ExecStart=/usr/bin/nvidia-smi -pm 1
ExecStart=/usr/bin/nvidia-smi -pl 225'''),
    ...para(
        '#',
        r'The -pm 1 enables persistence mode so the setting is not '
        r'dropped when no client holds the GPU open, and -pl 225 '
        r'sets the limit. (The meaning of those flags is general '
        r'nvidia-smi knowledge.) And the HUD config justifies its '
        r'VRAM readout with the card’s capacity:'),
    ...code('conf', 'home/.config/MangoHud/MangoHud.conf · why VRAM is on screen', r'''
# Toggle with Shift_R+F12. VRAM is on screen deliberately: this GTX 980 has
# 4 GB against the game's 6 GB minimum, so VRAM is the number to watch.'''),
    ...para(
        '#',
        r'Both comments carry numbers and a reason, which is the '
        r'house style of this repo. It matters here because every '
        r'one of those numbers goes stale if the card changes, and '
        r'the 580xx packages are the same kind of fact: a property '
        r'of this one machine, written down so the next person '
        r'does not have to rediscover it.'),

    ...sec('DKMS on a rolling kernel: where it can break'),
    ...para(
        '#',
        r'A frozen driver on a moving kernel is a known pairing '
        r'with a known failure mode. The list installs the stock '
        r'linux kernel, not linux-lts, so the kernel keeps '
        r'updating. DKMS rebuilds the nvidia modules at every '
        r'kernel update. The 580 branch no longer gets new '
        r'features, so a future kernel can change an internal '
        r'interface the old module relies on, and the build then '
        r'fails or the module refuses to load. That is general '
        r'reasoning about DKMS, not an incident from this repo, '
        r'which records none.'),
    blank,
    ...para(
        '#',
        r'The repo does contain mitigations, though none is aimed '
        r'at this exactly. linux.preset builds a second, fallback '
        r'unified kernel image with the autodetect step skipped; '
        r'that guards against a module being missing from the '
        r'trimmed image, not against a module that fails to build. '
        r'snapper is installed, so btrfs snapshots are possible, '
        r'but no snapper configuration is tracked. An LTS kernel '
        r'would be the standard hedge, and it is not in either '
        r'list.'),

    ...sec('yay and yay-debug'),
    ...para(
        '#',
        r'The AUR helper is itself an AUR package, which gives the '
        r'whole file a bootstrapping problem. On a new machine yay '
        r'has to be built by hand (clone, makepkg, install) before '
        r'it can install the other eight. Nothing in the repo '
        r'automates that step, and install.sh does not touch '
        r'packages at all.'),
    blank,
    ...para(
        '#',
        r'yay-debug is the companion package holding debug symbols, '
        r'the kind of split package makepkg produces when debug '
        r'packages are enabled. It is listed because the list '
        r'records everything that is explicitly installed, whether '
        r'or not anyone wanted it. It is a small tell that this '
        r'file was captured from the machine, not curated by hand.'),

    ...sec('the three applications'),
    ...pt(
        '#',
        'google-chrome',
        r'the browser, and the reason for the screen-sharing '
        r'workaround above. It is the only browser in either list.'),
    ...pt(
        '#',
        'jetbrains-toolbox',
        r'launched by a keybind: SUPER+ALT+J runs jetbrains-toolbox '
        r'in hyprland.lua, and the README keybinding table lists '
        r'it. It is the one application with its own shortcut.'),
    ...pt(
        '#',
        'spotify',
        r'present and unreferenced. The bar has a media widget '
        r'whose clicks play, pause and skip, but the config does '
        r'not name a player; whatever is running is what it '
        r'controls.'),
    blank,
    ...para(
        '#',
        r'As far as I know all three are AUR recipes that wrap a '
        r'vendor’s binary download. Nothing in the repo pins which '
        r'version they installed, and this is true of the whole '
        r'file: it is names only, so the exact 580.x release of '
        r'the driver in use is not recorded anywhere.'),

    ...sec('limits, and what is next'),
    ...pt(
        '#',
        'no bootstrap',
        r'yay is both required and in the list. A short script '
        r'that built it from its AUR snapshot would complete '
        r'install.sh into an end-to-end install.'),
    ...pt(
        '#',
        'no versions',
        r'a pinned branch with no recorded point release means two '
        r'installs a month apart can differ. The package names '
        r'carry the pin, the file does not carry the version.'),
    ...pt(
        '#',
        'no reasons',
        r'only the driver has its reason written next to it, and '
        r'that in another file. The list itself cannot hold '
        r'comments.'),
    ...pt(
        '#',
        'how to feed it to yay',
        r'with pacman I would pass the file on standard input. I '
        r'have not checked that yay accepts a list that way, so '
        r'I do not claim a command here.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
