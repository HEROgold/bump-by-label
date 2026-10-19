#!/usr/bin/env bats

# Recipe: Python (uv)
#   command:  uv version --no-sync --bump
#   validate: uv version --short

setup() {
  load ../test_helper
  require uv
  setup_repo python-uv
  export INPUT_COMMAND='uv version --no-sync --bump'
  export INPUT_VALIDATE='uv version --short'
}

@test "Python (uv): Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 pyproject.toml uv.lock
}

@test "Python (uv): Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 pyproject.toml uv.lock
}

@test "Python (uv): Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 pyproject.toml uv.lock
}
