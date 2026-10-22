import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/sysctl.d/99-zram.conf',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'99-zram.conf — four numbers that make swap cheap to use'),
    cm('#', r'memory settings that only make sense with compressed swap'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'kernel memory-reclaim settings tuned for zram swap'),
    kv(r'format', r'sysctl: key = value'),
    kv(r'size', r'5 lines: 1 comment and 4 settings'),
    kv(r'installed', r'/etc/sysctl.d/ by install.sh --system, then sysctl --system'),
    kv(r'history', r'1 commit: d552dfd (2026-09-19), never edited'),

    ...sec(r'why this file exists'),
    ...para('#',
        r'Linux defaults assume swap is a slow disk: you avoid it, you '
        r'fill the page cache, and you swap only under pressure. zram '
        r'changes the economics. It is a block device that lives in RAM '
        r'and compresses what is written to it, so “swapping” a page '
        r'costs a little CPU time, not a trip to a drive. The file’s '
        r'one comment line states the consequence and the strategy that '
        r'follows from it: swapping is cheap, “so lean on it early”.'),

    ...sec(r'the file, in full'),
    ...code('text', r'system/etc/sysctl.d/99-zram.conf · lines 1-5', r'''
# zram is RAM-backed compressed swap: swapping is cheap, so lean on it early.
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0'''),
    ...para('#',
        r'The file explains the idea once, in the comment, and gives '
        r'no reason per line. What each setting does is documented by '
        r'the kernel, and I am reading the values against that '
        r'documentation as I remember it. Where I go beyond the comment, '
        r'I say so.'),
    blank,
    ...pt('#', r'vm.swappiness = 180',
        r'the balance between reclaiming file cache and swapping out '
        r'anonymous memory. The old scale stopped at 100, where the two '
        r'were equal. Since kernel 5.8 the range goes to 200, and above '
        r'100 the kernel prefers swapping anonymous pages over '
        r'dropping cache. 180 is well into that range, which is the '
        r'“lean on it early” of the comment: idle application memory '
        r'is compressed away so the cache stays large.'),
    ...pt('#', r'vm.watermark_boost_factor = 0',
        r'turns off a boost that makes the kernel reclaim extra memory '
        r'for a while after memory fragmentation causes trouble. With '
        r'swap this fast the extra reclaim is unnecessary work; that '
        r'reasoning is mine, not the file’s.'),
    ...pt('#', r'vm.watermark_scale_factor = 125',
        r'how far apart the memory watermarks are, in hundredths of a '
        r'percent of memory. The default is 10; 125 starts background '
        r'reclaim earlier and keeps more free memory in reserve, so a '
        r'burst of allocation is less likely to stall waiting for '
        r'reclaim.'),
    ...pt('#', r'vm.page-cluster = 0',
        r'the number of pages, as a power of two, read back from swap '
        r'at once. 2 to the power 0 is a single page. Read-ahead '
        r'exists to amortize a disk’s seek time. RAM has none, so '
        r'reading only the page that was asked for wastes no work.'),

    ...sec(r'the parts that live outside this file'),
    ...para('#',
        r'The settings above do nothing useful without zram swap, and '
        r'this file does not create it. The repo carries two hints about '
        r'how it comes to exist: packages/pacman.txt lists '
        r'zram-generator, the tool that sets up a zram device from a '
        r'small config at boot, and README.md puts “zram swap” in its '
        r'setup table. What the repo does not track is the '
        r'zram-generator configuration itself. So the size, the '
        r'compression algorithm and the priority are not reproducible '
        r'from this repository. On the machine I checked, /dev/zram0 '
        r'is 7.8 G with zstd, active as swap at priority 100. A 16 G '
        r'swapfile at priority 10 also exists, so zram is used first '
        r'and the disk is the overflow. I list this as an observation '
        r'of the machine, not something the repo promises.'),
    blank,
    ...para('#',
        r'One more file belongs to the same arrangement: the kernel '
        r'command line sets zswap.enabled=0. zswap is another kernel '
        r'cache that compresses pages in front of a disk swap. With '
        r'zram doing that job, turning it off avoids doing the work '
        r'twice. That is my explanation. The command-line file gives '
        r'no reason.'),

    ...sec(r'trade-offs'),
    ...pt('#', r'CPU for RAM',
        r'compression costs cycles. On a Ryzen 7 5800X (README.md) '
        r'there are plenty to spend, which is part of why the numbers '
        r'are so aggressive.'),
    ...pt('#', r'no free lunch on a full device',
        r'compressed swap lives in RAM. If the data compresses badly, '
        r'a high swappiness moves memory around without freeing as '
        r'much as hoped.'),
    ...pt('#', r'bad fit for other machines',
        r'on a computer with a spinning disk as its only swap, '
        r'swappiness 180 and page-cluster 0 would be the opposite of '
        r'what you want. The comment states the assumption, so the '
        r'file documents its own limits.'),

    ...sec(r'how I checked it'),
    ...para('#',
        r'There is no test. On the machine, reading the live kernel '
        r'gives vm.swappiness = 180, vm.watermark_boost_factor = 0, '
        r'vm.watermark_scale_factor = 125 and vm.page-cluster = 0, so '
        r'the file is in effect. I did not run a memory-pressure '
        r'workload, so I cannot say what the numbers do for '
        r'responsiveness.'),

    ...sec(r'history'),
    ...pt('#', r'd552dfd, 2026-09-19',
        r'the initial commit describes the system side as “sysctl '
        r'tuning (zram, network)”. The network half was edited again '
        r'on 2026-10-08; this half never was.'),
  ],
);
