#!/usr/bin/env bash
# install.sh — install delete-session.sh + slash command into ~/.claude/
#
# Idempotent. Will not overwrite files unless --force.
# After install, the script lives at ~/.claude/scripts/delete-session.sh
# and the slash command is available as `/delete-session` inside Claude Code.

set -eu

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=1 ;;
    --help|-h)  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST_SCRIPT="$HOME/.claude/scripts/delete-session.sh"
DEST_CMD="$HOME/.claude/commands/delete-session.md"

command -v jq >/dev/null || { echo "error: jq is required. Install via 'brew install jq' or your package manager." >&2; exit 1; }

mkdir -p "$(dirname "$DEST_SCRIPT")" "$(dirname "$DEST_CMD")"

copy_file() {
  local src="$1" dst="$2"
  if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
    if cmp -s "$src" "$dst"; then
      echo "✓ $dst (already up to date)"
    else
      echo "✗ $dst exists and differs from source. Re-run with --force to overwrite." >&2
      return 1
    fi
  else
    cp "$src" "$dst"
    echo "✓ $dst"
  fi
}

copy_file "$HERE/scripts/delete-session.sh" "$DEST_SCRIPT"
chmod +x "$DEST_SCRIPT"
copy_file "$HERE/commands/delete-session.md" "$DEST_CMD"

echo ""
echo "Installed. Try it:"
echo "  Terminal:     ~/.claude/scripts/delete-session.sh list"
echo "  Claude Code:  /delete-session"
