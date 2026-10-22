import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/snippets/rust.json',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'snippets/rust.json — seven snippets, each one earned'),
    cm('//', r'the VS Code snippet format, read by blink.cmp'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'user snippets for Rust buffers'),
    kv(r'language', r'JSON in the VS Code snippet format (no comments allowed)'),
    kv(r'size', r'37 lines, 7 snippets, 2 commits (2026-10-09, 2026-10-13)'),
    kv(r'prefixes', r'testmod, testfn, ttest, tmain, impldisp, implfrom, dcommon'),
    kv(r'tested by', r'tests/snippets-completion-injections_spec.lua'),
    ...sec(r'why this file exists'),
    ...para('//', r'rust-analyzer already offers snippets, and LazyVim brings friendly-snippets, a large collection. This file is the small set that the author wanted to be sure about: the test module, the test function, the Tokio variants, and three bits of trait implementation boilerplate. JSON has no comments, so the reasoning lives in the commit history and in the spec, and this page collects it.'),
    ...para('//', r'The format is the one VS Code made common. The file is an object; each key is a snippet name (shown in the completion menu), and each value has a prefix, which is what you type, a body, the text to insert, and a description. The body is an array of lines, which keeps the JSON readable, and Neovim joins them with newlines when it expands the snippet. Tabs are written as \t escapes, so the snippets indent with tabs, as rustfmt’s default would after formatting.'),
    ...sec(r'how it is found'),
    ...para('//', r'blink.cmp has a snippets source that loads files from stdpath("config")/snippets by default. This file therefore needs no registration, and the spec asserts exactly that: the config copy exists, and no snippets.search_paths option is set, neither at top level nor in the provider’s options. A test also loads the real blink registry and checks that it finds snippets/rust.json. The file is named after the filetype, so the snippets appear only in Rust buffers.'),
    ...sec(r'tests as scaffolding'),
    ...code('json', r'snippets/rust.json · lines 1-11', r'''
{
  "Test module": {
    "prefix": "testmod",
    "body": ["#[cfg(test)]", "mod tests {", "\tuse super::*;", "", "\t#[test]", "\tfn ${1:it_works}() {", "\t\t$0", "\t}", "}"],
    "description": "#[cfg(test)] mod tests"
  },
  "Test fn": {
    "prefix": "testfn",
    "body": ["#[test]", "fn ${1:name}() {", "\t$0", "}"],
    "description": "#[test] fn"
  },'''),
    ...para('//', r'The body syntax is the LSP snippet grammar. ${1:it_works} is a tab stop with a default text: the cursor lands there first, with "it_works" selected so typing replaces it. $0 is the final cursor position, reached after the last tab. The test module snippet is the standard Rust idiom: a cfg(test) module named tests that imports the parent’s items with use super::*, with one test inside. The empty string in the array is a blank line.'),
    ...para('//', r'The prefixes tell a story. In the first commit (b64aa27, 2026-10-09, "wip-s7a") they were tmod and tfn. On 2026-10-13, commit a3d33c8 renamed them to testmod and testfn. The spec explains why, in the name of the test: it "offers testmod (not tmod: rust-analyzer’s own tmod outranked ours)". rust-analyzer offers a completion of its own called tmod, and in the blink menu it outranked this snippet. The author chose different words over fighting the ranking. The same test checks the other direction too: that ttest is offered and expands into the Tokio test snippet.'),
    ...sec(r'tokio'),
    ...code('json', r'snippets/rust.json · lines 12-21', r'''
  "Tokio test": {
    "prefix": "ttest",
    "body": ["#[tokio::test]", "async fn ${1:name}() {", "\t$0", "}"],
    "description": "#[tokio::test] async fn"
  },
  "Tokio main": {
    "prefix": "tmain",
    "body": ["#[tokio::main]", "async fn main() -> ${1:anyhow::Result<()>} {", "\t$0", "\tOk(())", "}"],
    "description": "#[tokio::main] async fn main"
  },'''),
    ...para('//', r'Two small decisions are visible. First, the return type of main is a placeholder with a default, ${1:anyhow::Result<()>}, so the common case needs no typing and an alternative like std::io::Result<()> is one keystroke away from being replaced. Second, the body puts the final cursor ($0) before the closing Ok(()), so you land inside the function at the point where your code goes, and the tail expression that makes the type check is already there.'),
    ...sec(r'trait boilerplate'),
    ...code('json', r'snippets/rust.json · lines 22-37', r'''
  "impl Display": {
    "prefix": "impldisp",
    "body": ["impl std::fmt::Display for ${1:Type} {", "\tfn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {", "\t\twrite!(f, \"${2}\")$0", "\t}", "}"],
    "description": "impl Display"
  },
  "impl From": {
    "prefix": "implfrom",
    "body": ["impl From<${1:Source}> for ${2:Target} {", "\tfn from(value: ${1:Source}) -> Self {", "\t\t$0", "\t}", "}"],
    "description": "impl From"
  },
  "Derive common": {
    "prefix": "dcommon",
    "body": ["#[derive(Debug, Clone, PartialEq, Eq)]"],
    "description": "derive Debug, Clone, PartialEq, Eq"
  }
}'''),
    ...para('//', r'impl Display uses fully qualified paths (std::fmt::Display, std::fmt::Formatter, std::fmt::Result) so the snippet works in a file with no imports, and the anonymous lifetime in Formatter<’_> is the form rust-analyzer would write. The write! call has its own tab stop, ${2}, inside an escaped pair of quotes (\" in the JSON), so the second Tab puts the cursor in the format string. Placing $0 after the closing parenthesis means the third Tab leaves the snippet at the end of the statement.'),
    ...para('//', r'impl From mentions ${1:Source} twice. In the LSP snippet grammar a repeated tab stop number is a mirror: editing one occurrence edits the other, so the type you write for the source appears in both the generic argument and the parameter. The target type is stop 2. The snippet ends with $0 inside the body, ready for the conversion.'),
    ...para('//', r'The last snippet is the simplest: one line, no tab stops. dcommon inserts the derive set Debug, Clone, PartialEq, Eq, which is the usual minimum for a plain data type. It exists because typing the derive list is the most repeated thing in Rust.'),
    ...sec(r'what the spec verifies'),
    ...pt('//', r'shape', r'the file decodes as JSON with exactly seven snippets, each with a prefix, a body that is an array and a description. A table in the spec maps each name to its prefix (Test module to testmod, Tokio test to ttest, and so on).'),
    ...pt('//', r'bodies', r'a test compares the documented bodies.'),
    ...pt('//', r'expansion', r'every body is expanded with vim.snippet.expand, the same engine that blink uses, with the defaults filled in. A malformed placeholder such as a missing brace would throw, so this catches typos that a JSON validator cannot.'),
    ...pt('//', r'in the menu', r'a real blink menu is opened in a Rust buffer for the prefixes, and the spec checks that testmod is offered from the snippets source and that ttest expands into a session with active placeholder jumps.'),
    ...pt('//', r'guard', r'the spec’s block ux.snippets_allowed documents the other half of the feature: snippets are suppressed after a dot, inside strings and comments, and in expression positions such as call arguments, so these snippets do not pop up while you are typing something else. That guard is in lua/config/ux.lua, not in this file.'),
    ...sec(r'edge cases'),
    ...pt('//', r'tabs in JSON', r'the \t sequences are JSON escapes, decoded by the parser, so the inserted text contains real tab characters. If the buffer uses spaces, Neovim does not convert them on insertion; formatting on save (rustfmt) is what normalises.'),
    ...pt('//', r'no comments', r'standard JSON does not allow them, so explanations have to stay outside the file. This page is where they live.'),
    ...pt('//', r'name collisions', r'the key of each object is its display name. Two snippets with the same key would silently collapse to one in JSON; the spec’s exact count of seven would catch it.'),
    ...sec(r'history'),
    ...pt('//', r'b64aa27 (2026-10-09)', r'"wip-s7a". The file is created with the first set, using the short prefixes tmod and tfn.'),
    ...pt('//', r'a3d33c8 (2026-10-13)', r'"Final loop round 2: ... snippet prefixes ...". tmod and tfn become testmod and testfn, because the language server’s own tmod outranked the snippet in the menu.'),
  ],
);
