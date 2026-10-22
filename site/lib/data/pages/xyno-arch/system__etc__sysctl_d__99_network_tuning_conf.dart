import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/sysctl.d/99-network-tuning.conf',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'99-network-tuning.conf — a long, thin pipe to Europe'),
    cm('#', r'BBR, big windows, and a cap on how much to queue unsent'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'kernel network settings for one specific internet line'),
    kv(r'format', r'sysctl: key=value, one per line'),
    kv(r'size', r'22 lines, 9 settings'),
    kv(r'installed', r'/etc/sysctl.d/ by install.sh --system, then sysctl --system'),
    kv(r'history', r'2 commits: d552dfd (2026-09-19), 901611a (2026-10-08)'),

    ...sec(r'why this file exists'),
    ...para('#',
        r'The comments in the file read like a diagnosis of one line. '
        r'The WAN is PPPoE with an MTU of 1492. The path to some '
        r'servers is about a hundred megabits at more than 200 ms '
        r'(“to Europe/Google”). That is a high bandwidth-delay '
        r'product: a lot of data has to be in flight to fill the pipe. '
        r'Stock settings are tuned for something else. The file '
        r'begins by saying where it came from: settings “carried over '
        r'from Omarchy’s 99-omarchy-sysctl.conf”, then adapted. '
        r'It is the network twin of the zram file, and the two are '
        r'installed together by the same loop in install.sh.'),

    ...sec(r'group one: do not stall'),
    ...code('text', r'system/etc/sysctl.d/99-network-tuning.conf · lines 1-7', r'''
# Network settings carried over from Omarchy's 99-omarchy-sysctl.conf.
# Recover from path-MTU black holes instead of stalling (your WAN is PPPoE, MTU 1492).
net.ipv4.tcp_mtu_probing=1
# BBR paces to measured bottleneck bandwidth instead of filling queues until loss;
# fq is the qdisc BBR is built to pace through.
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr'''),
    ...pt('#', r'tcp_mtu_probing=1',
        r'PPPoE shaves 8 bytes off a 1500-byte Ethernet frame, which is '
        r'where 1492 comes from. When a router in the path drops '
        r'oversized packets without telling the sender, a connection '
        r'can hang (a “black hole”). Probing finds a size that works '
        r'when that is detected. The comment says exactly this.'),
    ...pt('#', r'default_qdisc=fq and tcp_congestion_control=bbr',
        r'a pair. BBR is the congestion-control algorithm; it paces '
        r'by estimated bandwidth, not by waiting for loss. fq is the '
        r'queueing discipline that does the pacing, and the comment '
        r'calls it the one BBR “is built to pace through”. Setting one '
        r'without the other would work, but would leave half the '
        r'design unused.'),

    ...sec(r'group two: fill a long pipe'),
    ...code('text', r'system/etc/sysctl.d/99-network-tuning.conf · lines 9-15', r'''
# High bandwidth-delay paths (e.g. ~100 Mbps at 200+ ms to Europe/Google) need
# multi-MB windows. Autotuning already reaches 32 MB; these raise the ceiling
# for apps that size their own socket buffers, and stop idle connections from
# restarting at a tiny window after every pause.
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_wmem=4096 65536 33554432'''),
    ...para('#',
        r'The sums are worth doing. 100 Mbit/s is 12.5 MB per second; '
        r'times 0.2 s of round trip is 2.5 MB that must be in flight '
        r'to keep the pipe full. That is why the comment says '
        r'“multi-MB windows”, and why the ceiling of 33554432 bytes '
        r'(exactly 32 MiB) leaves a wide margin. rmem_max and wmem_max '
        r'are the largest buffer an application may request for itself '
        r'with setsockopt. tcp_wmem is a triple: minimum, default and '
        r'maximum send buffer, here 4096, 65536 and 33554432 bytes. The '
        r'comment is careful to say that autotuning “already reaches '
        r'32 MB”: these lines are for apps that size their own '
        r'socket buffers, as the comment says.'),
    blank,
    ...code('text', r'system/etc/sysctl.d/99-network-tuning.conf · lines 16-17', r'''
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_fastopen=3'''),
    ...pt('#', r'tcp_slow_start_after_idle=0',
        r'an idle connection keeps the window it had earned instead of '
        r'restarting small. This is the “restarting at a tiny window '
        r'after every pause” of the comment. On a 200 ms path every '
        r'slow-start round costs a visible delay.'),
    ...pt('#', r'tcp_fastopen=3',
        r'allows TCP Fast Open for both outgoing and incoming '
        r'connections (the value is a bit mask: 1 client, 2 server). '
        r'The file does not explain it. It saves a round trip on '
        r'repeat connections for servers that support it.'),

    ...sec(r'group three: do not queue behind your own upload'),
    ...code('text', r'system/etc/sysctl.d/99-network-tuning.conf · line 22', r'''
net.ipv4.tcp_notsent_lowat=131072'''),
    ...para('#',
        r'This is the later addition, 901611a, and it '
        r'sits next to group two. Large send buffers let a bulk '
        r'upload park megabytes in its own socket before the network '
        r'has taken them. Anything else on the machine that shares '
        r'the queue (a game, an SSH session, a call) waits behind '
        r'that backlog. The comment above the setting says so: “Cap '
        r'the unsent data queued in a socket so latency-sensitive '
        r'traffic (games, SSH, calls) isn’t stuck behind a bulk '
        r'upload’s backlog; fq+BBR then pace what is left”. '
        r'The value, 131072, is 128 KiB, and the comment checks '
        r'it against the line: “128 KB still fills a 1 Gbps LAN and a '
        r'~100 Mbps WAN”. The numbers back it up: 100 Mbit/s is 12.5 '
        r'MB/s, so 128 KiB is about ten milliseconds of data, '
        r'comfortably above what is needed to keep a send going.'),
    blank,
    ...para('#',
        r'Set a high ceiling for what the path can carry, then a low '
        r'cap on what waits unsent. One sizes the '
        r'in-flight window, the other the unsent queue.'),

    ...sec(r'trade-offs'),
    ...pt('#', r'tuned for one line',
        r'the MTU and the 200 ms path are the author’s own. Another '
        r'connection would not need tcp_mtu_probing, and the very '
        r'large buffers cost memory per busy socket.'),
    ...pt('#', r'bbr needs the module',
        r'the algorithm has to be available in the kernel. On the '
        r'machine I checked it is the active one.'),
    ...pt('#', r'fq globally',
        r'default_qdisc applies to interfaces that come up after the '
        r'setting; an interface already up keeps its qdisc until it '
        r'is brought up again.'),

    ...sec(r'how it is installed and verified'),
    ...para('#',
        r'install.sh copies the file to /etc/sysctl.d and runs '
        r'sudo sysctl --system, which loads every file in order; the '
        r'99- prefix puts this one last. On the machine I read back '
        r'bbr, fq, tcp_notsent_lowat=131072 and tcp_fastopen=3 from '
        r'the live kernel, matching the file. There is no automated '
        r'test and I did not measure throughput or latency, so the '
        r'benefits are the comments’ claims, not mine.'),

    ...sec(r'history'),
    ...pt('#', r'd552dfd, 2026-09-19',
        r'the initial commit: sysctl tuning for zram and network.'),
    ...pt('#', r'901611a, 2026-10-08',
        r'“Network: cap unsent TCP queue (notsent_lowat) and disable '
        r'LLMNR”. It adds the last five lines (a blank line, '
        r'three comment lines and the setting). The same commit adds the resolved '
        r'drop-in and the line in install.sh for it.'),
  ],
);
