#!/usr/bin/env bash
# ccsc — a safe session manager for Claude Code
# Bash 3.2 compatible (the version bundled with macOS).

set -u

VERSION="2.1.0"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
PROJECTS_DIR="${CCSC_PROJECTS_DIR:-$CLAUDE_HOME/projects}"
TRASH_DIR="${CCSC_TRASH_DIR:-$CLAUDE_HOME/session-cleaner-trash}"
ACTIVE_THRESHOLD_SEC="${CCSC_ACTIVE_THRESHOLD_SEC:-600}"
SCOPE="current"
PROJECT_PATH="$PWD"
JSON=0
NO_COLOR="${NO_COLOR:+1}"

is_tty() { [ -t 1 ] || [ "${FORCE_COLOR:-0}" = "1" ]; }
if is_tty && [ -z "$NO_COLOR" ]; then
  BOLD='\033[1m'; DIM='\033[2m'; CYAN='\033[36m'; GREEN='\033[32m'
  YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'
else
  BOLD=''; DIM=''; CYAN=''; GREEN=''; YELLOW=''; RED=''; RESET=''
fi

usage() {
  cat <<'EOF'
ccsc — safely manage Claude Code sessions

Usage:
  ccsc [options]                         interactive session browser
  ccsc [options] list [pattern]          list sessions
  ccsc [options] stats                   show storage overview
  ccsc doctor                            diagnose the local environment
  ccsc [options] clean --older-than 30d  preview an age-based cleanup
  ccsc trash <uuid>...                   move sessions to the trash
  ccsc restore [uuid]                    list trash or restore one session
  ccsc purge <uuid>|--all                permanently empty trash entries

Options:
  -a, --all              include every project
  -p, --project <path>   inspect a specific project
      --json             machine-readable output (list/stats/clean preview)
      --no-color         disable ANSI colors
  -h, --help             show help
  -v, --version          show version

Environment:
  CLAUDE_HOME                 Claude data directory (default: ~/.claude)
  CCSC_ACTIVE_THRESHOLD_SEC  active-session guard (default: 600)
  NO_COLOR                    disable ANSI colors
EOF
}

require_jq() {
  command -v jq >/dev/null || {
    echo "error: jq is required. Run 'ccsc doctor' for setup guidance." >&2
    return 1
  }
}

validate_config() {
  case "$ACTIVE_THRESHOLD_SEC" in
    ''|*[!0-9]*)
      echo "error: CCSC_ACTIVE_THRESHOLD_SEC must be a non-negative integer" >&2
      return 2 ;;
  esac
}

encode_path() { printf '%s' "$1" | sed 's:/:-:g'; }

file_mtime() {
  case "$(uname -s)" in
    Darwin) stat -f %m "$1" 2>/dev/null ;;
    *) stat -c %Y "$1" 2>/dev/null ;;
  esac || printf '0'
}

format_time() {
  date -r "$1" "+%Y-%m-%d %H:%M" 2>/dev/null ||
    date -d "@$1" "+%Y-%m-%d %H:%M" 2>/dev/null || printf 'unknown'
}

human_size() { du -h "$1" 2>/dev/null | awk 'NR==1 {print $1}'; }

last_user_message() {
  local all real
  all=$(jq -r '
    select(.type=="user") |
    if (.message.content | type) == "string" then .message.content
    elif (.message.content | type) == "array" then
      (.message.content | map(select(.type=="text") | .text) | join(" "))
    else "" end
  ' "$1" 2>/dev/null | awk 'NF')
  [ -z "$all" ] && return
  real=$(printf '%s\n' "$all" | grep -v -E '^<local-command-(caveat|stdout)>' | tail -1)
  [ -z "$real" ] && real=$(printf '%s\n' "$all" | tail -1)
  printf '%s' "$real" | tr '\n\t' '  ' | cut -c 1-70
}

custom_title() {
  jq -r 'select(.type=="custom-title") | .customTitle // empty' "$1" 2>/dev/null | tail -1
}

last_prompt() {
  jq -r 'select(.type=="last-prompt") | .lastPrompt // empty' "$1" 2>/dev/null |
    awk 'NF' | tail -1 | tr '\n\t' '  ' | cut -c 1-70
}

short_project() {
  local raw="$1" last
  case "$raw" in
    ssh-*) printf '%s' "$raw" ;;
    -*) last="${raw##*-}"; [ -z "$last" ] && last="$raw"; printf '%s' "$last" ;;
    *) printf '%s' "$raw" ;;
  esac
}

