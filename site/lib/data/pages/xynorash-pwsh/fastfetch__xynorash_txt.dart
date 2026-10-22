import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynorash-pwsh/fastfetch/xynorash.txt',
  lines: [
    cm('#', '──────────────────────────────────────────'),
    cm('#', r'fastfetch/xynorash.txt — the mark'),
    cm('#', r'thirty-two rows of coloured text'),
    cm('#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'the ASCII-art logo printed beside the system facts'),
    kv(r'format', r'plain text with 24-bit ANSI colour escapes'),
    kv(r'size', r'32 lines, 13,087 bytes, 479 escape characters'),
    kv(r'used by', r'fastfetch/config.jsonc, logo type raw'),
    kv(r'history', r'1 commit, never changed'),
    ...sec(r'why this file exists'),
    ...para('#', r'A banner needs a picture. This one is not a distribution logo but the project’s own mark, drawn in ASCII characters and coloured with escape codes, then stored as a plain text file that fastfetch prints verbatim. fastfetch/config.jsonc points at it with type raw and source xynorash.txt and declares its size as 150 by 32. The file has exactly 32 lines and 13,087 bytes, 479 of which are escape characters, so the declared height is the real height.'),
    ...sec(r'how it is built'),
    ...para('#', r'Each line is a row of characters from a small set: space, dots, colons, equals signs, hyphens, plus signs, asterisks and the hash mark, which is the usual way to turn an image into text by mapping brightness to character density. The colour comes from SGR escape codes of the form ESC [ 38;2;R;G;B m, the 24-bit foreground. The file changes colour in three zones, and the zones are the design.'),
    ...pt('#', r'rows 1 to 11', r'a single cyan, 0,229,255 (the prompt’s #00E5FF), set once at the start of each row.'),
    ...pt('#', r'rows 12 to 18', r'an escape before every single character, in two steps of blue (0,220,255 and 0,175,255). Colour per character is the expensive way to draw: it gives the middle band a gradient across a row, at the cost of making each row several times longer than its visible text.'),
    ...pt('#', r'rows 19 to 32', r'one escape at the start of each row, and the colour changes from row to row: 50,0,210 at row 19, passing through 170,0,255 (the prompt’s violet #AA00FF) at row 25, to 238,0,238 (magenta #EE00EE) at rows 31 and 32. This is the vertical gradient from blue-violet at the top of the lower half to magenta at the bottom.'),
    ...para('#', r'The three zones use exactly the cyan, violet and magenta of the theme and the profile, so the logo, the prompt and the syntax colours agree without any shared definition: the numbers are simply repeated.'),
    ...sec(r'why the file is not shown here'),
    ...para('#', r'The escape bytes are not printable, so a faithful excerpt of the file would be a page of unreadable control characters. This page therefore describes the file by its measured structure instead of copying lines from it. The measurements above (32 lines, 13,087 bytes, 479 ESC characters, the colour triples quoted) were taken from the file itself.'),
    ...sec(r'edge cases and trade-offs'),
    ...pt('#', r'width', r'the art is drawn on a wide canvas; most rows are padded with spaces on the left, so the visible shape is around the middle of a 150-column field. A narrower terminal will wrap it.'),
    ...pt('#', r'colour support', r'24-bit escapes need a terminal that supports them; Windows Terminal does, which is the terminal the project installs a font for.'),
    ...pt('#', r'editing', r'the file is awkward to edit by hand because of the per-character escapes in rows 12 to 18; regenerating it from an image would be easier than patching it, and the repository does not contain a generator.'),
    ...sec(r'history'),
    ...para('#', r'One commit: 3690dee, 2026-06-07 23:48, init: core XYNORASH configuration, 32 lines. Unchanged since.'),
  ],
);
