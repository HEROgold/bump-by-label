#!/usr/bin/env bats
# mode: branch commits the bump on the open PR's own branch.

setup() {
  load test_helper
  setup_repo
  export INPUT_MODE=branch
  echo '1.0.0' > VERSION
  git -c user.name=dev -c user.email=dev@example.com commit -q -am "version 1.0.0"
  git push -q origin main
  # The PR branch holds one feature commit on top of main.
  git checkout -q -b feature
  echo feature > FEATURE
  git add -A
  git -c user.name=dev -c user.email=dev@example.com commit -q -m "feature"
  git push -q origin feature
  git checkout -q main
  OTHER="$BATS_TEST_TMPDIR/other"
  git clone -q "$ORIGIN" "$OTHER"
  # push-to-head <file> <content>: commits on the PR branch in the other clone
  # and pushes it, once, as if someone pushed while the action runs. Put it in
  # INPUT_COMMAND.
  cat > "$BATS_TEST_TMPDIR/bin/push-to-head" <<SCRIPT
#!/usr/bin/env bash
set -e
[ ! -e "$BATS_TEST_TMPDIR/pushed-to-head" ] || exit 0
touch "$BATS_TEST_TMPDIR/pushed-to-head"
git -C "$OTHER" fetch -q origin
git -C "$OTHER" checkout -q -B feature origin/feature
echo "\$2" > "$OTHER/\$1"
git -C "$OTHER" add -A
git -C "$OTHER" -c user.name=other -c user.email=other@example.com commit -q -m "other: \$1"
git -C "$OTHER" push -q origin feature
SCRIPT
  chmod +x "$BATS_TEST_TMPDIR/bin/push-to-head"
}

# branch_event <action> [label...]: writes a pull_request event for the open
# PR from `feature`. HEAD_REPO overrides the head repository.
branch_event() {
  local action=$1
  shift
  jq -n --arg action "$action" --arg head_repo "${HEAD_REPO:-owner/repo}" \
    '{action: $action, pull_request: {number: 42, merged: false,
      head: {ref: "feature", repo: {full_name: $head_repo}},
      base: {ref: "main", repo: {full_name: "owner/repo"}},
      labels: ($ARGS.positional | map({name: .}))}}' \
    --args "$@" > "$GITHUB_EVENT_PATH"
}

# run_branch <action> [label...]: runs the entrypoint for that event.
run_branch() {
  branch_event "$@"
  run bash "$ENTRYPOINT"
  # shellcheck disable=SC2154 # `run` sets $output
  echo "$output"
}

head_sha() {
  git --git-dir="$ORIGIN" rev-parse feature
}

# head_subjects: the subjects of the commits feature has on top of main, oldest first.
head_subjects() {
  git --git-dir="$ORIGIN" log --reverse --format=%s main..feature
}

@test "a Minor label pushes one bump commit to the PR branch" {
  main_before=$(git --git-dir="$ORIGIN" rev-parse main)

  run_branch labeled Minor

  [ "$status" -eq 0 ]
  [ "$(remote_file feature VERSION)" = "1.1.0" ]
  [ "$(head_subjects)" = $'feature\nBump version from 1.0.0 to 1.1.0' ]
  [ "$(git --git-dir="$ORIGIN" rev-parse main)" = "$main_before" ]
  [ "$(remote_file main VERSION)" = "1.0.0" ]
  [ -z "$(git --git-dir="$ORIGIN" tag)" ]
  assert_outputs version-bumped=true previous-version=1.0.0 new-version=1.1.0 \
    bump-type=minor pr-number=42 tag=
}

@test "running again with the same event changes nothing" {
  run_branch labeled Minor
  [ "$status" -eq 0 ]
  before=$(head_sha)

  run_branch synchronize Minor

  [ "$status" -eq 0 ]
  [ "$(head_sha)" = "$before" ]
  [[ $output == *"already has version 1.1.0"* ]]
  assert_outputs version-bumped=false previous-version=1.0.0
}

