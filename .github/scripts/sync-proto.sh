#!/usr/bin/env bash
#
# sync-proto.sh — copy freshly generated proto bindings into the target
# language repository checkout, commit, push, and on tag triggers mirror
# the tag. Invoked by .github/workflows/proto-publish.yml.
#
# Required env:
#   LANGUAGE        one of: go, java, swift, typescript, php, php-rr
#   TARGET_DIR      relative path to the target repo checkout (default: target)
#   SOURCE_SHA      source commit SHA the bindings were generated from
#   REF_TYPE        "branch" or "tag" (github.ref_type)
#   REF_NAME        branch name or tag name (github.ref_name)
#   BOT_NAME        git user.name for the commit
#   BOT_EMAIL       git user.email for the commit
#
# Optional env:
#   PUBLIC_PROTO_PATHS  space-separated list of published .proto packages
#                       (default: "badrequest/v1 serviceinfo/v1"). Used by
#                       the php-rr case to mirror the .proto sources that
#                       RoadRunner's gRPC plugin needs at runtime.
#
# Behavior:
#   - For each language, wipe the regenerable subtree in TARGET_DIR
#     and replace it with the freshly generated output from gen/<lang>/.
#   - For TypeScript, bump package.json version: tag → release X.Y.Z;
#     branch → <next-patch>-<branch>.<sha7> pre-release.
#   - Commit only if the working tree changed (no-op skip otherwise).
#   - Push to the same-named branch in the target (main fast-forward,
#     others force-pushed). On tag triggers also create and push the
#     matching tag.

set -euo pipefail

: "${LANGUAGE:?LANGUAGE must be set (go|java|swift|typescript|php|php-rr)}"
: "${SOURCE_SHA:?SOURCE_SHA must be set}"
: "${REF_TYPE:?REF_TYPE must be set}"
: "${REF_NAME:?REF_NAME must be set}"
: "${BOT_NAME:?BOT_NAME must be set}"
: "${BOT_EMAIL:?BOT_EMAIL must be set}"

TARGET_DIR="${TARGET_DIR:-target}"

if [[ ! -d "${TARGET_DIR}" ]]; then
  echo "error: target repo not checked out at ${TARGET_DIR}" >&2
  exit 1
fi

case "${LANGUAGE}" in
  go)
    SRC="gen/go"
    rm -rf "${TARGET_DIR}/badrequest" "${TARGET_DIR}/serviceinfo"
    cp -R "${SRC}/badrequest" "${TARGET_DIR}/badrequest"
    cp -R "${SRC}/serviceinfo" "${TARGET_DIR}/serviceinfo"
    ;;
  java)
    SRC="gen/java"
    rm -rf "${TARGET_DIR}/src/main/java/io"
    mkdir -p "${TARGET_DIR}/src/main/java"
    cp -R "${SRC}/." "${TARGET_DIR}/src/main/java/"
    ;;
  swift)
    SRC="gen/swift"
    rm -rf "${TARGET_DIR}/Sources/Proto"
    mkdir -p "${TARGET_DIR}/Sources/Proto"
    cp -R "${SRC}/." "${TARGET_DIR}/Sources/Proto/"
    ;;
  typescript)
    SRC="gen/typescript"
    rm -rf "${TARGET_DIR}/src/gen"
    mkdir -p "${TARGET_DIR}/src/gen"
    cp -R "${SRC}/." "${TARGET_DIR}/src/gen/"
    if [[ "${REF_TYPE}" == "tag" ]]; then
      ts_version="${REF_NAME#v}"
    else
      current=$(node -p "require('./${TARGET_DIR}/package.json').version")
      if [[ "${current}" == *-* ]]; then
        next_patch="${current%%-*}"
      else
        IFS=. read -r major minor patch <<< "${current}"
        next_patch="${major}.${minor}.$((patch + 1))"
      fi
      short_sha="${SOURCE_SHA:0:7}"
      sanitized_branch="${REF_NAME//\//-}"
      ts_version="${next_patch}-${sanitized_branch}.${short_sha}"
    fi
    (cd "${TARGET_DIR}" && npm version --no-git-tag-version --allow-same-version "${ts_version}")
    ;;
  php|php-rr)
    SRC="gen/${LANGUAGE}"
    rm -rf "${TARGET_DIR}/src/Io" "${TARGET_DIR}/src/GPBMetadata"
    mkdir -p "${TARGET_DIR}/src"
    cp -R "${SRC}/." "${TARGET_DIR}/src/"
    if [[ "${LANGUAGE}" == "php-rr" ]]; then
      # RoadRunner's gRPC plugin needs the original .proto sources at
      # server startup (its `grpc.proto:` config takes file paths).
      rm -rf "${TARGET_DIR}/proto"
      for path in ${PUBLIC_PROTO_PATHS:-badrequest/v1 serviceinfo/v1}; do
        mkdir -p "${TARGET_DIR}/proto/${path}"
        cp "${path}"/*.proto "${TARGET_DIR}/proto/${path}/"
      done
    fi
    ;;
  *)
    echo "error: unknown LANGUAGE=${LANGUAGE} (expected go|java|swift|typescript|php|php-rr)" >&2
    exit 1
    ;;
esac

cd "${TARGET_DIR}"

git config user.name "${BOT_NAME}"
git config user.email "${BOT_EMAIL}"
git add -A

target_branch="main"
if [[ "${REF_TYPE}" == "branch" ]]; then
  target_branch="${REF_NAME}"
fi

if git diff --cached --quiet; then
  echo "no changes to publish for ${LANGUAGE} at ${SOURCE_SHA}"
else
  commit_msg="chore: sync from proto @ ${SOURCE_SHA}"
  if [[ "${REF_TYPE}" == "tag" ]]; then
    commit_msg="chore: sync from proto ${REF_NAME} (${SOURCE_SHA})"
  fi
  git commit -m "${commit_msg}"
  if [[ "${target_branch}" == "main" ]]; then
    git push origin "HEAD:${target_branch}"
  else
    git push --force origin "HEAD:${target_branch}"
  fi
fi

if [[ "${REF_TYPE}" == "tag" ]]; then
  git tag --force "${REF_NAME}"
  git push --force origin "refs/tags/${REF_NAME}"
fi
