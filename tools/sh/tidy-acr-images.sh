#!/usr/bin/env bash
# tidy-acr-images — Remove old container image tags from Azure Container Registry
# based on a version-scoped retention policy defined in a settings file.
#
# Usage:
#   tidy-acr-images <settings-file> [--dry-run]
#
# Settings file variables:
#   ACR_REGISTRY            FQDN of the ACR (e.g., example.azurecr.io)
#   REPOSITORY_VERSIONS_MAP Bash array of "repo/name:\"v1,v2\"" entries
#   ALWAYS_RETAIN_IMAGES    Bash array of "repo/name:tag" images to never delete
#   MAX_TAGS_TO_RETAIN      Integer — max latest-tags to keep per (repo, version)
#   FLUSH_UNKNOWN           true|false — when true, also delete any tag that is
#                           not covered by REPOSITORY_VERSIONS_MAP and not in
#                           ALWAYS_RETAIN_IMAGES (includes entirely unmapped repos)
#
# Tag naming convention:
#   SHA tag:    <major>.<minor>.<patch>-<env>.<target>.<7hex>   e.g. 3.1.0-dev.common.3d8a1f7
#   Latest tag: <major>.<minor>.<patch>-<env>.<target>.latest   e.g. 3.1.0-dev.common.latest
#
# Retention logic per (repository, version):
#   1. Collect all matching latest-tags and sha-tags.
#   2. Sort latest-tags by creation time (newest first).
#   3. Retain at most MAX_TAGS_TO_RETAIN latest-tags and their paired sha-tags.
#   4. Delete the rest — unless an image appears in ALWAYS_RETAIN_IMAGES.

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
  REPOSITORY_VERSIONS_MAP=(
    frontend-repo/sample-webui:"2.3.0,3.0.0,3.1.0"
    backend-repo/sample-api:"2.3.0,3.0.0,3.1.0"
  )
  ALWAYS_RETAIN_IMAGES=(
    frontend-repo/sample-webui:2.2.0-target01
  )
  MAX_TAGS_TO_RETAIN=3
  FLUSH_UNKNOWN=false
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

# Validate all required scalar variables are set
for var in ACR_REGISTRY MAX_TAGS_TO_RETAIN; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: Missing required setting in settings file: $var" >&2
        exit 1
    fi
done

if [[ -z "${REPOSITORY_VERSIONS_MAP[*]:-}" ]]; then
    echo "ERROR: Missing required setting in settings file: REPOSITORY_VERSIONS_MAP" >&2
    exit 1
fi

# Default FLUSH_UNKNOWN to false if not provided in the settings file
FLUSH_UNKNOWN="${FLUSH_UNKNOWN:-false}"
if [[ "$FLUSH_UNKNOWN" != "true" && "$FLUSH_UNKNOWN" != "false" ]]; then
    echo "ERROR: FLUSH_UNKNOWN must be 'true' or 'false', got: $FLUSH_UNKNOWN" >&2
    exit 1
fi

# Strip the .azurecr.io suffix to get the bare registry name for az acr commands
ACR_NAME="${ACR_REGISTRY%%.*}"

echo "════════════════════════════════════════════════════════════"
echo "  ACR Image Tidy"
echo "════════════════════════════════════════════════════════════"
echo "  Registry        : $ACR_REGISTRY  (name: $ACR_NAME)"
echo "  Max tags/version: $MAX_TAGS_TO_RETAIN"
echo "  Flush unknown   : $FLUSH_UNKNOWN"
echo "  Dry run         : $DRY_RUN"
echo "  Always-retain   : ${#ALWAYS_RETAIN_IMAGES[@]} image(s)"
echo "════════════════════════════════════════════════════════════"
echo

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Returns 0 if "repo:tag" is in the ALWAYS_RETAIN_IMAGES list.
is_always_retained() {
    local repo="$1" tag="$2"
    local candidate="$repo:$tag"
    local entry
    for entry in "${ALWAYS_RETAIN_IMAGES[@]:-}"; do
        [[ "$entry" == "$candidate" ]] && return 0
    done
    return 1
}

# Deletes a single tag from the ACR (or prints it in dry-run mode).
delete_tag() {
    local repo="$1" tag="$2"

    if is_always_retained "$repo" "$tag"; then
        echo "│     SKIP  (always-retain) : $repo:$tag"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "│     DRY-RUN delete        : $repo:$tag"
    else
        echo "│     Deleting              : $repo:$tag"
        if ! az acr repository delete \
            --name "$ACR_NAME" \
            --image "$repo:$tag" \
            --yes \
            --output none 2>/dev/null; then
            echo "│     WARNING: Failed to delete $repo:$tag" >&2
        fi
    fi
}

