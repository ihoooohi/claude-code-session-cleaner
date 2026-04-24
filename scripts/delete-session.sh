#!/usr/bin/env bash
# delete-session.sh — 列出并删除 Claude Code 历史 session 文件
#
# Sessions live at ~/.claude/projects/<encoded-path>/<uuid>.jsonl
# where <encoded-path> is the absolute path with every "/" replaced by "-".
#
# Scope:
#   Default:           only current project (derived from $PWD)
#   --all / -a:        every project
#   --project <path>:  override project path (default $PWD)
#
# Display priority for each session's label:
#   1. custom-title set via `/rename` in Claude Code (★ prefix)
#   2. first user message (wrappers like <local-command-caveat> skipped)
#
# Usage:
#   delete-session.sh                           # interactive (current project)
#   delete-session.sh list [pattern]            # list-only, optional substring grep
#   delete-session.sh --all list [pattern]      # list every project
#   delete-session.sh --project <path> list     # list a specific project
#   delete-session.sh delete <uuid>...          # non-interactive delete by uuid (prefix ok)
#
# Safety:
#   Sessions with mtime < ACTIVE_THRESHOLD_SEC are refused (likely the running session).

set -u

PROJECTS_DIR="$HOME/.claude/projects"
ACTIVE_THRESHOLD_SEC=600   # 10 minutes

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

# Encode an absolute path the way Claude Code stores it: every "/" -> "-".
encode_path() {
  printf '%s' "$1" | sed 's:/:-:g'
}

# Last user message (matching /resume's fallback when no `last-prompt` record exists).
# Skips auto-injected wrappers; falls back to raw last line if all messages are wrappers.
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

# Last `/rename` wins (Claude Code appends a new custom-title record each rename).
custom_title() {
  jq -r 'select(.type=="custom-title") | .customTitle // empty' "$1" 2>/dev/null | tail -1
}

# What /resume shows: the most recent user prompt in this session.
# Claude Code appends a `last-prompt` record on every user message, so `tail -1`
# gives the current /resume label.
last_prompt() {
  jq -r 'select(.type=="last-prompt") | .lastPrompt // empty' "$1" 2>/dev/null \
    | awk 'NF' | tail -1 | tr '\n\t' '  ' | cut -c 1-70
}

short_project() {
  local raw="$1"
  case "$raw" in
    ssh-*) printf '%s' "$raw" ;;
    -*)    local last="${raw##*-}"
           [ -z "$last" ] && last="$raw"
           printf '%s' "$last" ;;
    *)     printf '%s' "$raw" ;;
  esac
}

# TSV row: mtime_epoch<TAB>mtime_str<TAB>project<TAB>size<TAB>uuid<TAB>title<TAB>last_prompt<TAB>first_msg
parse_session() {
  local f="$1"
  local uuid proj proj_short mt mt_str size title last msg
  uuid=$(basename "$f" .jsonl)
  proj=$(basename "$(dirname "$f")")
  proj_short=$(short_project "$proj")
  mt=$(stat -f %m "$f" 2>/dev/null)
  [ -z "$mt" ] && mt=0
  mt_str=$(date -r "$mt" "+%Y-%m-%d %H:%M" 2>/dev/null)
  size=$(du -h "$f" 2>/dev/null | awk '{print $1}')
  title=$(custom_title "$f")
  last=$(last_prompt "$f")
  msg=$(last_user_message "$f")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$mt" "$mt_str" "$proj_short" "$size" "$uuid" "$title" "$last" "$msg"
}

