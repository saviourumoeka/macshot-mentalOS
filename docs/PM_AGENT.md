# PM Agent — Documentation maintainer role

A role any agent (Claude Code, Codex, Gemini, Cursor, Ollama-hosted
local model) adopts when the user invokes the PM Agent. Triggers
include phrases like:

- *"run the PM agent"*
- *"audit the docs"*
- *"keep the docs honest"*
- *"docs sync pass"*

The user may also wire this up as a scheduled routine (cron / GitHub
Action / Claude Code skill). Behaviour is the same regardless of
trigger — read this file, follow the steps, write a report.

The goal: **`AGENTS.md`, `CLAUDE.md`, `README.md`, `docs/TASKS.md`,
`docs/AGENT_HANDOFF.md`, and `CHANGELOG.md` are always an accurate
description of the current code and the current state of work.**

---

## When to run

- After a non-trivial task is marked `Done` in `docs/TASKS.md`
- After a PR merges to `main` (release-candidate cut)
- Before opening a PR, if it touches more than a handful of files
- On user request, ad hoc

You are **not** running this on every commit. It's a deliberate pass.

---

## Procedure

### Step 0 — Confirm branching

You must be on a working branch off `dev`. If not, branch first:

```bash
git fetch origin
git checkout dev && git pull --ff-only origin dev
git checkout -b chore/pm-agent-docs-sync-$(date +%Y%m%d)
```

Never run the PM Agent directly on `main` or `dev`.

### Step 1 — Mechanical audit

Run the audit script and read its output. It is fast and catches the
boring things:

```bash
scripts/audit-docs.sh
```

The script reports:

- Broken relative links inside markdown files
- File / directory paths referenced in docs that no longer exist
- Symbols (Swift types, function names) referenced in docs that no
  longer exist in the source tree
- Stale section drift between `AGENTS.md` and `CLAUDE.md` (overlapping
  topics that disagree)
- `TASKS.md` consistency: every `## Active` / `## Blocked` / `## Done`
  task block has the required fields, no orphan task ids in commit
  messages without a matching block, and `Last touched` dates parse

Fix every mechanical finding before proceeding. Do not skip — these
are the rot signals.

### Step 2 — Human-judgement audit

For each of the following, read the current state of the code and ask
"is the doc still true?". If not, edit.

- **`README.md`** — feature list, screenshots references, install
  instructions, badge URLs. Anything user-facing.
- **`CLAUDE.md`** — file structure, architecture sections, coding
  conventions. Especially the file map under "File Structure" — it
  should match `find macshot -name '*.swift'` (modulo grouping).
- **`AGENTS.md`** — gotchas, build instructions, out-of-scope list.
- **`CONTRIBUTING.md`** — still accurate for outside contributors.
- **`CHANGELOG.md`** — is the unreleased section reflecting recent
  merges? Don't fabricate entries; just check.
- **`docs/TASKS.md`** — every task in `## Done` has a final progress
  entry with commit SHA. No task languishing in `## Active` for
  weeks without progress (flag those to the user).
- **`docs/AGENT_HANDOFF.md`** — protocol still matches reality (e.g.
  if branching strategy changed, this file says so).

### Step 3 — Cross-reference invariants

These pairs must agree. Re-derive each one from the source of truth
and update the dependent doc if drift is found.

| Invariant | Source of truth | Dependent doc(s) |
| --- | --- | --- |
| Bundle id | `macshot.xcodeproj/project.pbxproj` | `CLAUDE.md`, `AGENTS.md`, `scripts/build-local-prod.sh` |
| Min macOS version | `MACOSX_DEPLOYMENT_TARGET` in `project.pbxproj` | `CLAUDE.md`, `AGENTS.md`, `README.md` |
| Sparkle feed URL | `macshot/Info.plist` | `CLAUDE.md` releasing section, `appcast.xml` |
| Hotkey default | `HotkeyManager.swift` defaults | `README.md`, `CLAUDE.md` |
| Annotation tool count | `AnnotationTool` enum in `Annotation.swift` | `CLAUDE.md`, `README.md` feature list |
| Entitlements | `macshot/macshot.entitlements` | `CLAUDE.md` "Project Setup" |
| Local-build script flags | `scripts/build-local-prod.sh --help` | `AGENTS.md` §4 |

### Step 4 — TASKS triage

For every task in `## Active`:

- If `Last touched` is more than 14 days ago, flag it to the user as
  potentially stale. Do not silently move it; the user decides.
- If the linked branch (`Branch: feat/...`) has been deleted on the
  remote, flag it.
- If acceptance-criteria checkboxes have all been ticked but the task
  is not yet `Done`, ask the user whether to close it.

For every task in `## Blocked`:

- If the `Blocked on:` reason no longer holds (the dependency landed,
  the question was answered), suggest unblocking.

### Step 5 — Write the report

Write findings to `docs/PM_REPORTS/YYYY-MM-DD.md`. Format:

```markdown
# PM Agent report — YYYY-MM-DD

**Branch:** chore/pm-agent-docs-sync-YYYYMMDD
**Triggered by:** <user request | scheduled | post-merge>

## Mechanical findings
- ...

## Human-judgement findings
- ...

## Drift fixed
- <doc>: <one-line summary> (commit <sha>)

## Flagged for user attention
- ...

## Suggested next actions
- ...
```

Commit the report and any doc fixes as one or more
`docs(pm-agent): ...` commits. Open a PR back to `dev` titled
`docs: PM Agent sync — YYYY-MM-DD`. Do **not** auto-merge.

---

## Constraints

- **Edit docs only.** The PM Agent does not refactor code, change
  behaviour, or touch CI / entitlements. If you find a code-level
  issue, file it as a `## Active` task in `TASKS.md` (or flag it for
  the user) — don't fix it under this role.
- **Do not invent tasks.** The PM Agent does not create new product
  work. Only triage existing items.
- **Do not delete history.** Stale `## Done` tasks stay. Old PM
  reports stay.
- **Be terse.** A 30-line report beats a 300-line one. The user reads
  every line.
- **One PR per pass.** Do not run the PM Agent again on top of an
  open PM Agent PR — wait for the previous one to merge or close.

---

## Vendor-specific wiring (optional)

Tools that benefit from native invocations:

- **Claude Code:** add a slash command at `.claude/commands/pm-agent.md`
  that simply says *"Read `docs/PM_AGENT.md` and execute the
  procedure."* — no other content needed; the role file is the prompt.
- **Codex / Gemini / Cursor / Ollama:** invoke as
  *"Read `docs/PM_AGENT.md` and execute the procedure."* No special
  config required.
- **Scheduled (GitHub Action / cron):** trigger an agent with the
  same one-line prompt. Schedule weekly or after each PR-to-`main`
  merge — not more often.

The role definition is intentionally tool-agnostic. If a vendor adds
new agent infrastructure, the wrapper goes in that vendor's config —
this file does not change.
