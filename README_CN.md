<div align="center">

# claude-code-session-cleaner

[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](./LICENSE)
[![Language](https://img.shields.io/badge/language-Bash-4EAA25.svg)](https://www.gnu.org/software/bash/)

[**English**](./README.md) | [**中文**](./README_CN.md)

</div>

---

## 项目概览

`claude-code-session-cleaner` 用于列出并删除 `~/.claude/projects/` 下的
Claude Code CLI 历史 session 文件。它是一个本地 session 清理工具，支持两种方式：

- 独立的交互式 shell 脚本
- Claude Code 斜杠命令：`/delete-session`

工具会尽量使用你在 `/resume` 中看到的同类标签，因此可以按标题、最近提示词、项目或 UUID
前缀识别并删除旧 session，而不需要手动查找编码后的项目目录。

## 功能特性

- 默认只列出当前项目的 session，并按修改时间从新到旧排序。
- 支持 `--all` 扫描所有 Claude Code 项目。
- 显示序号、修改时间、项目名、文件大小、UUID 前缀和标签。
- 标签优先级与 `/resume` 的实际表现保持一致：自定义标题、最近提示词、兜底用户消息。
- 删除选中的 `.jsonl` 文件，并同步清理同名 `<uuid>/` 衍生产物目录。
- 拒绝删除最近 10 分钟内修改过的 session，避免误删活跃 session。
- 安全解析 UUID 前缀，遇到歧义匹配会拒绝执行。
- 一条安装命令同时安装 shell 脚本和 Claude Code 斜杠命令。

## 项目结构

```text
.
├── commands/
│   └── delete-session.md      # Claude Code 斜杠命令
├── scripts/
│   └── delete-session.sh      # session 列出与删除脚本
├── install.sh                 # 安装到 ~/.claude/scripts 和 ~/.claude/commands
├── LICENSE
├── README.md
└── README_CN.md
```

## 环境要求

- macOS shell 环境
- Bash 3.2 或更新版本
- `jq`
- `~/.claude/projects/` 下已有 Claude Code session 数据

macOS 安装 `jq`：

```bash
brew install jq
```

## 快速开始

克隆仓库并安装脚本和斜杠命令：

```bash
git clone https://github.com/ihoooohi/claude-code-session-cleaner.git
cd claude-code-session-cleaner
./install.sh
```

安装脚本会复制：

- `scripts/delete-session.sh` 到 `~/.claude/scripts/delete-session.sh`
- `commands/delete-session.md` 到 `~/.claude/commands/delete-session.md`

除非传入 `--force`，否则不会覆盖已有文件。

## 使用方法

在终端中交互式运行：

```bash
~/.claude/scripts/delete-session.sh
```

只列出 session，不删除任何内容：

```bash
~/.claude/scripts/delete-session.sh list
~/.claude/scripts/delete-session.sh list fix-v2
~/.claude/scripts/delete-session.sh --all list
~/.claude/scripts/delete-session.sh --project /path/to/project list
```

按 UUID 或 UUID 前缀删除：

```bash
~/.claude/scripts/delete-session.sh delete 9c8dbd97
```

在 Claude Code 中使用：

```text
/delete-session
/delete-session fix-v2
/delete-session --all
/delete-session 9c8dbd97
```

## 核心流程

1. 脚本默认从 `$PWD` 推导当前项目，除非传入 `--all` 或 `--project`。
2. 它把项目路径映射为 Claude Code 在 `~/.claude/projects/` 下使用的编码目录名。
3. 它只读取顶层 `*.jsonl` 主 session 文件，不会把嵌套的衍生产物当成独立 session。
4. 它按顺序生成标签：`custom-title`、`last-prompt`、最后一条非包装器用户消息。
5. 它渲染可检查的编号列表。
6. 删除时会确认目标，拒绝活跃 session，删除主 `.jsonl` 文件，并在存在时删除同名
   `<uuid>/` 衍生产物目录。

## 最小示例

列表输出示例：

```text
[  1] 2026-04-24 18:17  EchoCenter           728K  bcf9c007...  Update map labels
[  2] 2026-04-24 08:02  EchoCenter            24K  34738f62...  Pull the latest repo
[  3] 2026-04-22 10:07  HERTCERT              31M  9f362cce...  ★ fix-v2-production-stability
```

交互式删除支持单个序号和范围：

```text
Enter indexes to delete (e.g. '1 3 5' or '1-4'; empty to quit): 2 5-7
```

## 安全说明

- 活跃 session 保护会拒绝删除最近 10 分钟内修改过的 session。
- `delete <uuid-prefix>` 在匹配不到或匹配到多条文件时都会拒绝执行。
- 斜杠命令会在调用删除脚本前要求二次确认。
- Linux 尚未验证，因为脚本目前使用 BSD/macOS 风格的 `stat` 和 `date` 参数。
- 没有撤销功能。删除动作使用 `rm` 直接移除文件。

## 卸载

```bash
rm ~/.claude/scripts/delete-session.sh
rm ~/.claude/commands/delete-session.md
```

## 许可证

本项目基于 [MIT License](./LICENSE) 发布。
