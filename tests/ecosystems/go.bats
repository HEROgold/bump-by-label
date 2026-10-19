#!/usr/bin/env bats

# Recipe: Go
#   command:  semver-bump.sh VERSION ''
#   validate: cat VERSION

setup() {
  load ../test_helper
  require go
  setup_repo go
  export INPUT_COMMAND="semver-bump.sh VERSION ''"
  export INPUT_VALIDATE='cat VERSION'
}

@test "Go: Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 VERSION
}

@test "Go: Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 VERSION
}

@test "Go: Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 VERSION
}

@test "Go: the embedded version follows the VERSION file" {
  bump Minor
  [ "$status" -eq 0 ]
  git checkout -q "$(bump_branch 1.2.3 1.3.0)"
  [ "$(go run .)" = "1.3.0" ]
}
