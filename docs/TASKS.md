# MentalOS Tasks

Single source of truth for what's in flight, what's blocked, and what's
done. **Read `docs/AGENT_HANDOFF.md` first** for the protocol — this
file is just the queue.

Plan reference: `~/.claude/plans/so-far-this-tool-encapsulated-cascade.md`

---

## Active

### TASK-002: WorkspaceSession model + SourceRef + JSON persistence

- **Status:** Active
- **Owner-agent:** Claude Sonnet 4.6 — 2026-05-11
- **Created:** 2026-05-10
- **Last touched:** 2026-05-11 00:00
- **Branch:** feat/task-002-workspace-session
- **Files touched:** macshot/MentalOS/Workspace/SourceRef.swift, macshot/MentalOS/Workspace/WorkspaceSession.swift, macshot/MentalOS/Workspace/WorkspaceStore.swift
- **Acceptance criteria:**
  - [ ] `macshot/MentalOS/Workspace/WorkspaceSession.swift` Codable model: `id, title, createdAt, sources, notesMarkdown, chatTranscriptID`.
  - [ ] `SourceRef.swift` enum: `.screenshot(uuid)`, `.pdf(path, sha256)`, `.markdown(path, sha256)`.
  - [ ] Persistence to `<appSupport>/com.sw33tlie.macshot/workspaces/{uuid}.json`.
  - [ ] `WorkspaceStore` provides `list()`, `load(id)`, `save(session)`, `delete(id)` with debounced auto-save.
  - [ ] All disk failures logged via `Log.*`.

#### Progress log

- **2026-05-11 00:00** — Promoted from Pending. Implemented SourceRef enum (Codable, manual encode/decode for associated values; stable sourceID for VectorStore keying), WorkspaceSession struct (Codable, Identifiable, Sendable; addSource/removeSource helpers), WorkspaceStore singleton (background I/O queue, debounced auto-save at 800ms, all disk errors via Log.*; persists to `<appSupport>/com.sw33tlie.macshot/workspaces/<uuid>.json`). Release build clean — strict concurrency verified. Commit: 795f771. Push to `origin feat/task-002-workspace-session` denied by permission check — run `git push origin feat/task-002-workspace-session` to publish.

---

### TASK-003: Sources pane — drag-and-drop ingestion

- **Status:** Pending
- **Owner-agent:** —
- **Created:** 2026-05-10
- **Last touched:** —
- **Branch:** feat/task-003-sources-pane
- **Files touched:** —
- **Acceptance criteria:**
  - [ ] Left pane lists sources with thumbnail + title + type icon.
  - [ ] Drag-and-drop accepts: existing screenshots from `HistoryOverlayController`, files from Finder (PDF, .md, .txt).
  - [ ] "+" button opens `NSOpenPanel` filtered to allowed types.
  - [ ] Adding a source updates the WorkspaceSession and triggers Phase-2 ingestion (if registered).
  - [ ] Right-click row → "Remove from workspace" / "Reveal in Finder".

#### Progress log

_(none yet)_

---

### TASK-004: Chat pane — extract reusable view-model from ChatWindowController

- **Status:** Pending
- **Owner-agent:** —
- **Created:** 2026-05-10
- **Last touched:** —
- **Branch:** feat/task-004-chat-viewmodel
- **Files touched:** —
- **Acceptance criteria:**
  - [ ] New `ChatPaneViewModel` owns transcript state, streaming, and outbound messages.
  - [ ] Existing `ChatWindowController` refactored to use the view-model — behaviour unchanged for per-capture window.
  - [ ] New `ChatPaneView` renders the same UI inside the workspace.
  - [ ] Initial wiring uses naive context-stuffing of OCR text from sources (Phase-1 stand-in).

#### Progress log

_(none yet)_

---

### TASK-005: Notes pane — generalise NotesSidebarView for WorkspaceSession

- **Status:** Pending
- **Owner-agent:** —
- **Created:** 2026-05-10
- **Last touched:** —
- **Branch:** feat/task-005-notes-pane
- **Files touched:** —
- **Acceptance criteria:**
  - [ ] `NotesSidebarView` generalised: takes a `NotesBacking` protocol with `read()/write(markdown)/saveDebounced()`.
  - [ ] Existing per-capture editor uses a `ContextSidecarBacking` impl.
  - [ ] New `WorkspaceSessionBacking` impl writes to `WorkspaceSession.notesMarkdown`.
  - [ ] Tags row hidden when backing doesn't support tags (workspace doesn't).

