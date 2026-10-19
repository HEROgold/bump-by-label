#!/usr/bin/env bats

# Recipe: C/C++ (CMake)
#   command:  semver-bump.sh CMakeLists.txt 'project\(demo VERSION '
#   validate: semver-bump.sh CMakeLists.txt 'project\(demo VERSION ' current

setup() {
  load ../test_helper
  require cmake
  setup_repo cmake
  export INPUT_COMMAND="semver-bump.sh CMakeLists.txt 'project\\(demo VERSION '"
  export INPUT_VALIDATE="semver-bump.sh CMakeLists.txt 'project\\(demo VERSION ' current"
}

@test "C/C++ (CMake): Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 CMakeLists.txt
}

@test "C/C++ (CMake): Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 CMakeLists.txt
}

@test "C/C++ (CMake): Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 CMakeLists.txt
}

@test "C/C++ (CMake): CMake configures with the new version" {
  require make
  bump Minor
  [ "$status" -eq 0 ]
  git checkout -q "$(bump_branch 1.2.3 1.3.0)"
  cmake -S . -B "$BATS_TEST_TMPDIR/build" | grep -qF "demo version: 1.3.0"
}
