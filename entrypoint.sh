#!/bin/bash
set -e

GITHUB_TOKEN=$1
COMMAND=$2
VALIDATE=$3
BASE_BRANCH=${4:-main}

export GH_TOKEN="$GITHUB_TOKEN"

if [ -z "$GITHUB_EVENT_PATH" ]; then
  echo "Error: GITHUB_EVENT_PATH not found. Can only run in a GitHub Actions environment."
  exit 1
fi

LABELS=$(jq -r '.pull_request.labels[].name' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "")

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

# Determine the bump type based on the labels
BUMP_TYPE=""
if echo "$LABELS" | grep -iq "Major"; then
  BUMP_TYPE="major"
elif echo "$LABELS" | grep -iq "Minor"; then
  BUMP_TYPE="minor"
elif echo "$LABELS" | grep -iq "Patch"; then
  BUMP_TYPE="patch"
fi

if [ -z "$BUMP_TYPE" ]; then
  echo "No 'Major', 'Minor' or 'Patch' label found. Version bump skipped."
  exit 0
fi

BRANCH_NAME="bump-version-${BUMP_TYPE}"

# Look for an already-pushed bump branch on the remote, not just locally: a
# fresh checkout has no other local branches, so a local-only check here
# never sees a branch left behind by a previous run and silently diverges
# from it, causing a non-fast-forward push rejection later.
git fetch origin 'refs/heads/bump-version-*:refs/remotes/origin/bump-version-*' 2>/dev/null || true
EXISTING_BRANCH=$(git for-each-ref --format='%(refname:short)' refs/remotes/origin/bump-version-* | sed 's#^origin/##' | head -n 1)

if [ -n "$EXISTING_BRANCH" ]; then
  echo "A bump-version-* branch already exists: $EXISTING_BRANCH"
  echo "Checking out existing branch."
  BRANCH_NAME="$EXISTING_BRANCH"
fi

echo "Running command: $COMMAND"
echo "Found bump-type: $BUMP_TYPE"

$COMMAND "$BUMP_TYPE"
NEW_VERSION="$BUMP_TYPE"

if [ -n "$VALIDATE" ]; then
  echo "Validating the new version..."
  NEW_VERSION=$($VALIDATE | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
  echo "New version validated: $NEW_VERSION"
  BRANCH_NAME="bump-version-${NEW_VERSION}"
fi

git config --local user.email "action@github.com"
git config --local user.name "GitHub Action"

# Always rebuild the branch from the current default branch tip rather than
# reusing whatever the existing local/remote branch points at: the bump
# branch is disposable and regenerated on every run, so a --force push is the
# correct (and only reliable) way to publish it.
git checkout -B "$BRANCH_NAME" "origin/${BASE_BRANCH}"
git add -A
git commit -m "chore: bump version to ${NEW_VERSION}"
git push --force origin "$BRANCH_NAME"

if gh pr view "$BRANCH_NAME" >/dev/null 2>&1; then
  echo "PR for $BRANCH_NAME already exists; updated it with the force-push above."
else
  gh pr create \
    --title "chore: bump version to ${NEW_VERSION}" \
    --body "Automated version bump to ${NEW_VERSION}" \
    --base "$BASE_BRANCH" \
    --head "$BRANCH_NAME" \
    --assignee "$GITHUB_ACTOR"
fi
