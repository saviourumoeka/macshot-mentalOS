# Agent Hand-off Protocol

This file is the contract between Claude sessions working on
`macshot-mentalOS`. The user often switches between sessions, days,
and machines, and expects the next agent to pick up exactly where the
last one stopped — without re-asking what was done.

## The contract

1. **Read `docs/TASKS.md` first.** Every session, before doing
   anything else. The user saying *"check current tasks"*, *"continue
   where we left off"*, or just *"go"* means: open `TASKS.md`, find
   the top item under `## Active`, and resume it.

2. **Before resuming, check whether the top Active task is already
   finished.** Open the task block. If *every* acceptance-criteria
   checkbox is `[x]`, the latest Progress-log entry references a
   commit on the task's branch, and `git log -1 --format=%cr
   <task-branch>` reports less than 4 hours, the engineering work
   is done. Your tick's job is then:

   - Push the branch: `git push -u origin <task-branch>`
     (pre-approved in `~/.claude/settings.json` for `feat/task-*`,
     `chore/task-*`, `fix/task-*`).
   - Append a one-line Progress-log entry: *"YYYY-MM-DD HH:MM —
     branch pushed, awaiting PR review. Commit: <sha>. Next: open
     PR to dev / wait for mentalos-qa pass."*
   - Promote the next `Pending` task to `Active` and start that
     instead.

   Do **not** re-implement work that is already committed. Re-reading
   source files to confirm a commit is fine; producing a duplicate
   commit is not — it burns a full tick of tokens for no progress.

3. **Pick exactly one task at a time.** If `## Active` has more than
   one item, pick the one whose `Last touched` is most recent — that
   is what the previous agent was working on. Do not start a new task
   while another is `in_progress`. If the user names a specific task
   ID (e.g. *"work on TASK-004"*), that wins.

4. **Append a Progress log entry on every meaningful step.** Not just
   on completion. Each entry is timestamped (`YYYY-MM-DD HH:MM` local
   time, the same date format used in commit messages) and explains
   *what changed*, *what was learned*, and *what is left*. Treat the
   Progress log as the only memory the next agent has — write so a
   stranger can read it cold and continue.

   **Required suffix on every entry:** end with `Commit: <sha>` (the
   short SHA of the commit produced by this tick, or `Commit: none`
   if no commit was made) and `Next: <one-line expected next step>`
   (what the *following* tick should pick up). The fast-path in
   item 2 depends on these being present and accurate.

5. **Status transitions:**

   - `Pending` → `Active`: when you start work. Set `Owner-agent` and
     `Last touched`.
   - `Active` → `Blocked`: when you cannot proceed. Add a `Blocked
     on:` line explaining why and what unblocks it. Move the entry
     under `## Blocked`.
   - `Active` → `Done`: only when **every** acceptance-criteria
     checkbox is ticked AND a verification step has been executed
     (built, ran, tailed log, etc.). Move the entry under `## Done`
     with a final progress entry summarising the outcome and the
     final commit SHA. Do not delete done tasks — the trail matters.

6. **Acceptance criteria are immutable once a task is `Active`.** If
   the work no longer matches the criteria, you have a different
   task. Close this one as `Cancelled` (a fourth status; rare) and
   open a new one rather than silently changing scope.

7. **Commits and tasks stay aligned.** Reference the task ID in every
   commit message: `feat(TASK-003): add embedding provider`. This
   makes `git log --grep=TASK-003` a complete audit trail.

8. **Branching.** All task work happens on `feat/...`, `fix/...`, or
   `chore/...` branches off `dev`. Never commit directly to `main`.
   When a task spans many commits, keep them on a single branch named
   after the task (e.g. `feat/task-003-embedding-provider`).

9. **When in doubt, ask the user.** Do not silently change task
   scope, acceptance criteria, or priority. Use `AskUserQuestion`.

## Task block template

```
### TASK-NNN: <short title>

- **Status:** Pending | Active | Blocked | Done | Cancelled
- **Owner-agent:** Claude (session label, e.g. "opus 4.7 — 2026-05-10")
- **Created:** YYYY-MM-DD
- **Last touched:** YYYY-MM-DD HH:MM
- **Branch:** feat/task-NNN-slug
- **Files touched:** path/one.swift, path/two.swift
- **Acceptance criteria:**
  - [ ] Criterion one
  - [ ] Criterion two
- **Blocked on:** (only when Status = Blocked)

#### Progress log

- **YYYY-MM-DD HH:MM** — Description of what changed, what was learned,
  what is left. Commit: <sha>.
```

## Quick commands

```sh
# Start: list active tasks
grep -E "^### TASK-" docs/TASKS.md
grep -A 1 "^### TASK-" docs/TASKS.md | grep "Status:"

# Tail the log while debugging
tail -f ~/Library/Containers/com.sw33tlie.macshot.macshot/Data/Library/Logs/com.sw33tlie.macshot/macshot.log

# Build sanity (Debug)
xcodebuild -scheme macshot -configuration Debug build 2>&1 | grep -E "error:|warning:" | tail -20

# Build sanity (Release — strict concurrency, run before tagging)
xcodebuild -scheme macshot -configuration Release build 2>&1 | grep "error:"
```
