#!/usr/bin/env bats
# mode: push commits the bump on the base branch instead of opening a PR.

setup() {
  load test_helper
  setup_repo
  export INPUT_MODE=push
  OTHER="$BATS_TEST_TMPDIR/other"
  git clone -q "$ORIGIN" "$OTHER"
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

@test "push mode rebases and retries when the base moved during the run" {
  export INPUT_COMMAND="semver-bump.sh VERSION '' {bump} && OTHER=$OTHER bash -c 'echo moved > \$OTHER/NOTES && git -C \$OTHER add -A && git -C \$OTHER -c user.name=o -c user.email=o@e commit -qm moved && git -C \$OTHER push -q origin main'"

  bump Patch

  [ "$status" -eq 0 ]
  [ "$(remote_file main NOTES)" = "moved" ]
  [ "$(remote_file main VERSION)" = "1.2.4" ]
  [ "$(git --git-dir="$ORIGIN" log -1 --format=%s main~1)" = "moved" ]
  [ "$(git --git-dir="$ORIGIN" rev-parse 'v1.2.4^{commit}')" = "$(git --git-dir="$ORIGIN" rev-parse main)" ]
}

@test "push mode fails clearly on a rebase conflict and never forces" {
  export INPUT_COMMAND="semver-bump.sh VERSION '' {bump} && OTHER=$OTHER bash -c 'echo 9.9.9 > \$OTHER/VERSION && git -C \$OTHER -c user.name=o -c user.email=o@e commit -qam conflict && git -C \$OTHER push -q origin main'"

  bump Patch

  [ "$status" -ne 0 ]
  [[ "$output" == *"conflicts with"* ]]
  [ "$(remote_file main VERSION)" = "9.9.9" ]
  [ ! -d .git/rebase-merge ] && [ ! -d .git/rebase-apply ]
  [ -z "$(git --git-dir="$ORIGIN" tag)" ]
  assert_outputs version-bumped=false
}

@test "push mode gives up after 3 rejected pushes" {
  cat > "$ORIGIN/hooks/pre-receive" <<'HOOK'
#!/bin/sh
echo attempt >> "$(dirname "$0")/attempts"
echo "rejected by test hook" >&2
exit 1
HOOK
  chmod +x "$ORIGIN/hooks/pre-receive"

  bump Patch

  [ "$status" -ne 0 ]
  [ "$(wc -l < "$ORIGIN/hooks/attempts")" -eq 3 ]
  [[ "$output" == *"after 3 attempts"* ]]
}

@test "an unknown mode fails" {
  export INPUT_MODE=merge

  bump Patch

  [ "$status" -ne 0 ]
  [[ "$output" == *"mode must be"* ]]
}
