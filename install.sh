#!/usr/bin/env bash
#
# SimPilot installer — installs the native `sipi` CLI to ~/.local/bin and
# materializes the embedded sipi-common / sipi-test / sipi-verify skills into
# Claude Code (~/.claude/skills) and Codex (~/.agents/skills).
#
# sipi ships as a single PREBUILT binary with the three skills baked in, so a
# normal end-user install is just a binary download — NO git clone, NO swift
# build, NO make on the user machine. (A full Xcode is still required at RUNTIME
# to drive the simulator; sipi dlopens its private frameworks by name.)
#
# Works two ways:
#   1. Local checkout:   ./install.sh   (run from inside the repo; builds from
#                        source as a dev/bootstrap path so the flow is testable
#                        before any GitHub Release exists)
#   2. Remote bootstrap: curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash
#                        (downloads the prebuilt `sipi` asset from the latest
#                        GitHub Release)
#
# Env overrides for the remote path:
#   SIMPILOT_REPO  GitHub repo slug to download from  (default: hmhv/SimPilot)
#   SIMPILOT_REF   release tag to download            (default: latest release)
#
# This installer is CLEAN-FIRST: it removes any existing install before
# installing. Re-running it is the supported reinstall path.
#
set -euo pipefail

SIMPILOT_REPO="${SIMPILOT_REPO:-hmhv/SimPilot}"
SIMPILOT_REF="${SIMPILOT_REF:-}"

BIN_DIR="$HOME/.local/bin"
SIPI_BIN="$BIN_DIR/sipi"
STAMP_FILE="$BIN_DIR/.sipi.stamp"
DATA_DIR="$HOME/.local/share/simpilot"

# Only these three skills are ever touched. Sibling directories living alongside
# ours (e.g. AutoStore sipi-shots / publish) are out of scope and never removed.
SKILL_NAMES="sipi-common sipi-test sipi-verify"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
AGENTS_SKILLS_DIR="$HOME/.agents/skills"

info()  { printf '%s\n' "$*"; }
warn()  { printf 'WARNING: %s\n' "$*" >&2; }
fail()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ── Guard: macOS (basic environment, always checked) ──────────────────────────

# Only the macOS check runs unconditionally: the prebuilt-download path needs no
# Xcode toolchain (a full Xcode is required at RUNTIME to drive the sim, but not
# to install). The Xcode 26+ toolchain check lives in build_from_checkout and
# only gates the local-checkout build path (see guard_build_toolchain).
guard_environment() {
  [ "$(uname -s)" = "Darwin" ] || fail "SimPilot requires macOS."
}

# ── Guard: Xcode 26+ toolchain (only needed for the local-checkout build) ─────

# Verifies a full Xcode 26+ is selected so `swift build` can compile sipi from
# source. Called only on the build_from_checkout path — the prebuilt-download
# path skips this entirely.
guard_build_toolchain() {
  command -v xcode-select >/dev/null 2>&1 || \
    fail "xcode-select not found. Install Xcode 26 or newer from the App Store."

  local dev_dir
  dev_dir="$(xcode-select -p 2>/dev/null || true)"
  if [ -z "$dev_dir" ] || [ ! -d "$dev_dir" ]; then
    fail "No Xcode selected. Install Xcode 26+ and run: sudo xcode-select -s /Applications/Xcode.app"
  fi

  command -v xcodebuild >/dev/null 2>&1 || \
    fail "xcodebuild not found. A full Xcode (not just Command Line Tools) is required: sudo xcode-select -s /Applications/Xcode.app"

  local xcode_line major
  xcode_line="$(xcodebuild -version 2>/dev/null | head -n1 || true)"
  major="$(printf '%s\n' "$xcode_line" | sed -n 's/^Xcode \([0-9][0-9]*\).*/\1/p')"
  if [ -z "$major" ]; then
    fail "Could not determine the Xcode version from: '$xcode_line'. Xcode 26+ is required."
  fi
  if [ "$major" -lt 26 ]; then
    fail "Xcode 26+ is required, but found '$xcode_line'. Update Xcode and run: sudo xcode-select -s /Applications/Xcode.app"
  fi
  info "Xcode: $xcode_line"
}

# ── Clean first: remove any existing install (only our three skills) ─────────

clean_existing_install() {
  info "Removing any existing SimPilot install..."

  rm -f "$SIPI_BIN" "$STAMP_FILE"

  local dir skill
  for dir in "$CLAUDE_SKILLS_DIR" "$AGENTS_SKILLS_DIR"; do
    for skill in $SKILL_NAMES; do
      # rm -rf also clears any stale symlink left by an older installer.
      rm -rf "$dir/$skill"
    done
  done

  rm -rf "$DATA_DIR"
}

