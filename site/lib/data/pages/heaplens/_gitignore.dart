import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/.gitignore',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', '.gitignore — seven lines that describe the workflow'),
    cm('#', 'what a project says by what it refuses to track'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', 'keeps build output, packages, logs and databases out of git'),
    kv('language', 'gitignore patterns'),
    kv('size', '7 lines'),
    kv('born', '2026-07-08, fourteen days after the first commit'),
    kv('commit', '43fc22e, “Adds .gitignore (previously absent)”'),

    ...sec('the whole file'),
    ...code('text', '.gitignore', r'''
/target/
/dist/
/heaplens_flutter/build/
/heaplens_flutter/.dart_tool/
/.idea/
*.log
heaplens.db'''),
    ...para('#',
        'The file is small enough to read in a glance and still '
        'says a lot, because each line exists for a specific '
        'thing the project produces. Going down the list:'),

    ...sec('line by line'),
    ...pt('#', '/target/',
        'Cargo’s output directory. Anchored to the root with a '
        'leading slash, so it means the workspace’s one target '
        'directory. The workspace has seven crates and a single '
        'target, which is part of why the one pattern is enough.'),
    ...pt('#', '/dist/',
        'the packaged build. The commit messages refer to '
        'versioned folders (dist/v3, dist/v4, dist/v5), and a '
        'comment in the injector to dist/HeapLens/, holding '
        'executables beside their .pdb files. Treating the '
        'package as an artifact and not as source fits how it '
        'is made: no packaging script is tracked anywhere in '
        'the repository.'),
    ...pt('#', '/heaplens_flutter/build/ and .dart_tool/',
        'Flutter’s outputs. They are anchored to the app '
        'directory. The app also has its own .gitignore under '
        'heaplens_flutter/, so these two lines overlap with it; '
        'they cost nothing and protect against running Flutter '
        'commands from the wrong directory.'),
    ...pt('#', '/.idea/',
        'an editor’s project folder. The only line in the file '
        'about a person rather than a tool.'),
    ...pt('#', '*.log',
        'unanchored, so it matches at any depth. The launcher '
        'writes two logs next to its own executable:'),
    ...code('rust', 'crates/heaplens-launcher/src/main.rs · log files', r'''
    let mut log_file = open_log(&dir, "launcher.log");
    let daemon_log = open_log(&dir, "daemon.log");'''),
    ...para('#',
        'A windowed program with no console needs somewhere to '
        'say what happened. The launcher is built with the '
        'Windows subsystem, so these two files are its only '
        'voice, and in a packaged folder they sit beside the '
        'executables.'),
    ...pt('#', 'heaplens.db',
        'the daemon’s SQLite file, also unanchored. Its name is '
        'the default for the database path setting, relative to '
        'wherever the daemon happens to run:'),
    ...code('rust', 'crates/heaplens-daemon/src/config.rs · the default', r'''
            db_path: std::env::var("HEAPLENS_DB_PATH")
                .unwrap_or_else(|_| "heaplens.db".to_owned()),'''),
    ...para('#',
        'Run from the repository root, it lands at the root. '
        'Started by the launcher, which sets the daemon’s working '
        'directory to its own folder, it lands in the package. '
        'Because the pattern has no slash it covers both. The '
        'H1 harness sidesteps the question by giving every run '
        'its own database file in the temp directory and deleting '
        'it afterwards.'),

    ...sec('what the file does not say'),
    ...pt('#', 'Cargo.lock is tracked',
        'there is no ignore for it, and it has been committed '
        'since the first commit. For a repository whose products '
        'are executables, that is the standard choice. It also '
        'makes the demo-dependency commit visible: that one '
        'change inserted 4,415 lines into the lock file and '
        'removed 443.'),
    ...pt('#', 'the user-facing README.txt is not here',
        'an earlier tooltip in the UI pointed the user at a '
        'README.txt (823dac7), and a later commit message '
        'describes rewriting it for dist/v5 (864167e). Since it '
        'lives in the ignored dist folder, the known-issues text '
        'users were told to read is not under version control '
        'in this repository.'),
    ...pt('#', '.pdb files',
        'not named here, but they are build output under '
        'target/, which the first line covers. They matter '
        'anyway: the packaging rule '
        'that the executables must ship with their matching '
        'PDBs is documented in a comment in writer.rs, not '
        'here.'),

    ...sec('why it arrived two weeks late'),
    ...para('#',
        'Fourteen days of work, 89 commits, and no .gitignore. '
        'The reason is not in a message, but three of the plans '
        'suggest one. In the protocol, allocator and daemon M3 '
        'plans each task ends with an explicit, narrow staging '
        'command, git add followed by the specific paths the task '
        'touched (for example the daemon plan’s “git add '
        'Cargo.toml crates/heaplens-daemon/”). Work done that way '
        'never sweeps up target/. The M4 and M5 plans contain no '
        'git add lines at all, so the habit is not documented for '
        'the later stages. The commit that finally added the file '
        'is the one that added a packaged launcher and a dist '
        'folder, outside that path-by-path discipline. That is an '
        'inference, not a quoted rationale.'),
    ...para('#',
        'The lesson is a small one and applies elsewhere: '
        'discipline in one place can hide the absence of a '
        'safeguard in another. It was cheap to add, and the '
        'commit that added it says so in one clause.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
