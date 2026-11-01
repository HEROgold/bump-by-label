#!/usr/bin/env bats

# Recipe: Java (Gradle)
#   command:  semver-bump.sh gradle.properties '^version='
#   validate: gradle -q printVersion

setup() {
  load ../test_helper
  require gradle
  setup_repo gradle
  export INPUT_COMMAND="semver-bump.sh gradle.properties '^version='"
  export INPUT_VALIDATE='gradle -q printVersion'
}

@test "Java (Gradle): Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 gradle.properties
}

@test "Java (Gradle): Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 gradle.properties
}

@test "Java (Gradle): Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 gradle.properties
}