# ── Locate this script's checkout (dev/bootstrap path) ───────────────────────

# Sets REPO_DIR to the local checkout root when install.sh is run from inside
# the repo (script dir, or cwd, contains Package.swift at the root). Leaves
# REPO_DIR empty for the remote curl|bash path.
resolve_local_checkout() {
  REPO_DIR=""
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
  if [ -n "$script_dir" ] && [ -f "$script_dir/Package.swift" ]; then
    REPO_DIR="$script_dir"
    return
  fi
  if [ -f "$PWD/Package.swift" ]; then
    REPO_DIR="$PWD"
    return
  fi
}

# ── Obtain the binary ────────────────────────────────────────────────────────

# Dev/bootstrap: build from the local checkout and copy into place. This keeps
# the flow testable now, before any GitHub Release has been cut.
build_from_checkout() {
  info "Local checkout detected at $REPO_DIR — building sipi from source (release)..."
  # Building from source needs the full Xcode 26+ toolchain; verify it here so
  # the prebuilt-download path stays Xcode-free.
  guard_build_toolchain
  command -v swift >/dev/null 2>&1 || fail "swift not found. Install Xcode 26+ (it ships the Swift toolchain)."

  swift build -c release --package-path "$REPO_DIR" --product sipi

  local built="$REPO_DIR/.build/release/sipi"
  [ -x "$built" ] || fail "Build did not produce $built."

  mkdir -p "$BIN_DIR"
  cp -f "$built" "$SIPI_BIN"
}

# Remote: download the prebuilt `sipi` asset from the latest (or pinned) GitHub
# Release of $SIMPILOT_REPO into ~/.local/bin/sipi.
download_prebuilt_binary() {
  command -v curl >/dev/null 2>&1 || fail "curl is required to download the sipi release asset."

  local api_url
  if [ -n "$SIMPILOT_REF" ]; then
    api_url="https://api.github.com/repos/$SIMPILOT_REPO/releases/tags/$SIMPILOT_REF"
    info "Looking up SimPilot release $SIMPILOT_REF from $SIMPILOT_REPO..."
  else
    api_url="https://api.github.com/repos/$SIMPILOT_REPO/releases/latest"
    info "Looking up the latest SimPilot release from $SIMPILOT_REPO..."
  fi

  local release_json
  release_json="$(curl -fsSL \
    -H 'Accept: application/vnd.github+json' \
    -H 'User-Agent: simpilot-install' \
    "$api_url" 2>/dev/null || true)"

  if [ -z "$release_json" ]; then
    fail "No SimPilot release found on $SIMPILOT_REPO${SIMPILOT_REF:+ (tag $SIMPILOT_REF)}. A release has not been cut yet — install from a local checkout, or set SIMPILOT_REPO/SIMPILOT_REF."
  fi

  # Find the download URL of the asset named exactly "sipi" (matches the asset
  # name that `sipi update` expects). Parsed without jq for portability.
  local asset_url
  asset_url="$(printf '%s\n' "$release_json" \
    | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*/sipi"' \
    | head -n1 \
    | sed -E 's/.*"(https?:[^"]*)".*/\1/')"

  if [ -z "$asset_url" ]; then
    fail "The latest SimPilot release on $SIMPILOT_REPO has no 'sipi' binary asset. A prebuilt binary has not been published yet."
  fi

  info "Downloading sipi from $asset_url..."
  mkdir -p "$BIN_DIR"
  curl -fsSL \
    -H 'Accept: application/octet-stream' \
    -H 'User-Agent: simpilot-install' \
    -o "$SIPI_BIN" \
    "$asset_url" || fail "Failed to download the sipi binary from $asset_url."
}

obtain_binary() {
  if [ -n "$REPO_DIR" ]; then
    build_from_checkout
  else
    download_prebuilt_binary
  fi

  [ -f "$SIPI_BIN" ] || fail "sipi binary was not installed to $SIPI_BIN."

  chmod +x "$SIPI_BIN"
  # Strip the quarantine bit so Gatekeeper does not block a downloaded binary.
  xattr -d com.apple.quarantine "$SIPI_BIN" 2>/dev/null || true
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
  guard_environment
  clean_existing_install
  resolve_local_checkout
  obtain_binary

  info "Installed sipi -> $SIPI_BIN"

  # The binary ships the skills embedded; `setup` materializes them into both
  # agent dirs, writes install metadata, and prints PATH advice if needed.
  info "Running sipi setup..."
  "$SIPI_BIN" setup

  info ""
  info "SimPilot installed successfully."
  info "  sipi binary : $SIPI_BIN"
  info "  Skills      : $SKILL_NAMES"
  info "    -> $CLAUDE_SKILLS_DIR"
  info "    -> $AGENTS_SKILLS_DIR"
}

main "$@"
