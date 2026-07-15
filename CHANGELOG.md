# Changelog

All notable changes to this project are documented here.

## [2.1.0] - 2026-07-15

### Added

- Safe age-based cleanup policies with preview-first `clean --older-than`
- `doctor` command for dependency, platform, storage, permission, and trash diagnostics
- Visible active-session status in the terminal browser
- Professional command reference, design notes, FAQ, and open-source policies

### Changed

- Expanded isolated integration coverage to include diagnostics and policy cleanup
- Refined repository metadata, issue forms, and bilingual project presentation

## [2.0.0] - 2026-07-15

### Added

- Recoverable local trash with `trash`, `restore`, and `purge` commands
- Branded interactive terminal interface and storage statistics
- Machine-readable JSON list and stats output
- Cross-platform file timestamp support for macOS and Linux
- Isolated integration tests, ShellCheck, and two-platform GitHub Actions CI
- English and Chinese documentation with project artwork

### Changed

- `delete` is now a backward-compatible alias for recoverable `trash`
- Installer exposes the short `ccsc` command through `~/.local/bin`
