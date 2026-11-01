# shellcheck shell=bash
# shellcheck disable=SC2034 # the outputs read these

# Loaded only with mode: push.

# publish_push: bumps on the tip of the base branch, commits and pushes.
# When the push is rejected because the base moved, it redoes the bump from
# the new tip instead of rebasing, so a version another run pushed meanwhile
# is bumped again. Up to 3 attempts. A rejection while the base didn't move
# (branch protection, permissions) fails at once. Never forces.
publish_push() {
  local attempt tip
  if [ -n "$(git status --porcelain)" ]; then
    echo "Error: the working tree has uncommitted changes from earlier steps;" \
      "push mode would commit them to $BASE_BRANCH:" >&2
    git status --short >&2
    exit 1
  fi
  for attempt in 1 2 3; do
    git fetch -q origin "$BASE_BRANCH"
    tip=$(git rev-parse "origin/$BASE_BRANCH")
    git checkout -q -B "$BASE_BRANCH" "$tip"
    bump_version
    stop_if_unchanged
    commit_bump
    if git push origin "HEAD:refs/heads/$BASE_BRANCH"; then
      VERSION_BUMPED=true
      BUMPED_VERSION=$NEW_VERSION
      echo "Pushed $TITLE to $BASE_BRANCH."
      return 0
    fi
    git fetch -q origin "$BASE_BRANCH"
    if [ "$(git rev-parse "origin/$BASE_BRANCH")" = "$tip" ]; then
      echo "Error: the push to $BASE_BRANCH was refused and $BASE_BRANCH hasn't moved." \
        "Branch protection must let this token push (GITHUB_TOKEN can't bypass required reviews)." >&2
      exit 1
    fi
    echo "$BASE_BRANCH moved during attempt $attempt; redoing the bump from its new tip."
  done
  echo "Error: $BASE_BRANCH kept moving; gave up after 3 attempts. Nothing was pushed." >&2
  exit 1
}
