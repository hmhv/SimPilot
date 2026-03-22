# SimPilot installer
# Usage:
#   make install    — Install Claude Code / Codex skill symlinks
#   make uninstall  — Remove Claude Code / Codex skill symlinks
#   make update     — Pull latest changes and reinstall skills

REPO_DIR := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
SKILLS_DIR := $(REPO_DIR)/.claude/skills
CLAUDE_SKILLS_DIR := $(HOME)/.claude/skills
AGENTS_SKILLS_DIR := $(HOME)/.agents/skills
INSTALL_SKILLS_DIRS := $(CLAUDE_SKILLS_DIR) $(AGENTS_SKILLS_DIR)
SKILL_NAMES := sipi-test sipi-verify sipi-common

.PHONY: help install uninstall update

# ── Help ────────────────────────────────────────────────

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "  install    Install Claude Code / Codex skill symlinks"
	@echo "  uninstall  Remove Claude Code / Codex skill symlinks"
	@echo "  update     Pull latest changes and reinstall skills"

# ── Install ──────────────────────────────────────────────

install:
	@command -v axe >/dev/null 2>&1 || { \
		echo "WARNING: axe CLI not found. Install with: brew install cameroncooke/axe/axe && axe init"; \
	}
	@for dir in $(INSTALL_SKILLS_DIRS); do \
		mkdir -p "$$dir"; \
	done
	@for dir in $(INSTALL_SKILLS_DIRS); do \
		for skill in $(SKILL_NAMES); do \
			src="$(SKILLS_DIR)/$$skill"; \
			dst="$$dir/$$skill"; \
			if [ -d "$$dst" ] && [ ! -L "$$dst" ]; then \
				echo "ERROR: $$dst is a regular directory (not a symlink). Remove it manually to proceed."; \
				exit 1; \
			fi; \
			rm -f "$$dst"; \
			ln -s "$$src" "$$dst"; \
			echo "Skill linked: $$dst"; \
		done; \
	done
	@echo ""
	@echo "SimPilot installed successfully."

# ── Uninstall ────────────────────────────────────────────

uninstall:
	@for dir in $(INSTALL_SKILLS_DIRS); do \
		for skill in $(SKILL_NAMES); do \
			dst="$$dir/$$skill"; \
			if [ -L "$$dst" ]; then \
				rm -f "$$dst"; \
				echo "Skill removed: $$dst"; \
			elif [ -d "$$dst" ]; then \
				echo "WARNING: $$dst is a regular directory - skipped. Remove it manually if intended."; \
			else \
				echo "Skill not installed: $$dst"; \
			fi; \
		done; \
	done
	@echo ""
	@echo "SimPilot uninstalled."

# ── Update ───────────────────────────────────────────────

update:
	@echo "Pulling latest changes..."
	@git -C "$(REPO_DIR)" pull --ff-only
	@echo "Reinstalling skills..."
	@$(MAKE) install
	@echo ""
	@echo "SimPilot updated."
