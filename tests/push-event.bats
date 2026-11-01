#!/usr/bin/env bats
# Push events: the action looks up the merged PR the pushed commit came from
# and handles the push like that PR's merge.

setup() {
  load test_helper
  setup_repo
  push_event
}

remote_tag() {
  git --git-dir="$ORIGIN" rev-parse --verify -q "refs/tags/$1^{commit}"
}

@test "a push from a merged labelled PR bumps and opens a PR" {
  local pushed
  pushed=$(git rev-parse HEAD)
  commit_pull true Minor

  run bash "$ENTRYPOINT"
  echo "$output"

  [ "$status" -eq 0 ]
  gh_called "api repos/owner/repo/commits/$pushed/pulls"
  [ "$(remote_file "$(bump_branch 1.2.3 1.3.0)" VERSION)" = "1.3.0" ]
  gh_called "pr create"
  assert_outputs version-bumped=true new-version=1.3.0 bump-type=minor pr-number=7
}

@test "a push from a merged bump PR tags the merge commit" {
  export INPUT_COMMAND="exit 9"
  PR_HEAD_REF=workflow/bump-version-from-1.2.3-to-1.2.4 commit_pull true

  run bash "$ENTRYPOINT"
  echo "$output"

  [ "$status" -eq 0 ]
  [ "$(remote_tag v1.2.4)" = "$(git rev-parse HEAD)" ]
  gh_not_called "pr create"
  assert_outputs version-bumped=true new-version=1.2.4 bump-type=patch pr-number=42 tag=v1.2.4
}

@test "a push from a merged PR without a bump label bumps nothing" {
  commit_pull true documentation

  run bash "$ENTRYPOINT"
  echo "$output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Version bump skipped"* ]]
  gh_not_called "pr create"
  assert_outputs version-bumped=false bump-type=none
}

@test "a push whose commit came from no PR bumps nothing" {
  run bash "$ENTRYPOINT"
  echo "$output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"didn't come from a merged PR"* ]]
  gh_not_called "label list"
  gh_not_called "pr create"
  assert_outputs version-bumped=false bump-type=none tag=
}

@test "a PR that lists the commit but isn't merged bumps nothing" {
  commit_pull false Minor

  run bash "$ENTRYPOINT"
  echo "$output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"didn't come from a merged PR"* ]]
  gh_not_called "pr create"
}

@test "an event without .after uses GITHUB_SHA" {
  push_event ""
  export GITHUB_SHA=0123456789abcdef0123456789abcdef01234567

  run bash "$ENTRYPOINT"
  echo "$output"

  [ "$status" -eq 0 ]
  gh_called "commits/$GITHUB_SHA/pulls"
}

@test "an event without .after or GITHUB_SHA fails" {
  push_event ""
  unset GITHUB_SHA

  run bash "$ENTRYPOINT"
  echo "$output"

  [ "$status" -ne 0 ]
  [[ "$output" == *"no pushed commit"* ]]
  assert_outputs version-bumped=false
}

@test "a failing PR lookup fails the run" {
  export GH_API_EXIT=1

  run bash "$ENTRYPOINT"
  echo "$output"

  [ "$status" -ne 0 ]
  gh_not_called "pr create"
  assert_outputs version-bumped=false
}

@test "push mode bumps on a push from a merged labelled PR" {
  export INPUT_MODE=push
  commit_pull true Patch

  run bash "$ENTRYPOINT"
  echo "$output"

  [ "$status" -eq 0 ]
  [ "$(remote_file main VERSION)" = "1.2.4" ]
  [ -n "$(remote_tag v1.2.4)" ]
}
