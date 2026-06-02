#!/bin/bash
set -eu

# Worktree setup hook for Pockode
# Runs automatically when creating a new worktree.
#
# Environment variables:
#   $POCKODE_MAIN_DIR      - Path to main worktree
#   $POCKODE_WORKTREE_PATH - Path to newly created worktree (= cwd)
#   $POCKODE_WORKTREE_NAME - Name of the worktree

# Symlink Claude Code local settings (share permissions across worktrees)
# if [ -f "$POCKODE_MAIN_DIR/.claude/settings.local.json" ]; then
#     mkdir -p .claude
#     ln -s "$POCKODE_MAIN_DIR/.claude/settings.local.json" .claude/settings.local.json
# fi

# Install npm dependencies
# if [ -f package.json ]; then
#     npm install
# fi
