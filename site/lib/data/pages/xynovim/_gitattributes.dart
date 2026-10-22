import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/.gitattributes',
  lines: [
    cm(r'#', '──────────────────────────────────────────'),
    cm(r'#', r'.gitattributes'),
    cm(r'#', r'LF everywhere'),
    cm(r'#', r'so a Windows checkout does not change the bytes the lockfile and scripts depend on'),
    cm(r'#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'line-ending policy for the whole repository'),
    kv(r'language', r'gitattributes'),
    kv(r'size', r'2 lines, one commit (ff1c8fa, 2026-10-16)'),
    ...sec(r'the whole file'),
    ...code('toml', r'.gitattributes · lines 1-2', r'''
* text=auto eol=lf
*.ps1 text eol=lf
'''),
    ...sec(r'why this file exists'),
    ...para(r'#', r'The repository was written on Linux and was then made to run on Windows and macOS in the portability commit ff1c8fa on 2026-10-16, the commit that added this file. The risk on Windows is git’s core.autocrlf: when it is true, git converts text files to CRLF on checkout (scripts/bootstrap.ps1 names exactly this risk in a comment). That would change the bytes of shell scripts and of the lockfile, which the bootstrap compares.'),
    blank,
    ...pt(r'#', r'* text=auto eol=lf', r'git decides per file whether it is text; text files get LF on checkout on every platform. per git’s documentation, as I recall it, the eol attribute takes priority over core.autocrlf.'),
    ...pt(r'#', r'*.ps1 text eol=lf', r'forces the PowerShell scripts to be text with LF, even though a previous rule covers them. It is redundant with the first line as far as the matching goes, and spells out that scripts like bootstrap.ps1 are meant to be LF.'),
    ...sec(r'how this relates to the bootstrap'),
    ...para(r'#', r'scripts/bootstrap.ps1 compares lazy-lock.json by hash because, as its comment says, core.autocrlf=true can rewrite the line endings of the checkout. With these attributes in place that should not happen for files in this repository, so the hash comparison and the attribute file are two layers for the same problem: one prevents the change, the other makes the check robust if it happens anyway. The second layer is an observation from reading both files; no comment states it.'),
    blank,
    ...sec(r'what text=auto does to the binary files'),
    ...para(r'#', r'The repository tracks 363 files, and 116 of them are PNG, MP4 and GIF files (the screenshots and recordings in docs/media and the share cards in site/assets). text=auto lets git look at the content and decide: a file with binary content is left alone, and only real text is normalised. That is why the first line can be a wildcard without a list of exceptions for media. The 115 Lua files, the shell and PowerShell scripts, the JSON, TOML and Markdown are text, and they all get LF.'),
    blank,
    ...sec(r'why the PowerShell scripts get a line of their own'),
    ...para(r'#', r'The second rule names *.ps1 although the first already matches it. The effect of the line is documentary: it lists the one file type that a Windows user would expect to be CRLF, and says it is not. The scripts that matter are scripts/bootstrap.ps1 and scripts/test.ps1, and both are pure ASCII (a search for non-ASCII bytes in scripts/*.ps1 finds nothing). That is consistent with the way they are written. PowerShell 5.1 reads a file without a byte order mark as the system code page, so keeping to ASCII avoids a class of mojibake; LF line endings are fine for it. The files do not state this reasoning, it is what the content allows.'),
    blank,
    ...sec(r'what it does not do'),
    ...pt(r'#', r'no export-ignore, no linguist', r'the file does not touch archives or the language statistics on GitHub. It is only about line endings.'),
    ...pt(r'#', r'no per-extension lists', r'the policy is whole-repository, so a new file type needs no edit here.'),
    ...pt(r'#', r'no enforcement', r'a contributor with a different editor setting can still save CRLF; git normalises it on add (text=auto) and the checkout writes LF again.'),
    ...sec(r'history'),
    ...pt(r'#', r'ff1c8fa 2026-10-16', r'Windows and macOS: portability fixes, PowerShell bootstrap, portable test runner, OS-aware skips, platforms workflow.'),
  ],
);
