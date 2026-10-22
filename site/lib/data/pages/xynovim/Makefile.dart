import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/Makefile',
  lines: [
    cm(r'#', '──────────────────────────────────────────'),
    cm(r'#', r'Makefile'),
    cm(r'#', r'two aliases, nothing else'),
    cm(r'#', r'make test and make coverage'),
    cm(r'#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'shortcuts for the test runner'),
    kv(r'language', r'GNU Make'),
    kv(r'size', r'7 lines, one commit (cf2b8e1, 2026-10-13)'),
    kv(r'targets', r'test · coverage'),
    ...sec(r'why this file exists'),
    ...para(r'#', r'The test runner was added on 2026-10-13 in cf2b8e1 along with the rest of the test infrastructure, and the Makefile came in the same commit. It is a convenience layer: the logic lives in scripts/test.sh, and the Makefile only gives it two short names.'),
    blank,
    ...code('bash', r'Makefile · lines 1-7', r'''
# Aliases for the scripts; see README "Tests".
.PHONY: test coverage
test:
	scripts/test.sh $(ARGS)

coverage:
	scripts/test.sh --coverage $(ARGS)
'''),
    ...sec(r'how it works'),
    ...pt(r'#', r'the header comment', r'points to the README section called Tests, which is where the options are documented. The Makefile does not repeat them.'),
    ...pt(r'#', r'.PHONY', r'test and coverage are not files, so they are declared phony. Without it a directory or file called test would make the target look up to date.'),
    ...pt(r'#', r'make test', r'runs scripts/test.sh with whatever is in ARGS. make test ARGS="rust --timeout 300" runs only the spec files whose path contains rust, with a longer timeout.'),
    ...pt(r'#', r'make coverage', r'the same with --coverage added. The runner then collects Lua line coverage of the repository’s own modules and prints a per-file report, at the cost of being several times slower (the test.sh header says so).'),
    ...sec(r'design decisions'),
    ...para(r'#', r'There is deliberately no install target, no lint target and no default goal. Setup is scripts/bootstrap.sh, which has its own contract (the lockfile must not change) and is not wrapped. The README names make test and make coverage next to scripts/test.sh; on Windows the PowerShell entry point scripts\test.ps1 is used instead.'),
    blank,
    ...para(r'#', r'Since the recipes are indented with a tab, the file must keep tabs; the stylua configuration does not touch it, and .gitattributes only normalises line endings.'),
    blank,
    ...sec(r'history'),
    ...pt(r'#', r'cf2b8e1 2026-10-13', r'added with scripts/test.sh, scripts/coverage.lua, the tests directory and the CI job. Unchanged since.'),
  ],
);
