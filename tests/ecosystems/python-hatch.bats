#!/usr/bin/env bats

# Recipe: Python (Hatch)
#   command:  hatch version
#   validate: hatch version

setup() {
  load ../test_helper
  require hatch
  setup_repo python-hatch
  export INPUT_COMMAND='hatch version'
  export INPUT_VALIDATE='hatch version'
}

@test "Python (Hatch): Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 src/demo/__about__.py
}

@test "Python (Hatch): Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 src/demo/__about__.py
}

@test "Python (Hatch): Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 src/demo/__about__.py
}