# mtime<TAB>date<TAB>project<TAB>size<TAB>uuid<TAB>title<TAB>prompt<TAB>message<TAB>path
parse_session() {
  local f="$1" uuid project mt
  uuid=$(basename "$f" .jsonl)
  project=$(short_project "$(basename "$(dirname "$f")")")
  mt=$(file_mtime "$f")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$mt" "$(format_time "$mt")" "$project" "$(human_size "$f")" "$uuid" \
    "$(custom_title "$f")" "$(last_prompt "$f")" "$(last_user_message "$f")" "$f"
}

collect_tsv() {
  local root depth encoded
  if [ "$SCOPE" = "current" ]; then
    encoded=$(encode_path "$PROJECT_PATH")
    root="$PROJECTS_DIR/$encoded"; depth=1
    if [ ! -d "$root" ]; then
      echo "No sessions directory for '$PROJECT_PATH'. Try --all." >&2
      return 0
    fi
  else
    root="$PROJECTS_DIR"; depth=2
  fi
  [ -d "$root" ] || return 0
  find "$root" -maxdepth "$depth" -name '*.jsonl' -type f 2>/dev/null |
    while IFS= read -r f; do parse_session "$f"; done |
    sort -rn -t "$(printf '\t')" -k1,1
}

render_list() {
  awk -F'\t' -v cyan="$CYAN" -v yellow="$YELLOW" -v reset="$RESET" \
    -v now="$(date +%s)" -v threshold="$ACTIVE_THRESHOLD_SEC" '
    {if ($6 != "") label = "★ " $6; else if ($7 != "") label = $7; else label = $8
     status = ((now - $1) < threshold) ? yellow "  ● active" reset : ""
     printf "%s[%3d]%s %s  %-18s %6s  %s…  %s%s\n", cyan, NR, reset, $2, $3, $4, substr($5,1,8), label, status
    }'
}

render_json() {
  jq -Rn '[inputs | split("\t") | {
    modified_at: .[1], project: .[2], size: .[3], uuid: .[4],
    label: (if .[5] != "" then .[5] elif .[6] != "" then .[6] else .[7] end)
  }]'
}

header() {
  printf '\n%s%s  ◆ Claude Session Cleaner%s %sv%s%s\n' "$BOLD" "$CYAN" "$RESET" "$DIM" "$VERSION" "$RESET"
  printf '%s  Safe space for unfinished conversations.%s\n\n' "$DIM" "$RESET"
}

cmd_list() {
  local pattern="${1:-}" tsv total
  tsv=$(collect_tsv)
  if [ -n "$pattern" ] && [ -n "$tsv" ]; then
    tsv=$(printf '%s\n' "$tsv" | grep -i -- "$pattern" || true)
  fi
  if [ "$JSON" -eq 1 ]; then printf '%s\n' "$tsv" | awk 'NF' | render_json; return; fi
  if [ -z "$tsv" ]; then
    if [ -n "$pattern" ]; then echo "No sessions found matching '$pattern'."
    else echo "No sessions found."
    fi
    return
  fi
  header
  printf '%s  Sessions%s %s(newest first)%s\n\n' "$BOLD" "$RESET" "$DIM" "$RESET"
  printf '%s\n' "$tsv" | render_list
  total=$(printf '%s\n' "$tsv" | wc -l | tr -d ' ')
  printf '\n%s  %s session(s) · %s scope%s\n' "$DIM" "$total" "$SCOPE" "$RESET"
}

count_files() {
  find "$1" -mindepth 2 -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null | wc -l | tr -d ' '
}
disk_usage() { [ -d "$1" ] && du -sh "$1" 2>/dev/null | awk '{print $1}' || printf '0B'; }