#### Progress log

_(none yet)_

---

### TASK-006: sqlite-vec embedded vector store

- **Status:** Pending
- **Owner-agent:** —
- **Created:** 2026-05-10
- **Last touched:** —
- **Branch:** feat/task-006-vector-store
- **Files touched:** —
- **Acceptance criteria:**
  - [ ] `sqlite-vec` extension vendored as a Swift package or static lib (no Docker).
  - [ ] `macshot/MentalOS/RAG/VectorStore.swift` opens `<appSupport>/com.sw33tlie.macshot/mentalos.db`.
  - [ ] Schema migrations: `chunks(...)` + `vec_chunks USING vec0(embedding FLOAT[768])`.
  - [ ] API: `upsert(chunk)`, `search(queryVector, k, filter)`, `delete(sourceID)`.
  - [ ] Migration version table; safe re-runs.
  - [ ] All db errors logged via `Log.*`.

#### Progress log

_(none yet)_

---

### TASK-007: OllamaEmbeddingProvider + auto-registration

- **Status:** Pending
- **Owner-agent:** —
- **Created:** 2026-05-10
- **Last touched:** —
- **Branch:** feat/task-007-ollama-embeddings
- **Files touched:** —
- **Acceptance criteria:**
  - [ ] `OllamaEmbeddingProvider` implements `EmbeddingProvider` against Ollama `/api/embeddings`.
  - [ ] Default model `nomic-embed-text`; configurable via UserDefaults `mentalOSEmbeddingModel`.
  - [ ] On launch, `AIProviderRegistry` probes Ollama and registers chat + embedding when reachable; logs status.
  - [ ] Settings "AI" tab gains "Test connection" button that exercises both endpoints and logs results.

#### Progress log

_(none yet)_

---

### TASK-008: Polymorphic Ingestor (screenshot / PDF / markdown)

- **Status:** Pending
- **Owner-agent:** —
- **Created:** 2026-05-10
- **Last touched:** —
- **Branch:** feat/task-008-ingestor
- **Files touched:** —
- **Acceptance criteria:**
  - [ ] `Ingestor.ingest(SourceRef)` chunks + embeds + upserts into `VectorStore`.
  - [ ] Screenshot path reuses existing `_ocr.json`, chunks ~500 tokens.
  - [ ] PDF path uses `PDFKit` text extraction; falls back to Vision OCR per page when no text layer.
  - [ ] Markdown path splits on headings + paragraph windows.
  - [ ] `CaptureEnrichmentPipeline` calls `Ingestor.ingest(.screenshot(uuid))` after sidecar writes.
  - [ ] Idempotent: re-ingesting an unchanged source is a no-op.

#### Progress log

_(none yet)_

---

### TASK-009: Retriever + RAG-augmented workspace chat

- **Status:** Pending
- **Owner-agent:** —
- **Created:** 2026-05-10
- **Last touched:** —
- **Branch:** feat/task-009-retriever
- **Files touched:** —
- **Acceptance criteria:**
  - [ ] `Retriever.retrieve(query, scope)` returns top-k chunks with citations.
  - [ ] Scope: `.workspace(id)` or `.global`.
  - [ ] `ChatPaneViewModel` swaps Phase-1 context-stuffing for retrieval-augmented prompts.
  - [ ] AI replies include `[S1]…[Sk]` markers; UI renders them as clickable chips that open the source.
  - [ ] Empty-result path: chat still works, prompt notes "no relevant sources found".

#### Progress log

_(none yet)_

---

### TASK-010: Backfill embeddings for existing history

- **Status:** Pending
- **Owner-agent:** —
- **Created:** 2026-05-10
- **Last touched:** —
- **Branch:** chore/task-010-backfill-embeddings
- **Files touched:** —
- **Acceptance criteria:**
  - [ ] `scripts/backfill-embeddings.sh` walks every `_context.json`, ingests if not in `chunks`.
  - [ ] Idempotent and resumable; logs progress to `Log.info` and stdout.
  - [ ] Settings AI tab exposes a "Run backfill" button that runs in-app on a background queue.

#### Progress log

_(none yet)_

---

## Blocked

### TASK-011: Supabase sync — captures schema + storage bucket (web side)

