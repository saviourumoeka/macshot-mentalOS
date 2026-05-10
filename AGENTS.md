# AGENTS.md — Multi-agent contract for macshot-mentalOS

**Read this first, every session, regardless of which model or tool you are.**

This file is the canonical, vendor-neutral entry point for every AI agent
working on this repo — Claude Code, Codex, Gemini CLI, Cursor, Aider,
Continue, locally-hosted Ollama agents, and anything we add later. If your
tool also reads `CLAUDE.md` / `GEMINI.md` / `.cursorrules`, those exist as
thin pointers back to this file. **The source of truth is here.**

If you only have time to read three files, read these in order:

1. `AGENTS.md` (this file) — how to operate
2. `docs/TASKS.md` — what to work on
3. `docs/AGENT_HANDOFF.md` — task-state protocol

Everything else is reference material, fetched on demand.

---

## 1. What this project is

macshot-mentalOS is a fork of [`sw33tLie/macshot`](https://github.com/sw33tLie/macshot)
— a native macOS screenshot/annotation tool — extended with a private
"MentalOS" layer (capture OCR, contextual recall, chat, notes, search,
local-AI sidecar). Pure Swift + AppKit. No SwiftUI except where Apple
forces it (mesh gradients). No Electron, no Qt.

- **Min target:** macOS 12.3
- **Bundle id (Release):** `com.sw33tlie.macshot.macshot`
- **Sandbox:** enabled — see `macshot/macshot.entitlements`
- **Project file:** `macshot.xcodeproj` (file-system-synced groups — just
  drop `.swift` files into `macshot/` and Xcode picks them up)

The detailed architecture, file map, and coding conventions live in
`CLAUDE.md`. Do not duplicate them here — read that file when you need
implementation context.

---

## 2. Branching & commits — non-negotiable

- **Never commit to `main` directly.** `main` only receives merges via PR.
- **Always branch off `dev`.** Branch names: `feat/...`, `fix/...`,
  `chore/...`, `docs/...`. When working a task from `docs/TASKS.md`,
  encode the task id: `feat/task-003-embedding-provider`.
- **One commit per logical unit of work.** Conventional commits
  (`feat:`, `fix:`, `chore:`, `docs:`). Reference the task id when
  applicable: `feat(TASK-003): add embedding provider`.
- **Tag risky operations** with `git tag checkpoint-<name>` before
  destructive steps so they're reversible.
- **PRs target `dev` for ongoing work.** PR `dev → main` only when the
  user asks for a release-candidate merge.

If you're about to `git push` to a remote, confirm with the user first
unless the user has already authorised the push for the current task.

---

## 3. Task hand-off protocol

`docs/TASKS.md` is the queue. `docs/AGENT_HANDOFF.md` is the contract.
Read both before starting work. The short version:

1. Find the top item under `## Active` (or the one with the most-recent
   `Last touched`).
2. Move it to `## Active` with `Status: in_progress`, set `Owner-agent`,
   set `Last touched`.
3. Append a `Progress log` entry **on every meaningful step** —
   timestamped, written for a stranger to pick up cold.
4. Acceptance criteria are immutable once a task is in_progress. If
   scope changes, cancel the task and open a new one.
5. Mark `Done` only when every acceptance checkbox is ticked **and**
   verification (build / run / log tail) has been executed.

When in doubt, ask the user. Do not silently change scope.

---

## 4. Building locally for daily use

The user runs the fork as their daily-driver. To produce a Release
build that installs over `/Applications/macshot.app` and survives
across rebuilds without re-prompting for permissions:

```bash
scripts/build-local-prod.sh              # pull main, build, install, launch
scripts/build-local-prod.sh --no-pull    # rebuild current checkout as-is
scripts/build-local-prod.sh --reset-tcc  # also reset TCC grants (rare)
```

The script:

- Signs with the user's **Apple Development** keychain identity so the
  codesign designated requirement is stable across rebuilds — TCC
  permissions (Screen Recording, Accessibility) granted once persist.
- Strips Sparkle (`SUFeedURL`, `SUEnableAutomaticChecks`) from the
  installed `Info.plist` so the local fork build cannot be silently
  replaced by an upstream `sw33tLie/macshot` release.
- Re-signs after `Info.plist` mutation **while preserving sandbox
  entitlements** from `macshot/macshot.entitlements`. Naive
  `codesign --force --deep` drops them — do not use that.

If a build fails, do not switch to ad-hoc signing as a shortcut. Diagnose
the actual cause. Ad-hoc signing breaks TCC persistence — every rebuild
will look like a different app and re-prompt.

The CI release pipeline (`.github/workflows/build-release.yml`) is
**separate** and untouched by this script. Do not modify CI to mimic
local behaviour.

---

## 5. Tools, conventions, gotchas

These are the things agents most often get wrong. Read `CLAUDE.md` for
the full set; the highlights:

- **Pure AppKit.** No SwiftUI except `BeautifyRenderer` (mesh gradients,
  `@available(macOS 15+)`).
- **No new dependencies** unless absolutely necessary. Apple frameworks
  preferred.
- **Strict concurrency.** CI builds with `-Owholemodule` which enforces
  strict Swift concurrency. Local Debug builds do **not** catch these
  errors. Before claiming a task is done, verify with a Release build:
  `xcodebuild -scheme macshot -configuration Release build 2>&1 | grep "error:"`
- **Coordinate systems.** Overlay vs Editor mapping rules are subtle
  and have caused regressions — see the "Overlay vs Editor coordinate
  rules" section of `CLAUDE.md` before touching `OverlayView`,
  `EditorView`, or anything that converts between view and canvas
  space.
- **Annotation is a class, not a struct.** When adding a property,
  update three places: the declaration, `clone()`, and
  `CodableAnnotation` in `AnnotationCodable.swift`. The compiler will
  not catch a missing field — annotations will silently lose data.
- **Keyboard shortcuts** for Cmd+letter must use `event.keyCode`, never
  `event.charactersIgnoringModifiers` (breaks on non-Latin layouts).
- **Focus management** is centralised in
  `AppDelegate.returnFocusIfNeeded()`. Do not inline
  `setActivationPolicy` / `activate` calls.

---

## 6. Documentation maintenance — the PM Agent role

Documentation rots fast on a project this size. Every session ends
with a small chance of leaving `TASKS.md`, `CLAUDE.md`, `README.md`,
or this file slightly out of step with reality. To keep humans and
agents pointed at the truth:

- **Any agent**, when the user invokes the PM Agent role (commands like
  *"run the PM agent"*, *"audit the docs"*, *"keep the docs honest"*),
  should follow the procedure in [`docs/PM_AGENT.md`](docs/PM_AGENT.md).
- The mechanical pre-check is `scripts/audit-docs.sh` — run it first to
  catch broken links, stale paths, missing task references, and
  doc/code drift before doing the human-judgement pass.
- The PM Agent role is **not Claude-specific.** Codex, Gemini, and
  Ollama-hosted agents adopt the same role by reading the same file.
  Treat `docs/PM_AGENT.md` as the contract.

The user may also wire this up as a scheduled routine (cron, GitHub
Action, Claude Code skill). The role definition stays the same
regardless of trigger.

---

## 7. Communication style with the user

The user is a Staff Engineer peer, autonomy is HIGH (per their global
operating model). Concretely:

- **No preambles.** Don't open with "Let me…" or "Great!". State
  results directly.
- **No progress narration.** Brief updates at key moments — finding,
  changing direction, hitting a blocker. Otherwise silent.
- **Report blockers, not progress.** If you're stuck, say so with
  options. If you're not stuck, just keep going.
- **Default to action on reversible work** (edits, tests, branches,
  commits). **Ask first** for anything that affects shared state
  (`git push`, PR open/close, modifying secrets, dropping data, package
  installs that aren't well-known safe ones).
- **End-of-turn summary:** one or two sentences. What changed, what's
  next.

---

## 8. Things that are out of scope for any agent

Without explicit user authorisation, do **not**:

- Push to the `sw33tLie/macshot` upstream remote.
- Modify the CI workflow (`.github/workflows/build-release.yml`) or
  the Sparkle appcast (`appcast.xml`).
- Bump `MARKETING_VERSION` or create release tags.
- Change `macshot.entitlements`.
- Touch `.env` files or anything containing secrets.
- Disable security checks (`--no-verify`, `--no-gpg-sign`, etc.).

If you think one of these is required for the task, stop and ask.
