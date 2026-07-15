#!/usr/bin/env bash
# Remove ccsc, its compatibility script, and the Claude Code slash command.

set -eu

FORCE=0
BIN_DIR="${HOME}/.local/bin"
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=1 ;;
    --bin-dir=*) BIN_DIR="${arg#*=}" ;;
    --help|-h)
      echo "usage: ./uninstall.sh [--force] [--bin-dir=/path]"
      exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

remove_file() {
  local target="$1" confirm
  if [ ! -e "$target" ]; then
    echo "✓ $target (already absent)"
    return
  fi
  if [ "$FORCE" -ne 1 ]; then
    printf "Remove %s? [y/N] " "$target"
    read -r confirm
    case "$confirm" in y|Y|yes|YES) ;; *) echo "  skipped"; return ;; esac
  fi
  rm -- "$target"
  echo "✓ $target (removed)"
}

remove_file "$BIN_DIR/ccsc"
remove_file "$HOME/.claude/scripts/delete-session.sh"
remove_file "$HOME/.claude/commands/delete-session.md"

echo ""
echo "Uninstalled ccsc. Recoverable sessions in ~/.claude/session-cleaner-trash were kept."