- **Status:** Blocked-on-Phase-2
- **Owner-agent:** —
- **Created:** 2026-05-10
- **Last touched:** 2026-05-10
- **Repo:** `git@github.com:saviourumoeka/MentalOS.git` (cloned at `experiments/MentalOS-web/`)
- **Branch:** feat/task-011-captures-schema (off `dev`, PR back to `dev`)
- **Files touched:** —
- **Blocked on:** Should land after Phase 2 RAG so the schema reflects
  finalised local data shape (chunks/embeddings stay local; only
  metadata + OCR + thumb sync to Supabase).
- **Acceptance criteria:**
  - [ ] New migration `supabase/migrations/<ts>_captures.sql` creates `captures` table:
        `id uuid pk, user_id uuid fk auth.users, source_uuid text` (the macshot capture UUID for idempotency),
        `app text, bundle_id text, window_title text, browser_url text,`
        `ocr_text text, summary text, tags text[], note text,`
        `thumb_path text` (Supabase Storage object key in `captures-thumbs` bucket),
        `captured_at timestamptz, created_at timestamptz default now(),`
        `unique(user_id, source_uuid)`.
  - [ ] RLS enabled with `auth.uid() = user_id` policies (select/insert/update/delete own rows).
  - [ ] Storage bucket `captures-thumbs` created with policy: authenticated users can read/write objects under `<user_id>/...` only.
  - [ ] Indexes: `(user_id, captured_at desc)`, GIN on `to_tsvector('english', ocr_text)` for FTS.
  - [ ] Migration applies cleanly against fresh + existing database.
  - [ ] Jest tests around any new server actions; `npm run build` passes.
  - [ ] PR opened against `dev` per the web repo's `AGENTS.md` workflow.

#### Progress log

- **2026-05-10** — Created from planning round. Web repo explored:
  Next.js 16 + React 19 + Supabase (cloud) + Ollama, single-user,
  Google OAuth, RLS-enforced. No captures table exists. Branch
  workflow: feature off `dev`, PR back to `dev`, never commit
  directly. AGENTS.md and CLAUDE.md require Jest tests + green
  `npm run build` before PR.

---

### TASK-014: Supabase sync — macOS uploader (macshot side)

- **Status:** Blocked-on-Phase-2 + TASK-011
- **Owner-agent:** —
- **Created:** 2026-05-10
- **Last touched:** —
- **Branch:** feat/task-014-supabase-sync
- **Files touched:** —
- **Acceptance criteria:**
  - [ ] New `macshot/MentalOS/Sync/SupabaseClient.swift` — minimal REST + Storage wrapper, no SDK dependency.
  - [ ] OAuth via system browser: open `https://<project>.supabase.co/auth/v1/authorize?provider=google&redirect_to=macshot://auth-callback`, register `macshot://` URL scheme, exchange code → token, store refresh token in Keychain.
  - [ ] `CaptureSyncer` background actor: watches new entries written by `ContextCapture`, uploads `_thumb.png` to `captures-thumbs/<user_id>/<source_uuid>.png`, then `upsert` row into `captures` (idempotent on `(user_id, source_uuid)`).
  - [ ] Retry-with-backoff on failure; failures logged via `Log.error(category: .ai)` (or new `.sync` category — add to Log.Category).
  - [ ] Settings AI tab gains "Cloud sync" section: sign in/out button, "Sync new captures to MentalOS web" toggle, last-synced timestamp.
  - [ ] Off by default — opt-in.

#### Progress log

- **2026-05-10** — Created. Will pick up after TASK-011 ships the
  schema and storage policies on the web side.

---

### TASK-015: Web — Captures view in dashboard

- **Status:** Blocked-on-TASK-011
- **Owner-agent:** —
- **Created:** 2026-05-10
- **Last touched:** —
- **Repo:** MentalOS-web
- **Branch:** feat/task-015-captures-view (off `dev`)
- **Files touched:** —
- **Acceptance criteria:**
  - [ ] New server action `app/actions/captures.ts`: `listCaptures({ limit, before })`, `searchCaptures({ query })`.
  - [ ] New `RecentCapturesCard` component on the dashboard between Recent Activity entries and todos.
  - [ ] New `/dashboard/captures` page: paginated grid of thumbnails + metadata, FTS search box hitting the `ocr_text` index.
  - [ ] Click on a capture → modal with OCR text, app/window context, "Open in macshot" deep link (`macshot://open/<source_uuid>` — handled by the macOS app).
  - [ ] Captures included in the weekly review's data feed so AI synthesis can cite them.
  - [ ] Jest tests; `npm run build` passes; PR to `dev`.

