import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/systemd/resolved.conf.d/10-no-llmnr.conf',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'10-no-llmnr.conf — closing a door nobody here uses'),
    cm('#', r'one setting that switches off a legacy name-lookup protocol'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'turn off LLMNR in systemd-resolved'),
    kv(r'format', r'systemd drop-in: a [Resolve] section with one key'),
    kv(r'size', r'4 lines: 2 comment lines, a header and 1 setting'),
    kv(r'installed', r'/etc/systemd/resolved.conf.d/ by install.sh --system'),
    kv(r'history', r'1 commit: 901611a (2026-10-08 11:53), the newest system file'),

    ...sec(r'why this file exists'),
    ...para('#',
        r'systemd-resolved is the local DNS resolver on this machine. '
        r'Besides ordinary DNS it can speak two older protocols for '
        r'finding machines on the local network without a DNS server: '
        r'mDNS and LLMNR. The comment in the file makes a distinction '
        r'between them. It keeps one and drops the other, and it gives '
        r'a reason for each side. This is a small file whose '
        r'interest is in what it chooses not to do.'),

    ...sec(r'the file, in full'),
    ...code('ini', r'system/etc/systemd/resolved.conf.d/10-no-llmnr.conf · lines 1-4', r'''
# LLMNR is legacy Windows-style name resolution on UDP/TCP 5355: nothing here
# uses it, and it only adds a chatty, spoofable listener. mDNS stays on.
[Resolve]
LLMNR=no'''),
    ...para('#',
        r'The comment makes three claims about LLMNR: it is legacy and '
        r'Windows-style, it listens on port 5355 over both UDP and TCP, '
        r'and it is chatty and spoofable. The last is the security '
        r'case. LLMNR answers a name question that was broadcast to '
        r'the local network, and anyone on that network can answer it. '
        r'A host that asks for a name nobody knows can be told a '
        r'false address by whoever answers first. The comment says '
        r'“spoofable”, and that is what it means. I take the '
        r'protocol description from the comment and my own knowledge '
        r'of the protocol; the repo contains no measurement of the '
        r'traffic.'),
    blank,
    ...para('#',
        r'The reason to switch it off is the sentence “nothing here '
        r'uses it”. A listener that nothing needs is attack surface '
        r'without a benefit. The setting is the standard one: '
        r'LLMNR=no in the [Resolve] section, which disables both the '
        r'responder and the resolver for the protocol.'),
    blank,
    ...para('#',
        r'The last sentence, “mDNS stays on”, is the other half. mDNS '
        r'is the multicast DNS that printers, chromecasts and .local '
        r'names use. The file does not touch it, and so the default '
        r'applies. The author considered the pair and switched off '
        r'only the one without a use.'),

    ...sec(r'where it sits in the repo'),
    ...para('#',
        r'The commit that added it, 901611a, is titled “Network: cap '
        r'unsent TCP queue (notsent_lowat) and disable LLMNR”. It is '
        r'a two-part network change. The sysctl half is in '
        r'99-network-tuning.conf and is about latency; this half is '
        r'about exposure. They share a commit, a theme (the network '
        r'stack of one machine) and the same line in install.sh, where '
        r'this file is the last entry of the list of nine.'),
    blank,
    ...code('bash', r'install.sh · lines 41-52', r'''
  for rel in etc/sysctl.d/99-zram.conf \
             etc/sysctl.d/99-network-tuning.conf \
             etc/security/limits.d/99-realtime-audio.conf \
             etc/modules-load.d/ntsync.conf \
             etc/scx_loader.toml \
             etc/greetd/config.toml \
             etc/systemd/system/nvidia-powerlimit.service \
             etc/systemd/logind.conf.d/10-power-key.conf \
             etc/systemd/resolved.conf.d/10-no-llmnr.conf; do
    sudo install -Dm644 "$repo/system/$rel" "/$rel"
    echo "  /$rel"
  done'''),

    ...sec(r'a gap: nothing restarts the resolver'),
    ...para('#',
        r'Right after the loop, install.sh runs sysctl --system, then '
        r'daemon-reload, then a reload of systemd-logind, then enables '
        r'two services. None of those touches systemd-resolved: the '
        r'installer has no restart or reload for it, and I searched '
        r'the script for “resolved” and found only this file’s path. '
        r'As far as I know, resolved reads its configuration when it '
        r'starts, so the drop-in takes effect at the next restart of '
        r'the service or the next boot. The setting is therefore '
        r'installed immediately and live later. It is a gap in the '
        r'installer, not in this file. The fix is a line, '
        r'sudo systemctl restart systemd-resolved, beside the logind '
        r'reload that the power-key commit added.'),

    ...sec(r'trade-offs'),
    ...pt('#', r'lose single-label names from neighbours',
        r'a Windows machine or an appliance that only answers LLMNR '
        r'would no longer be found by name. The comment says nothing '
        r'here depends on that, which is a statement about this one '
        r'network.'),
    ...pt('#', r'a drop-in, not an edit',
        r'resolved.conf is left to the package; this file is read on '
        r'top of it, and 10- puts it early in the order.'),
    ...pt('#', r'not the same as a firewall',
        r'the setting stops resolved from listening for LLMNR. It does '
        r'not protect against other protocols that behave similarly.'),

    ...sec(r'how I checked it'),
    ...para('#',
        r'No test in the repo. On the machine, the tracked file '
        r'matches the installed one, and resolvectl status shows '
        r'-LLMNR and +mDNS in the protocol lines of the global section '
        r'and on the links I looked at. That is the state the '
        r'comment describes. It does not show which restart '
        r'applied it, so the gap above is a reading of the script, '
        r'not an observation.'),

    ...sec(r'history'),
    ...pt('#', r'901611a, 2026-10-08 11:53',
        r'the only commit. The same second also carries the DotClick '
        r'cursor commit and the WinApps commit, so the '
        r'three share one timestamp.'),
  ],
);