cmd_stats() {
  local sessions projects storage trash
  sessions=$(count_files "$PROJECTS_DIR")
  projects=$(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  storage=$(disk_usage "$PROJECTS_DIR")
  trash=$(find "$TRASH_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  if [ "$JSON" -eq 1 ]; then
    jq -n --argjson sessions "$sessions" --argjson projects "$projects" \
      --arg storage "$storage" --argjson trash "$trash" \
      '{sessions:$sessions, projects:$projects, storage:$storage, trash_items:$trash}'
    return
  fi
  header
  printf '  %s%-12s%s %s%s%s\n' "$BOLD" "Sessions" "$RESET" "$CYAN" "$sessions" "$RESET"
  printf '  %s%-12s%s %s%s%s\n' "$BOLD" "Projects" "$RESET" "$CYAN" "$projects" "$RESET"
  printf '  %s%-12s%s %s%s%s\n' "$BOLD" "Storage" "$RESET" "$CYAN" "$storage" "$RESET"
  printf '  %s%-12s%s %s%s%s\n' "$BOLD" "Trash" "$RESET" "$CYAN" "$trash item(s)" "$RESET"
}

doctor_row() {
  local state="$1" label="$2" detail="$3" icon color
  case "$state" in
    ok) icon="✓"; color="$GREEN" ;;
    warn) icon="!"; color="$YELLOW" ;;
    *) icon="✗"; color="$RED" ;;
  esac
  printf '  %s%s%s  %-16s %s\n' "$color" "$icon" "$RESET" "$label" "$detail"
}

cmd_doctor() {
  local errors=0 os bash_version jq_version sessions trash parent
  header
  printf '%s  Environment check%s\n\n' "$BOLD" "$RESET"

  os=$(uname -s)
  case "$os" in
    Darwin|Linux) doctor_row ok "Platform" "$os" ;;
    *) doctor_row error "Platform" "$os (unsupported)"; errors=$((errors + 1)) ;;
  esac

  bash_version="${BASH_VERSION:-unknown}"
  if [ "${BASH_VERSINFO[0]:-0}" -ge 3 ]; then
    doctor_row ok "Bash" "$bash_version"
  else
    doctor_row error "Bash" "$bash_version (3.2+ required)"
    errors=$((errors + 1))
  fi

  if command -v jq >/dev/null; then
    jq_version=$(jq --version 2>/dev/null || echo unknown)
    doctor_row ok "jq" "$jq_version"
  else
    doctor_row error "jq" "missing — install with brew install jq / apt install jq"
    errors=$((errors + 1))
  fi

  if [ -d "$PROJECTS_DIR" ]; then
    sessions=$(count_files "$PROJECTS_DIR")
    doctor_row ok "Session store" "$sessions session(s) at $PROJECTS_DIR"
  else
    doctor_row warn "Session store" "not found at $PROJECTS_DIR"
  fi

  if [ -d "$CLAUDE_HOME" ]; then parent="$CLAUDE_HOME"; else parent=$(dirname "$CLAUDE_HOME"); fi
  if [ -w "$parent" ]; then
    doctor_row ok "Write access" "$parent"
  else
    doctor_row error "Write access" "$parent is not writable"
    errors=$((errors + 1))
  fi

  trash=$(find "$TRASH_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  doctor_row ok "Recovery trash" "$trash recoverable item(s)"

  case "$ACTIVE_THRESHOLD_SEC" in
    ''|*[!0-9]*)
      doctor_row error "Active guard" "invalid value: $ACTIVE_THRESHOLD_SEC"
      errors=$((errors + 1)) ;;
    *) doctor_row ok "Active guard" "${ACTIVE_THRESHOLD_SEC}s" ;;
  esac

  printf '\n'
  if [ "$errors" -eq 0 ]; then
    printf '  %s%sReady.%s ccsc can safely manage sessions on this machine.\n' "$BOLD" "$GREEN" "$RESET"
  else
    printf '  %s%s%s issue(s) need attention.%s\n' "$BOLD" "$RED" "$errors" "$RESET"
    return 1
  fi
}

