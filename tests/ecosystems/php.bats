#!/usr/bin/env bats

# Recipe: PHP
#   command:  semver-bump.sh composer.json '"version":\s*"'
#   validate: jq -r .version composer.json

setup() {
  load ../test_helper
  require jq composer
  setup_repo php
  export INPUT_COMMAND="semver-bump.sh composer.json '\"version\":\\s*\"'"
  export INPUT_VALIDATE='jq -r .version composer.json'
}

@test "PHP: Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 composer.json
}

@test "PHP: Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 composer.json
}

@test "PHP: Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 composer.json
}

@test "PHP: composer.json is still valid after a bump" {
  bump Patch
  [ "$status" -eq 0 ]
  git checkout -q "$(bump_branch 1.2.3 1.2.4)"
  composer validate --no-check-publish --no-check-lock
}
