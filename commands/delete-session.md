---
description: 列出并删除 Claude Code 历史 session 文件（默认限定当前项目）
allowed-tools: Bash(~/.claude/scripts/delete-session.sh:*)
---

用户想清理 Claude Code 的历史 session 文件（位于 `~/.claude/projects/<encoded-path>/<uuid>.jsonl`）。

## 脚本的默认行为（重要）

脚本**默认只看当前项目**（按 `$PWD` 推导），并且只列"主 session"——不递归进 `subagents/` / `tool-results/` / `memory/` 这些衍生目录。

删除主 session 时，会同时把同名的 `<uuid>/` 目录（含 subagents / tool-results / memory）一并删掉。

## 第一步：列出候选

解析 `$ARGUMENTS`：

| $ARGUMENTS | 脚本调用 | 含义 |
|---|---|---|
| 空 | `delete-session.sh list` | 当前项目全部 |
| `foo`（关键字） | `delete-session.sh list foo` | 当前项目 + 按 foo 过滤 |
| `--all` | `delete-session.sh --all list` | 所有项目 |
| `--all foo` | `delete-session.sh --all list foo` | 所有项目 + 过滤 |
| UUID 前缀（8+ 位十六进制） | 跳过列出，直接进第二步 | 单条定位 |

把脚本输出**完整转发**给用户，不要截断重排。注意输出里带 ★ 前缀的是用户用 `/rename` 设置过的名字，优先拿那个识别。

## 第二步：接收选择

等待用户指定要删哪几条。支持这几种表达：

- `1 3 5` —— 三条
- `1-5` —— 范围
- `除 1 以外都删` / `all except 1` —— 全部减掉几条
- `全部` / `all` —— 清单里的全部（**但仍要二次确认**）
- `算了` / `取消` / 空回复 —— 直接结束

对"全部"或"除 X 外"这种批量操作要特别谨慎——先算出最终 uuid 列表，逐条列在二次确认里。

## 第三步：二次确认

在真正调用删除前，把准备删的 session 的**完整路径 + label**（custom-title 或首条消息）列给用户：

```
准备删除 N 个 session：
  [5] EchoCenter/83a02149…  "你现在模型的上下文..."
  [6] HERTCERT/9f362cce…    ★ fix-v2-production-stability

确认删除？[y/N]
```

只有收到明确肯定（y / yes / 确认 / 删 / 好 等）才进入第四步。

## 第四步：执行删除

一次调用可以传多个 uuid：`~/.claude/scripts/delete-session.sh delete <uuid1> <uuid2> ...`

**脚本的安全拒绝**：如果某条 session 的 mtime < 10 分钟，脚本会输出 `refuse: ... is active`。把这些被拒的条目原样报给用户，不要尝试绕过。

## 约束

- **不要并行执行**脚本（可能遇到同一 uuid 的竞争）。
- **不要对"当前会话"（你正在和用户对话的 session）发起删除**——即使用户明确要求。告诉他这需要在另一个终端里用脚本的 interactive 模式做。判断方法：脚本的活跃保护会拒绝 mtime < 10 分钟的 session，当前 session 几乎总会撞这个阈值。
- 删完之后不要再总结 "已完成了 X 件事"——脚本的 `deleted:` 输出就足够清晰。
- 如果 $ARGUMENTS 看起来像一个 UUID 前缀（至少 8 位十六进制），跳过"列出"直接去第三步的二次确认。

## 脚本完整 API 参考

```
~/.claude/scripts/delete-session.sh                           # interactive (for terminal, NOT for you)
~/.claude/scripts/delete-session.sh list [pattern]            # list-only, current project
~/.claude/scripts/delete-session.sh --all list [pattern]      # list-only, every project
~/.claude/scripts/delete-session.sh --project <path> list     # list-only, a specific project
~/.claude/scripts/delete-session.sh delete <uuid>...          # non-interactive delete by uuid (prefix ok)
```
