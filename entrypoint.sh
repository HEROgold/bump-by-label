#!/bin/bash
set -euo pipefail

# Inputs arrive as INPUT_* environment variables (see action.yml); GH_TOKEN
# is set there too.
COMMAND=${INPUT_COMMAND:?INPUT_COMMAND (the command input) is required}
VALIDATE=${INPUT_VALIDATE:?INPUT_VALIDATE (the validate input) is required}
BASE_BRANCH=${INPUT_BASE_BRANCH:-main}
BRANCH_PREFIX=${INPUT_BRANCH_PREFIX-workflow}
CREATE_TAG=${INPUT_CREATE_TAG:-true}
TAG_PREFIX=${INPUT_TAG_PREFIX-v}
MOVING_TAGS=${INPUT_MOVING_TAGS:-false}
LABEL_MAJOR=${INPUT_LABEL_MAJOR:-Major}
LABEL_MINOR=${INPUT_LABEL_MINOR:-Minor}
LABEL_PATCH=${INPUT_LABEL_PATCH:-Patch}
LABELS_TO_ADD=${INPUT_LABELS_TO_ADD:-}
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

# ensure_label <name> <color> <description>: creates the label unless the
# repo already has it (GitHub label names ignore case). Never --force: that
# resets colours and descriptions the user changed.
REPO_LABELS=""
ensure_label() {
  if grep -ixqF -- "$1" <<<"$REPO_LABELS"; then
    return 0
  fi
  echo "Creating label '$1'."
  gh label create "$1" --color "$2" --description "$3"
  REPO_LABELS+=$'\n'"$1"
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

# Action outputs. The EXIT trap writes all of them on every exit path, so
# steps.<id>.outputs.version-bumped is never undefined.
VERSION_BUMPED=false
PREVIOUS_VERSION=""
BUMPED_VERSION=""
BUMP_TYPE=""
PR_NUMBER=""
TAG=""
write_outputs() {
  [ -n "${GITHUB_OUTPUT:-}" ] || return 0
  {
    echo "version-bumped=$VERSION_BUMPED"
    echo "previous-version=$PREVIOUS_VERSION"
    echo "new-version=$BUMPED_VERSION"
    echo "bump-type=${BUMP_TYPE:-none}"
    echo "pr-number=$PR_NUMBER"
    echo "tag=$TAG"
  } >>"$GITHUB_OUTPUT"
}
trap write_outputs EXIT

# BUMP_BY_LABEL_EVENT_PATH lets the e2e test supply its own event: the runner
# resets GITHUB_EVENT_PATH for every step.
EVENT_PATH=${BUMP_BY_LABEL_EVENT_PATH:-${GITHUB_EVENT_PATH:-}}
if [ -z "$EVENT_PATH" ]; then
  echo "Error: GITHUB_EVENT_PATH not found. Can only run in a GitHub Actions environment."
  exit 1
fi

git config --local user.name "$COMMIT_USER_NAME"
git config --local user.email "$COMMIT_USER_EMAIL"

REPO_LABELS=$(gh label list --limit 1000 --json name --jq '.[].name')
ensure_label "$LABEL_MAJOR" "${INPUT_LABEL_MAJOR_COLOR:-d93f0b}" "Bumps the major version (breaking changes)"
ensure_label "$LABEL_MINOR" "${INPUT_LABEL_MINOR_COLOR:-0e8a16}" "Bumps the minor version (new features)"
ensure_label "$LABEL_PATCH" "${INPUT_LABEL_PATCH_COLOR:-0075ca}" "Bumps the patch version (bug fixes)"

# A merged bump PR (its head branch is a bump branch, see below) releases
# the version it bumped to: tag the merge commit and skip the label logic.
HEAD_REF=$(jq -r '.pull_request.head.ref // ""' "$EVENT_PATH")
BUMP_BRANCH_START="bump-version-from-"
if [ -n "$BRANCH_PREFIX" ]; then
  BUMP_BRANCH_START="${BRANCH_PREFIX}/${BUMP_BRANCH_START}"
fi
SEMVER_RE='([0-9]+)\.([0-9]+)\.([0-9]+)'
if [[ $HEAD_REF == "$BUMP_BRANCH_START"* ]] &&
  [[ ${HEAD_REF#"$BUMP_BRANCH_START"} =~ ^${SEMVER_RE}-to-${SEMVER_RE}$ ]]; then
  # An open or closed-unmerged PR also has a merge_commit_sha (a test merge),
  # which must never be tagged as a release.
  if [ "$(jq -r '.pull_request.merged // false' "$EVENT_PATH")" != true ]; then
    echo "Bump PR from $HEAD_REF is not merged; nothing to tag."
    exit 0
  fi
  OLD=("${BASH_REMATCH[@]:1:3}")
  NEW=("${BASH_REMATCH[@]:4:3}")
  PREVIOUS_VERSION="${OLD[0]}.${OLD[1]}.${OLD[2]}"
  BUMPED_VERSION="${NEW[0]}.${NEW[1]}.${NEW[2]}"
  VERSION_BUMPED=true
  PR_NUMBER=$(jq -r '.pull_request.number // ""' "$EVENT_PATH")
  if [ "${NEW[0]}" != "${OLD[0]}" ]; then
    BUMP_TYPE="major"
  elif [ "${NEW[1]}" != "${OLD[1]}" ]; then
    BUMP_TYPE="minor"
  else
    BUMP_TYPE="patch"
  fi
  echo "PR #$PR_NUMBER ($HEAD_REF) is a bump PR for $BUMPED_VERSION; skipping the version bump."

  if [ "$CREATE_TAG" != true ]; then
    echo "create-tag is off; not tagging."
    exit 0
  fi

  MERGE_SHA=$(jq -r '.pull_request.merge_commit_sha // ""' "$EVENT_PATH")
  if [ -z "$MERGE_SHA" ]; then
    echo "Error: the event has no pull_request.merge_commit_sha to tag." >&2
    exit 1
  fi
  if ! git cat-file -e "${MERGE_SHA}^{commit}" 2>/dev/null; then
    git fetch -q origin "$MERGE_SHA"
  fi

  RELEASE_TAG="${TAG_PREFIX}${BUMPED_VERSION}"
  if git ls-remote --exit-code --tags origin "refs/tags/$RELEASE_TAG" >/dev/null; then
    echo "Tag $RELEASE_TAG already exists; not tagging."
  else
    git tag -a "$RELEASE_TAG" -m "Release $RELEASE_TAG" "$MERGE_SHA"
    git push origin "refs/tags/$RELEASE_TAG"
    TAG=$RELEASE_TAG
    echo "Tagged $MERGE_SHA as $RELEASE_TAG."
  fi

  # Moving tags follow only a release this run tagged, so they never end up
  # on a commit the release tag doesn't point at.
  if [ "$MOVING_TAGS" = true ] && [ -n "$TAG" ]; then
    # The only force-pushes besides the bump branch, and only of these tags.
    for MOVING_TAG in "${TAG_PREFIX}${NEW[0]}" "${TAG_PREFIX}${NEW[0]}.${NEW[1]}"; do
      git tag -f -a "$MOVING_TAG" -m "Release $RELEASE_TAG" "$MERGE_SHA"
      git push -f origin "refs/tags/$MOVING_TAG"
      echo "Moved $MOVING_TAG to $MERGE_SHA."
    done
  fi
  exit 0
fi

LABELS=$(jq -r '.pull_request.labels[].name' "$EVENT_PATH" 2>/dev/null || echo "")

# Whole label names only, ignoring case: a `dispatch` label is no patch.
if grep -ixqF -- "$LABEL_MAJOR" <<<"$LABELS"; then
  BUMP_TYPE="major"
elif grep -ixqF -- "$LABEL_MINOR" <<<"$LABELS"; then
  BUMP_TYPE="minor"
elif grep -ixqF -- "$LABEL_PATCH" <<<"$LABELS"; then
  BUMP_TYPE="patch"
fi

if [ -z "$BUMP_TYPE" ]; then
  echo "No '$LABEL_MAJOR', '$LABEL_MINOR' or '$LABEL_PATCH' label found. Version bump skipped."
  exit 0
fi

echo "Validating the current version..."
OLD_VERSION=$(read_version)
PREVIOUS_VERSION=$OLD_VERSION
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

# Always rebuild the branch from the current default branch tip rather than
# reusing whatever the existing local/remote branch points at: the bump
# branch is disposable and regenerated on every run, so a --force push is the
# correct (and only reliable) way to publish it.
git checkout -B "$BRANCH_NAME" "origin/${BASE_BRANCH}"
git add -A
git commit -m "$TITLE"
git push --force origin "$BRANCH_NAME"
VERSION_BUMPED=true
BUMPED_VERSION=$NEW_VERSION

if EXISTING_PR=$(gh pr view "$BRANCH_NAME" --json number --jq .number 2>/dev/null); then
  PR_NUMBER=$EXISTING_PR
  echo "PR #$PR_NUMBER for $BRANCH_NAME already exists; updated it with the force-push above."
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
IFS=',' read -ra EXTRA_LABELS <<<"$LABELS_TO_ADD"
for LABEL in "${EXTRA_LABELS[@]}"; do
  LABEL="${LABEL#"${LABEL%%[![:space:]]*}"}"
  LABEL="${LABEL%"${LABEL##*[![:space:]]}"}"
  if [ -n "$LABEL" ]; then
    ensure_label "$LABEL" "ededed" "Added to version bump PRs by bump-by-label"
    PR_ARGS+=(--label "$LABEL")
  fi
done

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
# gh pr create prints the new PR's URL, which ends in its number. The output
# includes stderr, so take the URL rather than the last line.
PR_NUMBER=$(grep -Eo '/pull/[0-9]+' <<<"$PR_OUTPUT" | tail -n 1) || true
PR_NUMBER=${PR_NUMBER##*/}
