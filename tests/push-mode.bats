#!/usr/bin/env bats
# mode: push commits the bump on the base branch instead of opening a PR.

setup() {
  load test_helper
  setup_repo
  export INPUT_MODE=push
  OTHER="$BATS_TEST_TMPDIR/other"
  git clone -q "$ORIGIN" "$OTHER"
  # push-from-other <file> <content> <message> [every]: commits in the other
  # clone and pushes to main, as if someone merged while the action runs. Put
  # it in INPUT_COMMAND. It pushes on the first call only, since push mode
  # reruns the command on each attempt; with `every` it pushes every call.
  cat > "$BATS_TEST_TMPDIR/bin/push-from-other" <<EOF
#!/usr/bin/env bash
set -e
if [ "\${4:-}" != every ]; then
  [ ! -e "$BATS_TEST_TMPDIR/pushed-from-other" ] || exit 0
  touch "$BATS_TEST_TMPDIR/pushed-from-other"
fi
if [ "\${4:-}" = every ]; then
  echo "\$2 \$RANDOM" > "$OTHER/\$1"
else
  echo "\$2" > "$OTHER/\$1"
fi
git -C "$OTHER" add -A
git -C "$OTHER" -c user.name=other -c user.email=other@example.com commit -q -m "\$3"
git -C "$OTHER" push -q origin main
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/push-from-other"
}

# Commits <file>=<content> in another clone and pushes it to main, as if
# someone merged while the action ran.
other_push() {
  echo "$2" > "$OTHER/$1"
  git -C "$OTHER" add -A
  git -C "$OTHER" -c user.name=other -c user.email=other@example.com commit -q -m "other: $1"
  git -C "$OTHER" push -q origin main
}

@test "push mode commits the bump on the base branch and tags it" {
  bump Patch

  [ "$status" -eq 0 ]
  [ "$(remote_file main VERSION)" = "1.2.4" ]
  [ "$(git --git-dir="$ORIGIN" log -1 --format=%s main)" = "Bump version from 1.2.3 to 1.2.4" ]
  [ "$(git --git-dir="$ORIGIN" rev-parse 'v1.2.4^{commit}')" = "$(git --git-dir="$ORIGIN" rev-parse main)" ]
  [ -z "$(git --git-dir="$ORIGIN" for-each-ref refs/heads | grep bump-version)" ]
  ! gh_called "pr create"
  assert_outputs version-bumped=true previous-version=1.2.3 new-version=1.2.4 \
    bump-type=patch pr-number= tag=v1.2.4
}

@test "push mode without create-tag doesn't tag" {
  export INPUT_CREATE_TAG=false

  bump Minor

  [ "$status" -eq 0 ]
  [ "$(remote_file main VERSION)" = "1.3.0" ]
  [ -z "$(git --git-dir="$ORIGIN" tag)" ]
  assert_outputs version-bumped=true tag=
}

@test "push mode starts from the latest base branch" {
  other_push NOTES "merged before the run"

  bump Patch

  [ "$status" -eq 0 ]
  [ "$(remote_file main NOTES)" = "merged before the run" ]
  [ "$(remote_file main VERSION)" = "1.2.4" ]
}

@test "push mode redoes the bump when the base moved during the run" {
  export INPUT_COMMAND="semver-bump.sh VERSION '' {bump} && push-from-other NOTES moved moved"

  bump Patch

  [ "$status" -eq 0 ]
  [ "$(remote_file main NOTES)" = "moved" ]
  [ "$(remote_file main VERSION)" = "1.2.4" ]
  [ "$(git --git-dir="$ORIGIN" log -1 --format=%s main~1)" = "moved" ]
  [ "$(git --git-dir="$ORIGIN" rev-parse 'v1.2.4^{commit}')" = "$(git --git-dir="$ORIGIN" rev-parse main)" ]
}

@test "push mode bumps again when another run pushed the same bump" {
  export INPUT_COMMAND="semver-bump.sh VERSION '' {bump} && push-from-other VERSION 1.2.4 'Bump version from 1.2.3 to 1.2.4'"

  bump Patch

  [ "$status" -eq 0 ]
  [ "$(remote_file main VERSION)" = "1.2.5" ]
  [ "$(git --git-dir="$ORIGIN" log -1 --format=%s main)" = "Bump version from 1.2.4 to 1.2.5" ]
  [ "$(git --git-dir="$ORIGIN" log -1 --format=%s main~1)" = "Bump version from 1.2.3 to 1.2.4" ]
  assert_outputs version-bumped=true previous-version=1.2.4 new-version=1.2.5 tag=v1.2.5
}

@test "push mode bumps from a version pushed during the run" {
  export INPUT_COMMAND="semver-bump.sh VERSION '' {bump} && push-from-other VERSION 9.9.9 'manual 9.9.9'"

  bump Patch

  [ "$status" -eq 0 ]
  [ "$(remote_file main VERSION)" = "9.9.10" ]
  [ "$(git --git-dir="$ORIGIN" log -1 --format=%s main~1)" = "manual 9.9.9" ]
  assert_outputs previous-version=9.9.9 new-version=9.9.10 tag=v9.9.10
}

@test "push mode fails at once when the push is refused and the base didn't move" {
  cat > "$ORIGIN/hooks/pre-receive" <<'HOOK'
#!/bin/sh
echo attempt >> "$(dirname "$0")/attempts"
echo "rejected by test hook" >&2
exit 1
HOOK
  chmod +x "$ORIGIN/hooks/pre-receive"

  bump Patch

  [ "$status" -ne 0 ]
  [ "$(wc -l < "$ORIGIN/hooks/attempts")" -eq 1 ]
  [[ "$output" == *"hasn't moved"* ]]
  assert_outputs version-bumped=false tag=
}

@test "push mode gives up after 3 attempts when the base keeps moving" {
  export INPUT_COMMAND="semver-bump.sh VERSION '' {bump} && push-from-other NOTES moved moved every"

  bump Patch

  [ "$status" -ne 0 ]
  [[ "$output" == *"after 3 attempts"* ]]
  [ "$(remote_file main VERSION)" = "1.2.3" ]
  [ -z "$(git --git-dir="$ORIGIN" tag)" ]
}

@test "push mode refuses to commit changes left by earlier steps" {
  echo stray > STRAY

  bump Patch

  [ "$status" -ne 0 ]
  [[ "$output" == *"uncommitted changes"* ]]
  [ "$(remote_file main VERSION)" = "1.2.3" ]
}

@test "a labelled PR closed without merging bumps nothing" {
  pr_event Patch
  jq '.pull_request.merged = false' "$GITHUB_EVENT_PATH" > "$BATS_TEST_TMPDIR/e.json"
  mv "$BATS_TEST_TMPDIR/e.json" "$GITHUB_EVENT_PATH"

  run bash "$ENTRYPOINT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"not merged"* ]]
  [ "$(remote_file main VERSION)" = "1.2.3" ]
  [ -z "$(git --git-dir="$ORIGIN" tag)" ]
  assert_outputs version-bumped=false
}

@test "an unknown mode fails" {
  export INPUT_MODE=merge

  bump Patch

  [ "$status" -ne 0 ]
  [[ "$output" == *"mode must be"* ]]
}
