import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/.github/workflows/platforms.yml',
  lines: [
    cm(r'#', '──────────────────────────────────────────'),
    cm(r'#', r'.github/workflows/platforms.yml'),
    cm(r'#', r'Windows and macOS'),
    cm(r'#', r'the same checks as ci.yml on the other two operating systems the config targets'),
    cm(r'#', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'cross-platform continuous integration'),
    kv(r'language', r'GitHub Actions YAML (pwsh on Windows, bash on macOS)'),
    kv(r'size', r'130 lines, two jobs, three commits (ff1c8fa, cd602fd, 6524272)'),
    kv(r'runners', r'windows-latest (90 minutes) · macos-latest (60 minutes)'),
    kv(r'Neovim', r'v0.12.5, pinned, SHA-256 verified'),
    ...sec(r'why this file exists'),
    ...para(r'#', r'The README says the configuration is developed on Linux (Arch) and also run in CI on Windows and macOS. This workflow is the Windows and macOS part of that. The header says what the workflow is: the same checks as ci.yml (bootstrap from the lockfile, a silent startup, the spec suite) on the platforms the config also targets. It is a separate workflow, and the stated reason is that the Linux job in ci.yml should stay as fast and as stable as it was. It also tells the reader what to expect: specs that cannot work there (bubblewrap, /proc, tmux, bash stubs) skip with a printed reason, visible as SKIP lines in the log.'),
    blank,
    ...code('yaml', r'.github/workflows/platforms.yml · lines 1-18', r'''
name: platforms

# Windows and macOS: the same checks as ci.yml (bootstrap from the lockfile, a
# silent startup, the spec suite) on the platforms the config also targets. A
# separate workflow so the Linux job in ci.yml stays as fast and as stable as it
# was. Specs that cannot work there (bubblewrap, /proc, tmux, bash stubs) skip
# with a printed reason: see the SKIP lines in the log.

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

env:
  NVIM_VERSION: v0.12.5
'''),
    ...para(r'#', r'One variable is shared by both jobs: NVIM_VERSION. Both jobs use v0.12.5 and neither downloads stable. Where ci.yml follows a moving target, these jobs follow a fixed one, with a checksum for each operating system.'),
    blank,
    ...sec(r'the Windows job'),
    ...code('yaml', r'.github/workflows/platforms.yml · lines 20-41', r'''
jobs:
  windows:
    runs-on: windows-latest
    timeout-minutes: 90
    defaults:
      run:
        shell: pwsh
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          persist-credentials: false

      - name: Install Neovim (pinned, checksum verified)
        env:
          NVIM_SHA256: de8625ba8cf65ebf40eb80a388ba1ec8e9c15b30218821e2c639119b05920de1
        run: |
          $zip = Join-Path $env:RUNNER_TEMP 'nvim-win64.zip'
          Invoke-WebRequest -Uri "https://github.com/neovim/neovim/releases/download/$env:NVIM_VERSION/nvim-win64.zip" -OutFile $zip
          $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
          if ($hash -ne $env:NVIM_SHA256.ToUpper()) { throw "nvim-win64.zip sha256 mismatch: $hash" }
          Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $env:RUNNER_TEMP 'nvim')
          Add-Content -Path $env:GITHUB_PATH -Value (Join-Path $env:RUNNER_TEMP 'nvim\nvim-win64\bin')
'''),
    ...para(r'#', r'Defaults make every run step PowerShell 7 (pwsh). The job has a 90 minute timeout, longer than the 40 of the Linux job (the file does not say why). Neovim is downloaded as a zip, its SHA-256 is computed with Get-FileHash and compared to a value in the workflow, and a mismatch throws. Only after that is the archive expanded and its bin added to GITHUB_PATH. The hash is upper-cased on one side because Get-FileHash returns upper case.'),
    blank,
    ...code('yaml', r'.github/workflows/platforms.yml · lines 43-52', r'''
      - name: Use the checkout as the Neovim config (junction)
        run: |
          cmd /c mklink /J "$env:LOCALAPPDATA\nvim" "$env:GITHUB_WORKSPACE"
          nvim --version | Select-Object -First 1

      - name: Add rust-analyzer (a prerequisite the bootstrap script checks)
        run: rustup component add rust-analyzer clippy

      - name: Restore plugins from the lockfile
        run: scripts\bootstrap.ps1
'''),
    ...para(r'#', r'The config directory on Windows is %LOCALAPPDATA%\nvim, so the checkout is linked there with a junction (no administrator rights needed), the same mechanism that scripts/bootstrap.ps1 uses. Then the step prints the first line of nvim --version into the log as a record. rust-analyzer and clippy are added, then scripts\bootstrap.ps1 restores the plugins.'),
    blank,
    ...sec(r'diagnostics that run even when things fail'),
    ...code('yaml', r'.github/workflows/platforms.yml · lines 54-62', r'''
      - name: Mason log (what could not be installed here, and why)
        if: always()
        run: |
          $log = Join-Path $env:LOCALAPPDATA 'nvim-data\mason.log'
          if (Test-Path $log) { Get-Content $log | Select-String -Pattern 'codelldb|ERROR|failed' | Select-Object -Last 60 } else { "no $log" }

      - name: Language client diagnostic (what attaches to a fresh crate)
        if: always()
        run: nvim --headless "+luafile .github/ci/diag-lsp.lua"
'''),
    ...para(r'#', r'Two steps run with if: always(), which means they report after a failed bootstrap or when the next step would not run. The first prints the part of mason.log that matches codelldb, ERROR or failed, the last 60 lines, or says that there is no log. The step name states the purpose: what could not be installed here, and why. These steps came in with cd602fd (2026-10-21). The step name says what they are for: what could not be installed here, and why.'),
    blank,
    ...para(r'#', r'The second step runs .github/ci/diag-lsp.lua, a script that prints which language clients attach to a fresh crate, and what the LSP log says when one does not (see the page for that file). It was added by 6524272 together with the Windows and macOS fixes of run 39640256853. Only the Windows job has it.'),
    blank,
    ...sec(r'the checks themselves'),
    ...code('yaml', r'.github/workflows/platforms.yml · lines 64-73', r'''
      - name: Lockfile unchanged
        run: git diff --exit-code lazy-lock.json

      - name: Startup smoke test
        run: |
          # any message on stderr (a failed plugin spec, a Lua error) fails the job
          $log = Join-Path $env:RUNNER_TEMP 'startup.log'
          $t = Measure-Command { nvim --headless +qa 2> $log }
          Write-Host ("headless startup: {0} ms" -f [int]$t.TotalMilliseconds)
          if ((Test-Path $log) -and (Get-Item $log).Length -gt 0) { Get-Content $log; exit 1 }
'''),
    ...para(r'#', r'The lockfile check is the same as on Linux, and it comes before the startup test. The startup test is the PowerShell version of the smoke test: stderr goes to a file, Measure-Command times it, and a non-empty file fails the job. Compare with ci.yml: there is no limit of 3000 ms here, only silence. The workflow does not say why the time check was left out.'),
    blank,
    ...code('yaml', r'.github/workflows/platforms.yml · lines 75-79', r'''
      - name: Spec suite
        run: scripts\test.ps1 --timeout 240

      - name: Lockfile still unchanged after the specs
        run: git diff --exit-code lazy-lock.json
'''),
    ...para(r'#', r'The suite runs through the PowerShell entry point scripts\test.ps1, which calls scripts/test.lua, and passes --timeout 240. That is twice the runner’s default of 120 seconds; the workflow gives no reason. The final step re-checks the lockfile.'),
    blank,
    ...sec(r'the macOS job'),
    ...code('yaml', r'.github/workflows/platforms.yml · lines 81-103', r'''
  macos:
    runs-on: macos-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          persist-credentials: false

      - name: Install Neovim (pinned, checksum verified)
        env:
          NVIM_SHA256: 65fb000099e47ca1b762584c484cc833f40e30851a0ec450d4174e16317c1f9b
        run: |
          curl -fsSL -o nvim.tar.gz "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-macos-arm64.tar.gz"
          echo "${NVIM_SHA256}  nvim.tar.gz" | shasum -a 256 -c -
          mkdir -p "$HOME/nvim"
          tar -xzf nvim.tar.gz -C "$HOME/nvim" --strip-components=1
          echo "$HOME/nvim/bin" >> "$GITHUB_PATH"

      - name: Use the checkout as the Neovim config
        run: |
          mkdir -p "$HOME/.config"
          ln -s "$GITHUB_WORKSPACE" "$HOME/.config/nvim"
          "$HOME/nvim/bin/nvim" --version | head -1
'''),
    ...para(r'#', r'macOS runs on arm64 with its own pinned checksum, verified with shasum. Neovim is installed from a tarball into the home directory, the checkout is linked into ~/.config/nvim as on Linux, and the version is printed. The same prerequisite, bootstrap, Mason log, lockfile and startup steps follow; on macOS the Mason log is read from the state directory, ~/.local/state/nvim/mason.log, and the startup check is silence-only like on Windows.'),
    blank,
    ...code('yaml', r'.github/workflows/platforms.yml · lines 125-130', r'''
      - name: Spec suite
        # the portable runner: macOS has no GNU timeout for scripts/test.sh
        run: nvim --clean -l scripts/test.lua --timeout 240

      - name: Lockfile still unchanged after the specs
        run: git diff --exit-code lazy-lock.json
'''),
    ...para(r'#', r'The suite step has a comment that explains the one real difference from Linux: macOS has no GNU timeout, which scripts/test.sh uses, so the job runs the portable Lua runner directly, with nvim --clean -l scripts/test.lua --timeout 240.'),
    blank,
    ...sec(r'design decisions and trade-offs'),
    ...pt(r'#', r'pinned and verified Neovim', r'the Neovim version cannot change between runs, so a difference between runs is not a Neovim release.'),
    ...pt(r'#', r'separate from ci.yml', r'a failure or a slow run on Windows does not hold up the Linux gate.'),
    ...pt(r'#', r'diagnostics as steps', r'the Mason log and language-client steps run with if: always(), so their output is in the log even when an earlier step failed.'),
    ...pt(r'#', r'honest skips', r'the workflow does not hide what cannot run on the platform: the specs print SKIP with a reason, and the README was changed to follow the runs (196c8af, 751c0c7).'),
    ...sec(r'history'),
    ...pt(r'#', r'ff1c8fa 2026-10-16', r'added with the PowerShell bootstrap, the portable runner and the OS-aware skips.'),
    ...pt(r'#', r'cd602fd 2026-10-21', r'platform runs: path-form tolerant equality on Windows, a BSD-safe sed stub, a noice notify filter, explicit skips for two undiagnosed failures, a Mason log step.'),
    ...pt(r'#', r'6524272 2026-10-21', r'fixes from run 39640256853: .exe suffix and drive-letter case, canonical state keys, and the language-client diagnostic step.'),
    ...pt(r'#', r'751c0c7 and 196c8af 2026-10-22', r'commits that change wording in the README and site to follow the platform runs; they do not change this file.'),
  ],
);
