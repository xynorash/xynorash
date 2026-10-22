import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/tests/fixtures/deps-lab/Cargo.toml',
  lines: [
    cm('--', '──────────────────────────────────────────'),
    cm('--', r'tests/fixtures/deps-lab/Cargo.toml — one small crate that stands for every real project'),
    cm('--', r'six dependencies chosen because most of them bring a different kind of macro, and two siblings that differ by one line'),
    cm('--', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the manifest of the main fixture crate of the macros-and-dependencies specs'),
    kv(r'language', r'TOML, 12 lines, edition 2024'),
    kv(r'siblings', r'deps-lab-nofeature (serde without the derive feature) and no-deps-lab (no dependencies at all)'),
    kv(r'used by', r'9 spec files, among them crate-meta, crate-features, macro-attrs, import-engine, deps-freshness and macros-deps-flows'),
    kv(r'history', r'one commit, 6e1b567 (2026-10-14, "Macros and deps: foundation modules (crate_meta, code_actions) and fixtures")'),
    ...sec(r'why this file exists'),
    ...para('--', r'Fixtures in this repository come in two kinds. The first kind (for example basic, workspace, broken, standalone.rs, sql_and_routes.rs) is built for the general behaviour of the editor. The second kind, deps-lab and its siblings, exists for one feature set: dependencies and macros. Features such as the missing-feature fix, attribute argument completion, the import engine and dependency freshness need a crate that really depends on the crates that make those features interesting. A hand-made metadata table would test the code against its own assumptions; a real Cargo project tests it against what cargo says. So the fixture is a real crate with a real Cargo.lock, small enough to be read in a minute.'),
    ...code('toml', r'tests/fixtures/deps-lab/Cargo.toml · lines 1-12', r'''
[package]
name = "deps-lab"
version = "0.1.0"
edition = "2024"

[dependencies]
anyhow = "1"
clap = { version = "4", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "2"
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }'''),
    ...sec(r'why these six dependencies'),
    ...para('--', r'The manifest lists anyhow, clap, serde, serde_json, thiserror and tokio. The specs name a reason for each.'),
    blank,
    ...pt('--', r'serde, with derive', r'the standard case of a derive macro with helper attributes (rename_all, rename, default). It is the crate for macro_attrs completion, for the missing-feature fix (the derive feature gates Serialize and Deserialize) and for the check that schema helpers are declared by the real proc-macro crate (serde_derive).'),
    ...pt('--', r'clap, with derive', r'a second derive family with several helper attributes (command, arg, value, group) and a Parser derive. The macro_attrs table of cases has ten cases whose title starts with clap.'),
    ...pt('--', r'thiserror', r'the error derive with its error and from helpers, whose positional message sorts first in the completion. It is also the crate that import_engine ranks first inside #[derive( for the name Error.'),
    ...pt('--', r'tokio, with macros and rt-multi-thread', r'an attribute macro (#[tokio::main]) instead of a derive, and a crate whose items are gated behind a chain of features (the scanner test of crate_features uses tokio-shaped cfg_macros! and cfg_rt! wrappers).'),
    ...pt('--', r'anyhow and serde_json', r'ordinary libraries that make the manifest realistic and the import engine’s choices real: anyhow::Error, std::io::Error and thiserror::Error all compete for the name Error. serde_json is one of the six names that crate_meta must report as a dependency when asked for known path heads (crate-meta_spec.lua, line 658).'),
    ...para('--', r'Those reasons are read from the specs, not from the file: the manifest itself contains no comments.'),
    ...sec(r'the code that goes with it'),
    ...para('--', r'The manifest is half of the fixture. src/main.rs has exactly what the specs look for: a thiserror enum with an error message, a serde struct with rename_all and field attributes, a clap Parser struct with command and arg attributes, a tokio main, and a Result using anyhow. Specs find lines in it by content, for example the line #[derive(Debug, Serialize, Deserialize)] and the line with Ok(()), so the file is a contract with them.'),
    ...code('rust', r'tests/fixtures/deps-lab/src/main.rs · lines 1-30', r'''
use clap::Parser;
use serde::{Deserialize, Serialize};

#[derive(Debug, thiserror::Error)]
enum LabError {
    #[error("bad input: {0}")]
    Bad(String),
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Item {
    #[serde(rename = "itemId", default)]
    item_id: u32,
    name: String,
}

#[derive(Parser, Debug)]
#[command(name = "deps-lab", version)]
struct Cli {
    #[arg(short, long)]
    name: Option<String>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    let item = Item { item_id: 1, name: cli.name.unwrap_or_default() };
    if item.name == "bad" {
        return Err(LabError::Bad(item.name).into());'''),
    ...sec(r'the two siblings'),
    ...para('--', r'deps-lab-nofeature is the same crate with two differences: the package name and serde = "1" without the derive feature. A diff of the two manifests shows exactly those two lines. It makes the compile error cannot find derive macro Serialize real, and crate-features_spec.lua applies the fix on a copy and requires cargo check to pass, and that the clap line stays untouched. no-deps-lab has no dependencies and a main.rs whose first line says so on purpose: the name below is unresolved until a crate is added. It is the start of the Uuid journey in crate-import_spec.lua and macros-deps-flows_spec.lua.'),
    ...code('rust', r'tests/fixtures/no-deps-lab/src/main.rs · lines 1-5', r'''
// no dependencies on purpose: the name below is unresolved until a crate is added
fn main() {
    let id = Uuid::nil();
    println!("{id}");
}'''),
    ...sec(r'strategy: copy, never edit'),
    ...para('--', r'No spec opens the committed fixture. H.fixture copies it into a private temp directory (cp -a on Linux, a recursive copy elsewhere), and optionally makes it a git repository, so tests can edit Cargo.toml, run cargo add and write files freely. The .gitignore of the repository ignores tests/fixtures/**/target/ and the rustc info file, so a debug run that built a fixture in place cannot be committed by accident. The history of the repository shows that this has happened with another fixture: the keymaps-rust-crate fixture had build artifacts removed in 670058d (2026-10-13) and cfe8c06 (2026-10-14).'),
    ...sec(r'strategy: the registry decides, and skips say so'),
    ...para('--', r'cargo metadata needs the dependency sources. The specs call it with --offline against the deps-lab copies, and when the local registry lacks the crates, they skip with a message that begins registry lacks the deps-lab crates offline and gives the first characters of cargo’s error (see crate-meta_spec.lua line 225). On a machine that built the fixture once, or whose cargo registry has the crates, the full set of tests runs. The Cargo.lock is committed (35 packages), so the versions are the same everywhere that resolves them, and cargo check --offline in the flows does not need the network after the first fetch.'),
    ...code('toml', r'tests/fixtures/deps-lab/Cargo.toml · lines 1-12', r'''
[package]
name = "deps-lab"
version = "0.1.0"
edition = "2024"

[dependencies]
anyhow = "1"
clap = { version = "4", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "2"
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }'''),
    ...sec(r'strategy: pure layers first'),
    ...para('--', r'The fixture is used only at the top of each spec. Below it sit the layers that need no crate: path-only temp workspaces written by the spec itself (cargo metadata needs no registry for path dependencies), fake LSP clients, and a fake curl for the crates.io client. That is why most of the macros and dependencies suite runs on any machine, and only the acceptance tests, the live rust-analyzer tests and the flows need deps-lab.'),
    ...sec(r'edition 2024'),
    ...para('--', r'The manifest says edition = "2024". The same edition is in no-deps-lab. The rust-new_spec.lua spec stresses the opposite principle for generated projects (the edition of the installed cargo, never a fixed one), but a fixture is a stable input, so it pins its own. With edition 2024, the resolver is 3 for a workspace (see the editions test in rust-new_spec.lua). The fixture needs a cargo recent enough to read the edition, and crate-meta_spec.lua asserts that metadata reports the edition 2024 for it.'),
    ...sec(r'history'),
    blank,
    ...pt('--', r'6e1b567 (2026-10-14)', r'the fixture and the foundation modules it tests (crate_meta and code_actions) arrived together.'),
    ...pt('--', r'6e1b567 (2026-10-14)', r'deps-lab-nofeature was added by the same commit as deps-lab.'),
    ...pt('--', r'b9363cd (2026-10-14)', r'no-deps-lab was added, together with the specs that used the fixtures (dependency freshness, crate add, missing-feature fix, attribute and derive completion, import engine).'),
  ],
);
