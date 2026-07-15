#!/usr/bin/env bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CCSC="$ROOT/scripts/delete-session.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export CLAUDE_HOME="$TMP/.claude"
export CCSC_ACTIVE_THRESHOLD_SEC=0
export NO_COLOR=1
PROJECT="$TMP/demo-project"
ENCODED="$(printf '%s' "$PROJECT" | sed 's:/:-:g')"
SESSIONS="$CLAUDE_HOME/projects/$ENCODED"
mkdir -p "$PROJECT" "$SESSIONS"

pass=0
fail() { echo "not ok - $1" >&2; exit 1; }
ok() { pass=$((pass + 1)); echo "ok $pass - $1"; }
assert_contains() { printf '%s' "$1" | grep -Fq "$2" || fail "$3 (missing: $2)"; }

UUID1="11111111-1111-4111-8111-111111111111"
UUID2="22222222-2222-4222-8222-222222222222"
cat > "$SESSIONS/$UUID1.jsonl" <<'EOF'
{"type":"user","message":{"content":"fallback prompt"}}
{"type":"last-prompt","lastPrompt":"ship the release"}
{"type":"custom-title","customTitle":"Release prep"}
EOF
cat > "$SESSIONS/$UUID2.jsonl" <<'EOF'
{"type":"user","message":{"content":[{"type":"text","text":"array message"}]}}
EOF
touch -t 202001010101 "$SESSIONS/$UUID1.jsonl" "$SESSIONS/$UUID2.jsonl"
mkdir -p "$SESSIONS/$UUID1/subagents"
echo artifact > "$SESSIONS/$UUID1/subagents/result.txt"

out=$(cd "$PROJECT" && "$CCSC" list)
assert_contains "$out" "★ Release prep" "custom title has highest priority"
assert_contains "$out" "array message" "array user content is rendered"
ok "list renders title priorities"

out=$(cd "$PROJECT" && "$CCSC" --json list)
[ "$(printf '%s' "$out" | jq length)" -eq 2 ] || fail "JSON list count"
[ "$(printf '%s' "$out" | jq --arg uuid "$UUID1" '[.[] | select(.uuid == $uuid)] | length')" -eq 1 ] || fail "JSON list UUID"
ok "list supports machine-readable JSON"

out=$("$CCSC" stats)
assert_contains "$out" "Sessions" "stats output"
assert_contains "$out" "2" "stats session count"
ok "stats summarizes storage"

out=$("$CCSC" doctor)
assert_contains "$out" "Ready." "doctor ready state"
assert_contains "$out" "Session store" "doctor session store check"
ok "doctor validates the local environment"

out=$("$CCSC" trash "${UUID1:0:8}")
assert_contains "$out" "trashed:" "trash confirmation"
[ ! -e "$SESSIONS/$UUID1.jsonl" ] || fail "session should leave projects dir"
[ ! -e "$SESSIONS/$UUID1" ] || fail "artifacts should leave projects dir"
[ -n "$(find "$CLAUDE_HOME/session-cleaner-trash" -name metadata.json -print -quit)" ] || fail "trash metadata"
ok "trash moves the transcript and derivative artifacts"

mkdir -p "$SESSIONS/$UUID1"
if "$CCSC" restore "${UUID1:0:8}" >"$TMP/out" 2>"$TMP/err"; then fail "restore should refuse an artifact conflict"; fi
assert_contains "$(cat "$TMP/err")" "artifact destination already exists" "restore conflict message"
[ ! -e "$SESSIONS/$UUID1.jsonl" ] || fail "conflicted restore must keep transcript in trash"
rm -rf "$SESSIONS/$UUID1"
out=$("$CCSC" restore "${UUID1:0:8}")
assert_contains "$out" "restored:" "restore confirmation"
[ -f "$SESSIONS/$UUID1.jsonl" ] || fail "session should be restored"
[ -f "$SESSIONS/$UUID1/subagents/result.txt" ] || fail "artifacts should be restored"
ok "restore refuses conflicts and reconstructs the original session"

export CCSC_ACTIVE_THRESHOLD_SEC=999999999
if "$CCSC" trash "${UUID2:0:8}" >"$TMP/out" 2>"$TMP/err"; then fail "active guard should reject"; fi
assert_contains "$(cat "$TMP/err")" "is active" "active guard message"
ok "active sessions are protected"

export CCSC_ACTIVE_THRESHOLD_SEC=0
out=$("$CCSC" --project "$PROJECT" clean --older-than 1d)
assert_contains "$out" "Preview only" "clean defaults to preview"
[ -f "$SESSIONS/$UUID1.jsonl" ] && [ -f "$SESSIONS/$UUID2.jsonl" ] || fail "preview must not move sessions"
out=$("$CCSC" --project "$PROJECT" --json clean --older-than 1d)
[ "$(printf '%s' "$out" | jq length)" -eq 2 ] || fail "clean JSON preview count"
if "$CCSC" --project "$PROJECT" clean --older-than yesterday >"$TMP/out" 2>"$TMP/err"; then fail "invalid duration should fail"; fi
assert_contains "$(cat "$TMP/err")" "invalid duration" "invalid duration message"
out=$("$CCSC" --project "$PROJECT" clean --older-than 1d --yes)
assert_contains "$out" "trashed:" "clean execution output"
[ ! -e "$SESSIONS/$UUID1.jsonl" ] && [ ! -e "$SESSIONS/$UUID2.jsonl" ] || fail "clean --yes should move candidates"
ok "age-based cleanup previews before moving sessions"

INSTALL_HOME="$TMP/install-home"
mkdir -p "$INSTALL_HOME"
out=$(HOME="$INSTALL_HOME" "$ROOT/install.sh" --bin-dir="$INSTALL_HOME/bin")
[ -x "$INSTALL_HOME/bin/ccsc" ] || fail "installer should create ccsc"
[ -f "$INSTALL_HOME/.claude/commands/delete-session.md" ] || fail "installer should create slash command"
assert_contains "$out" "Installed ccsc" "installer output"
ok "installer creates the CLI and Claude Code command"

out=$(HOME="$INSTALL_HOME" "$ROOT/uninstall.sh" --force --bin-dir="$INSTALL_HOME/bin")
[ ! -e "$INSTALL_HOME/bin/ccsc" ] || fail "uninstaller should remove ccsc"
[ ! -e "$INSTALL_HOME/.claude/scripts/delete-session.sh" ] || fail "uninstaller should remove compatibility script"
[ ! -e "$INSTALL_HOME/.claude/commands/delete-session.md" ] || fail "uninstaller should remove slash command"
assert_contains "$out" "Recoverable sessions" "uninstaller preserves trash"
ok "uninstaller removes commands while preserving recoverable data"

echo "1..$pass"
