#!/usr/bin/env bash
# Refresh vendored googleapis protos from github.com/googleapis/googleapis.
#
# Fetches the five files we depend on, overwrites the vendored copies
# under ${THIRD_PARTY_DIR}/google/, and reports back to GitHub Actions
# via $GITHUB_OUTPUT whether anything changed (so the workflow knows
# whether to open a PR).
#
# Env:
#   GOOGLEAPIS_REF    Upstream ref to track. Default: master.
#   THIRD_PARTY_DIR   Vendor root. Default: third_party.
#   GITHUB_OUTPUT     Set by GitHub Actions. Optional locally.
#   GITHUB_TOKEN      Optional. Used only to authenticate the
#                     api.github.com SHA lookup against the 60/hour
#                     unauthenticated limit.

set -euo pipefail

GOOGLEAPIS_REF="${GOOGLEAPIS_REF:-master}"
THIRD_PARTY_DIR="${THIRD_PARTY_DIR:-third_party}"

# Single source of truth. Each entry is a path relative to the
# googleapis repo root; it also dictates the destination path under
# ${THIRD_PARTY_DIR}/.
FILES=(
  "google/api/field_behavior.proto"
  "google/type/color.proto"
  "google/type/date.proto"
  "google/type/money.proto"
  "google/type/phone_number.proto"
)

raw_base="https://raw.githubusercontent.com/googleapis/googleapis/${GOOGLEAPIS_REF}"

for path in "${FILES[@]}"; do
  dest="${THIRD_PARTY_DIR}/${path}"
  mkdir -p "$(dirname "${dest}")"
  echo "fetching ${path} from ${GOOGLEAPIS_REF}"
  curl -fsSL "${raw_base}/${path}" -o "${dest}"
done

# Look up the upstream commit SHA so we can mention it in the PR body
# and commit message.
api_url="https://api.github.com/repos/googleapis/googleapis/commits/${GOOGLEAPIS_REF}"
curl_args=(-fsSL -H "Accept: application/vnd.github+json")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi
upstream_sha=$(curl "${curl_args[@]}" "${api_url}" \
  | sed -n 's/^  "sha": "\(.*\)",$/\1/p' | head -1)
upstream_short="${upstream_sha:0:12}"

git add -A "${THIRD_PARTY_DIR}/"

if git diff --cached --quiet -- "${THIRD_PARTY_DIR}/"; then
  echo "no upstream changes — vendored files already match googleapis@${upstream_short}"
  changed="false"
  changed_files=""
else
  changed="true"
  changed_files=$(git diff --cached --name-only -- "${THIRD_PARTY_DIR}/")
  echo "changed:"
  echo "${changed_files}"
fi

# Emit outputs only when running under GitHub Actions.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "changed=${changed}"
    echo "sha=${upstream_short}"
    echo "changed_files<<EOF"
    echo "${changed_files}"
    echo "EOF"
  } >> "${GITHUB_OUTPUT}"
fi
