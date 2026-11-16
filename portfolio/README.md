# portfolio

The default public page at https://xynorash.github.io/xynorash/ : a static,
full-width HTML page (no build step). Design reference: `docs/mockups/b-signal-v3.html`.

The Flutter "IDE" app in `../site` is kept at `/xynorash/ide/`.

## Assembly and deploy

`.github/workflows/pages.yml` runs on push to `main` (paths `portfolio/**`, `site/**`,
the workflow) or manually. It builds `site` with `--base-href /xynorash/ide/`, copies
`portfolio/*` to the root of `_site/` and the Flutter build to `_site/ide/`, adds
`.nojekyll`, and publishes `_site/` to the `gh-pages` branch (Pages source: gh-pages, root).
`tools/assemble-site.sh` does the same assembly locally.

## Run locally

Page only: `python3 -m http.server -d portfolio`
Full site: `tools/assemble-site.sh && python3 -m http.server -d _site`
(the IDE is built for the `/xynorash/ide/` base, so check it at
`http://localhost:8000/ide/` only after serving under a `/xynorash/` prefix, or deploy-test on Pages).
