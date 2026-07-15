#!/usr/bin/env bash
# Install ccsc, its compatibility script, and the Claude Code slash command.

set -eu

FORCE=0
BIN_DIR="${HOME}/.local/bin"
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=1 ;;
    --bin-dir=*) BIN_DIR="${arg#*=}" ;;
    --help|-h)
      echo "usage: ./install.sh [--force] [--bin-dir=/path]"
      exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST_BIN="$BIN_DIR/ccsc"
DEST_SCRIPT="$HOME/.claude/scripts/delete-session.sh"
DEST_CMD="$HOME/.claude/commands/delete-session.md"

command -v jq >/dev/null || {
  echo "error: jq is required (brew install jq / apt-get install jq)" >&2
  exit 1
}

mkdir -p "$BIN_DIR" "$(dirname "$DEST_SCRIPT")" "$(dirname "$DEST_CMD")"

copy_file() {
  local src="$1" dst="$2"
  if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
    if cmp -s "$src" "$dst"; then
      echo "✓ $dst (up to date)"
    else
      echo "✗ $dst exists. Re-run with --force to replace it." >&2
      return 1
    fi
  else
    cp "$src" "$dst"
    echo "✓ $dst"
  fi
}

copy_file "$HERE/scripts/delete-session.sh" "$DEST_BIN"
chmod +x "$DEST_BIN"
copy_file "$HERE/scripts/delete-session.sh" "$DEST_SCRIPT"
chmod +x "$DEST_SCRIPT"
copy_file "$HERE/commands/delete-session.md" "$DEST_CMD"

echo ""
echo "Installed ccsc. Try:"
echo "  ccsc                 # interactive browser"
echo "  ccsc stats           # storage overview"
echo "  /delete-session      # inside Claude Code"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo ""; echo "Note: add $BIN_DIR to PATH to use the ccsc command." ;;
esac
