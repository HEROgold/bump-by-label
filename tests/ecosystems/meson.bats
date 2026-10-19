#!/usr/bin/env bats

# Recipe: C/C++ (Meson)
#   command:  semver-bump.sh meson.build "version: '"
#   validate: meson introspect --projectinfo meson.build | jq -r .version

setup() {
  load ../test_helper
  require meson jq
  setup_repo meson
  export INPUT_COMMAND="semver-bump.sh meson.build \"version: '\""
  export INPUT_VALIDATE='meson introspect --projectinfo meson.build | jq -r .version'
}

@test "C/C++ (Meson): Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 meson.build
}

@test "C/C++ (Meson): Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 meson.build
}

@test "C/C++ (Meson): Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 meson.build
}
