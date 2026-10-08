import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-arch/home/.bashrc',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', '.bashrc — the shell, kept almost stock'),
    cm('#', 'ten inherited lines and four local decisions'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'interactive bash setup, symlinked to ~/.bashrc'),
    kv('language', 'bash'),
    kv('size', '14 lines: 12 at birth, 2 added two days later'),
    kv('history', '2 commits: 208de62 (2026-09-19), 5f2db81 (2026-09-21)'),
    kv('checked here', 'ran install.sh on a throw-away HOME, sourced the file'),

    ...sec('why this file exists'),
    ...para(
        '#',
        r'The first commit of this repository (d552dfd, 2026-09-19 '
        r'18:28) tracked the compositor, the shell widgets, the '
        r'terminal and the system tuning, and did not track the '
        r'shell itself. Six minutes later a second commit, 208de62, '
        r'titled “Track everything needed to reproduce the desktop”, '
        r'added it. The commit body gives the reason in one sentence '
        r'about something else, and it applies here as well: the point '
        r'is that “a fresh machine comes up identical instead of '
        r'falling back to defaults”. The body lists this file first '
        r'among the additions: “Add .bashrc, the Steam download '
        r'tweaks, the greetd PAM stack and the mkinitcpio preset”.'),
    blank,
    ...para(
        '#',
        r'So the file is a small piece of the reproducibility claim, '
        r'and it is the smallest piece that can still break it. Every '
        r'Ghostty window (Super+T in hyprland.lua) opens a bash '
        r'prompt; a PATH that differs between two machines is the '
        r'kind of difference that shows up months later as “command '
        r'not found”.'),

    ...sec('the whole file, in two halves'),
    ...code('bash', 'home/.bashrc · the inherited half', r'''
#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '
'''),
    ...para(
        '#',
        r'These ten lines look like the stock skeleton that the bash '
        r'package installs for new users on Arch. I believe that is '
        r'what they are, but the repo does not say so; it is the '
        r'one claim on this page I take from memory instead of from '
        r'a file. What can be shown is how little was changed: '
        r'diffed against a stock-looking file that I recreated for the '
        r'experiment, the repo version differs by exactly four added '
        r'lines at the end and nothing else.'),
    ...code('bash', 'home/.bashrc · the local half', r'''
export PATH="$HOME/.local/bin:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$PATH:$ANDROID_HOME/platform-tools"
. "$HOME/.cargo/env"'''),
    ...para(
        '#',
        r'Four lines, three decisions. Each one is a statement about '
        r'something that lives outside this repository, which is the '
        r'interesting part and is covered under “what the file '
        r'assumes”.'),

    ...sec('the guard on line 6'),
    ...para(
        '#',
        r'[[ $- != *i* ]] && return is the idiom that makes a bashrc '
        r'safe to source from anywhere. The special parameter $- '
        r'holds the option letters of the current shell, and the '
        r'letter i is present only in an interactive one. For '
        r'anything else the file returns before it sets a single '
        r'variable.'),
    blank,
    ...para(
        '#',
        r'The guard has a consequence for the four local lines that '
        r'is easy to miss. I sourced the file from a non-interactive '
        r'bash -c and printed ANDROID_HOME: it was empty. The same '
        r'file sourced by an interactive shell exported it. So '
        r'ANDROID_HOME and the two PATH edits exist for people typing '
        r'at a prompt, not for scripts, not for a systemd unit and '
        r'not for anything launched from a menu.'),
    blank,
    ...para(
        '#',
        r'That fits how the rest of the repo is written. The '
        r'compositor is started by greetd with --cmd start-hyprland '
        r'(system/etc/greetd/config.toml), not by an interactive '
        r'bash, so the session never reads this file. Where Hyprland '
        r'needs an environment it sets one itself, and where it runs '
        r'a helper it spells out the full path:'),
    ...code('lua', 'home/.config/hypr/hyprland.lua · session environment', r'''
hl.env("XCURSOR_THEME", "DotClick")
hl.env("XCURSOR_SIZE", "32")
-- SDL_VIDEODRIVER deliberately unset — forcing it breaks Steam titles.

-- ─── Autostart ───────────────────────────────────────────────────────────
hl.on("hyprland.start", function()
    hl.exec_cmd("noctalia")
    -- Notification clicks land on the sending app even if it ignores the
    -- activation token.
    hl.exec_cmd("/home/xynorash/.local/bin/notification-focus")
end)'''),
    ...para(
        '#',
        r'notification-focus lives in ~/.local/bin, the very '
        r'directory that line 11 of .bashrc puts at the front of '
        r'PATH, and still hyprland.lua calls it by absolute path. '
        r'The code implies the reason: the compositor cannot rely on '
        r'a PATH that only interactive shells have. The README '
        r'states the price of that choice as a note, “Paths inside '
        r'hyprland.lua and noctalia/config.toml are absolute”, and '
        r'tells you to adjust them for another username.'),

    ...sec('what the four local lines assume'),
    ...pt(
        '#',
        'PATH order',
        r'~/.local/bin goes first, platform-tools goes last. I '
        r'verified the order in a fresh interactive shell: the '
        r'personal directory was entry 1 and platform-tools was the '
        r'final entry. Putting your own scripts first lets them win '
        r'over a system program of the same name; putting the Android '
        r'tools last makes sure adb and fastboot can never shadow '
        r'something the distribution ships. The file does not say '
        r'this is why, so treat it as my reading.'),
    ...pt(
        '#',
        'ANDROID_HOME',
        r'the commit that added it (5f2db81, 2026-09-21 22:02, “Shell: '
        r'Android SDK platform-tools on PATH (adb, fastboot)”) '
        r'names the purpose: adb and fastboot. The path '
        r'~/Android/Sdk is not installed by anything in the repo. '
        r'Neither package list contains an Android package; the only '
        r'candidate in packages/aur.txt is jetbrains-toolbox, which '
        r'is bound to Super+Alt+J in hyprland.lua. That an IDE '
        r'created the SDK directory is a guess.'),
    ...pt(
        '#',
        'the cargo line',
        r'. "$HOME/.cargo/env" is the line that rustup’s installer '
        r'appends to shell startup files, as far as I know. It is '
        r'the last line, and the two Android lines were inserted '
        r'above it (the diff of 5f2db81 shows them landing between '
        r'the PATH line and the cargo line). Nothing in packages/ '
        r'installs rustup or a Rust toolchain.'),
    blank,
    ...para(
        '#',
        r'The last bullet is the only place the file can fail on a '
        r'fresh machine. The line is unguarded, so before rustup '
        r'exists every interactive shell prints one error and then '
        r'continues. I reproduced it on a throw-away HOME:'),
    blank,
    plain('  bash: .../fakehome/.cargo/env: No such file or directory'),
    blank,
    ...para(
        '#',
        r'It is cosmetic, because the line is last and bash keeps '
        r'going. A guard such as [ -f "$HOME/.cargo/env" ] && . '
        r'"$HOME/.cargo/env" would silence it. I note that as a '
        r'possible fix and not as something the repo does.'),

    ...sec('how it reaches ~/.bashrc'),
    ...para(
        '#',
        r'install.sh finds every regular file under home/ with find '
        r'-type f and symlinks it to the same relative path in $HOME. '
        r'Run against an empty throw-away HOME that already held a '
        r'skeleton .bashrc, it created 97 links (one per tracked file '
        r'under home/, 80 of them cursor files), moved the old file '
        r'to .bashrc.bak-<timestamp> and pointed ~/.bashrc at '
        r'home/.bashrc in the clone. The .gitignore patterns *.bak '
        r'and *.bak-* are there so that the backups never get '
        r'committed.'),
    blank,
    ...para(
        '#',
        r'Because the target is a symlink into the repo, a tool that '
        r'appends to ~/.bashrc edits the tracked file. That is '
        r'convenient when you want a new line recorded and surprising '
        r'when an installer writes to it. It is also a plausible '
        r'route for the cargo line to have entered the repo, but '
        r'the history cannot confirm that: the line is already in '
        r'the file at its first commit.'),

    ...sec('a small leak: nested shells'),
    ...para(
        '#',
        r'The PATH lines are not idempotent. Each export prepends or '
        r'appends again, so a second interactive bash started from '
        r'inside the first inherits the already extended PATH and '
        r'extends it once more. In the experiment a nested shell '
        r'listed ~/.local/bin twice and platform-tools twice. '
        r'Lookups still work, because the first match wins; the '
        r'cost is a longer PATH for each level of nesting, which only '
        r'matters if you start many nested shells.'),

    ...sec('what is not in it'),
    ...pt(
        '#',
        'no tool hooks',
        r'fzf and zoxide are both in packages/pacman.txt and neither '
        r'is initialised here. I cannot tell from the repo whether '
        r'that is intended; yazi, the file manager bound to Super+E, '
        r'can use both on its own as I understand it.'),
    ...pt(
        '#',
        'no EDITOR, no history settings',
        r'neovim is installed and nothing exports EDITOR or VISUAL. '
        r'There are no HISTSIZE or HISTCONTROL lines either, so '
        r'bash’s defaults apply.'),
    ...pt(
        '#',
        'a plain prompt',
        r'PS1 is the stock [user@host dir]$ with no colour and no '
        r'git status. The coloured parts of the desktop come from '
        r'noctalia’s theme templates; the prompt takes no part '
        r'in them.'),
    ...pt(
        '#',
        'one shell only',
        r'there is no .bash_profile, .profile or .zshrc in the repo, '
        r'so a login shell on a tty reads nothing from here that is '
        r'not already in the system defaults.'),

    ...sec('lessons'),
    ...para(
        '#',
        r'Keep the inherited file and add at the bottom. Four extra '
        r'lines make the diff against the distribution trivial to '
        r'read, and a distribution update to the skeleton is a '
        r'one-glance merge.'),
    blank,
    ...para(
        '#',
        r'A reproducible setup should either install what it '
        r'sources or guard the line. The cargo line and the SDK path '
        r'point at software the package lists never mention, so a '
        r'clean install of this repo gets a configured PATH for tools '
        r'that are not there yet. The honest summary is that the '
        r'.bashrc is accurate about the owner’s machine and only '
        r'partly reproducible on another one.'),
    blank,
    link('→ github.com/xynorash/xyno-arch',
        'https://github.com/xynorash/xyno-arch'),
  ],
);