# SCOPE ∈ {current, all}. When current, PROJECT_PATH scopes to that project's dir.
collect_tsv() {
  local root
  if [ "$SCOPE" = "current" ]; then
    local encoded; encoded=$(encode_path "$PROJECT_PATH")
    root="$PROJECTS_DIR/$encoded"
    if [ ! -d "$root" ]; then
      echo "No sessions directory for '$PROJECT_PATH' (looked at $root)." >&2
      echo "Hint: pass --all to scan every project." >&2
      return 0
    fi
  else
    root="$PROJECTS_DIR"
  fi
  # -maxdepth 2: PROJECTS_DIR/<project>/<uuid>.jsonl is exactly 2 levels deep
  # from PROJECTS_DIR. We do NOT recurse into <uuid>/subagents/ etc — those are
  # derivative artifacts of a main session, not separately-resumable sessions.
  local depth
  if [ "$SCOPE" = "current" ]; then depth=1; else depth=2; fi
  find "$root" -maxdepth "$depth" -name "*.jsonl" -type f 2>/dev/null | while read -r f; do
    parse_session "$f"
  done | sort -rn -t $'\t' -k1,1
}

# Render TSV into the pretty indexed list.
# Label priority: custom-title (★) > last-prompt (what /resume shows) > first user msg.
render_list() {
  awk -F'\t' '{
    # 1=mt_epoch 2=mt_str 3=project 4=size 5=uuid 6=title 7=last_prompt 8=first_msg
    if ($6 != "")      label = "★ " $6
    else if ($7 != "") label = $7
    else               label = $8
    printf "[%3d] %s  %-18s %6s  %s…  %s\n", NR, $2, $3, $4, substr($5,1,8), label
  }'
}

print_scope_footer() {
  local total="$1"
  if [ "$SCOPE" = "current" ]; then
    echo "Total: $total session(s) in $(basename "$PROJECT_PATH")  [use --all for every project]"
  else
    echo "Total: $total session(s) across all projects"
  fi
}

print_empty_scope_note() {
  if [ "$SCOPE" = "current" ]; then
    echo "No sessions in $(basename "$PROJECT_PATH"). Use --all for every project."
  else
    echo "No sessions found."
  fi
}

cmd_list() {
  local pattern="${1:-}"
  local tsv
  tsv=$(collect_tsv)
  if [ -z "$tsv" ]; then
    print_empty_scope_note
    return 0
  fi
  if [ -n "$pattern" ]; then
    tsv=$(echo "$tsv" | grep -i -- "$pattern" || true)
    [ -z "$tsv" ] && { echo "No sessions match: $pattern"; return 0; }
  fi
  echo "$tsv" | render_list
  local total
  total=$(echo "$tsv" | wc -l | tr -d ' ')
  echo ""
  print_scope_footer "$total"
}

resolve_uuid() {
  local prefix="$1"
  local matches
  matches=$(find "$PROJECTS_DIR" -name "${prefix}*.jsonl" -type f 2>/dev/null)
  local count
  count=$(printf '%s\n' "$matches" | awk 'NF' | wc -l | tr -d ' ')
  if [ "$count" -eq 0 ]; then
    echo "no match for uuid prefix: $prefix" >&2; return 2
  elif [ "$count" -gt 1 ]; then
    echo "ambiguous uuid prefix (matches $count files): $prefix" >&2; return 3
  fi
  printf '%s\n' "$matches" | awk 'NF'
}

