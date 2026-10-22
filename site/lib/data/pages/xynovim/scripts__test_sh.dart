import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/scripts/test.sh',
  lines: [
    cm(r'#', '──────────────────────────────────────────'),
    cm(r'#', r'scripts/test.sh'),
    cm(r'#', r'one headless Neovim per spec file'),
    cm(r'#', r'isolated, time-limited, and honest about hangs'),
    cm(r'#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the test runner on Linux (CI’s Linux job and make test)'),
    kv(r'language', r'bash (set -uo pipefail, deliberately not -e)'),
    kv(r'size', r'199 lines, five commits, 2026-10-13 to 2026-10-14'),
    kv(r'protocol', r'runs tests/runner.lua with XYNO_SPEC=<file>, parses the XYNO_RESULT line'),
    kv(r'exit status', r'0 all passed (skips allowed) · 1 any failure, timeout or crash · 2 usage or setup'),
    ...sec(r'why this file exists'),
    ...para(r'#', r'The suite tests an editor configuration, and an editor configuration is a bad fit for an in-process test framework: it changes global state, starts language servers, opens terminals and sometimes does not exit. So the runner does the simplest robust thing. Every spec file in tests/ gets its own nvim --headless process with the real configuration loaded, a time limit, and a private home for its state. What a spec does to Neovim dies with the process. This script is the supervisor of those processes.'),
    blank,
    ...para(r'#', r'It arrived with the first test infrastructure commit, cf2b8e1 on 2026-10-13, and was extended by b2fee5c (per-spec timeout, the exit-hang fix) the same day. The shellcheck comment above the cleanup function reflects that the suite lints this script: tests/health-bootstrap-ci_spec.lua runs shellcheck over scripts/bootstrap.sh and scripts/test.sh when shellcheck is installed.'),
    blank,
    ...code('bash', r'scripts/test.sh · lines 1-20', r'''
#!/usr/bin/env bash
# Run the spec files in tests/ headless, each in its own nvim process.
#
# Usage: scripts/test.sh [options] [pattern...]
#   pattern       only spec files whose path contains it (several = any of them)
#   --list        print the spec files and exit
#   --coverage    collect Lua line coverage of the repo's own modules, print the
#                 per-file report afterwards (several times slower)
#   --timeout N   hard timeout per spec file in seconds (default 120,
#                 or $TEST_TIMEOUT); a hung file fails, the suite goes on
#   -v, --verbose print the full output of every spec file, not only failures
#
# Isolation: the config is this checkout (linked into a temp XDG_CONFIG_HOME),
# XDG_STATE_HOME and XDG_CACHE_HOME are temp dirs (no shada, undo, lsp.log or
# local-history leaks into your real ones), XDG_DATA_HOME is the REAL one: the
# plugins are not reinstalled. A fresh machine (CI) must run scripts/bootstrap.sh
# first. Specs needing rust-analyzer/cargo/bwrap/tmux skip with a message when
# they are missing (XYNO_TEST_SKIP_RUST=1 forces the Rust ones to skip).
# Exit status: 0 all passed (skips allowed), 1 any failure/timeout, 2 usage/setup.
set -uo pipefail
'''),
    ...para(r'#', r'The header is also the help text. The -h option prints lines 2 up to the set line with sed and strips the leading comment marker, so the documentation cannot drift from the script that prints it.'),
    blank,
    ...sec(r'argument parsing and spec selection'),
    ...code('bash', r'scripts/test.sh · lines 22-62', r'''
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
timeout_s=${TEST_TIMEOUT:-120}
list=0 cov=0 verbose=0
patterns=()
while [ $# -gt 0 ]; do
  case $1 in
    --list) list=1 ;;
    --coverage) cov=1 ;;
    --timeout)
      shift
      [ $# -gt 0 ] || { echo "test.sh: --timeout needs seconds" >&2; exit 2; }
      timeout_s=$1
      ;;
    -v | --verbose) verbose=1 ;;
    -h | --help) sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*) echo "test.sh: unknown option $1" >&2; exit 2 ;;
    *) patterns+=("$1") ;;
  esac
  shift
done

specs=()
for f in "$repo"/tests/*_spec.lua; do
  [ -e "$f" ] || continue
  rel=${f#"$repo"/}
  if [ ${#patterns[@]} -gt 0 ]; then
    hit=0
    for p in "${patterns[@]}"; do [[ $rel == *$p* ]] && hit=1; done
    [ $hit = 1 ] || continue
  fi
  specs+=("$rel")
done

if [ $list = 1 ]; then
  printf '%s\n' "${specs[@]}"
  exit 0
fi
if [ ${#specs[@]} -eq 0 ]; then
  echo "test.sh: no spec file matches ${patterns[*]:-(none found in tests/)}" >&2
  exit 2
fi
'''),
    ...para(r'#', r'A pattern is any string, and a spec file is selected when its path contains one of them, so scripts/test.sh rust runs every spec with rust in its name. The loop sets a flag when any pattern matches, with the glob in [[ $rel == *$p* ]]. The option parser rejects unknown options with exit 2 rather than treating them as patterns; a mistyped flag would otherwise be a surprising filter. No match is also exit 2 with a message that names the pattern, and a missing nvim is exit 2. All setup problems share one code that CI can tell apart from a test failure.'),
    blank,
    ...para(r'#', r'set -e is not used on purpose. The script has to survive a failing nvim, a failing grep and a kill on a process that is already gone, and it collects results instead of stopping at the first non-zero status.'),
    blank,
    ...sec(r'isolation'),
    ...code('bash', r'scripts/test.sh · lines 68-102', r'''
data=${XDG_DATA_HOME:-$HOME/.local/share}
if [ ! -d "$data/nvim/lazy/lazy.nvim" ]; then
  echo "test.sh: no plugins in $data/nvim/lazy. Run scripts/bootstrap.sh first" >&2
  echo "  (with this checkout linked as the config: ln -s '$repo' ~/.config/nvim)." >&2
  exit 2
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/xynotest.XXXXXX")
export XYNO_TMUX_PREFIX=xynotest-$$
lock_before=$work/lazy-lock.before
cp "$repo/lazy-lock.json" "$lock_before"

# shellcheck disable=SC2317,SC2329  # only called through the EXIT trap
cleanup() {
  # leftover tmux servers of the specs
  if command -v tmux >/dev/null 2>&1; then
    for s in "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$XYNO_TMUX_PREFIX"-*; do
      [ -S "$s" ] || continue
      tmux -L "$(basename "$s")" kill-server >/dev/null 2>&1
      rm -f "$s" # the dead server leaves its socket file behind
    done
  fi
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$work"/{config,state,cache,tmp,cov}
ln -s "$repo" "$work/config/nvim"
export XDG_CONFIG_HOME=$work/config XDG_STATE_HOME=$work/state XDG_CACHE_HOME=$work/cache
export XDG_DATA_HOME=$data
export XYNO_TEST_TMP=$work/tmp
export TMPDIR=$work/tmp
repo_real=$(readlink -f "$repo")
export XYNO_COV_ROOTS="$work/config/nvim:$repo_real"
'''),
    ...para(r'#', r'This block is the core of the design. The configuration under test is this very checkout, linked into a temporary XDG_CONFIG_HOME as nvim. State and cache are temporary, so no shada, undo history, lsp.log or local-history data leaks into the real ones. The data directory is deliberately the real one, because the plugins live there and reinstalling them for every run would take minutes. On a clean machine the script refuses to run and says to run scripts/bootstrap.sh first. TMPDIR is also redirected, so anything a spec writes into the system temp folder lands in a directory that is deleted at the end.'),
    blank,
    ...para(r'#', r'The lockfile is copied before the run (lock_before) and compared at the end, with a WARNING if it changed. A spec that triggers a plugin update would otherwise silently dirty the checkout.'),
    blank,
    ...para(r'#', r'XYNO_TMUX_PREFIX gives every run a unique tmux socket prefix (xynotest-<pid>), which makes the cleanup function able to find and kill exactly the tmux servers that this run created.'),
    blank,
    ...code('bash', r'scripts/test.sh · lines 80-93', r'''
# shellcheck disable=SC2317,SC2329  # only called through the EXIT trap
cleanup() {
  # leftover tmux servers of the specs
  if command -v tmux >/dev/null 2>&1; then
    for s in "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$XYNO_TMUX_PREFIX"-*; do
      [ -S "$s" ] || continue
      tmux -L "$(basename "$s")" kill-server >/dev/null 2>&1
      rm -f "$s" # the dead server leaves its socket file behind
    done
  fi
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
'''),
    ...para(r'#', r'The cleanup function runs on EXIT. It lists the tmux sockets that carry the run’s prefix, kills the server behind each, removes the socket file (a dead server leaves one behind, says the comment) and deletes the temporary directory. INT and TERM exit with 130 so the EXIT trap fires. Specs that need tmux therefore leave nothing behind even when the run is interrupted.'),
    blank,
    ...sec(r'the environment banner'),
    ...code('bash', r'scripts/test.sh · lines 104-112', r'''
echo "xynovim tests: ${#specs[@]} spec file(s), timeout ${timeout_s}s each"
if [ "${XYNO_TEST_SKIP_RUST:-}" = 1 ]; then
  echo "  XYNO_TEST_SKIP_RUST=1 (Rust specs will skip)"
elif command -v rust-analyzer >/dev/null 2>&1 && rust-analyzer --version >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1; then
  echo "  rust-analyzer + cargo: found (Rust specs run)"
else
  echo "  rust-analyzer/cargo: NOT usable (Rust specs will skip)"
fi
[ $cov = 1 ] && echo "  coverage: on"
'''),
    ...para(r'#', r'Before the first spec the runner prints how many files it will run and whether Rust specs can run: rust-analyzer --version must succeed (a rustup proxy can exist without a working rust-analyzer behind it), cargo must exist, and XYNO_TEST_SKIP_RUST=1 forces the skip. The same facts appear at the top of a CI log, so a skipped group of specs is explained before anyone reads the numbers.'),
    blank,
    ...sec(r'the per-spec loop'),
    ...code('bash', r'scripts/test.sh · lines 114-135', r'''
set -m # every nvim gets its own process group, so leftovers can be killed
tot_pass=0 tot_fail=0 tot_skip=0 failed_files=()
t_all=$(date +%s)
for rel in "${specs[@]}"; do
  log=$work/$(basename "$rel").log
  args=(--headless)
  extra=()
  if [ $cov = 1 ]; then
    args+=(--cmd "luafile $repo/tests/coverage_hook.lua")
    extra+=(XYNO_COV_OUT="$work/cov/$(basename "$rel" .lua).json")
  fi
  t0=$(date +%s)
  # A slow spec states its own limit in a "-- xyno-timeout: N" line near the top
  # (it is never lower than the global one).
  spec_to=$(head -n 15 "$repo/$rel" | sed -n 's/^-- xyno-timeout: *\([0-9][0-9]*\).*/\1/p' | head -n1)
  eff_to=$timeout_s
  [ -n "$spec_to" ] && [ "$spec_to" -gt "$eff_to" ] && eff_to=$spec_to
  # (a subshell, so bash does not print "Killed" when the timeout has to use -9)
  (env XYNO_SPEC="$repo/$rel" ${extra[@]+"${extra[@]}"} \
    timeout -k 5 "$eff_to" nvim "${args[@]}" -S "$repo/tests/runner.lua" \
    </dev/null >"$log" 2>&1) &
  pid=$!
'''),
    ...para(r'#', r'set -m gives each background job its own process group. That is what makes the later kill -- -PID reach the language servers and helper processes that nvim spawned, not only nvim. A spec can raise its own limit with a line -- xyno-timeout: N in its first 15 lines, found with head and sed; the effective limit is never below the global one. The process is started in a subshell so that bash does not print Killed when timeout needs the -9 signal.'),
    blank,
    ...sec(r'hang handling'),
    ...code('bash', r'scripts/test.sh · lines 136-155', r'''
  # A spec that printed its result but whose nvim does not exit (seen once in a
  # while, cause unknown) must not eat the whole timeout: 30 s of grace, then the
  # process group is killed and the printed result counts, with a note.
  seen="" hung=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ -z "$seen" ] && grep -aq '^XYNO_RESULT ' "$log"; then seen=$SECONDS; fi
    if [ -n "$seen" ] && [ $((SECONDS - seen)) -ge 30 ]; then
      hung=1
      kill -TERM -- "-$pid" 2>/dev/null
      sleep 3
      kill -KILL -- "-$pid" 2>/dev/null
      break
    fi
    sleep 0.5
  done
  wait "$pid"
  rc=$?
  [ $hung = 1 ] && rc=0
  kill -TERM -- "-$pid" 2>/dev/null || true # stragglers (language servers...)
  secs=$(($(date +%s) - t0))
'''),
    ...para(r'#', r'The comment is candid: a spec that printed its result but whose nvim does not exit happens now and then, cause unknown. Rather than let it eat the whole timeout, the loop watches the log for the XYNO_RESULT line, and gives the process 30 seconds of grace after it appears, then kills the group (TERM, three seconds, KILL). A run that was hung after reporting is treated as exit 0 and a NOTE is printed, so the result counts but is not hidden. After wait, a TERM goes to the whole group once more to clear stragglers such as language servers.'),
    blank,
    ...sec(r'classifying the outcome'),
    ...code('bash', r'scripts/test.sh · lines 157-171', r'''
  res=$(grep -a '^XYNO_RESULT ' "$log" | tail -n1)
  if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then
    status="TIMEOUT"; p=0; f=1; s=0
  elif [ -z "$res" ]; then
    status="CRASH"; p=0; f=1; s=0
  else
    p=$(sed -n 's/.*passed=\([0-9]*\).*/\1/p' <<<"$res")
    f=$(sed -n 's/.*failed=\([0-9]*\).*/\1/p' <<<"$res")
    s=$(sed -n 's/.*skipped=\([0-9]*\).*/\1/p' <<<"$res")
    if [ "$f" -gt 0 ] || [ "$rc" != 0 ]; then status="FAIL"; [ "$f" -eq 0 ] && f=1; else status="PASS"; fi
  fi
  tot_pass=$((tot_pass + p)); tot_fail=$((tot_fail + f)); tot_skip=$((tot_skip + s))
  printf '%-7s %s  %s passed, %s failed, %s skipped (%ss)\n' "$status" "$rel" "$p" "$f" "$s" "$secs"
  [ $hung = 1 ] && echo "    NOTE: nvim did not exit 30 s after the result line and was killed (the result above counts)"
  [ "$status" = PASS ] || failed_files+=("$rel")
'''),
    ...para(r'#', r'Exit codes 124 and 137 are what timeout gives for a time-out and for a kill, and become TIMEOUT. A missing result line becomes CRASH. Otherwise the three counts come from the result line with sed, and the file is FAIL if any test failed or nvim exited non-zero, PASS otherwise. A file that counted zero failures but exited non-zero is reported as one failure, so no combination of codes can produce a green PASS. The line that is printed for each spec carries the status, the path, the counts and the seconds.'),
    blank,
    ...code('bash', r'scripts/test.sh · lines 173-199', r'''
  if [ "$verbose" = 1 ]; then
    sed 's/^/    | /' "$log"
  else
    grep -a -E '^(SKIP|FAIL)|^       ' "$log" | sed 's/^/    /'
    if [ "$status" = TIMEOUT ] || [ "$status" = CRASH ]; then
      echo "    ($status, exit $rc; last output)"
      tail -n 15 "$log" | sed 's/^/    | /'
    fi
  fi
done

if [ $cov = 1 ]; then
  echo
  nvim -l "$repo/scripts/coverage.lua" "$repo" "$work/cov"
fi

if ! cmp -s "$lock_before" "$repo/lazy-lock.json"; then
  echo "WARNING: lazy-lock.json changed during the run (git diff lazy-lock.json)"
fi

echo
echo "total: $tot_pass passed, $tot_fail failed, $tot_skip skipped in $(($(date +%s) - t_all))s"
if [ ${#failed_files[@]} -gt 0 ]; then
  echo "failed: ${failed_files[*]}"
  exit 1
fi
exit 0
'''),
    ...para(r'#', r'Without -v only the lines that begin with SKIP or FAIL, or with seven spaces (the detail lines under a failure), are shown, so a green run reads as a list of one line per file. On a timeout or crash, the last 15 lines of the log are printed. The coverage branch (line 186) runs scripts/coverage.lua over the dumps. At the end the lockfile is compared and the totals printed; failed files are listed.'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt(r'#', r'process per spec', r'costs a startup for each of the files, but a hung language server or a corrupted global cannot affect the next spec.'),
    ...pt(r'#', r'real plugin data, fake everything else', r'fast, and it keeps the user’s own state out of the tests, with the one risk that the real plugin directory could be changed by a spec (hence the lockfile warning).'),
    ...pt(r'#', r'parse a protocol, not an exit code', r'the XYNO_RESULT line says how many passed, failed and were skipped even when nvim exits late or badly.'),
    ...sec(r'the portable twin'),
    ...para(r'#', r'macOS has no GNU timeout command, which this script uses to limit a spec, so the macOS job in platforms.yml runs the Lua runner instead. scripts/test.lua does the same job in Lua so that Windows can run it. The two scripts share the protocol, the exit codes, the 15-line header scan and the 30-second grace; they differ in coverage (test.sh only) and in how they kill a tree (negative PIDs here, taskkill there).'),
    blank,
    ...sec(r'history'),
    ...pt(r'#', r'cf2b8e1 2026-10-13', r'added with the harness, the helpers and the CI job.'),
    ...pt(r'#', r'b2fee5c 2026-10-13', r'22 feature specs, per-spec timeout and the exit-hang fix.'),
    ...pt(r'#', r'98c9bb4 2026-10-13', r'--timeout without a value now exits 2 with a message (before, the shell expansion failed with its own error).'),
    ...pt(r'#', r'fc2062a 2026-10-14', r'adds a shellcheck suppression for the cleanup function, which is only called through the EXIT trap; the commit is the CI clean-machine one.'),
    ...pt(r'#', r'0b0eee8 2026-10-14', r'extends the suppression to SC2329 and moves readlink -f of the repo into repo_real.'),
  ],
);
