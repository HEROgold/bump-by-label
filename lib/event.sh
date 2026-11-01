# shellcheck shell=bash
# shellcheck disable=SC2034 # entrypoint.sh and the outputs read these

# require_event: sets EVENT_PATH, or ends the run outside GitHub Actions.
# BUMP_BY_LABEL_EVENT_PATH lets the e2e test supply its own event: the runner
# resets GITHUB_EVENT_PATH for every step.
require_event() {
  EVENT_PATH=${BUMP_BY_LABEL_EVENT_PATH:-${GITHUB_EVENT_PATH:-}}
  if [ -z "$EVENT_PATH" ]; then
    echo "Error: GITHUB_EVENT_PATH not found. Can only run in a GitHub Actions environment."
    exit 1
  fi
}

# event_field <jq filter>: prints a field of the event.
event_field() {
  jq -r "$1" "$EVENT_PATH"
}

# pr_from_push: an event without a pull_request, such as a push, gets the
# merged PR its commit came from. EVENT_PATH then points at a pull_request
# event built from that PR, so the rest of the run handles the push like the
# PR's merge. This lets a bump job wait for the checks of a push. A commit
# that came from no merged PR ends the run.
pr_from_push() {
  local sha pulls pr_event
  if [ "$(event_field 'has("pull_request")')" = true ]; then
    return 0
  fi
  sha=$(event_field '.after // ""')
  sha=${sha:-${GITHUB_SHA:-}}
  if [ -z "$sha" ]; then
    echo "Error: the event has no pull_request and no pushed commit (.after or GITHUB_SHA)." >&2
    exit 1
  fi

  pulls=$(gh api "repos/${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}/commits/$sha/pulls")
  pr_event=$(mktemp)
  # The list endpoint has no `merged` field, only merged_at.
  jq '[.[] | select(.merged_at != null)] | first // empty
    | {pull_request: (. + {merged: true})}' <<<"$pulls" >"$pr_event"
  if [ ! -s "$pr_event" ]; then
    echo "Commit $sha didn't come from a merged PR; nothing to bump or tag."
    exit 0
  fi
  EVENT_PATH=$pr_event
  echo "Commit $sha came from PR #$(event_field '.pull_request.number')."
}

# stop_unless_merged: ends the run unless the event is a merged PR. Only a
# merged PR bumps or releases. An open or closed-unmerged PR also has a
# merge_commit_sha (a test merge), which must never be tagged.
stop_unless_merged() {
  if [ "$(event_field '.pull_request.merged // false')" != true ]; then
    echo "PR #$(event_field '.pull_request.number // "?"') is not merged; nothing to bump or tag."
    exit 0
  fi
}

# bump_branch_start: prints how every bump branch name starts,
# `<prefix>/bump-version-from-`. publish_pr names branches with it and
# read_bump_pr recognises merged bump PRs by it.
bump_branch_start() {
  if [ -n "$BRANCH_PREFIX" ]; then
    echo "${BRANCH_PREFIX}/bump-version-from-"
  else
    echo "bump-version-from-"
  fi
}

# read_bump_pr <head ref>: true when <head ref> is a bump branch,
# `<prefix>/bump-version-from-X.Y.Z-to-X.Y.Z`. Then sets PREVIOUS_VERSION,
# BUMPED_VERSION, BUMP_TYPE and VERSION_BUMPED from the branch name.
read_bump_pr() {
  local head_ref=$1 start semver_re='([0-9]+)\.([0-9]+)\.([0-9]+)'
  local -a old new
  start=$(bump_branch_start)
  [[ $head_ref == "$start"* ]] || return 1
  [[ ${head_ref#"$start"} =~ ^${semver_re}-to-${semver_re}$ ]] || return 1

  old=("${BASH_REMATCH[@]:1:3}")
  new=("${BASH_REMATCH[@]:4:3}")
  PREVIOUS_VERSION="${old[0]}.${old[1]}.${old[2]}"
  BUMPED_VERSION="${new[0]}.${new[1]}.${new[2]}"
  VERSION_BUMPED=true
  if [ "${new[0]}" != "${old[0]}" ]; then
    BUMP_TYPE="major"
  elif [ "${new[1]}" != "${old[1]}" ]; then
    BUMP_TYPE="minor"
  else
    BUMP_TYPE="patch"
  fi
}