cmd_delete() {
  [ $# -eq 0 ] && { echo "usage: delete-session.sh delete <uuid>..." >&2; return 2; }
  local now; now=$(date +%s)
  local failed=0
  for u in "$@"; do
    local f
    if ! f=$(resolve_uuid "$u"); then failed=$((failed+1)); continue; fi
    local mt; mt=$(stat -f %m "$f" 2>/dev/null || echo 0)
    local age=$((now - mt))
    if [ "$age" -lt "$ACTIVE_THRESHOLD_SEC" ]; then
      echo "refuse: $(basename "$f" .jsonl) is active (${age}s ago, < ${ACTIVE_THRESHOLD_SEC}s)" >&2
      failed=$((failed+1)); continue
    fi
    if rm -- "$f"; then
      echo "deleted: $f"
      # Clean up the sibling <uuid>/ directory (subagents/, tool-results/, memory/).
      local stem="${f%.jsonl}"
      if [ -d "$stem" ]; then
        if rm -rf -- "$stem"; then
          echo "deleted: $stem/ (derivative artifacts)"
        else
          echo "warn: could not remove $stem/" >&2
        fi
      fi
    else
      echo "rm failed: $f" >&2
      failed=$((failed+1))
    fi
  done
  return "$failed"
}

cmd_interactive() {
  local tsv
  tsv=$(collect_tsv)
  if [ -z "$tsv" ]; then
    print_empty_scope_note
    return 0
  fi

  echo ""
  echo "Sessions (newest first):"
  echo "$tsv" | render_list
  local total
  total=$(echo "$tsv" | wc -l | tr -d ' ')
  echo ""
  print_scope_footer "$total"
  echo ""

  read -r -p "Enter indexes to delete (e.g. '1 3 5' or '1-4'; empty to quit): " selection
  [ -z "$selection" ] && { echo "Cancelled."; return 0; }

  local expanded=""
  for tok in $selection; do
    if [[ "$tok" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local a="${BASH_REMATCH[1]}" b="${BASH_REMATCH[2]}"
      if [ "$a" -gt "$b" ]; then local t=$a; a=$b; b=$t; fi
      for ((i=a; i<=b; i++)); do expanded="$expanded $i"; done
    elif [[ "$tok" =~ ^[0-9]+$ ]]; then
      expanded="$expanded $tok"
    else
      echo "Skipping non-numeric token: $tok"
    fi
  done

  local now; now=$(date +%s)
  local files=()
  for n in $expanded; do
    if [ "$n" -lt 1 ] || [ "$n" -gt "$total" ]; then
      echo "Skipping out-of-range: $n"; continue
    fi
    local line mt uuid proj
    line=$(echo "$tsv" | sed -n "${n}p")
    mt=$(echo "$line"  | cut -f1)
    proj=$(echo "$line" | cut -f3)
    uuid=$(echo "$line" | cut -f5)
    local age=$((now - mt))
    if [ "$age" -lt "$ACTIVE_THRESHOLD_SEC" ]; then
      echo "⚠️  [$n] $proj/${uuid:0:8} was active $((age/60))m ago — likely your current session. Skipping."
      continue
    fi
    local f
    f=$(find "$PROJECTS_DIR" -name "$uuid.jsonl" -type f | head -1)
    [ -z "$f" ] && { echo "Not found on disk: $uuid"; continue; }
    files+=("$f")
  done

  [ ${#files[@]} -eq 0 ] && { echo "Nothing to delete."; return 0; }

  echo ""
  echo "Will delete ${#files[@]} file(s):"
  for f in "${files[@]}"; do echo "  $f"; done
  echo ""
  read -r -p "Confirm? [y/N] " confirm
  case "$confirm" in
    y|Y|yes|YES)
      for f in "${files[@]}"; do
        rm -v -- "$f"
        local stem="${f%.jsonl}"
        [ -d "$stem" ] && rm -rfv -- "$stem" | tail -1
      done
      echo "✓ Done."
      ;;
    *) echo "Cancelled." ;;
  esac
}

# ---- parse top-level flags before the subcommand ----
SCOPE="current"
PROJECT_PATH="$PWD"

while [ $# -gt 0 ]; do
  case "$1" in
    --all|-a)        SCOPE="all"; shift ;;
    --project)
      [ $# -ge 2 ] || { echo "--project needs a path" >&2; exit 2; }
      PROJECT_PATH="$2"; shift 2 ;;
    -h|--help|help)  sed -n '1,/^set -u/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    list|delete|interactive) break ;;
    -*)              echo "unknown flag: $1" >&2; exit 2 ;;
    *)               break ;;
  esac
done

case "${1:-interactive}" in
  list)           shift || true; cmd_list "$@" ;;
  delete)         shift; cmd_delete "$@" ;;
  interactive|"") cmd_interactive ;;
  *)              echo "unknown subcommand: $1" >&2; exit 2 ;;
esac
