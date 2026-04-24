# claude-code-session-cleaner

A stopgap tool to **list and delete Claude Code CLI session files** until the
official `/delete` command (tracked in
[anthropics/claude-code#26904](https://github.com/anthropics/claude-code/issues/26904))
lands.

Works as **both** a standalone shell script (interactive) and a Claude Code
slash command (conversational).

---

## Why this exists

Claude Code has no built-in way to delete a saved session. When the list in
`/resume` gets noisy, or a session contains an accidentally-pasted secret,
the only workaround is to:

1. Exit Claude Code
2. `cd ~/.claude/projects/`
3. Figure out which `<encoded-path>/<uuid>.jsonl` file corresponds to the session
4. `rm` it — and remember to also clean the sibling `<uuid>/` directory holding
   subagents / tool-results / memory (otherwise you leave orphan artifacts)

This tool does all of that, safely, with the same labels you see in `/resume`.

## What it shows

```
[  1] 2026-04-24 18:17  EchoCenter    728K  bcf9c007…  我觉得你01地图做的不好，不够通俗易懂…
[  2] 2026-04-24 08:02  EchoCenter     24K  34738f62…  拉一下最新的仓库
[  3] 2026-04-22 10:07  HERTCERT       31M  9f362cce…  ★ fix-v2-production-stability
```

Each row: **index** · **mtime** · **project** · **file size** · **uuid prefix** ·
**label**. Label priority matches `/resume`:

1. `★ <name>` — `custom-title` set via `/rename` in Claude Code
2. `last-prompt` — the most recent user prompt (what `/resume` shows)
3. The last user message (minus auto-injected wrappers)

---

## Installation

### Prerequisites

- Bash 3.2+ (macOS default works)
- `jq` ([install](https://jqlang.org/download/))

### Option A — one command

```bash
git clone https://github.com/ihoooohi/claude-code-session-cleaner.git
cd claude-code-session-cleaner
./install.sh
```

This copies:

- `scripts/delete-session.sh` → `~/.claude/scripts/delete-session.sh`
- `commands/delete-session.md` → `~/.claude/commands/delete-session.md`

It **will not overwrite** existing files unless you pass `--force`.

### Option B — manual

```bash
cp scripts/delete-session.sh   ~/.claude/scripts/
cp commands/delete-session.md  ~/.claude/commands/
chmod +x ~/.claude/scripts/delete-session.sh
```

---

## Usage

### From the terminal (interactive)

```bash
~/.claude/scripts/delete-session.sh
```

Default scope is **only the current project** (derived from `$PWD`). The script
shows a numbered list, then prompts for indexes:

```
Enter indexes to delete (e.g. '1 3 5' or '1-4'; empty to quit): 2 5-7
```

Supports:

- `1 3 5` — individual indexes
- `1-4` — ranges
- `1 3-5 9` — mixed
- Empty input — cancel

After confirmation (`y/N`), each selected file and its sibling `<uuid>/`
directory are deleted.

### From the terminal (non-interactive)

```bash
~/.claude/scripts/delete-session.sh list                   # current project
~/.claude/scripts/delete-session.sh list pattern           # filter by substring
~/.claude/scripts/delete-session.sh --all list             # every project
~/.claude/scripts/delete-session.sh --project /path list   # specific project
~/.claude/scripts/delete-session.sh delete <uuid>...       # delete by uuid (prefix ok)
```

### From Claude Code

Type `/delete-session` in a conversation:

```
/delete-session                # list current project, then pick
/delete-session fix-v2         # filter by keyword
/delete-session --all          # scan everything
/delete-session 9c8dbd97       # jump straight to uuid confirmation
```

Claude lists the candidates, asks you which to delete (`1 3-5`, `除 X 外全部`,
`all`, etc.), shows a summary, and waits for confirmation before calling the
script's non-interactive `delete` mode.

---

## Safety

**Active-session protection.** Sessions with `mtime < 10 minutes` are refused:

```
refuse: 01c3a07b-a25b-4aed-9c66-26eb29f64d26 is active (142s ago, < 600s)
```

The running session updates its `.jsonl` on every message, so it nearly always
trips this guard. To raise or lower the threshold, edit
`ACTIVE_THRESHOLD_SEC` at the top of the script.

**Derivative cleanup.** Claude Code stores subagent transcripts, tool results,
and scoped memory at `~/.claude/projects/<project>/<uuid>/` (a directory with
the same stem as the main `.jsonl`). When this tool deletes a main session, it
also removes that sibling directory — otherwise those files would live on as
orphans.

**UUID prefix disambiguation.** `delete abc12345` refuses if the prefix matches
zero or multiple sessions. No "it probably means this one" guessing.

**Two-step confirmation in the slash command.** Claude always lists the
resolved files to you before calling `delete`.

---

## Reverse-engineering notes

To make labels match `/resume`, this tool reads Claude Code's session JSONL
format directly. Three record types matter:

| `type`           | When written                                     | Used as label           |
| ---------------- | ------------------------------------------------ | ----------------------- |
| `custom-title`   | Each time you run `/rename`. Multiple records are appended; the most recent wins. | `★ <customTitle>` |
| `last-prompt`    | On every new user message. Takes precedence for sessions created by recent Claude Code versions. | `<lastPrompt>` |
| `user`           | Every user message (including auto-injected `<local-command-caveat>` / `<command-name>/clear</command-name>` wrappers). | Fallback: last non-wrapper content |

This matches what `/resume` surfaces in practice (verified across 10+ real
sessions). If Claude Code changes its storage format, update `custom_title()`,
`last_prompt()`, and `last_user_message()` in the script.

---

## Known limits

- **Can't delete the session you're currently in** — the active-session guard
  rejects it. Do it from another terminal.
- **macOS and Linux only.** Uses BSD `stat -f %m` and `date -r`. Not yet tested
  on other BSDs. Contributions welcome.
- **No `--older-than 30d`** yet. If you want bulk purge by age, open an issue.
- **No undo.** This is `rm`, not a trash bin. Confirmation is the safety net.

---

## Uninstall

```bash
rm ~/.claude/scripts/delete-session.sh
rm ~/.claude/commands/delete-session.md
```

---

## Upstream

When Claude Code ships an official delete command, this tool becomes
redundant — that's the goal. Track progress at
[anthropics/claude-code#26904](https://github.com/anthropics/claude-code/issues/26904).

## License

[MIT](./LICENSE).
