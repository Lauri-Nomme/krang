#!/usr/bin/env bash
set -euo pipefail

KRANG_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-project}"

usage() {
  echo "Usage: $0 [project|global]"
  echo "  project  - Install into .opencode/agents/ in the current directory (default)"
  echo "  global   - Install into ~/.config/opencode/agents/ for all projects"
  exit 1
}

if [ "$MODE" != "project" ] && [ "$MODE" != "global" ]; then
  usage
fi

if [ "$MODE" = "project" ]; then
  TARGET=".opencode/agents"
  echo "Installing krang agents into $TARGET ..."
  mkdir -p "$TARGET"
  cp "$KRANG_DIR/.opencode/agents/krang-"*.md "$TARGET/"
  echo "Done. Use @krang-planner, @krang-executor, @krang-replanner in your project."
else
  TARGET="$HOME/.config/opencode/agents"
  echo "Installing krang agents globally into $TARGET ..."
  mkdir -p "$TARGET"
  cp "$KRANG_DIR/.opencode/agents/krang-"*.md "$TARGET/"
  echo "Done. Agents available globally for all projects."
fi
