import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/rust-new_spec.lua',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'rust-new_spec.lua — new Rust projects with the real cargo, and no half-made directories when anything fails'),
    cm('--', r'pure text editing of manifests, real cargo new in temp dirs, stub cargo for failures, a dashboard rendered in tmux at many sizes'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'spec for lua/config/rust_new.lua (:RustNewBin, :RustNewLib, :RustNewWorkspace, :RustNewMember and three dashboard entries) and lua/plugins/rust-new.lua'),
    kv(r'language', r'Lua spec, 1114 lines, 55 it() blocks, 11 describe() blocks, 300 second timeout'),
    kv(r'platform', r'Linux and macOS (sh cargo stubs and a tmux dashboard)'),
    kv(r'history', r'4 commits: d163480, e166947 (2026-10-16), ff1c8fa (2026-10-16), cd602fd (2026-10-21)'),
    ...sec(r'why this file exists'),
    ...para('--', r'The commit d163480 (2026-10-16, "New Rust Binary, Library and Workspace entries on the dashboard") added four ways to start a Rust project from the editor. A command that creates directories, runs cargo and edits manifests is a command that can leave a mess. The header lists the layers: pure functions, flows with the real cargo in temp directories (cargo new works offline), the failure paths with a stub cargo, an empty PATH and a read-only parent, and the dashboard rendered in tmux at several window sizes.'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 1-6', r'''
-- xyno-timeout: 300
-- config.rust_new (:RustNewBin, :RustNewLib, :RustNewWorkspace, :RustNewMember and the three
-- dashboard entries) and lua/plugins/rust-new.lua. Pure functions first, then the flows with the
-- REAL cargo in temp directories (cargo new works offline), the failure paths (stub cargo / empty
-- PATH / read-only parent), and the dashboard rendered in tmux at several window sizes.
-- xyno-os: linux,macos (sh cargo stubs and a tmux dashboard)'''),
    ...sec(r'what is shared with the egui flow'),
    ...para('--', r'The name rules are those of cargo and the egui flow: rust_new.name accepts hyphens and keeps the name as typed, applies the same rules through a shared function, and does not carry the egui template own restrictions (the template dependency names are only forbidden for egui projects). The library flow shows the crate identifier (hyphens turned into underscores) only when it differs from the name. This is why the spec requires egui_new at the top: both are tested against the same function.'),
    ...sec(r'editing manifests as text'),
    ...para('--', r'A workspace has a root Cargo.toml and members that inherit version and edition. The edition is read from the Cargo.toml of a generated project, [package] only. The resolver is 3 from edition 2024 on, else 2. inherit rewrites cargo own output: version.workspace = true and edition.workspace = true, nothing else, and it works on the text the installed cargo really writes, so a change in cargo output would be noticed. The key list, the section limit, comments and CRLF are all kept.'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 259-261', r'''
  it("rewrites version and edition of cargo's own output, nothing else", function()
    H.eq('[package]\nname = "my-app"\nversion.workspace = true\nedition.workspace = true\n\n[dependencies]\n', R.inherit(SAMPLE))
  end)'''),
    ...para('--', r'Adding a member to the members list is the delicate part: a glob list needs no edit; a one-line list gets a new entry; a multi-line list keeps indent, comma and comments; an entry that already covers the path means no change; only the [workspace] table list is touched; the comma goes after the last entry of a line holding several; an empty list keeps its comment; CRLF is kept; and a manifest without a members list is refused. A new workspace that would nest inside the members of another workspace or inside a git work tree gets a warning.'),
    ...sec(r'the real cargo'),
    ...para('--', r'The create_project tests run the actual cargo new in a temp directory. A binary has src/main.rs and no lib.rs, a repository, the hyphen name kept, and cargo check --offline returns 0. The edition is the one the installed cargo reports and never a fixed one, so the test passes on every cargo version. Parent directories are created.'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 404-416', r'''
  it("a binary: cargo new --bin with a git repository, hyphens kept", function()
    local parent = H.tmpdir()
    local err, info = wait_cb(function(cb)
      R.create_project({ name = "my-app", parent = parent, kind = "binary" }, cb)
    end)
    H.is_nil(err)
    H.eq(parent .. "/my-app", info.dir)
    H.ok(vim.uv.fs_stat(parent .. "/my-app/src/main.rs"))
    H.is_nil(vim.uv.fs_stat(parent .. "/my-app/src/lib.rs"))
    H.ok(vim.uv.fs_stat(parent .. "/my-app/.git"), "a repository exists")
    H.has(read(parent .. "/my-app/Cargo.toml"), 'name = "my-app"')
    H.eq(0, run({ "cargo", "check", "--offline" }, parent .. "/my-app").code)
  end)'''),
    ...para('--', r'For a workspace, the test requires the exact layout: crates/my-ws-app/src/main.rs, a top manifest equal to what workspace_toml produces for the edition cargo reports, the resolver in the info, a .gitignore that is exactly /target, member manifests that inherit version and edition, a git repository in the root only, branch main, and no commit. cargo metadata must list the members and cargo check must pass with a binary and a library. The edition for the resolver is asked from cargo once per session, tested with a stub that counts probes.'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 458-478', r'''
  it("builds the layout with a binary member and inherited version / edition", function()
    local parent = H.tmpdir()
    local err, info = ws(parent, "my-ws", "binary", "my-ws-app")
    H.is_nil(err)
    local root = parent .. "/my-ws"
    H.eq(root, info.dir)
    H.eq(root .. "/crates/my-ws-app/src/main.rs", info.file)
    local top = read(root .. "/Cargo.toml")
    local edition = R.parse_edition(real_cargo_toml("--bin"))
    H.eq(R.workspace_toml(edition), top)
    H.eq(R.resolver(edition), info.resolver)
    H.eq("/target\n", read(root .. "/.gitignore"))
    H.eq(
      '[package]\nname = "my-ws-app"\nversion.workspace = true\nedition.workspace = true\n\n[dependencies]\n',
      read(root .. "/crates/my-ws-app/Cargo.toml")
    )
    H.ok(vim.uv.fs_stat(root .. "/.git"), "git init")
    H.is_nil(vim.uv.fs_stat(root .. "/crates/my-ws-app/.git"), "no repository inside the member")
    H.eq("main", vim.trim(run({ "git", "symbolic-ref", "--short", "HEAD" }, root).stdout))
    H.eq("", vim.trim(run({ "git", "log", "--oneline" }, root).stdout), "no commit")
  end)'''),
    ...sec(r'failures leave nothing behind'),
    ...para('--', r'This is the most important group. An existing target is refused and left alone. An invalid name or kind never reaches cargo. With an empty PATH, create_project, create_workspace and create_member all return cargo not found, and the parent directory is still empty, even though the test asked for parent paths that did not exist. When cargo fails, the first stderr line is shown and no directory is left; a workspace whose member step fails removes the whole workspace. In the test, a stub cargo executes the real cargo for the probe call and fails everything else with error: member step failed. A read-only parent gives an error and nothing is left behind.'),
    ...code('lua', r'tests/rust-new_spec.lua · lines 683-731', r'''
  it("cargo missing: a clear error and nothing created, parents included", function()
    local parent = H.tmpdir()
    local empty = H.tmpdir()
    vim.env.PATH = empty
    for _, f in ipairs({
      function(cb)
        R.create_project({ name = "a", parent = parent .. "/p/q", kind = "binary" }, cb)
      end,
      function(cb)
        R.create_workspace({ name = "a", parent = parent .. "/p/q", kind = "binary", member = "m" }, cb)
      end,
      function(cb)
        R.create_member({ root = parent, kind = "binary", name = "m" }, cb)
      end,
    }) do
      local err = wait_cb(f)
      H.eq("cargo not found", err)
    end
    H.eq({}, vim.fn.readdir(parent))
  end)

  it("cargo failing: its first stderr line, no directory left (project, workspace)", function()
    local parent = H.tmpdir()
    stub_cargo('echo "error: the stub says no" >&2\necho "second line" >&2\nexit 101')
    local err = wait_cb(function(cb)
      R.create_project({ name = "boom", parent = parent .. "/new/dir", kind = "binary" }, cb)
    end)
    H.eq("cargo new failed: error: the stub says no", err)
    H.eq({}, vim.fn.readdir(parent))
    -- the edition probe is the first cargo call of a workspace
    R.reset_edition()
    err = wait_cb(function(cb)
      R.create_workspace({ name = "boom", parent = parent .. "/new/dir", kind = "binary", member = "m" }, cb)
    end)
    H.match(err, "error: the stub says no", true)
    H.eq({}, vim.fn.readdir(parent))
  end)

  it("a workspace whose member step fails leaves no directory behind", function()
    need_cargo()
    local real = vim.fn.exepath("cargo")
    local parent = H.tmpdir()
    stub_cargo(('case "$*" in *probe*) exec "%s" "$@";; esac\necho "error: member step failed" >&2\nexit 101'):format(real))
    local err = wait_cb(function(cb)
      R.create_workspace({ name = "half", parent = parent .. "/x/y", kind = "library", member = "half-core" }, cb)
    end)
    H.match(err, "error: member step failed", true)
    H.eq({}, vim.fn.readdir(parent))
  end)'''),
    ...sec(r'members of an existing workspace'),
    ...para('--', r'create_member with glob members does not edit the manifest and the member inherits; with an explicit list the path is added once with formatting kept, and a [workspace.package] without an edition is respected; a name that collides with an existing member (hyphen or underscore) or a taken directory is rejected; a manifest without a members list is refused and the manifest is restored when cargo fails.'),
    ...sec(r'prompts'),
    ...para('--', r'The four commands exist with an optional name. For a binary: name, parent (default vim.g.xynovim_projects_dir, else ~/projects when it exists, else the cwd), cargo new, change directory, open main.rs, show the next steps. An invalid argument re-prompts with the reason; an existing target and a file as a parent re-prompt; a missing parent is created only after asking and No creates nothing; cancelling any prompt aborts silently and leaves nothing; the workspace flow asks the kind first and then prefills the member name with -app or -core; a progress notification is shown while cargo runs, so the editor does not freeze; :RustNewMember finds the workspace from the current buffer and refuses elsewhere; and a second command while one runs is refused.'),
    ...sec(r'the dashboard in tmux'),
    ...para('--', r'Three entries New Rust Binary, Library and Workspace have unique keys and distinct icons, sit in order before the egui entry and Quit, and the layout thresholds follow the number of entries. Then a table of window sizes: every entry and key must be on screen at each, and pressing each key at 80x24 opens the right prompt. This is rendered in a real terminal in tmux, because the dashboard layout depends on terminal size and not on any API.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'd163480 (2026-10-16)', r'created with the entries. e166947 (2026-10-16) :: review fixes.'),
    ...pt('--', r'ff1c8fa (2026-10-16)', r'Linux and macOS header. cd602fd (2026-10-21) :: "BSD-safe sed stub".'),
  ],
);
