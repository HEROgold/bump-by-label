#!/usr/bin/env bats
# The tag step: a merged bump PR gets its release tagged instead of a bump.

setup() {
  load test_helper
  setup_repo
  # Proves the bump logic is skipped for a bump PR.
  export INPUT_COMMAND="exit 9"
  MERGE_SHA=$(git rev-parse HEAD)
  export MERGE_SHA
}

# merge_bump_pr <head-ref>: runs the entrypoint for a merged PR from <head-ref>.
merge_bump_pr() {
  PR_HEAD_REF=$1 bump
}

remote_tag() {
  git --git-dir="$ORIGIN" rev-parse --verify -q "refs/tags/$1^{commit}"
}

@test "a merged bump PR tags the merge commit" {
  merge_bump_pr workflow/bump-version-from-1.2.3-to-1.2.4

  [ "$status" -eq 0 ]
  [ "$(remote_tag v1.2.4)" = "$MERGE_SHA" ]
  ! remote_tag v1
  assert_outputs version-bumped=true previous-version=1.2.3 new-version=1.2.4 \
    bump-type=patch pr-number=42 tag=v1.2.4
}

@test "a bump PR closed without merging isn't tagged" {
  PR_HEAD_REF=workflow/bump-version-from-1.2.3-to-1.2.4 pr_event
  jq '.pull_request.merged = false' "$GITHUB_EVENT_PATH" > "$BATS_TEST_TMPDIR/e.json"
  mv "$BATS_TEST_TMPDIR/e.json" "$GITHUB_EVENT_PATH"

  run bash "$ENTRYPOINT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"not merged"* ]]
  [ -z "$(git --git-dir="$ORIGIN" tag)" ]
  assert_outputs version-bumped=false tag=
}

@test "moving tags stay put when the release tag already exists" {
  git tag v1.2.4 && git tag v1 && git push -q origin v1.2.4 v1
  echo change > CHANGE && git add CHANGE
  git -c user.name=dev -c user.email=dev@example.com commit -q -m change && git push -q origin main
  export MERGE_SHA INPUT_MOVING_TAGS=true
  MERGE_SHA=$(git rev-parse HEAD)

  merge_bump_pr workflow/bump-version-from-1.2.3-to-1.2.4

  [ "$status" -eq 0 ]
  [ "$(remote_tag v1)" = "$(git rev-parse HEAD~1)" ]
  ! remote_tag v1.2
}

@test "the tag is annotated by the commit identity" {
  merge_bump_pr workflow/bump-version-from-1.2.3-to-2.0.0

  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$ORIGIN" cat-file -t v2.0.0)" = "tag" ]
  git --git-dir="$ORIGIN" cat-file -p v2.0.0 | grep -qF "tagger github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>"
  assert_outputs bump-type=major
}

@test "an existing tag is left alone" {
  git tag v1.2.4 && git push -q origin v1.2.4
  echo change > CHANGE && git add CHANGE
  git -c user.name=dev -c user.email=dev@example.com commit -q -m change && git push -q origin main
  export MERGE_SHA
  MERGE_SHA=$(git rev-parse HEAD)

  merge_bump_pr workflow/bump-version-from-1.2.3-to-1.2.4

  [ "$status" -eq 0 ]
  [[ "$output" == *"Tag v1.2.4 already exists"* ]]
  [ "$(remote_tag v1.2.4)" = "$(git rev-parse HEAD~1)" ]
  assert_outputs version-bumped=true new-version=1.2.4 tag=
}

@test "moving tags follow the release" {
  git tag v1 && git push -q origin v1
  echo change > CHANGE && git add CHANGE
  git -c user.name=dev -c user.email=dev@example.com commit -q -m change && git push -q origin main
  export MERGE_SHA INPUT_MOVING_TAGS=true
  MERGE_SHA=$(git rev-parse HEAD)

  merge_bump_pr workflow/bump-version-from-1.2.3-to-1.3.0

  [ "$status" -eq 0 ]
  [ "$(remote_tag v1.3.0)" = "$MERGE_SHA" ]
  [ "$(remote_tag v1.3)" = "$MERGE_SHA" ]
  [ "$(remote_tag v1)" = "$MERGE_SHA" ]
  assert_outputs bump-type=minor tag=v1.3.0
}

@test "create-tag false skips the tag but still skips the bump" {
  export INPUT_CREATE_TAG=false

  merge_bump_pr workflow/bump-version-from-1.2.3-to-1.2.4

  [ "$status" -eq 0 ]
  ! remote_tag v1.2.4
  assert_outputs version-bumped=true new-version=1.2.4 tag=
}

@test "the tag prefix is configurable" {
  export INPUT_TAG_PREFIX="release-"

  merge_bump_pr workflow/bump-version-from-1.2.3-to-1.2.4

  [ "$status" -eq 0 ]
  [ "$(remote_tag release-1.2.4)" = "$MERGE_SHA" ]
  assert_outputs tag=release-1.2.4
}

@test "a custom branch prefix is recognised" {
  export INPUT_BRANCH_PREFIX="release"

  merge_bump_pr release/bump-version-from-1.2.3-to-1.2.4

  [ "$status" -eq 0 ]
  [ "$(remote_tag v1.2.4)" = "$MERGE_SHA" ]
}

@test "branches that don't match the pattern exactly aren't bump PRs" {
  for ref in feature/bump-version-from-1.2.3-to-1.2.4 \
    workflow/bump-version-from-1.2-to-1.3 \
    workflow/bump-version-from-1.2.3-to-1.2.4-fix \
    xworkflow/bump-version-from-1.2.3-to-1.2.4; do
    merge_bump_pr "$ref"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No labels found"* ]]
  done
  [ -z "$(git --git-dir="$ORIGIN" tag)" ]
}