parse_duration() {
  local value="$1" number multiplier
  case "$value" in
    *d) number="${value%d}"; multiplier=86400 ;;
    *h) number="${value%h}"; multiplier=3600 ;;
    *m) number="${value%m}"; multiplier=60 ;;
    *) echo "invalid duration: $value (use 30d, 12h, or 90m)" >&2; return 2 ;;
  esac
  case "$number" in ''|*[!0-9]*) echo "invalid duration: $value" >&2; return 2 ;; esac
  [ "$number" -gt 0 ] || { echo "duration must be greater than zero" >&2; return 2; }
  printf '%s' "$((number * multiplier))"
}

cmd_clean() {
  local older_than="" yes=0 seconds cutoff tsv candidates total line path failed=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --older-than)
        [ $# -ge 2 ] || { echo "--older-than needs a duration" >&2; return 2; }
        older_than="$2"; shift 2 ;;
      --yes|-y) yes=1; shift ;;
      *) echo "unknown clean option: $1" >&2; return 2 ;;
    esac
  done
  [ -n "$older_than" ] || { echo "usage: ccsc clean --older-than <30d|12h|90m> [--yes]" >&2; return 2; }
  seconds=$(parse_duration "$older_than") || return
  cutoff=$(($(date +%s) - seconds))
  tsv=$(collect_tsv)
  candidates=$(printf '%s\n' "$tsv" | awk -F'\t' -v cutoff="$cutoff" 'NF && $1 <= cutoff')

  if [ "$JSON" -eq 1 ]; then
    [ "$yes" -eq 0 ] || { echo "--json cannot be combined with clean --yes" >&2; return 2; }
    printf '%s\n' "$candidates" | awk 'NF' | render_json
    return
  fi
  [ -n "$candidates" ] || { echo "No sessions older than $older_than in the selected scope."; return; }

  header
  printf '%s  Cleanup preview%s %s(older than %s)%s\n\n' "$BOLD" "$RESET" "$DIM" "$older_than" "$RESET"
  printf '%s\n' "$candidates" | render_list
  total=$(printf '%s\n' "$candidates" | wc -l | tr -d ' ')
  printf '\n  %s candidate session(s).\n' "$total"
  if [ "$yes" -eq 0 ]; then
    printf '  %sPreview only.%s Re-run with %s--yes%s to move them to recoverable trash.\n' "$YELLOW" "$RESET" "$BOLD" "$RESET"
    return
  fi

  printf '\n'
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path=$(printf '%s' "$line" | cut -f9-)
    trash_session "$path" || failed=$((failed + 1))
  done <<EOF
$candidates
EOF
  [ "$failed" -eq 0 ]
}

resolve_uuid() {
  local prefix="$1" matches count
  case "$prefix" in
    *[!0-9a-fA-F-]*|'') echo "invalid uuid prefix: $prefix" >&2; return 2 ;;
  esac
  matches=$(find "$PROJECTS_DIR" -name "${prefix}*.jsonl" -type f 2>/dev/null)
  count=$(printf '%s\n' "$matches" | awk 'NF' | wc -l | tr -d ' ')
  [ "$count" -eq 0 ] && { echo "no match for uuid prefix: $prefix" >&2; return 2; }
  [ "$count" -gt 1 ] && { echo "ambiguous uuid prefix ($count matches): $prefix" >&2; return 3; }
  printf '%s\n' "$matches"
}

