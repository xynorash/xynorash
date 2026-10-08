import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/home/.local/bin/notification-focus',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'notification-focus — a click should go somewhere'),
    cm('#', 'a D-Bus listener that finds the sender’s window'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'focus the window of the app whose notification was clicked'),
    kv('language', r'bash (needs bash 4), plus jq, hyprctl, dbus-monitor'),
    kv('size', '36 lines, one commit: 0ae2015 (2026-09-21)'),
    kv('started by', 'the hyprland.start hook in hyprland.lua'),
    kv('checked here', 'real dbus-monitor on a private bus, fake hyprctl'),

    ...sec('the problem'),
    ...para(
        '#',
        r'A desktop notification is an invitation to go somewhere. '
        r'You click the toast that says a message arrived, and you '
        r'expect to land on the chat window, on whatever workspace '
        r'it lives. Out of the box on a tiling compositor that '
        r'often does not happen: the click is delivered to the app '
        r'as an action, and what the app does with it is up to '
        r'the app.'),
    blank,
    ...para(
        '#',
        r'The commit that introduced this file, 0ae2015 on '
        r'2026-09-21, is titled “Notification clicks jump to the '
        r'sending app’s window and workspace”. It changes two '
        r'places at once, and the pair is the design: a standard '
        r'mechanism that handles most apps, and this script for the '
        r'ones that ignore it.'),

    ...sec('two layers'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · layer one', r'''
        -- Clicking a notification (toast or Control Center) hands the app an
        -- activation token; honour it so Hyprland jumps to that window.
        focus_on_activate        = true,'''),
    ...para(
        '#',
        r'Layer one is a single setting. noctalia attaches an '
        r'activation token to the click, a Wayland mechanism by which '
        r'the shell says “the user asked for this”, and the app '
        r'passes it back when it raises its window. Hyprland’s '
        r'misc.focus_on_activate makes the compositor act on such a '
        r'request by focusing the window; the setting’s name and '
        r'the two comments are the repo’s only description of it. '
        r'Apps that pass the token back need nothing else.'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · layer two', r'''
hl.on("hyprland.start", function()
    hl.exec_cmd("noctalia")
    -- Notification clicks land on the sending app even if it ignores the
    -- activation token.
    hl.exec_cmd("/home/xynorash/.local/bin/notification-focus")
end)'''),
    ...para(
        '#',
        r'Layer two is this script, started once with the session. '
        r'The header comment states the gap it covers: “not every '
        r'app uses the token”. For those apps the script watches '
        r'for the click on the session bus, finds out who sent '
        r'the notification and focuses a window of that class '
        r'itself. The two layers are meant to agree. If the token '
        r'already worked, the script notices and does nothing.'),

    ...sec('the script, part one: where to look'),
    ...code('bash', 'home/.local/bin/notification-focus · header', r'''
#!/usr/bin/env bash
# Clicking a notification (toast or Control Center) should land on the app
# that sent it. noctalia passes an activation token and Hyprland honours it
# (misc.focus_on_activate), but not every app uses the token. For those,
# watch the click (ActionInvoked), look up the sender in noctalia's history
# and focus its window, which also switches to its workspace.

history="${XDG_STATE_HOME:-$HOME/.local/state}/noctalia/notification_history.json"'''),
    ...para(
        '#',
        r'The key input is not on the bus. A click signal carries '
        r'only a notification id and an action name; it does not say '
        r'which app sent the notification. That information is in '
        r'noctalia’s own history file, which the script reads. '
        r'The path honours XDG_STATE_HOME and falls back to '
        r'~/.local/state, the standard place for state that is '
        r'neither config nor cache.'),
    blank,
    ...para(
        '#',
        r'I never saw a real history file. Its shape is inferred '
        r'from the jq filter in the next part: an entries array, '
        r'each with a notification object holding id, desktop_entry '
        r'and app_name. If noctalia changes that layout the script '
        r'stops finding anyone and does nothing, with no message.'),

    ...sec('the script, part two: who sent it'),
    ...code('bash', 'home/.local/bin/notification-focus · the lookup', r'''
focus_sender() {
    local id=$1 entry
    entry=$(jq -r --argjson id "$id" '
        .entries[].notification | select(.id == $id)
        | (.desktop_entry // "" | if . == "" then null else . end) // .app_name // ""' "$history")
    [ -n "$entry" ] || return'''),
    ...para(
        '#',
        r'The id is passed in as a JSON number with --argjson so '
        r'that the comparison select(.id == $id) compares numbers '
        r'with numbers; as a string it would never match. The '
        r'last line is a three-step fallback, written with jq’s '
        r'alternative operator. Prefer desktop_entry, because it '
        r'names the application’s .desktop file and usually matches '
        r'its window class. An empty string counts as missing, '
        r'which is what the inner if is for, since // only skips '
        r'null and false. Then fall back to app_name. Then to an '
        r'empty string.'),
    blank,
    ...para(
        '#',
        r'I tested the filter on a fixture I wrote from the shape '
        r'above:'),
    blank,
    plain('  id 41  desktop_entry ""      app_name Discord   -> Discord'),
    plain('  id 42  desktop_entry set                         -> that value'),
    plain('  id 43  no desktop_entry      app_name notify-send'),
    plain('                                                 -> notify-send'),
    plain('  id 44  neither field                           -> empty'),
    plain('  id 99  no such entry                           -> no output'),
    blank,
    ...para(
        '#',
        r'The last two cases both end at [ -n "$entry" ] || return, '
        r'so a notification the script cannot attribute is ignored '
        r'rather than answered with a guess.'),

    ...sec('the script, part three: act, but only if needed'),
    ...code('bash', 'home/.local/bin/notification-focus · focus', r'''
    # Give the app a moment to raise itself with the token first.
    sleep 0.4
    local active
    active=$(hyprctl activewindow -j | jq -r '.class // ""')
    [ "${active,,}" = "${entry,,}" ] && return

    local re
    re=$(printf '%s' "$entry" | sed 's/[][\.*^$+?(){}|]/\\&/g')
    hyprctl dispatch "hl.dsp.focus({ window = \"class:(?i)^(${re//\\/\\\\})\$\" })" >/dev/null
}'''),
    ...pt(
        '#',
        'sleep 0.4',
        r'the two layers race. The token path is handled by the '
        r'app and the compositor; the script waits a moment so '
        r'that, if layer one works, it has already won. The value '
        r'is a guess that the comment justifies but does not '
        r'measure.'),
    ...pt(
        '#',
        'compare, ignoring case',
        r'${active,,} lowercases a variable, a bash 4 feature. With '
        r'the local keyword and the ${re//...} substitution it is '
        r'why the shebang is bash and not sh as in gamemode-attach. '
        r'If the focused window already belongs to '
        r'the sender, return: no dispatch, no flicker. I tested '
        r'this with the focused class written as Org.Mozilla.FireFox '
        r'against a desktop entry in lower case; no dispatch was '
        r'issued.'),
    ...pt(
        '#',
        'escape the name',
        r'the entry becomes part of a regular expression, so its '
        r'metacharacters must be neutralised. The sed expression '
        r'prefixes a backslash to each of [ ] \ . * ^ $ + ? ( ) '
        r'{ } |. The bracket expression opens with ][ on purpose: a '
        r'] placed first is taken literally, which is the portable '
        r'way to include it. A dot matters most, since application '
        r'ids are full of them.'),
    ...pt(
        '#',
        'double the backslashes',
        r'${re//\\/\\\\} replaces each backslash by two. The regex '
        r'is about to be embedded in a Lua string literal, where '
        r'\\ is how you write one backslash. Without this step the '
        r'Lua parser would eat the escapes.'),
    blank,
    ...para(
        '#',
        r'Here is what reached the compositor for the entry '
        r'“C++ (IDE) [x]”, captured from a stand-in hyprctl that '
        r'logs its arguments:'),
    blank,
    plain('  hyprctl dispatch hl.dsp.focus({ window ='),
    plain(r'    "class:(?i)^(C\\+\\+ \\(IDE\\) \\[x\\])$" })'),
    blank,
    ...para(
        '#',
        r'(Wrapped here for width.) The dispatch '
        r'uses the same Lua API as the key bindings in '
        r'hyprland.lua, for example hl.dsp.focus({ direction = '
        r'"left" }). The window selector is a class pattern with a '
        r'case-insensitive flag, anchored at both ends so that '
        r'“code” cannot select “vscode”. As the header says, '
        r'focusing a window also moves to its workspace, which is '
        r'the other half of the promise in the commit title.'),

    ...sec('the script, part four: listening'),
    ...code('bash', 'home/.local/bin/notification-focus · the loop', r'''
dbus-monitor --session "type='signal',interface='org.freedesktop.Notifications',member='ActionInvoked'" |
while read -r line; do
    case $line in
        *member=ActionInvoked*)
            read -r _ id
            focus_sender "$id" &
            ;;
    esac
done'''),
    ...para(
        '#',
        r'This is the piece I enjoyed most, because it parses a '
        r'human-readable stream without a parser. dbus-monitor '
        r'prints one header line per message and then one line per '
        r'argument. I captured what it printed for a real signal '
        r'on a private session bus:'),
    blank,
    plain('  signal time=... sender=:1.1 -> ... member=ActionInvoked'),
    plain('     uint32 42'),
    plain('     string "default"'),
    blank,
    ...para(
        '#',
        r'The outer read takes the header line. The case pattern '
        r'matches only a header that contains member=ActionInvoked. '
        r'Inside the branch a second read consumes the next line '
        r'from the same pipe, splits it on whitespace, throws away '
        r'the word uint32 into _ and keeps 42 in id. The following '
        r'line, string "default", matches no pattern and is '
        r'dropped by the next trip round the loop.'),
    blank,
    ...para(
        '#',
        r'The same capture showed why the case guard is needed. '
        r'dbus-monitor also printed NameAcquired and NameLost '
        r'signals for its own connection, each with a string '
        r'argument line. Those headers do not match, so they pass '
        r'silently. The match rule in the command line would not '
        r'have been enough on its own.'),
    blank,
    ...para(
        '#',
        r'Two smaller choices. The trailing & on focus_sender '
        r'detaches each lookup so that the 0.4 second sleep of one '
        r'click never delays reading the next line; two quick '
        r'clicks are handled independently. And the signal '
        r'is ActionInvoked, which fires when a notification’s '
        r'action is chosen, whether by clicking its body or a '
        r'button. Dismissing a notification emits a different '
        r'signal, so closing a toast does not steal focus.'),

    ...sec('how it was checked'),
    ...para(
        '#',
        r'I started a private session bus with dbus-daemon, put a '
        r'fake hyprctl first on PATH that appends its arguments to '
        r'a log and answers activewindow with a class chosen by '
        r'an environment variable, wrote a history file in the '
        r'assumed shape, and sent ActionInvoked signals with '
        r'dbus-send while the real script ran against real '
        r'dbus-monitor. The results:'),
    ...pt(
        '#',
        'unfocused sender',
        r'one activewindow query, then one dispatch with the '
        r'escaped class pattern.'),
    ...pt(
        '#',
        'focused sender, different case',
        r'one activewindow query, no dispatch.'),
    ...pt(
        '#',
        'unattributable id',
        r'no hyprctl call of any kind.'),
    ...pt(
        '#',
        'metacharacters',
        r'dots and brackets arrived escaped and doubled, as shown '
        r'above.'),
    blank,
    ...para(
        '#',
        r'What this does not cover is Hyprland itself: whether the '
        r'selector syntax is accepted, how a class shared by several '
        r'windows is resolved, and what noctalia writes to disk. '
        r'Those rest on the repo’s own claim that the feature '
        r'works.'),

    ...sec('limits'),
    ...pt(
        '#',
        'identity by name',
        r'the sender is matched to a window by comparing a '
        r'desktop entry or application name with a window class, '
        r'ignoring case. Where the two differ in more than case, '
        r'for example in spaces against hyphens, nothing is '
        r'focused. That is a limit of the technique, not a bug in '
        r'the code, and it is why layer one exists.'),
    ...pt(
        '#',
        'no supervision',
        r'the script is started once. If dbus-monitor exits the '
        r'pipeline ends and nothing restarts it until the next '
        r'login.'),
    ...pt(
        '#',
        'silent failures',
        r'a missing history file, a changed schema, a missing jq '
        r'or hyprctl all end quietly. jq is in packages/pacman.txt; '
        r'dbus-monitor comes from the dbus package, which is not '
        r'listed explicitly.'),
    ...pt(
        '#',
        'a fixed delay',
        r'0.4 seconds is enough or not depending on the app; '
        r'the cost of too short is a brief double focus, the '
        r'cost of too long is a lag you can feel.'),
    ...pt(
        '#',
        'a hard-coded home',
        r'hyprland.lua starts the script by an absolute path under '
        r'/home/xynorash, as the README warns.'),

    ...sec('lessons'),
    ...para(
        '#',
        r'Use the standard mechanism first and write the fallback '
        r'to defer to it. This script checks whether the problem '
        r'is already solved before acting. And when a tool '
        r'gives you text meant for people, a header line to '
        r'select and a read for the next line can be enough; '
        r'what makes it safe is a pattern that matches only what '
        r'you mean.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