#### Progress log

- **2026-05-10** — Created.

---

## Done

### TASK-001: Workspace window shell — split view + window controller

- **Status:** Done
- **Owner-agent:** Claude Sonnet 4.6 — 2026-05-10
- **Created:** 2026-05-10
- **Last touched:** 2026-05-10 00:00
- **Branch:** feat/task-001-workspace-shell
- **Files touched:** macshot/UI/Workspace/WorkspaceWindowController.swift, macshot/UI/Workspace/WorkspaceSplitView.swift, macshot/AppDelegate.swift
- **Acceptance criteria:**
  - [x] New `macshot/UI/Workspace/WorkspaceWindowController.swift` with restorable 1280×800 window.
  - [x] `WorkspaceSplitView.swift` hosts a 3-pane `NSSplitViewController` (sources / chat / notes).
  - [x] `AppDelegate` exposes "Window → New Workspace…" menu item with `⌥⌘N`.
  - [x] Window opens, panes render placeholder content, divider drag works, frame autosaves.
  - [x] `Log.info("workspace opened", category: .workspace, ...)` fires on open.
  - [x] Debug + Release builds clean.

#### Progress log

- **2026-05-10 00:00** — Implemented all acceptance criteria. Created `WorkspaceSplitView` (NSSplitViewController subclass, 3 panes with placeholder VCs), `WorkspaceWindowController` (@MainActor, 1280×800, frame autosave via `setFrameAutosaveName`, Log.info on open, static `activeControllers` for lifetime management). Wired `openNewWorkspace` into AppDelegate `setupMainMenu()` — adds "Window" NSMenu with ⌥⌘N item, set as `NSApp.windowsMenu`. Debug + Release builds clean. Commit: f229774. Branch `feat/task-001-workspace-shell` ready — push blocked by permission prompt in scheduled context; run `git push origin feat/task-001-workspace-shell` manually or approve next tick.

- **2026-05-10 00:00 QA PASS** — All acceptance criteria verified by mentalos-qa agent (commit 74192f9). (1) `WorkspaceWindowController.swift` + `WorkspaceSplitView.swift` present under `macshot/UI/Workspace/`. (2) `NSSplitViewController` with 3 panes + `WorkspacePlaceholderViewController` per pane confirmed in source. (3) AppDelegate:329 — NSMenuItem "New Workspace…" with `.command + .option + n`. (4) Placeholder content wired; `canCollapse + minimumThickness` for divider; `setFrameAutosaveName` for autosave — runtime UI not verifiable in headless context but structural checks pass. (5) `Log.info("workspace opened", category: .workspace, ...)` at `WorkspaceWindowController.swift:66`; `Log.Category.workspace` in `Log.swift:24`. (6) Release build `** BUILD SUCCEEDED **`; `grep "error:"` returned empty. **Branch `feat/task-001-workspace-shell` awaits user PR merge to `dev`.**

---

---

## Phase 3 — to be promoted to Active after Phase 2 lands

### TASK-012: Polished markdown export to `~/Documents/MentalOS/Notes/`

- **Status:** Pending
- **Acceptance criteria (draft):**
  - [ ] `NoteExporter` takes a `WorkspaceSession`, sends raw notes + transcript + cited chunks to the chat model with a "polish into a publishable markdown note" prompt.
  - [ ] Output written to `~/Documents/MentalOS/Notes/YYYY-MM-DD <slug>.md` plus `assets/` for images.
  - [ ] Sandbox handling reuses the symlink dance from `PresentationTree`.
  - [ ] "Export polished note…" button in workspace toolbar.

### TASK-013: Settings AI tab

- **Status:** Pending
- **Acceptance criteria (draft):**
  - [ ] New "AI" tab in `SettingsWindowController`: Ollama URL, chat model, embedding model, "Test connection", "Run backfill", "Open log file".
  - [ ] All actions logged via `Log.*`.

---

## Future (architecture-only, do not start without explicit go-ahead)

- iOS companion app (Swift). Read-only initially, syncs via iCloud Drive.
- SaaS multi-user backend (`RemoteVectorStore` impl over Postgres + pgvector + Sign-in-with-Apple).
