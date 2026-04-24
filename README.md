<div align="center">

# claude-code-session-cleaner

[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](./LICENSE)
[![Language](https://img.shields.io/badge/language-Bash-4EAA25.svg)](https://www.gnu.org/software/bash/)

[**English**](./README.md) | [**中文**](./README_CN.md)

</div>

---

## Project Overview

`claude-code-session-cleaner` lists and deletes Claude Code CLI session files
from `~/.claude/projects/`. It is a local cleanup helper for saved sessions and
can run as either:

- a standalone interactive shell script
- a Claude Code slash command: `/delete-session`

The tool uses the same practical labels you see in `/resume`, so you can delete
old sessions by title, recent prompt, project, or UUID prefix without manually
digging through encoded project directories.

## Features

- Lists sessions newest first for the current project by default.
- Supports `--all` to scan every Claude Code project.
- Shows index, modified time, project name, file size, UUID prefix, and label.
- Uses label priority compatible with `/resume`: custom title, last prompt, then
  fallback user message.
- Deletes the selected `.jsonl` file and its sibling `<uuid>/` artifact
  directory.
- Refuses to delete sessions modified in the last 10 minutes to avoid removing
  an active session.
- Resolves UUID prefixes safely and refuses ambiguous matches.
- Installs both the shell script and Claude Code slash command with one command.

## Project Structure

```text
.
├── commands/
│   └── delete-session.md      # Claude Code slash command
├── scripts/
│   └── delete-session.sh      # Session listing and deletion script
├── install.sh                 # Installer for ~/.claude/scripts and ~/.claude/commands
├── LICENSE
├── README.md
└── README_CN.md
```

## Requirements

- macOS shell environment
- Bash 3.2 or newer
- `jq`
- Claude Code session data under `~/.claude/projects/`

Install `jq` on macOS:

```bash
brew install jq
```

## Quick Start

Clone the repository and install the script plus slash command:

```bash
git clone https://github.com/ihoooohi/claude-code-session-cleaner.git
cd claude-code-session-cleaner
./install.sh
```

The installer copies:

- `scripts/delete-session.sh` to `~/.claude/scripts/delete-session.sh`
- `commands/delete-session.md` to `~/.claude/commands/delete-session.md`

It will not overwrite existing files unless you pass `--force`.

## Usage

Run interactively from a terminal:

```bash
~/.claude/scripts/delete-session.sh
```

List sessions without deleting anything:

```bash
~/.claude/scripts/delete-session.sh list
~/.claude/scripts/delete-session.sh list fix-v2
~/.claude/scripts/delete-session.sh --all list
~/.claude/scripts/delete-session.sh --project /path/to/project list
```

Delete by UUID or UUID prefix:

```bash
~/.claude/scripts/delete-session.sh delete 9c8dbd97
```

Use it inside Claude Code:

```text
/delete-session
/delete-session fix-v2
/delete-session --all
/delete-session 9c8dbd97
```

## Core Flow

1. The script derives the current project from `$PWD`, unless you pass `--all`
   or `--project`.
2. It maps the project path to Claude Code's encoded directory format under
   `~/.claude/projects/`.
3. It reads only top-level `*.jsonl` session files, not nested artifact files.
4. It builds labels from session records in this order:
   `custom-title`, `last-prompt`, then the last non-wrapper user message.
5. It renders a numbered list for review.
6. On deletion, it confirms the target, refuses active sessions, removes the
   main `.jsonl`, and removes the sibling `<uuid>/` artifact directory if it
   exists.

## Minimal Example

Example list output:

```text
[  1] 2026-04-24 18:17  EchoCenter           728K  bcf9c007...  Update map labels
[  2] 2026-04-24 08:02  EchoCenter            24K  34738f62...  Pull the latest repo
[  3] 2026-04-22 10:07  HERTCERT              31M  9f362cce...  ★ fix-v2-production-stability
```

Interactive deletion accepts individual indexes and ranges:

```text
Enter indexes to delete (e.g. '1 3 5' or '1-4'; empty to quit): 2 5-7
```

## Safety Notes

- The active-session guard refuses sessions modified less than 10 minutes ago.
- `delete <uuid-prefix>` refuses if the prefix matches zero or multiple files.
- The slash command asks for confirmation before calling the deletion script.
- Linux is not verified because the script currently uses BSD/macOS `stat` and
  `date` flags.
- There is no undo. Deleted files are removed with `rm`.

## Uninstall

```bash
rm ~/.claude/scripts/delete-session.sh
rm ~/.claude/commands/delete-session.md
```

## License

This project is released under the [MIT License](./LICENSE).