trash_session() {
  local f="$1" uuid mt age now item stem
  uuid=$(basename "$f" .jsonl); mt=$(file_mtime "$f"); now=$(date +%s); age=$((now - mt))
  if [ "$age" -lt "$ACTIVE_THRESHOLD_SEC" ]; then
    echo "refuse: $uuid is active (${age}s ago, < ${ACTIVE_THRESHOLD_SEC}s)" >&2
    return 1
  fi
  if ! mkdir -p "$TRASH_DIR"; then
    echo "error: could not create recovery trash: $TRASH_DIR" >&2
    return 1
  fi
  item="$TRASH_DIR/$(date -u +%Y%m%dT%H%M%SZ)-$uuid"
  [ -e "$item" ] && item="$item-$$"
  if ! mkdir -p "$item"; then
    echo "error: could not create trash entry: $item" >&2
    return 1
  fi
  if ! jq -n --arg uuid "$uuid" --arg original "$f" --arg trashed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{uuid:$uuid, original_path:$original, trashed_at:$trashed_at}' > "$item/metadata.json"; then
    rm -rf "$item"
    echo "error: could not write recovery metadata" >&2
    return 1
  fi
  if ! mv "$f" "$item/session.jsonl"; then
    rm -rf "$item"
    echo "error: could not move transcript to trash" >&2
    return 1
  fi
  stem="${f%.jsonl}"
  if [ -d "$stem" ] && ! mv "$stem" "$item/artifacts"; then
    mv "$item/session.jsonl" "$f" || true
    rm -rf "$item"
    echo "error: could not move derivative artifacts; transcript restored" >&2
    return 1
  fi
  printf '%strashed:%s %s %s(restore with: ccsc restore %s)%s\n' "$GREEN" "$RESET" "$f" "$DIM" "${uuid:0:8}" "$RESET"
}

