import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/scripts/make-share-images.sh',
  lines: [
    cm(r'#', '──────────────────────────────────────────'),
    cm(r'#', r'scripts/make-share-images.sh'),
    cm(r'#', r'the social cards, regenerated from a palette and a screenshot'),
    cm(r'#', r'one ImageMagick function, nine images'),
    cm(r'#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'generates the Open Graph and social-preview PNGs'),
    kv(r'language', r'bash with ImageMagick (magick)'),
    kv(r'size', r'60 lines, two commits (ca84675, e6ad339, both 2026-10-22)'),
    kv(r'outputs', r'og.png, social-preview.png, og-plugins.png, og/<slug>.png for each of six guides'),
    ...sec(r'why this file exists'),
    ...para(r'#', r'When someone pastes a link to the site into a chat or a social network, the preview image comes from the Open Graph tags of that page. The script gives each page its own card. It builds those images from three things that already exist in the repository: the Island Dark palette, a screenshot from docs/media and the title of the page. Because the PNGs are committed, it only has to be run when a card changes, and a person who does not have ImageMagick can still build the site.'),
    blank,
    ...code('bash', r'scripts/make-share-images.sh · lines 1-18', r'''
#!/usr/bin/env bash
# Regenerate the share images with ImageMagick (the Island Dark palette from
# lua/island/palette.lua, DejaVu fonts, a screenshot from docs/media):
#
#   site/assets/og.png              1200x630 card of the home page
#   site/assets/og/<slug>.png       1200x630 card of each guide
#   site/assets/og-plugins.png      1200x630 card of the plugins page (the nine names, no screenshot)
#   site/assets/social-preview.png  1280x640 GitHub social preview (upload it by hand:
#                                   Settings > Social preview; GitHub has no API for it)
#
# Usage: scripts/make-share-images.sh      (needs `magick`; the PNGs are committed)
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
command -v magick >/dev/null || { echo "make-share-images: ImageMagick (magick) is missing" >&2; exit 2; }

BG='#1e1f22' PANEL='#2b2d30' BORDER='#393b40' TITLE='#e6e8ec' MUTED='#9da0a8' BLUE='#56a8f5' GREEN='#6aab73'
BOLD=DejaVu-Sans-Bold SANS=DejaVu-Sans MONO=DejaVu-Sans-Mono-Bold
'''),
    ...para(r'#', r'The header names every output with its size. The GitHub social preview (1280 by 640) is mentioned with a plain warning that it has to be uploaded by hand under Settings, Social preview, because GitHub has no API for it. The script stops with exit 2 when magick is missing. The colours are the Island Dark values given as constants: BG, PANEL, BORDER, TITLE, MUTED, BLUE and GREEN. The comment points to lua/island/palette.lua as their source.'),
    blank,
    ...sec(r'the card function'),
    ...code('bash', r'scripts/make-share-images.sh · lines 20-34', r'''
# card OUT WIDTH HEIGHT KICKER TITLE SUBTITLE SHOT [TITLE_SIZE_PERMILLE_OF_WIDTH]
card() {
  local out=$1 w=$2 h=$3 kicker=$4 title=$5 sub=$6 shot=$7 tsize=${8:-46}
  local tw=$((w - 144)) shotw=$((w * 8 / 10))
  mkdir -p "$(dirname "$out")"
  magick -size "${w}x${h}" "xc:$BG" \
    \( "$shot" -resize "${shotw}x" -bordercolor "$BORDER" -border 2 \) -gravity north -geometry "+0+$((h * 52 / 100))" -composite \
    \( -size "${w}x$((h * 52 / 100))" "xc:$BG" \) -gravity north -composite \
    \( -size "${tw}x40" -background none -fill "$BLUE" -font "$MONO" -pointsize 28 -gravity west caption:"$kicker" \) -gravity northwest -geometry "+72+$((h * 6 / 100))" -composite \
    \( -size "${tw}x$((h * 22 / 100))" -background none -fill "$TITLE" -font "$BOLD" -pointsize $((w * tsize / 1000)) -gravity northwest caption:"$title" \) -gravity northwest -geometry "+72+$((h * 16 / 100))" -composite \
    \( -size "${tw}x40" -background none -fill "$MUTED" -font "$SANS" -pointsize 27 -gravity west caption:"$sub" \) -gravity northwest -geometry "+72+$((h * 40 / 100))" -composite \
    \( -size "$((w / 3))x36" -background none -fill "$GREEN" -font "$MONO" -pointsize 22 -gravity east caption:"xynorash.github.io/xynovim" \) -gravity northeast -geometry "+72+$((h * 8 / 100))" -composite \
    -colors 128 -depth 8 "PNG8:$out"
  echo "$out $(identify -format '%wx%h' "$out") $(stat -c %s "$out") bytes"
}
'''),
    ...para(r'#', r'Everything is composed in one magick command. The geometry is expressed as fractions of the width and height, so the same function makes a 1200 by 630 card and a 1280 by 640 one. In order: a canvas filled with the background; the screenshot, resized to 80 percent of the width with a border, placed at 52 percent of the height; a block of background colour over the upper part, where the text goes; then four text layers made with caption, which wraps within a given width. They are the kicker in blue, the title in bold at a point size that is a thousandth part of the width (the optional last argument), the subtitle in the muted colour, and the site address in green in the top right.'),
    blank,
    ...para(r'#', r'The result is quantised to 128 colours and 8 bits and written as PNG8. The script does not say why; the effect is a palette image, which keeps flat colours and text small (the function prints each file’s size). The function prints the path, the dimensions and the size in bytes of each image, as a record that the run happened.'),
    blank,
    ...sec(r'the cards'),
    ...code('bash', r'scripts/make-share-images.sh · lines 36-50', r'''
TAG="A personal Neovim configuration for Rust"
card site/assets/og.png 1200 630 "Neovim, Rust, LazyVim" "xynovim" "$TAG" docs/media/01-hero.png 100
card site/assets/social-preview.png 1280 640 "Neovim, Rust, LazyVim" "xynovim" "$TAG" docs/media/01-hero.png 100

# slug | title | subtitle | screenshot
while IFS='|' read -r slug title sub shot; do
  card "site/assets/og/$slug.png" 1200 630 "xynovim guide" "$title" "$sub" "docs/media/$shot"
done <<'LIST'
neovim-rust-diagnostics|Instant Rust diagnostics in Neovim|rust-analyzer while you type, clippy half a second later|02-diagnostics-clippy.png
neovim-rust-debugging|Debugging Rust in Neovim|nvim-dap and codelldb, with Rust-aware variable views|06-debug-stopped.png
neovim-rust-tests-coverage|Rust tests and coverage in Neovim|neotest, cargo-nextest and coverage in the gutter|05-tests-coverage.png
neovim-cargo-workspaces|Cargo workspaces, features and crates in Neovim|New projects, :CrateAdd and :CrateFeatures|15-rust-new-workspace-tree.png
neovim-git-local-history|A git safety net for Neovim|Local History as git refs, lazygit and diffview|08-git-local-history.png
neovim-island-dark-theme|The Island Dark colour scheme for Neovim|A dark palette for Rust, Treesitter and LSP tokens|09-theme-completion.png
LIST
'''),
    ...para(r'#', r'The home page and the social preview use the hero screenshot. For the guides, a loop reads a here-document with the pipe character as the separator, so adding a guide is adding one line: slug, title, subtitle and screenshot. The six guides are neovim-rust-diagnostics, neovim-rust-debugging, neovim-rust-tests-coverage, neovim-cargo-workspaces, neovim-git-local-history and neovim-island-dark-theme. The here-document is quoted so the shell does not expand anything inside it.'),
    blank,
    ...sec(r'the plugins card without a screenshot'),
    ...code('bash', r'scripts/make-share-images.sh · lines 52-60', r'''
# The plugins page: the card shows the nine plugin names instead of a screenshot.
plug=$(mktemp --suffix=.png)
trap 'rm -f "$plug"' EXIT
magick -size 1440x470 "xc:$PANEL" -font "$MONO" -pointsize 40 \
  -fill "$BLUE" -annotate +60+80 "Standalone" -fill "$BLUE" -annotate +760+80 "Rust toolkit" \
  -fill "$TITLE" -annotate +60+160 "xyno-history.nvim" -annotate +60+215 "xyno-sandbox.nvim" -annotate +60+270 "xyno-clipboard.nvim" -annotate +60+325 "xyno-guard.nvim" \
  -annotate +760+160 "xyno-rust.nvim" -annotate +760+215 "xyno-new.nvim" -annotate +760+270 "xyno-imports.nvim" -annotate +760+325 "xyno-crates.nvim" -annotate +760+380 "xyno-macros.nvim" \
  "$plug"
card site/assets/og-plugins.png 1200 630 "xynovim plugins" "Nine Neovim plugins" "MIT licensed, extracted from my config, installed with lazy.nvim" "$plug" 60
'''),
    ...para(r'#', r'The plugins page has no screenshot to show, so the script draws one: a panel with two columns of names in the monospace font, Standalone and Rust toolkit, with the nine xyno-* plugin names. It is created as a temporary PNG and removed by an EXIT trap. Then card is called with that image and a title size of 60.'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt(r'#', r'committed output', r'the cards are generated rarely and are served as plain files. The build and CI do not need ImageMagick.'),
    ...pt(r'#', r'fonts', r'the fonts are chosen by ImageMagick name (DejaVu-Sans-Bold, DejaVu-Sans, DejaVu-Sans-Mono-Bold), so the output depends on those fonts being installed where the script runs. The PNGs are committed and the header says the script needs magick.'),
    ...pt(r'#', r'hard-coded positions', r'the offsets are given as percentages inside one function, so a change to the layout is a change in one place.'),
    ...sec(r'history'),
    ...pt(r'#', r'ca84675 2026-10-22', r'share images added for the home page, the guides and the GitHub social preview.'),
    ...pt(r'#', r'e6ad339 2026-10-22', r'the plugins page and its card with the nine plugin names.'),
  ],
);
