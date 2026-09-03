#!/bin/bash
set -e

GITHUB_TOKEN=$1
COMMAND=$2
VALIDATE=$3

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
EXISTING_BRANCH=$(git for-each-ref --format='%(refname:short)' refs/heads/bump-version-* | head -n 1)

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

git checkout -b "$BRANCH_NAME" 2>/dev/null || git checkout "$BRANCH_NAME"
git add -A
git commit -m "chore: bump version to ${NEW_VERSION}"
git push origin "$BRANCH_NAME"

gh pr create \
  --title "chore: bump version to ${NEW_VERSION}" \
  --body "Automated version bump to ${NEW_VERSION}" \
  --base main \
  --assignee "$GITHUB_ACTOR"
