#!/usr/bin/env bats

# Recipe: Ruby
#   command:  semver-bump.sh demo.gemspec 'spec\.version\s*=\s*"'
#   validate: ruby -e 'puts Gem::Specification.load("demo.gemspec").version'

setup() {
  load ../test_helper
  require ruby
  setup_repo ruby
  export INPUT_COMMAND="semver-bump.sh demo.gemspec 'spec\\.version\\s*=\\s*\"'"
  export INPUT_VALIDATE="ruby -e 'puts Gem::Specification.load(\"demo.gemspec\").version'"
}

@test "Ruby: Patch bumps 1.2.3 to 1.2.4" {
  bump Patch
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.2.4 demo.gemspec
}

@test "Ruby: Minor bumps 1.2.3 to 1.3.0" {
  bump Minor
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 1.3.0 demo.gemspec
}

@test "Ruby: Major bumps 1.2.3 to 2.0.0" {
  bump Major
  [ "$status" -eq 0 ]
  assert_bumped 1.2.3 2.0.0 demo.gemspec
}
