# SimPilot Distribution

## 1. Model: one prebuilt binary, skills embedded

SimPilot ships as a **single prebuilt `sipi` binary** published via **GitHub
Releases**. The `sipi-common` skill is **embedded into the binary** at build
time, so one binary download is fully
self-contained — there is no separate skill payload to fetch, clone, or sync.

This is safe even though `sipi` drives Apple's **private** Simulator frameworks:
`sipi` `dlopen`s those frameworks **at runtime by string** (no build-time
linkage), so a prebuilt binary resolves the user's Xcode frameworks identically
to a locally-built one. Xcode 27.2+ is therefore needed at **runtime** (to drive
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

No `git clone` and no `swift build` on the user machine. `install.sh` renames
the new binary over the old one, then removes the old skills and data before `sipi setup`
lays them down again, so a failed download leaves the old install working.

## 3. `sipi` lifecycle subcommands

The installer is a thin bootstrap; the lifecycle lives in the binary itself:

- **`sipi setup`** — materialize the embedded skills into **both**
  `~/.claude/skills` (Claude Code) and `~/.agents/skills` (Codex), and record
  install metadata. Clean-first and idempotent; only ever touches the SimPilot
  skill, and removes `sipi-test` / `sipi-verify` left by versions before 3.0.0
  (sibling skills are left intact).
- **`sipi update`** — check GitHub Releases for a newer tag, download the
  prebuilt binary, strip the quarantine xattr, self-replace, and refresh the
  skills. "Already up to date" / "no release yet" is a clean exit 0.
- **`sipi uninstall`** — remove the skills from both agent dirs, the install
  metadata, and the binary.
- **`sipi version`** / **`sipi doctor`** — version handshake + capability probe.

## 4. Developer workflow

A developer working on SimPilot builds with `swift build -c release` from the
repository root and runs the local `.build/release/sipi`. End users never build
from source.

## 5. Deferred ops

- **CI auto-release.** Building and publishing the prebuilt binary to GitHub
  Releases on tag is not yet automated; releases are cut manually. The per-Xcode
  `sipi doctor` matrix remains a separate, deferred ops item.
