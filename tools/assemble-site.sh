#!/usr/bin/env bash
# Build the Flutter app and assemble _site/ exactly like .github/workflows/pages.yml.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

(cd site && flutter pub get && flutter build web --release --base-href /xynorash/ide/)

rm -rf _site
mkdir -p _site/ide
cp -r portfolio/. _site/
cp -r site/build/web/. _site/ide/
rm -f _site/README.md
touch _site/.nojekyll
echo "assembled $root/_site (serve with: python3 -m http.server -d _site)"
