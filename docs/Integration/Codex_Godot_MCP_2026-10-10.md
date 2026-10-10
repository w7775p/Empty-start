# Codex CLI × Godot MCP 接入记录（2026-10-10）

## 环境、来源与职责

- Windows：`LAPTOP-C2OB3O8H`；主项目 `D:\Godot\Empty-start`；Godot 可执行文件 `D:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`（本机 CLI 及测试日志显示 `4.7.2.stable.steam.ed1daf0bf`）。
- 编辑器 MCP：社区项目 [yurineko73/Godot-MCP-Native](https://github.com/yurineko73/Godot-MCP-Native)，已有 `addons/godot_mcp/`，`plugin.cfg` 版本 1.0.8，`project.godot` 已启用插件。此插件通过 Godot 原生 HTTP 提供编辑器、节点、场景树、脚本、资源及运行时相关工具。
- 文档 MCP：本机 `uv tool list` 为 `godot-docs-mcp v0.1.0`，启动文件为 `C:\Users\lvy\.local\bin\godot-docs-mcp.exe`。MCP 初始化报告 `godot-docs 1.30.0`，用于查询 Godot 类、方法、属性、信号、文档及代码示例。
- Codex CLI：`C:\Users\lvy\AppData\Local\OpenAI\Codex\bin\9691020b546a15b2\codex.exe`。用户级配置 `C:\Users\lvy\.codex\config.toml`；安装记录已有 `config.toml.before-godot-auth-20261010.bak` 和 `config.toml.before-isolated-native-port-20261010.bak`。
- 两个服务作用不同：Native 连接一个正在运行的具体 Godot 工程，Docs 使用 stdio 查询 API 文档。

## 当前已注册的 Codex MCP

`codex mcp list` 显示 `godot-native`（HTTP）和 `godot-docs`（stdio）均为 `enabled`。当前用户配置要点如下，Bearer 密钥仅保存在本机，**严禁提交真实令牌到 Git**：

```toml
[mcp_servers.godot-native]
url = "http://127.0.0.1:19080/mcp"

[mcp_servers.godot-native.http_headers]
Authorization = "Bearer <LOCAL_SECRET>"

[mcp_servers.godot-docs]
command = 'C:\Users\lvy\.local\bin\godot-docs-mcp.exe'
```

修改个人配置前备份；Windows 新终端中可运行：

```powershell
$cli = 'C:\Users\lvy\AppData\Local\OpenAI\Codex\bin\9691020b546a15b2\codex.exe'
& $cli mcp list
```

## 服务器启动与恢复

当前 Godot-Native 已用以下**经过核实的**启动方式运行，在 Windows 另一个终端中执行，端口应以实际工作区分配为准：

```powershell
$godot = 'D:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
& $godot --headless --editor --path 'D:\Godot\Empty-start' -- --mcp-server --mcp-port=19080 --mcp-transport=http
```

在进程存在期间访问 `http://127.0.0.1:19080/mcp`；与 Godot HTTP MCP 交互需要合规 JSON-RPC / MCP 握手和 Authorization。单纯浏览器 GET 或端口监听不能证明工具可用。项目插件已在 `project.godot` 启用。Native 编辑器启动后可用 `get_project_info` 核对工程路径、`get_scene_tree` 核对场景树；Docs 可用 `lookup_method(class_name="Node", method="add_child")` 核对 API。

**Worktree 隔离：** 全局 Native URL 当前绑定主仓库 `D:\Godot\Empty-start`，所以其他 Lane 在独立 worktree 中运行时，不应通过这个服务器修改主仓库的编辑器场景/脚本/资源。需要 Native 写入时，为该 worktree 启动**独立** Godot 编辑器服务（例如端口 19081），使该 Codex 会话的 MCP URL 指向自己工程，再次用 `get_project_info` 验证路径。共享的文档 MCP 可以直接使用。修改用户级 MCP 配置通常只对新启动的 Codex 会话生效；老会话的工具初始化状态应保留，避免打断运行任务。

## 2026-10-10 实测

| 项目 | 实测结果 |
| --- | --- |
| `codex mcp list` | 两个 MCP 均为 enabled |
| Native `initialize` | JSON-RPC OK；serverInfo `godot-native-mcp 2.0.0` |
| Native `tools/list` | 30 个核心工具 |
| Native `get_project_info` | `project_path=D:/Godot/Empty-start/`；`main_scene=res://core/boot/boot.tscn`；报告 `godot_version=4.7.stable` |
| Native `get_scene_tree` | 成功读取 Boot，两个节点 |
| Docs `initialize` | JSON-RPC OK；serverInfo `godot-docs 1.30.0` |
| Docs `tools/list` | 12 个工具，包括 `lookup_method`、`search_docs`、`lookup_signal` |
| Docs `lookup_method` | `Node.add_child` 返回真实方法文档 |

以上另经真实 Codex CLI `exec --json` 会话（Lane A / INT-08）补验：`godot-docs.lookup_method(Node, add_child)` 和 `godot-native.get_project_info()` 均在会话事件流中显示 `item.completed`；Native 返回 `C:/Users/lvy/.codex/worktrees/lane-a-int08-1010/Empty-start/`，证明会话覆盖地址 `19081` 成功接入隔离 worktree。该会话使用 `-c mcp_servers.godot-native.url=http://127.0.0.1:19081/mcp`，并通过本机 `HTTP_PROXY/HTTPS_PROXY/ALL_PROXY=http://127.0.0.1:7897` 连接模型服务，`NO_PROXY=127.0.0.1,localhost` 保留 MCP 本地直连。首轮因缺失代理曾出现模型请求超时，新会话重启后进入真实工具调用。文档检索结果依然需要按项目 Godot 4.7.2 API 核对版本差异。Windows 防火墙须限制 HTTP 服务访问范围：本次 `netstat` 表明 19080 监听 `0.0.0.0`，虽然已配置 Bearer 鉴权，仍需避免向局域网开放此高权限服务。

后续 Agent 的默认开发流程：先读 `AGENTS.md` / `known_traps.md` / 任务卡 → 搜索已有实现 → Docs 核对 API → 如涉及编辑器操作，确认 Native 服务路径是本 Lane 工程 → Godot 真实运行 → 单卡提交、记录日志并开 PR → 等候调度方 Review。
