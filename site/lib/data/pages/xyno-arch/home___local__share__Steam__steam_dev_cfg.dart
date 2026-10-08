import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/home/.local/share/Steam/steam_dev.cfg',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'steam_dev.cfg — three undocumented download knobs'),
    cm('#', 'three lines that cannot explain themselves'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'tunes the Steam client’s download behaviour'),
    kv('format', 'one “@name value” console variable per line'),
    kv('size', '3 lines, one commit: 208de62 (2026-09-19)'),
    kv('documented by', 'not by the repo and, as far as I found, not by Valve'),
    kv('verified here', 'install path only; the effect is not measured'),

    ...sec('the file'),
    ...code('text', 'home/.local/share/Steam/steam_dev.cfg', r'''
@nClientDownloadEnableHTTP2PlatformLinux 0
@fDownloadRateImprovementToAddAnotherConnection 1.0
@cMaxInitialDownloadSources 15'''),
    ...para(
        '#',
        r'This is the smallest file in the repository and the one '
        r'whose purpose is hardest to prove, so this page is more '
        r'about what is known and what is not than about the code. '
        r'There is no comment in the file. I do not know whether '
        r'Steam’s parser accepts comments, and I would not add one '
        r'without testing it. The only description the repo ever '
        r'gave is in a commit message.'),

    ...sec('what the repo says'),
    ...para(
        '#',
        r'Exactly one sentence, in the body of commit 208de62, '
        r'“Track everything needed to reproduce the desktop”: “Add '
        r'.bashrc, the Steam download tweaks, the greetd PAM stack '
        r'and the mkinitcpio preset that builds the fallback UKI.” '
        r'It was made six minutes after the initial commit, in '
        r'the same sweep that moved the wallpaper and the bar '
        r'geometry out of noctalia’s state file. The file has not '
        r'changed since.'),
    blank,
    ...para(
        '#',
        r'So the history establishes three things: it is a '
        r'deliberate tweak, it concerns Steam downloads, and it '
        r'was important enough to track so that a fresh machine '
        r'would have it. It does not establish what the tweak '
        r'achieved.'),

    ...sec('what the names say'),
    ...para(
        '#',
        r'The three names read as Valve-style console variables, '
        r'with a one-letter type prefix: n, f and c. I read them '
        r'as an integer, a float and a count; that is my reading '
        r'of the naming, not a documented fact.'),
    ...pt(
        '#',
        '@nClientDownloadEnableHTTP2PlatformLinux 0',
        r'a switch for HTTP/2 in the Linux client’s downloads, '
        r'set to off. The name says what it controls and the 0 says '
        r'which way it was turned.'),
    ...pt(
        '#',
        '@fDownloadRateImprovementToAddAnotherConnection 1.0',
        r'a ratio that decides how much faster the transfer must '
        r'become before Steam opens another connection. The name '
        r'implies a threshold; I did not find a statement of '
        r'the exact rule. Community guides use 1.0 most often, one '
        r'uses 1.1 and one uses 2.'),
    ...pt(
        '#',
        '@cMaxInitialDownloadSources 15',
        r'a cap on the number of download sources used at the '
        r'start of a download. One guide I found says Steam starts '
        r'with a single source and adds more as needed; 15 is the '
        r'value most guides use.'),
    blank,
    ...para(
        '#',
        r'Taken together the three lines push in one direction: '
        r'turn HTTP/2 off, start with many sources, open more '
        r'connections readily. That resembles the lever that '
        r'home/.local/bin/intl-speedtest pulls with its four '
        r'parallel streams, and it would address the same '
        r'issue that system/etc/sysctl.d/99-network-tuning.conf '
        r'names:'),
    ...code('ini', 'system/etc/sysctl.d/99-network-tuning.conf · the path', r'''
# High bandwidth-delay paths (e.g. ~100 Mbps at 200+ ms to Europe/Google) need
# multi-MB windows. Autotuning already reaches 32 MB; these raise the ceiling'''),
    ...para(
        '#',
        r'That connection between the files is my inference. The '
        r'repo never says that the Steam settings were chosen '
        r'because of the long path.'),

    ...sec('what outside sources say'),
    ...para(
        '#',
        r'I searched for the three names on 2026-10-08. What came '
        r'back were forum posts, blog posts and Reddit threads; '
        r'none was from Valve. I mention them as context and '
        r'not as proof:'),
    ...pt(
        '#',
        'status',
        r'these are community workarounds. One guide mentions a '
        r'Valve issue about HTTP/2 slowdowns, which would make the '
        r'first line a workaround for a bug and not a tuning '
        r'option.'),
    ...pt(
        '#',
        'results are mixed',
        r'one CachyOS user credited the settings, together with '
        r'turning off Wi-Fi power saving, for a fix; one Manjaro '
        r'user saw no change; one Arch poster said the same '
        r'settings had worked before a reinstall and then stopped '
        r'helping.'),
    ...pt(
        '#',
        'may not last',
        r'being undocumented, the variables can change or vanish '
        r'in any Steam update. A line Steam ignores does no harm, '
        r'but it also does nothing.'),
    ...pt(
        '#',
        'a suggestion',
        r'one commenter thought the HTTP/2 line alone might be the '
        r'useful one. This repo sets all three together, so it '
        r'cannot say which, if any, helped.'),

    ...sec('how it gets onto the machine'),
    ...code('bash', 'install.sh · the linking loop', r'''
echo "linking home configs"
while IFS= read -r -d '' src; do
  rel=${src#"$repo"/home/}
  dst=$HOME/$rel
  mkdir -p "$(dirname "$dst")"
  backup "$dst"
  ln -s "$src" "$dst"
  echo "  $dst -> $src"
done < <(find "$repo/home" -type f -print0)'''),
    ...para(
        '#',
        r'The file is not special-cased. The loop walks every '
        r'file under home/ and links it to the same relative '
        r'path, so steam_dev.cfg becomes a symlink at '
        r'~/.local/share/Steam/steam_dev.cfg, creating the Steam '
        r'directory if it does not exist. I ran the installer on a '
        r'throw-away HOME and confirmed the link. The guides I '
        r'found place the file at ~/.steam/steam/steam_dev.cfg '
        r'for a native install. That path is, as far as I know, '
        r'a symlink to ~/.local/share/Steam that Steam itself '
        r'creates, which would make the two the same file; I did '
        r'not verify that here.'),
    blank,
    ...para(
        '#',
        r'Two things I could not check. Whether Steam follows a '
        r'symlink for this file, and whether creating the Steam '
        r'directory before Steam has ever run is harmless. The file '
        r'has sat unchanged since 2026-09-19, which at least means '
        r'nothing forced a rewrite.'),

    ...sec('how you would test it'),
    ...para(
        '#',
        r'The honest way to learn what these lines do is an '
        r'A/B test on one game, with the other variables held '
        r'still. The tools for that are in the repo already:'),
    ...pt(
        '#',
        '1. a baseline',
        r'move the file aside, restart Steam, download a large '
        r'game, and note the sustained rate.'),
    ...pt(
        '#',
        '2. a reference',
        r'run intl-speedtest at the same hour; if the line itself '
        r'is the limit, no setting will beat it.'),
    ...pt(
        '#',
        '3. one change at a time',
        r'restore the lines singly, HTTP/2 first, and repeat. '
        r'Community guidance says Steam’s console command '
        r'download_sources shows the live sources and connection '
        r'statistics; I did not run it.'),
    blank,
    ...para(
        '#',
        r'Steam has to be restarted after the file changes, '
        r'according to those guides.'),

    ...sec('lessons'),
    ...para(
        '#',
        r'A tweak you cannot explain is a liability even when it '
        r'works. The file records what was done and not why, and '
        r'the why survives only in one commit message and in the '
        r'memory of the owner. The cheap fix is a one-line note '
        r'beside the file, in this repo’s README, naming the problem '
        r'it was meant to solve and the measurement that showed it '
        r'did. The other lesson is about changing three settings '
        r'at once: it is fast, and it makes the result impossible '
        r'to attribute.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
