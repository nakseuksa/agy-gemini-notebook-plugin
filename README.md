
# 📓 Gemini Notebook by Chryzalide — Windows  (v1.0.6)

## 1. 目标与背景
将开源项目 **`agy-gemini-notebook-plugin`**（Gemini Notebook by Chryzalide）作为插件安装部署到 Windows 环境下的 **Google Antigravity 2**，打通本地与 **Google NotebookLM** 的双向连接，解决 Windows 环境下的路径解析、目录扫描、浏览器文件锁以及 Sidecar 模块遮蔽问题。

---

## 2. 核心排查与修复点 (Why & How)

### 🔹 修复点 1：Windows 虚拟环境与解释器启动兼容性
* **现象/原因**：
  * 该项目此前基于 Linux/macOS 开发，多处硬编码检查 `.venv/bin/python` 及 `.venv/lib/python*/site-packages`，环境变量路径分隔符写死为 `:`。
  * 在 Windows 环境下，虚拟环境目录实际为 `.venv/Scripts/python.exe` 与 `.venv/Lib/site-packages`，路径分隔符应为 `;`（`os.pathsep`）。
  * Windows 系统 PATH 中常附带 `C:\Users\<user>\AppData\Local\Microsoft\WindowsApps\python3.exe`（微软商店空占位符），在非交互调用时直接报错退出，导致回退 `python3` 失败。
