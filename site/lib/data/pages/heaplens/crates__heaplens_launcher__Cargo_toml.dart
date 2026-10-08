import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-launcher/Cargo.toml',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'Cargo.toml — the crate is heaplens-launcher, the program is HeapLens'),
    cm('#', r'sixteen lines, one capitalised binary name, and the only dependency is the operating system'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv('role', r'manifest for the launcher that users actually double-click'),
    kv('language', r'TOML'),
    kv('size', r'16 lines, one commit: 43fc22e (2026-07-08), never edited since'),
    kv('output', r'HeapLens.exe, from a package called heaplens-launcher'),
    kv('resolved', r'windows-sys 0.61.2 (Cargo.lock)'),
    ...sec(r'the whole file'),
    ...code('toml', 'crates/heaplens-launcher/Cargo.toml · the manifest', r'''
[package]
name = "heaplens-launcher"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "HeapLens"
path = "src/main.rs"

[dependencies]
windows-sys = { version = "0.61", features = [
    "Win32_Foundation",
    "Win32_Security",
    "Win32_System_JobObjects",
    "Win32_System_Threading",
] }'''),
    ...sec(r'two names for one thing'),
    ...para('#',
        r'The package is called heaplens-launcher, like its sibling '
        r'crates, so cargo commands that say -p heaplens-launcher '
        r'find it. The binary is called HeapLens, with capitals. The '
        r'[[bin]] table is the only place in the workspace where '
        r'an executable name is chosen for a person and not for a '
        r'program: every other binary (heaplens-daemon, '
        r'heaplens-injector, h1-harness) is named for what it is. '
        r'The launcher’s output is what the delivery folder shows '
        r'in the file explorer, so it gets the product’s name.'),
    blank,
    ...para('#',
        r'The names this executable has to know about are in the '
        r'source and not in the manifest. It looks for '
        r'heaplens-daemon.exe and heaplens_flutter.exe next to itself '
        r'by constant, and the pair of them is the packaging contract '
        r'of the delivery folder. A change to the daemon’s binary name '
        r'in its own manifest would compile and then fail at the '
        r'launcher’s first assert!, because nothing here ties the two '
        r'together. The page for crates/heaplens-launcher/src/main.rs '
        r'covers what that failure looks like.'),
    ...sec(r'a launcher with no heaplens crate in it'),
    ...para('#',
        r'The [dependencies] table has one entry, windows-sys. The launcher '
        r'does not use heaplens-protocol, does not use the daemon’s library, '
        r'and cannot see the WebSocket messages that the app and the '
        r'daemon exchange. That is the correct size for a '
        r'process supervisor. Its knowledge of the daemon is the '
        r'address of a TCP port, and its knowledge of the app is a file '
        r'name. The design document (docs/stage7-injection-design.md, '
        r'section 3.1) uses the same argument to keep the process picker '
        r'out of the launcher: it "has no process-enumeration facility '
        r'and no UI", and giving it either would mean building "a second, '
        r'separate UI toolkit inside a component designed to be '
        r'invisible".'),
    blank,
    ...para('#',
        r'The same rule also explains something the manifest does '
        r'not contain: no tokio, no logging crate, no argument parser. '
        r'The launcher is a straight-line, blocking program that '
        r'writes two plain text files with writeln!. A runtime would '
        r'have been the largest thing in it.'),
    ...sec(r'the four feature flags'),
    ...para('#',
        r'The source imports from three of the four modules. Matching '
        r'them to the code:'),
    ...pt('#', r'Win32_System_JobObjects',
        r'the reason the crate has a dependency at all. main.rs imports '
        r'AssignProcessToJobObject, CreateJobObjectW, '
        r'JobObjectExtendedLimitInformation, SetInformationJobObject, '
        r'JOBOBJECT_EXTENDED_LIMIT_INFORMATION and '
        r'JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE: the whole of the '
        r'kill-on-close mechanism the module comment is about.'),
    ...pt('#', r'Win32_Foundation',
        r'HANDLE, the type of the job handle that create_kill_on_close_job '
        r'returns and assign_to_job takes.'),
    ...pt('#', r'Win32_Security',
        r'no import names anything from it. My reading is that it is '
        r'needed by CreateJobObjectW, whose first parameter is a pointer '
        r'to SECURITY_ATTRIBUTES; the code passes std::ptr::null() for it '
        r'(the call is CreateJobObjectW(std::ptr::null(), '
        r'std::ptr::null())). I could not confirm that against the '
        r'windows-sys sources, which are not in the local registry.'),
    ...pt('#', r'Win32_System_Threading',
        r'no import names anything from it either. The most likely '
        r'consumer is a type inside the structure that is imported: '
        r'JOBOBJECT_EXTENDED_LIMIT_INFORMATION is declared in the '
        r'Windows headers with an IO_COUNTERS field, and I believe '
        r'windows-sys places that type in the Threading module. That is '
        r'from memory of the bindings, not from the source here, so it '
        r'is a guess.'),
    blank,
    ...para('#',
        r'The pattern, a feature that is listed and never named, '
        r'also appears in the injector’s manifest, and it has a '
        r'practical consequence for anyone who tries to trim the list. '
        r'Removing a feature that no line mentions can still break the '
        r'build, and I would expect the error to be an unresolved '
        r'import or a missing function at a line that uses it, not a '
        r'message about the feature.'),
    ...sec(r'what the root manifest adds'),
    ...pt('#', r'debug = true in the release profile',
        r'the workspace root keeps debug information in release builds, '
        r'with a long comment about why the ownership function needs '
        r'it. The launcher does not need symbols, but the profile is '
        r'workspace-wide, so HeapLens.exe is built with them. The '
        r'writer thread’s doc comment in heaplens-alloc/src/writer.rs '
        r'records a release that shipped .exe files without their '
        r'matching .pdb files, which made every symbol collapse; that '
        r'concerns the producer executables, not this one.'),
    ...pt('#', r'workspace membership',
        r'"crates/heaplens-launcher" is listed in the root members, so '
        r'a plain cargo build --release makes HeapLens.exe along with '
        r'everything else. Nothing builds the Flutter app; the launcher '
        r'only expects to find it.'),
    ...sec(r'what the manifest cannot say'),
    ...pt('#', r'an application manifest',
        r'there is no build script, no resource file and no embedded '
        r'icon or version information. The crate produces a bare '
        r'executable; any icon or metadata that HeapLens.exe has in the '
        r'delivery folder comes from outside this repository, or does '
        r'not exist. I found no such step in the repo.'),
    ...pt('#', r'a platform',
        r'the main.rs imports std::os::windows, so the crate cannot '
        r'compile elsewhere. Like the injector it is honest about it '
        r'and has no cfg.'),
    ...pt('#', r'a test target',
        r'there is no [dev-dependencies] and no tests directory. The '
        r'launcher’s behaviour is exercised by running it.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-launcher/Cargo.toml',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-launcher/Cargo.toml'),
  ],
);
