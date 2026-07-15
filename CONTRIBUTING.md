# Contributing

Thanks for helping make Claude Code session management safer. Small, focused pull requests are easiest to review.

## Development setup

```bash
git clone https://github.com/ihoooohi/claude-code-session-cleaner.git
cd claude-code-session-cleaner
bash tests/test.sh
```

The test suite creates a temporary `CLAUDE_HOME`. It must never inspect, move, or delete sessions from your real `~/.claude` directory.

## Before opening a pull request

```bash
bash -n scripts/delete-session.sh install.sh uninstall.sh tests/test.sh
shellcheck scripts/delete-session.sh install.sh uninstall.sh tests/test.sh
bash tests/test.sh
```

Please update both `README.md` and `README_CN.md` when user-facing behavior changes.

## Safety invariants

Changes must preserve these rules:

1. Recently active sessions are refused.
2. Ambiguous UUID prefixes never resolve automatically.
3. Transcript and derivative artifacts move together or roll back.
4. Restore never overwrites an existing destination.
5. Bulk cleanup previews before mutation.
6. Permanent deletion remains separate from recoverable trash.

## Pull requests

- Explain the user-visible behavior and motivation.
- Add an isolated integration test for filesystem behavior.
- Keep Bash 3.2 compatibility for the macOS system shell.
- Avoid new runtime dependencies unless the benefit clearly outweighs installation cost.

By contributing, you agree that your work is licensed under the project’s [MIT License](./LICENSE).
