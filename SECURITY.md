# Security Policy

Claude Session Cleaner handles local conversation files, so path validation, restore conflicts, and deletion boundaries are security-sensitive.

## Reporting a vulnerability

Please do not open a public issue for vulnerabilities that could cause unintended file access, session loss, command injection, or unsafe path handling.

Use GitHub’s private vulnerability reporting for this repository, or contact the maintainer through the address listed in the repository commit history. Include:

- affected command and version;
- operating system and Bash version;
- minimal reproduction using a temporary `CLAUDE_HOME`;
- expected and actual filesystem changes.

Do not include real conversation content, credentials, or private filesystem paths.

## Scope

Security fixes are prioritized for the latest version on `main`. The project does not transmit session content or operate a hosted service; all processing is local.
