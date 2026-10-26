# Gemini Notebook by Chryzalide — Grounding & Piloting Rules

When this plugin (`gemini-notebook` / **Gemini Notebook by Chryzalide**) is enabled in Antigravity 2 or configured in an IDE workspace:

1. **First-Time Setup & Workspace Notebook Awareness**:
   - Check if the active workspace contains a `.agents/notebook.json` binding (or call `notebook_status` / `notebook_invoke` from `gemini_notebook_mcp`).
   - If `notebook_status` reports `setup_ready: false` (or a tool returns `status: "auth_required"`), guide the user through the setup workflow by calling `notebook_login(browser_cookies="auto")` for Engine 2 (imports active browser session without Playwright sign-in automation; note the unofficial RPC grey-area disclaimer) or `notebook_login(gcloud=True)` + `GCP_PROJECT_NUMBER` for Engine 1 (100% official Google Cloud API).
   - When a Gemini Notebook is attached to the workspace and the user asks architectural, domain, specification, or research questions, prioritize querying the attached notebook (`notebook_query` or `notebook_search_sources`) before making assumptions.
   - When the user asks to "invoke" a notebook by name, alias, or ID, call `notebook_invoke`.

2. **Piloting Notebooks, Documentary Research & Local `.md` Synthesis**:
   - Use the MCP tools (`gemini_notebook_mcp`) or the `agy-gemini-notebook` CLI to pilot notebooks on behalf of the user: creating new notebooks (`notebook_create`), syncing local docs (`notebook_sync_files`), launching Fast or Deep Research (`notebook_research` with `mode="fast"` or `mode="deep"`), generating Studio artifacts (`notebook_generate_artifact`, `notebook_create_audio`), and storing persistent session findings (`notebook_notes`).
   - **Decision-Support & Local Markdown Generation**: When a project requires documentary research to help make an architectural, technical, or product decision, invoke an existing Gemini Notebook (`notebook_invoke`) or create a new one (`notebook_create`), run documentary research (`notebook_research`) or query existing notebook documents (`notebook_query`), and synthesize the pertinent findings with inline citations into structured `.md` files inside the local project repository (e.g., `docs/research/`, `docs/adr/`).

3. **Citation Integrity**:
   - When incorporating facts or answers retrieved from a Gemini Notebook (in chat or in generated local `.md` files), explicitly cite the notebook title and source name.

4. **Sidecar Panel Link (Antigravity 2)**:
   - Whenever you attach, switch, or update a notebook visualization in the sidecar panel, include the clickable pill link `[Gemini Notebook by Chryzalide](sidecar://gemini-notebook/notebook_context_panel/ui.html)` so the user can open the sidecar with one click.

5. **Fast Auth Recovery, Pagination & Windows Sandbox Best Practices**:
   - **Stale Cookie Recovery (`notebook_login` First)**: `notebook_status` reporting `setup_ready: true` / `has_saved_session: true` only indicates that `storage_state.json` exists on disk; Google session cookies inside it may still expire after a few hours. If `notebook_list`, `notebook_get`, `notebook_query`, or any `gemini_notebook_mcp` tool returns `Error executing tool ...` or `status: "auth_required"`, **immediately call `notebook_login(browser_cookies="auto")` via MCP** and retry the tool call.
   - **Do Not Debug Plugin `.venv` via Sandboxed Shell**: Never run `uv`, `.venv/Scripts/python.exe`, `Get-CimInstance`, or `$env:PYTHONPATH` in the workspace terminal sandbox to troubleshoot MCP errors—the plugin's `.venv` junction targets a directory outside the workspace sandbox (`OS error 5 / 拒绝访问`). Always use the MCP tools (`notebook_login`, `notebook_status`, `notebook_list`) directly.
   - **List All Notebooks Without Truncation**: When asked to list all notebooks, pass `page_size=100` (or `200`) to `notebook_list(page_size=100)` and check `total_count` / `has_more` so collections larger than 25 notebooks are listed in full on the first call.
   - **Windows UTF-8 Output**: When formatting large MCP JSON step outputs via Python on Windows, always include `sys.stdout.reconfigure(encoding='utf-8')` to avoid `gbk` `UnicodeEncodeError` on notebook emojis.