* **修复方案**：
  * 修改 [`scripts/run_mcp.sh`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/scripts/run_mcp.sh) 和 [`scripts/setup.sh`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/scripts/setup.sh)，优先解析 `.venv/Scripts/python.exe`，并在回退系统 Python 时校验 `python3 -c "import sys"`，无效时自动使用 `python`。
  * 修改 [`src/agy_gemini_notebook/engines/rpc_bridge.py`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/src/agy_gemini_notebook/engines/rpc_bridge.py#L186-L206) 的 [`_resolve_python_executable`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/src/agy_gemini_notebook/engines/rpc_bridge.py#L186-L206) 与 [`login`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/src/agy_gemini_notebook/engines/rpc_bridge.py#L306-L323)，补充 Windows `.venv` 结构并采用 `os.pathsep` 拼接 `PYTHONPATH` 与 `PATH`。

---

### 🔹 修复点 2：Antigravity 2 语言服务 Windows 插件发现机制（实体目录 vs 联接）
* **现象/原因**：
  * 初次通过 Windows 目录联接（Junction，`mklink /J`）将项目链接到 `~/.gemini/config/plugins/gemini-notebook` 时，重启 Antigravity 后插件列表未显示该插件。
  * **根因**：Antigravity 2 的 Language Server（Go 编写）使用 `os.ReadDir` 扫描 `plugins/`，Windows 下顶层目录如果是 `ReparsePoint`（联接/软链），`DirEntry.IsDir()` 返回 `false`，扫描器会直接忽略该文件夹。
* **修复方案**：
  * 将 `C:\Users\<个人用户名>\.gemini\config\plugins\gemini-notebook` 改造为**标准实体目录（`Mode: d-----`）**，内部将 `.venv` 通过目录联接指向工作区环境，外层保持实体结构。
  * 同步在 [`src/agy_gemini_notebook/cli.py`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/src/agy_gemini_notebook/cli.py#L49-L85) 的 [`_run_setup`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/src/agy_gemini_notebook/cli.py#L38-L90) 中增加 Windows 实体目录安装逻辑。
  * **验证**：Language Server RPC `GetAllPlugins` 立即成功识别 `gemini-notebook`（`disabled: false`，`isGlobal: true`）。

---

### 🔹 修复点 3：Sidecar 目录脚本名称遮蔽 Bug（Shadowing）
* **现象/原因**：
  * 插件安装成功后，打开右侧 Sidecar 面板，下拉列表中显示为空（`— No notebooks returned by active engine —`），控制台报 `cannot import name 'NotebookLMClient' from 'notebooklm'`。
  * **根因**：在 `sidecars/notebook_context_panel/` 下存在历史残留脚本 `notebooklm.py`。Python 启动 `server.py` 时会将脚本所在目录加入 `sys.path[0]`，导致在执行 `from notebooklm import NotebookLMClient` 时误导入了同目录下的本地脚本，遮蔽了真正的 `notebooklm-py` 第三方库。
* **修复方案**：
  * 删除了冗余的 `sidecars/notebook_context_panel/notebooklm.py`。
  * 在 [`sidecars/notebook_context_panel/server.py`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/sidecars/notebook_context_panel/server.py) 头部增加了防遮蔽保护逻辑：
    ```python
    if str(SIDECAR_DIR) in sys.path:
        sys.path.remove(str(SIDECAR_DIR))
    ```
  * 重启 Sidecar 服务进程后，`/api/notebooks` 接口恢复正常，成功返回全部 **49 本** 笔记本。

---

### 🔹 修复点 4：Windows 下 Chromium 浏览器独占锁定 Cookies 数据库（OS error 32）
* **现象/原因**：
  * 使用 `rookie-cookies` 读取本地浏览器会话时，若 Chrome、Vivaldi、Edge 等处于打开状态，Windows 会对 `Network\Cookies` SQLite 文件施加独占共享锁（`dwShareMode = 0`），抛出 `OS error 32: 另一个程序正在使用此文件，进程无法访问`。
* **修复方案**：
  * 在 [`src/agy_gemini_notebook/engines/rpc_bridge.py`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/src/agy_gemini_notebook/engines/rpc_bridge.py#L355-L360) 的登录失败提示中增加针对 Windows 浏览器锁的明确指引（提醒用户在导入会话前短暂关闭浏览器窗口）。
  * 修复了 Windows 下 `~/.notebooklm/profiles/default/storage_state.json` 的文件 ACL 权限，确保后台服务进程拥有读取权限。

---

### 🔹 修复点 5：笔记本列表默认分页与防截断优化
* **优化内容**：
  * 在 [`src/agy_gemini_notebook/mcp_server.py`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/src/agy_gemini_notebook/mcp_server.py#L328-L360) 的 [`notebook_list`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/src/agy_gemini_notebook/mcp_server.py#L328-L360) 工具中，将默认 `page_size` 由 25 提升至 100，并在响应中添加 `total_count` 和 `has_more` 字段，确保笔记本数量超过 25 时的首次查询不发生截断。

---

## 3. 受修改文件清单 (Files Modified)

| 序号 | 文件路径 | 修改性质 | 主要改动说明 |
| :---: | :--- | :---: | :--- |
| 1 | [`scripts/run_mcp.sh`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/scripts/run_mcp.sh) | 修改 | 优先解析 Windows `.venv/Scripts/python.exe`，增加 `python3` 真实性校验与 `python` 回退 |
| 2 | [`scripts/setup.sh`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/scripts/setup.sh) | 修改 | 适配 Windows 虚拟环境路径，增加 Windows 实体目录/联接安装逻辑与版本号更新 |
| 3 | [`sidecars/notebook_context_panel/sidecar.json`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/sidecars/notebook_context_panel/sidecar.json) | 修改 | 使用跨平台启动命令，依次探测 `.venv/bin/python`、`.venv/Scripts/python.exe`、`python3` 与 `python` |
| 4 | [`sidecars/notebook_context_panel/server.py`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/sidecars/notebook_context_panel/server.py) | 修改 | 引入 Windows `.venv` 解释器与 `Lib/site-packages`，移除当前目录以防止模块遮蔽 |
| 5 | `sidecars/notebook_context_panel/notebooklm.py` | **删除** | 彻底移除造成 `notebooklm` 模块遮蔽的冗余脚本 |
| 6 | [`sidecars/notebook_context_panel/ui.html`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/sidecars/notebook_context_panel/ui.html#L528) | 修改 | 更新徽标为 `Dual-Engine v1.0.6` |
| 7 | [`src/agy_gemini_notebook/__init__.py`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/src/agy_gemini_notebook/__init__.py) | 修改 | 版本升级至 `1.0.6` |
| 8 | [`plugin.json`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/plugin.json) | 修改 | 版本升级至 `1.0.6` |
| 9 | [`pyproject.toml`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/pyproject.toml) | 修改 | 版本升级至 `1.0.6` |
| 10 | [`src/agy_gemini_notebook/cli.py`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/src/agy_gemini_notebook/cli.py) | 修改 | `_run_setup` 在 Windows 下自动部署实体插件目录 |
| 11 | [`src/agy_gemini_notebook/engines/rpc_bridge.py`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/src/agy_gemini_notebook/engines/rpc_bridge.py) | 修改 | 适配 Windows 解释器与 `os.pathsep`，增加 Windows 浏览器独占锁错误诊断指引 |
| 12 | [`src/agy_gemini_notebook/mcp_server.py`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/src/agy_gemini_notebook/mcp_server.py) | 修改 | `notebook_list` 默认 `page_size` 调整为 100，并返回 `total_count` 和 `has_more` |
| 13 | [`tests/test_sidecar_server.py`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/tests/test_sidecar_server.py) | 修改 | 单元测试兼顾 Windows `.venv/Scripts/python.exe` 路径校验 |
| 14 | [`AGENTS.md`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/AGENTS.md) | 修改 | 版本基线更新为 `v1.0.6` |
| 15 | [`README.md`](file:///c:/Users/<个人用户名>/iCloudDrive/antigravity/agy-gemini-notebook-plugin/README.md#L315-L330) | 修改 | 版本徽章更新为 `v1.0.6`，在 `## 📦 Versioning & Changelog` 中完整记录本次改动的原因与方法 |
---
Ran check symlinks in plugin directory
Analyzed rpc_bridge.py:L1-100
Analyzed rpc_bridge.py:L140-440
Analyzed storage_state.json:L1-40
Analyzed setup.sh:L1-120
Analyzed mcp_server.py:L1-125
Analyzed AGENTS.md:L1-19
Analyzed SKILL.md:L45-70
Analyzed mcp_server.py:L1-10
Edited run_mcp.sh
Analyzed run_mcp.sh:L1-30
Analyzed rpc_bridge.py:L40-60
Analyzed rpc_bridge.py:L320-445
Editing rpc_bridge.py
Edited rpc_bridge.py
Analyzed rpc_bridge.py:L70-90
Ran normalize plugin files to LF · Exited with code 1
Edited rpc_bridge.py
Analyzed rpc_bridge.py:L175-215
Analyzed rpc_bridge.py:L390-450
Edited rpc_bridge.py
Edited rpc_bridge.py
Edited rpc_bridge.py
Edited rpc_bridge.py
Analyzed mcp_server.py:L325-365
Edited mcp_server.py
Edited mcp_server.py
Used tool: edit_file
Ran verify Python syntax of modified files · Exited with code 1
Ran check AST syntax of modified Python files
Edited AGENTS.md
Edited SKILL.md
Edited mcp_server.py
Edited mcp_server.py
Edited rpc_bridge.py

已完成对本次会话全过程的错误复盘、根因定位，并将修复方案与实战经验回写至 **MCP 服务端代码**、**RPC 桥接引擎**、**启动脚本**、**全局 Grounding 规则（Rule）** 以及 **Gemini Notebook 技能（Skill）** 中。

---

### 26/10/2026 修正

| 阶段 | 现象 / 错误 | 核心根因分析 |
| :--- | :--- | :--- |
| **1. 初次调用 `notebook_list` 失败** | 返回通用报错 `Encountered error in tool execution: Error executing tool notebook_list` | 本地虽存在数小时前保存的 `storage_state.json`，但其中的 Google 会话 Cookie（如 `SIDCC` / `__Secure-1PSIDTS`）或 `SNlM0e` CSRF 令牌已过期。而 [`NotebookRpcBridge._open_client`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/src/agy_gemini_notebook/engines/rpc_bridge.py#L460-L541) 原本仅捕获 `FileNotFoundError`，未捕获 `notebooklm-py` 因 Cookie 过期抛出的认证异常，导致异常直接穿透 FastMCP 变成不透明的工具报错。 |
| **2. `notebook_status` 误导性就绪状态** | `notebook_status` 返回 `has_saved_session: true`、`setup_ready: true` | [`has_saved_session()`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/src/agy_gemini_notebook/engines/rpc_bridge.py#L257-L263) 仅检查磁盘上是否存在 `storage_state.json` 文件，不校验文件中的 Cookie 是否仍然有效；且 [`resolve_storage_path()`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/src/agy_gemini_notebook/engines/rpc_bridge.py#L180-L225) 原先按固定顺序返回第一个存在的文件，而非修改时间（`mtime`）最新的会话文件。 |
| **3. 沙盒终端调试弯路** | 在终端尝试运行 `uv run`、`.venv`、`Get-CimInstance`、`$env:PYTHONPATH` 均报错 | 1) 插件目录下的 `.venv` 是指向工作区外的目录联接（Junction），在当前工作区（`02.read`）沙盒内直接调用会触发 `OS error 5 (拒绝访问)`；<br>2) 沙盒 PowerShell 包装器会改写 `$env:PYTHONPATH`；<br>3) 实际上 MCP Server 运行在宿主进程中，遇到认证报错只需直接调用 MCP 工具 `notebook_login(browser_cookies="auto")` 即可 1 秒修复，无需通过终端排障。 |
| **4. 列表分页截断（25 vs 49）** | 首次成功调用 `notebook_list()` 仅返回 25 个笔记本 | [`notebook_list`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/src/agy_gemini_notebook/mcp_server.py#L330-L360) 默认 `page_size=25`，且返回结果中仅有截断后的 `count`，缺少 `total_count` 与 `has_more` 提示，导致二次调用 `page_size=100` 才拿到全部 49 个笔记本。 |
| **5. Windows 终端 Emoji 编码异常** | Python 打印笔记本 Emoji 时报 `UnicodeEncodeError: 'gbk' codec can't encode character` | Windows 控制台默认使用 `gbk` 编码，Python 脚本输出含 Emoji（如 `📖`、`🧮`）的文本前需显式调用 `sys.stdout.reconfigure(encoding='utf-8')`。 |

---

### 二、 已回写的代码与脚本修正

1. **自动无感刷新过期 Cookie + 异常精准捕获（[`rpc_bridge.py`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/src/agy_gemini_notebook/engines/rpc_bridge.py)）**
   - 新增 [`_is_auth_error()`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/src/agy_gemini_notebook/engines/rpc_bridge.py#L46-L72) 识别各类认证/会话/CSRF/401/403/重定向异常。
   - 升级 [`NotebookRpcBridge._open_client()`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/src/agy_gemini_notebook/engines/rpc_bridge.py#L460-L541)：当检测到本地无会话或已有 `storage_state.json` 中的 Cookie 过期失效时，**自动在后台静默执行一次 `self.login(browser_cookies="auto")`** 从浏览器同步最新 Cookie 并立即重连；若在 RPC 调用期间触发刷新，[`list_notebooks()`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/src/agy_gemini_notebook/engines/rpc_bridge.py#L582-L617) 会自动重试一次，实现**首次调用即无感成功**。
   - 若自动刷新仍失败，统一抛出结构化的 [`NotebookAuthRequiredError`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/src/agy_gemini_notebook/engines/rpc_bridge.py#L75-L80)，不再让 MCP 崩溃报 `Error executing tool`。

2. **多路径会话同步与最新文件优选（[`rpc_bridge.py`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/src/agy_gemini_notebook/engines/rpc_bridge.py)）**
   - 升级 [`resolve_storage_path()`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/src/agy_gemini_notebook/engines/rpc_bridge.py#L180-L225)：跨 `~/.notebooklm`、插件 `.notebooklm-auth` 等全部候选路径按文件修改时间（`st_mtime`）倒序选取**最新且非空**的 `storage_state.json`。
   - 升级 [`login()`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/src/agy_gemini_notebook/engines/rpc_bridge.py#L414-L428)：登录成功后同步写入用户主目录与插件目录，防止多处会话文件不一致。

3. **扩大默认分页并返回总数元数据（[`mcp_server.py`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/src/agy_gemini_notebook/mcp_server.py)）**
   - 将 [`notebook_list`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/src/agy_gemini_notebook/mcp_server.py#L330-L360) 的默认 `page_size` 从 `25` 提升至 `100`，并在返回值中新增 `"total_count"` 和 `"has_more"` 字段，确保单次调用即可完整罗列全部笔记本。

4. **优先加载插件本地源码（[`run_mcp.sh`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/scripts/run_mcp.sh)）**
   - 在 [`scripts/run_mcp.sh`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/scripts/run_mcp.sh#L7-L16) 顶部提前导出 `export PYTHONPATH="${PLUGIN_DIR}/src..."`，确保即使 `.venv` 是跨目录 Junction，MCP Server 也始终优先加载插件目录下的最新代码。

---

### 三、 已回写的规则（Rule）与技能（Skill）资源

1. **全局插件规则 [`rules/AGENTS.md`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/rules/AGENTS.md#L20-L25)**
   - 新增第 5 条 **Fast Auth Recovery, Pagination & Windows Sandbox Best Practices**：
     - 明确指出 `notebook_status` 的 `setup_ready: true` 仅代表文件存在，遇到任何 MCP 工具报错时**第一时间直接调用 `notebook_login(browser_cookies="auto")`**。
     - **严禁**在工作区终端沙盒内运行 `uv`、`.venv/Scripts/python.exe`、`Get-CimInstance` 或 `$env:PYTHONPATH` 去调试插件环境。
     - 罗列全部笔记本时显式传入 `page_size=100` 并检查 `total_count` / `has_more`。
     - Windows 下用 Python 处理含 Emoji 的大文本输出时强制加上 `sys.stdout.reconfigure(encoding='utf-8')`。

2. **技能指南 [`skills/gemini-notebook/SKILL.md`](file:///C:/Users/<个人用户名>/.gemini/config/plugins/gemini-notebook/skills/gemini-notebook/SKILL.md#L72-L90)**
   - 新增 **`## Troubleshooting, Fast Auth Recovery & Pagination Best Practices`** 章节，沉淀完整的故障自愈标准作业程序（SOP），供后续所有会话读取遵循。
