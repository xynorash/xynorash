import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/system/etc/security/limits.d/99-realtime-audio.conf',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', '99-realtime-audio.conf — permission to be urgent'),
    cm('#', 'realtime priority for PipeWire, granted through rlimits'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'raises three per-user resource limits for the wheel group'),
    kv('language', 'limits.conf(5): domain, type, item, value'),
    kv('size', '5 lines, 3 active; 1 commit: d552dfd (2026-09-19), unchanged'),
    kv('installed as', '/etc/security/limits.d/99-realtime-audio.conf (copy, mode 644)'),
    kv('takes effect', 'at the next login, through PAM; the installer does not apply it'),

    ...sec('why this file exists'),
    ...para(
        '#',
        r'Audio is the part of a desktop that cannot be late. A '
        r'frame of video that arrives 10 ms late is a hitch; a '
        r'buffer of audio that arrives 10 ms late is a crackle. '
        r'The way to make a program reliably on time is to run it '
        r'with a real-time scheduling policy, which makes it '
        r'preempt every ordinary thread. That power must be '
        r'granted: an ordinary user may not simply ask for it. '
        r'There are two ways to grant it. One is a helper daemon, '
        r'RealtimeKit (rtkit), which hands out priorities on '
        r'request. The other is to raise the limits the kernel '
        r'enforces for the user. This file does the second.'),
    blank,
    ...para(
        '#',
        r'The first comment line says it directly: “PipeWire '
        r'realtime scheduling without rtkit.” The package list '
        r'agrees from the other side. It installs pipewire, its '
        r'ALSA, JACK and PulseAudio shims and wireplumber, and '
        r'rtkit is in neither packages/pacman.txt nor aur.txt. The '
        r'absence and this file are one decision seen twice.'),

    ...sec('the file, in full'),
    ...code('ini', 'system/etc/security/limits.d/99-realtime-audio.conf', r'''
# PipeWire realtime scheduling without rtkit.
# module-rt falls back to POSIX rlimits when RealtimeKit is unavailable.
@wheel   -  rtprio      95
@wheel   -  nice       -19
@wheel   -  memlock     unlimited'''),
    ...para(
        '#',
        r'The second comment line names the mechanism it relies '
        r'on. module-rt is the PipeWire module that gives the '
        r'audio threads real-time priority. The comment states '
        r'that, when RealtimeKit is not there to ask, the module '
        r'falls back to the POSIX resource limits of the process. '
        r'Those limits are exactly what the three lines raise.'),

    ...sec('reading a limits line'),
    ...para(
        '#',
        r'Each active line has four columns, and they read left to '
        r'right as a sentence:'),
    blank,
    ...pt(
        '#',
        '@wheel',
        r'who: the @ means a group. wheel is the administrator '
        r'group on Arch; it is what grants sudo in a typical '
        r'setup. The repo does not create the user or its groups '
        r'(the installer only adds gamemode, seat and docker), so '
        r'which account is in wheel is decided outside it.'),
    ...pt(
        '#',
        '-',
        r'which limit: the dash sets both the soft limit (what a '
        r'process starts with) and the hard limit (the ceiling it '
        r'can raise itself to). Setting both avoids a gap where '
        r'the ceiling is high and the default is not.'),
    ...pt(
        '#',
        'rtprio 95',
        r'the highest real-time priority a process may request. '
        r'The scale runs from 1 to 99, so 95 is near the top.'),
    ...pt(
        '#',
        'nice -19',
        r'the lowest nice value a process may set. Nice runs from '
        r'-20 (most favoured) to 19; -19 is one step short of the '
        r'strongest. This is for threads that want a better share '
        r'without a real-time policy.'),
    ...pt(
        '#',
        'memlock unlimited',
        r'how much memory a process may pin in RAM so that it can '
        r'never be swapped out. Unlimited removes the cap.'),

    ...sec('why the three belong together'),
    ...para(
        '#',
        r'Each limit guards against a different way for an audio '
        r'thread to be late, and I read them as a set.'),
    blank,
    ...pt(
        '#',
        'rtprio',
        r'a real-time thread is scheduled ahead of every ordinary '
        r'one, so a busy game, compiler or browser cannot delay '
        r'it. This is the main protection.'),
    ...pt(
        '#',
        'nice',
        r'a fallback for work that is not real-time but should '
        r'still win ties against background tasks.'),
    ...pt(
        '#',
        'memlock',
        r'a real-time thread that touches a page that has been '
        r'swapped out waits for the disk or, here, for the '
        r'decompression of a zram page. Either wait defeats the '
        r'priority. Locking the audio buffers in RAM removes the '
        r'wait. The link to the rest of the system is real: this '
        r'machine swaps early and often (etc/sysctl.d/99-zram.conf '
        r'sets vm.swappiness to 180), so pages being moved to '
        r'compressed swap is routine, and a locked buffer is how '
        r'audio stays out of that traffic. The connection between '
        r'the two files is my reading; neither mentions the other.'),

    ...sec('when it applies, and the path it takes'),
    ...para(
        '#',
        r'A limits file is not read by the kernel or by systemd. '
        r'It is read by pam_limits, a PAM module that sets the '
        r'limits of a session when it opens. So the grant only exists '
        r'for sessions that open after the file is in place, which '
        r'is why the installer’s activation step has nothing to '
        r'say about it, and why logging out and in is the '
        r'cure. The installer’s closing line, “log out and back in '
        r'for the session to pick everything up”, covers this file.'),
    blank,
    ...para(
        '#',
        r'The route is where the claim is weakest. The login goes '
        r'through the PAM service in etc/pam.d/greetd, which '
        r'includes system-local-login. I believe that chain '
        r'reaches pam_limits on Arch, and that the user manager '
        r'that runs PipeWire gets its limits from its own PAM '
        r'service, which also loads it. I cannot confirm either '
        r'link from the repo, and if one is missing the file '
        r'would be correct and inert.'),

    ...sec('the trade-off the file accepts'),
    ...para(
        '#',
        r'Granting rtprio 95 to a whole group means any process of '
        r'any wheel user may take it. A runaway real-time loop can '
        r'freeze a desktop, because it never yields to ordinary '
        r'threads. The kernel limits the damage with real-time '
        r'throttling: by default a real-time group may use at most '
        r'950000 microseconds of every 1000000, leaving 5 percent '
        r'for everything else. I read those two numbers from '
        r'/proc/sys/kernel on a 6.18 kernel in my sandbox, so they '
        r'are the upstream defaults, and I did not check that the '
        r'Arch kernel keeps them.'),
    blank,
    ...para(
        '#',
        r'The choice of the wheel group, rather than a dedicated '
        r'audio group, matches a one-person machine. There is '
        r'no multi-user risk to guard against, and the installer '
        r'does not have to create a group. The cost is that the '
        r'privilege is tied to administrator status, which is '
        r'broader than the need.'),
    blank,
    ...para(
        '#',
        r'There is an overlap with the gaming setup that I did not '
        r'resolve. gamemode.ini sets renice=10, which asks for a '
        r'nice value of -10 for the game, and that is also a '
        r'privilege the kernel guards. Whether this file or the '
        r'gamemode package’s own limits is what satisfies it I '
        r'cannot tell. The installer joins the user to the gamemode '
        r'group for the second route.'),

    ...sec('how I would check it'),
    ...para(
        '#',
        r'In a fresh session, ulimit -r should print 95, ulimit -e '
        r'should print 39 (the kernel stores the nice ceiling as 20 '
        r'minus the value, so -19 becomes 39) and ulimit -l should '
        r'print unlimited. Then '
        r'chrt -p on the PipeWire process would show whether its '
        r'audio threads run with a FIFO policy. In my sandbox the '
        r'first two print 0, which is what a user without any such '
        r'file gets; that confirms the baseline, not the '
        r'result. I did not run the checks on the target machine.'),

    ...sec('history'),
    ...para(
        '#',
        r'A single commit, d552dfd, the initial one on '
        r'2026-09-19; the commit body lists “realtime audio '
        r'limits” among the system-side pieces. The file is '
        r'untouched since, and there is no sign of the values '
        r'having been tuned: 95, -19 and unlimited look like '
        r'generous round-ups, not measured settings. That is '
        r'an impression from the numbers, not from a record.'),

    ...sec('limits, and what is next'),
    ...pt(
        '#',
        'no evidence it was needed',
        r'the repo has no record of dropouts before the change or '
        r'of the improvement after it. The file is a precaution '
        r'in the standard form.'),
    ...pt(
        '#',
        'applies to the whole group',
        r'a narrower grant, to one user or one audio group, '
        r'would carry less risk with the same effect here.'),
    ...pt(
        '#',
        'pipewire.conf not tracked',
        r'the priorities PipeWire actually requests are its own '
        r'defaults. The ceiling here is above them, so nothing '
        r'is clamped, but no tracked file shows what they are.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