cmd_trash() {
  [ $# -gt 0 ] || { echo "usage: ccsc trash <uuid>..." >&2; return 2; }
  local u f failed=0
  for u in "$@"; do
    if f=$(resolve_uuid "$u"); then trash_session "$f" || failed=$((failed + 1))
    else failed=$((failed + 1)); fi
  done
  [ "$failed" -eq 0 ]
}

list_trash() {
  local item meta count=0
  [ -d "$TRASH_DIR" ] || { echo "Trash is empty."; return; }
  header
  printf '%s  Recoverable sessions%s\n\n' "$BOLD" "$RESET"
  for item in "$TRASH_DIR"/*; do
    [ -d "$item" ] || continue; meta="$item/metadata.json"; [ -f "$meta" ] || continue
    count=$((count + 1))
    printf '%s[%3d]%s %s…  %-20s  %s\n' "$CYAN" "$count" "$RESET" \
      "$(jq -r '.uuid[0:8]' "$meta")" "$(jq -r '.trashed_at' "$meta")" \
      "$(basename "$(dirname "$(jq -r '.original_path' "$meta")")")"
  done
  [ "$count" -eq 0 ] && echo "Trash is empty."
}

find_trash_item() {
  local prefix="$1" item matches="" uuid count
  case "$prefix" in
    *[!0-9a-fA-F-]*|'') echo "invalid uuid prefix: $prefix" >&2; return 2 ;;
  esac
  [ -d "$TRASH_DIR" ] || return 2
  for item in "$TRASH_DIR"/*; do
    [ -f "$item/metadata.json" ] || continue
    uuid=$(jq -r '.uuid' "$item/metadata.json")
    case "$uuid" in "$prefix"*) matches="${matches}${item}\n" ;; esac
  done
  count=$(printf '%b' "$matches" | awk 'NF' | wc -l | tr -d ' ')
  [ "$count" -eq 0 ] && { echo "no trash match for uuid prefix: $prefix" >&2; return 2; }
  [ "$count" -gt 1 ] && { echo "ambiguous trash prefix ($count matches): $prefix" >&2; return 3; }
  printf '%b' "$matches" | awk 'NF'
}

cmd_restore() {
  [ $# -eq 0 ] && { list_trash; return; }
  [ $# -eq 1 ] || { echo "restore accepts one uuid at a time" >&2; return 2; }
  local item original parent stem
  item=$(find_trash_item "$1") || return
  original=$(jq -r '.original_path' "$item/metadata.json")
  [ ! -e "$original" ] || { echo "refuse: destination already exists: $original" >&2; return 1; }
  stem="${original%.jsonl}"
  [ ! -e "$stem" ] || { echo "refuse: artifact destination already exists: $stem" >&2; return 1; }
  parent=$(dirname "$original")
  if ! mkdir -p "$parent" || ! mv "$item/session.jsonl" "$original"; then
    echo "error: could not restore transcript" >&2
    return 1
  fi
  if [ -d "$item/artifacts" ] && ! mv "$item/artifacts" "$stem"; then
    mv "$original" "$item/session.jsonl" || true
    echo "error: could not restore artifacts; transcript returned to trash" >&2
    return 1
  fi
  rm -rf "$item"
  printf '%srestored:%s %s\n' "$GREEN" "$RESET" "$original"
}

cmd_purge() {
  [ $# -eq 1 ] || { echo "usage: ccsc purge <uuid>|--all" >&2; return 2; }
  local item
  if [ "$1" = "--all" ]; then
    [ -d "$TRASH_DIR" ] && find "$TRASH_DIR" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +
    echo "purged: all trash entries"; return
  fi
  item=$(find_trash_item "$1") || return
  rm -rf "$item"; echo "purged: $1"
}

cmd_interactive() {
  local tsv total selection expanded="" tok a b i n line uuid confirm
  tsv=$(collect_tsv); [ -n "$tsv" ] || { echo "No sessions found."; return; }
  header
  printf '%s  Sessions%s %s(select one or more to move to trash)%s\n\n' "$BOLD" "$RESET" "$DIM" "$RESET"
  printf '%s\n' "$tsv" | render_list
  total=$(printf '%s\n' "$tsv" | wc -l | tr -d ' ')
  printf '\n%sSelect%s %s(1 3 5, 2-6, or Enter to cancel)%s: ' "$BOLD" "$RESET" "$DIM" "$RESET"
  read -r selection
  [ -z "$selection" ] && { echo "Cancelled."; return; }
  for tok in $selection; do
    if [[ "$tok" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      a="${BASH_REMATCH[1]}"; b="${BASH_REMATCH[2]}"; [ "$a" -gt "$b" ] && { i=$a; a=$b; b=$i; }
      for ((i=a; i<=b; i++)); do expanded="$expanded $i"; done
    elif [[ "$tok" =~ ^[0-9]+$ ]]; then expanded="$expanded $tok"
    else echo "Skipping invalid selection: $tok" >&2; fi
  done
  [ -n "$expanded" ] || { echo "Nothing selected."; return; }
  printf '\n%sMove selected sessions to recoverable trash?%s [y/N] ' "$YELLOW" "$RESET"
  read -r confirm
  case "$confirm" in y|Y|yes|YES) ;; *) echo "Cancelled."; return ;; esac
  for n in $expanded; do
    if [ "$n" -lt 1 ] || [ "$n" -gt "$total" ]; then
      echo "Skipping out-of-range: $n"
      continue
    fi
    line=$(printf '%s\n' "$tsv" | sed -n "${n}p"); uuid=$(printf '%s' "$line" | cut -f5)
    cmd_trash "$uuid" || true
  done
}

while [ $# -gt 0 ]; do
  case "$1" in
    --all|-a) SCOPE="all"; shift ;;
    --project|-p) [ $# -ge 2 ] || { echo "$1 needs a path" >&2; exit 2; }; PROJECT_PATH="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    --no-color) NO_COLOR=1; BOLD=''; DIM=''; CYAN=''; GREEN=''; YELLOW=''; RED=''; RESET=''; shift ;;
    --help|-h|help) usage; exit 0 ;;
    --version|-v) echo "ccsc $VERSION"; exit 0 ;;
    list|stats|doctor|clean|trash|delete|restore|purge|interactive) break ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

case "${1:-interactive}" in
  doctor) shift; cmd_doctor "$@" ;;
  list) shift; validate_config && require_jq && cmd_list "$@" ;;
  stats) shift; validate_config && require_jq && cmd_stats "$@" ;;
  clean) shift; validate_config && require_jq && cmd_clean "$@" ;;
  trash|delete) shift; validate_config && require_jq && cmd_trash "$@" ;;
  restore) shift; validate_config && require_jq && cmd_restore "$@" ;;
  purge) shift; validate_config && require_jq && cmd_purge "$@" ;;
  interactive|"") validate_config && require_jq && cmd_interactive ;;
  *) echo "unknown command: $1" >&2; usage >&2; exit 2 ;;
esac
