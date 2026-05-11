#!/usr/bin/env bash
#
# Mechanical documentation audit. Read by the PM Agent role
# (see docs/PM_AGENT.md) but safe to run any time.
#
# Reports — does not fix. Exit 0 if clean, 1 if findings.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

FINDINGS=0
note() { printf '  - %s\n' "$1"; FINDINGS=$((FINDINGS + 1)); }
section() { printf '\n== %s ==\n' "$1"; }

DOCS=(
  AGENTS.md
  CLAUDE.md
  README.md
  CONTRIBUTING.md
  CHANGELOG.md
  RELEASE_NOTES.md
  docs/AGENT_HANDOFF.md
  docs/TASKS.md
  docs/PM_AGENT.md
)

# ---------------------------------------------------------------------------
section "Doc files exist"
for d in "${DOCS[@]}"; do
  if [[ ! -f "$d" ]]; then
    note "missing expected doc: $d"
  fi
done

# ---------------------------------------------------------------------------
section "Broken relative links"
# Markdown link form: [text](path) where path is not http(s):// and not a
# pure anchor (#section). Bare anchors and external URLs are skipped.
grep -nHE '\[[^]]+\]\(([^)]+)\)' "${DOCS[@]}" 2>/dev/null \
  | while IFS= read -r line; do
      file="${line%%:*}"
      rest="${line#*:}"
      lineno="${rest%%:*}"
      # Extract every (path) occurrence on this line.
      printf '%s\n' "$rest" | grep -oE '\([^)]+\)' | while read -r paren; do
        path="${paren#(}"
        path="${path%)}"
        # Strip optional title: "path "title"" → "path"
        path="${path%% *}"
        case "$path" in
          ''|'#'*|http*|mailto:*) continue ;;
        esac
        # Strip any trailing #anchor from the path before stat-ing.
        target_path="${path%%#*}"
        [[ -z "$target_path" ]] && continue
        # Resolve relative to the file's directory.
        dir="$(dirname "$file")"
        full="$dir/$target_path"
        if [[ ! -e "$full" ]]; then
          # Try repo-root-absolute interpretation as a fallback.
          if [[ ! -e "$target_path" ]]; then
            note "broken link in $file:$lineno → $path"
          fi
        fi
      done
    done

