import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/home/.local/bin/gamemode-attach',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'gamemode-attach — GameMode without launch options'),
    cm('#', 'a 25-line POSIX script and one argv detail'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'puts a running game into GameMode when its window opens'),
    kv('language', 'POSIX sh, executable'),
    kv('size', '25 lines: 18 at birth, 7 added by the one bug fix'),
    kv('history', '2 commits: d552dfd, aebd41e (both 2026-09-19)'),
    kv('called by', 'the window.open hook in hyprland.lua'),
    kv('checked here', 'ran it against a stand-in gamemoded, read the daemon source'),

    ...sec('the problem'),
    ...para(
        '#',
        r'The usual way to use Feral’s GameMode is to edit every game’s '
        r'Steam launch options to read gamemoderun %command%. That '
        r'is one more thing to forget, and it is invisible when '
        r'it is missing: the game simply runs on the idle governor. '
        r'The README claims the opposite for this machine, “No '
        r'per-game launch options needed”, and this script is how.'),
    blank,
    ...para(
        '#',
        r'The idea is to let the compositor do the noticing. Every '
        r'Steam game under Proton gets a window whose class is '
        r'steam_app_<appid>. When such a window opens, Hyprland runs '
        r'this script with the window’s PID, and the script asks '
        r'gamemoded to switch the machine into gaming mode.'),

    ...sec('the call site'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · the hook', r'''
-- Proton names every Steam game window steam_app_<appid>. When one opens,
-- its process joins GameMode (Ryzen -> performance governor, screensaver
-- inhibited). It drops back to powersave ~20 s after the game exits.
-- Steam's own client window is class "steam" and deliberately not matched.
hl.on("window.open", function(w)
    if w and w.initial_class and w.initial_class:match("^steam_app_%d+$") then
        hl.exec_cmd("/home/xynorash/.local/bin/gamemode-attach " .. w.pid)
    end
end)'''),
    ...para(
        '#',
        r'Two details are decided here and not in the script. The '
        r'pattern is anchored at both ends and wants digits, so '
        r'Steam’s own window (class “steam”) never triggers it; a '
        r'client that sat in GameMode all day would defeat the '
        r'purpose. And the script is called by absolute path, as '
        r'every command in that file is, because the compositor is '
        r'not started from an interactive bash and so cannot count '
        r'on ~/.local/bin being on its PATH (see home/.bashrc). '
        r'exec_cmd spawns the script as its own process, so the '
        r'sleeps below should not block the compositor.'),

    ...sec('the script, as written'),
    ...code('bash', 'home/.local/bin/gamemode-attach · header and guard', r'''
#!/bin/sh
# Put an already-running process (a game window's PID) into GameMode.
# Called by Hyprland when a Steam game window opens — see hyprland.lua.
#
# `gamemoded -r PID` toggles, so a game that opens two windows from one
# process would switch itself back off. An atomic mkdir lock per PID
# makes a second call a no-op. The -r helper also blocks forever, so we
# wait for the game to exit and then clean it up.
pid="$1"
[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || exit 0'''),
    ...para(
        '#',
        r'The header is a design note in miniature: it names the '
        r'hazard (a toggle), the countermeasure (a lock) and a '
        r'consequence (a helper that never returns). The guard line '
        r'reads as “if the argument is non-empty and that process '
        r'exists, carry on, otherwise exit 0”. kill -0 sends no '
        r'signal and only asks whether the PID can be signalled. '
        r'Exit status 0 is deliberate: a window that vanished '
        r'before the script ran is not an error worth reporting. I '
        r'ran both cases, a PID that does not exist and an empty '
        r'argument, and both exited 0 without output.'),

    ...sec('the bug that shaped it: self-registered games'),
    ...para(
        '#',
        r'The first version, from the initial commit d552dfd at '
        r'18:28 on 2026-09-19, ended after the guard. Fifty-nine '
        r'minutes later, at 19:28, commit aebd41e added seven lines. '
        r'Its message is the whole story: “A game started through '
        r'gamemoderun registers itself; calling gamemoded -r on it '
        r'toggles GameMode back off. Skip processes that have '
        r'libgamemodeauto loaded.”'),
    ...code('bash', 'home/.local/bin/gamemode-attach · the fix', r'''
# Launched through gamemoderun, the game registers itself (libgamemodeauto is
# preloaded into it). Calling -r on it would toggle GameMode back off, so leave
# it alone. MangoHud loads plain libgamemode only to query status, so matching
# the "auto" library is specific to self-registration.
sleep 2
grep -q libgamemodeauto "/proc/$pid/maps" 2>/dev/null && exit 0'''),
    ...para(
        '#',
        r'How do you tell a process that registered itself from one '
        r'that did not? You look at what is mapped into it. '
        r'gamemoderun works by preloading a small library, '
        r'libgamemodeauto, into the game; that library registers '
        r'the process when it is loaded. The kernel lists every '
        r'mapped file of a process in /proc/<pid>/maps, so a grep '
        r'for the name answers the question without asking '
        r'anybody.'),
    blank,
    ...para(
        '#',
        r'The comment shows care about false positives. MangoHud '
        r'also loads a GameMode library, but only to query whether '
        r'GameMode is on, and it loads the plain libgamemode. Had the '
        r'grep been for “gamemode” alone, every game with a HUD '
        r'would have matched and been skipped. Matching the “auto” '
        r'variant is what makes the check specific. I tested both '
        r'sides with two empty shared libraries named '
        r'libgamemodeauto.so.0 and libgamemode.so.0, each preloaded '
        r'into a sleeping process:'),
    blank,
    plain('  LD_PRELOAD=libgamemodeauto.so.0  -> exit 0, no helper'),
    plain('  LD_PRELOAD=libgamemode.so.0      -> helper started'),
    blank,
    ...para(
        '#',
        r'The sleep 2 is not explained in the file. My inference is '
        r'that it gives a freshly mapped window’s process time to '
        r'finish loading before its maps are read. Nothing in the '
        r'repo records whether it was needed.'),

    ...sec('the lock'),
    ...code('bash', 'home/.local/bin/gamemode-attach · lock, helper, cleanup', r'''
lock="${XDG_RUNTIME_DIR:-/tmp}/gamemode-attach.$pid"
mkdir "$lock" 2>/dev/null || exit 0

gamemoded -r "$pid" >/dev/null 2>&1 &
req=$!
while kill -0 "$pid" 2>/dev/null; do sleep 5; done
kill "$req" 2>/dev/null
rmdir "$lock" 2>/dev/null'''),
    ...para(
        '#',
        r'mkdir is the classic shell lock because creating a '
        r'directory either succeeds or fails in one atomic step; '
        r'no two callers can both win, and unlike a test-then-touch '
        r'there is no gap between the check and the claim. The lock '
        r'name carries the PID, so two different games never block '
        r'each other, only a second window of the same process does. '
        r'XDG_RUNTIME_DIR is a per-user directory on tmpfs, which '
        r'means a lock that survives a killed script is cleared '
        r'with the session. That last fact is general Linux, not '
        r'something the repo states.'),
    blank,
    ...para(
        '#',
        r'I tested concurrency by starting the script twice at the '
        r'same instant on one sleeping PID, with a stand-in '
        r'gamemoded on PATH that logs its arguments. The log '
        r'contained one line, so exactly one helper existed, and '
        r'one lock directory was present while the game ran. '
        r'After the game exited, both scripts were gone, the '
        r'helper was gone and the lock directory had been removed.'),
    blank,
    ...para(
        '#',
        r'Per-PID locking has a second, accidental benefit. A '
        r'launcher may start a small stub that opens a window and '
        r'then hands over to the real game process. Each process '
        r'with a steam_app window gets its own lock and its own '
        r'helper, and GameMode stays active until the last one '
        r'goes away. That follows from the code; I did not test '
        r'a launcher.'),

    ...sec('timing: the poll'),
    ...para(
        '#',
        r'The loop asks every 5 seconds whether the game is alive. '
        r'In the stand-in test the game exited at 9 seconds and the '
        r'script returned at 12, because its checks fell at 2, 7 and '
        r'12 seconds. So the release is up to 5 seconds late by '
        r'design, a trade of promptness for not spinning. The daemon '
        r'then needs its own reaper pass (every 5 seconds by '
        r'default) to notice the dead helper. The comment in '
        r'hyprland.lua says “~20 s” in total; the code accounts for '
        r'about 10 at most.'),

    ...sec('what -r actually does'),
    ...para(
        '#',
        r'Here is the part that is not obvious and that the script’s '
        r'own comments half-describe. The help text of gamemoded '
        r'reads “-r[PID], --request=[PID] Toggle gamemode for '
        r'process. When no PID given, requests gamemode and '
        r'pauses”. The option is declared with an optional '
        r'argument, in the short-option string “dls::r::tvhR”. '
        r'For GNU getopt an optional argument must be attached to '
        r'its option, as -r1234 or --request=1234. Written with a '
        r'space, as this script does, the number is not an '
        r'argument of -r at all. I wrote a short C program '
        r'with the same option string and ran it:'),
    blank,
    plain('  ./getopt_t -r 1234         case r: optarg=(null)'),
    plain('                             leftover non-option: 1234'),
    plain('  ./getopt_t -r1234          case r: optarg=1234'),
    plain('  ./getopt_t --request=1234  case r: optarg=1234'),
    blank,
    ...para(
        '#',
        r'In gamemoded.c (1.8.2 and current master) the two cases '
        r'are different branches. With a PID it queries the status '
        r'and toggles: request start for that PID if it is not '
        r'registered, request end if it is, then it exits. Without '
        r'a PID it requests GameMode for itself, queries the result '
        r'and calls pause() until it receives SIGINT. So '
        r'gamemoded -r "$pid" lands in the second branch.'),
    blank,
    ...para(
        '#',
        r'Look back at the header comment with that in mind. “The '
        r'-r helper also blocks forever” is exactly the second '
        r'branch; the first branch exits at once. The script was '
        r'evidently written from what the process did when run, '
        r'which is why it has a wait loop and a kill. The word '
        r'“toggles” in the same comment, and in the commit message '
        r'of aebd41e, describes the first branch, which this call '
        r'does not reach. Both sentences are true of gamemoded and '
        r'only one of them describes this invocation.'),
    blank,
    ...para(
        '#',
        r'The practical consequences, if my reading is right:'),
    ...pt(
        '#',
        'the registered client is the helper',
        r'what GameMode tracks is the gamemoded -r process, not '
        r'the game. The governor switch and the screensaver '
        r'inhibition are global, so the headline effect is intact.'),
    ...pt(
        '#',
        'renice and ioprio miss the game',
        r'the daemon applies them per registered client. With '
        r'renice=10 in home/.config/gamemode.ini they would '
        r'apply to the helper, a process that sleeps.'),
    ...pt(
        '#',
        'the toggle never happens',
        r'a second helper for the same game would simply be a '
        r'second registered client. The lock is still sensible, '
        r'because it avoids redundant helpers, but it is not '
        r'preventing a switch-off.'),
    ...pt(
        '#',
        'the aebd41e skip is harmless and right',
        r'a self-registered game does not need a second client. '
        r'The grep stays useful even though its stated reason is '
        r'the other branch’s behaviour.'),
    ...pt(
        '#',
        'release goes through the reaper',
        r'kill "$req" sends SIGTERM. In the no-PID branch only '
        r'SIGINT has a handler, which makes the helper call '
        r'its explicit end request; SIGTERM kills it outright and '
        r'the daemon finds out on its next reaper pass. Whether '
        r'kill -INT would shorten the tail I have not tested.'),
    blank,
    ...para(
        '#',
        r'A one-character change would give the other behaviour: '
        r'gamemoded -r"$pid" with the number attached. Then the '
        r'game itself would be registered, renice and ioprio would '
        r'reach it, the call would return immediately, and the wait '
        r'loop and the kill would become unnecessary, while the '
        r'lock would start to matter for the reason the comment '
        r'gives. I did not make that change. This page records a '
        r'finding from reading source and from a getopt test; '
        r'I never ran a real gamemoded, so the end-to-end '
        r'behaviour is not confirmed by observation.'),

    ...sec('failure modes'),
    ...pt(
        '#',
        'silence',
        r'both output streams of gamemoded go to /dev/null. If the '
        r'daemon is missing or the bus call fails, the script '
        r'still exits normally and nothing tells you. The MangoHud '
        r'gamemode line (home/.config/MangoHud/MangoHud.conf) and '
        r'the toast from gamemode.ini are the only feedback.'),
    ...pt(
        '#',
        'a lock left behind',
        r'if the script is killed with SIGKILL, rmdir never runs. A '
        r'new game that happens to get the same PID in the same '
        r'session would exit at the mkdir line. The window for that '
        r'is small, and a logout clears the directory.'),
    ...pt(
        '#',
        'one process per attached game',
        r'a sleeping shell and a helper for the whole play '
        r'session. Cheap, but not zero.'),
    ...pt(
        '#',
        'matching',
        r'only windows whose initial class is steam_app_<digits> '
        r'are attached. A native game or a launcher outside Steam '
        r'gets nothing from this script and would need gamemoderun '
        r'in its launch options.'),

    ...sec('how it was checked'),
    ...para(
        '#',
        r'A stand-in gamemoded on PATH that logs its arguments and '
        r'sleeps; a sleeping process as the “game”; empty libraries '
        r'preloaded for the maps test. That covers the guard, the '
        r'maps check, the lock, the helper lifecycle and the timing. '
        r'It does not cover the real daemon, polkit, cpufreq or '
        r'Hyprland. The stand-in recorded the arguments as two words, “-r” '
        r'and the PID, which is what the getopt result depends on.'),

    ...sec('lessons'),
    ...pt(
        '#',
        'test the world, not the intent',
        r'the fix asks /proc what is loaded and does not assume how '
        r'the game was launched.'),
    ...pt(
        '#',
        'make idempotency structural',
        r'one atomic mkdir turns “maybe called twice” from a '
        r'hazard into a no-op.'),
    ...pt(
        '#',
        'read the usage line twice',
        r'“[PID]” in square brackets, with an optional argument, is '
        r'where this script’s model and the program’s behaviour '
        r'parted. Comments written from observation are more '
        r'reliable than comments written from the help text, and '
        r'this file has both.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
