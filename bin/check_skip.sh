#!/usr/bin/env bash

set -e

# Helper: get last successful commit SHA for the current branch
get_last_successful_commit() {
  local org="$CIRCLE_PROJECT_USERNAME"
  local repo="$CIRCLE_PROJECT_REPONAME"
  local branch="$CIRCLE_BRANCH"
  local token="$CIRCLE_CI_API_TOKEN"

  # Validate required environment variables
  if [[ -z "$org" || -z "$repo" || -z "$branch" || -z "$token" ]]; then
    echo "[ERROR] Missing required environment variables (org, repo, branch, or token)."
    return 1
  fi

  # Query pipelines for the specified branch
  local pipeline_url="https://circleci.com/api/v2/project/gh/$org/$repo/pipeline?branch=$branch"
  local pipeline_response
  pipeline_response=$(curl -s -H "Circle-Token: $token" "$pipeline_url")

  # Check for API errors
  if echo "$pipeline_response" | grep -q '"message"'; then
    echo "[ERROR] API request failed: $(echo "$pipeline_response" | jq -r '.message')"
    return 1
  fi

  # Extract the first pipeline with a successful workflow
  local pipeline_id
  local commit_sha
  while IFS= read -r pipeline; do
    pipeline_id=$(echo "$pipeline" | jq -r '.id')
    commit_sha=$(echo "$pipeline" | jq -r '.vcs.revision')

    # Skip if no valid pipeline ID or commit SHA
    [[ -z "$pipeline_id" || "$pipeline_id" == "null" || -z "$commit_sha" || "$commit_sha" == "null" ]] && continue

    # Query workflows for this pipeline
    local workflow_url="https://circleci.com/api/v2/pipeline/$pipeline_id/workflow"
    local workflow_response
    workflow_response=$(curl -s -H "Circle-Token: $token" "$workflow_url")

    # Check if any workflow has a "success" status
    if echo "$workflow_response" | jq -r '.items[] | select(.status == "success")' | grep -q .; then
      echo "$commit_sha"
      return 0
    fi
  done < <(echo "$pipeline_response" | jq -c '.items[]')

  echo "[INFO] No successful pipeline found for branch $branch."
  return 1
}

# Main logic
if [[ ! -d .git ]]; then
  echo "[ERROR] .git directory not found. Exiting."
  exit 1
fi

# Get the last successful commit SHA
BASE_COMMIT=$(get_last_successful_commit) || BASE_COMMIT=""
if [[ -z "$BASE_COMMIT" ]]; then
  echo "[INFO] No previous successful commit found. Falling back to latest commit on branch $CIRCLE_BRANCH."
  git fetch origin "$CIRCLE_BRANCH" --depth=1 2>/dev/null || {
    echo "[ERROR] Failed to fetch branch $CIRCLE_BRANCH."
    exit 1
  }
  BASE_COMMIT=$(git rev-parse origin/$CIRCLE_BRANCH 2>/dev/null) || {
    echo "[ERROR] Could not determine base commit for branch $CIRCLE_BRANCH."
    exit 1
  }
fi

# Ensure both BASE_COMMIT and CIRCLE_SHA1 exist locally. Handle force-pushes gracefully.
ensure_commit_available() {
  local commit_sha="$1"
  local branch="$2"
  if git cat-file -e "${commit_sha}^{commit}" 2>/dev/null; then
    return 0
  fi
  # Attempt to deepen history for the branch to fetch the missing commit
  echo "[INFO] Commit ${commit_sha} not found locally. Deepening history for ${branch}..."
  git fetch origin "${branch}" --deepen=1000 2>/dev/null || true
  git cat-file -e "${commit_sha}^{commit}" 2>/dev/null
}

FALLBACK_TO_CURRENT_COMMIT=0

if ! ensure_commit_available "$BASE_COMMIT" "$CIRCLE_BRANCH"; then
  echo "[WARN] Base commit $BASE_COMMIT unavailable after fetch. Will fall back to current commit diff."
  FALLBACK_TO_CURRENT_COMMIT=1
fi

