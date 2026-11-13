# shellcheck shell=bash

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

# ensure_bump_labels: creates the bump labels the repo doesn't have yet.
ensure_bump_labels() {
  REPO_LABELS=$(gh label list --limit 1000 --json name --jq '.[].name')
  ensure_label "$LABEL_MAJOR" "$LABEL_MAJOR_COLOR" "Bumps the major version (breaking changes)"
  ensure_label "$LABEL_MINOR" "$LABEL_MINOR_COLOR" "Bumps the minor version (new features)"
  ensure_label "$LABEL_PATCH" "$LABEL_PATCH_COLOR" "Bumps the patch version (bug fixes)"
}

# bump_type_from_labels: prints major, minor or patch for the PR's highest
# bump label, or nothing when it has none. Whole label names only, ignoring
# case: a `dispatch` label is no patch.
bump_type_from_labels() {
  local labels
  labels=$(event_field '.pull_request.labels[].name' 2>/dev/null || echo "")
  if grep -ixqF -- "$LABEL_MAJOR" <<<"$labels"; then
    echo "major"
  elif grep -ixqF -- "$LABEL_MINOR" <<<"$labels"; then
    echo "minor"
  elif grep -ixqF -- "$LABEL_PATCH" <<<"$labels"; then
    echo "patch"
  fi
}

# bump_label_count: prints how many of the three bump labels the PR has.
# Same whole-name, case-insensitive match as bump_type_from_labels.
bump_label_count() {
  local labels name count=0
  labels=$(event_field '.pull_request.labels[].name' 2>/dev/null || echo "")
  for name in "$LABEL_MAJOR" "$LABEL_MINOR" "$LABEL_PATCH"; do
    if grep -ixqF -- "$name" <<<"$labels"; then
      count=$((count + 1))
    fi
  done
  echo "$count"
}
