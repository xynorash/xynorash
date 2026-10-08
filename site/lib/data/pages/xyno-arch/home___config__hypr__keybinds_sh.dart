import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/home/.config/hypr/keybinds.sh',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', 'keybinds.sh — a cheat sheet that cannot go stale'),
    cm('#', 'an awk program that reads hyprland.lua and prints its own binds'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'prints the keybinds declared in hyprland.lua, grouped and aligned'),
    kv('language', 'bash wrapper around a single awk program'),
    kv('size', '123 lines, of which about 90 are the awk program'),
    kv('bound to', 'SUPER+SHIFT+/ and SUPER+SHIFT+? (hyprland.lua, "Help")'),
    kv('history', '1 commit, d552dfd (2026-09-19); never edited since'),
    kv('verified by', 'running it against a copy of the real config (see below)'),
    ...sec('the problem: documentation that rots'),
    ...para('#',
        r'A desktop with 62 key bindings needs a list of them, and a '
        r'list kept apart from the config tends to drift from it. The '
        r'README handles it with one sentence: pressing Super+Shift+/ '
        r'prints the full list in a floating terminal, and "it is parsed '
        r'straight out of hyprland.lua, so it can’t go stale". This file '
        r'is that sentence turned into code.'),
    blank,
    ...para('#',
        r'The design choice is to make the config the only source of '
        r'truth and treat its own text as the data. There is no second '
        r'table of key names, no generated file to commit and no build '
        r'step. Every time the key is pressed, the script reads '
        r'hyprland.lua again, so a bind added a minute ago is already '
        r'in the list.'),
    ...sec('how it is launched'),
    ...para('#',
        r'Two things in hyprland.lua belong to this script. The first is '
        r'the bind itself, which runs Ghostty with a dedicated window '
        r'class; the second is a window rule that recognises that class '
        r'and shapes the window.'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · the launcher', r'''
-- Help
-- SUPER+? prints this config's binds in a floating terminal.
-- Both keysyms are bound: shift+slash reports as `question` on some layouts.
-- The script pages itself, so no wrapper shell or pager is needed here.
local cheatsheet = "ghostty --class=com.hypr.Keybinds -e /home/xynorash/.config/hypr/keybinds.sh"
hl.bind(mod .. " + SHIFT + slash",    hl.dsp.exec_cmd(cheatsheet))
hl.bind(mod .. " + SHIFT + question", hl.dsp.exec_cmd(cheatsheet))'''),
    ...code('lua', 'home/.config/hypr/hyprland.lua · the window rule', r'''
hl.window_rule({
    name   = "keybinds-cheatsheet",
    match  = { class = "^(com\\.hypr\\.Keybinds)$" },
    float  = true,
    size   = "900 820",
    center = true,
})'''),
    ...para('#',
        r'The class com.hypr.Keybinds is a private name chosen for this '
        r'one window. '
        r'Ghostty’s --class flag sets it, and the rule matches it with '
        r'an anchored regular expression, so only this window floats, '
        r'at 900 by 820 pixels, centred. Presumably the point is that '
        r'a cheat sheet opened as a tiled pane would push every other '
        r'window around, where a floating one appears over the work and '
        r'goes away when closed. The two '
        r'binds exist because the comment says shift+slash is reported '
        r'as the keysym "question" on some layouts, and this config '
        r'cycles between us and fr (kb_layout = "us,fr").'),
    blank,
    ...para('#',
        r'The comment also records a decision about where paging lives: '
        r'"The script pages itself, so no wrapper shell or pager is '
        r'needed here." The launcher could have been bash -c with a '
        r'pipe into less. Instead the knowledge of how to page stays in '
        r'the script, and the config line stays a one-liner that the '
        r'script itself can parse (it recognises it, as we will see).'),
    ...sec('the paging prologue'),
    ...code('bash', 'home/.config/hypr/keybinds.sh · the prologue', r'''
set -euo pipefail

if [ -t 1 ] && [ "${KEYBINDS_PAGED:-}" != "1" ]; then
    export KEYBINDS_PAGED=1
    if command -v less >/dev/null 2>&1; then
        "$0" | less -R
        exit 0
    elif command -v more >/dev/null 2>&1; then
        "$0" | more
        exit 0
    else
        "$0"
        printf '  Press Enter to close. '
        read -r _
        exit 0
    fi
fi'''),
    ...para('#',
        r'The script runs itself twice. The first run finds that its '
        r'standard output is a terminal ([ -t 1 ]) and that nobody has '
        r'set KEYBINDS_PAGED, so it sets it and re-runs itself, '
        r'$0, with the output piped into a pager. The second run sees a '
        r'pipe instead of a terminal, skips the block, and prints the '
        r'list. The -R flag of less is what lets the ANSI colours '
        r'through.'),
    blank,
    ...para('#',
        r'The header comment states the intent: it "falls back through '
        r'less -> more -> hold-open, so a missing pager cannot make the '
        r'cheatsheet flash up and vanish". That failure mode is real for '
        r'a script run as a terminal’s command: when the command exits '
        r'the window normally goes with it (the usual behaviour for a '
        r'command given with -e; the repo does not '
        r'configure it), so a script that printed and exited would '
        r'vanish at once. The third branch prints the list and then '
        r'waits for Enter.'),
    blank,
    ...para('#',
        r'What the environment variable is for is not written down; it '
        r'can be read from the control flow. In the first two branches the '
        r'inner run has a pipe on standard output, so the [ -t 1 ] test '
        r'would already stop the recursion. In the third branch the '
        r'inner run is "$0" with the terminal still attached. Without '
        r'KEYBINDS_PAGED it would take the same branch again, and again, '
        r'forever. The guard is what makes the hold-open fallback safe. '
        r'It is also a handy switch: set KEYBINDS_PAGED=1 and the script '
        r'prints plainly, which is how it was run for this page (below).'),
    ...sec('the awk program, rule by rule'),
    ...para('#',
        r'Everything after the prologue is one awk program run over '
        r'$conf, the path of hyprland.lua. The path honours '
        r'XDG_CONFIG_HOME and falls back to $HOME/.config. hyprland.lua '
        r'also exports XDG_CONFIG_HOME (/home/xynorash/.config) to '
        r'everything it launches, so the lookup lands on the same file '
        r'however the shell was started; that is a reading, not a '
        r'stated reason. The same variable lets the script be pointed '
        r'at any copy of the config.'),
    ...code('bash', 'home/.config/hypr/keybinds.sh · variables and section headings', r'''
conf="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"

awk '
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

# local mod = "SUPER"  -> render $mod as SUPER
/^[ \t]*local[ \t]+[A-Za-z_]+[ \t]*=[ \t]*"/ {
    eq = index($0, "=")
    name = trim(substr($0, 1, eq - 1)); sub(/^local[ \t]+/, "", name)
    val  = trim(substr($0, eq + 1))
    sub(/^"/, "", val); sub(/"[ \t]*$/, "", val)
    vars[name] = val
    next
}

