#!/usr/bin/env bats

# Recipe: JavaScript
#   command:  npm version --no-git-tag-version
#   validate: node -p "require('./package.json').version"

setup() {
  load ../test_helper
  require node npm
  setup_repo javascript
  export INPUT_COMMAND='npm version --no-git-tag-version'
  export INPUT_VALIDATE="node -p \"require('./package.json').version\""
}

@test "JavaScript: Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 package.json package-lock.json
}

@test "JavaScript: Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 package.json package-lock.json
}

@test "JavaScript: Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 package.json package-lock.json
}