# ---------------------------------------------------------------------------
section "File paths in docs that no longer exist"
# Look for backtick-wrapped paths that contain a directory separator
# (otherwise they're likely informal file mentions, not paths).
#
# Skip docs that legitimately reference future or template paths:
#   - docs/TASKS.md references files for tasks not yet implemented
#   - docs/PM_AGENT.md uses placeholder paths (YYYY-MM-DD.md, optional wiring)
PATH_CHECK_SKIP_RE='^(docs/TASKS\.md|docs/PM_AGENT\.md|CHANGELOG\.md)$'
for doc in "${DOCS[@]}"; do
  [[ -f "$doc" ]] || continue
  [[ "$doc" =~ $PATH_CHECK_SKIP_RE ]] && continue
  grep -oE '`[A-Za-z0-9_./-]+/[A-Za-z0-9_./-]+\.(swift|md|sh|plist|entitlements|xcscheme|json|yml|xml)`' "$doc" 2>/dev/null \
    | sort -u \
    | while read -r match; do
        path="${match//\`/}"
        [[ -z "$path" ]] && continue
        case "$path" in /*|http*) continue ;; esac
        # Try as-is, then under the doc's own directory, then under
        # macshot/ (most source paths in CLAUDE.md are relative to it).
        if [[ ! -e "$path" ]] \
          && [[ ! -e "$(dirname "$doc")/$path" ]] \
          && [[ ! -e "macshot/$path" ]]; then
          note "$doc references missing path: $path"
        fi
      done
done

# ---------------------------------------------------------------------------
section "TASKS.md structural sanity"
TASKS=docs/TASKS.md
if [[ -f "$TASKS" ]]; then
  # Every task block should have these fields — but only enforce on
  # blocks in the Active / Blocked / Done sections. Phase 3 and Future
  # sections are explicit draft stubs (see TASKS.md headers
  # "## Phase 3 — to be promoted ..." and "## Future ..."); enforcing
  # required PM fields on them contradicts their stated purpose.
  required_fields=("Status:" "Owner-agent:" "Created:" "Last touched:" "Branch:")
  enforced_task_ids=$(awk '
    /^## / {
      section = $0
      sub(/^## /, "", section)
      enforce = (section ~ /^Active/ || section ~ /^Blocked/ || section ~ /^Done/)
      next
    }
    enforce && /^### TASK-/ {
      # Print just the TASK-NNN id.
      match($0, /TASK-[0-9]+/)
      if (RSTART > 0) print substr($0, RSTART, RLENGTH)
    }
  ' "$TASKS" | sort -u)
  for tid in $enforced_task_ids; do
    block=$(awk -v id="### $tid" '
      $0 ~ id { capture=1; print; next }
      capture && /^### TASK-/ { exit }
      capture && /^## / { exit }
      capture { print }
    ' "$TASKS")
    if [[ -z "$block" ]]; then continue; fi
    for field in "${required_fields[@]}"; do
      if ! grep -q "$field" <<<"$block"; then
        note "$tid block missing field: $field"
      fi
    done
  done

  # Orphan task ids — referenced in commit messages but not declared.
  if git rev-parse --git-dir >/dev/null 2>&1; then
    git_task_ids=$(git log --pretty=%s | grep -oE 'TASK-[0-9]+' | sort -u || true)
    for tid in $git_task_ids; do
      if ! grep -q "^### $tid" "$TASKS"; then
        note "commit log references $tid but no task block exists"
      fi
    done
  fi
fi

# ---------------------------------------------------------------------------
section "Cross-doc invariants"

# Bundle id must agree between project.pbxproj (Release config) and
# AGENTS.md / CLAUDE.md. In .pbxproj, settings precede `name = Release;`,
# so we pair the most-recently-seen bundle id with each `name = ...` line.
PBX=macshot.xcodeproj/project.pbxproj
if [[ -f "$PBX" ]]; then
  release_bundle_id=$(awk '
    /PRODUCT_BUNDLE_IDENTIFIER = / {
      v=$0; gsub(/.*PRODUCT_BUNDLE_IDENTIFIER = /, "", v); gsub(/;.*/, "", v); pid=v
    }
    /name = Release;/ { print pid; exit }
  ' "$PBX")
  for doc in AGENTS.md CLAUDE.md; do
    if [[ -f "$doc" && -n "$release_bundle_id" ]]; then
      if ! grep -q "$release_bundle_id" "$doc"; then
        note "$doc does not mention current Release bundle id ($release_bundle_id)"
      fi
    fi
  done

  release_min_target=$(awk '
    /MACOSX_DEPLOYMENT_TARGET = / {
      v=$0; gsub(/.*MACOSX_DEPLOYMENT_TARGET = /, "", v); gsub(/;.*/, "", v); mt=v
    }
    /name = Release;/ { print mt; exit }
  ' "$PBX")
  for doc in AGENTS.md CLAUDE.md README.md; do
    if [[ -f "$doc" && -n "$release_min_target" ]]; then
      if ! grep -q "$release_min_target" "$doc"; then
        note "$doc does not mention current min macOS target ($release_min_target)"
      fi
    fi
  done
fi

# build-local-prod.sh referenced in AGENTS.md must exist and be executable.
if [[ -f AGENTS.md ]] && grep -q 'scripts/build-local-prod.sh' AGENTS.md; then
  if [[ ! -x scripts/build-local-prod.sh ]]; then
    note "AGENTS.md references scripts/build-local-prod.sh but it's missing or not executable"
  fi
fi

# ---------------------------------------------------------------------------
section "Stale Active tasks (Last touched > 14 days ago)"
if [[ -f "$TASKS" ]]; then
  awk '
    /^## Active/ {in_active=1; next}
    /^## / {in_active=0}
    in_active && /^### TASK-/ {tid=$2; next}
    in_active && /Last touched:/ {
      gsub(/.*Last touched: */, "");
      gsub(/[ \t]+$/, "");
      print tid, $0
    }
  ' "$TASKS" \
  | while read -r tid date_str; do
      # Skip placeholders.
      case "$date_str" in ''|'—'|'-'|'TBD') continue ;; esac
      if epoch=$(date -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null); then
        now=$(date +%s)
        age_days=$(( (now - epoch) / 86400 ))
        if (( age_days > 14 )); then
          note "$tid Last touched $age_days days ago — review for staleness"
        fi
      fi
    done
fi

# ---------------------------------------------------------------------------
echo
if (( FINDINGS == 0 )); then
  echo "audit clean — 0 findings"
  exit 0
else
  echo "audit complete — $FINDINGS finding(s)"
  exit 1
fi