if ! ensure_commit_available "$CIRCLE_SHA1" "$CIRCLE_BRANCH"; then
  echo "[ERROR] Current commit $CIRCLE_SHA1 is not available locally. Attempting to fetch..."
  git fetch origin "$CIRCLE_BRANCH" --depth=1 2>/dev/null || true
  if ! git cat-file -e "${CIRCLE_SHA1}^{commit}" 2>/dev/null; then
    echo "[ERROR] Unable to access current commit $CIRCLE_SHA1. Exiting to avoid false results."
    exit 1
  fi
fi

# Get changed files. If base commit is missing (e.g., force-push removed it),
# use the current commit's file list as a conservative fallback.
if [[ "$FALLBACK_TO_CURRENT_COMMIT" -eq 1 ]]; then
  CHANGED_FILES=$(git show --pretty="" --name-only "$CIRCLE_SHA1")
else
  CHANGED_FILES=$(git diff --name-only "$BASE_COMMIT" "$CIRCLE_SHA1")
fi
if [[ -z "$CHANGED_FILES" ]]; then
  echo "[INFO] No changes detected between $BASE_COMMIT and $CIRCLE_SHA1."
  exit 0
fi

# Print the change set
echo "Change set ($BASE_COMMIT to $CIRCLE_SHA1):"
echo "$CHANGED_FILES"

# Handle CI_SKIP_PATHS
if [[ -n "$CI_SKIP_PATHS" ]]; then
  IFS=',' read -ra SKIP_PATHS <<< "$CI_SKIP_PATHS"
  all_skipped=true
  for file in $CHANGED_FILES; do
    skipped=false
    for path in "${SKIP_PATHS[@]}"; do
      if [[ $file == $path* ]]; then
        skipped=true
        break
      fi
    done
    if [[ $skipped == false ]]; then
      all_skipped=false
      break
    fi
  done
  if [[ $all_skipped == true ]]; then
    echo "All changes are within CI_SKIP_PATHS ($CI_SKIP_PATHS). Cancelling workflow."
    if [[ -z "$CIRCLE_CI_API_TOKEN" || -z "$CIRCLE_WORKFLOW_ID" ]]; then
      echo "CIRCLE_CI_API_TOKEN or CIRCLE_WORKFLOW_ID not set. Cannot cancel workflow. Exiting with code 0."
      exit 0
    fi
    curl -s -X POST \
      --header "Circle-Token: $CIRCLE_CI_API_TOKEN" \
      "https://circleci.com/api/v2/workflow/${CIRCLE_WORKFLOW_ID}/cancel"
    echo "Workflow cancellation requested. Exiting."
    exit 0
  fi
fi

# --- PR approval check using gh CLI ---
# Install gh CLI if not present
if ! command -v gh &> /dev/null; then
  echo '[INFO] gh CLI not found. Installing...'
  if command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y gh
  elif command -v yum &> /dev/null; then
    sudo yum install -y gh
  else
    echo '[ERROR] Could not install gh CLI. Please ensure it is available.'
    exit 1
  fi
fi

# Export GITHUB_TOKEN for gh CLI
if [[ -n "$GITHUB_BOT_TOKEN" ]]; then
  export GITHUB_TOKEN="$GITHUB_BOT_TOKEN"
fi

# Check if this is a PR build
if [[ -n "$CIRCLE_PULL_REQUEST" ]]; then
  # Extract PR number from URL
  PR_NUMBER=$(echo "$CIRCLE_PULL_REQUEST" | grep -oE '[0-9]+$')
  REPO_FULL_NAME="$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME"
  if [[ -n "$PR_NUMBER" && -n "$REPO_FULL_NAME" ]]; then
    # Query PR approval status
    REVIEW_DECISION=$(gh pr view "$PR_NUMBER" --repo "$REPO_FULL_NAME" --json reviewDecision -q '.reviewDecision' 2>/dev/null || echo "")
    if [[ "$REVIEW_DECISION" == "APPROVED" ]]; then
      echo '[INFO] PR is approved. Not skipping any jobs.'
      exit 0
    fi
  fi
fi

echo "Relevant changes found. Continuing build."
exit 0
