## Agent skills

### Delegation policy — Antigravity does the work, Claude coordinates

**Default: dispatch real work (code changes, content authorship, test writing, bulk edits) to Google Antigravity via its headless CLI, not the main Claude Code thread.** Claude's role on this project is coordinator, not implementer:
1. Write a self-contained task brief (exact files, exact strings/patterns, reference commits to copy style from, verification commands, commit message format incl. `Co-Authored-By: Google Antigravity <antigravity@google.com>` — never sign Antigravity's commits as Claude/Anthropic).
2. Save the brief to a file, then dispatch it in the background:
   ```
   agy --add-dir "<worktree path>" --dangerously-skip-permissions --output-format json --print-timeout 20m -p "$(cat <brief-file>)"
   ```
   (`agy.exe` lives at `C:\Users\nguye\AppData\Local\agy\bin\agy.exe`; use `run_in_background: true`.)
3. **Never trust its self-report or the wrapper's exit code.** Verify independently: `git log`/`git status` for real commits, then re-run `flutter analyze`, the relevant `flutter test` targets, and GitNexus `detect-changes` yourself before calling a task done.

Known `agy` headless quirks (full detail in `docs/agents/antigravity-collab.md`): stdout can silently drop over a non-TTY pipe — the wrapper reports a false `failed`/`timeout` even though `agy.exe` finished and committed correctly, so judge completion by `git log`, not the command's exit code. It can also genuinely hang; if a background run shows no file/commit activity for a long stretch AND memory/CPU look idle, it's safe to kill and redispatch on a clean tree — but if it's still actively working (mem/CPU moving), let it run to completion rather than interrupting.

Exception: a trivial read-only check that produces no file diff (a `grep` to confirm dead code, a quick status check) is cheaper to just do directly — an `agy` run costs real minutes and its own quota even for a 5-second grep. Use judgment there; the default is to delegate anything that actually changes a file.

Fall back to a Haiku subagent (`Agent` tool, `subagent_type: general-purpose`, `model: haiku`) only if `agy` is unavailable — same briefing discipline applies (point it at an already-committed reference file, give exact verification commands), and it needs even more explicit instructions than Antigravity and can miss edge cases (e.g., autoDispose Riverpod providers being sensitive to widget-mount timing in tests).

### Issue tracker

GitHub Issues (`nguyendong47/flutter-clean-notes`), via `gh` CLI. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context — `CONTEXT.md` + `docs/adr/` at repo root (created lazily when needed). See `docs/agents/domain.md`.

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **flutter-clean-notes** (8869 symbols, 19545 relationships, 240 execution flows).

> Index stale? Run `node .gitnexus/run.cjs analyze --index-only` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? Bootstrap with `npx`, `bunx`, or `pnpm dlx` — e.g. `bunx gitnexus@latest analyze` (npm 11 npx crash; #1939).

## Always Do

- **MUST run impact analysis before editing.** Use `impact({target: "symbolName", direction: "upstream"})` (MCP) or `node .gitnexus/run.cjs impact "symbolName" --direction upstream --repo .` (CLI fallback); report callers, processes, and risk. Never substitute grep for graph analysis.
- **MUST analyze graph changes before committing.** Use `detect_changes({scope: "all"})` (MCP) or `node .gitnexus/run.cjs detect-changes --scope all --repo .` (CLI fallback). `partial: true` or `truncated: true` is not a clean check — a zero means unseen, not unaffected; re-run it. For regression review: `detect_changes({scope: "compare", base_ref: "main"})` or `node .gitnexus/run.cjs detect-changes --scope compare --base-ref "main" --repo .`.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- **MUST treat `risk: UNKNOWN` as unresolved, not as low.** An empty caller set is not evidence the symbol is unused — it can also mean the callers are not resolvable by the index (plain-object property access, dynamic dispatch, cross-language calls). `impact` pairs `UNKNOWN` with a `riskNote` saying so. Confirm with a text search before treating the symbol as safe to change or delete; do not proceed on the strength of a zero.
- When exploring unfamiliar code, use `query({search_query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `context({name: "symbolName"})`.
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
