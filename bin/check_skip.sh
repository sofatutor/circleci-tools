#!/usr/bin/env bash

set -euo pipefail

get_last_successful_commit() {
  local org="${CIRCLE_PROJECT_USERNAME:-}"
  local repo="${CIRCLE_PROJECT_REPONAME:-}"
  local branch="${CIRCLE_BRANCH:-}"
  local token="${CIRCLE_CI_API_TOKEN:-}"

  if [[ -z "$org" || -z "$repo" || -z "$branch" || -z "$token" ]]; then
    return 1
  fi

  local pipeline_url="https://circleci.com/api/v2/project/gh/$org/$repo/pipeline?branch=$branch"
  local pipeline_response
  pipeline_response="$(curl -s -H "Circle-Token: $token" "$pipeline_url")"

  if echo "$pipeline_response" | jq -e 'has("message")' >/dev/null 2>&1; then
    return 1
  fi

  local pipeline_id
  local commit_sha
  local workflow_url
  local workflow_response
  local checked_pipelines=0
  local max_pipelines=8

  while IFS= read -r pipeline; do
    checked_pipelines=$((checked_pipelines + 1))
    if [[ "$checked_pipelines" -gt "$max_pipelines" ]]; then
      break
    fi

    pipeline_id="$(echo "$pipeline" | jq -r '.id')"
    commit_sha="$(echo "$pipeline" | jq -r '.vcs.revision')"

    [[ -z "$pipeline_id" || "$pipeline_id" == "null" || -z "$commit_sha" || "$commit_sha" == "null" ]] && continue

    workflow_url="https://circleci.com/api/v2/pipeline/$pipeline_id/workflow"
    workflow_response="$(curl -s -H "Circle-Token: $token" "$workflow_url")"
    if echo "$workflow_response" | jq -e '.items[]? | select(.status == "success")' >/dev/null 2>&1; then
      echo "$commit_sha"
      return 0
    fi
  done < <(echo "$pipeline_response" | jq -c '.items[]?')

  return 1
}

ensure_commit_available() {
  local commit_sha="$1"
  local branch="${2:-${CIRCLE_BRANCH:-}}"

  if git cat-file -e "${commit_sha}^{commit}" 2>/dev/null; then
    return 0
  fi

  git fetch origin "${branch}" --deepen=100 2>/dev/null || true
  git cat-file -e "${commit_sha}^{commit}" 2>/dev/null
}

get_pr_base_branch() {
  local pr_url="${CIRCLE_PULL_REQUEST:-}"
  local gh_token="${GITHUB_BOT_TOKEN:-${GITHUB_TOKEN:-}}"

  if [[ -z "$pr_url" || -z "$gh_token" || ! "$pr_url" =~ /pull/([0-9]+)$ ]]; then
    return 1
  fi

  local pr_number="${BASH_REMATCH[1]}"
  local owner repo api_url
  owner="${CIRCLE_PROJECT_USERNAME:-}"
  repo="${CIRCLE_PROJECT_REPONAME:-}"
  api_url="https://api.github.com/repos/${owner}/${repo}/pulls/${pr_number}"

  curl -s -H "Authorization: Bearer ${gh_token}" -H "Accept: application/vnd.github+json" "$api_url" | jq -r '.base.ref // empty'
}

