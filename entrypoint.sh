#!/bin/bash
set -euo pipefail

# Inputs arrive as INPUT_* environment variables (see action.yml); GH_TOKEN
# is set there too.
COMMAND=${INPUT_COMMAND:?INPUT_COMMAND (the command input) is required}
VALIDATE=${INPUT_VALIDATE:?INPUT_VALIDATE (the validate input) is required}
BASE_BRANCH=${INPUT_BASE_BRANCH:-main}
BRANCH_PREFIX=${INPUT_BRANCH_PREFIX-workflow}
# 41898282 is the user id of github-actions[bot]; this noreply address is
# what links commits to the bot account.
COMMIT_USER_NAME=${INPUT_COMMIT_USER_NAME:-github-actions[bot]}
COMMIT_USER_EMAIL=${INPUT_COMMIT_USER_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}

# Helper scripts shipped with the action (semver-bump.sh) can be used in
# `command` and `validate`.
PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts:$PATH"

# Runs `command` through bash so its quoting works. `{bump}` is replaced by
# the bump type; without it, the bump type is appended as the last argument.
run_command() {
  if [[ $COMMAND == *"{bump}"* ]]; then
    bash -c "${COMMAND//\{bump\}/$BUMP_TYPE}"
  else
    bash -c "$COMMAND \"\$1\"" bump-by-label "$BUMP_TYPE"
  fi
}

# Prints the first MAJOR.MINOR.PATCH that `validate` prints on stdout. Its
# stderr goes to the log as is: tool warnings there often name versions.
# Fails the run with the command and its output when it fails or prints no
# version.
read_version() {
  local output status=0 version
  output=$(bash -c "$VALIDATE") || status=$?
  if [ "$status" -ne 0 ]; then
    echo "Error: the validate command failed (exit $status): $VALIDATE" >&2
    echo "$output" >&2
    return 1
  fi
  # No match is handled below, so grep's exit status is ignored on purpose.
  version=$(grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' <<<"$output" | head -n 1) || true
  if [ -z "$version" ]; then
    echo "Error: the validate command printed no MAJOR.MINOR.PATCH version: $VALIDATE" >&2
    echo "$output" >&2
    return 1
  fi
  echo "$version"
}

# BUMP_BY_LABEL_EVENT_PATH lets the e2e test supply its own event: the runner
# resets GITHUB_EVENT_PATH for every step.
EVENT_PATH=${BUMP_BY_LABEL_EVENT_PATH:-${GITHUB_EVENT_PATH:-}}
if [ -z "$EVENT_PATH" ]; then
  echo "Error: GITHUB_EVENT_PATH not found. Can only run in a GitHub Actions environment."
  exit 1
fi

LABELS=$(jq -r '.pull_request.labels[].name' "$EVENT_PATH" 2>/dev/null || echo "")

# ensure there's labels on the repository.
if [ -z "$LABELS" ]; then
  echo "No labels found on the pull request. Creating 'Major', 'Minor', and 'Patch' labels."
  
  gh label create "Major" --description "Bumps the major version (breaking changes)" --color "d93f0b" --force
  gh label create "Minor" --description "Bumps the minor version (new features)" --color "0e8a16" --force
  gh label create "Patch" --description "Bumps the patch version (bug fixes)" --color "0075ca" --force
  
  echo "Labels 'Major', 'Minor' and 'Patch' created successfully."
  echo "Add one of these labels to the PR and run the action again."
  exit 0
fi

# Determine the bump type based on the labels. Here-strings, not
# `echo | grep -q`: with pipefail, grep -q exiting early can fail the echo.
BUMP_TYPE=""
if grep -iq "Major" <<<"$LABELS"; then
  BUMP_TYPE="major"
elif grep -iq "Minor" <<<"$LABELS"; then
  BUMP_TYPE="minor"
elif grep -iq "Patch" <<<"$LABELS"; then
  BUMP_TYPE="patch"
fi

if [ -z "$BUMP_TYPE" ]; then
  echo "No 'Major', 'Minor' or 'Patch' label found. Version bump skipped."
  exit 0
fi

echo "Validating the current version..."
OLD_VERSION=$(read_version)
echo "Current version: $OLD_VERSION"

echo "Running command: $COMMAND"
echo "Found bump-type: $BUMP_TYPE"

run_command

echo "Validating the new version..."
NEW_VERSION=$(read_version)
echo "New version validated: $NEW_VERSION"

if [ "$NEW_VERSION" = "$OLD_VERSION" ]; then
  echo "No version bump required."
  exit 0
fi

# Old and new version are both in the name, so rerunning the same bump
# force-pushes the same branch and a different bump gets its own. The tag
# step recognises merged bump PRs by this name.
BRANCH_NAME="bump-version-from-${OLD_VERSION}-to-${NEW_VERSION}"
if [ -n "$BRANCH_PREFIX" ]; then
  BRANCH_NAME="${BRANCH_PREFIX}/${BRANCH_NAME}"
fi
TITLE="Bump version from ${OLD_VERSION} to ${NEW_VERSION}"

git config --local user.name "$COMMIT_USER_NAME"
git config --local user.email "$COMMIT_USER_EMAIL"

# Always rebuild the branch from the current default branch tip rather than
# reusing whatever the existing local/remote branch points at: the bump
# branch is disposable and regenerated on every run, so a --force push is the
# correct (and only reliable) way to publish it.
git checkout -B "$BRANCH_NAME" "origin/${BASE_BRANCH}"
git add -A
git commit -m "$TITLE"
git push --force origin "$BRANCH_NAME"

if gh pr view "$BRANCH_NAME" >/dev/null 2>&1; then
  echo "PR for $BRANCH_NAME already exists; updated it with the force-push above."
  exit 0
fi

PR_ARGS=(
  --title "$TITLE"
  --body "Automated version bump from ${OLD_VERSION} to ${NEW_VERSION}."
  --base "$BASE_BRANCH"
  --head "$BRANCH_NAME"
)
if [ -n "${GITHUB_ACTOR:-}" ]; then
  PR_ARGS+=(--assignee "$GITHUB_ACTOR")
fi

PR_STATUS=0
PR_OUTPUT=$(gh pr create "${PR_ARGS[@]}" 2>&1) || PR_STATUS=$?
echo "$PR_OUTPUT"
if [ "$PR_STATUS" -ne 0 ]; then
  if grep -q "not permitted to create or approve pull requests" <<<"$PR_OUTPUT"; then
    echo "Error: GitHub Actions may not open PRs in this repository. Turn on" \
      "Settings > Actions > General > Workflow permissions >" \
      "\"Allow GitHub Actions to create and approve pull requests\"," \
      "or pass a PAT or app token as github_token." >&2
  else
    echo "Error: gh pr create failed (exit $PR_STATUS)." >&2
  fi
  exit "$PR_STATUS"
fi
