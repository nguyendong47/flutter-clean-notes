# Multi-Agent Collaboration Protocol: Claude Code & Google Antigravity

This project (`flutter-clean-notes`) is co-developed by **Claude Code** and **Google Antigravity (AGY)** using a shared SQLite MCP Server (`shared-sqlite`).

---

## 1. Architecture & Storage

- **MCP Server Name**: `shared-sqlite`
- **Database File**: `.agent-shared/collab.db` (WAL Mode enabled for non-blocking concurrent access)
- **Role Division**:
  - **Claude Code**: Core Clean Architecture implementation, business logic (domain/usecases), complex refactoring, test fixes.
  - **Antigravity (Gemini)**: Global architectural planning, large-context audits, GitNexus symbol impact oversight, Flutter UI/presentation layer, test generation.

---

## 2. Database Schema

### Table: `tasks`
Manages work items, assignment, and execution states.
```sql
CREATE TABLE tasks (
    id TEXT PRIMARY KEY,          -- e.g. 'TASK-1', 'FEAT-AUTH'
    title TEXT NOT NULL,
    description TEXT,
    assigned_to TEXT,             -- 'claude' | 'antigravity'
    status TEXT DEFAULT 'todo',   -- 'todo' | 'in_progress' | 'done' | 'blocked'
    result_summary TEXT,          -- Brief summary of what was changed/implemented
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### Table: `agent_messages`
Asynchronous message board and handoff notes between agents.
```sql
CREATE TABLE agent_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sender TEXT NOT NULL,         -- 'claude' | 'antigravity'
    recipient TEXT NOT NULL,      -- 'claude' | 'antigravity'
    content TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### Table: `project_decisions`
Persistent record of architecture decisions (ADRs) and conventions agreed upon by both agents.
```sql
CREATE TABLE project_decisions (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    author TEXT,                  -- 'claude' | 'antigravity' | 'user'
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

---

## 3. Standard Workflow for Claude Code

### Step 1: Check Inbox & Assigned Tasks
When starting a session or completing a feature, check for new messages and available tasks:
```sql
-- Check latest messages from Antigravity
SELECT sender, content, created_at FROM agent_messages ORDER BY id DESC LIMIT 5;

-- Find tasks assigned to Claude or open for pickup
SELECT id, title, description, status FROM tasks WHERE status = 'todo' AND (assigned_to = 'claude' OR assigned_to IS NULL);
```

### Step 2: Claim Task
Before modifying any source files:
```sql
UPDATE tasks 
SET status = 'in_progress', assigned_to = 'claude', updated_at = CURRENT_TIMESTAMP 
WHERE id = 'TASK-X';
```

### Step 3: Implement & Respect Project Rules
- Follow Clean Architecture structure (`lib/core`, `lib/features/<name>/domain`, `data`, `presentation`).
- Comply with GitNexus impact rules in `CLAUDE.md` (`impact`, `detect_changes`).
- Do not edit files actively being worked on by Antigravity (`status = 'in_progress' AND assigned_to = 'antigravity'`).

### Step 4: Complete & Handoff
Once implementation and local tests (`flutter test`) pass:
```sql
-- Mark task as done with a concise summary
UPDATE tasks 
SET status = 'done', result_summary = 'Implemented NoteRepository and unit tests.', updated_at = CURRENT_TIMESTAMP 
WHERE id = 'TASK-X';

-- Notify Antigravity if review or UI integration is needed
INSERT INTO agent_messages (sender, recipient, content) 
VALUES ('claude', 'antigravity', 'TASK-X completed: Added domain/data layers for Notes. Ready for UI integration and review.');
```

---

## 4. Helpful MCP Tool Queries

Claude Code has access to `shared-sqlite` MCP tools:
- `read_query`: Use for `SELECT` statements.
- `write_query`: Use for `INSERT`, `UPDATE`, `DELETE` statements.
- `list_tables`: List tables in `collab.db`.
- `describe_table`: Inspect column schemas.

If the `shared-sqlite` MCP connection drops or hangs (observed intermittently), fall back to reading/writing `collab.db` directly with Python's built-in `sqlite3` module — it's the same WAL-mode file, no server needed:
```bash
python -c "import sqlite3; c=sqlite3.connect('.agent-shared/collab.db'); [print(r) for r in c.execute('SELECT * FROM tasks')]"
```

## 5. Coordination Reality (as actually operated)

- **Antigravity has no autonomous watch/poll loop on this DB.** There is no daemon on either side that reacts to a new row automatically. A row sitting in `tasks` with `status='todo'` does nothing by itself.
- **Claude Code is the active coordinator.** It reads `tasks`/`agent_messages` on-demand — when the user asks, or naturally between its own tasks — not on a continuous background timer (token cost). When it finds work assigned to `antigravity`, it dispatches the actual execution itself via the `agy` CLI in headless mode from the same machine:
  ```powershell
  agy -p "<task prompt>" --dangerously-skip-permissions --output-format json --print-timeout 20m
  ```
  Known `agy` headless quirks to expect: stdout can silently drop / the wrapping shell command can report a false failure when run through a non-TTY pipe/redirect on Windows (a documented upstream issue) even though `agy.exe` keeps running and finishes correctly — verify completion via `git log`/`git status` in the target worktree, not the wrapper's exit code. It can also genuinely hang; if no file/commit activity for a long stretch, kill the `agy.exe` process and redispatch.
- **Antigravity's own IDE session** (when the user has it open) can independently read/write the same DB — that's the only path for it to see or act on anything here without Claude driving it.
