#!/usr/bin/env bats

# Recipe: Python (Poetry)
#   command:  poetry version
#   validate: poetry version -s

setup() {
  load ../test_helper
  require poetry
  setup_repo python-poetry
  export INPUT_COMMAND='poetry version'
  export INPUT_VALIDATE='poetry version -s'
}

@test "Python (Poetry): Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 pyproject.toml
}

@test "Python (Poetry): Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 pyproject.toml
}

@test "Python (Poetry): Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 pyproject.toml
}
