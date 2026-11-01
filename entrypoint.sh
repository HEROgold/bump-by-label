#!/bin/bash
set -euo pipefail

# Runs bump-by-label for one pull_request event. This file only picks the
# path; each path's code is in lib/. A path's files are loaded only when the
# run takes that path, so an option that turns a path off never loads it.
#
#   PR not merged                    stop
#   head branch is a bump branch     tag the merge commit (lib/tag.sh)
#   no bump label                    stop
#   mode: push                       bump on the base branch (lib/push-mode.sh)
#   mode: pr                         open a bump PR (lib/pr-mode.sh)

ACTION_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB=$ACTION_DIR/lib

# Helper scripts shipped with the action (semver-bump.sh) can be used in
# `command` and `validate`.
PATH="$ACTION_DIR/scripts:$PATH"

# shellcheck source=lib/inputs.sh
source "$LIB/inputs.sh"
# shellcheck source=lib/outputs.sh
source "$LIB/outputs.sh"
# shellcheck source=lib/event.sh
source "$LIB/event.sh"
# shellcheck source=lib/labels.sh
source "$LIB/labels.sh"

read_inputs
trap write_outputs EXIT
require_event
stop_unless_merged

git config --local user.name "$COMMIT_USER_NAME"
git config --local user.email "$COMMIT_USER_EMAIL"
ensure_bump_labels

# A merged bump PR releases the version it bumped to: tag the merge commit
# and skip the label logic.
HEAD_REF=$(event_field '.pull_request.head.ref // ""')
if read_bump_pr "$HEAD_REF"; then
  PR_NUMBER=$(event_field '.pull_request.number // ""')
  echo "PR #$PR_NUMBER ($HEAD_REF) is a bump PR for $BUMPED_VERSION; skipping the version bump."
  if [ "$CREATE_TAG" != true ]; then
    echo "create-tag is off; not tagging."
    exit 0
  fi
  # shellcheck source=lib/tag.sh
  source "$LIB/tag.sh"
  tag_merge_commit
  exit 0
fi

BUMP_TYPE=$(bump_type_from_labels)
if [ -z "$BUMP_TYPE" ]; then
  echo "No '$LABEL_MAJOR', '$LABEL_MINOR' or '$LABEL_PATCH' label found. Version bump skipped."
  exit 0
fi

# shellcheck source=lib/version.sh
source "$LIB/version.sh"

if [ "$MODE" = push ]; then
  # shellcheck source=lib/push-mode.sh
  source "$LIB/push-mode.sh"
  publish_push
  # No bump PR will merge later, so tag the pushed commit now.
  if [ "$CREATE_TAG" = true ]; then
    # shellcheck source=lib/tag.sh
    source "$LIB/tag.sh"
    tag_release "$(git rev-parse HEAD)"
  fi
  exit 0
fi

# shellcheck source=lib/pr-mode.sh
source "$LIB/pr-mode.sh"
publish_pr