# ─── Main loop ────────────────────────────────────────────────────────────────

total_deleted=0
total_retained=0

for entry in "${REPOSITORY_VERSIONS_MAP[@]}"; do
    # Each entry looks like:  repo/name:"2.3.0,3.1.0"
    repo="${entry%%:*}"
    versions_raw="${entry#*:}"
    versions_raw="${versions_raw//\"/}" # strip surrounding quotes
    versions_raw="${versions_raw// /}"  # strip spaces

    IFS=',' read -ra versions <<<"$versions_raw"

    # Pre-build a combined regex that matches any known tag for this repo
    # (used later by FLUSH_UNKNOWN to identify tags that belong to no version)
    _ver_patterns=()
    for _v in "${versions[@]}"; do
        _ev="${_v//./\\.}"
        _ver_patterns+=("^${_ev}-[^.]+\\.[^.]+\\.([0-9a-f]{7}|latest)$")
    done
    combined_ver_pattern="$(
        IFS='|'
        echo "${_ver_patterns[*]}"
    )"
    unset _v _ev _ver_patterns

    echo "┌── Repository: $repo"
    echo "│   Versions  : ${versions[*]}"

    # Fetch all tags for this repository once (sorted newest first)
    echo "│   Fetching tags from ACR..."
    all_tags_json=$(
        az acr repository show-tags \
            --name "$ACR_NAME" \
            --repository "$repo" \
            --detail \
            --orderby time_desc \
            --output json 2>/dev/null
    ) || {
        echo "│   WARNING: Could not list tags for $repo — skipping" >&2
        echo "└──"
        echo
        continue
    }

    tag_count=$(echo "$all_tags_json" | jq 'length')
    echo "│   Total tags in repo: $tag_count"

    for version in "${versions[@]}"; do
        echo "│"
        echo "│   ── Version: $version"

        # Escape dots for use in jq regex
        escaped_ver="${version//./\\.}"

        # Tag patterns:
        #   sha-tag:    <version>-<env>.<target>.<7 lowercase hex chars>
        #   latest-tag: <version>-<env>.<target>.latest
        sha_pattern="^${escaped_ver}-[^.]+\\.[^.]+\\.[0-9a-f]{7}$"
        latest_pattern="^${escaped_ver}-[^.]+\\.[^.]+\\.latest$"

        # Collect sha-tags sorted by creation time, newest first.
        # The ACR API was already requested with --orderby time_desc so jq
        # preserves that order.
        mapfile -t sha_tags < <(
            echo "$all_tags_json" |
                jq -r --arg pat "$sha_pattern" \
                    '.[] | select(.name | test($pat)) | .name'
        )

        # Collect latest-tags (one per <env>.<target> prefix; order irrelevant)
        mapfile -t latest_tags < <(
            echo "$all_tags_json" |
                jq -r --arg pat "$latest_pattern" \
                    '.[] | select(.name | test($pat)) | .name'
        )

        echo "│     SHA-tags found    : ${#sha_tags[@]}"
        echo "│     Latest-tags found : ${#latest_tags[@]}"

        if [[ ${#sha_tags[@]} -eq 0 && ${#latest_tags[@]} -eq 0 ]]; then
            echo "│     No matching tags found — skipping"
            continue
        fi

        # ── Retain sha-tags, grouped by <version>-<env>.<target> prefix ───
        #
        # sha-tags are already ordered newest→oldest (from ACR API).
        # We count how many we keep per prefix; once a prefix reaches
        # MAX_TAGS_TO_RETAIN the remainder are deleted.
        #
        # Prefix derivation:
        #   "3.1.0-dev.common.3d8a1f7" → strip trailing ".<7hex>" → "3.1.0-dev.common"

        declare -A _prefix_kept=() # prefix → retained count

        for stag in "${sha_tags[@]}"; do
            stag_prefix="${stag%.*}"
            kept="${_prefix_kept[$stag_prefix]:-0}"

            if ((kept < MAX_TAGS_TO_RETAIN)); then
                echo "│     RETAIN (sha)      : $repo:$stag"
                _prefix_kept[$stag_prefix]=$((kept + 1))
                ((total_retained++)) || true
            else
                delete_tag "$repo" "$stag"
                ((total_deleted++)) || true
            fi
        done

        # ── Process latest-tags ───────────────────────────────────────────
        #
        # Each latest-tag is the alias for the newest sha-tag of its prefix.
        # Retain it when its prefix still has at least one retained sha-tag;
        # delete it when all sha-tags for that prefix were pruned or absent.
        #
        # Prefix derivation:
        #   "3.1.0-dev.common.latest" → strip ".latest" → "3.1.0-dev.common"

        for ltag in "${latest_tags[@]}"; do
            ltag_prefix="${ltag%.latest}"

            if [[ "${_prefix_kept[$ltag_prefix]:-0}" -gt 0 ]]; then
                echo "│     RETAIN (latest)   : $repo:$ltag"
                ((total_retained++)) || true
            else
                delete_tag "$repo" "$ltag"
                ((total_deleted++)) || true
            fi
        done

        unset _prefix_kept
    done

    # ── Flush unknown tags within this mapped repo ─────────────────────────
    # Tags that don't match any version pattern are "unknown" for this repo.
    if [[ "$FLUSH_UNKNOWN" == "true" ]]; then
        echo "│"
        echo "│   ── Flushing unknown tags (not covered by any version)"

        mapfile -t unknown_tags < <(
            echo "$all_tags_json" |
                jq -r --arg pat "$combined_ver_pattern" \
                    '.[] | select(.name | test($pat) | not) | .name'
        )

        if [[ ${#unknown_tags[@]} -eq 0 ]]; then
            echo "│     No unknown tags found"
        else
            echo "│     Unknown tags found: ${#unknown_tags[@]}"
            for utag in "${unknown_tags[@]}"; do
                delete_tag "$repo" "$utag"
                ((total_deleted++)) || true
            done
        fi
    fi

    echo "└──"
    echo
done

# ─── Flush unmapped repositories ─────────────────────────────────────────────
# When FLUSH_UNKNOWN=true, list every repo in the ACR and delete all tags in
# repos that are not present in REPOSITORY_VERSIONS_MAP (subject to
# ALWAYS_RETAIN_IMAGES).

if [[ "$FLUSH_UNKNOWN" == "true" ]]; then
    echo "════════════════════════════════════════════════════════════"
    echo "  Flushing unmapped repositories"
    echo "════════════════════════════════════════════════════════════"

    # Build set of repo names from the map
    mapped_repos=()
    for _entry in "${REPOSITORY_VERSIONS_MAP[@]}"; do
        mapped_repos+=("${_entry%%:*}")
    done
    unset _entry

    # List every repository in the ACR
    mapfile -t all_acr_repos < <(
        az acr repository list --name "$ACR_NAME" --output tsv 2>/dev/null
    ) || {
        echo "WARNING: Could not list repositories in $ACR_NAME — skipping unmapped flush" >&2
        all_acr_repos=()
    }

    for acr_repo in "${all_acr_repos[@]}"; do
        # Skip if this repo is covered by the map
        is_mapped=false
        for _m in "${mapped_repos[@]}"; do
            if [[ "$_m" == "$acr_repo" ]]; then
                is_mapped=true
                break
            fi
        done
        [[ "$is_mapped" == "true" ]] && continue

        echo "┌── Unmapped repository: $acr_repo"

        # Fetch all tags for this unmapped repo
        unmapped_tags_json=$(
            az acr repository show-tags \
                --name "$ACR_NAME" \
                --repository "$acr_repo" \
                --output json 2>/dev/null
        ) || {
            echo "│   WARNING: Could not list tags for $acr_repo — skipping" >&2
            echo "└──"
            echo
            continue
        }

        mapfile -t all_repo_tags < <(
            echo "$unmapped_tags_json" | jq -r '.[]'
        )

        echo "│   Total tags: ${#all_repo_tags[@]}"

        for rtag in "${all_repo_tags[@]}"; do
            delete_tag "$acr_repo" "$rtag"
            ((total_deleted++)) || true
        done

        echo "└──"
        echo
    done
    unset _m mapped_repos all_acr_repos
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo "════════════════════════════════════════════════════════════"
if [[ "$DRY_RUN" == "true" ]]; then
    echo "  DRY RUN complete — no images were deleted"
    echo "  Would delete  : $total_deleted tag(s)"
    echo "  Would retain  : $total_retained tag(s)"
else
    echo "  Cleanup complete"
    echo "  Deleted  : $total_deleted tag(s)"
    echo "  Retained : $total_retained tag(s)"
fi
echo "════════════════════════════════════════════════════════════"