# A short -- comment above a bind becomes its section heading.
/^[ \t]*--/ {
    c = trim($0); sub(/^--+[ \t]*/, "", c)
    gsub(/^[─ ]+|[─ ]+$/, "", c)
    sub(/ *—.*$/, "", c)
    if (c ~ /^[A-Za-z]/ && length(c) < 40) pending = c
    next
}'''),
    ...pt('#', 'rule 1: remember string locals',
        'any line of the form local name = "value" is stored in vars. '
        'In hyprland.lua two lines qualify: mod = "SUPER" and cheatsheet, '
        'the Ghostty command. Storing the second one falls out of the '
        'general rule, and the exec_cmd branch later takes advantage of '
        'it: a bind written as exec_cmd(cheatsheet) is resolved by '
        'looking the name up in vars.'),
    ...pt('#', 'rule 2: comments propose headings',
        'a comment line is stripped of its dashes and of banner '
        'characters (the box-drawing line used in the file’s section '
        'banners), and everything from an em dash onward is cut off. '
        'If what is left starts with a letter and is shorter than 40 '
        'characters, it becomes the pending heading.'),
    blank,
    ...para('#',
        r'The em dash cut is why one comment in hyprland.lua serves two '
        r'readers. The line "-- Audio / media — routed through noctalia '
        r'so the OSD shows" reads as a full explanation to a person and '
        r'as the heading "Audio / media" to the script. The 40 character '
        r'limit is the other half of the contract: the long explanatory '
        r'comments in the config ("Physical power button opens the '
        r'session menu ...") are too long to count as headings, so they '
        r'document without leaking into the output.'),
    ...code('awk', 'home/.config/hypr/keybinds.sh · splitting one bind', r'''
