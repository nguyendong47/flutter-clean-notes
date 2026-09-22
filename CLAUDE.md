## Agent skills

### Delegation policy — Antigravity does the work, Claude coordinates

**Default: dispatch real work (code changes, content authorship, test writing, bulk edits) to Google Antigravity via the `agy-delegate` skill (`.claude/skills/agy-delegate/`), not the main Claude Code thread.** Claude's role on this project is coordinator, not implementer. Use the skill's own loop (`SKILL.md` + `references/`), not a hand-rolled `agy -p` shell wrapper — its `scripts/relay.mjs` spawns `agy` directly via argv (no shell-quoting bugs), writes a structured `result.json` instead of relying on stdout, and has a watchdog that converts a hang into a clean timeout instead of needing a manual kill:
1. Write a self-contained brief per [`references/writing-the-brief.md`](.claude/skills/agy-delegate/references/writing-the-brief.md) (exact files/patterns, reference commits, the project's real gate commands, a report contract, and that Antigravity does **not** commit).
2. Dispatch: `node .claude/skills/agy-delegate/scripts/relay.mjs --brief <file> --cd <worktree path>` with `run_in_background: true`. Add `--effort high` for harder tasks; add `--read-only` for a verification-only dispatch.
3. **Never trust the self-report.** Read `result.json`, then independently re-run `flutter analyze`, the relevant `flutter test` targets, and GitNexus `detect-changes` yourself before calling a task done — see [`references/review-and-land.md`](.claude/skills/agy-delegate/references/review-and-land.md).
4. **Claude lands the commit**, not the relay and not Antigravity (`references/review-and-land.md`: "you commit — the orchestrator, never the implementer"). This project's established convention (see prior commits on this branch, e.g. `4ec7fbe`, `4d882f5`) is to still credit Antigravity's actual authorship with `Co-Authored-By: Google Antigravity <antigravity@google.com>` in the message Claude writes — keep doing that, never substitute a Claude/Anthropic attribution for Antigravity's own work.

Prior sessions on this branch hand-rolled `agy --print-timeout ... -p "$(cat brief)"` directly in bash before this skill was installed (2026-09-08/09) — that approach is superseded; its known quirks (stdout silently dropping over a non-TTY pipe on Windows, occasional genuine hangs) are exactly what `relay.mjs`'s watchdog and `result.json` contract exist to fix. Full incident history: `docs/agents/antigravity-collab.md`.

Exception: a trivial read-only check that produces no file diff (a `grep` to confirm dead code, a quick status check) is cheaper to just do directly — a delegation run costs real minutes and its own quota even for a 5-second grep. Use judgment there; the default is to delegate anything that actually changes a file.

Fall back to a Haiku subagent (`Agent` tool, `subagent_type: general-purpose`, `model: haiku`) only if `agy` is unavailable — same briefing discipline applies (point it at an already-committed reference file, give exact verification commands), and it needs even more explicit instructions than Antigravity and can miss edge cases (e.g., autoDispose Riverpod providers being sensitive to widget-mount timing in tests).

### Cross-session project memory (`engrim`)

This machine also has `engrim` wired into Claude Code and Antigravity (global, `~/.claude` + `~/.gemini`, installed 2026-09-09) — a local SQLite memory store that survives `/clear` and session restarts, and is shared across both tools. A `SessionStart` hook auto-loads this project's memory pack; write to it at real decisions/corrections, not routine progress: `engrim add -t <decision|fact|feedback|state> -s "<one line>"`. Recall on demand with `engrim recall -q "<topic>"` or `engrim context`. This is a different layer than the `.agent-shared/collab.db` mailbox below — that one is this-project-only and manually queried; `engrim` is cross-project and auto-injected.

### Issue tracker

GitHub Issues (`nguyendong47/flutter-clean-notes`), via `gh` CLI. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context — `CONTEXT.md` + `docs/adr/` at repo root (created lazily when needed). See `docs/agents/domain.md`.

### Multi-Agent Collaboration (Antigravity & Claude Code)

Shared SQLite MCP (shared-sqlite) on .agent-shared/collab.db. Full protocol: docs/agents/antigravity-collab.md.
- **Tasks & State**: Query and update the `tasks` table before and after work (`SELECT * FROM tasks WHERE status = 'todo'`).
- **Messages & Handoff**: Read and post to the `agent_messages` table to exchange status with Antigravity.

### Session handoff — always leave a resumable trail

**Rule: at the end of every session — and any time you're about to lose the thread (long pause, context compaction, handing off to another agent/session/machine) — write or update a handoff doc and commit it.** This project is worked on across multiple sessions, tools (Claude Code, Google Antigravity), and machines; nothing persists unless it's in a committed file. Assume the next reader (which may be you, a fresh session with zero conversation context, or a different agent entirely) has only `git log` and this file.

- Location: `docs/agents/session-handoff-<YYYY-MM-DD>.md`. If one from today already exists, **update it in place** rather than creating a second file for the same day — append/revise sections, don't fork the trail.
- Contents, at minimum:
  - Current branch/worktree and the exact path/command to get back into it.
  - Which plan/task is done (with commit SHAs) vs. next, referencing the plan doc.
  - Any real bug, gotcha, or non-obvious fix discovered this session — write it down even if it feels obvious in the moment; it will not be obvious to the next agent starting cold. Include the reproduction and the fix, not just "watch out for X."
  - Housekeeping already done that shouldn't be redone.
  - Open questions or decisions that are the user's to make, not yours.
- Commit the handoff doc itself (`docs/...` change, own commit or folded into the last task commit — either is fine, just don't leave it uncommitted).
- This applies regardless of whether the session ends "cleanly" (task complete) or gets interrupted — an interrupted session especially needs one, since there's no natural stopping point otherwise.

### Pre-release verification rule — visual screenshots required

- Never rely solely on passing unit/widget tests before approving a release candidate.
- Run automated UI/integration tests and capture visual verification screenshot evidence across light/dark themes, varied text scales, and edge layouts (e.g. status bar padding, bottom sheets, dialogs, keyboard insets) on real or emulated devices before release. See `docs/qa.md`.

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **flutter-clean-notes** (9089 symbols, 19825 relationships, 143 execution flows).

> Index stale? Run `node .gitnexus/run.cjs analyze --index-only` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? Bootstrap with `npx`, `bunx`, or `pnpm dlx` — e.g. `bunx gitnexus@latest analyze` (npm 11 npx crash; #1939).

## Always Do

- **MUST run impact before editing.** Use `impact({target: "symbolName", direction: "upstream"})` or `node .gitnexus/run.cjs impact "symbolName" --direction upstream --repo .`; report callers, processes, and risk. Never substitute grep for graph analysis.
- **MUST analyze graph changes before committing.** Use `detect_changes({scope: "all"})` (MCP) or `node .gitnexus/run.cjs detect-changes --scope all --repo .` (CLI fallback). `partial: true` or `truncated: true` is not a clean check — a zero means unseen, not unaffected; re-run it. For regression review: `detect_changes({scope: "compare", base_ref: "main"})` or `node .gitnexus/run.cjs detect-changes --scope compare --base-ref "main" --repo .`.
- MUST warn on HIGH/CRITICAL `risk` pre-edit; never use `riskSharedAxes` to waive a HIGH/CRITICAL `risk` warning. Compare File/symbol: MCP File omits axes; Graph-RAG expands File.
- **MUST treat `risk: UNKNOWN` as unresolved, not as low.** An empty caller set is not evidence the symbol is unused — it can also mean the callers are not resolvable by the index (plain-object property access, dynamic dispatch, cross-language calls). `impact` pairs `UNKNOWN` with a `riskNote` saying so. Confirm with a text search before treating the symbol as safe to change or delete; do not proceed on the strength of a zero.
- **MUST use `query({search_query: "concept"})` for concepts/flows, `context({name: "symbolName"})` for a named symbol, or `impact` for blast radius, on read-only callers, dependencies, imports, or execution flow.** Graph first; text search only for empty/`UNKNOWN`/literals.
- For security review, `explain({target: "fileOrSymbol"})` lists taint findings (source→sink flows; needs `analyze --pdg`).

## Never Do

- NEVER edit a function, class, or method before MCP/CLI impact analysis.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis, and never read `UNKNOWN` as an all-clear — it means the walk could not answer, which is the one verdict that requires confirming by other means.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit before MCP/CLI graph change analysis.

## Resources

| Resource | Use for |
| --- | --- |
| `gitnexus://repo/flutter-clean-notes/context` | Codebase overview, check index freshness |
| `gitnexus://repo/flutter-clean-notes/clusters` | All functional areas |
| `gitnexus://repo/flutter-clean-notes/processes` | All execution flows |
| `gitnexus://repo/flutter-clean-notes/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
| --- | --- |
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
