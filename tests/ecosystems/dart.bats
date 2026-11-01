#!/usr/bin/env bats

# Recipe: Dart
#   command:  semver-bump.sh pubspec.yaml '^version:\s*'
#   validate: dart pub get >/dev/null && dart pub deps --json | jq -r '.packages[] | select(.kind == "root") | .version'

setup() {
  load ../test_helper
  require dart jq
  setup_repo dart
  export INPUT_COMMAND="semver-bump.sh pubspec.yaml '^version:\\s*'"
  export INPUT_VALIDATE="dart pub get >/dev/null && dart pub deps --json | jq -r '.packages[] | select(.kind == \"root\") | .version'"
}

@test "Dart: Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 pubspec.yaml
}

@test "Dart: Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 pubspec.yaml
}

@test "Dart: Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 pubspec.yaml
}
