#!/usr/bin/env bats

setup() {
  load test_helper
  setup_repo
}

@test "a Patch label bumps, pushes a branch and opens a PR" {
  bump Patch

  [ "$status" -eq 0 ]
  [ "$(remote_file "$(bump_branch 1.2.3 1.2.4)" VERSION)" = "1.2.4" ]
  [ "$(remote_file main VERSION)" = "1.2.3" ]
  gh_called "pr create"
  gh_called "--base main"
  gh_called "--head $(bump_branch 1.2.3 1.2.4)"
}

@test "major beats minor beats patch" {
  bump Patch Major Minor
  [ "$status" -eq 0 ]
  [ "$(remote_file "$(bump_branch 1.2.3 2.0.0)" VERSION)" = "2.0.0" ]
}

@test "a PR without labels doesn't bump" {
  bump
  [ "$status" -eq 0 ]
  ! git --git-dir="$ORIGIN" show-ref | grep -q bump-version
}

@test "a PR without a bump label doesn't bump" {
  bump documentation
  [ "$status" -eq 0 ]
  [[ "$output" == *"Version bump skipped"* ]]
  ! git --git-dir="$ORIGIN" show-ref | grep -q bump-version
}

@test "an existing PR is updated, not created again" {
  GH_PR_VIEW_EXIT=0 bump Minor
  [ "$status" -eq 0 ]
  [ "$(remote_file "$(bump_branch 1.2.3 1.3.0)" VERSION)" = "1.3.0" ]
  ! gh_called "pr create"
}

@test "command and validate are run by a shell, so quoting works" {
  printf 'name = "demo"\nversion = "1.2.3"\n' > config.toml
  git add config.toml && git -c user.name=dev -c user.email=dev@example.com commit -q -m config
  git push -q origin main
  export INPUT_COMMAND="semver-bump.sh config.toml 'version = \"'"
  export INPUT_VALIDATE="semver-bump.sh config.toml 'version = \"' current"

  bump Minor

  [ "$status" -eq 0 ]
  remote_file "$(bump_branch 1.2.3 1.3.0)" config.toml | grep -qF 'version = "1.3.0"'
}

@test "{bump} in the command is replaced by the bump type" {
  export INPUT_COMMAND="semver-bump.sh VERSION '' {bump} && echo bumped-{bump}"

  bump Major

  [ "$status" -eq 0 ]
  [[ "$output" == *"bumped-major"* ]]
  [ "$(remote_file "$(bump_branch 1.2.3 2.0.0)" VERSION)" = "2.0.0" ]
}

@test "the base branch is configurable" {
  git checkout -q -b develop
  echo '0.1.0' > VERSION
  git -c user.name=dev -c user.email=dev@example.com commit -q -am develop
  git push -q origin develop
  export INPUT_BASE_BRANCH=develop

  bump Patch

  [ "$status" -eq 0 ]
  [ "$(remote_file "$(bump_branch 0.1.0 0.1.1)" VERSION)" = "0.1.1" ]
  gh_called "--base develop"
}

@test "fails outside GitHub Actions" {
  unset GITHUB_EVENT_PATH
  run bash "$ENTRYPOINT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"GITHUB_EVENT_PATH"* ]]
}

@test "a failing validate fails the run, naming the command and its output" {
  export INPUT_VALIDATE="echo 'boom: no project here' >&2; exit 3"

  bump Patch

  [ "$status" -ne 0 ]
  [[ "$output" == *"validate command failed"* ]]
  [[ "$output" == *"exit 3"* ]]
  [[ "$output" == *"boom: no project here"* ]]
  ! gh_called "pr create"
}

@test "a validate that prints no version fails the run" {
  export INPUT_VALIDATE="echo 'version: dev'"

  bump Patch

  [ "$status" -ne 0 ]
  [[ "$output" == *"printed no MAJOR.MINOR.PATCH version"* ]]
  [[ "$output" == *"version: dev"* ]]
  ! gh_called "pr create"
}

@test "only the first version validate prints is used" {
  export INPUT_VALIDATE="echo 'demo 1.2.4 (built with tool 9.9.9)'"

  bump Patch

  [ "$status" -eq 0 ]
  [ "$(remote_file "$(bump_branch 1.2.3 1.2.4)" VERSION)" = "1.2.4" ]
}

@test "a failing command fails the run" {
  export INPUT_COMMAND="false"

  bump Patch

  [ "$status" -ne 0 ]
  ! gh_called "pr create"
}

@test "a missing required input fails with its name" {
  unset INPUT_COMMAND

  bump Patch

  [ "$status" -ne 0 ]
  [[ "$output" == *"INPUT_COMMAND"* ]]
}

@test "works without GITHUB_ACTOR, just without an assignee" {
  unset GITHUB_ACTOR

  bump Patch

  [ "$status" -eq 0 ]
  gh_called "pr create"
  ! gh_called "--assignee"
}

@test "explains the repo setting when Actions may not create PRs" {
  export GH_PR_CREATE_EXIT=1
  export GH_PR_CREATE_STDERR="pull request create failed: GraphQL: GitHub Actions is not permitted to create or approve pull requests (createPullRequest)"

  bump Patch

  [ "$status" -ne 0 ]
  [[ "$output" == *"Allow GitHub Actions to create and approve pull requests"* ]]
}

@test "versions in validate's stderr are ignored" {
  export INPUT_VALIDATE="echo 'WARN: requires node >=18.0.0' >&2; cat VERSION"

  bump Patch

  [ "$status" -eq 0 ]
  [ "$(remote_file "$(bump_branch 1.2.3 1.2.4)" VERSION)" = "1.2.4" ]
}
