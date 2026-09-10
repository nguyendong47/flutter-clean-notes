# Antigravity (AGY) Collaboration Rules for flutter-clean-notes

This project is co-developed with **Claude Code** via a shared SQLite MCP Server (`shared-sqlite`).

## 1. Multi-Agent Protocol
- **State Database**: `.agent-shared/collab.db`
- **Full Documentation**: See `docs/agents/antigravity-collab.md`.
- **Coordination Rules**:
  1. Check `tasks` in `collab.db` before editing files.
  2. Do not overwrite files actively assigned to Claude (`status = 'in_progress' AND assigned_to = 'claude'`).
  3. When completing a task, update `status = 'done'` and post a note to `agent_messages`.

## 2. Project Architecture Guardrails
- Flutter Clean Architecture:
  - `lib/core/` (network, errors, utils, theme)
  - `lib/features/<feature>/domain/` (entities, usecases, repository interfaces)
  - `lib/features/<feature>/data/` (models, datasources, repository implementations)
  - `lib/features/<feature>/presentation/` (bloc/cubit/riverpod, widgets, pages)
- Must follow GitNexus impact analysis before refactoring or major symbol edits.
