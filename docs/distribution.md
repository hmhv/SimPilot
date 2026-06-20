# SimPilot Distribution

## 1. Model: one prebuilt binary, skills embedded

SimPilot ships as a **single prebuilt `sipi` binary** published via **GitHub
Releases**. The three skills (`sipi-common`, `sipi-test`, `sipi-verify`) are
**embedded into the binary** at build time, so one binary download is fully
self-contained — there is no separate skill payload to fetch, clone, or sync.

This is safe even though `sipi` drives Apple's **private** Simulator frameworks:
`sipi` `dlopen`s those frameworks **at runtime by string** (no build-time
linkage), so a prebuilt binary resolves the user's Xcode frameworks identically
to a locally-built one. Xcode 26+ is therefore needed at **runtime** (to drive
the Simulator), not to install.

## 2. End-user lifecycle

```bash
# Install — downloads the prebuilt binary; sipi then lays down the embedded skills
curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash

# Update — download the latest release binary and refresh the embedded skills
sipi update

# Uninstall — remove the skills, install metadata, and the binary
sipi uninstall
```

No `git clone` and no `swift build` on the user machine. `install.sh` is
**clean-first**: it removes any existing install before installing.

## 3. `sipi` lifecycle subcommands

The installer is a thin bootstrap; the lifecycle lives in the binary itself:

- **`sipi setup`** — materialize the embedded skills into **both**
  `~/.claude/skills` (Claude Code) and `~/.agents/skills` (Codex), and record
  install metadata. Clean-first and idempotent; only ever touches the three
  SimPilot skills (sibling skills are left intact).
- **`sipi update`** — check GitHub Releases for a newer tag, download the
  prebuilt binary, strip the quarantine xattr, self-replace, and refresh the
  skills. "Already up to date" / "no release yet" is a clean exit 0.
- **`sipi uninstall`** — remove the three skills from both agent dirs, the
  install metadata, and the binary.
- **`sipi report` / `sipi verify-report` / `sipi validate`** — report generation
  and result validation live inside the binary, so the single-binary install
  stays self-contained. The skill docs invoke `sipi report …` directly.
- **`sipi version`** / **`sipi doctor`** — version handshake + capability probe.

## 4. Developer workflow

A developer working on SimPilot builds with `swift build -c release` from the
repository root and runs the local `.build/release/sipi`. End users never build
from source.

## 5. Deferred ops

- **CI auto-release.** Building and publishing the prebuilt binary to GitHub
  Releases on tag is not yet automated; releases are cut manually. The per-Xcode
  `sipi doctor` matrix remains a separate, deferred ops item.
