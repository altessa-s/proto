#!/bin/bash
# Generates grouped release notes from Conventional Commits between two tags.
#
# Usage: generate-release-notes.sh <tag> [prev_tag]
#
# Commits are grouped by type (feat -> Features, fix -> Fixes, ...).
# ci and test commits are excluded from the changelog.
# Merge commits are skipped; commits that don't follow Conventional
# Commits go into the "Other" section.

set -euo pipefail

TAG="$1"
PREV_TAG="${2:-$(git describe --tags --abbrev=0 "${TAG}^" 2>/dev/null || echo "")}"

if [[ -n "$PREV_TAG" ]]; then
    RANGE="${PREV_TAG}..${TAG}"
else
    RANGE="$TAG"
fi

# Section order and titles (parallel arrays)
ORDER=(feat fix perf refactor docs style build chore other)
TITLES=("Features" "Fixes" "Performance" "Refactoring" "Documentation" "Code Style" "Build" "Chores" "Other")
EXCLUDED="ci test"

# One temp file per section (bash 3.2 compatible — no associative arrays)
SECTIONS_DIR=$(mktemp -d)
trap 'rm -rf "$SECTIONS_DIR"' EXIT

# `|| [[ -n "$line" ]]`: --pretty=format: omits the trailing newline,
# so plain `read` would drop the oldest commit in the range.
while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    hash="${line%% *}"
    subject="${line#* }"

    if [[ "$subject" =~ ^([a-z]+)(\(([^\)]+)\))?(!)?:\ (.+)$ ]]; then
        type="${BASH_REMATCH[1]}"
        scope="${BASH_REMATCH[3]}"
        desc="${BASH_REMATCH[5]}"
    else
        type="other"
        scope=""
        desc="$subject"
    fi

    # Skip excluded types entirely
    if grep -wq "$type" <<< "$EXCLUDED"; then
        continue
    fi

    # Unknown types fall into "Other"
    case " ${ORDER[*]} " in
        *" $type "*) ;;
        *) type="other" ;;
    esac

    if [[ -n "$scope" ]]; then
        entry="- **${scope}**: ${desc} (${hash})"
    else
        entry="- ${desc} (${hash})"
    fi
    echo "$entry" >> "${SECTIONS_DIR}/${type}"
done < <(git log --no-merges --pretty=format:'%h %s' "$RANGE")

printed=false
for i in "${!ORDER[@]}"; do
    type="${ORDER[$i]}"
    [[ -s "${SECTIONS_DIR}/${type}" ]] || continue
    printed=true
    echo "## ${TITLES[$i]}"
    echo
    cat "${SECTIONS_DIR}/${type}"
    echo
done

if [[ "$printed" == false ]]; then
    echo "No notable changes."
    echo
fi

# Repo URL: from Actions env, or derived from the origin remote for local runs
if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    REPO_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}"
else
    REPO_URL=$(git remote get-url origin 2>/dev/null | sed -E 's#^git@([^:]+):#https://\1/#; s#\.git$##' || echo "")
fi

if [[ -n "$PREV_TAG" && -n "$REPO_URL" ]]; then
    echo "**Full Changelog**: ${REPO_URL}/compare/${PREV_TAG}...${TAG}"
fi