/hl\.bind\(/ {
    line = $0

    # Split key expression from dispatcher at the comma before hl.dsp.
    # Must tolerate column alignment, i.e. several spaces.
    if (!match(line, /,[ \t]*hl\.dsp/)) next
    keyexpr = substr(line, 1, RSTART - 1)
    action  = substr(line, RSTART + 1)
    sub(/^[ \t]*/, "", action)

    sub(/^[ \t]*hl\.bind\([ \t]*/, "", keyexpr)

    # Loop-generated workspace binds: mod .. " + " .. i
    looped = (keyexpr ~ /\.\.[ \t]*i[ \t]*$/)

    gsub(/"/, "", keyexpr)
    gsub(/\.\./, " ", keyexpr)
    for (v in vars) gsub("\\<" v "\\>", vars[v], keyexpr)
    if (looped) sub(/[ \t]+i[ \t]*$/, " 1..9", keyexpr)
    gsub(/[ \t]+/, " ", keyexpr)
    combo = trim(keyexpr)
    gsub(/ \+ +/, " + ", combo)'''),
    ...para('#',
        r'Rule 3 is the heart. It does not parse Lua; it splits the line '
        r'at the first comma that is followed by hl.dsp. Everything '
        r'before is the key expression, everything after is the '
        r'dispatcher call. The comment "Must tolerate column alignment, '
        r'i.e. several spaces" explains the [ \t]* in the pattern: the '
        r'config aligns its arguments in columns (hl.bind(mod .. " + '
        r'left",  hl.dsp...), and the regular expression has to accept '
        r'that. The consequence for the config is that formatting is part '
        r'of the interface: a bind split across two lines would be '
        r'silently skipped by the match test.'),
    blank,
    ...para('#',
        r'The key expression is a fragment of Lua such as mod .. " + '
        r'CTRL + H". The program removes the quotes, turns the .. '
        r'concatenation operator into a space, substitutes every stored '
        r'variable by its value, and collapses whitespace. The loop '
        r'binds are special-cased: the two lines inside for i = 1, 9 end '
        r'with .. i, which the program detects ("looped") and renders '
        r'as 1..9, so nine workspaces cost two lines of output instead '
        r'of eighteen.'),
    ...code('awk', 'home/.config/hypr/keybinds.sh · from dispatcher to words', r'''
    # Dispatcher -> readable action
    sub(/\)[ \t]*$/, "", action)
    sub(/,[ \t]*\{[^}]*\}[ \t]*$/, "", action)   # drop the opts table
    a = action

    if (a ~ /exec_cmd\(/) {
        sub(/^.*exec_cmd\([ \t]*/, "", a); sub(/\)[ \t]*$/, "", a)
        if (a ~ /^"/) { sub(/^"/, "", a); sub(/"[ \t]*$/, "", a) }
        else if (a in vars) a = vars[a]
        if (a ~ /keybinds\.sh/) a = "Show this list"
    }
    else if (a ~ /window\.close/)        a = "close window"
    else if (a ~ /window\.float/)        a = "toggle floating"
    else if (a ~ /window\.pseudo/)       a = "toggle pseudotile"
    else if (a ~ /window\.drag/)         a = "drag window"
    else if (a ~ /window\.resize/)       a = "resize window"
    else if (a ~ /window\.move\(\{ *workspace/) a = "move window to workspace"
    else if (a ~ /window\.move/)      { dir = a; sub(/^.*direction *= *"/, "", dir); sub(/".*$/, "", dir); a = "move window " dir }
    else if (a ~ /focus\(\{ *workspace *= *"e\+1/) a = "next workspace"
    else if (a ~ /focus\(\{ *workspace *= *"e-1/)  a = "previous workspace"
    else if (a ~ /focus\(\{ *workspace/) a = "go to workspace"
    else if (a ~ /focus\(/)           { dir = a; sub(/^.*direction *= *"/, "", dir); sub(/".*$/, "", dir); a = "focus " dir }
    else if (a ~ /layout\(/)          { dir = a; sub(/^.*layout\([ \t]*"/, "", dir); sub(/".*$/, "", dir); a = dir }
    else if (a ~ /dsp\.exit/)            a = "exit Hyprland"
    else { sub(/^hl\.dsp\./, "", a); sub(/\(.*$/, "", a) }'''),
    ...para('#',
        r'This is an if/else chain whose order carries meaning. The '
        r'specific case window.move with a workspace argument must come '
        r'before the general window.move, and the focus cases for "e+1" '
        r'and "e-1" must come before the general focus-with-workspace, '
        r'which comes before the plain directional focus. Each general '
        r'pattern would otherwise swallow the special one. The options '
        r'table that the config attaches to some binds ({ locked = true, '
        r'repeating = true } and { mouse = true }) is cut off first, so '
        r'it never interferes with the matching.'),
    blank,
    ...para('#',
        r'The exec_cmd branch handles three shapes: a quoted command, '
        r'a variable name (looked up in vars, which is how cheatsheet '
        r'resolves), and the special case of the keybinds script '
        r'itself, which is relabelled "Show this list". Every other '
        r'exec_cmd bind is displayed as the command string, for example '
        r'"noctalia msg panel-toggle launcher". That is a design '
        r'choice with a cost returned to below. The final else is the '
        r'fallback: take the dispatcher name and strip the leading '
        r'hl.dsp. and the arguments.'),
    ...code('awk', 'home/.config/hypr/keybinds.sh · key names and output', r"""
    # Prettify keysyms
    gsub(/\<minus\>/,      "-",           combo)
    gsub(/\<equal\>/,      "=",           combo)
    gsub(/\<mouse_down\>/, "Scroll Down", combo)
    gsub(/\<mouse_up\>/,   "Scroll Up",   combo)
    gsub(/mouse:272/,      "Left Drag",   combo)
    gsub(/mouse:273/,      "Right Drag",  combo)
    gsub(/XF86/,           "",            combo)

    if (pending != "" && pending != section) {
        section = pending
        printf "\n  \033[1;35m%s\033[0m\n", section
    }
    pending = ""
    printf "    \033[1;36m%-30s\033[0m %s\n", combo, a
}

/[^ \t]/ { if ($0 !~ /^[ \t]*--/) pending = pending }

BEGIN { printf "\n  \033[1mHyprland keybinds\033[0m\n" }
END   { printf "\n" }
' "$conf"

printf '  \033[2mPress q to close.\033[0m\n\n'"""),
    ...para('#',
        r'The last part cleans up key names (mouse button numbers become '
        r'Left Drag and Right Drag) and prints. A section heading is '
        r'emitted only when the pending heading differs from the one '
        r'already shown, then the bind is printed with the key combination '
        r'padded to 30 columns in bold cyan. Headings are bold magenta. '
        r'These are the sixteen-colour ANSI codes, which a terminal maps '
        r'through its own palette; since the Ghostty theme is regenerated '
        r'by noctalia from the Tokyo Night palette, the sheet follows the '
        r'theme without containing a single colour value of its own. That '
        r'last point is an inference from config.ghostty and the README.'),
    ...sec('what it prints, checked by running it'),
    ...para('#',
        r'The repo has no tests for this script, so it was run for this '
        r'page. The script allows that: it takes the config path from '
        r'XDG_CONFIG_HOME and skips paging when KEYBINDS_PAGED=1. A '
        r'copy of hyprland.lua was placed at <scratch>/hypr/hyprland.lua '
        r'and the script run as '
        r'XDG_CONFIG_HOME=<scratch> KEYBINDS_PAGED=1 bash keybinds.sh. '
        r'The machine used has mawk 1.3.4 as its awk; the author’s '
        r'system presumably has a different one (see the next section). '
        r'The nine groups came out as Apps (9 lines), Help (2), Focus '
        r'(8), Move windows (4), Window state (4), Workspaces (6), Mouse '
        r'drag (2), Screenshots (3) and Audio / media (8): 46 lines '
        r'for the 46 hl.bind calls in the file. The loop collapses into '
        r'two of them, "1..9 go to workspace" and "CTRL + 1..9 move '
        r'window to workspace".'),
    blank,
    ...para('#',
        r'Three binds were added after this script was written, and '
        r'none of them required touching it. The power button (0dc7770), '
        r'the clipboard history (608f2d1) and SUPER+F (b22bf50) all '
        r'appeared in the output as soon as they were in the config. '
        r'That is the design working. But the run also showed what '
        r'working does not mean:'),
    ...pt('#', 'SUPER+F prints window.fullscreen',
        'b22bf50 added hl.dsp.window.fullscreen, and no branch of the '
        'if/else chain knows it. It falls into the final else, so the '
        'sheet shows the raw dispatcher name where the neighbouring '
        'lines say "toggle floating" and "toggle pseudotile". The '
        'fix is one more branch.'),
    ...pt('#', 'the power button prints as PowerOff',
        'gsub(/XF86/, "", combo) removes the vendor prefix from '
        'XF86PowerOff, XF86AudioMute and the rest. This is cosmetic '
        'and arguably intended, but the audio keys read '
        '"AudioRaiseVolume", not "Volume Up".'),
    ...pt('#', 'commands appear as commands',
        'the clipboard bind prints "noctalia msg panel-toggle '
        'clipboard" and the launcher prints "noctalia msg panel-toggle '
        'launcher". Anyone who knows noctalia can read them; for '
        'everyone else the cheat sheet answers "what does this key do" '
        'with a shell command.'),
    ...pt('#', 'a no-op line',
        r'the rule /[^ \t]/ { if ($0 !~ /^[ \t]*--/) pending = pending } '
        r'assigns the variable to itself. Perhaps it was meant to reset '
        r'a heading after a code line; the repo does not say, and as '
        r'written it does nothing.'),
    ...sec('a dependency the script does not declare'),
    ...para('#',
        r'The same run revealed something about the script’s awk. The '
        r'sheet printed the key as "mod + T", not "SUPER + T", and '
        r'the scroll binds as "mod + mouse_down", not "Scroll Down". '
        r'Both rely on the \< and \> word-boundary operators: '
        r'gsub("\\<" v "\\>", ...) for variables, and /\<mouse_down\>/ '
        r'for key names. Those operators are an extension of GNU awk; '
        r'under mawk they match nothing, so the substitutions silently '
        r'do not happen. A one-line test confirms it in isolation: '
        r'the pattern /\<mouse_down\>/ left the text unchanged, '
        r'while the plain pattern /mouse_down/ replaced it.'),
    blank,
    ...para('#',
        r'That does not make the script wrong for its owner. The README '
        r'says the system is Arch, where awk is probably GNU awk, but '
        r'nothing in the repo (packages/pacman.txt lists base, not '
        r'gawk by name) says so, and gawk was not available to run and '
        r'see the intended output. So the statement of record is this: '
        r'the script needs an awk with word boundaries, it does not '
        r'check for one, and with the wrong awk it degrades quietly '
        r'instead of failing. A tiny guard at the top, or a version '
        r'check, would turn a mystery into a message.'),
    ...sec('the contract with hyprland.lua'),
    ...para('#',
        r'Put together, the script and the config have an unwritten '
        r'agreement. Whoever edits hyprland.lua keeps these:'),
    ...pt('#', 'one bind per line',
        'the key expression and the hl.dsp call on the same line, '
        'separated by a comma.'),
    ...pt('#', 'string locals on one line',
        'local name = "value", so the script can substitute them.'),
    ...pt('#', 'heading comments',
        'a short comment (under 40 characters, starting with a letter) '
        'directly above a group of binds, optionally followed by an '
        'em dash and an explanation.'),
    ...pt('#', 'the loop idiom',
        'workspace binds end their key expression with .. i.'),
    ...pt('#', 'new dispatchers need a branch',
        'otherwise they print their raw name, as SUPER+F does.'),
    ...para('#',
        r'None of this is enforced; it is kept by the person who '
        r'wrote both files. The comment in the Help section of '
        r'hyprland.lua is the only mention of the script on the '
        r'config’s side.'),
    ...sec('what is not here'),
    ...pt('#', 'no tests',
        'there is no test script and no CI in the repository. The '
        'script is simple to test by design (config path from the '
        'environment, paging switch), but nobody has written the test.'),
    ...pt('#', 'no history to speak of',
        'one commit. The decisions in the file (self-paging, the '
        '40-character heading rule, the loop special case) arrived '
        'fully formed on 2026-09-19 at 18:28, so the repo cannot show '
        'what was tried first.'),
    ...pt('#', 'no Lua parsing',
        'the awk reads text, not syntax. Commented-out binds are '
        'skipped because comment lines are consumed by rule 2, but any '
        'other line that contains hl.bind( followed by , hl.dsp would '
        'be printed whatever its context, and a bind written across '
        'two lines would be silently skipped.'),
    ...sec('why it is a good small tool'),
    ...para('#',
        r'The script is about ninety lines of awk and does one useful '
        r'thing that is easy to skip: it keeps documentation and '
        r'behaviour in the same file. The trick is to '
        r'accept a constraint (a regular, one-line style for binds) '
        r'in exchange for never maintaining a second list. The '
        r'failures found above are the kind this approach produces, an '
        r'unmapped dispatcher and an undeclared awk, and both are '
        r'visible in the output instead of hiding in a stale document.'),
    blank,
    link('→ github.com/XNash/xyno-arch', 'https://github.com/XNash/xyno-arch'),
  ],
);
