# macshot — Local Production Install

This file records the state of the locally-installed daily-driver build at `/Applications/macshot.app`. The companion dev/MentalOS work continues on the `dev` branch; the installed prod app does not include any of it.

## Current install — 2026-05-10

| | |
|---|---|
| Installed at | `/Applications/macshot.app` |
| Source branch | `main` |
| Source commit | `0f2bdfa` — *ci: update appcast.xml for v4.1.0* |
| Marketing version | 4.1.0 |
| Build number (CFBundleVersion) | 4.1.0 |
| Bundle identifier | `com.sw33tlie.macshot.macshot` |
| Architectures | universal (`x86_64` + `arm64`) |
| Min macOS | 12.3 |
| Code signing | Apple Development — `saviourumoeka@gmail.com (AS9MJSKHZC)`, team `6BX9L8T3S4` |
| Codesign verify | `valid on disk`, `satisfies its Designated Requirement`, deep+strict pass |
| Gatekeeper assessment | `spctl` rejects (expected — no Developer ID cert; runs locally via Launch Services) |
| Sparkle framework | embedded (auto-update from `appcast.xml`) |
| Built from worktree | `../macshot-prod-build` (disposable, removable via `git worktree remove`) |

## Dev / prod isolation

To prevent Xcode dev sessions from corrupting the installed prod app's preferences, sandbox container, and Dock state, the **Debug** build configuration on the `dev` branch was changed to a separate bundle id:

| Build config | Bundle id | Branch |
|---|---|---|
| Release (this install) | `com.sw33tlie.macshot.macshot` | `main` |
| Debug (Xcode dev runs) | `com.sw33tlie.macshot.macshot.dev` | `dev` |

Effect: macOS treats them as two different apps — separate `~/Library/Preferences/*.plist`, separate sandbox containers under `~/Library/Containers/`, separate Login Items, separate Dock identity. Running both simultaneously is supported.

**One-time caveat caught during install:** a stale Debug binary built before the `.dev` change was running at install time and still claimed the prod bundle id. macOS rejects a second instance with the same id, so the prod app self-terminated on first launch. Resolution: kill the stale dev binary once; the next dev `Build & Run` from Xcode will produce the `.dev` build and the two coexist cleanly.

## End-to-end smoke verification

Project has no XCTest/UITest targets, so verification is a structured manual smoke pass against `/Applications/macshot.app` (not the Xcode-built binary). Automated checks were run; interactive flows are listed for the user to confirm.

### Automated (passed)
- ✅ Codesign deep+strict verification on installed bundle
- ✅ `CFBundleShortVersionString = 4.1.0`, `CFBundleIdentifier = com.sw33tlie.macshot.macshot`
- ✅ Universal binary (`lipo -archs` reports `x86_64 arm64`)
- ✅ Sparkle.framework embedded and signature-validated
- ✅ App launches as a process and stays resident (PID stable, no crash, no errors in `log show` for the `macshot` process during boot)
- ✅ No quarantine xattr (locally built, won't trip Gatekeeper on first open)

### Interactive (run these in front of the screen)
1. Menu-bar icon visible after launch; About menu shows version 4.1.0.
2. Global hotkey (Cmd+Shift+X by default) → fullscreen overlay appears on every connected display.
3. Drag a selection rectangle, draw an annotation (pencil/arrow/text), confirm with Enter — image lands in clipboard / saved to configured directory.
4. Open a capture in the editor window; draw, save; reopen and confirm persistence.
5. Open Preferences, change a value (e.g., image format), quit, relaunch — value persists in `~/Library/Preferences/com.sw33tlie.macshot.macshot.plist`.
6. Run the dev build from Xcode; confirm it appears as a *separate* Dock/menu-bar entity and the prod prefs plist is not touched (`stat -f "%m" ~/Library/Preferences/com.sw33tlie.macshot.macshot.plist` mtime stable).

## What's intentionally absent vs. `dev`

The following dev-branch features did **not** ship in this prod install (they live on `dev`, not `main`):

- MentalOS sidecar capture writer (TASK-011, etc.)
- Ollama "Chat about this" window (`feat: Ollama chat client`, `feat: 'Chat about this' window powered by local Gemma model`)
- Structured logging via `Services/Log.swift`
- Editor toolbar "Chat about this" button
- Various dev fixes still queued behind a release: presentation-tree symlink fix, MainActor isolation tweak, app-delegate assignment fix

## Reinstall command (future refresh)

```bash
cd "/Users/saviour/Documents/Code & Dev/Projects/macshot-mentalOS/macshot-mentalOS"
git fetch origin main
# refresh the worktree
git worktree remove ../macshot-prod-build 2>/dev/null
git worktree add ../macshot-prod-build origin/main

cd ../macshot-prod-build
xcodebuild -project macshot.xcodeproj -scheme macshot -configuration Release \
  -derivedDataPath ./build-prod \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=6BX9L8T3S4 \
  'CODE_SIGN_IDENTITY=Apple Development' \
  MARKETING_VERSION=4.1.0 CURRENT_PROJECT_VERSION=4.1.0 \
  clean build

# quit any running instance first
pkill -x macshot 2>/dev/null

# replace install (move-to-Trash, then ditto) — do NOT use rm -rf
mv /Applications/macshot.app ~/.Trash/macshot-old-$(date +%s).app
ditto ./build-prod/Build/Products/Release/macshot.app /Applications/macshot.app

codesign --verify --deep --strict /Applications/macshot.app
open /Applications/macshot.app
```

## Known limitations

- No notarization — no Developer ID Application cert in keychain. Gatekeeper rejects via `spctl`, but `open` from this account works because the bundle was built locally and Launch Services trusts it.
- The build pins `MARKETING_VERSION=4.1.0` at the xcodebuild invocation; `project.pbxproj` on `main` still reads `3.5.2` (CI normally overrides at release time per `CLAUDE.md`).
- No Sparkle delta-update wired up for this local install — auto-update would pull from the public appcast, which may differ from this exact build.