append_skip_paths_from_value() {
  local value="$1"
  local candidate token

  if [[ -z "$value" ]]; then
    return 0
  fi

  if [[ "$value" =~ ^[[:space:]]*\[.*\][[:space:]]*$ ]] && command -v jq >/dev/null 2>&1; then
    while IFS= read -r candidate || [[ -n "$candidate" ]]; do
      [[ -z "$candidate" || "$candidate" =~ ^[[:space:]]*# ]] && continue
      SKIP_PATHS+=("$candidate")
    done < <(echo "$value" | jq -r '.[]?')
    return 0
  fi

  if [[ "$value" == *,* ]]; then
    while IFS= read -r candidate || [[ -n "$candidate" ]]; do
      candidate="${candidate#"${candidate%%[![:space:]]*}"}"
      candidate="${candidate%"${candidate##*[![:space:]]}"}"
      [[ -z "$candidate" || "$candidate" =~ ^[[:space:]]*# ]] && continue
      SKIP_PATHS+=("$candidate")
    done < <(echo "$value" | tr ',' '\n')
    return 0
  fi

  while IFS= read -r candidate || [[ -n "$candidate" ]]; do
    while IFS= read -r token; do
      [[ -z "$token" || "$token" =~ ^[[:space:]]*# ]] && continue
      SKIP_PATHS+=("$token")
    done < <(echo "$candidate" | xargs -n1)
  done < <(echo "$value")
}

path_matches_rule() {
  local file="$1"
  local rule="$2"
  local normalized_file="${file#./}"
  local normalized_rule="${rule#./}"
  local dir_rule

  if [[ "$normalized_rule" == *'*'* || "$normalized_rule" == *'?'* || "$normalized_rule" == *'['* ]]; then
    [[ "$normalized_file" == $normalized_rule ]]
    return $?
  fi

  dir_rule="${normalized_rule%/}"
  [[ "$normalized_file" == "$dir_rule" || "$normalized_file" == "$dir_rule/"* ]]
}

cancel_workflow_if_possible() {
  local reason="$1"
  echo "$reason"

  if [[ -z "${CIRCLE_CI_API_TOKEN:-}" || -z "${CIRCLE_WORKFLOW_ID:-}" ]]; then
    echo "CIRCLE_CI_API_TOKEN or CIRCLE_WORKFLOW_ID not set. Cannot cancel workflow. Exiting with code 0."
    exit 0
  fi

  curl -s -X POST \
    --header "Circle-Token: $CIRCLE_CI_API_TOKEN" \
    "https://circleci.com/api/v2/workflow/${CIRCLE_WORKFLOW_ID}/cancel" >/dev/null
  echo "Workflow cancellation requested. Exiting."
  exit 0
}

if [[ ! -d .git ]]; then
  echo "[ERROR] .git directory not found. Exiting."
  exit 1
fi

# Fast path: avoid network calls when parent commit is available locally.
BASE_COMMIT="$(git rev-parse "${CIRCLE_SHA1}~1" 2>/dev/null || true)"
if [[ -n "$BASE_COMMIT" ]]; then
  echo "[INFO] Using previous commit on branch as base."
else
  BASE_COMMIT="$(get_last_successful_commit || true)"
fi

if [[ -z "$BASE_COMMIT" ]]; then
  echo "[INFO] No previous successful commit found. Resolving fallback base commit."

  PR_BASE_BRANCH="$(get_pr_base_branch || true)"
  if [[ -n "$PR_BASE_BRANCH" ]]; then
    echo "[INFO] Using merge-base against PR base branch '${PR_BASE_BRANCH}'."
    git fetch origin "$PR_BASE_BRANCH" --deepen=100 2>/dev/null || git fetch origin "$PR_BASE_BRANCH" 2>/dev/null || true
    BASE_COMMIT="$(git merge-base "origin/${PR_BASE_BRANCH}" "${CIRCLE_SHA1}" 2>/dev/null || true)"
  fi

  if [[ -z "$BASE_COMMIT" ]]; then
    BASE_COMMIT="$(git rev-parse "${CIRCLE_SHA1}~1" 2>/dev/null || true)"
    if [[ -n "$BASE_COMMIT" ]]; then
      echo "[INFO] Falling back to previous commit on branch."
    fi
  fi

  if [[ -z "$BASE_COMMIT" ]]; then
    git fetch origin "$CIRCLE_BRANCH" --deepen=50 2>/dev/null || git fetch origin "$CIRCLE_BRANCH" --depth=50 2>/dev/null || true
    BASE_COMMIT="$(git rev-parse "origin/${CIRCLE_BRANCH}" 2>/dev/null || true)"
    if [[ -n "$BASE_COMMIT" ]]; then
      echo "[INFO] Falling back to origin/${CIRCLE_BRANCH}."
    fi
  fi
fi

if [[ -z "$BASE_COMMIT" ]]; then
  echo "[WARN] Could not determine a reliable base commit; defaulting to current commit file list."
  CHANGED_FILES="$(git show --pretty="" --name-only "$CIRCLE_SHA1")"
else
  if ! ensure_commit_available "$BASE_COMMIT" "$CIRCLE_BRANCH"; then
    echo "[WARN] Base commit $BASE_COMMIT unavailable after fetch. Falling back to current commit file list."
    CHANGED_FILES="$(git show --pretty="" --name-only "$CIRCLE_SHA1")"
  else
    CHANGED_FILES="$(git diff --name-only "$BASE_COMMIT" "$CIRCLE_SHA1")"
  fi
fi

if [[ -z "$CHANGED_FILES" ]]; then
  cancel_workflow_if_possible "[INFO] No changes detected for this commit. Cancelling workflow."
fi

echo "Change set:"
echo "$CHANGED_FILES"

SKIP_PATHS=()
if [[ -n "${CI_SKIP_FILE:-}" && -f "${CI_SKIP_FILE}" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    SKIP_PATHS+=("$line")
  done < "${CI_SKIP_FILE}"
fi
if [[ -n "${CI_SKIP_PATHS:-}" ]]; then
  append_skip_paths_from_value "${CI_SKIP_PATHS}"
fi

if [[ ${#SKIP_PATHS[@]} -gt 0 ]]; then
  all_skipped=true
  for file in $CHANGED_FILES; do
    skipped=false
    for path in "${SKIP_PATHS[@]}"; do
      if path_matches_rule "$file" "$path"; then
        skipped=true
        break
      fi
    done
    if [[ "$skipped" == false ]]; then
      all_skipped=false
      break
    fi
  done

  if [[ "$all_skipped" == true ]]; then
    if [[ -n "${CI_SKIP_FILE:-}" ]]; then
      cancel_workflow_if_possible "All changes are within CI_SKIP_FILE (${CI_SKIP_FILE}). Cancelling workflow."
    else
      cancel_workflow_if_possible "All changes are within CI_SKIP_PATHS (${CI_SKIP_PATHS}). Cancelling workflow."
    fi
  fi
fi

echo "Relevant changes found. Continuing build."
