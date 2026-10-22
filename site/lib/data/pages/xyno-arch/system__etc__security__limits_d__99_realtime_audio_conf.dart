import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/security/limits.d/99-realtime-audio.conf',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'99-realtime-audio.conf — permission to be urgent'),
    cm('#', r'three resource limits that let PipeWire schedule itself'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'raise per-user limits for realtime audio scheduling'),
    kv(r'format', r'pam_limits: domain, type, item, value'),
    kv(r'size', r'5 lines: 2 comment lines and 3 limits'),
    kv(r'applies to', r'members of the wheel group'),
    kv(r'installed', r'/etc/security/limits.d/ by install.sh --system'),
    kv(r'history', r'1 commit: d552dfd (2026-09-19), never edited'),

    ...sec(r'why this file exists'),
    ...para('#',
        r'Audio is a deadline problem. A buffer of sound has to be '
        r'refilled every few milliseconds, and if the thread that does '
        r'it is delayed by a busy CPU, you hear a click. Linux lets a '
        r'process ask for a realtime priority, which puts it ahead of '
        r'ordinary work, but by default an ordinary user may not. The '
        r'usual way to grant that is a small daemon, RealtimeKit '
        r'(rtkit), which hands out realtime priority on request. This '
        r'file is the other way, with no daemon at all: raise the '
        r'user’s own limits so the audio server can ask for the '
        r'priority directly.'),

    ...sec(r'the file, in full'),
    ...code('text', r'system/etc/security/limits.d/99-realtime-audio.conf · lines 1-5', r'''
# PipeWire realtime scheduling without rtkit.
# module-rt falls back to POSIX rlimits when RealtimeKit is unavailable.
@wheel   -  rtprio      95
@wheel   -  nice       -19
@wheel   -  memlock     unlimited'''),
    ...para('#',
        r'The two comment lines are the whole design statement. PipeWire '
        r'has a module, module-rt, which tries RealtimeKit first and, '
        r'when it is not there, falls back to the process’s own '
        r'limits (the “POSIX rlimits”). This machine has no rtkit: '
        r'neither packages/pacman.txt nor packages/aur.txt lists it. '
        r'So the limits have to be set, and this is the file that does '
        r'it.'),
    blank,
    ...para('#', r'Reading the three lines:'),
    blank,
    ...pt('#', r'@wheel',
        r'the @ means a group, not a user. wheel is the administrators’ '
        r'group on Arch; on the machine I checked, the one real user '
        r'is a member of it. Anyone else on the system gets nothing.'),
    ...pt('#', r'- (the type)',
        r'a dash sets both the soft and the hard limit at once, so the '
        r'user cannot lower it for one and raise it for the other.'),
    ...pt('#', r'rtprio 95',
        r'the highest realtime priority a process of this group may '
        r'request. The scale runs to 99, so 95 leaves the top few '
        r'values free; the repo does not say why 95 was chosen.'),
    ...pt('#', r'nice -19',
        r'the lowest (most favourable) ordinary priority that may be '
        r'set. A nice value of -20 is the extreme, so this is one step '
        r'short of it. It matters for threads that are not realtime '
        r'but still want to win against background work.'),
    ...pt('#', r'memlock unlimited',
        r'no cap on memory that may be locked into RAM. Realtime audio '
        r'wants this so that its buffers can never be swapped out, '
        r'because a page fault in the middle of a deadline is a '
        r'glitch. With 7.8 G of zram swap and a swapfile on the '
        r'machine I looked at, being swapped out is a real possibility '
        r'for any unlocked page.'),

    ...sec(r'how it takes effect'),
    ...para('#',
        r'These limits are applied by PAM, in a module called '
        r'pam_limits, at login. That is a detail with a consequence: '
        r'the limits belong to a login session, so they apply to '
        r'processes that were started after the login, and not to '
        r'anything already running. On this machine /etc/pam.d/'
        r'system-auth has pam_limits in its session section, and the '
        r'greetd stack in this repo includes system-local-login, which '
        r'reaches system-auth. So a session that comes through the '
        r'greeter picks the limits up.'),
    blank,
    ...para('#',
        r'I did not run PipeWire under a debugger, so I cannot say it '
        r'is the thing using the 95. On the machine, a shell started '
        r'in the session reports a realtime priority limit of 95 '
        r'(ulimit -r), which proves the file took effect for the '
        r'login.'),

    ...sec(r'trade-offs'),
    ...pt('#', r'realtime is a power',
        r'a runaway realtime process can starve the system. At '
        r'priority 95 it can starve most of it. The file trusts every '
        r'member of wheel with that, which on a single-user desktop is '
        r'the same person.'),
    ...pt('#', r'no daemon, no policy',
        r'rtkit also guards against abuse; plain limits do not. The '
        r'repo accepts that in exchange for one fewer moving part.'),
    ...pt('#', r'whole group, not one user',
        r'the @wheel domain means that adding another administrator '
        r'gives them the limits too, with no change here.'),
    ...pt('#', r'name 99-',
        r'files in limits.d are read in name order, and 99 sorts last, '
        r'so these lines come after any distribution default and the '
        r'later value wins. That ordering is a convention in the name, '
        r'which the sysctl files in this repo follow too.'),

    ...sec(r'failure modes'),
    ...pt('#', r'not in wheel',
        r'a user outside the group sees no change, and PipeWire falls '
        r'back to ordinary scheduling.'),
    ...pt('#', r'no login',
        r'a session that never goes through PAM (a service started by '
        r'systemd on its own) does not get these limits.'),
    ...pt('#', r'effective at next login',
        r'install.sh copies the file but does not tell the running '
        r'session. Log out and in, which the installer ends by '
        r'saying: “log out and back in for the session to pick '
        r'everything up”.'),

    ...sec(r'how I checked it'),
    ...para('#',
        r'No test in the repo. On the machine the tracked file matches '
        r'the installed one, and ulimit -r in my shell printed 95, '
        r'which shows the rtprio line was applied. I did not check '
        r'nice or memlock separately.'),

    ...sec(r'history'),
    ...pt('#', r'd552dfd, 2026-09-19',
        r'the initial commit lists “realtime audio limits” as part of '
        r'the system side. No later commit changed it.'),
  ],
);