@test "changing the label to Major leaves one version change on the branch" {
  run_branch labeled Minor
  [ "$status" -eq 0 ]

  run_branch labeled Major

  [ "$status" -eq 0 ]
  [ "$(remote_file feature VERSION)" = "2.0.0" ]
  [ "$(git --git-dir="$ORIGIN" log -1 --format=%s feature)" = "Bump version from 1.0.0 to 2.0.0" ]
  [ "$(git --git-dir="$ORIGIN" diff --numstat main feature -- VERSION)" = $'1\t1\tVERSION' ]
  assert_outputs version-bumped=true previous-version=1.0.0 new-version=2.0.0 bump-type=major
}

@test "removing the label resets the version to the base version" {
  run_branch labeled Minor
  [ "$status" -eq 0 ]

  run_branch unlabeled

  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$ORIGIN" log -1 --format=%s feature)" = "Reset version to 1.0.0" ]
  [ "$(remote_file feature VERSION)" = "$(remote_file main VERSION)" ]
  assert_outputs version-bumped=true previous-version=1.0.0 new-version=1.0.0 bump-type=none
}

@test "two version labels fail and push nothing" {
  before=$(head_sha)

  run_branch labeled Minor Patch

  [ "$status" -eq 1 ]
  [[ $output == *"has more than one version label"* ]]
  [ "$(head_sha)" = "$before" ]
}

@test "a PR from a fork fails and pushes nothing" {
  before=$(head_sha)
  export HEAD_REPO="someone/repo"

  run_branch labeled Minor

  [ "$status" -eq 1 ]
  [[ $output == *"comes from the fork someone/repo"* ]]
  [ "$(head_sha)" = "$before" ]
}

@test "a base branch that moved and was merged in gives the next version" {
  git clone -q "$ORIGIN" "$BATS_TEST_TMPDIR/mover"
  echo '1.0.1' > "$BATS_TEST_TMPDIR/mover/VERSION"
  git -C "$BATS_TEST_TMPDIR/mover" -c user.name=dev -c user.email=dev@example.com commit -q -am "Bump version from 1.0.0 to 1.0.1"
  git -C "$BATS_TEST_TMPDIR/mover" push -q origin main
  git fetch -q origin
  git checkout -q -B feature origin/feature
  git -c user.name=dev -c user.email=dev@example.com merge -q --no-edit origin/main
  git push -q origin feature
  git checkout -q main

  run_branch synchronize Patch

  [ "$status" -eq 0 ]
  [ "$(remote_file feature VERSION)" = "1.0.2" ]
  [ "$(git --git-dir="$ORIGIN" log -1 --format=%s feature)" = "Bump version from 1.0.1 to 1.0.2" ]
}

@test "a hand-edited version with no bump commit fails and pushes nothing" {
  git checkout -q feature
  echo '1.5.0' > VERSION
  git -c user.name=dev -c user.email=dev@example.com commit -q -am "edit version by hand"
  git push -q origin feature
  git checkout -q main
  before=$(head_sha)

  run_branch labeled Minor

  [ "$status" -eq 1 ]
  [[ $output == *"The version was edited by hand"* ]]
  [ "$(head_sha)" = "$before" ]
}

@test "a closed PR does nothing" {
  before=$(head_sha)

  run_branch closed Minor

  [ "$status" -eq 0 ]
  [[ $output == *"nothing to do for 'closed'"* ]]
  [ "$(head_sha)" = "$before" ]
  assert_outputs version-bumped=false
}

@test "a push event does nothing" {
  before=$(head_sha)
  push_event

  run bash "$ENTRYPOINT"
  echo "$output"

  [ "$status" -eq 0 ]
  [[ $output == *"nothing to do"* ]]
  [ "$(head_sha)" = "$before" ]
  assert_outputs version-bumped=false
}

@test "the run retries when the PR branch moved during the push" {
  export INPUT_COMMAND="semver-bump.sh VERSION '' {bump} && push-to-head NOTES moved"

  run_branch labeled Minor

  [ "$status" -eq 0 ]
  [ "$(remote_file feature NOTES)" = "moved" ]
  [ "$(remote_file feature VERSION)" = "1.1.0" ]
  [ "$(git --git-dir="$ORIGIN" log -1 --format=%s feature)" = "Bump version from 1.0.0 to 1.1.0" ]
  [ "$(git --git-dir="$ORIGIN" log -1 --format=%s feature~1)" = "other: NOTES" ]
}
