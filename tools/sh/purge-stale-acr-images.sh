#!/usr/bin/env bash
# purge-acr-stale-images — Delete every tag in a repository that does NOT
# match any of its configured retention patterns.
#
# Usage:
#   purge-acr-stale-images <settings-file> [--dry-run]
#
# Settings file variables:
#   ACR_REGISTRY              FQDN of the ACR (e.g., example.azurecr.io)
#   REPOSITORY_TAG_PATTERNS   Bash array of "repo/name:\"pat1,pat2\"" entries.
#                             Each pattern is matched against the tag name.
#                             A tag matching ANY pattern is retained.
#                             Patterns support:
#                               *    glob wildcard — matches any characters
#                               \.   literal dot
#                               ^/$  ERE anchors
#   ALWAYS_RETAIN_IMAGES      Bash array of "repo/name:tag" images to never
#                             delete, regardless of pattern matching.
#
# Example — retain tags for dev/uat environments:
#   REPOSITORY_TAG_PATTERNS=(
#       frontend-repo/sample-webui:"*\.target01\.*,*\.target02\.*"
#       backend-repo/sample-api:"*-dev\.all\.*,*-uat\.all\.*"
#   )

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
    cat >&2 <<EOF
Usage: $SCRIPT_NAME <settings-file> [--dry-run]

  settings-file   Path to the settings file (required)
  --dry-run       Print what would be deleted without actually deleting

Settings file example:
  ACR_REGISTRY=example.azurecr.io
  REPOSITORY_TAG_PATTERNS=(
    frontend-repo/sample-webui:"*\.target01\.*,*\.target02\.*"
    backend-repo/sample-api:"*-dev\.all\.*,*-uat\.all\.*"
  )
  ALWAYS_RETAIN_IMAGES=(
    frontend-repo/sample-webui:2.2.0-uat.target01
  )
EOF
    exit 1
}

# ─── Argument parsing ────────────────────────────────────────────────────────

[[ $# -lt 1 ]] && usage

SETTINGS_FILE="$1"
DRY_RUN=false

shift
while [[ $# -gt 0 ]]; do
    case "$1" in
    --dry-run) DRY_RUN=true ;;
    -h | --help) usage ;;
    *)
        echo "ERROR: Unknown argument: $1" >&2
        usage
        ;;
    esac
    shift
done

# ─── Dependency checks ────────────────────────────────────────────────────────

for cmd in az jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: Required tool not found in PATH: $cmd" >&2
        exit 1
    fi
done

# ─── Load settings ────────────────────────────────────────────────────────────

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "ERROR: Settings file not found: $SETTINGS_FILE" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$SETTINGS_FILE"

for var in ACR_REGISTRY; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: Missing required setting: $var" >&2
        exit 1
    fi
done

if [[ -z "${REPOSITORY_TAG_PATTERNS[*]:-}" ]]; then
    echo "ERROR: Missing required setting: REPOSITORY_TAG_PATTERNS" >&2
    exit 1
fi

ACR_NAME="${ACR_REGISTRY%%.*}"

echo "════════════════════════════════════════════════════════════"
echo "  ACR Stale Image Purge"
echo "════════════════════════════════════════════════════════════"
echo "  Registry      : $ACR_REGISTRY  (name: $ACR_NAME)"
echo "  Dry run       : $DRY_RUN"
echo "  Always-retain : ${#ALWAYS_RETAIN_IMAGES[@]} image(s)"
echo "════════════════════════════════════════════════════════════"
echo

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Returns 0 if "repo:tag" is in the ALWAYS_RETAIN_IMAGES list.
is_always_retained() {
    local repo="$1" tag="$2"
    local entry
    for entry in "${ALWAYS_RETAIN_IMAGES[@]:-}"; do
        [[ "$entry" == "$repo:$tag" ]] && return 0
    done
    return 1
}

# Returns 0 if the tag matches at least one pattern in the provided list.
# Patterns may use glob-style * as a wildcard (converted to .* for ERE) and
# \. for a literal dot.  Standard ERE anchors (^ $) are also supported.
matches_any_pattern() {
    local tag="$1"
    shift
    local pat regex
    for pat in "$@"; do
        # Convert bare * to .* so users can write glob-style wildcards.
        # e.g. "*-dev\.common\.*" becomes ".*-dev\.common\..*"
        regex="${pat//\*/.*}"
        [[ "$tag" =~ $regex ]] && return 0
    done
    return 1
}

# Deletes a single tag from the ACR (or prints it in dry-run mode).
delete_tag() {
    local repo="$1" tag="$2"

    if is_always_retained "$repo" "$tag"; then
        echo "│   SKIP  (always-retain) : $repo:$tag"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "│   DRY-RUN delete        : $repo:$tag"
    else
        echo "│   Deleting              : $repo:$tag"
        if ! az acr repository delete \
            --name "$ACR_NAME" \
            --image "$repo:$tag" \
            --yes \
            --output none 2>/dev/null; then
            echo "│   WARNING: Failed to delete $repo:$tag" >&2
        fi
    fi
}

# ─── Main loop ────────────────────────────────────────────────────────────────

total_deleted=0
total_retained=0

for entry in "${REPOSITORY_TAG_PATTERNS[@]}"; do
    # Each entry looks like:  repo/name:"^3\.,^2\."
    repo="${entry%%:*}"
    patterns_raw="${entry#*:}"
    patterns_raw="${patterns_raw//\"/}" # strip surrounding quotes

    # Split comma-separated patterns into an array
    IFS=',' read -ra patterns <<<"$patterns_raw"

    echo "┌── Repository : $repo"
    printf "│   Patterns   :"
    for pat in "${patterns[@]}"; do printf ' "%s"' "$pat"; done
    echo

    # Fetch all tag names for this repository
    echo "│   Fetching tags from ACR..."
    all_tags_json=$(
        az acr repository show-tags \
            --name "$ACR_NAME" \
            --repository "$repo" \
            --output json 2>/dev/null
    ) || {
        echo "│   WARNING: Could not list tags for $repo — skipping" >&2
        echo "└──"
        echo
        continue
    }

    mapfile -t all_tags < <(echo "$all_tags_json" | jq -r '.[]')

    echo "│   Total tags : ${#all_tags[@]}"
    echo "│"

    for tag in "${all_tags[@]}"; do
        if matches_any_pattern "$tag" "${patterns[@]}"; then
            echo "│   RETAIN : $repo:$tag"
            ((total_retained++)) || true
        else
            delete_tag "$repo" "$tag"
            ((total_deleted++)) || true
        fi
    done

    echo "└──"
    echo
done

# ─── Summary ─────────────────────────────────────────────────────────────────

echo "════════════════════════════════════════════════════════════"
if [[ "$DRY_RUN" == "true" ]]; then
    echo "  DRY RUN complete — no images were deleted"
    echo "  Would delete  : $total_deleted tag(s)"
    echo "  Would retain  : $total_retained tag(s)"
else
    echo "  Purge complete"
    echo "  Deleted  : $total_deleted tag(s)"
    echo "  Retained : $total_retained tag(s)"
fi
echo "════════════════════════════════════════════════════════════"
